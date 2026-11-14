"""Figures SVG des fiches méthode (sans dépendance : pas de matplotlib dans l'exécutable).

Chaque fonction renvoie une chaîne SVG autonome (640 × 360 px par défaut), lisible à l'écran et à
l'impression : axes gradués, nombres au format français, palette sobre et accessible.
"""

from __future__ import annotations

import math
from html import escape

import numpy as np

W, H = 640, 360
M = {"l": 64, "r": 20, "t": 20, "b": 52}
INK, MUTED, GRID, AXIS = "#1c2430", "#5f6b7a", "#e6e9ee", "#9aa4b0"
BLUE, ORANGE, RED = "#2a78d6", "#eb6834", "#c2410c"
PALETTE = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
FONT = "'IBM Plex Sans', 'Segoe UI', Arial, sans-serif"


def fmt(v: float, nd: int | None = None) -> str:
    if v is None or not math.isfinite(v):
        return ""
    if nd is None:
        a = abs(v)
        nd = 0 if a >= 100 or float(v).is_integer() else 1 if a >= 10 else 2 if a >= 0.1 else 3
    s = f"{v:,.{nd}f}".replace(",", " ").replace(".", ",")
    return "−" + s[1:] if s.startswith("-") else s


def ticks(lo: float, hi: float, n: int = 5) -> list[float]:
    if not (math.isfinite(lo) and math.isfinite(hi)):
        return []
    if hi == lo:
        hi = lo + 1
    raw = (hi - lo) / n
    mag = 10 ** math.floor(math.log10(raw))
    step = min((s * mag for s in (1, 2, 2.5, 5, 10) if s * mag >= raw), default=10 * mag)
    start = math.ceil(lo / step) * step
    out, v = [], start
    while v <= hi + step * 1e-9:
        out.append(round(v, 12))
        v += step
    return out


class _Plot:
    def __init__(self, xlo, xhi, ylo, yhi, w=W, h=H, m=None):
        self.w, self.h, self.m = w, h, dict(M, **(m or {}))
        pad_y = (yhi - ylo) * 0.05 or 1
        self.ylo, self.yhi = ylo - pad_y, yhi + pad_y
        self.xlo, self.xhi = xlo, xhi
        self.parts: list[str] = []

    def X(self, v):
        m = self.m
        return m["l"] + (v - self.xlo) / ((self.xhi - self.xlo) or 1) * (self.w - m["l"] - m["r"])

    def Y(self, v):
        m = self.m
        return self.h - m["b"] - (v - self.ylo) / ((self.yhi - self.ylo) or 1) * (self.h - m["t"] - m["b"])

    def add(self, s: str):
        self.parts.append(s)

    def yaxis(self, label: str):
        m = self.m
        for t in ticks(self.ylo, self.yhi):
            y = self.Y(t)
            self.add(f'<line x1="{m["l"]}" x2="{self.w - m["r"]}" y1="{y:.1f}" y2="{y:.1f}" stroke="{GRID}"/>')
            self.add(f'<text x="{m["l"] - 6}" y="{y + 4:.1f}" text-anchor="end" fill="{MUTED}" font-size="11">{fmt(t)}</text>')
        cy = (m["t"] + self.h - m["b"]) / 2
        self.add(f'<text transform="translate(14,{cy:.0f}) rotate(-90)" text-anchor="middle" fill="{INK}" font-size="12">'
                 f'{escape(label)}</text>')

    def xaxis_num(self, label: str):
        m = self.m
        for t in ticks(self.xlo, self.xhi):
            x = self.X(t)
            self.add(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{m["t"]}" y2="{self.h - m["b"]}" stroke="{GRID}"/>')
            self.add(f'<text x="{x:.1f}" y="{self.h - m["b"] + 16}" text-anchor="middle" fill="{MUTED}" font-size="11">{fmt(t)}</text>')
        self.xlabel(label)

    def xlabel(self, label: str):
        m = self.m
        cx = (m["l"] + self.w - m["r"]) / 2
        self.add(f'<text x="{cx:.0f}" y="{self.h - 10}" text-anchor="middle" fill="{INK}" font-size="12">{escape(label)}</text>')

    def frame(self):
        m = self.m
        self.add(f'<line x1="{m["l"]}" x2="{self.w - m["r"]}" y1="{self.h - m["b"]}" y2="{self.h - m["b"]}" stroke="{AXIS}"/>')

    def svg(self, title: str = "") -> str:
        t = f"<title>{escape(title)}</title>" if title else ""
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
                f'font-family="{FONT}" role="img">{t}<rect width="100%" height="100%" fill="#fff"/>' + "".join(self.parts) + "</svg>")


def _sample(a: np.ndarray, n: int = 4000, seed: int = 0) -> np.ndarray:
    a = np.asarray(a, dtype=float)
    a = a[np.isfinite(a)]
    if len(a) <= n:
        return a
    return np.random.default_rng(seed).choice(a, n, replace=False)


def _label(s: str, n: int = 14) -> str:
    s = str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


# --------------------------------------------------------------------------- figures


def boxplot(groups: list[str], values: list[np.ndarray], yname: str, xname: str) -> str:
    """Boîtes à moustaches (Tukey 1977) avec points individuels si les groupes sont petits."""
    vals = [np.asarray(v, dtype=float)[np.isfinite(np.asarray(v, dtype=float))] for v in values]
    allv = np.concatenate([v for v in vals if len(v)]) if any(len(v) for v in vals) else np.array([0.0, 1.0])
    k = len(groups)
    p = _Plot(0, k, float(allv.min()), float(allv.max()), m={"b": 64 if k > 6 else 52})
    p.yaxis(yname)
    p.frame()
    bw = min(56, (p.w - p.m["l"] - p.m["r"]) / k * 0.55)
    rng = np.random.default_rng(1)
    for i, (g, v) in enumerate(zip(groups, vals)):
        cx = p.X(i + 0.5)
        col = PALETTE[i % len(PALETTE)]
        if len(v) == 0:
            continue
        q1, med, q3 = np.percentile(v, [25, 50, 75])
        iqr = q3 - q1
        lo = v[v >= q1 - 1.5 * iqr].min()
        hi = v[v <= q3 + 1.5 * iqr].max()
        p.add(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{p.Y(lo):.1f}" y2="{p.Y(q1):.1f}" stroke="{INK}"/>')
        p.add(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{p.Y(q3):.1f}" y2="{p.Y(hi):.1f}" stroke="{INK}"/>')
        for w_ in (lo, hi):
            p.add(f'<line x1="{cx - bw / 4:.1f}" x2="{cx + bw / 4:.1f}" y1="{p.Y(w_):.1f}" y2="{p.Y(w_):.1f}" stroke="{INK}"/>')
        p.add(f'<rect x="{cx - bw / 2:.1f}" y="{p.Y(q3):.1f}" width="{bw:.1f}" height="{max(p.Y(q1) - p.Y(q3), 1):.1f}" '
              f'fill="{col}" fill-opacity="0.18" stroke="{col}" stroke-width="1.5"/>')
        p.add(f'<line x1="{cx - bw / 2:.1f}" x2="{cx + bw / 2:.1f}" y1="{p.Y(med):.1f}" y2="{p.Y(med):.1f}" stroke="{col}" stroke-width="2.5"/>')
        mean = float(v.mean())
        p.add(f'<path d="M{cx - 4:.1f},{p.Y(mean):.1f} l4,-4 l4,4 l-4,4 z" fill="#fff" stroke="{INK}"/>')
        pts = v if len(v) <= 60 else v[(v < q1 - 1.5 * iqr) | (v > q3 + 1.5 * iqr)]
        for y in _sample(pts, 300):
            jx = cx + (rng.random() - 0.5) * bw * (0.6 if len(v) <= 60 else 0.2)
            p.add(f'<circle cx="{jx:.1f}" cy="{p.Y(y):.1f}" r="2.2" fill="{col}" fill-opacity="0.55"/>')
        rot = k > 6
        lab = escape(_label(g, 12 if rot else 16))
        ly = p.h - p.m["b"] + 16
        if rot:
            p.add(f'<text transform="translate({cx:.1f},{ly}) rotate(-30)" text-anchor="end" fill="{MUTED}" font-size="11">{lab}</text>')
        else:
            p.add(f'<text x="{cx:.1f}" y="{ly}" text-anchor="middle" fill="{MUTED}" font-size="11">{lab}</text>')
            p.add(f'<text x="{cx:.1f}" y="{ly + 13}" text-anchor="middle" fill="{AXIS}" font-size="10">n = {len(v)}</text>')
    if k <= 6:
        p.m["b"] += 0
    else:
        p.xlabel(xname)
    return p.svg(f"{yname} selon {xname}")


def scatter(x, y, xname: str, yname: str, line: tuple[float, float] | None = None, hline: float | None = None,
            smooth: bool = False) -> str:
    x, y = np.asarray(x, dtype=float), np.asarray(y, dtype=float)
    ok = np.isfinite(x) & np.isfinite(y)
    x, y = x[ok], y[ok]
    if len(x) == 0:
        x, y = np.array([0.0, 1.0]), np.array([0.0, 1.0])
    idx = np.random.default_rng(0).choice(len(x), min(len(x), 3000), replace=False)
    xs, ys = x[idx], y[idx]
    padx = (x.max() - x.min()) * 0.03 or 1
    p = _Plot(float(x.min() - padx), float(x.max() + padx), float(y.min()), float(y.max()))
    p.yaxis(yname)
    p.xaxis_num(xname)
    p.frame()
    op = 0.55 if len(xs) < 500 else 0.3
    p.add("".join(f'<circle cx="{p.X(a):.1f}" cy="{p.Y(b):.1f}" r="2.6" fill="{BLUE}" fill-opacity="{op}"/>' for a, b in zip(xs, ys)))
    if hline is not None:
        p.add(f'<line x1="{p.m["l"]}" x2="{p.w - p.m["r"]}" y1="{p.Y(hline):.1f}" y2="{p.Y(hline):.1f}" stroke="{INK}" '
              f'stroke-dasharray="4 3"/>')
    if line is not None:
        a, b = line
        x0, x1 = p.xlo, p.xhi
        p.add(f'<line x1="{p.X(x0):.1f}" x2="{p.X(x1):.1f}" y1="{p.Y(a + b * x0):.1f}" y2="{p.Y(a + b * x1):.1f}" '
              f'stroke="{ORANGE}" stroke-width="2"/>')
    if smooth and len(x) >= 20:
        # tendance par moyennes mobiles sur déciles de x : repère une forme dans les résidus
        order = np.argsort(x)
        bins = np.array_split(order, min(12, len(x) // 10))
        pts = [(float(x[b].mean()), float(y[b].mean())) for b in bins if len(b)]
        d = " ".join(f"{'M' if i == 0 else 'L'}{p.X(a):.1f},{p.Y(b):.1f}" for i, (a, b) in enumerate(pts))
        p.add(f'<path d="{d}" fill="none" stroke="{ORANGE}" stroke-width="2"/>')
    return p.svg(f"{yname} en fonction de {xname}")


def qqplot(resid, title: str = "Résidus") -> str:
    """Diagramme quantile-quantile normal : points alignés sur la diagonale = distribution normale."""
    from scipy import stats as st

    r = np.sort(_sample(resid, 2000))
    n = len(r)
    if n < 3:
        r, n = np.array([-1.0, 0.0, 1.0]), 3
    z = st.norm.ppf((np.arange(1, n + 1) - 0.5) / n)
    rs = (r - r.mean()) / (r.std(ddof=1) or 1)
    lo, hi = float(min(z.min(), rs.min())), float(max(z.max(), rs.max()))
    p = _Plot(lo, hi, lo, hi)
    p.yaxis(f"{title} (centrés réduits)")
    p.xaxis_num("Quantiles théoriques de la loi normale")
    p.frame()
    p.add(f'<line x1="{p.X(lo):.1f}" x2="{p.X(hi):.1f}" y1="{p.Y(lo):.1f}" y2="{p.Y(hi):.1f}" stroke="{ORANGE}" stroke-width="1.5"/>')
    p.add("".join(f'<circle cx="{p.X(a):.1f}" cy="{p.Y(b):.1f}" r="2.4" fill="{BLUE}" fill-opacity="0.5"/>' for a, b in zip(z, rs)))
    return p.svg("Diagramme quantile-quantile")


def bars(labels: list[str], values: list[float], yname: str, xname: str = "", lo: list[float] | None = None,
         hi: list[float] | None = None, color: str = BLUE, ref: float | None = None) -> str:
    """Barres verticales (avec intervalles de confiance si fournis) ; l'axe part de zéro."""
    vals = [float(v) if v is not None and math.isfinite(float(v)) else 0.0 for v in values]
    top = max(vals + (hi or [0])) if vals else 1
    k = max(len(labels), 1)
    p = _Plot(0, k, 0, top or 1, m={"b": 64 if k > 8 else 52})
    p.ylo = 0
    p.yaxis(yname)
    p.frame()
    bw = (p.w - p.m["l"] - p.m["r"]) / k * 0.62
    for i, (lab, v) in enumerate(zip(labels, vals)):
        cx = p.X(i + 0.5)
        p.add(f'<rect x="{cx - bw / 2:.1f}" y="{p.Y(v):.1f}" width="{bw:.1f}" height="{max(p.Y(0) - p.Y(v), 0):.1f}" fill="{color}" '
              f'fill-opacity="0.85"/>')
        if lo is not None and hi is not None:
            a, b = p.Y(lo[i]), p.Y(hi[i])
            p.add(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{a:.1f}" y2="{b:.1f}" stroke="{INK}" stroke-width="1.3"/>')
            for yy in (a, b):
                p.add(f'<line x1="{cx - 5:.1f}" x2="{cx + 5:.1f}" y1="{yy:.1f}" y2="{yy:.1f}" stroke="{INK}" stroke-width="1.3"/>')
        ly = p.h - p.m["b"] + 16
        if k > 8:
            p.add(f'<text transform="translate({cx:.1f},{ly}) rotate(-35)" text-anchor="end" fill="{MUTED}" font-size="11">'
                  f'{escape(_label(lab, 12))}</text>')
        else:
            p.add(f'<text x="{cx:.1f}" y="{ly}" text-anchor="middle" fill="{MUTED}" font-size="11">{escape(_label(lab, 16))}</text>')
    if ref is not None:
        p.add(f'<line x1="{p.m["l"]}" x2="{p.w - p.m["r"]}" y1="{p.Y(ref):.1f}" y2="{p.Y(ref):.1f}" stroke="{INK}" stroke-dasharray="4 3"/>')
    if xname and k <= 8:
        p.xlabel(xname)
    return p.svg(yname)


def hbars(labels: list[str], values: list[float], xname: str, maxv: float | None = None, color: str = BLUE,
          suffix: str = "") -> str:
    """Barres horizontales (ex. taux de remplissage par colonne)."""
    n = max(len(labels), 1)
    h = max(120, 26 + n * 20 + 40)
    maxv = maxv or (max(values) if values else 1) or 1
    lw = 170
    parts = []
    for i, (lab, v) in enumerate(zip(labels, values)):
        y = 20 + i * 20
        w = (W - lw - 70) * (v / maxv if maxv else 0)
        parts.append(f'<text x="{lw - 8}" y="{y + 13}" text-anchor="end" fill="{INK}" font-size="11">{escape(_label(lab, 26))}</text>')
        parts.append(f'<rect x="{lw}" y="{y + 3}" width="{W - lw - 70}" height="13" fill="{GRID}"/>')
        parts.append(f'<rect x="{lw}" y="{y + 3}" width="{max(w, 0):.1f}" height="13" fill="{color}"/>')
        parts.append(f'<text x="{W - 64}" y="{y + 13}" fill="{MUTED}" font-size="11">{fmt(v)}{suffix}</text>')
    parts.append(f'<text x="{lw}" y="{h - 10}" fill="{INK}" font-size="12">{escape(xname)}</text>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" width="{W}" height="{h}" font-family="{FONT}" '
            f'role="img"><rect width="100%" height="100%" fill="#fff"/>' + "".join(parts) + "</svg>")


def stacked(rows: list[str], cols: list[str], props: np.ndarray, xname: str, legend: str) -> str:
    """Barres empilées à 100 % : répartition de la seconde variable dans chaque modalité de la première."""
    k = len(rows)
    h = max(160, 40 + k * 26 + 70)
    lw = 140
    parts = []
    for i, r in enumerate(rows):
        y = 20 + i * 26
        x = lw
        parts.append(f'<text x="{lw - 8}" y="{y + 15}" text-anchor="end" fill="{INK}" font-size="11">{escape(_label(r, 20))}</text>')
        for j in range(len(cols)):
            w = (W - lw - 20) * float(props[i, j])
            parts.append(f'<rect x="{x:.1f}" y="{y + 2}" width="{max(w, 0):.1f}" height="18" fill="{PALETTE[j % len(PALETTE)]}" '
                         f'stroke="#fff" stroke-width="0.5"/>')
            if w > 30:
                parts.append(f'<text x="{x + w / 2:.1f}" y="{y + 15}" text-anchor="middle" fill="#fff" font-size="10">'
                             f'{fmt(100 * float(props[i, j]), 0)} %</text>')
            x += w
    ly = 20 + k * 26 + 14
    x = lw
    parts.append(f'<text x="{lw - 8}" y="{ly + 10}" text-anchor="end" fill="{MUTED}" font-size="11">{escape(_label(legend, 20))}</text>')
    for j, c in enumerate(cols[:10]):
        parts.append(f'<rect x="{x}" y="{ly + 1}" width="11" height="11" fill="{PALETTE[j % len(PALETTE)]}"/>')
        parts.append(f'<text x="{x + 15}" y="{ly + 10}" fill="{INK}" font-size="11">{escape(_label(c, 12))}</text>')
        x += 24 + 7 * min(len(str(c)), 12)
        if x > W - 80:
            break
    parts.append(f'<text x="{lw}" y="{h - 8}" fill="{INK}" font-size="12">{escape(xname)}</text>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" width="{W}" height="{h}" font-family="{FONT}" '
            f'role="img"><rect width="100%" height="100%" fill="#fff"/>' + "".join(parts) + "</svg>")


def histogram(v, xname: str, bins: int = 30) -> str:
    v = _sample(v, 200000)
    if len(v) == 0:
        v = np.array([0.0])
    counts, edges = np.histogram(v, bins=min(bins, max(5, int(math.sqrt(len(v))))))
    p = _Plot(float(edges[0]), float(edges[-1]), 0, float(counts.max() or 1))
    p.ylo = 0
    p.yaxis("Effectif")
    p.xaxis_num(xname)
    p.frame()
    for c, a, b in zip(counts, edges[:-1], edges[1:]):
        p.add(f'<rect x="{p.X(a):.1f}" y="{p.Y(c):.1f}" width="{max(p.X(b) - p.X(a) - 1, 0.5):.1f}" '
              f'height="{p.Y(0) - p.Y(c):.1f}" fill="{BLUE}" fill-opacity="0.8"/>')
    return p.svg(f"Distribution de {xname}")
