# =============================================================================
# functions_data.R — Fonctions utilitaires module Gestion de la donnée
# =============================================================================

# -----------------------------------------------------------------------------
# 1. IMPORT (réutilise charger_fichier de functions_dyn si déjà sourcé,
#    sinon défini ici de façon autonome)
# -----------------------------------------------------------------------------

# Colonnes à forcer en character à l'import (pattern regex sur le nom de colonne)
# Ajoutez ici tout pattern qui peut contenir des codes alphanumériques comme "23E6"
COLS_FORCER_CHARACTER <- c(
  "stat_rect", "rectangle_stat", "rect_stat",
  "div_ciem", "quartier_cod", "quartier",
  "engin_cod", "esp_cod", "port_cod", "navire_cod",
  "code$", "_cod$", "_code$"
)

#' Détecte les colonnes d'un df qui doivent être lues comme character
#' selon COLS_FORCER_CHARACTER (matching partiel insensible à la casse)
.cols_a_forcer_chr <- function(noms_cols) {
  pattern <- paste(COLS_FORCER_CHARACTER, collapse = "|")
  noms_cols[grepl(pattern, noms_cols, ignore.case = TRUE)]
}

#' Applique le forçage character après import (pour RDS, JSON, XLSX sans col_types)
.forcer_character_post <- function(df) {
  cols <- .cols_a_forcer_chr(names(df))
  for (col in cols) df[[col]] <- as.character(df[[col]])
  df
}

#' Chargement multi-format (CSV, TSV, XLSX, RDS, JSON)
#' Retourne un data.frame ou NULL en cas d'erreur.
#' Les colonnes dont le nom matche COLS_FORCER_CHARACTER sont systématiquement
#' lues comme character pour éviter la conversion 23E6 → 23000000.
charger_fichier_data <- function(path, ext = NULL,
                                 sep = ",", dec = ".", enc = "UTF-8",
                                 header = TRUE) {
  if (is.null(ext)) ext <- tolower(tools::file_ext(path))
  tryCatch({
    df <- switch(ext,
                 "csv" = {
                   # Lecture rapide pour récupérer les noms de colonnes
                   noms  <- names(readr::read_delim(path, delim = sep, n_max = 0,
                                                    col_names = header,
                                                    locale = readr::locale(decimal_mark = dec,
                                                                           encoding = enc),
                                                    show_col_types = FALSE))
                   a_forcer <- .cols_a_forcer_chr(noms)
                   spec_chr  <- if (length(a_forcer) > 0)
                     do.call(readr::cols, stats::setNames(
                       lapply(a_forcer, function(x) readr::col_character()), a_forcer))
                   else readr::cols()
                   readr::read_delim(path, delim = sep, col_names = header,
                                     locale = readr::locale(decimal_mark = dec, encoding = enc),
                                     col_types = spec_chr,
                                     show_col_types = FALSE)
                 },
                 "tsv" = {
                   noms  <- names(readr::read_tsv(path, n_max = 0, show_col_types = FALSE))
                   a_forcer <- .cols_a_forcer_chr(noms)
                   spec_chr  <- if (length(a_forcer) > 0)
                     do.call(readr::cols, stats::setNames(
                       lapply(a_forcer, function(x) readr::col_character()), a_forcer))
                   else readr::cols()
                   readr::read_tsv(path, col_types = spec_chr, show_col_types = FALSE)
                 },
                 "txt" = {
                   noms  <- names(readr::read_delim(path, delim = sep, n_max = 0,
                                                    show_col_types = FALSE))
                   a_forcer <- .cols_a_forcer_chr(noms)
                   spec_chr  <- if (length(a_forcer) > 0)
                     do.call(readr::cols, stats::setNames(
                       lapply(a_forcer, function(x) readr::col_character()), a_forcer))
                   else readr::cols()
                   readr::read_delim(path, delim = sep, col_types = spec_chr,
                                     show_col_types = FALSE)
                 },
                 "xlsx" = {
                   # readxl : on lit d'abord pour détecter, puis on relit avec col_types vecteur
                   df_tmp   <- readxl::read_excel(path, n_max = 0)
                   noms     <- names(df_tmp)
                   a_forcer <- .cols_a_forcer_chr(noms)
                   types    <- ifelse(noms %in% a_forcer, "text", "guess")
                   readxl::read_excel(path, col_types = types)
                 },
                 "xls" = {
                   df_tmp   <- readxl::read_excel(path, n_max = 0)
                   noms     <- names(df_tmp)
                   a_forcer <- .cols_a_forcer_chr(noms)
                   types    <- ifelse(noms %in% a_forcer, "text", "guess")
                   readxl::read_excel(path, col_types = types)
                 },
                 "rds"  = .forcer_character_post(readRDS(path)),
                 "json" = .forcer_character_post(
                   jsonlite::fromJSON(path, flatten = TRUE) |> as.data.frame()
                 ),
                 NULL
    )
    if (is.null(df)) stop("Format non reconnu : ", ext)
    as.data.frame(df)
  }, error = function(e) {
    shiny::showNotification(paste("Erreur import :", e$message), type = "error",
                            duration = 8)
    NULL
  })
}

# -----------------------------------------------------------------------------
# 1b. FALLBACKS — parser_date / ajouter_ns
# Définis ici uniquement si functions_dyn.R n'a pas encore été sourcé,
# ce qui évite l'erreur "could not find function 'parser_date'".
# -----------------------------------------------------------------------------

if (!exists("parser_date", mode = "function")) {
  parser_date <- function(x) {
    formats <- c("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y",
                 "%Y/%m/%d", "%d.%m.%Y", "%Y%m%d")
    if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return(as.Date(x))
    if (is.numeric(x)) {
      if (all(nchar(as.character(na.omit(x))) == 6))
        return(as.Date(paste0(x, "01"), format = "%Y%m%d"))
      return(as.Date(x, origin = "1899-12-30"))
    }
    for (fmt in formats) {
      parsed <- suppressWarnings(as.Date(as.character(x), format = fmt))
      if (sum(!is.na(parsed), na.rm = TRUE) / max(length(x), 1) > 0.8)
        return(parsed)
    }
    suppressWarnings(
      lubridate::parse_date_time(x,
                                 orders = c("dmy","ymd","mdy","dmy HM","ymd HM")) |> as.Date()
    )
  }
}

if (!exists("ajouter_ns", mode = "function")) {
  ajouter_ns <- function(df) {
    if ("NS" %in% names(df) && !all(is.na(df$NS))) return(df)
    if ("div_ciem_cod_sipa" %in% names(df)) {
      df$NS <- dplyr::case_when(
        grepl("^27\\.7", df$div_ciem_cod_sipa) ~ "Nord",
        grepl("^27\\.8", df$div_ciem_cod_sipa) ~ "Sud",
        TRUE ~ NA_character_
      )
    }
    df
  }
}

# -----------------------------------------------------------------------------
# 2. RÉSUMÉ STATISTIQUE
# -----------------------------------------------------------------------------

#' Tableau de résumé statistique par colonne
#' Retourne un data.frame propre affichable dans DT.
resumer_donnees <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(data.frame())
  
  purrr::map_dfr(names(df), function(col) {
    x    <- df[[col]]
    type <- type_colonne(x)
    na_n <- sum(is.na(x))
    na_p <- round(na_n / length(x) * 100, 1)
    
    base <- data.frame(
      Colonne   = col,
      Type      = type,
      N_total   = length(x),
      N_NA      = na_n,
      Pct_NA    = paste0(na_p, "%"),
      stringsAsFactors = FALSE
    )
    
    if (is.numeric(x) && !all(is.na(x))) {
      base$Min    <- round(min(x, na.rm = TRUE), 3)
      base$Max    <- round(max(x, na.rm = TRUE), 3)
      base$Moyenne <- round(mean(x, na.rm = TRUE), 3)
      base$Médiane <- round(stats::median(x, na.rm = TRUE), 3)
      base$N_uniques <- dplyr::n_distinct(x, na.rm = TRUE)
    } else {
      base$Min    <- NA
      base$Max    <- NA
      base$Moyenne <- NA
      base$Médiane <- NA
      base$N_uniques <- dplyr::n_distinct(x, na.rm = TRUE)
    }
    base
  })
}

# -----------------------------------------------------------------------------
# 3. HELPERS TYPE
# -----------------------------------------------------------------------------

#' Retourne le type simplifié d'une colonne sous forme de label lisible
type_colonne <- function(x) {
  if (is.numeric(x))   return("Numérique")
  if (is.character(x)) return("Texte")
  if (is.factor(x))    return("Facteur")
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return("Date")
  if (is.logical(x))   return("Logique")
  "Autre"
}

#' Badge CSS selon le type de colonne
badge_type <- function(type) {
  cls <- switch(type,
                "Numérique" = "col-badge-num",
                "Texte"     = "col-badge-chr",
                "Facteur"   = "col-badge-fct",
                "Date"      = "col-badge-dat",
                "Logique"   = "col-badge-lgl",
                "col-badge-oth"
  )
  shiny::tags$span(class = paste("col-badge", cls), type)
}

# -----------------------------------------------------------------------------
# 4. OPÉRATIONS SUR LES COLONNES
# -----------------------------------------------------------------------------

#' Renommer une ou plusieurs colonnes
#' @param df  data.frame
#' @param old vecteur noms actuels
#' @param new vecteur nouveaux noms (même longueur)
renommer_colonnes <- function(df, old, new) {
  for (i in seq_along(old)) {
    if (old[i] %in% names(df)) names(df)[names(df) == old[i]] <- new[i]
  }
  df
}

#' Supprimer des colonnes
supprimer_colonnes <- function(df, cols) {
  df[, setdiff(names(df), cols), drop = FALSE]
}

#' Réordonner les colonnes (cols_ordonnees = vecteur complet dans le bon ordre)
reordonner_colonnes <- function(df, cols_ordonnees) {
  cols_ok <- intersect(cols_ordonnees, names(df))
  df[, cols_ok, drop = FALSE]
}

#' Changer le type d'une colonne
#' @param type_cible "numeric","character","factor","Date","logical"
changer_type <- function(df, col, type_cible) {
  if (!col %in% names(df)) return(df)
  tryCatch({
    df[[col]] <- switch(type_cible,
                        "numeric"   = suppressWarnings(as.numeric(df[[col]])),
                        "character" = as.character(df[[col]]),
                        "factor"    = as.factor(df[[col]]),
                        "Date"      = parser_date(df[[col]]),   # réutilise parser_date de functions_dyn
                        "logical"   = suppressWarnings(as.logical(df[[col]])),
                        df[[col]]
    )
  }, error = function(e) {
    shiny::showNotification(
      paste0("Impossible de convertir '", col, "' en ", type_cible,
             " : ", e$message),
      type = "warning", duration = 6
    )
  })
  df
}

#' Créer une nouvelle colonne par expression R libre (évaluée sur df)
#' Expression ex : "col_a + col_b", "toupper(nom)", "ifelse(age > 18, 'adulte','mineur')"
creer_colonne <- function(df, nom_col, expression_r) {
  tryCatch({
    val <- with(df, eval(parse(text = expression_r)))
    df[[nom_col]] <- val
    df
  }, error = function(e) {
    shiny::showNotification(
      paste("Erreur dans l'expression :", e$message),
      type = "error", duration = 8
    )
    df
  })
}

#' Appliquer une transformation sur une colonne existante
#' @param op   "uppercase","lowercase","trim","arrondir","abs","log","sqrt",
#'             "replace_na","recode_valeur","bin_egal","bin_quantile"
#' @param params liste de paramètres complémentaires selon l'opération
transformer_colonne <- function(df, col, op, params = list()) {
  if (!col %in% names(df)) return(df)
  x <- df[[col]]
  
  result <- tryCatch({
    switch(op,
           "uppercase"     = toupper(as.character(x)),
           "lowercase"     = tolower(as.character(x)),
           "trim"          = trimws(as.character(x)),
           "arrondir"      = round(as.numeric(x), digits = as.integer(params$digits %||% 2)),
           "abs"           = abs(as.numeric(x)),
           "log"           = log(as.numeric(x)),
           "sqrt"          = sqrt(as.numeric(x)),
           "replace_na"    = {
             val <- params$valeur_na
             if (is.numeric(x)) {
               val <- suppressWarnings(as.numeric(val))
             }
             dplyr::coalesce(x, val)
           },
           "recode_valeur" = {
             # params$old, params$new
             dplyr::recode(as.character(x),
                           !!!stats::setNames(list(params$new),
                                              params$old))
           },
           "bin_egal"      = {
             n <- as.integer(params$n_bins %||% 5)
             cut(as.numeric(x), breaks = n, include.lowest = TRUE)
           },
           "bin_quantile"  = {
             n <- as.integer(params$n_bins %||% 4)
             ggplot2::cut_number(as.numeric(x), n = n)
           },
           x  # inchangé si op inconnu
    )
  }, error = function(e) {
    shiny::showNotification(
      paste0("Opération '", op, "' échouée : ", e$message),
      type = "error", duration = 6
    )
    x
  })
  
  df[[col]] <- result
  df
}

# Opérateur null-coalescing interne
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

# -----------------------------------------------------------------------------
# 4b. CONVERSION D'UNITÉS
# -----------------------------------------------------------------------------

#' Table des facteurs de conversion entre unités
#' Chaque entrée : from → to → facteur multiplicatif
CONVERSION_UNITS <- list(
  # Masse
  masse = list(
    units = c("kg", "g", "t", "mg", "lb", "oz"),
    labels = c("Kilogramme (kg)", "Gramme (g)", "Tonne (t)",
               "Milligramme (mg)", "Livre (lb)", "Once (oz)"),
    # Tout vers kg d'abord, puis vers cible
    to_kg = c(kg=1, g=0.001, t=1000, mg=1e-6, lb=0.453592, oz=0.0283495)
  ),
  # Volume
  volume = list(
    units = c("l", "ml", "m3", "cl"),
    labels = c("Litre (l)", "Millilitre (ml)", "Mètre cube (m³)", "Centilitre (cl)"),
    to_base = c(l=1, ml=0.001, m3=1000, cl=0.01)
  ),
  # Distance
  distance = list(
    units = c("m", "km", "nm", "ft"),
    labels = c("Mètre (m)", "Kilomètre (km)", "Mille nautique (nm)", "Pied (ft)"),
    to_base = c(m=1, km=1000, nm=1852, ft=0.3048)
  )
)

#' Convertit une colonne numérique d'une unité vers une autre
#' @param df       data.frame
#' @param col      nom de la colonne source
#' @param unite_in code unité source (ex: "kg")
#' @param unite_out code unité cible (ex: "g")
#' @param col_dest  nom de la colonne résultat (défaut : col_<unite_out>)
convertir_unite <- function(df, col, unite_in, unite_out, col_dest = NULL) {
  if (!col %in% names(df)) {
    shiny::showNotification(paste0("Colonne '", col, "' introuvable."),
                            type = "warning", duration = 4)
    return(df)
  }
  if (unite_in == unite_out) {
    shiny::showNotification("Unité source = unité cible, rien à convertir.",
                            type = "warning", duration = 3)
    return(df)
  }
  
  # Chercher le groupe d'unités qui contient les deux
  facteur <- tryCatch({
    groupe <- NULL
    for (g in CONVERSION_UNITS) {
      base_field <- if (!is.null(g$to_kg)) "to_kg" else "to_base"
      tbl <- g[[base_field]]
      if (unite_in %in% names(tbl) && unite_out %in% names(tbl)) {
        groupe <- tbl
        break
      }
    }
    if (is.null(groupe)) stop("Combinaison d'unités non supportée.")
    # Conversion via base commune
    groupe[[unite_in]] / groupe[[unite_out]]
  }, error = function(e) {
    shiny::showNotification(paste("Erreur conversion :", e$message), type = "error", duration = 5)
    NULL
  })
  
  if (is.null(facteur)) return(df)
  
  nom_dest <- col_dest %||% paste0(col, "_", unite_out)
  tryCatch({
    df[[nom_dest]] <- suppressWarnings(as.numeric(df[[col]])) * facteur
    shiny::showNotification(
      paste0("'", col, "' converti de ", unite_in, " → ", unite_out,
             " (×", round(facteur, 6), ") → colonne '", nom_dest, "'"),
      type = "message", duration = 4
    )
  }, error = function(e) {
    shiny::showNotification(paste("Erreur :", e$message), type = "error", duration = 5)
  })
  df
}

#' Retourne les unités disponibles par catégorie (pour l'UI)
get_units_choices <- function() {
  lapply(CONVERSION_UNITS, function(g) {
    stats::setNames(g$units, g$labels)
  })
}

# -----------------------------------------------------------------------------
# 4c. COLONNE MÉTIER (via référentiel)
# -----------------------------------------------------------------------------

#' Charge le référentiel métier depuis un fichier xlsx
#' Retourne un data.frame avec colonnes : engin_cod, metier_detail, metier
#' Hardcodé directement (pas de fichier externe requis).
charger_ref_metier <- function(...) {
  data.frame(
    engin_cod     = c(
      "OTB", "OTM", "OTT", "OT", "PTB", "PTM", "TBB", "TBN", "TB", "TBS",
      "SDN", "SV", "SPR", "SX", "SSC", "SDV", "SB", "PS", "PS1", "DRB",
      "DHB", "GNC", "GNS", "GND", "GTN", "GNE", "LN", "LNS", "LNB", "GTR",
      "GN", "GEN", "FPO", "FYK", "LHP", "LHM", "LLD", "LLS", "LX", "LVS",
      "LVD", "LL", "LTL", "GES", "HRK", "FIE", "FID"
    ),
    metier_detail = c(
      "Chaluts à panneaux", "Chaluts à panneaux", "Chaluts à panneaux", "Chaluts à panneaux",
      "Chaluts à bœuf", "Chaluts à bœuf",
      NA_character_, NA_character_, NA_character_, NA_character_,
      NA_character_, NA_character_, "Senne coulissante", NA_character_, NA_character_,
      NA_character_, "Senne de plage", "Senne coulissante", "Senne coulissante", NA_character_,
      "Dragues à main", "Filets maillants", "Filets maillants", "Filets maillants",
      "Filets maillants", "Filets maillants", "Filets soulevés", "Filets soulevés",
      "Filets soulevés", "Trémail", "Filets maillants", "Filets maillants",
      "Casiers et nasses", "Verveux", "Lignes à main", "Lignes à main",
      "Palangres", "Palangres", "Palangres", "Palangres", "Palangres", "Palangres",
      "Lignes de traîne", NA_character_, NA_character_, NA_character_, NA_character_
    ),
    metier        = c(
      "Chaluts", "Chaluts", "Chaluts", "Chaluts", "Chaluts", "Chaluts",
      "Chaluts", "Chaluts", "Chaluts", "Chaluts",
      "Senne", "Senne", "Senne", "Senne", "Senne",
      "Dragues", "Senne", "Senne", "Senne", "Dragues",
      "Dragues", "Filets", "Filets", "Filets", "Filets", "Filets",
      "Filets", "Filets", "Filets", "Filets", "Filets", "Filets",
      "Casiers", "Casiers", "Hamçons", "Hamçons", "Hamçons", "Hamçons",
      "Hamçons", "Hamçons", "Hamçons", "Hamçons", "Hamçons",
      "Divers", "Divers", "Divers", "Divers"
    ),
    stringsAsFactors = FALSE
  )
}

#' Crée une colonne métier large et/ou détaillée à partir d'engin_cod
#' Logique de hiérarchie : si l'utilisateur sélectionne un métier détaillé
#' ET son métier large parent, les engins du détaillé sont retirés du large.
#'
#' @param df           data.frame
#' @param col_engin    nom de la colonne engin (ex: "engin_cod")
#' @param ref          data.frame référentiel métier (issu de charger_ref_metier)
#' @param metiers_sel  vecteur des métiers retenus par l'utilisateur (valeurs de $metier_detail)
#' @param niveau       "large", "detail" ou "les_deux"
#' @param col_dest_large  nom colonne résultat métier large (défaut: "metier")
#' @param col_dest_detail nom colonne résultat métier détaillé (défaut: "metier_detail")
creer_colonne_metier <- function(df, col_engin, ref,
                                 metiers_sel = NULL,
                                 niveau = "les_deux",
                                 col_dest_large  = "metier",
                                 col_dest_detail = "metier_detail") {
  if (!col_engin %in% names(df)) {
    shiny::showNotification(paste0("Colonne '", col_engin, "' introuvable."),
                            type = "warning", duration = 4)
    return(df)
  }
  if (nrow(ref) == 0) {
    shiny::showNotification("Référentiel métier vide.", type = "warning", duration = 4)
    return(df)
  }
  
  # Table de correspondance engin -> metier (on prend le premier match par engin)
  ref_uniq <- ref[!duplicated(ref$engin_cod), c("engin_cod", "metier", "metier_detail")]
  
  # Filtrage selon le niveau et la selection de l'utilisateur
  if (!is.null(metiers_sel) && length(metiers_sel) > 0) {
    if (niveau == "large") {
      # metiers_sel contient des valeurs de $metier (large)
      engins_sel <- ref$engin_cod[ref$metier %in% metiers_sel]
    } else {
      # niveau "detail" ou "les_deux" -> metiers_sel contient des valeurs de $metier_detail
      engins_sel <- ref$engin_cod[ref$metier_detail %in% metiers_sel]
    }
    ref_filtre <- ref[ref$engin_cod %in% engins_sel, ]
    ref_uniq   <- ref_filtre[!duplicated(ref_filtre$engin_cod), c("engin_cod", "metier", "metier_detail")]
  }
  
  engin_vec <- as.character(df[[col_engin]])
  
  # Jointure vectorielle
  metier_large  <- ref_uniq$metier[match(engin_vec, ref_uniq$engin_cod)]
  metier_detail_v <- ref_uniq$metier_detail[match(engin_vec, ref_uniq$engin_cod)]
  
  # NA → "Autres"
  metier_large[is.na(metier_large)]    <- "Autres"
  metier_detail_v[is.na(metier_detail_v)] <- "Autres"
  
  if (niveau %in% c("large", "les_deux")) {
    df[[col_dest_large]] <- metier_large
  }
  if (niveau %in% c("detail", "les_deux")) {
    df[[col_dest_detail]] <- metier_detail_v
  }
  
  cols_crees <- c(
    if (niveau %in% c("large","les_deux")) col_dest_large,
    if (niveau %in% c("detail","les_deux")) col_dest_detail
  )
  shiny::showNotification(
    paste0("Colonne(s) métier créée(s) : ", paste(cols_crees, collapse=", ")),
    type = "message", duration = 4
  )
  df
}

# -----------------------------------------------------------------------------
# 5. FILTRES GÉNÉRIQUES
# -----------------------------------------------------------------------------

#' Applique une liste de filtres génériques sur n'importe quel data.frame.
#' filtres = list(list(col="nom", condition="eq", valeur="truc"), ...)
appliquer_filtres_data <- function(df, filtres) {
  if (is.null(df) || length(filtres) == 0) return(df)
  
  for (f in filtres) {
    col  <- f$col
    cond <- f$condition
    val  <- f$valeur
    if (!col %in% names(df)) next
    
    x <- df[[col]]
    keep <- switch(cond,
                   "eq"       = !is.na(x) & as.character(x) == as.character(val),
                   "neq"      = is.na(x)  | as.character(x) != as.character(val),
                   "contains" = grepl(val, as.character(x), ignore.case = TRUE),
                   "isna"     = is.na(x),
                   "notna"    = !is.na(x),
                   "gt"       = suppressWarnings(!is.na(as.numeric(x)) &
                                                   as.numeric(x) > as.numeric(val)),
                   "lt"       = suppressWarnings(!is.na(as.numeric(x)) &
                                                   as.numeric(x) < as.numeric(val)),
                   "in"       = as.character(x) %in% as.character(val),
                   "in_list"  = as.character(x) %in% as.character(val),
                   rep(TRUE, nrow(df))
    )
    df <- df[keep, , drop = FALSE]
  }
  df
}

# -----------------------------------------------------------------------------
# 6. FUSION (JOIN / BIND)
# -----------------------------------------------------------------------------

#' Fusion de deux data.frames
#' @param type "left","right","inner","full","rbind"
#' @param by   vecteur de colonnes clé (pour les joins)
fusionner_fichiers <- function(df1, df2, type = "left", by = NULL) {
  tryCatch({
    if (type == "rbind") {
      # Harmonise les types de df2 sur df1 (référentiel) avant l'empilement
      df2 <- harmoniser_types_avec(df2, df1)
      dplyr::bind_rows(df1, df2)
    } else {
      fn <- switch(type,
                   "left"  = dplyr::left_join,
                   "right" = dplyr::right_join,
                   "inner" = dplyr::inner_join,
                   "full"  = dplyr::full_join,
                   dplyr::left_join
      )
      fn(df1, df2, by = by)
    }
  }, error = function(e) {
    shiny::showNotification(
      paste("Erreur fusion :", e$message),
      type = "error", duration = 8
    )
    df1
  })
}

#' Harmonise les types des colonnes communes de df_cible avec df_ref.
#' Les colonnes absentes du référentiel sont laissées telles quelles (→ bind_rows les met en NA).
harmoniser_types_avec <- function(df_cible, df_ref) {
  cols_communes <- intersect(names(df_cible), names(df_ref))
  for (col in cols_communes) {
    ref_col <- df_ref[[col]]
    cib_col <- df_cible[[col]]
    tryCatch({
      df_cible[[col]] <- {
        if (inherits(ref_col, c("Date", "POSIXct", "POSIXlt"))) {
          tryCatch(parser_date(cib_col),
                   error = function(e) suppressWarnings(as.Date(as.character(cib_col))))
        } else if (is.numeric(ref_col)) {
          suppressWarnings(as.numeric(cib_col))
        } else if (is.factor(ref_col)) {
          as.factor(as.character(cib_col))
        } else if (is.logical(ref_col)) {
          suppressWarnings(as.logical(cib_col))
        } else if (is.character(ref_col)) {
          as.character(cib_col)
        } else {
          cib_col  # type inconnu, on ne touche pas
        }
      }
    }, error = function(e) {
      # Si la coercition plante on laisse la colonne telle quelle
      message("harmoniser_types_avec : impossible de convertir '", col, "' — ", e$message)
    })
  }
  df_cible
}

#' Empile une liste de data.frames (colonnes non communes → NA).
#' Les types des colonnes communes des fichiers secondaires sont forcés
#' sur ceux du fichier principal pour éviter les conflits de type.
#' @param liste_df  liste nommée ou non de data.frames
#' @return data.frame empilé + colonne ".source_fichier" si les df sont nommés
empiler_fichiers <- function(liste_df) {
  if (length(liste_df) == 0) return(NULL)
  tryCatch({
    # Forcer les types des fichiers secondaires sur le référentiel (1er fichier)
    if (length(liste_df) > 1) {
      liste_df[-1] <- lapply(liste_df[-1], function(df) {
        harmoniser_types_avec(df, liste_df[[1]])
      })
    }
    # Ajoute une colonne source si les df sont nommés
    noms <- names(liste_df)
    if (!is.null(noms) && all(nzchar(noms))) {
      liste_df <- lapply(seq_along(liste_df), function(i) {
        df <- liste_df[[i]]
        df$.source_fichier <- noms[i]
        df
      })
    }
    dplyr::bind_rows(liste_df)
  }, error = function(e) {
    shiny::showNotification(
      paste("Erreur empilement :", e$message),
      type = "error", duration = 8
    )
    liste_df[[1]]
  })
}

#' Fusionne deux colonnes : col1 a la priorité, col2 comble les NA de col1.
#' Résultat stocké dans col_dest (par défaut col1).
#' @param df       data.frame
#' @param col1     colonne prioritaire (sa valeur est conservée si non-NA)
#' @param col2     colonne secondaire (utilisée là où col1 est NA)
#' @param col_dest nom de la colonne résultat (défaut = col1)
#' @param suppr    TRUE pour supprimer col2 après fusion
fusionner_colonnes <- function(df, col1, col2,
                               col_dest = col1, suppr = TRUE) {
  if (!col1 %in% names(df) || !col2 %in% names(df)) {
    shiny::showNotification(
      paste0("Colonnes introuvables : '", col1, "' ou '", col2, "'"),
      type = "warning", duration = 5
    )
    return(df)
  }
  tryCatch({
    df[[col_dest]] <- dplyr::coalesce(df[[col1]], df[[col2]])
    if (suppr && col2 != col_dest) df[[col2]] <- NULL
    df
  }, error = function(e) {
    shiny::showNotification(
      paste("Erreur fusion colonnes :", e$message),
      type = "error", duration = 6
    )
    df
  })
}

# -----------------------------------------------------------------------------
# 6b. CRÉATION DE COLONNES TEMPORELLES
# -----------------------------------------------------------------------------

#' Crée une ou plusieurs colonnes temporelles depuis une colonne date.
#' @param df       data.frame
#' @param col_date nom de la colonne date source
#' @param ops      vecteur de noms d'opérations à appliquer parmi :
#'   "annee", "mois_num", "mois_label", "trimestre", "semestre",
#'   "semaine_iso", "jour_mois", "jour_semaine_num", "jour_semaine_label",
#'   "jour_annee", "date_tronquee_mois", "date_tronquee_trim",
#'   "date_tronquee_sem"
#' @return data.frame avec les nouvelles colonnes + attribut "cols_creees"
creer_colonnes_temporelles <- function(df, col_date, ops) {
  if (!col_date %in% names(df)) {
    shiny::showNotification(
      paste0("Colonne '", col_date, "' introuvable."),
      type = "error", duration = 5
    )
    return(df)
  }
  
  # Tentative de conversion en Date
  x_raw <- df[[col_date]]
  x <- tryCatch(
    parser_date(x_raw),
    error = function(e) suppressWarnings(as.Date(as.character(x_raw)))
  )
  
  if (all(is.na(x))) {
    shiny::showNotification(
      paste0("Impossible de convertir '", col_date,
             "' en Date. Vérifiez le format."),
      type = "error", duration = 6
    )
    return(df)
  }
  
  # Si la conversion a réussi (même partiellement), on écrase la colonne source
  df[[col_date]] <- x
  
  cols_creees <- character(0)
  
  for (op in ops) {
    nouveau_nom <- switch(op,
                          "annee"               = paste0(col_date, "_annee"),
                          "mois_num"            = paste0(col_date, "_mois"),
                          "mois_label"          = paste0(col_date, "_mois_label"),
                          "trimestre"           = paste0(col_date, "_trim"),
                          "semestre"            = paste0(col_date, "_sem"),
                          "semaine_iso"         = paste0(col_date, "_semaine"),
                          "jour_mois"           = paste0(col_date, "_jour"),
                          "jour_semaine_num"    = paste0(col_date, "_jdm_num"),
                          "jour_semaine_label"  = paste0(col_date, "_jdm_label"),
                          "jour_annee"          = paste0(col_date, "_jda"),
                          "date_tronquee_mois"  = paste0(col_date, "_tronc_mois"),
                          "date_tronquee_trim"  = paste0(col_date, "_tronc_trim"),
                          "date_tronquee_sem"   = paste0(col_date, "_tronc_sem"),
                          op
    )
    
    valeur <- tryCatch(switch(op,
                              "annee"               = lubridate::year(x),
                              "mois_num"            = lubridate::month(x),
                              "mois_label"          = lubridate::month(x, label = TRUE, abbr = FALSE,
                                                                       locale = "fr_FR.UTF-8") |>
                                as.character(),
                              "trimestre"           = lubridate::quarter(x),
                              "semestre"            = ifelse(lubridate::month(x) <= 6, 1L, 2L),
                              "semaine_iso"         = lubridate::isoweek(x),
                              "jour_mois"           = lubridate::mday(x),
                              "jour_semaine_num"    = lubridate::wday(x, week_start = 1),
                              "jour_semaine_label"  = lubridate::wday(x, label = TRUE, abbr = FALSE,
                                                                      locale = "fr_FR.UTF-8") |>
                                as.character(),
                              "jour_annee"          = lubridate::yday(x),
                              "date_tronquee_mois"  = lubridate::floor_date(x, "month"),
                              "date_tronquee_trim"  = lubridate::floor_date(x, "quarter"),
                              "date_tronquee_sem"   = lubridate::floor_date(x, "week",
                                                                            week_start = 1),
                              NULL
    ), error = function(e) NULL)
    
    if (!is.null(valeur)) {
      df[[nouveau_nom]] <- valeur
      cols_creees <- c(cols_creees, nouveau_nom)
    }
  }
  
  attr(df, "cols_creees") <- cols_creees
  df
}

#' Labels lisibles pour les opérations temporelles (pour l'UI)
LABELS_OPS_TEMP <- c(
  "annee"              = "Année (numérique)",
  "mois_num"           = "Mois (numérique 1–12)",
  "mois_label"         = "Mois (libellé : Janvier…)",
  "trimestre"          = "Trimestre (1–4)",
  "semestre"           = "Semestre (1–2)",
  "semaine_iso"        = "Semaine ISO (1–53)",
  "jour_mois"          = "Jour du mois (1–31)",
  "jour_semaine_num"   = "Jour de la semaine (1=Lun, 7=Dim)",
  "jour_semaine_label" = "Jour de la semaine (libellé : Lundi…)",
  "jour_annee"         = "Jour de l'année (1–366)",
  "date_tronquee_mois" = "Date tronquée au 1er du mois",
  "date_tronquee_trim" = "Date tronquée au 1er du trimestre",
  "date_tronquee_sem"  = "Date tronquée au lundi de la semaine"
)

# -----------------------------------------------------------------------------
# 7. REGISTRE DES ROUTINES DE TRAITEMENT
# -----------------------------------------------------------------------------
# Pour ajouter une nouvelle routine :
#   1. Définissez une fonction R : routine_<id> <- function(df) { ... ; attr(df,"ops_routine") <- ops ; df }
#   2. Ajoutez une entrée dans ROUTINES_DISPONIBLES :
#        list(id="<id>", label="Nom affiché", description=c("Étape 1","Étape 2",...))
# C'est tout — l'UI et le serveur la détecteront automatiquement.
# -----------------------------------------------------------------------------

ROUTINES_DISPONIBLES <- list(
  
  list(
    id          = "halieut_standard",
    label       = "Routine halieutique standard",
    description = c(
      "Parsing automatique des colonnes date (date, date_maree…) → an_ref, mois_ref, trim_ref",
      "Calcul de la colonne Nord/Sud (NS) depuis div_ciem_cod_sipa",
      "Calcul de la CPUE (kg/JdM) si debarquement_Kg et duree_maree présents",
      "Calcul du prix moyen (€/kg) si debarquement_Kg et debarquement_euros présents",
      "Conversion des colonnes _cod/_code en facteur + suppression des doublons"
    )
  )
  
  # ── Ajoutez vos routines ici ──────────────────────────────────────────────
  # ,list(
  #   id          = "ma_routine",
  #   label       = "Ma routine personnalisée",
  #   description = c("Étape 1 : ...", "Étape 2 : ...", "Étape 3 : ...")
  # )
  # ─────────────────────────────────────────────────────────────────────────
  
)

#' Applique la routine identifiée par `id` sur `df`
#' Retourne df avec attribut "ops_routine" (vecteur de messages)
appliquer_routine <- function(df, id) {
  fn_name <- paste0("routine_", id)
  if (exists(fn_name, mode = "function")) {
    fn <- get(fn_name)
    return(fn(df))
  }
  # Routine non trouvée
  shiny::showNotification(paste0("Routine '", id, "' introuvable."),
                          type = "error", duration = 5)
  df
}

# ── Implémentation : routine halieutique standard ──────────────────────────

routine_halieut_standard <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  
  ops <- character(0)
  
  # 1. Parsing dates
  col_date <- intersect(
    c("date","Date","DATE","date_maree","date_debarque"), names(df)
  )
  if (length(col_date) > 0) {
    cd <- col_date[1]
    df[[cd]]    <- parser_date(df[[cd]])
    df$an_ref   <- lubridate::year(df[[cd]])
    df$mois_ref <- lubridate::month(df[[cd]])
    df$trim_ref <- lubridate::quarter(df[[cd]])
    ops <- c(ops, paste0("Date parsée ('", cd, "') → an_ref, mois_ref, trim_ref"))
  }
  
  # 2. Nord/Sud
  df <- ajouter_ns(df)
  if ("NS" %in% names(df)) ops <- c(ops, "Colonne NS (Nord/Sud) calculée")
  
  # 3. CPUE
  if (all(c("debarquement_Kg", "duree_maree") %in% names(df))) {
    deb_kg  <- suppressWarnings(as.numeric(df$debarquement_Kg))
    dur_mar <- suppressWarnings(as.numeric(df$duree_maree))
    df$cpue_kg_jdm <- ifelse(!is.na(dur_mar) & dur_mar > 0,
                             deb_kg / dur_mar, NA_real_)
    ops <- c(ops, "CPUE (kg/JdM) calculée")
  }
  
  # 4. Prix moyen
  if (all(c("debarquement_Kg", "debarquement_euros") %in% names(df))) {
    deb_kg  <- suppressWarnings(as.numeric(df$debarquement_Kg))
    deb_eur <- suppressWarnings(as.numeric(df$debarquement_euros))
    df$prix_moyen_kg <- ifelse(!is.na(deb_kg) & deb_kg > 0,
                               deb_eur / deb_kg, NA_real_)
    ops <- c(ops, "Prix moyen (€/kg) calculé")
  }
  
  # 5. Nettoyage types + doublons
  cols_code <- grep("_cod$|_code$|^esp_|^engin|^port|^zone|^quartier",
                    names(df), value = TRUE)
  for (col in cols_code) {
    if (is.character(df[[col]])) df[[col]] <- as.factor(df[[col]])
  }
  if (length(cols_code) > 0)
    ops <- c(ops, paste0("Types ajustés : ", paste(cols_code, collapse = ", ")))
  
  n_before <- nrow(df)
  df <- dplyr::distinct(df)
  if (nrow(df) < n_before)
    ops <- c(ops, paste0(n_before - nrow(df), " doublons supprimés"))
  
  attr(df, "ops_routine") <- ops
  df
}

# Alias de compatibilité (anciens appels éventuels)
appliquer_routine_halieut <- function(df) routine_halieut_standard(df)

# ── Ajoutez ici les implémentations de vos nouvelles routines ─────────────
# routine_ma_routine <- function(df) {
#   ops <- character(0)
#   # ... vos traitements ...
#   attr(df, "ops_routine") <- ops
#   df
# }

# -----------------------------------------------------------------------------
# 8. EXPORT
# -----------------------------------------------------------------------------

exporter_xlsx_data <- function(df, file) {
  df <- .forcer_character_post(df)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Données")
  openxlsx::writeDataTable(wb, 1, df, tableStyle = "TableStyleMedium9")
  openxlsx::addStyle(wb, 1,
                     style = openxlsx::createStyle(
                       fontColour = "#FFFFFF", fgFill = "#0077B6",
                       halign = "center", textDecoration = "bold"
                     ),
                     rows = 1, cols = 1:ncol(df), gridExpand = TRUE
  )
  openxlsx::setColWidths(wb, 1, cols = 1:ncol(df), widths = "auto")
  openxlsx::saveWorkbook(wb, file, overwrite = TRUE)
}

# =============================================================================
# 8b. EXPORT DÉCOUPÉ PAR VARIABLE — helpers
# =============================================================================

# Clés de découpage reconnues et leurs patterns de détection
DECOUPAGE_CONFIGS <- list(
  
  annee = list(
    id          = "annee",
    label       = "Par année",
    description = "Un fichier par année (an_ref / date_annee)",
    patterns    = c("an_ref", "date_annee", "annee", "year"),
    suffixe_fn  = function(val) as.character(val),   # ex: "2023"
    combo       = FALSE
  ),
  
  mois = list(
    id          = "mois",
    label       = "Par mois",
    description = "Un fichier par mois (mois_ref / date_mois)",
    patterns    = c("mois_ref", "date_mois", "mois", "month"),
    suffixe_fn  = function(val) sprintf("%02d", as.integer(val)),   # ex: "03"
    combo       = FALSE
  ),
  
  espece = list(
    id          = "espece",
    label       = "Par espèce",
    description = "Un fichier par code espèce FAO (esp_cod_fao)",
    patterns    = c("esp_cod_fao", "esp_cod", "espece_cod", "species_cod"),
    suffixe_fn  = function(val) as.character(val),
    combo       = FALSE
  ),
  
  quartier = list(
    id          = "quartier",
    label       = "Par quartier",
    description = "Un fichier par quartier (quartier_cod / quartier)",
    patterns    = c("quartier_cod", "quartier", "port_quartier_cod"),
    suffixe_fn  = function(val) as.character(val),
    combo       = FALSE
  ),
  
  mois_annee = list(
    id          = "mois_annee",
    label       = "Par mois × année",
    description = "Un fichier par combinaison mois + année",
    patterns    = NULL,   # combinaison spéciale
    suffixe_fn  = function(val) val,   # val déjà formaté en "2023_03"
    combo       = TRUE
  )
  
)

#' Détecte la première colonne d'un df correspondant aux patterns d'un découpage
#' @param df   data.frame
#' @param patterns vecteur de noms exacts ou regex à tester (insensible à la casse)
#' @return nom de colonne trouvé ou NULL
.detecter_col_decoupage <- function(df, patterns) {
  noms <- names(df)
  for (p in patterns) {
    hits <- noms[tolower(noms) == tolower(p)]
    if (length(hits) > 0) return(hits[1])
  }
  NULL
}

#' Vérifie quels découpages sont disponibles sur un df donné.
#' Retourne une liste nommée par id : TRUE si la colonne est présente, FALSE sinon.
#' @param df data.frame
verifier_decoupages_disponibles <- function(df) {
  if (is.null(df)) return(list())
  
  res <- lapply(DECOUPAGE_CONFIGS, function(cfg) {
    if (cfg$combo) {
      # mois_annee : nécessite une colonne année ET une colonne mois
      col_an   <- .detecter_col_decoupage(df, DECOUPAGE_CONFIGS$annee$patterns)
      col_mois <- .detecter_col_decoupage(df, DECOUPAGE_CONFIGS$mois$patterns)
      list(dispo = !is.null(col_an) && !is.null(col_mois),
           col_an = col_an, col_mois = col_mois)
    } else {
      col <- .detecter_col_decoupage(df, cfg$patterns)
      list(dispo = !is.null(col), col = col)
    }
  })
  res
}

#' Découpe un df selon un type de découpage et exporte les morceaux en xlsx
#' dans un dossier temporaire, puis zippe le tout.
#'
#' @param df         data.frame source
#' @param type_dec   identifiant du découpage ("annee","mois","espece","quartier","mois_annee")
#' @param prefixe    préfixe du nom de fichier choisi par l'utilisateur (ex: "MAC")
#' @param zip_dest   chemin du zip de sortie (fourni par downloadHandler)
#' @return invisible NULL — effets de bord : crée le zip à zip_dest
exporter_decoupage_zip <- function(df, type_dec, prefixe, zip_dest) {
  
  cfg     <- DECOUPAGE_CONFIGS[[type_dec]]
  dispo   <- verifier_decoupages_disponibles(df)[[type_dec]]
  
  if (!dispo$dispo) {
    stop(paste0("Découpage '", type_dec, "' impossible : colonne(s) requise(s) absente(s)."))
  }
  
  # Créer un dossier temporaire propre
  tmp_dir <- file.path(tempdir(), paste0("export_", type_dec, "_", format(Sys.time(), "%H%M%S")))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  
  # --- Construire la liste de morceaux (valeur_decoupage -> sous-df) ---
  if (type_dec == "mois_annee") {
    col_an   <- dispo$col_an
    col_mois <- dispo$col_mois
    val_an   <- sort(unique(na.omit(df[[col_an]])))
    
    # Si une seule année : découper uniquement par mois (pas de préfixe année)
    multi_annee <- length(val_an) > 1
    
    morceaux <- list()
    for (an in val_an) {
      df_an <- df[!is.na(df[[col_an]]) & df[[col_an]] == an, , drop = FALSE]
      val_mois_an <- sort(unique(na.omit(df_an[[col_mois]])))
      for (mo in val_mois_an) {
        df_mo <- df_an[!is.na(df_an[[col_mois]]) & df_an[[col_mois]] == mo, , drop = FALSE]
        suffixe <- if (multi_annee)
          paste0(as.character(an), "_", sprintf("%02d", as.integer(mo)))
        else
          sprintf("%02d", as.integer(mo))
        morceaux[[suffixe]] <- df_mo
      }
    }
    
  } else {
    col     <- dispo$col
    valeurs <- sort(unique(na.omit(df[[col]])))
    morceaux <- stats::setNames(
      lapply(valeurs, function(v) df[!is.na(df[[col]]) & df[[col]] == v, , drop = FALSE]),
      vapply(valeurs, cfg$suffixe_fn, character(1))
    )
  }
  
  if (length(morceaux) == 0) stop("Aucune donnée à exporter après découpage.")
  
  # --- Écrire chaque morceau en xlsx ---
  fichiers_crees <- character(0)
  for (suffixe in names(morceaux)) {
    nom_fichier <- paste0(prefixe, "_", suffixe, ".xlsx")
    chemin      <- file.path(tmp_dir, nom_fichier)
    exporter_xlsx_data(morceaux[[suffixe]], chemin)
    fichiers_crees <- c(fichiers_crees, chemin)
  }
  
  # --- Zipper ---
  old_wd <- getwd()
  on.exit({ setwd(old_wd) }, add = TRUE)
  setwd(tmp_dir)
  utils::zip(zip_dest, files = basename(fichiers_crees), flags = "-r9X")
  
  invisible(NULL)
}

#' Label résumé du découpage pour affichage dans l'UI (nb de valeurs uniques, colonne détectée)
label_decoupage_info <- function(df, type_dec) {
  if (is.null(df)) return("")
  dispo <- verifier_decoupages_disponibles(df)[[type_dec]]
  if (!dispo$dispo) return("— colonne non trouvée dans le jeu de données")
  
  if (type_dec == "mois_annee") {
    col_an   <- dispo$col_an
    col_mois <- dispo$col_mois
    n_an  <- dplyr::n_distinct(df[[col_an]], na.rm = TRUE)
    n_mo  <- dplyr::n_distinct(df[[col_mois]], na.rm = TRUE)
    n_combo <- dplyr::n_distinct(
      paste(df[[col_an]], df[[col_mois]]), na.rm = TRUE
    )
    sprintf("Colonnes : %s × %s — %s année(s), %s mois unique(s), %s fichier(s) à créer",
            col_an, col_mois, n_an, n_mo, n_combo)
  } else {
    col <- dispo$col
    n   <- dplyr::n_distinct(df[[col]], na.rm = TRUE)
    sprintf("Colonne détectée : %s — %s valeur(s) unique(s) → %s fichier(s)", col, n, n)
  }
}

# =============================================================================
# 8c. EXPORTS ESPÈCES SPÉCIFIQUES — MAC / POL / SOL
# =============================================================================

# Patterns communs réutilisés dans les routines espèces
.PATTERNS_ESP  <- c("esp_cod_fao", "esp_cod", "espece_cod", "species_cod")
.PATTERNS_AN   <- c("an_ref", "date_annee", "annee", "year")
.PATTERNS_MOIS <- c("mois_ref", "date_mois", "mois", "month")
.PATTERNS_CIEM <- c("div_ciem_cod_sipa", "zone_ciem", "div_ciem", "ciem_cod")

# Patterns CIEM pour Nord (27.7.x) et Sud (27.8.x)
.PATTERN_NORD <- "^27\\.7"
.PATTERN_SUD  <- "^27\\.8"

#' Détecte la colonne espèce dans un df (retourne NULL si absente)
.col_espece <- function(df) .detecter_col_decoupage(df, .PATTERNS_ESP)

#' Détecte la colonne CIEM dans un df (retourne NULL si absente)
.col_ciem <- function(df) .detecter_col_decoupage(df, .PATTERNS_CIEM)

#' Ajoute la colonne mois numérique si absente, en la déduisant d'une colonne date existante.
#' Retourne le df (modifié ou non) + le nom de la colonne mois utilisée.
.assurer_col_mois <- function(df) {
  col_mois <- .detecter_col_decoupage(df, .PATTERNS_MOIS)
  if (!is.null(col_mois)) return(list(df = df, col = col_mois, creee = FALSE))
  
  # Chercher une colonne date source
  col_date <- .detecter_col_decoupage(df,
                                      c("date", "Date", "DATE", "date_maree", "date_debarque"))
  if (!is.null(col_date)) {
    x <- df[[col_date]]
    if (!inherits(x, c("Date", "POSIXct", "POSIXlt"))) {
      x <- tryCatch(parser_date(x), error = function(e) NULL)
    }
    if (!is.null(x)) {
      df$mois_ref <- lubridate::month(x)
      return(list(df = df, col = "mois_ref", creee = TRUE))
    }
  }
  list(df = df, col = NULL, creee = FALSE)
}

#' Ajoute la colonne semestre numérique si absente.
#' Retourne le df + nom colonne semestre.
.assurer_col_semestre <- function(df) {
  col_sem <- .detecter_col_decoupage(df,
                                     c("semestre", "sem_ref", "semester"))
  if (!is.null(col_sem)) return(list(df = df, col = col_sem, creee = FALSE))
  
  # Construire depuis mois
  r <- .assurer_col_mois(df)
  df      <- r$df
  col_mo  <- r$col
  if (!is.null(col_mo)) {
    df$semestre <- ifelse(as.integer(df[[col_mo]]) <= 6, 1L, 2L)
    return(list(df = df, col = "semestre", creee = TRUE))
  }
  list(df = df, col = NULL, creee = FALSE)
}

#' Filtre un df pour ne garder que les lignes d'une espèce donnée.
#' Retourne NULL si la colonne espèce est introuvable ou si aucune ligne ne correspond.
.filtrer_espece <- function(df, code_fao) {
  col <- .col_espece(df)
  if (is.null(col)) return(NULL)
  res <- df[!is.na(df[[col]]) & as.character(df[[col]]) == code_fao, , drop = FALSE]
  if (nrow(res) == 0) return(NULL)
  res
}

#' Applique un découpage par année sur un sous-df.
#' Retourne une liste nommée suffixe -> df, ou list() si la colonne année est absente.
.morceaux_par_annee <- function(df, prefixe) {
  col_an <- .detecter_col_decoupage(df, .PATTERNS_AN)
  if (is.null(col_an)) return(list())
  valeurs <- sort(unique(na.omit(df[[col_an]])))
  stats::setNames(
    lapply(valeurs, function(v)
      df[!is.na(df[[col_an]]) & df[[col_an]] == v, , drop = FALSE]),
    paste0(prefixe, "_", as.character(valeurs))
  )
}

#' Segmente un df en Nord / Sud / complet selon la colonne CIEM.
#' Retourne une liste nommée (complet, nord, sud).
.segmenter_ns <- function(df, prefixe) {
  col_ciem <- .col_ciem(df)
  res <- list()
  res[[prefixe]] <- df   # fichier complet toujours présent
  
  if (!is.null(col_ciem)) {
    ciem_chr <- as.character(df[[col_ciem]])
    idx_nord <- !is.na(ciem_chr) & grepl(.PATTERN_NORD, ciem_chr)
    idx_sud  <- !is.na(ciem_chr) & grepl(.PATTERN_SUD,  ciem_chr)
    if (any(idx_nord)) res[[paste0(prefixe, "_Nord")]] <- df[idx_nord, , drop = FALSE]
    if (any(idx_sud))  res[[paste0(prefixe, "_Sud")]]  <- df[idx_sud,  , drop = FALSE]
  }
  res
}

# ── Vérification disponibilité ────────────────────────────────────────────────

#' Indique si un export espèce-spécifique est réalisable sur le df.
#' @param df        data.frame
#' @param code_fao  "MAC", "POL" ou "SOL"
#' @return list(dispo, message, n_lignes)
verifier_export_espece <- function(df, code_fao) {
  if (is.null(df) || nrow(df) == 0)
    return(list(dispo = FALSE, message = "Aucune donnée chargée.", n_lignes = 0L))
  
  col_esp <- .col_espece(df)
  if (is.null(col_esp))
    return(list(dispo = FALSE,
                message = "Colonne espèce introuvable (esp_cod_fao…).",
                n_lignes = 0L))
  
  df_esp <- .filtrer_espece(df, code_fao)
  n <- if (is.null(df_esp)) 0L else nrow(df_esp)
  if (n == 0L)
    return(list(dispo = FALSE,
                message = sprintf("Aucune ligne '%s' dans la colonne %s.", code_fao, col_esp),
                n_lignes = 0L))
  
  extras <- character(0)
  col_an   <- .detecter_col_decoupage(df_esp, .PATTERNS_AN)
  col_ciem <- .col_ciem(df_esp)
  
  if (!is.null(col_an))   extras <- c(extras, paste0("année via ", col_an))
  if (!is.null(col_ciem)) extras <- c(extras, paste0("CIEM via ", col_ciem))
  if (code_fao %in% c("POL","SOL")) {
    col_mo <- .detecter_col_decoupage(df_esp, .PATTERNS_MOIS)
    if (!is.null(col_mo)) extras <- c(extras, paste0("mois via ", col_mo))
    else extras <- c(extras, "mois (sera créé depuis date)")
  }
  if (code_fao == "SOL") {
    col_sem <- .detecter_col_decoupage(df_esp, c("semestre","sem_ref","semester"))
    if (!is.null(col_sem)) extras <- c(extras, paste0("semestre via ", col_sem))
    else extras <- c(extras, "semestre (sera créé depuis mois)")
  }
  
  list(
    dispo    = TRUE,
    message  = sprintf("%s ligne(s) — colonnes : %s",
                       format(n, big.mark = "\u202f"),
                       if (length(extras) > 0) paste(extras, collapse = ", ") else "basiques"),
    n_lignes = n
  )
}

# ── Fonctions d'export ────────────────────────────────────────────────────────

#' Export MAC : filtre MAC, découpe par année, un xlsx par année + zip.
exporter_mac <- function(df, zip_dest) {
  df_mac <- .filtrer_espece(df, "MAC")
  if (is.null(df_mac)) stop("Aucune ligne MAC trouvée.")
  
  tmp_dir <- file.path(tempdir(), paste0("export_MAC_", format(Sys.time(), "%H%M%S")))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  old_wd <- getwd()
  on.exit({ setwd(old_wd); unlink(tmp_dir, recursive = TRUE) }, add = TRUE)
  
  morceaux <- .morceaux_par_annee(df_mac, "MAC")
  
  # Si pas de colonne année : un seul fichier MAC complet
  if (length(morceaux) == 0) morceaux <- list(MAC = df_mac)
  
  fichiers <- character(0)
  for (nm in names(morceaux)) {
    f <- file.path(tmp_dir, paste0(nm, ".xlsx"))
    exporter_xlsx_data(morceaux[[nm]], f)
    fichiers <- c(fichiers, f)
  }
  
  setwd(tmp_dir)
  utils::zip(zip_dest, files = basename(fichiers), flags = "-r9X")
  invisible(NULL)
}

#' Export POL : filtre POL, assure colonne mois, segmente Nord/Sud, découpe par année.
#' Structure du zip :
#'   POL_<YYYY>.xlsx          (complet par année)
#'   POL_Nord_<YYYY>.xlsx     (si CIEM disponible)
#'   POL_Sud_<YYYY>.xlsx      (si CIEM disponible)
exporter_pol <- function(df, zip_dest) {
  df_pol <- .filtrer_espece(df, "POL")
  if (is.null(df_pol)) stop("Aucune ligne POL trouvée.")
  
  # Ajouter colonne mois si absente
  r <- .assurer_col_mois(df_pol)
  df_pol <- r$df
  
  tmp_dir <- file.path(tempdir(), paste0("export_POL_", format(Sys.time(), "%H%M%S")))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  old_wd <- getwd()
  on.exit({ setwd(old_wd); unlink(tmp_dir, recursive = TRUE) }, add = TRUE)
  
  # Segments (complet + Nord + Sud)
  segments <- .segmenter_ns(df_pol, "POL")
  
  fichiers <- character(0)
  for (seg_nom in names(segments)) {
    morceaux <- .morceaux_par_annee(segments[[seg_nom]], seg_nom)
    if (length(morceaux) == 0) morceaux <- stats::setNames(list(segments[[seg_nom]]), seg_nom)
    for (nm in names(morceaux)) {
      f <- file.path(tmp_dir, paste0(nm, ".xlsx"))
      exporter_xlsx_data(morceaux[[nm]], f)
      fichiers <- c(fichiers, f)
    }
  }
  
  setwd(tmp_dir)
  utils::zip(zip_dest, files = basename(fichiers), flags = "-r9X")
  invisible(NULL)
}

#' Export SOL : filtre SOL, assure colonne mois + semestre, segmente Nord/Sud, découpe par année.
#' Structure du zip :
#'   SOL_<YYYY>.xlsx          (complet par année)
#'   SOL_Nord_<YYYY>.xlsx     (si CIEM disponible)
#'   SOL_Sud_<YYYY>.xlsx      (si CIEM disponible)
exporter_sol <- function(df, zip_dest) {
  df_sol <- .filtrer_espece(df, "SOL")
  if (is.null(df_sol)) stop("Aucune ligne SOL trouvée.")
  
  # Ajouter colonne mois si absente, puis semestre
  r <- .assurer_col_semestre(df_sol)
  df_sol <- r$df
  
  tmp_dir <- file.path(tempdir(), paste0("export_SOL_", format(Sys.time(), "%H%M%S")))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  old_wd <- getwd()
  on.exit({ setwd(old_wd); unlink(tmp_dir, recursive = TRUE) }, add = TRUE)
  
  # Segments (complet + Nord + Sud)
  segments <- .segmenter_ns(df_sol, "SOL")
  
  fichiers <- character(0)
  for (seg_nom in names(segments)) {
    morceaux <- .morceaux_par_annee(segments[[seg_nom]], seg_nom)
    if (length(morceaux) == 0) morceaux <- stats::setNames(list(segments[[seg_nom]]), seg_nom)
    for (nm in names(morceaux)) {
      f <- file.path(tmp_dir, paste0(nm, ".xlsx"))
      exporter_xlsx_data(morceaux[[nm]], f)
      fichiers <- c(fichiers, f)
    }
  }
  
  setwd(tmp_dir)
  utils::zip(zip_dest, files = basename(fichiers), flags = "-r9X")
  invisible(NULL)
}

# =============================================================================
# 9. CORRECTION DE LA DONNÉE ENGIN (cohérence engin/espèce)
# =============================================================================

# Chemin par défaut du fichier base des incohérences connues, livré dans www/
# (modifié/remplacé par l'admin au moment de compiler l'app)
CHEMIN_BASE_INCOHERENCES <- file.path("www", "base_incoherences_engins.xlsx")

# Colonnes attendues dans le fichier base des incohérences
COLS_BASE_INCOHERENCES <- c("nom_navire", "cfr_cod", "quartier_cod",
                            "esp_cod_fao", "engin_cod", "engin_corrige")

#' Charge la base des incohérences connues (fichier www/), avec gestion
#' du cas où le fichier n'existe pas encore (première utilisation)
#' @param chemin chemin vers le fichier xlsx (par défaut CHEMIN_BASE_INCOHERENCES)
charger_base_incoherences <- function(chemin = CHEMIN_BASE_INCOHERENCES) {
  if (!file.exists(chemin)) {
    return(stats::setNames(
      data.frame(matrix(ncol = length(COLS_BASE_INCOHERENCES), nrow = 0)),
      COLS_BASE_INCOHERENCES
    ))
  }
  tryCatch({
    base <- openxlsx::read.xlsx(chemin, sheet = 1)
    # S'assure que toutes les colonnes attendues sont présentes
    manquantes <- setdiff(COLS_BASE_INCOHERENCES, names(base))
    for (col in manquantes) base[[col]] <- NA_character_
    # Tout en character pour un matching fiable (évite les soucis factor/numeric)
    for (col in COLS_BASE_INCOHERENCES) base[[col]] <- as.character(base[[col]])
    base[, COLS_BASE_INCOHERENCES, drop = FALSE]
  }, error = function(e) {
    shiny::showNotification(
      paste("Erreur lecture base incohérences :", e$message),
      type = "error", duration = 8
    )
    stats::setNames(
      data.frame(matrix(ncol = length(COLS_BASE_INCOHERENCES), nrow = 0)),
      COLS_BASE_INCOHERENCES
    )
  })
}

#' Détecte les couples (navire, espèce, engin) incohérents dans un jeu de
#' données, au regard d'une table de référence engins cohérents par espèce
#' (même structure que SQ_ENGINS_COHERENTS du module Suivi des quotas :
#' liste nommée par code espèce FAO, chaque élément ayant un $coherents).
#'
#' Logique : pour un couple (navire, espèce) donné, TOUTES les lignes de ce
#' couple sont extraites dès qu'AU MOINS UNE ligne porte un engin non listé
#' comme cohérent pour cette espèce. Une ligne d'export = une combinaison
#' distincte (navire, cfr, quartier, espèce, engin incohérent).
#'
#' @param df          data.frame mappé (colonnes nom_navire, cfr_cod,
#'                     quartier_cod, esp_cod_fao, engin_cod)
#' @param engins_ref   liste nommée par espèce, type SQ_ENGINS_COHERENTS
#' @return data.frame des combinaisons distinctes navire/espèce/engin incohérentes
detecter_incoherences_engin <- function(df, engins_ref) {
  req_cols <- c("nom_navire", "cfr_cod", "quartier_cod", "esp_cod_fao", "engin_cod")
  manquantes <- setdiff(req_cols, names(df))
  if (length(manquantes) > 0) {
    stop(paste("Colonnes manquantes pour la détection :", paste(manquantes, collapse = ", ")))
  }
  
  df <- df[, req_cols, drop = FALSE]
  for (col in req_cols) df[[col]] <- as.character(df[[col]])
  
  especes_dispo <- intersect(unique(df$esp_cod_fao), names(engins_ref))
  if (length(especes_dispo) == 0) {
    return(stats::setNames(
      data.frame(matrix(ncol = length(req_cols), nrow = 0)),
      req_cols
    ))
  }
  
  res <- lapply(especes_dispo, function(sp) {
    coherents <- engins_ref[[sp]]$coherents %||% character(0)
    df_sp <- df[df$esp_cod_fao == sp, , drop = FALSE]
    df_sp[!(df_sp$engin_cod %in% coherents), , drop = FALSE]
  })
  
  df_incoh <- do.call(rbind, res)
  if (is.null(df_incoh) || nrow(df_incoh) == 0) {
    return(stats::setNames(
      data.frame(matrix(ncol = length(req_cols), nrow = 0)),
      req_cols
    ))
  }
  
  unique(df_incoh)
}

#' Compare les incohérences détectées à la base connue et isole celles
#' qui ne sont PAS encore référencées (à exporter pour l'admin).
#' Clé de matching : nom_navire + cfr_cod + esp_cod_fao + engin_cod.
#'
#' @param df_incoh data.frame issu de detecter_incoherences_engin()
#' @param base     data.frame issu de charger_base_incoherences()
#' @return data.frame des incohérences nouvelles, non présentes dans la base
incoherences_non_referencees <- function(df_incoh, base) {
  if (nrow(df_incoh) == 0) {
    return(df_incoh)
  }
  cle_incoh <- paste(df_incoh$nom_navire, df_incoh$cfr_cod,
                     df_incoh$esp_cod_fao, df_incoh$engin_cod, sep = "|||")
  cle_base  <- if (nrow(base) > 0) {
    paste(base$nom_navire, base$cfr_cod,
          base$esp_cod_fao, base$engin_cod, sep = "|||")
  } else character(0)
  
  df_incoh[!(cle_incoh %in% cle_base), , drop = FALSE]
}

#' Construit la colonne engin_sug (engin suggéré) à partir des données,
#' de la liste des engins cohérents par espèce et de la base de
#' corrections connues.
#'
#' Règles :
#' - navire cohérent sur cette espèce (engin déjà dans la liste cohérente)
#'   -> engin_sug = engin_cod (inchangé, sans étoile)
#' - navire incohérent, présent dans la base, "engin_corrige" rempli
#'   -> engin_sug = engin_corrige (même si identique à engin_cod : le cas
#'      "le vrai engin est bien celui-ci" est géré ainsi, sans étoile)
#' - navire incohérent, présent dans la base, "engin_corrige" vide (NA)
#'   -> engin_sug = engin_cod suffixé d'une étoile ("OTB*"), pour signaler
#'      une incohérence connue mais pas encore corrigée
#' - navire incohérent, absent de la base (pas encore traité par l'admin)
#'   -> engin_sug = engin_cod suffixé d'une étoile, même traitement que
#'      ci-dessus en attendant l'ajout à la base
#'
#' @param df         data.frame mappé (colonnes nom_navire, cfr_cod,
#'                    quartier_cod, esp_cod_fao, engin_cod)
#' @param engins_ref  liste nommée par espèce, type SQ_ENGINS_COHERENTS
#' @param base       data.frame issu de charger_base_incoherences()
#' @return df d'origine avec une colonne supplémentaire engin_sug
construire_engin_suggere <- function(df, engins_ref, base) {
  req_cols <- c("nom_navire", "cfr_cod", "esp_cod_fao", "engin_cod")
  manquantes <- setdiff(req_cols, names(df))
  if (length(manquantes) > 0) {
    stop(paste("Colonnes manquantes pour engin_sug :", paste(manquantes, collapse = ", ")))
  }
  
  nom_navire_chr <- as.character(df$nom_navire)
  cfr_cod_chr    <- as.character(df$cfr_cod)
  esp_cod_chr    <- as.character(df$esp_cod_fao)
  engin_cod_chr  <- as.character(df$engin_cod)
  
  # Cohérence ligne à ligne : engin déjà dans la liste cohérente de l'espèce ?
  est_coherent <- vapply(seq_len(nrow(df)), function(i) {
    sp <- esp_cod_chr[i]
    coherents <- engins_ref[[sp]]$coherents %||% character(0)
    engin_cod_chr[i] %in% coherents
  }, logical(1))
  
  # Clé de correspondance avec la base de corrections connues
  cle_lignes <- paste(nom_navire_chr, cfr_cod_chr, esp_cod_chr, engin_cod_chr, sep = "|||")
  cle_base   <- if (nrow(base) > 0) {
    paste(base$nom_navire, base$cfr_cod, base$esp_cod_fao, base$engin_cod, sep = "|||")
  } else character(0)
  idx_base   <- match(cle_lignes, cle_base)
  
  engin_corrige_match <- if (nrow(base) > 0) base$engin_corrige[idx_base] else rep(NA_character_, nrow(df))
  
  engin_sug <- ifelse(
    est_coherent,
    engin_cod_chr,                                                      # cohérent -> inchangé
    ifelse(
      !is.na(engin_corrige_match) & nzchar(engin_corrige_match),
      engin_corrige_match,                                              # incohérent + corrigé -> engin corrigé
      paste0(engin_cod_chr, "*")                                        # incohérent + pas (encore) corrigé -> étoile
    )
  )
  
  df$engin_sug <- engin_sug
  df
}