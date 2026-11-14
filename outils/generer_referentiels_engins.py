"""Régénère les référentiels engins (FAO ISSCFG 2016, engins cohérents, métiers).

Usage : python outils/generer_referentiels_engins.py backend/moanui/referentiels
Les listes sont à modifier ici puis à régénérer (ne pas éditer les JSON à la main).
"""
import json, sys
from pathlib import Path
REF = Path(sys.argv[1])

# ISSCFG Rev.1 (CWP 2016) — libellés français + codes DCF/historiques utilisés dans SACROIS
FAO = [
 # code, isscfg, famille, libellé, statut
 ("PS","01.1","Filets tournants","Sennes coulissantes","ISSCFG 2016"),
 ("LA","01.2","Filets tournants","Filets tournants sans coulisse (lamparo)","ISSCFG 2016"),
 ("SUX","01.9","Filets tournants","Filets tournants (non spécifiés)","ISSCFG 2016"),
 ("SB","02.1","Sennes","Sennes de plage","ISSCFG 2016"),
 ("SV","02.2","Sennes","Sennes de bateau","ISSCFG 2016"),
 ("SDN","02.2","Sennes","Sennes danoises","DCF (sous-catégorie de SV)"),
 ("SSC","02.2","Sennes","Sennes écossaises","DCF (sous-catégorie de SV)"),
 ("SPR","02.2","Sennes","Sennes manœuvrées par deux bateaux","DCF (sous-catégorie de SV)"),
 ("SX","02.9","Sennes","Sennes (non spécifiées)","ISSCFG 2016"),
 ("TBB","03.11","Chaluts de fond","Chaluts à perche","ISSCFG 2016"),
 ("OTB","03.12","Chaluts de fond","Chaluts de fond à panneaux","ISSCFG 2016"),
 ("OTT","03.13","Chaluts de fond","Chaluts jumeaux à panneaux","ISSCFG 2016"),
 ("OTP","03.14","Chaluts de fond","Chaluts multiples à panneaux","ISSCFG 2016"),
 ("PTB","03.15","Chaluts de fond","Chaluts bœufs de fond","ISSCFG 2016"),
 ("TB","03.19","Chaluts de fond","Chaluts de fond (non spécifiés)","ISSCFG 2016"),
 ("TBN","03.19","Chaluts de fond","Chaluts à langoustine","Historique (ISSCFG 1980)"),
 ("TBS","03.19","Chaluts de fond","Chaluts à crevette","Historique (ISSCFG 1980)"),
 ("OTM","03.21","Chaluts pélagiques","Chaluts pélagiques à panneaux","ISSCFG 2016"),
 ("PTM","03.22","Chaluts pélagiques","Chaluts bœufs pélagiques","ISSCFG 2016"),
 ("TM","03.29","Chaluts pélagiques","Chaluts pélagiques (non spécifiés)","ISSCFG 2016"),
 ("TSP","03.3","Chaluts","Chaluts semi-pélagiques","ISSCFG 2016"),
 ("OT","03.9","Chaluts","Chaluts à panneaux (non spécifiés)","Historique (ISSCFG 1980)"),
 ("PT","03.9","Chaluts","Chaluts bœufs (non spécifiés)","Historique (ISSCFG 1980)"),
 ("TX","03.9","Chaluts","Chaluts (non spécifiés)","ISSCFG 2016"),
 ("DRB","04.1","Dragues","Dragues remorquées","ISSCFG 2016"),
 ("DRH","04.2","Dragues","Dragues à main","ISSCFG 2016"),
 ("DRM","04.3","Dragues","Dragues mécanisées","ISSCFG 2016"),
 ("HMD","04.3","Dragues","Dragues mécanisées (dont hydrauliques)","DCF"),
 ("DRX","04.9","Dragues","Dragues (non spécifiées)","ISSCFG 2016"),
 ("LNP","05.1","Filets soulevés","Filets soulevés portatifs","ISSCFG 2016"),
 ("LNB","05.2","Filets soulevés","Filets soulevés manœuvrés du bateau","ISSCFG 2016"),
 ("LNS","05.3","Filets soulevés","Filets soulevés fixes manœuvrés du rivage","ISSCFG 2016"),
 ("LN","05.9","Filets soulevés","Filets soulevés (non spécifiés)","ISSCFG 2016"),
 ("FCN","06.1","Filets retombants","Éperviers","ISSCFG 2016"),
 ("FCO","06.2","Filets retombants","Nasses à couvercle / filets lanternes","ISSCFG 2016"),
 ("FG","06.9","Filets retombants","Filets retombants (non spécifiés)","ISSCFG 2016"),
 ("GNS","07.1","Filets maillants","Filets maillants calés (ancrés)","ISSCFG 2016"),
 ("GND","07.2","Filets maillants","Filets maillants dérivants","ISSCFG 2016"),
 ("GNC","07.3","Filets maillants","Filets maillants encerclants","ISSCFG 2016"),
 ("GNF","07.4","Filets maillants","Filets maillants fixes (sur piquets)","ISSCFG 2016"),
 ("GTR","07.5","Filets maillants","Trémails","ISSCFG 2016"),
 ("GTN","07.6","Filets maillants","Filets combinés maillant-trémail","ISSCFG 2016"),
 ("GEN","07.9","Filets maillants","Filets maillants et emmêlants (non spécifiés)","ISSCFG 2016"),
 ("GN","07.9","Filets maillants","Filets maillants (non spécifiés)","Historique (ISSCFG 1980)"),
 ("FPN","08.1","Pièges","Filets-pièges fixes non couverts (parcs)","ISSCFG 2016"),
 ("FPO","08.2","Pièges","Casiers et nasses","ISSCFG 2016"),
 ("FYK","08.3","Pièges","Verveux","ISSCFG 2016"),
 ("FSN","08.4","Pièges","Filets à l'étalage (diables)","ISSCFG 2016"),
 ("FWR","08.5","Pièges","Barrages, bordigues, écluses","ISSCFG 2016"),
 ("FAR","08.6","Pièges","Pièges aériens","ISSCFG 2016"),
 ("FIX","08.9","Pièges","Pièges (non spécifiés)","ISSCFG 2016"),
 ("LHP","09.1","Lignes et hameçons","Lignes à main et cannes manœuvrées à la main","ISSCFG 2016"),
 ("LHM","09.2","Lignes et hameçons","Lignes et cannes mécanisées","ISSCFG 2016"),
 ("LLS","09.31","Lignes et hameçons","Palangres calées","ISSCFG 2016"),
 ("LLD","09.32","Lignes et hameçons","Palangres dérivantes","ISSCFG 2016"),
 ("LL","09.39","Lignes et hameçons","Palangres (non spécifiées)","ISSCFG 2016"),
 ("LVT","09.4","Lignes et hameçons","Lignes verticales","ISSCFG 2016"),
 ("LTL","09.5","Lignes et hameçons","Lignes de traîne","ISSCFG 2016"),
 ("LX","09.9","Lignes et hameçons","Lignes et hameçons (non spécifiés)","ISSCFG 2016"),
 ("HAR","10.1","Divers","Harpons","ISSCFG 2016"),
 ("MHI","10.2","Divers","Outils à main (râteaux, pinces, foënes…)","ISSCFG 2016"),
 ("MPM","10.3","Divers","Pompes","ISSCFG 2016"),
 ("MEL","10.4","Divers","Pêche électrique","ISSCFG 2016"),
 ("MPN","10.5","Divers","Haveneaux poussés","ISSCFG 2016"),
 ("MSP","10.6","Divers","Épuisettes","ISSCFG 2016"),
 ("MDR","10.7","Divers","Filets rabattants","ISSCFG 2016"),
 ("MDV","10.8","Divers","Plongée","ISSCFG 2016"),
 ("MIS","10.9","Divers","Engins divers (non spécifiés)","ISSCFG 2016"),
 ("NK","99.9","Inconnu","Engin inconnu","ISSCFG 2016"),
]
codes = {c[0] for c in FAO}

# codes génériques (« non spécifiés ») : acceptés si un engin précis de leur groupe est cohérent
GENERIQUES = {
 "SUX": ["PS","LA"], "SX": ["SB","SV","SDN","SSC","SPR"], "SV": ["SDN","SSC","SPR"],
 "TB": ["TBB","OTB","OTT","OTP","PTB","TBN","TBS"], "TM": ["OTM","PTM"],
 "OT": ["OTB","OTT","OTP","OTM"], "PT": ["PTB","PTM"],
 "TX": ["TBB","OTB","OTT","OTP","PTB","TBN","TBS","OTM","PTM","TSP"],
 "DRX": ["DRB","DRH","DRM","HMD"], "LN": ["LNP","LNB","LNS"], "FG": ["FCN","FCO"],
 "GEN": ["GNS","GND","GNC","GNF","GTR","GTN"], "GN": ["GNS","GND","GNC","GNF","GTR","GTN"],
 "FIX": ["FPN","FPO","FYK","FSN","FWR","FAR"], "LL": ["LLS","LLD"],
 "LX": ["LHP","LHM","LLS","LLD","LVT","LTL"],
}
NON_CONTROLABLES = ["MIS","NK"]

CHAL_FOND = ["OTB","OTT","OTP","PTB"]
SENNES = ["SDN","SSC","SPR"]
FILETS = ["GNS","GTR","GTN"]
CHAL_PEL = ["OTM","PTM"]

def sp(codes_, nom, latin, principaux, accessoires, note=""):
    return codes_, {"nom": nom, "nom_latin": latin, "principaux": principaux,
                    "coherents": sorted(set(principaux) | set(accessoires)), "note": note}

ESP = [
 sp(["SOL"],"Sole commune","Solea solea",["GTR","GNS","GTN","OTB","OTT","TBB"],["PTB","OTP"]+SENNES,
    "Espèce benthique : filets (trémail en tête) et chaluts de fond ; prises à l'hameçon ou au casier marginales."),
 sp(["HKE"],"Merlu européen","Merluccius merluccius",["GNS","LLS","OTB","OTT","PTB"],["GTR","GTN","GND","LHM","LHP","OTP","TBB"]+CHAL_PEL+SENNES),
 sp(["NEP"],"Langoustine","Nephrops norvegicus",["OTB","OTT","TBN"],["OTP","PTB","FPO","TBB"],
    "Casier (creel) rare en France mais réglementaire."),
 sp(["ANF","MON","MNZ"],"Baudroies","Lophius piscatorius, L. budegassa",["OTB","OTT","GNS","GTR"],["GTN","PTB","OTP","TBB","LLS","DRB"]+SENNES,
    "Prise accessoire connue des dragues à coquille en Manche."),
 sp(["SCE"],"Coquille Saint-Jacques","Pecten maximus",["DRB"],["DRM","HMD","DRH","MDV"],
    "Pêche quasi exclusive à la drague ; plongée autorisée localement."),
 sp(["BSS"],"Bar européen","Dicentrarchus labrax",["LHP","LHM","LLS","LTL","GNS","OTM","PTM"],["GTR","GTN","OTB","OTT","PTB","PS","SB"]+SENNES),
 sp(["CTC"],"Seiche commune","Sepia officinalis",["OTB","OTT","FPO","GTR"],["PTB","OTP","TBB","GNS","GTN"]+SENNES,
    "Casiers à seiche au printemps sur la côte."),
 sp(["SQR","SQZ"],"Encornets (calmars)","Loligo spp.",["OTB","OTT","LHP","LHM"],["PTB","OTP","TBB","OTM","PTM","LVT","GNS"]+SENNES,
    "Turlutte = ligne (LHP/LHM)."),
 sp(["MAC"],"Maquereau commun","Scomber scombrus",["OTM","PTM","PS","LHP","LHM","LTL"],["OTB","OTT","PTB","GNS","GND","LA","SB"]+SENNES),
 sp(["LEZ","MEG","LDB"],"Cardines","Lepidorhombus spp.",["OTB","OTT"],["PTB","OTP","TBB","GNS","GTR","GTN"]+SENNES),
 sp(["POL"],"Lieu jaune","Pollachius pollachius",["LHP","LHM","LTL","GNS","LLS"],["GTR","GTN","OTB","OTT","PTB","OTM","PTM"]+SENNES),
 sp(["WHG"],"Merlan","Merlangius merlangus",["OTB","OTT","PTB"],["OTP","TBB","OTM","PTM","GNS","GTR","GTN","LLS","LHP"]+SENNES),
 sp(["RJC","RJU","RJN","RJH","RJM","RJE","SKA"],"Raies","Rajidae",["OTB","OTT","GTR","GNS"],["GTN","PTB","OTP","TBB","LLS","DRB"]+SENNES,
    "Raie brunette (RJU) : pêche encadrée, vérifier la réglementation en vigueur."),
 sp(["CRE"],"Tourteau","Cancer pagurus",["FPO"],["GTR","GNS","GTN","OTB","OTT","TBB","DRB"]),
 sp(["LBE"],"Homard européen","Homarus gammarus",["FPO"],["GTR","GNS","GTN"],
    "Captures au chalut ou à la drague très rares : à vérifier."),
 sp(["SCR"],"Araignée de mer","Maja brachydactyla",["FPO","GTR","GNS"],["GTN","OTB","OTT","TBB","DRB"]),
 sp(["WHE"],"Bulot","Buccinum undatum",["FPO"],["DRB","OTB","TBB"]),
 sp(["JOD"],"Saint-Pierre","Zeus faber",["OTB","OTT","PTB"],["OTP","TBB","OTM","PTM","GNS","GTR","GTN","LLS","LHP"]+SENNES),
 sp(["MUR"],"Rouget barbet de roche","Mullus surmuletus",["OTB","OTT","GTR","GNS"],["PTB","OTP","TBB","GTN","OTM","PTM"]+SENNES),
 sp(["BRB"],"Dorade grise","Spondyliosoma cantharus",["OTB","OTT","PTB","OTM","PTM","LHP","LHM"],["GNS","GTR","GTN","LLS","FPO"]+SENNES),
]
COMPL = [
 sp(["PIL"],"Sardine","Sardina pilchardus",["PS","OTM","PTM"],["LA","GND","GNS"]),
 sp(["ANE"],"Anchois","Engraulis encrasicolus",["PS","OTM","PTM"],["LA"]),
 sp(["PLE"],"Plie","Pleuronectes platessa",["OTB","OTT","TBB","GTR"],["PTB","OTP","GNS","GTN"]+SENNES),
 sp(["TUR","BLL"],"Turbot, barbue","Scophthalmus maximus, S. rhombus",["GTR","GNS","OTB","OTT"],["GTN","PTB","OTP","TBB","LLS","DRB"]+SENNES),
 sp(["GUU","GUR","GUX"],"Grondins","Triglidae",["OTB","OTT"],["PTB","OTP","TBB","OTM","PTM","GNS","GTR","GTN","LHP"]+SENNES),
 sp(["LIN"],"Lingue franche","Molva molva",["LLS","OTB","OTT"],["PTB","GNS","GTR","GTN","LHM"]),
]
especes = {}
for lst, palier in ((ESP,"20 principales"),(COMPL,"complémentaire")):
    for cs, d in lst:
        for g in d["coherents"]:
            assert g in codes, g
        for c in cs:
            e = dict(d); e["groupe"] = palier
            if len(cs) > 1: e["codes_associes"] = cs
            especes[c] = e

coh = {
 "nom": "Engins cohérents par espèce",
 "description": ("Engins attendus pour 26 espèces (20 principales Manche / golfe de Gascogne + 6 complémentaires), "
                 "codes FAO ISSCFG 2016. Liste de départ issue de la littérature, à adapter par chaque structure."),
 "version": "2026-11",
 "methode": ("Les classements par comité / navires hors OP ne sont pas publics : sélection des espèces sur les principales "
             "espèces débarquées en valeur par les navires français en Manche et golfe de Gascogne (Ifremer SIH, "
             "FranceAgriMer), en privilégiant celles de la petite pêche côtière. Pour chaque espèce : « principaux » = "
             "engins ciblant l'espèce ; « coherents » = principaux + engins où elle est une prise accessoire régulière. "
             "Les codes génériques (« non spécifiés ») sont acceptés si un engin précis de leur groupe est cohérent ; "
             "MIS et NK ne sont jamais signalés."),
 "sources": [
   "FAO CWP (2016). Handbook of Fishery Statistical Standards, Annex M : International Standard Classification of Fishing Gears (ISSCFG Rev.1).",
   "He P., Chopin F., Suuronen P., Ferro R.S.T., Lansley J. (2021). Classification and illustrated definition of fishing gears. FAO Fisheries and Aquaculture Technical Paper 672.",
   "Commission européenne, DCF / EU-MAP : codification des métiers (niveaux 4 à 6), liste de référence des RCG.",
   "Ifremer, Système d'Informations Halieutiques : synthèses annuelles des flottilles de pêche et activité des navires par façade.",
   "CIEM (ICES) : rapports WGBIE et WGCSE (sole, merlu, cardines, baudroies, langoustine, raies), WGBASS / WGCSE (bar), WGWIDE (maquereau).",
   "Quéro J.-C., Vayne J.-J. (1997). Les poissons de mer des pêches françaises. Delachaux et Niestlé.",
 ],
 "generiques": GENERIQUES,
 "non_controlables": NON_CONTROLABLES,
 "especes": especes,
}
(REF/"engins_coherents.json").write_text(json.dumps(coh, ensure_ascii=False, indent=1), encoding="utf-8")

fao = {"nom": "Engins FAO (ISSCFG 2016)",
       "description": "Libellé français, famille et code ISSCFG des codes engins FAO (+ codes DCF et historiques vus dans SACROIS).",
       "cle": "engin_cod", "colonnes": ["engin_lib", "engin_famille", "isscfg", "engin_statut"],
       "lignes": [{"engin_cod": c, "engin_lib": l, "engin_famille": f, "isscfg": i, "engin_statut": s} for c,i,f,l,s in FAO]}
(REF/"engins_fao.json").write_text(json.dumps(fao, ensure_ascii=False, indent=1), encoding="utf-8")

# compléter engins → métiers avec les codes FAO absents (sans modifier l'existant)
met = json.loads((REF/"engins_metiers.json").read_text(encoding="utf-8"))
have = {r["engin_cod"] for r in met["lignes"]}
FAM2MET = {"Filets tournants":("Sennes","Senne coulissante"),"Sennes":("Sennes","Sennes"),
  "Chaluts de fond":("Chaluts","Chaluts"),"Chaluts pélagiques":("Chaluts","Chaluts pélagiques"),"Chaluts":("Chaluts","Chaluts"),
  "Dragues":("Dragues","Dragues"),"Filets soulevés":("Filets","Filets soulevés"),"Filets retombants":("Divers","Divers"),
  "Filets maillants":("Filets","Filets maillants"),"Pièges":("Casiers","Casiers et nasses"),
  "Lignes et hameçons":("Hameçons","Lignes"),"Divers":("Divers","Divers"),"Inconnu":("Autres","Inconnu")}
for c,i,f,l,s in FAO:
    if c not in have:
        m, d = FAM2MET[f]
        if c == "OTP": d = "Chaluts à panneaux"
        if c in ("LVT",): d = "Lignes à main"
        if c == "MDV": m, d = "Divers", "Plongée"
        met["lignes"].append({"engin_cod": c, "metier": m, "metier_detail": d})
met["description"] = "Regroupement des codes engins FAO en métiers (repris de Moanui 0.1, complété avec l'ISSCFG 2016 ; à valider par chaque structure)."
(REF/"engins_metiers.json").write_text(json.dumps(met, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(especes), "codes espèces;", len(met["lignes"]), "lignes métiers")
