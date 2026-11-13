"""Modèles linéaires généralisés (GLM) : Poisson, quasi-Poisson, binomiale négative, Gamma, logistique.

Ajustement par moindres carrés repondérés itératifs (IRLS), comme `glm()` de R ; la binomiale
négative (NB2) estime son paramètre θ par maximum de vraisemblance en alternance (comme
`MASS::glm.nb`). Écrit avec NumPy / SciPy pour ne pas alourdir l'exécutable.

Usages halieutiques typiques : standardisation de CPUE (effort en décalage « offset »), comptages
(nombre d'individus, de marées), présence / absence d'une espèce, captures positives (Gamma).
"""

from __future__ import annotations

import math

import numpy as np
from scipy import optimize
from scipy import stats as st
from scipy.special import expit, gammaln

from .engine.sql import RecipeError

FAMILIES = {
    "poisson": "GLM de Poisson (lien log)",
    "quasi_poisson": "GLM quasi-Poisson (lien log, surdispersion estimée)",
    "binomiale_negative": "GLM binomial négatif (lien log)",
    "gamma": "GLM Gamma (lien log)",
    "logistique": "Régression logistique (GLM binomial, lien logit)",
}
LOGIT = {"logistique"}
ESTIMATED_PHI = {"quasi_poisson", "gamma"}  # dispersion estimée : tests F / t


# --------------------------------------------------------------------------- familles


def _variance(fam, mu, theta):
    if fam in ("poisson", "quasi_poisson"):
        return mu
    if fam == "binomiale_negative":
        return mu + mu ** 2 / theta
    if fam == "gamma":
        return mu ** 2
    return mu * (1 - mu)


def _xlogy(y, x):
    with np.errstate(divide="ignore", invalid="ignore"):
        return np.where(y > 0, y * np.log(np.where(y > 0, y, 1) / x), 0.0)


def deviance_units(fam, y, mu, theta=None):
    if fam in ("poisson", "quasi_poisson"):
        return 2 * (_xlogy(y, mu) - (y - mu))
    if fam == "binomiale_negative":
        return 2 * (_xlogy(y, mu) - (y + theta) * np.log((y + theta) / (mu + theta)))
    if fam == "gamma":
        return 2 * (-np.log(y / mu) + (y - mu) / mu)
    return 2 * (_xlogy(y, mu) + _xlogy(1 - y, 1 - mu))


def loglik(fam, y, mu, theta=None, phi=1.0) -> float:
    if fam in ("poisson", "quasi_poisson"):
        return float(np.sum(st.poisson.logpmf(y, mu)))
    if fam == "binomiale_negative":
        return float(np.sum(gammaln(y + theta) - gammaln(theta) - gammaln(y + 1)
                            + theta * np.log(theta / (theta + mu)) + y * np.log(mu / (theta + mu))))
    if fam == "gamma":
        k = 1 / phi
        return float(np.sum(st.gamma.logpdf(y, a=k, scale=mu / k)))
    return float(np.sum(y * np.log(mu) + (1 - y) * np.log1p(-mu)))


def _linkinv(fam, eta):
    if fam in LOGIT:
        mu = expit(eta)
        return np.clip(mu, 1e-10, 1 - 1e-10), mu * (1 - mu)
    mu = np.exp(np.clip(eta, -30, 30))
    return mu, mu


def irls(X, y, fam, offset=None, theta=None, maxit=100, tol=1e-9):
    """Renvoie (beta, mu, XtWX inverse, converge)."""
    n, p = X.shape
    off = np.zeros(n) if offset is None else offset
    if fam in LOGIT:
        mu = (y + 0.5) / 2
        eta = np.log(mu / (1 - mu))
    else:
        mu = (y + y.mean()) / 2 if fam != "gamma" else y.copy()
        mu = np.maximum(mu, 1e-3)
        eta = np.log(mu)
    beta = np.zeros(p)
    dev_old = np.inf
    converged = False
    for _ in range(maxit):
        _, dmu = _linkinv(fam, eta)
        dmu = np.maximum(dmu, 1e-10)
        var = np.maximum(_variance(fam, mu, theta), 1e-10)
        w = dmu ** 2 / var
        z = eta - off + (y - mu) / dmu
        sw = np.sqrt(w)
        new, *_ = np.linalg.lstsq(X * sw[:, None], z * sw, rcond=None)
        # pas réduit si la déviance augmente (rare, données extrêmes)
        for _h in range(30):
            eta_new = X @ new + off
            mu_new, _ = _linkinv(fam, eta_new)
            dev = float(np.sum(deviance_units(fam, y, mu_new, theta)))
            if math.isfinite(dev) and dev <= dev_old * (1 + 1e-7) + 1e-9:
                break
            new = (new + beta) / 2
        beta, eta, mu = new, eta_new, mu_new
        if abs(dev - dev_old) / (abs(dev) + 0.1) < tol:
            converged = True
            break
        dev_old = dev
    _, dmu = _linkinv(fam, eta)
    w = np.maximum(dmu, 1e-10) ** 2 / np.maximum(_variance(fam, mu, theta), 1e-10)
    try:
        inv = np.linalg.inv((X * w[:, None]).T @ X)
    except np.linalg.LinAlgError as e:
        raise RecipeError("Facteurs redondants (colinéarité parfaite ou modalité sans observation) : retirez-en un.") from e
    return beta, mu, inv, converged


def _theta_ml(y, mu) -> float:
    f = lambda lt: -loglik("binomiale_negative", y, mu, math.exp(lt))  # noqa: E731
    r = optimize.minimize_scalar(f, bounds=(-8, 12), method="bounded")
    return math.exp(r.x)


def fit(X, y, fam, offset=None):
    """Ajustement complet ; renvoie un dict (beta, cov, mu, deviance, phi, theta, ll, conv)."""
    theta = None
    if fam == "binomiale_negative":
        _, mu, _, _ = irls(X, y, "poisson", offset)
        theta = _theta_ml(y, mu)
        for _ in range(25):
            beta, mu, inv, conv = irls(X, y, fam, offset, theta)
            t2 = _theta_ml(y, mu)
            if abs(math.log(t2) - math.log(theta)) < 1e-6:
                theta = t2
                break
            theta = t2
    beta, mu, inv, conv = irls(X, y, fam, offset, theta)
    n, p = X.shape
    dev = float(np.sum(deviance_units(fam, y, mu, theta)))
    pearson = float(np.sum((y - mu) ** 2 / np.maximum(_variance(fam, mu, theta), 1e-12)))
    disp = pearson / max(n - p, 1)
    phi = disp if fam in ESTIMATED_PHI else 1.0
    ll = loglik(fam, y, mu, theta, phi) if fam != "quasi_poisson" else None
    k = p + (1 if fam in ("binomiale_negative", "gamma") else 0)
    return {"beta": beta, "cov": inv * phi, "mu": mu, "dev": dev, "phi": phi, "disp": disp, "theta": theta,
            "ll": ll, "aic": (-2 * ll + 2 * k) if ll is not None else None, "conv": conv, "n": n, "p": p}


def quantile_residuals(fam, y, mu, theta=None, phi=1.0, seed=0) -> np.ndarray:
    """Résidus quantiles randomisés (Dunn & Smyth 1996) : ~ N(0,1) si le modèle est adapté."""
    rng = np.random.default_rng(seed)
    if fam in ("poisson", "quasi_poisson"):
        lo, hi = st.poisson.cdf(y - 1, mu), st.poisson.cdf(y, mu)
    elif fam == "binomiale_negative":
        pr = theta / (theta + mu)
        lo, hi = st.nbinom.cdf(y - 1, theta, pr), st.nbinom.cdf(y, theta, pr)
    elif fam == "gamma":
        k = 1 / phi
        u = st.gamma.cdf(y, a=k, scale=mu / k)
        return st.norm.ppf(np.clip(u, 1e-12, 1 - 1e-12))
    else:
        lo, hi = np.where(y > 0, 1 - mu, 0.0), np.where(y > 0, 1.0, 1 - mu)
    u = lo + rng.random(len(y)) * (hi - lo)
    return st.norm.ppf(np.clip(u, 1e-12, 1 - 1e-12))


def expected_zeros(fam, mu, theta=None) -> float:
    if fam in ("poisson", "quasi_poisson"):
        return float(np.sum(np.exp(-mu)))
    if fam == "binomiale_negative":
        return float(np.sum((theta / (theta + mu)) ** theta))
    return float("nan")
