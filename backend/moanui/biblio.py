"""Références bibliographiques citées par les fiches méthode et le guide.

Une seule source de vérité : chaque fiche cite des clés, la liste « Références » est construite à partir
d'ici (format auteur-date, à la française). Ne citer que des références vérifiées.
"""

from __future__ import annotations

REFS: dict[str, str] = {
    # ------------------------------------------------------------------ données, traçabilité
    "broman2018": "Broman K. W., Woo K. H. (2018). Data organization in spreadsheets. The American Statistician, 72(1), 2-10.",
    "wickham2014": "Wickham H. (2014). Tidy data. Journal of Statistical Software, 59(10), 1-23.",
    "wilkinson2016": "Wilkinson M. D. et al. (2016). The FAIR Guiding Principles for scientific data management and stewardship. "
                     "Scientific Data, 3, 160018.",
    "zuur2010": "Zuur A. F., Ieno E. N., Elphick C. S. (2010). A protocol for data exploration to avoid common statistical problems. "
                "Methods in Ecology and Evolution, 1(1), 3-14.",
    "tukey1977": "Tukey J. W. (1977). Exploratory Data Analysis. Addison-Wesley.",
    "little2019": "Little R. J. A., Rubin D. B. (2019). Statistical Analysis with Missing Data, 3e éd. Wiley.",
    "loi1951": "Loi n° 51-711 du 7 juin 1951 sur l'obligation, la coordination et le secret en matière de statistiques.",
    "reg223": "Règlement (CE) n° 223/2009 du 11 mars 2009 relatif aux statistiques européennes (confidentialité statistique, art. 20 à 26).",
    "rgpd": "Règlement (UE) 2016/679 du 27 avril 2016 (règlement général sur la protection des données).",
    # ------------------------------------------------------------------ halieutique
    "sih_sacrois": "Ifremer, Système d'Informations Halieutiques (2016). Flux SACROIS v3.5 : algorithme SACROIS/Jour et fichiers "
                   "utilisateurs. Ifremer / DPMA.",
    "sih_sacrois_data": "Ifremer, Système d'Informations Halieutiques (2017). Données de production et d'effort de pêche (SACROIS), "
                        "2003-2017. Ifremer.",
    "isscfg": "FAO, Coordinating Working Party on Fishery Statistics (2016). International Standard Statistical Classification of "
              "Fishing Gear (ISSCFG Rev. 1). CWP Handbook of Fishery Statistics, annexe M. FAO, Rome.",
    "dcf_metiers": "Règlement (UE) 2017/1004 relatif à la collecte et à la gestion de données dans le secteur de la pêche, et décision "
                   "déléguée (UE) 2021/1167 (programme pluriannuel : niveaux de métiers DCF).",
    "ices_rect": "CIEM / ICES. Rectangles statistiques (grille de 1° de longitude sur 0,5° de latitude). Conseil international pour "
                 "l'exploration de la mer, Copenhague.",
    "hintzen2012": "Hintzen N. T., Bastardie F., Beare D., Piet G. J., Ulrich C., Deporte N., Egekvist J., Degel H. (2012). VMStools: "
                   "open-source software for the processing, analysis and visualisation of fisheries logbook and VMS data. "
                   "Fisheries Research, 115-116, 31-43.",
    "lee2010": "Lee J., South A. B., Jennings S. (2010). Developing reliable, repeatable, and accessible methods to provide "
               "high-resolution estimates of fishing-effort distributions from vessel monitoring system (VMS) data. "
               "ICES Journal of Marine Science, 67(6), 1260-1271.",
    "gerritsen2011": "Gerritsen H., Lordan C. (2011). Integrating vessel monitoring systems (VMS) data with daily catch data from "
                     "logbooks to explore the spatial distribution of catch and effort at high resolution. ICES Journal of "
                     "Marine Science, 68(1), 245-252.",
    "maunder2004": "Maunder M. N., Punt A. E. (2004). Standardizing catch and effort data: a review of recent approaches. "
                   "Fisheries Research, 70(2-3), 141-159.",
    "venables2004": "Venables W. N., Dichmont C. M. (2004). GLMs, GAMs and GLMMs: an overview of theory for applications in "
                    "fisheries research. Fisheries Research, 70(2-3), 319-337.",
    "campbell2004": "Campbell R. A. (2004). CPUE standardisation and the construction of indices of stock abundance in a spatially "
                    "varying fishery using general linear models. Fisheries Research, 70(2-3), 209-227.",
    "lo1992": "Lo N. C. H., Jacobson L. D., Squire J. L. (1992). Indices of relative abundance from fish spotter data based on "
              "delta-lognormal models. Canadian Journal of Fisheries and Aquatic Sciences, 49(12), 2515-2526.",
    "shom_delmar": "Shom. Délimitations maritimes françaises (DELMAR). Licence Ouverte 2.0, data.gouv.fr.",
    "ofb_amp": "Office français de la biodiversité. Aires marines protégées françaises. Licence Ouverte 2.0, data.gouv.fr.",
    "naturalearth": "Natural Earth. Land polygons, 1:10m (domaine public). naturalearthdata.com.",
    # ------------------------------------------------------------------ tests et modèles
    "wasserstein2016": "Wasserstein R. L., Lazar N. A. (2016). The ASA statement on p-values: context, process, and purpose. "
                       "The American Statistician, 70(2), 129-133.",
    "shapiro1965": "Shapiro S. S., Wilk M. B. (1965). An analysis of variance test for normality (complete samples). "
                   "Biometrika, 52(3-4), 591-611.",
    "welch1947": "Welch B. L. (1947). The generalization of « Student's » problem when several different population variances are "
                 "involved. Biometrika, 34(1-2), 28-35.",
    "welch1951": "Welch B. L. (1951). On the comparison of several mean values: an alternative approach. Biometrika, 38(3-4), 330-336.",
    "delacre2017": "Delacre M., Lakens D., Leys C. (2017). Why psychologists should by default use Welch's t-test instead of "
                   "Student's t-test. International Review of Social Psychology, 30(1), 92-101.",
    "mannwhitney1947": "Mann H. B., Whitney D. R. (1947). On a test of whether one of two random variables is stochastically larger "
                       "than the other. Annals of Mathematical Statistics, 18(1), 50-60.",
    "kruskal1952": "Kruskal W. H., Wallis W. A. (1952). Use of ranks in one-criterion variance analysis. Journal of the American "
                   "Statistical Association, 47(260), 583-621.",
    "holm1979": "Holm S. (1979). A simple sequentially rejective multiple test procedure. Scandinavian Journal of Statistics, "
                "6(2), 65-70.",
    "levene1960": "Levene H. (1960). Robust tests for equality of variances. In Olkin I. (dir.), Contributions to Probability and "
                  "Statistics, Stanford University Press, 278-292.",
    "brown1974": "Brown M. B., Forsythe A. B. (1974). Robust tests for the equality of variances. Journal of the American "
                 "Statistical Association, 69(346), 364-367.",
    "cohen1988": "Cohen J. (1988). Statistical Power Analysis for the Behavioral Sciences, 2e éd. Lawrence Erlbaum.",
    "cochran1954": "Cochran W. G. (1954). Some methods for strengthening the common χ² tests. Biometrics, 10(4), 417-451.",
    "fisher1922": "Fisher R. A. (1922). On the interpretation of χ² from contingency tables, and the calculation of P. "
                  "Journal of the Royal Statistical Society, 85(1), 87-94.",
    "cramer1946": "Cramér H. (1946). Mathematical Methods of Statistics. Princeton University Press.",
    "spearman1904": "Spearman C. (1904). The proof and measurement of association between two things. American Journal of "
                    "Psychology, 15(1), 72-101.",
    "breusch1979": "Breusch T. S., Pagan A. R. (1979). A simple test for heteroscedasticity and random coefficient variation. "
                   "Econometrica, 47(5), 1287-1294.",
    "cook1977": "Cook R. D. (1977). Detection of influential observation in linear regression. Technometrics, 19(1), 15-18.",
    "mccullagh1989": "McCullagh P., Nelder J. A. (1989). Generalized Linear Models, 2e éd. Chapman & Hall.",
    "venables2002": "Venables W. N., Ripley B. D. (2002). Modern Applied Statistics with S, 4e éd. Springer.",
    "dunn1996": "Dunn P. K., Smyth G. K. (1996). Randomized quantile residuals. Journal of Computational and Graphical Statistics, "
                "5(3), 236-244.",
    "verhoef2007": "Ver Hoef J. M., Boveng P. L. (2007). Quasi-Poisson vs. negative binomial regression: how should we model "
                   "overdispersed count data? Ecology, 88(11), 2766-2772.",
    "zuur2009": "Zuur A. F., Ieno E. N., Walker N. J., Saveliev A. A., Smith G. M. (2009). Mixed Effects Models and Extensions in "
                "Ecology with R. Springer.",
    "martin2005": "Martin T. G., Wintle B. A., Rhodes J. R., Kuhnert P. M., Field S. A., Low-Choy S. J., Tyre A. J., Possingham H. P. "
                  "(2005). Zero tolerance ecology: improving ecological inference by modelling the source of zero observations. "
                  "Ecology Letters, 8(11), 1235-1246.",
    "searle1980": "Searle S. R., Speed F. M., Milliken G. A. (1980). Population marginal means in the linear model: an alternative "
                  "to least squares means. The American Statistician, 34(4), 216-221.",
    # ------------------------------------------------------------------ représentation
    "cleveland1984": "Cleveland W. S., McGill R. (1984). Graphical perception: theory, experimentation, and application to the "
                     "development of graphical methods. Journal of the American Statistical Association, 79(387), 531-554.",
    "tufte2001": "Tufte E. R. (2001). The Visual Display of Quantitative Information, 2e éd. Graphics Press.",
    "wilke2019": "Wilke C. O. (2019). Fundamentals of Data Visualization. O'Reilly.",
    "crameri2020": "Crameri F., Shephard G. E., Heron P. J. (2020). The misuse of colour in science communication. "
                   "Nature Communications, 11, 5444.",
    "brewer2003": "Brewer C. A., Hatchard G. W., Harrower M. A. (2003). ColorBrewer in print: a catalog of color schemes for maps. "
                  "Cartography and Geographic Information Science, 30(1), 5-32.",
    "monmonier2018": "Monmonier M. (2018). How to Lie with Maps, 3e éd. University of Chicago Press.",
}


def refs_md(keys: list[str]) -> list[str]:
    """Liste Markdown des références citées, triée par auteur, sans doublon."""
    seen = []
    for k in keys:
        if k in REFS and k not in seen:
            seen.append(k)
    return [f"- {REFS[k]}" for k in sorted(seen, key=lambda k: REFS[k].lower())]
