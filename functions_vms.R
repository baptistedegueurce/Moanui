# =============================================================================
# functions_vms.R — Fonctions utilitaires onglet VMS
# =============================================================================

# -----------------------------------------------------------------------------
# 0. CACHE RASTER (session-level, évite de recharger le même .tif N fois)
# -----------------------------------------------------------------------------
# On utilise un environnement simple comme cache clé→valeur pour éviter
# de dépendre du package memoise (pas toujours installé).
.raster_cache <- new.env(parent = emptyenv())
# Cache des tuiles déjà converties en raster R (hex_mat → as.raster)
# Clé = chemin fichier + "_" + target_px. Évite de re-convertir la même
# tuile pour des mois qui partagent le même jeu de rasters.
.rendered_cache <- new.env(parent = emptyenv())

load_raster_cached <- function(path) {
  key <- path
  if (exists(key, envir = .raster_cache)) {
    return(get(key, envir = .raster_cache))
  }
  r <- tryCatch(terra::rast(path), error = function(e) NULL)
  if (!is.null(r)) assign(key, r, envir = .raster_cache)
  r
}

reset_raster_cache <- function() {
  rm(list = ls(.raster_cache),   envir = .raster_cache)
  rm(list = ls(.rendered_cache), envir = .rendered_cache)
}

# -----------------------------------------------------------------------------
# 1. PARSING FICHIERS CLS BRUTS (format //KEY/VALUE//)
# -----------------------------------------------------------------------------

is_cls_raw_format <- function(filepath) {
  first_line <- tryCatch(readLines(filepath, n = 1, warn = FALSE), error = function(e) "")
  grepl("^//SR//", first_line)
}

#' Parse un fichier CLS brut en data.frame
#' Format : //SR//TM/POS//OP/CLS508939//LT/48.6423//LG/-2.015//SP/5//DA/20230101//TI/005949//ER
#' Gère les clés dupliquées en ne gardant que la première occurrence
parse_cls_raw <- function(filepath) {
  lines <- readLines(filepath, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  
  parse_one_line <- function(line) {
    line  <- gsub("^//|//ER\\r?$", "", line)
    parts <- strsplit(line, "//")[[1]]
    parts <- parts[nzchar(trimws(parts))]
    kv <- lapply(parts, function(p) {
      idx <- regexpr("/", p)
      if (idx < 1) return(NULL)
      list(key = substr(p, 1, idx - 1), val = substr(p, idx + 1, nchar(p)))
    })
    kv   <- Filter(Negate(is.null), kv)
    keys <- sapply(kv, `[[`, "key")
    vals <- sapply(kv, `[[`, "val")
    # Deduplique : garde uniquement la premiere occurrence de chaque cle
    dup  <- duplicated(keys)
    keys <- keys[!dup]
    vals <- vals[!dup]
    # Filtre les cles vides ou purement numeriques (artefacts)
    ok   <- nzchar(keys) & !grepl("^[0-9]+$", keys)
    as.data.frame(
      as.list(setNames(vals[ok], keys[ok])),
      stringsAsFactors = FALSE
    )
  }
  
  dfs <- lapply(lines, function(l) tryCatch(parse_one_line(l), error = function(e) NULL))
  dfs <- Filter(Negate(is.null), dfs)
  if (length(dfs) == 0) return(NULL)
  dplyr::bind_rows(dfs)
}

# -----------------------------------------------------------------------------
# 2. LECTURE GENERIQUE VMS (CLS brut ou CSV standard)
# -----------------------------------------------------------------------------

read_vms_file <- function(filepath, filename, sep = ";", dec = ".") {
  ext <- tolower(tools::file_ext(filename))
  
  if (ext == "rds") {
    return(readRDS(filepath))
  }
  
  if (ext %in% c("csv", "txt", "")) {
    if (is_cls_raw_format(filepath)) {
      df <- parse_cls_raw(filepath)
      return(df)
    }
    df <- tryCatch(
      read.csv(filepath, sep = sep, dec = dec, stringsAsFactors = FALSE, encoding = "UTF-8"),
      error = function(e) {
        read.csv(filepath, sep = sep, dec = dec, stringsAsFactors = FALSE)
      }
    )
    return(df)
  }
  
  if (ext %in% c("xlsx", "xls")) {
    return(readxl::read_excel(filepath))
  }
  
  NULL
}

# -----------------------------------------------------------------------------
# 3. DETECTION DU TYPE DE NAVIRE (CLS vs Agiltech)
# -----------------------------------------------------------------------------

detect_vms_type <- function(df, col_immat) {
  if (is.null(col_immat) || !col_immat %in% names(df)) return("agiltech")
  vals <- as.character(df[[col_immat]])
  vals <- vals[!is.na(vals) & nzchar(vals)]
  if (length(vals) == 0) return("agiltech")
  pct_cls <- mean(grepl("^CLS", vals, ignore.case = TRUE))
  if (pct_cls > 0.5) "cls" else "agiltech"
}

# -----------------------------------------------------------------------------
# 4. MAPPING COLONNES VMS
# -----------------------------------------------------------------------------

VMS_COLS_ATTENDUES <- list(
  col_lat   = c("LT", "lat", "latitude", "LAT", "Latitude"),
  col_lon   = c("LG", "lon", "longitude", "LNG", "Longitude"),
  col_speed = c("SP", "vitesse", "speed", "vitesse_cls", "Vitesse", "SPEED"),
  col_date  = c("DA", "date", "Date", "DATE", "da"),
  col_immat = c("OP", "immat", "navire", "vessel", "IMMAT", "nom_navire")
)

VMS_COLS_LABELS <- c(
  col_lat   = "Latitude",
  col_lon   = "Longitude",
  col_speed = "Vitesse",
  col_date  = "Date (YYYYMMDD)",
  col_immat = "Immatriculation navire"
)

autodetect_vms_cols <- function(df) {
  result <- list()
  for (var in names(VMS_COLS_ATTENDUES)) {
    candidats  <- VMS_COLS_ATTENDUES[[var]]
    match_auto <- intersect(candidats, names(df))
    result[[var]] <- if (length(match_auto) > 0) match_auto[1] else NA_character_
  }
  result
}

# -----------------------------------------------------------------------------
# 5. TRAITEMENT PRINCIPAL
# -----------------------------------------------------------------------------

process_vms_data <- function(df, mapping, speed_range = c(0, Inf)) {
  
  for (var in names(mapping)) {
    src <- mapping[[var]]
    if (!is.na(src) && src %in% names(df) && src != var) {
      names(df)[names(df) == src] <- var
    }
  }
  
  if ("col_lat"   %in% names(df)) df$col_lat   <- suppressWarnings(as.numeric(df$col_lat))
  if ("col_lon"   %in% names(df)) df$col_lon   <- suppressWarnings(as.numeric(df$col_lon))
  if ("col_speed" %in% names(df)) df$col_speed <- suppressWarnings(as.numeric(df$col_speed))
  
  vms_type <- detect_vms_type(df, "col_immat")
  if (vms_type == "cls" && "col_speed" %in% names(df)) {
    df$col_speed <- df$col_speed / 10
  }
  df$vms_type <- vms_type
  
  if ("col_date" %in% names(df)) {
    d_chr <- as.character(df$col_date)
    
    # ── Parsing robuste multi-format ────────────────────────────────────────
    # Ordre important : les formats les plus spécifiques (4 chiffres année)
    # AVANT les formats ambigus, pour éviter qu'un "11/10/2023" soit interprété
    # comme année=11 avec %Y/%m/%d.
    # Les formats avec heure (%H:%M, %H:%M:%S) sont aussi testés car certains
    # exports VMS incluent l'heure dans la colonne date.
    date_formats <- c(
      "%Y%m%d",           # 20231011
      "%Y-%m-%d %H:%M:%S",# 2023-10-11 22:58:00
      "%Y-%m-%d %H:%M",   # 2023-10-11 22:58
      "%Y-%m-%d",         # 2023-10-11
      "%d/%m/%Y %H:%M:%S",# 11/10/2023 22:58:00
      "%d/%m/%Y %H:%M",   # 11/10/2023 22:58
      "%d/%m/%Y",         # 11/10/2023
      "%m/%d/%Y %H:%M:%S",# 10/11/2023 22:58:00  (format US)
      "%m/%d/%Y %H:%M",   # 10/11/2023 22:58
      "%m/%d/%Y",         # 10/11/2023
      "%d-%m-%Y %H:%M:%S",# 11-10-2023 22:58:00
      "%d-%m-%Y %H:%M",   # 11-10-2023 22:58
      "%d-%m-%Y",         # 11-10-2023
      "%d.%m.%Y %H:%M:%S",# 11.10.2023 22:58:00
      "%d.%m.%Y %H:%M",   # 11.10.2023 22:58
      "%d.%m.%Y"          # 11.10.2023
    )
    
    parsed <- rep(as.Date(NA), length(d_chr))
    remaining <- seq_along(d_chr)
    for (fmt in date_formats) {
      if (length(remaining) == 0) break
      trial <- suppressWarnings(as.Date(d_chr[remaining], format = fmt))
      # Valider : l'année doit être >= 1990 pour écarter les parsings absurdes
      # (ex. "%Y/%m/%d" sur "11/10/2023" donnerait année=11)
      valid  <- !is.na(trial) & !is.na(as.integer(format(trial, "%Y"))) &
        as.integer(format(trial, "%Y")) >= 1990
      parsed[remaining[valid]] <- trial[valid]
      remaining <- remaining[!valid]
    }
    
    # Statistique de couverture pour debug
    n_ok  <- sum(!is.na(parsed))
    n_tot <- length(parsed)
    if (n_ok < n_tot) {
      message(sprintf("[VMS parse_date] %d/%d dates parsees — %d echecs",
                      n_ok, n_tot, n_tot - n_ok))
    }
    
    df$col_date_parsed <- parsed
    if (!"annee" %in% names(df)) df$annee <- as.integer(format(parsed, "%Y"))
    if (!"mois"  %in% names(df)) df$mois  <- as.integer(format(parsed, "%m"))
  }
  
  if ("col_speed" %in% names(df)) {
    n_avant <- nrow(df)
    df <- df[!is.na(df$col_speed) &
               df$col_speed >= speed_range[1] &
               df$col_speed <= speed_range[2], ]
    message(sprintf("[VMS filtre vitesse] range=[%.1f, %.1f] | %d \u2192 %d lignes (type=%s)",
                    speed_range[1], speed_range[2], n_avant, nrow(df),
                    if ("vms_type" %in% names(df)) df$vms_type[1] else "?"))
  }
  
  if (all(c("col_lat", "col_lon") %in% names(df))) {
    df <- df[!is.na(df$col_lat) & !is.na(df$col_lon), ]
  }
  
  df
}

# -----------------------------------------------------------------------------
# 6. CROISEMENT SHAPEFILE RECTANGLES
# -----------------------------------------------------------------------------

cross_vms_rectangles <- function(df_vms, sf_rect) {
  empty <- list(on = sf_rect[0, ], context = sf_rect[0, ])
  
  if (!all(c("col_lat", "col_lon") %in% names(df_vms))) return(empty)
  if (nrow(df_vms) == 0)                                 return(empty)
  
  df_clean <- df_vms[
    !is.na(df_vms$col_lat)  & !is.na(df_vms$col_lon)  &
      is.finite(df_vms$col_lat) & is.finite(df_vms$col_lon) &
      df_vms$col_lat >= -90    & df_vms$col_lat <= 90    &
      df_vms$col_lon >= -180   & df_vms$col_lon <= 180,
  ]
  if (nrow(df_clean) == 0) return(empty)
  
  old_s2 <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  
  pts <- tryCatch(
    sf::st_as_sf(df_clean, coords = c("col_lon", "col_lat"), crs = 4326),
    error = function(e) NULL
  )
  if (is.null(pts) || nrow(pts) == 0) return(empty)
  
  # ── Pré-filtrage bbox SANS st_intersects : opération sur coordonnées pures ──
  # st_make_valid + st_intersects sur 48k polygones = très lent.
  # On utilise les centroïdes pré-calculés si disponibles (attr "centroids_xy"),
  # sinon on les calcule à la volée — ~100× plus rapide que st_intersects bbox.
  bb     <- tryCatch(sf::st_bbox(pts), error = function(e) NULL)
  if (is.null(bb) || anyNA(bb) || any(!is.finite(as.numeric(bb)))) return(empty)
  
  margin <- 0.1   # Réduit de 1.0 → 0.1 : simple pré-filtre bbox, pas un filtre métier
  xmin_f <- as.numeric(bb["xmin"]) - margin
  xmax_f <- as.numeric(bb["xmax"]) + margin
  ymin_f <- as.numeric(bb["ymin"]) - margin
  ymax_f <- as.numeric(bb["ymax"]) + margin
  
  coords <- attr(sf_rect, "centroids_xy")
  if (is.null(coords))
    coords <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf_rect)))
  
  in_zone <- coords[, 1] >= xmin_f & coords[, 1] <= xmax_f &
    coords[, 2] >= ymin_f & coords[, 2] <= ymax_f
  sf_zone <- sf_rect[in_zone, ]
  
  if (nrow(sf_zone) == 0) return(list(on = sf_rect[0, ], context = sf_rect[0, ]))
  
  id_col <- names(sf_zone)[
    !names(sf_zone) %in% c(attr(sf_zone, "sf_column"), "geometry")
  ][1]
  
  # Valider les géométries AVANT le croisement
  sf_zone <- tryCatch(sf::st_make_valid(sf_zone), error = function(e) sf_zone)
  pts     <- tryCatch(sf::st_make_valid(pts),     error = function(e) pts)
  
  # Croisement explicite : st_intersects sparse retourne pour chaque rectangle
  # la liste des points qu'il contient. Un rectangle est "actif" si cette liste
  # est non-vide. On évite st_join qui fait un left-join gauche et peut produire
  # des lignes dupliquées ou des correspondances erronées aux frontières.
  mat <- tryCatch(
    sf::st_intersects(sf_zone, pts, sparse = TRUE),  # liste longueur nrow(sf_zone)
    error = function(e) {
      message("[VMS cross_vms_rectangles] st_intersects échoué : ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(mat)) return(empty)
  
  # Rectangles actifs = ceux qui contiennent au moins 1 point
  rect_actifs <- lengths(mat) > 0
  message(sprintf("[VMS cross] %d pts | %d rects candidats | %d actifs",
                  nrow(pts), nrow(sf_zone), sum(rect_actifs)))
  
  # Filtre par index booléen (et non par valeur d'ID) pour éviter les faux-positifs
  # quand id_col contient des valeurs dupliquées ou non-uniques.
  list(
    on      = sf_zone[rect_actifs, ],
    context = sf_zone   # toute la zone bbox — l'appelant filtre selon show_grid
  )
}

# -----------------------------------------------------------------------------
# 7. SELECTION DE LA CARTE SHOM
# -----------------------------------------------------------------------------

load_assemblage_shp <- function(shp_path) {
  tryCatch({
    shp <- sf::st_read(shp_path, quiet = TRUE)
    # Si le CRS est absent du fichier, on assigne WGS84 par defaut
    if (is.na(sf::st_crs(shp)) || is.null(sf::st_crs(shp)$input)) {
      shp <- sf::st_set_crs(shp, 4326)
    }
    shp
  }, error = function(e) NULL)
}

select_shom_maps <- function(sf_rect_active, sf_assemblage, raster_dir) {
  if (is.null(sf_assemblage) || nrow(sf_rect_active) == 0) return(NULL)
  
  # Desactiver S2 en premier -- evite les warnings "assumes planar" en rafale
  old_s2 <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  
  # -- Validation AVANT toute opération spatiale --------------------------------
  # Certains mois (Jan/Fév) peuvent produire des géométries légèrement invalides
  # (anneaux auto-intersectants, etc.) qui font échouer st_union silencieusement.
  sf_rect_active <- tryCatch(sf::st_make_valid(sf_rect_active), error = function(e) sf_rect_active)
  sf_assemblage  <- tryCatch(sf::st_make_valid(sf_assemblage),  error = function(e) sf_assemblage)
  
  # -- Harmonisation CRS -------------------------------------------------------
  crs_assemblage <- sf::st_crs(sf_assemblage)
  crs_rect       <- sf::st_crs(sf_rect_active)
  
  if (is.na(crs_assemblage) || is.null(crs_assemblage$input)) {
    sf_assemblage  <- sf::st_set_crs(sf_assemblage, 4326)
    crs_assemblage <- sf::st_crs(sf_assemblage)
  }
  if (is.na(crs_rect) || is.null(crs_rect$input)) {
    sf_rect_active <- sf::st_set_crs(sf_rect_active, 4326)
    crs_rect       <- sf::st_crs(sf_rect_active)
  }
  
  if (!is.na(crs_assemblage) && !is.na(crs_rect) && crs_assemblage != crs_rect) {
    tryCatch(
      sf_assemblage <- sf::st_transform(sf_assemblage, crs_rect),
      error = function(e) NULL
    )
  }
  
  id_col <- names(sf_assemblage)[!names(sf_assemblage) %in%
                                   c(attr(sf_assemblage, "sf_column"), "geometry")][1]
  
  # -- Cartes candidates : celles qui intersectent au moins un rectangle actif --
  covering <- tryCatch(
    sf::st_intersects(sf_assemblage, sf_rect_active, sparse = FALSE),
    error = function(e) matrix(FALSE, nrow = nrow(sf_assemblage), ncol = nrow(sf_rect_active))
  )
  cartes_candidates <- sf_assemblage[rowSums(covering) > 0, ]
  if (nrow(cartes_candidates) == 0) {
    message("[SHOM] Aucune carte candidate — vérifiez CRS et emprise de l'assemblage")
    return(NULL)
  }
  
  # -- ÉTAPE CLÉ : ne garder que les candidats dont le raster existe ----------
  # Sans ce filtre, st_covers peut trouver une carte géographiquement couvrant
  # la zone mais sans fichier .tif associé, et le mode mosaïque renvoie
  # build_raster_paths([ids sans fichier]) = character(0) → pas de fond SHOM.
  #
  # Stratégie de matching à 3 niveaux (du plus strict au plus souple) :
  #   1. Correspondance exacte du nom complet (id_clean == nom_fichier)
  #   2. Correspondance par préfixe complet sans extension
  #      ex. shapefile="7210_Atterrages_..._Mer.tif" → pattern "^7210_Atterrages_..._Mer"
  #      → rate si le fichier disque a "_dec.tif" au lieu de "_Mer.tif"
  #   3. Correspondance sur le PRÉFIXE NUMÉRIQUE uniquement (4 premiers chiffres)
  #      ex. shapefile="7210_Atterrages_..._Mer.tif" → pattern "^7210_"
  #      → trouve "7210_Atterrages_de_lentree_de_La_Manche_dec.tif" ✓
  #      C'est le niveau qui résout le décalage _Mer / _dec entre shapefile et disque.
  ids_candidats <- as.character(cartes_candidates[[id_col]])
  paths_par_id  <- sapply(ids_candidats, function(id) {
    id_clean <- trimws(id)
    
    # Niveau 1 : correspondance exacte
    exact <- file.path(raster_dir, id_clean)
    if (file.exists(exact)) return(exact)
    
    # Niveau 2 : préfixe complet sans extension
    base_id <- tools::file_path_sans_ext(id_clean)
    files   <- list.files(raster_dir, pattern = paste0("^", base_id),
                          full.names = TRUE, ignore.case = TRUE)
    if (length(files) > 0) return(files[1])
    
    # Niveau 3 : préfixe numérique seul (robuste aux variantes de nommage)
    # Extrait les chiffres initiaux du nom (ex. "7210" depuis "7210_Atterrages_…")
    num_prefix <- regmatches(id_clean, regexpr("^[0-9]+", id_clean))
    if (length(num_prefix) > 0 && nzchar(num_prefix)) {
      files_num <- list.files(raster_dir,
                              pattern    = paste0("^", num_prefix, "[_.]"),
                              full.names = TRUE, ignore.case = TRUE)
      if (length(files_num) > 0) {
        message(sprintf("[SHOM] Match prefixe num '%s' pour id='%s' → %s",
                        num_prefix, id_clean, basename(files_num[1])))
        return(files_num[1])
      }
    }
    
    NA_character_
  }, USE.NAMES = TRUE)
  
  # Subsetting par indices NUMERIQUES — évite tout pb de nommage avec apostrophes/accents
  idx_avec_raster     <- which(!is.na(paths_par_id))
  rasters_disponibles <- unname(paths_par_id[idx_avec_raster])
  
  message(sprintf("[SHOM] paths_par_id : %d/%d avec fichier trouve",
                  length(idx_avec_raster), length(paths_par_id)))
  if (length(idx_avec_raster) < length(paths_par_id))
    message("[SHOM] IDs sans raster : ",
            paste(names(paths_par_id)[is.na(paths_par_id)], collapse = ", "))
  
  if (length(idx_avec_raster) == 0) {
    message("[SHOM] Aucun raster .tif disponible pour les cartes candidates de ce mois")
    return(NULL)
  }
  
  cartes_avec_raster <- cartes_candidates[idx_avec_raster, , drop = FALSE]
  
  message(sprintf("[SHOM] %d carte(s) candidate(s), %d avec raster disponible",
                  nrow(cartes_candidates), nrow(cartes_avec_raster)))
  
  # -- Sélection de la meilleure carte ----------------------------------------
  #
  # Niveau 1 : cherche un raster unique dont l'emprise réelle (terra::ext du
  #            fichier .tif) contient la bbox complète de tous les rectangles
  #            actifs avec une petite marge.
  #            On compare les emprises raster — pas les géométries du shapefile
  #            assemblage qui peuvent avoir des bords non-rectangulaires ou des
  #            polygones tronqués ne reflétant pas la vraie couverture du .tif.
  #
  # Fallback garanti : mosaïque de toutes les tuiles avec raster disponible.
  # -----------------------------------------------------------------------------
  tryCatch({
    if (length(rasters_disponibles) > 0 && nrow(sf_rect_active) > 0) {
      
      # ── Bbox des rectangles actifs ──────────────────────────────────────
      bb_rects <- sf::st_bbox(sf_rect_active)
      rx_need  <- as.numeric(bb_rects["xmin"])
      rx_need2 <- as.numeric(bb_rects["xmax"])
      ry_need  <- as.numeric(bb_rects["ymin"])
      ry_need2 <- as.numeric(bb_rects["ymax"])
      
      # ── Niveau 1 : un seul raster couvre toute la bbox des rects ────────
      # On lit l'emprise de chaque raster candidat et on cherche celui dont
      # l'emprise (xmin ≤ need_xmin, xmax ≥ need_xmax, etc.) contient entièrement
      # la bbox des rectangles actifs. Tolérance de 0.01° pour les bords exacts.
      TOL <- 0.01
      single_idx <- NULL
      single_path <- NULL
      for (k in seq_along(rasters_disponibles)) {
        path_k <- rasters_disponibles[k]
        ev <- tryCatch({
          r_tmp <- load_raster_cached(path_k)
          as.vector(terra::ext(r_tmp))   # c(xmin, xmax, ymin, ymax)
        }, error = function(e) NULL)
        if (is.null(ev) || length(ev) < 4) next
        if (ev[1] - TOL <= rx_need  &&
            ev[2] + TOL >= rx_need2 &&
            ev[3] - TOL <= ry_need  &&
            ev[4] + TOL >= ry_need2) {
          single_idx  <- k
          single_path <- path_k
          break   # on prend le premier qui convient (liste déjà triée par candidature)
        }
      }
      
      if (!is.null(single_idx)) {
        chosen <- cartes_avec_raster[single_idx, , drop = FALSE]
        message(sprintf(
          "[SHOM] Mode single (raster couvre bbox des %d rects) — carte=%s | chemin=%s",
          nrow(sf_rect_active),
          trimws(as.character(chosen[[id_col]])),
          basename(single_path)
        ))
        return(list(
          cartes  = chosen, id_col = id_col, mode = "single",
          rasters = single_path
        ))
      }
      # Aucun raster unique ne couvre toute la bbox → mosaïque
    }
  }, error = function(e) {
    message("[SHOM] Erreur bloc single, fallback mosaic : ", conditionMessage(e))
  })
  
  # -- Fallback garanti : mosaïque de toutes les cartes avec raster ----------
  message(sprintf("[SHOM] Mode mosaic — %d rasters : %s",
                  length(rasters_disponibles),
                  paste(basename(rasters_disponibles), collapse = ", ")))
  return(list(
    cartes  = cartes_avec_raster, id_col  = id_col, mode = "mosaic",
    rasters = rasters_disponibles
  ))
}

build_raster_paths <- function(carte_ids, raster_dir) {
  # Meme strategie de matching a 3 niveaux que select_shom_maps :
  #   1. Exacte  2. Prefixe complet sans extension  3. Prefixe numerique seul
  paths <- sapply(as.character(carte_ids), function(id) {
    id_clean <- trimws(id)
    
    # Niveau 1 : correspondance exacte
    exact_path <- file.path(raster_dir, id_clean)
    if (file.exists(exact_path)) return(exact_path)
    
    # Niveau 2 : prefixe complet sans extension
    base_id <- tools::file_path_sans_ext(id_clean)
    files   <- list.files(raster_dir, pattern = paste0("^", base_id),
                          full.names = TRUE, ignore.case = TRUE)
    if (length(files) > 0) return(files[1])
    
    # Niveau 3 : prefixe numerique seul (robuste aux variantes _dec / _Mer / etc.)
    num_prefix <- regmatches(id_clean, regexpr("^[0-9]+", id_clean))
    if (length(num_prefix) > 0 && nzchar(num_prefix)) {
      files_num <- list.files(raster_dir,
                              pattern    = paste0("^", num_prefix, "[_.]"),
                              full.names = TRUE, ignore.case = TRUE)
      if (length(files_num) > 0) return(files_num[1])
    }
    
    NA_character_
  })
  paths[!is.na(paths)]
}

load_and_mosaic_rasters <- function(raster_paths) {
  # ── Stratégie : on ne fusionne JAMAIS les tuiles ─────────────────────────
  # Chaque tuile est renvoyée telle quelle (pleine résolution).
  # terra lit les .tif en lazy : les pixels ne sont rapatriés en RAM
  # qu'au moment du terra::as.array() dans render_one_raster().
  # Le downsample éventuel pour l'affichage est géré par renderPlot()
  # via son propre mécanisme de redimensionnement.
  if (length(raster_paths) == 0) return(NULL)
  
  rasters <- lapply(raster_paths, function(path) {
    tryCatch(terra::rast(path), error = function(e) {
      message("[SHOM] Impossible de charger : ", path, " — ", conditionMessage(e))
      NULL
    })
  })
  
  rasters <- Filter(Negate(is.null), rasters)
  if (length(rasters) == 0) return(NULL)
  
  # Log diagnostic à la première utilisation
  r1 <- rasters[[1]]
  message(sprintf("[SHOM] Tuile chargée : %d bande(s), type=%s, has.colors=%s",
                  terra::nlyr(r1),
                  paste(terra::datatype(r1), collapse = "/"),
                  terra::has.colors(r1)))
  
  rasters   # liste de SpatRaster — make_vms_map itère dessus
}

# -----------------------------------------------------------------------------
# 8. GENERATION DU GRAPHIQUE GGPLOT
# -----------------------------------------------------------------------------

make_vms_map <- function(sf_rect_on, sf_rect_context = NULL,
                         raster_shom = NULL, navire, mois_num, annee,
                         downsample_px = NULL) {
  # sf_rect_on      : rectangles actifs uniquement (présents ce mois)
  # sf_rect_context : tous les rectangles de la zone (optionnel, fond grisé)
  # downsample_px   : NULL = pleine résolution (export) ; entier = max pixels
  #                   sur le grand côté du raster (affichage écran, ~1500).
  
  mois_noms <- c("Janvier","Fevrier","Mars","Avril","Mai","Juin",
                 "Juillet","Aout","Septembre","Octobre","Novembre","Decembre")
  titre_mois <- if (!is.na(mois_num) && mois_num >= 1 && mois_num <= 12)
    mois_noms[mois_num] else as.character(mois_num)
  
  n_actifs <- nrow(sf_rect_on)
  
  # ── Calcul de la bbox zoomée ──────────────────────────────────────────────
  # Le zoom est calé sur l'emprise des rectangles actifs, avec une marge de 5%.
  # Le raster SHOM est un fond de carte : il ne doit PAS restreindre la vue.
  # Les zones sans raster apparaissent avec la couleur panel (#D6E8F0 = mer),
  # ce qui est préférable à couper des rectangles actifs hors-champ.
  zoom_layer <- NULL
  if (n_actifs > 0) {
    bb <- sf::st_bbox(sf_rect_on)
    dx <- max((as.numeric(bb["xmax"]) - as.numeric(bb["xmin"])) * 0.05, 0.05)
    dy <- max((as.numeric(bb["ymax"]) - as.numeric(bb["ymin"])) * 0.05, 0.05)
    xlim <- c(as.numeric(bb["xmin"]) - dx, as.numeric(bb["xmax"]) + dx)
    ylim <- c(as.numeric(bb["ymin"]) - dy, as.numeric(bb["ymax"]) + dy)
    zoom_layer <- ggplot2::coord_sf(xlim = xlim, ylim = ylim,
                                    expand = FALSE, crs = 4326)
  }
  
  p <- ggplot2::ggplot()
  
  # ── Fond de carte SHOM ────────────────────────────────────────────────────
  # raster_shom est une LISTE de SpatRaster (une entrée par tuile).
  # Chaque tuile est convertie en raster R natif et superposée via annotation_raster.
  # Les cartes SHOM sont en couleur : on préserve le RGB si >= 3 bandes,
  # sinon on restitue les niveaux de gris tels quels (pas de coercition monochrome).
  render_one_raster <- function(r, target_px = NULL) {
    ext  <- terra::ext(r)
    
    # ── Clé de cache : source du raster + résolution cible ─────────────────
    src_key   <- tryCatch(terra::sources(r), error = function(e) "")
    cache_key <- paste0(src_key, "_", if (is.null(target_px)) "full" else target_px)
    cache_key <- gsub("[^A-Za-z0-9._-]", "_", cache_key)
    if (nzchar(cache_key) && exists(cache_key, envir = .rendered_cache)) {
      cached <- get(cache_key, envir = .rendered_cache)
      return(list(ras = cached, ext = ext))
    }
    
    # ── Downsampling pour l'affichage écran ────────────────────────────────
    # Pour l'export on garde la pleine résolution (target_px = NULL).
    # Pour le carrousel, on ramène le grand côté à target_px max.
    # IMPORTANT : terra::has.colors() retourne un vecteur logique (1 valeur
    # par bande) ; on utilise isTRUE([1L]) pour garantir un scalaire.
    if (!is.null(target_px) && is.numeric(target_px) && target_px > 0) {
      nc <- terra::ncol(r)
      nr <- terra::nrow(r)
      if (max(nc, nr) > target_px) {
        fact    <- max(ceiling(max(nc, nr) / target_px), 1L)
        fun_agg <- if (isTRUE(terra::has.colors(r)[1L])) "modal" else "mean"
        r       <- tryCatch(terra::aggregate(r, fact = fact, fun = fun_agg),
                            error = function(e) r)
      }
    }
    
    nlyr <- terra::nlyr(r)   # recalculé APRÈS downsampling éventuel
    
    # ── Cas 1 : GeoTIFF avec palette/colormap embarquée (ex. cartes SHOM) ──
    # 1 bande INT1U (valeurs 0-255) + table de couleurs → couleur réelle.
    # terra::has.colors() détecte la palette ; on lit la colormap et on
    # vectorise l'application : arr[i,j] → rgb depuis la table.
    if (isTRUE(terra::has.colors(r)[1L])) {
      ct <- tryCatch(terra::coltab(r)[[1]], error = function(e) NULL)
      if (!is.null(ct) && nrow(ct) > 0) {
        # ct est un data.frame avec colonnes value, red, green, blue (0-255)
        arr_idx <- terra::as.matrix(r[[1]], wide = TRUE)   # indices de palette (entiers)
        # Construire un vecteur de lookup hex[0..255]
        lookup <- rep("#000000", 256)
        valid  <- ct$value >= 0 & ct$value <= 255
        lookup[ct$value[valid] + 1L] <- grDevices::rgb(
          ct$red[valid], ct$green[valid], ct$blue[valid],
          maxColorValue = 255
        )
        # Appliquer le lookup : arr_idx contient des entiers 0-255
        hex_mat <- matrix(
          lookup[as.integer(arr_idx) + 1L],
          nrow = nrow(arr_idx), ncol = ncol(arr_idx)
        )
        if (nzchar(cache_key)) assign(cache_key, grDevices::as.raster(hex_mat), envir = .rendered_cache)
        return(list(ras = grDevices::as.raster(hex_mat), ext = ext))
      }
    }
    
    # ── Cas 2 : 3 bandes ou plus → RGB classique ──────────────────────────
    if (nlyr >= 3) {
      r3  <- r[[1:3]]
      arr <- terra::as.array(r3)   # rows × cols × 3
      mx  <- max(arr, na.rm = TRUE)
      if (mx > 1) arr <- arr / 255
      arr[is.na(arr) | is.nan(arr)] <- 1
      arr <- pmax(pmin(arr, 1), 0)
      hex_mat <- matrix(
        grDevices::rgb(arr[,,1], arr[,,2], arr[,,3]),
        nrow = nrow(arr), ncol = ncol(arr)
      )
      if (nzchar(cache_key)) assign(cache_key, grDevices::as.raster(hex_mat), envir = .rendered_cache)
      return(list(ras = grDevices::as.raster(hex_mat), ext = ext))
    }
    
    # ── Cas 3 : 1 bande sans palette → niveaux de gris ────────────────────
    arr <- terra::as.matrix(r[[1]], wide = TRUE)
    mx  <- max(arr, na.rm = TRUE)
    if (mx > 1) arr <- arr / 255
    arr[is.na(arr) | is.nan(arr)] <- 1
    arr <- pmax(pmin(arr, 1), 0)
    hex_mat <- matrix(
      grDevices::rgb(arr, arr, arr),
      nrow = nrow(arr), ncol = ncol(arr)
    )
    if (nzchar(cache_key)) assign(cache_key, grDevices::as.raster(hex_mat), envir = .rendered_cache)
    list(ras = grDevices::as.raster(hex_mat), ext = ext)
  }
  
  if (!is.null(raster_shom)) {
    tuiles <- if (is.list(raster_shom)) raster_shom else list(raster_shom)
    # ── Tri : grandes cartes d'abord, cartes de détail par-dessus ──────────
    # Évite les joints blancs entre tuiles dans la mosaïque : les cartes de
    # détail (petite surface = grande échelle) recouvrent les cartes générales
    # là où elles se chevauchent, assurant une transition sans lacune.
    tuile_areas <- sapply(tuiles, function(r) {
      tryCatch({
        ev <- as.vector(terra::ext(r))
        (ev[2] - ev[1]) * (ev[4] - ev[3])   # xrange * yrange
      }, error = function(e) 0)
    })
    tuiles <- tuiles[order(tuile_areas, decreasing = TRUE)]  # grandes d'abord
    
    for (tuile in tuiles) {
      tryCatch({
        rendered <- render_one_raster(tuile, target_px = downsample_px)
        p <- p + ggplot2::annotation_raster(
          rendered$ras,
          xmin = rendered$ext$xmin, xmax = rendered$ext$xmax,
          ymin = rendered$ext$ymin, ymax = rendered$ext$ymax,
          interpolate = FALSE   # pas d'interpolation aux bords → joints nets
        )
      }, error = function(e) {
        message("[SHOM] Erreur rendu tuile : ", conditionMessage(e))
      })
    }
  }
  
  # ── Contexte : rectangles de la zone SANS ping (grisés) ──────────────────
  if (!is.null(sf_rect_context) && nrow(sf_rect_context) > 0 && n_actifs > 0) {
    id_col_ctx <- names(sf_rect_context)[
      !names(sf_rect_context) %in% c(attr(sf_rect_context, "sf_column"), "geometry")
    ][1]
    id_col_on <- names(sf_rect_on)[
      !names(sf_rect_on) %in% c(attr(sf_rect_on, "sf_column"), "geometry")
    ][1]
    ids_actifs  <- sf_rect_on[[id_col_on]]
    sf_inactifs <- sf_rect_context[!sf_rect_context[[id_col_ctx]] %in% ids_actifs, ]
    if (nrow(sf_inactifs) > 0)
      p <- p + ggplot2::geom_sf(data      = sf_inactifs,
                                fill      = NA,
                                color     = "#1D4E6D",
                                linewidth = 0.25,
                                alpha     = 0.4)
  } else if (!is.null(sf_rect_context) && nrow(sf_rect_context) > 0) {
    p <- p + ggplot2::geom_sf(data      = sf_rect_context,
                              fill      = NA,
                              color     = "#1D4E6D",
                              linewidth = 0.25,
                              alpha     = 0.4)
  }
  
  # ── Rectangles actifs (orange) ────────────────────────────────────────────
  if (n_actifs > 0) {
    p <- p + ggplot2::geom_sf(data      = sf_rect_on,
                              fill      = "#FF6B00",
                              color     = NA,
                              linewidth = 0,
                              alpha     = 0.90)
  }
  
  if (!is.null(zoom_layer)) p <- p + zoom_layer
  
  title_sz    <- 18
  subtitle_sz <- 14
  caption_sz  <- 10
  
  p <- p +
    ggplot2::labs(
      title    = paste0(navire, " \u2014 ", titre_mois, " ", annee),
      subtitle = paste0(n_actifs, " rectangle(s) actif(s)"),
      caption  = "Fond de carte : SHOM | CRPMEM Bretagne"
    ) +
    ggplot2::theme_void(base_family = "sans") +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      plot.title       = ggplot2::element_text(color = "#061A2B", size = title_sz,
                                               face = "bold",
                                               margin = ggplot2::margin(b = 2)),
      plot.subtitle    = ggplot2::element_text(color = "#1D4E6D", size = subtitle_sz),
      plot.caption     = ggplot2::element_text(color = "#4A7A9B", size = caption_sz),
      plot.margin      = ggplot2::margin(6, 6, 6, 6)
    )
  p
}

# -----------------------------------------------------------------------------
# 8b. EXPORT SHAPEFILE CONSOLIDE
# -----------------------------------------------------------------------------

#' Construit un sf consolidé de tous les rectangles actifs (tous mois),
#' avec une colonne "mois" (1-12) pour distinguer les périodes.
#' Utilisé par l'export SHP ZIP dans server_vms.R.
#'
#' @param df_nav   data.frame VMS normalisé (colonnes col_lat, col_lon, mois)
#' @param sf_rect  sf des rectangles ICES/stat (la grille complète)
#' @return sf avec colonnes du rectangle + colonne "mois", ou NULL si rien
build_export_shp <- function(df_nav, sf_rect) {
  if (is.null(df_nav) || nrow(df_nav) == 0) return(NULL)
  if (is.null(sf_rect) || nrow(sf_rect) == 0) return(NULL)
  if (!"mois" %in% names(df_nav)) return(NULL)
  
  mois_presents <- sort(unique(df_nav$mois[!is.na(df_nav$mois)]))
  if (length(mois_presents) == 0) return(NULL)
  
  sf_list <- lapply(mois_presents, function(m) {
    df_m <- df_nav[!is.na(df_nav$mois) & df_nav$mois == m, ]
    if (nrow(df_m) == 0) return(NULL)
    crossed <- tryCatch(
      cross_vms_rectangles(df_m, sf_rect),
      error = function(e) NULL
    )
    if (is.null(crossed) || nrow(crossed$on) == 0) return(NULL)
    sf_m <- crossed$on
    sf_m$mois <- as.integer(m)
    sf_m
  })
  
  sf_list <- Filter(Negate(is.null), sf_list)
  if (length(sf_list) == 0) return(NULL)
  
  tryCatch(
    do.call(rbind, sf_list),
    error = function(e) {
      message("[SHP export] Erreur rbind : ", conditionMessage(e))
      NULL
    }
  )
}

# -----------------------------------------------------------------------------
# 9. UTILITAIRES
# -----------------------------------------------------------------------------

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

mois_label <- function(m) {
  noms <- c("Janv.","Fevr.","Mars","Avr.","Mai","Juin",
            "Juil.","Aout","Sept.","Oct.","Nov.","Dec.")
  # Garde contre character(0) / integer(0) / NA / valeurs hors [1,12]
  if (length(m) == 0) return("")
  if (is.na(m) || m < 1 || m > 12) return(paste0("Mois ", m))
  noms[m]
}