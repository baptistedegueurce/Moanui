# =============================================================================
# functions_map.R — Fonctions utilitaires cartographie
# Dépendances : sf, dplyr, ggplot2, leaflet, viridis, RColorBrewer
# =============================================================================

# Opérateur null-coalescing (autonome, au cas où functions_data.R n'est pas sourcé avant)
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b
}

# Fallback label_variable si functions_data.R non sourcé
if (!exists("label_variable", mode = "function")) {
  label_variable <- function(x) x
}


# =============================================================================
# 1. CHARGEMENT SHAPEFILES
# =============================================================================

# Chemins et colonnes de jointure exacts pour les deux shapefiles ICES
# Pour div_ciem : la colonne "area_ciem" est construite au chargement en
# concaténant Major_FA + SubArea + Division (ex: "27.7.e").
SHP_CONFIG <- list(
  stat_rect = list(
    path     = file.path("www", "shapefile", "rectangle_stat",
                         "ICES_Statistical_Rectangles_Eco.shp"),
    col_join = "ICESNAME",   # ex: "24E4"
    crs      = NA            # WGS84 natif
  ),
  div_ciem = list(
    path     = file.path("www", "shapefile", "zone_ciem",
                         "ICES_Areas_20160601_cut_dense_3857.shp"),
    col_join = "area_ciem",  # colonne calculée : paste(Major_FA, SubArea, Division, sep=".")
    crs      = 3857          # Web Mercator → reprojection WGS84
  )
)


#' Charge un shapefile ICES par clé ("stat_rect" ou "div_ciem")
#' Pour div_ciem, crée la colonne area_ciem = paste(Major_FA, SubArea, Division)
#' @return objet sf reprojeté en WGS84, ou NULL si erreur
charger_shapefile <- function(nom) {
  cfg <- SHP_CONFIG[[nom]]
  if (is.null(cfg)) {
    warning("[functions_map] Clé shapefile inconnue : ", nom)
    return(NULL)
  }
  if (!file.exists(cfg$path)) {
    warning("[functions_map] Fichier .shp introuvable : ", cfg$path)
    return(NULL)
  }
  tryCatch({
    sf_obj <- sf::st_read(cfg$path, quiet = TRUE)
    
    # Reprojection en WGS84 si nécessaire
    if (!is.na(cfg$crs) && !sf::st_is_longlat(sf_obj)) {
      sf_obj <- sf::st_transform(sf_obj, crs = 4326)
    }
    
    # Validation géométrie
    sf_obj <- sf::st_make_valid(sf_obj)
    
    # ── div_ciem : construction de la colonne de jointure ──────────────────
    # Le shapefile contient Major_FA (ex: "27"), SubArea (ex: "7"),
    # Division (ex: "e"). On colle les trois pour obtenir "27.7.e".
    if (nom == "div_ciem") {
      cols_attendues <- c("Major_FA", "SubArea", "Division")
      if (all(cols_attendues %in% names(sf_obj))) {
        sf_obj$area_ciem <- paste(
          sf_obj$Major_FA,
          sf_obj$SubArea,
          sf_obj$Division,
          sep = "."
        )
        message("[functions_map] Colonne area_ciem créée pour div_ciem")
      } else if ("Area_27" %in% names(sf_obj)) {
        # Fallback si les colonnes séparées sont absentes mais Area_27 existe
        sf_obj$area_ciem <- sf_obj$Area_27
        message("[functions_map] Colonne area_ciem copiée depuis Area_27 (fallback)")
      } else {
        warning("[functions_map] Impossible de construire area_ciem : ",
                "colonnes Major_FA/SubArea/Division et Area_27 absentes du shapefile.")
      }
    }
    
    message("[functions_map] Shapefile chargé : ", nom,
            " (", nrow(sf_obj), " zones, col jointure = '", cfg$col_join, "')")
    sf_obj
    
  }, error = function(e) {
    warning("[functions_map] Erreur lecture shapefile '", nom, "' : ", e$message)
    NULL
  })
}


#' Charge un shapefile personnalisé depuis un chemin arbitraire (import utilisateur)
#' @param path      chemin vers le .shp (ou tout format sf::st_read-compatible)
#' @return objet sf reprojeté en WGS84, ou NULL si erreur
charger_shapefile_custom <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    warning("[functions_map] Fichier shapefile custom introuvable : ", path)
    return(NULL)
  }
  tryCatch({
    sf_obj <- sf::st_read(path, quiet = TRUE)
    if (!sf::st_is_longlat(sf_obj)) {
      sf_obj <- sf::st_transform(sf_obj, crs = 4326)
    }
    sf_obj <- sf::st_make_valid(sf_obj)
    message("[functions_map] Shapefile custom chargé : ", basename(path),
            " (", nrow(sf_obj), " zones, colonnes : ",
            paste(names(sf_obj)[!names(sf_obj) %in% "geometry"], collapse = ", "), ")")
    sf_obj
  }, error = function(e) {
    warning("[functions_map] Erreur lecture shapefile custom : ", e$message)
    NULL
  })
}


#' Retourne la colonne de jointure connue pour un shapefile ICES prédéfini
col_jointure_shp <- function(nom) {
  SHP_CONFIG[[nom]]$col_join %||% "ICESNAME"
}


# =============================================================================
# 2. DÉTECTION AUTOMATIQUE DU MODE GÉO
# =============================================================================

#' Détecte le mode géo probable d'un dataframe
#' @return "rect_stat" | "div_ciem" | "latlon" | "inconnu"
detecter_mode_geo <- function(df) {
  if (is.null(df)) return("inconnu")
  noms <- tolower(names(df))
  
  # Lat/Lon explicites
  a_lat <- any(noms %in% c("lat", "latitude", "lat_dd", "y"))
  a_lon <- any(noms %in% c("lon", "long", "longitude", "lon_dd", "x"))
  if (a_lat && a_lon) return("latlon")
  
  # Rectangles statistiques ICES (ex: "24E4")
  for (col in names(df)) {
    if (is.character(df[[col]]) || is.factor(df[[col]])) {
      vals <- as.character(na.omit(unique(df[[col]])))
      if (any(grepl("^\\d{2}[A-Z]\\d{1,2}$", head(vals, 30)))) return("rect_stat")
    }
  }
  
  # Divisions CIEM (ex: "27.7.e")
  for (col in names(df)) {
    if (is.character(df[[col]]) || is.factor(df[[col]])) {
      vals <- as.character(na.omit(unique(df[[col]])))
      if (any(grepl("^27\\.\\d", head(vals, 30)))) return("div_ciem")
    }
  }
  
  "inconnu"
}


#' Retourne le(s) nom(s) de colonne probable(s) selon le mode géo
colonnes_geo_probables <- function(df, mode) {
  if (is.null(df)) return(list())
  noms <- names(df)
  
  if (mode == "latlon") {
    lat_col <- noms[tolower(noms) %in% c("lat","latitude","lat_dd","y")]
    lon_col <- noms[tolower(noms) %in% c("lon","long","longitude","lon_dd","x")]
    return(list(lat = if (length(lat_col) > 0) lat_col[1] else noms[1],
                lon = if (length(lon_col) > 0) lon_col[1] else noms[1]))
  }
  
  if (mode == "rect_stat") {
    for (col in noms) {
      if (is.character(df[[col]]) || is.factor(df[[col]])) {
        vals <- as.character(na.omit(unique(df[[col]])))
        if (any(grepl("^\\d{2}[A-Z]\\d{1,2}$", head(vals, 30)))) return(list(zone = col))
      }
    }
    return(list(zone = noms[1]))
  }
  
  if (mode == "div_ciem") {
    for (col in noms) {
      if (is.character(df[[col]]) || is.factor(df[[col]])) {
        vals <- as.character(na.omit(unique(df[[col]])))
        if (any(grepl("^27\\.", head(vals, 30)))) return(list(zone = col))
      }
    }
    return(list(zone = noms[1]))
  }
  
  list(zone = noms[1])
}


# =============================================================================
# 3. AGRÉGATION ET JOINTURE SPATIALE
# =============================================================================

#' Agrège les données par zone et joint au shapefile
#' @param df          dataframe source
#' @param sf_zones    objet sf des zones (shapefile)
#' @param col_zone    nom de la colonne de jointure dans df (rect/division)
#' @param col_sf_zone nom de la colonne de jointure dans sf_zones
#' @param col_valeur  colonne à agréger (NULL pour agg_fun = "n")
#' @param agg_fun     "sum" | "mean" | "median" | "n" | "n_distinct" | "max" | "min"
#' @param col_lat     (optionnel) pour mode latlon
#' @param col_lon     (optionnel) pour mode latlon
#' @return sf avec colonne 'valeur'
agreger_par_zone <- function(df, sf_zones,
                             col_zone    = NULL,
                             col_sf_zone = NULL,
                             col_valeur  = NULL,
                             agg_fun     = "sum",
                             col_lat     = NULL,
                             col_lon     = NULL) {
  
  if (is.null(df) || is.null(sf_zones)) return(NULL)
  
  # Mode lat/lon : jointure spatiale par point-dans-polygone ─────────────────
  if (!is.null(col_lat) && !is.null(col_lon)) {
    df_valid <- df[!is.na(df[[col_lat]]) & !is.na(df[[col_lon]]), ]
    pts <- tryCatch(
      sf::st_as_sf(df_valid, coords = c(col_lon, col_lat), crs = 4326),
      error = function(e) { warning("Erreur conversion lat/lon : ", e$message); NULL }
    )
    if (is.null(pts)) return(NULL)
    joined <- tryCatch(
      sf::st_join(pts, sf_zones[, col_sf_zone], join = sf::st_within),
      error = function(e) { warning("Erreur st_join : ", e$message); NULL }
    )
    if (is.null(joined)) return(NULL)
    df <- as.data.frame(joined)
    df <- df[!is.na(df[[col_sf_zone]]), ]
    col_zone <- col_sf_zone
  }
  
  # Vérification colonne zone ────────────────────────────────────────────────
  if (is.null(col_zone) || !col_zone %in% names(df)) return(NULL)
  
  # Agrégation ───────────────────────────────────────────────────────────────
  df_agg <- switch(agg_fun,
                   
                   "n" = {
                     df |>
                       dplyr::group_by(zone_id = .data[[col_zone]]) |>
                       dplyr::summarise(valeur = dplyr::n(), .groups = "drop")
                   },
                   
                   "n_distinct" = {
                     if (is.null(col_valeur) || !col_valeur %in% names(df)) return(NULL)
                     df |>
                       dplyr::group_by(zone_id = .data[[col_zone]]) |>
                       dplyr::summarise(valeur = dplyr::n_distinct(.data[[col_valeur]],
                                                                   na.rm = TRUE),
                                        .groups = "drop")
                   },
                   
                   {
                     # Fonctions numériques classiques : sum, mean, median, max, min
                     if (is.null(col_valeur) || !col_valeur %in% names(df)) return(NULL)
                     fun <- switch(agg_fun,
                                   "sum"    = function(x) sum(x,             na.rm = TRUE),
                                   "mean"   = function(x) mean(x,            na.rm = TRUE),
                                   "median" = function(x) stats::median(x,   na.rm = TRUE),
                                   "max"    = function(x) max(x,             na.rm = TRUE),
                                   "min"    = function(x) min(x,             na.rm = TRUE),
                                   function(x) sum(x, na.rm = TRUE)   # fallback
                     )
                     df |>
                       dplyr::group_by(zone_id = .data[[col_zone]]) |>
                       dplyr::summarise(valeur = fun(.data[[col_valeur]]), .groups = "drop")
                   }
  )
  
  # Jointure avec sf ─────────────────────────────────────────────────────────
  if (is.null(col_sf_zone) || !col_sf_zone %in% names(sf_zones)) {
    col_sf_zone <- names(sf_zones)[1]
  }
  
  # Diagnostic de correspondance avant jointure
  vals_df  <- unique(df_agg$zone_id)
  vals_shp <- unique(as.character(sf_zones[[col_sf_zone]]))
  n_match  <- sum(vals_df %in% vals_shp)
  message(sprintf("[functions_map] Jointure — col données='%s' (%d valeurs uniques) / col shp='%s' (%d zones)",
                  col_sf_zone, length(vals_df), col_sf_zone, length(vals_shp)))
  message(sprintf("[functions_map] Correspondances : %d / %d valeurs trouvées dans le shapefile",
                  n_match, length(vals_df)))
  if (n_match == 0) {
    message("[functions_map] ATTENTION : 0 correspondance ! Exemples données : ",
            paste(head(vals_df, 5), collapse = ", "))
    message("[functions_map] ATTENTION : Exemples shapefile : ",
            paste(head(vals_shp, 5), collapse = ", "))
  } else if (n_match < length(vals_df)) {
    non_match <- vals_df[!vals_df %in% vals_shp]
    message("[functions_map] Valeurs sans correspondance dans le shp : ",
            paste(head(non_match, 10), collapse = ", "))
  }
  
  sf_result <- sf_zones |>
    dplyr::left_join(df_agg,
                     by = stats::setNames("zone_id", col_sf_zone))
  
  sf_result
}


# =============================================================================
# 4. BBOX DES PRESETS
# =============================================================================

#' Retourne la bbox [lon_min, lat_min, lon_max, lat_max] d'un preset
bbox_preset <- function(preset) {
  presets <- list(
    bretagne       = c(-5.5,  47.0,  -0.5, 49.5),
    golfe_gascogne = c(-9.0,  43.0,  -1.0, 48.5),
    manche         = c(-5.5,  48.5,   2.5, 51.5),
    mer_nord       = c(-2.0,  50.5,   9.0, 58.0),
    atlantique_ne  = c(-20.0, 40.0,  10.0, 65.0)
  )
  presets[[preset]] %||% c(-5.5, 47.0, -0.5, 49.5)
}


# =============================================================================
# 5. PALETTE DE COULEURS
# =============================================================================

#' Retourne une fonction de palette colorRamp pour leaflet, ou un vecteur pour ggplot
#' @param valeurs  si fourni, retourne une leaflet::colorNumeric() ; sinon un vecteur hex
palette_map <- function(nom, reverse = FALSE, valeurs = NULL) {
  
  if (nom == "hal") {
    cols <- c("#061A2B", "#0B2A3D", "#0077B6", "#00B4D8", "#90E0EF", "#FFDD57")
    if (reverse) cols <- rev(cols)
    if (!is.null(valeurs))
      return(leaflet::colorNumeric(cols, domain = valeurs, na.color = "transparent"))
    return(cols)
  }
  
  if (nom %in% c("viridis", "plasma")) {
    pal_fn <- if (nom == "viridis") viridis::viridis else viridis::plasma
    cols   <- pal_fn(256, direction = if (reverse) -1 else 1)
    if (!is.null(valeurs))
      return(leaflet::colorNumeric(cols, domain = valeurs, na.color = "transparent"))
    return(cols)
  }
  
  # RColorBrewer
  n_max <- RColorBrewer::brewer.pal.info[nom, "maxcolors"]
  n_use <- min(9L, n_max)
  cols  <- RColorBrewer::brewer.pal(n_use, nom)
  if (reverse) cols <- rev(cols)
  if (!is.null(valeurs))
    return(leaflet::colorNumeric(cols, domain = valeurs, na.color = "transparent"))
  cols
}


# =============================================================================
# 6. THÈMES FOND DE CARTE GGPLOT
# =============================================================================

#' Retourne les paramètres visuels (couleurs + theme ggplot) selon le preset
theme_map_gg <- function(theme_nom = "hal_dark") {
  
  base <- switch(theme_nom,
                 
                 "hal_dark" = list(
                   bg        = "#061A2B",
                   sea       = "#0B2A3D",
                   land      = "#123A52",
                   border    = "#1D4E6D",
                   text      = "#EAF2F8",
                   grid      = "#1D4E6D",
                   gg_theme  = ggplot2::theme(
                     plot.background   = ggplot2::element_rect(fill = "#061A2B", color = NA),
                     panel.background  = ggplot2::element_rect(fill = "#0B2A3D", color = NA),
                     panel.grid.major  = ggplot2::element_line(color = "#1D4E6D", linewidth = 0.2),
                     panel.grid.minor  = ggplot2::element_blank(),
                     axis.text         = ggplot2::element_text(color = "#7FB3D3", size = 8),
                     axis.title        = ggplot2::element_blank(),
                     plot.title        = ggplot2::element_text(color = "#EAF2F8", size = 14, face = "bold"),
                     plot.subtitle     = ggplot2::element_text(color = "#7FB3D3", size = 10),
                     plot.caption      = ggplot2::element_text(color = "#7FB3D3", size = 8),
                     legend.background = ggplot2::element_rect(fill = "#0B2A3D", color = "#1D4E6D"),
                     legend.text       = ggplot2::element_text(color = "#EAF2F8", size = 8),
                     legend.title      = ggplot2::element_text(color = "#7FB3D3", size = 9, face = "bold")
                   )
                 ),
                 
                 "hal_light" = list(
                   bg        = "#F0F6FA",
                   sea       = "#D0E8F5",
                   land      = "#E8F4F8",
                   border    = "#A0C4DC",
                   text      = "#0B2A3D",
                   grid      = "#C5DCE8",
                   gg_theme  = ggplot2::theme(
                     plot.background   = ggplot2::element_rect(fill = "#F0F6FA", color = NA),
                     panel.background  = ggplot2::element_rect(fill = "#D0E8F5", color = NA),
                     panel.grid.major  = ggplot2::element_line(color = "#C5DCE8", linewidth = 0.2),
                     panel.grid.minor  = ggplot2::element_blank(),
                     axis.text         = ggplot2::element_text(color = "#0B2A3D", size = 8),
                     axis.title        = ggplot2::element_blank(),
                     plot.title        = ggplot2::element_text(color = "#0B2A3D", size = 14, face = "bold"),
                     plot.subtitle     = ggplot2::element_text(color = "#1D4E6D", size = 10),
                     plot.caption      = ggplot2::element_text(color = "#1D4E6D", size = 8),
                     legend.background = ggplot2::element_rect(fill = "#F0F6FA", color = "#A0C4DC"),
                     legend.text       = ggplot2::element_text(color = "#0B2A3D", size = 8),
                     legend.title      = ggplot2::element_text(color = "#1D4E6D", size = 9, face = "bold")
                   )
                 ),
                 
                 "classic" = list(
                   bg = "white", sea = "#E8F4F8", land = "#F5F5F0",
                   border = "#999", text = "#222", grid = "#ddd",
                   gg_theme = ggplot2::theme_bw(base_size = 11)
                 ),
                 
                 "minimal" = list(
                   bg = "#FAFAFA", sea = "#EEF5FB", land = "#F0F0EC",
                   border = "#ccc", text = "#333", grid = "#eee",
                   gg_theme = ggplot2::theme_minimal(base_size = 11)
                 ),
                 
                 "ocean" = list(
                   bg = "#002B47", sea = "#003D5B", land = "#1A5276",
                   border = "#2E86C1", text = "#AED6F1", grid = "#1A5276",
                   gg_theme = ggplot2::theme(
                     plot.background   = ggplot2::element_rect(fill = "#002B47", color = NA),
                     panel.background  = ggplot2::element_rect(fill = "#003D5B", color = NA),
                     panel.grid.major  = ggplot2::element_line(color = "#1A5276", linewidth = 0.2),
                     panel.grid.minor  = ggplot2::element_blank(),
                     axis.text         = ggplot2::element_text(color = "#AED6F1", size = 8),
                     axis.title        = ggplot2::element_blank(),
                     plot.title        = ggplot2::element_text(color = "#AED6F1", size = 14, face = "bold"),
                     plot.subtitle     = ggplot2::element_text(color = "#AED6F1", size = 10),
                     plot.caption      = ggplot2::element_text(color = "#AED6F1", size = 8),
                     legend.background = ggplot2::element_rect(fill = "#002B47", color = "#2E86C1"),
                     legend.text       = ggplot2::element_text(color = "#AED6F1", size = 8),
                     legend.title      = ggplot2::element_text(color = "#AED6F1", size = 9, face = "bold")
                   )
                 ),
                 
                 "relief" = list(
                   bg = "#F5F0E8", sea = "#C8DCE8", land = "#E8DCC8",
                   border = "#8B7355", text = "#3E2723", grid = "#D5C9B5",
                   gg_theme = ggplot2::theme_classic(base_size = 11)
                 ),
                 
                 # fallback
                 list(
                   bg = "#061A2B", sea = "#0B2A3D", land = "#123A52",
                   border = "#1D4E6D", text = "#EAF2F8", grid = "#1D4E6D",
                   gg_theme = ggplot2::theme_void()
                 )
  )
  
  base
}


# =============================================================================
# 7. LABEL FONCTION AGRÉGATION
# =============================================================================

#' Retourne le label lisible d'une fonction d'agrégation
label_agg_fun <- function(agg_fun) {
  switch(agg_fun,
         "sum"      = "Somme",
         "mean"     = "Moyenne",
         "median"   = "Médiane",
         "n"        = "Comptage",
         "n_distinct" = "Nb unique",
         "max"      = "Maximum",
         "min"      = "Minimum",
         "Valeur"
  )
}


# =============================================================================
# 8. CONSTRUCTION CARTE GGPLOT
# =============================================================================

#' Construit la carte ggplot à partir du sf agrégé
construire_carte_ggplot <- function(sf_data,
                                    bbox,
                                    palette_nom   = "hal",
                                    reverse_pal   = FALSE,
                                    alpha         = 0.75,
                                    theme_nom     = "hal_dark",
                                    titre         = "",
                                    soustitre     = "",
                                    caption       = "",
                                    show_labels   = FALSE,
                                    label_size    = 3,
                                    show_borders  = TRUE,
                                    col_label     = NULL,
                                    agg_fun       = "sum",
                                    legende_titre = NULL) {
  
  if (is.null(sf_data)) return(ggplot2::ggplot() + ggplot2::theme_void())
  
  th   <- theme_map_gg(theme_nom)
  cols <- palette_map(palette_nom, reverse = reverse_pal)
  
  # Couche terres — monde entier
  sf_land <- tryCatch(
    rnaturalearth::ne_countries(scale = "medium", returnclass = "sf"),
    error = function(e) NULL
  )
  
  p <- ggplot2::ggplot() +
    # 1. Données (polygones colorés) en fond
    ggplot2::geom_sf(data      = sf_data,
                     ggplot2::aes(fill = valeur),
                     color     = th$border,
                     linewidth = 0.3,
                     alpha     = alpha) +
    ggplot2::scale_fill_gradientn(
      colours  = cols,
      na.value = "transparent",
      name     = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
        trimws(legende_titre) else label_agg_fun(agg_fun),
      labels   = scales::label_number(big.mark = "\u202f", accuracy = 1)
    ) +
    # 2. Fond terres PAR-DESSUS les données (toujours visible — masque les zones sans données)
    { if (!is.null(sf_land))
      ggplot2::geom_sf(data        = sf_land,
                       fill        = th$land,
                       color       = NA,
                       linewidth   = 0,
                       inherit.aes = FALSE)
    } +
    # 3. Frontières terrestres (lignes seules) — uniquement si show_borders = TRUE
    { if (show_borders && !is.null(sf_land))
      ggplot2::geom_sf(data        = sf_land,
                       fill        = NA,
                       color       = th$border,
                       linewidth   = 0.4,
                       inherit.aes = FALSE)
    } +
    # 3. Zoom cale sur la bbox du preset
    #    default_crs = 4326 empeche ggplot2 de recalculer l'etendue
    #    depuis l'emprise mondiale de sf_land
    ggplot2::coord_sf(
      xlim        = c(bbox[1], bbox[3]),
      ylim        = c(bbox[2], bbox[4]),
      expand      = FALSE,
      default_crs = sf::st_crs(4326)
    ) +
    ggplot2::labs(
      title    = titre,
      subtitle = soustitre,
      caption  = caption
    ) +
    th$gg_theme
  
  # Labels zones
  if (show_labels && !is.null(col_label) && col_label %in% names(sf_data)) {
    centres <- suppressWarnings(sf::st_point_on_surface(sf_data))
    p <- p + ggplot2::geom_sf_text(
      data     = centres,
      ggplot2::aes(label = .data[[col_label]]),
      size     = label_size,
      color    = th$text,
      fontface = "bold"
    )
  }
  
  p
}


# =============================================================================
# 9. CONSTRUCTION CARTE LEAFLET
# =============================================================================

#' Construit la carte leaflet interactive
construire_carte_leaflet <- function(sf_data,
                                     bbox,
                                     palette_nom    = "hal",
                                     reverse_pal    = FALSE,
                                     alpha          = 0.75,
                                     show_labels    = FALSE,
                                     col_label      = NULL,
                                     agg_fun        = "sum",
                                     legende_titre  = NULL) {
  
  if (is.null(sf_data)) {
    return(leaflet::leaflet() |>
             leaflet::addProviderTiles(leaflet::providers$CartoDB.DarkMatter) |>
             leaflet::setView(lng = -3, lat = 48, zoom = 6))
  }
  
  vals      <- sf_data$valeur
  pal_fn    <- palette_map(palette_nom, reverse = reverse_pal, valeurs = vals)
  label_fun <- if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
    trimws(legende_titre) else label_agg_fun(agg_fun)
  
  # Popup HTML
  popup_txt <- if (!is.null(col_label) && col_label %in% names(sf_data)) {
    paste0(
      "<strong>Zone : </strong>", sf_data[[col_label]], "<br>",
      "<strong>", label_fun, " : </strong>",
      format(round(vals, 2), big.mark = "\u202f", nsmall = 0)
    )
  } else {
    paste0(
      "<strong>", label_fun, " : </strong>",
      format(round(vals, 2), big.mark = "\u202f", nsmall = 0)
    )
  }
  
  m <- leaflet::leaflet(sf_data) |>
    leaflet::addProviderTiles(
      leaflet::providers$CartoDB.DarkMatter,
      options = leaflet::providerTileOptions(opacity = 0.9)
    ) |>
    leaflet::fitBounds(
      lng1 = bbox[1], lat1 = bbox[2],
      lng2 = bbox[3], lat2 = bbox[4]
    ) |>
    leaflet::addPolygons(
      fillColor   = ~pal_fn(valeur),
      fillOpacity = alpha,
      color       = "#1D4E6D",
      weight      = 0.8,
      opacity     = 1,
      popup       = popup_txt,
      highlight   = leaflet::highlightOptions(
        weight       = 2,
        color        = "#00B4D8",
        fillOpacity  = min(alpha + 0.1, 1),
        bringToFront = TRUE
      )
    ) |>
    leaflet::addLegend(
      position  = "bottomright",
      pal       = pal_fn,
      values    = ~valeur,
      title     = label_fun,
      opacity   = 0.9,
      labFormat = leaflet::labelFormat(big.mark = "\u202f", digits = 0)
    )
  
  # Labels zones
  if (show_labels && !is.null(col_label) && col_label %in% names(sf_data)) {
    # st_point_on_surface est plus robuste que st_centroid pour les données lon/lat
    centres <- suppressWarnings(sf::st_point_on_surface(sf_data))
    # .data[[]] n'est pas disponible dans les formules leaflet → extraction directe
    centres$label_txt <- as.character(centres[[col_label]])
    m <- m |> leaflet::addLabelOnlyMarkers(
      data  = centres,
      label = ~label_txt,
      labelOptions = leaflet::labelOptions(
        noHide   = TRUE,
        textOnly = TRUE,
        style    = list("color" = "white", "font-weight" = "bold", "font-size" = "9px")
      )
    )
  }
  
  m
}


# =============================================================================
# 10. GÉNÉRATION CODE R ÉQUIVALENT
# =============================================================================

#' Génère le code R reproductible correspondant aux paramètres actifs
generer_code_r_map <- function(shapefile_nom, col_zone, col_valeur,
                               agg_fun, palette_nom, theme_nom,
                               bbox, titre, caption) {
  
  # ── En-tête packages ────────────────────────────────────────────────────────
  header <- paste0(
    "# Packages\n",
    "library(sf)\n",
    "library(dplyr)\n",
    "library(ggplot2)\n"
  )
  
  # ── Chargement shapefile ────────────────────────────────────────────────────
  shp_block <- if (shapefile_nom == "stat_rect") {
    paste0(
      "\n# Charger shapefile rectangles stat ICES\n",
      'sf_zones <- sf::st_read("www/shapefile/rect_stat/',
      'ICES_Statistical_Rectangles_Eco.shp")\n',
      "sf_zones <- sf::st_make_valid(sf_zones)\n",
      'col_sf_zone <- "ICESNAME"   # colonne de jointure\n'
    )
  } else if (shapefile_nom == "div_ciem") {
    paste0(
      "\n# Charger shapefile divisions CIEM\n",
      'sf_zones <- sf::st_read("www/shapefile/zone_ciem/',
      'ICES_Areas_20160601_cut_dense_3857.shp")\n',
      "sf_zones <- sf::st_transform(sf_zones, crs = 4326)\n",
      "sf_zones <- sf::st_make_valid(sf_zones)\n",
      "# Construction de la colonne de jointure area_ciem\n",
      'sf_zones$area_ciem <- paste(sf_zones$Major_FA,\n',
      '                            sf_zones$SubArea,\n',
      '                            sf_zones$Division, sep = ".")\n',
      'col_sf_zone <- "area_ciem"   # colonne de jointure\n'
    )
  } else {
    paste0(
      "\n# Charger shapefile personnalise\n",
      'sf_zones <- sf::st_read("chemin/vers/votre_shapefile.shp")\n',
      "sf_zones <- sf::st_transform(sf_zones, crs = 4326)\n",
      'col_sf_zone <- "votre_colonne_jointure"\n'
    )
  }
  
  # ── Chargement données ──────────────────────────────────────────────────────
  data_block <- paste0(
    "\n# Charger données\n",
    'df <- readRDS("votre_fichier.rds")\n',
    "# ou : df <- read.csv2('votre_fichier.csv')\n"
  )
  
  # ── Agrégation ──────────────────────────────────────────────────────────────
  agg_block <- if (agg_fun == "n") {
    paste0(
      "\n# Agrégation : comptage de lignes par zone\n",
      "df_agg <- df |>\n",
      "  dplyr::group_by(zone_id = ", col_zone, ") |>\n",
      "  dplyr::summarise(valeur = dplyr::n(), .groups = 'drop')\n"
    )
  } else if (agg_fun == "n_distinct") {
    paste0(
      "\n# Agrégation : nombre de valeurs uniques de '", col_valeur, "' par zone\n",
      "df_agg <- df |>\n",
      "  dplyr::group_by(zone_id = ", col_zone, ") |>\n",
      "  dplyr::summarise(valeur = dplyr::n_distinct(",
      col_valeur, ", na.rm = TRUE), .groups = 'drop')\n"
    )
  } else {
    fun_r <- switch(agg_fun,
                    "sum"    = "sum",
                    "mean"   = "mean",
                    "median" = "median",
                    "max"    = "max",
                    "min"    = "min",
                    "sum")
    paste0(
      "\n# Agrégation : ", label_agg_fun(agg_fun),
      " de '", col_valeur %||% "votre_variable", "' par zone\n",
      "df_agg <- df |>\n",
      "  dplyr::group_by(zone_id = ", col_zone, ") |>\n",
      "  dplyr::summarise(valeur = ", fun_r, "(",
      col_valeur %||% "votre_variable", ", na.rm = TRUE), .groups = 'drop')\n"
    )
  }
  
  # ── Jointure ─────────────────────────────────────────────────────────────────
  join_block <- paste0(
    "\n# Jointure avec shapefile\n",
    "sf_data <- sf_zones |>\n",
    "  dplyr::left_join(df_agg, by = setNames('zone_id', col_sf_zone))\n"
  )
  
  # ── Carte ggplot ─────────────────────────────────────────────────────────────
  pal_code <- if (palette_nom == "hal") {
    paste0(
      '  ggplot2::scale_fill_gradientn(\n',
      '    colours  = c("#061A2B","#0077B6","#00B4D8","#90E0EF","#FFDD57"),\n',
      '    na.value = "transparent", name = "', label_agg_fun(agg_fun), '"\n',
      '  ) +\n'
    )
  } else if (palette_nom %in% c("viridis", "plasma")) {
    paste0('  ggplot2::scale_fill_viridis_c(option = "', palette_nom,
           '", na.value = "transparent") +\n')
  } else {
    paste0('  ggplot2::scale_fill_distiller(palette = "', palette_nom,
           '", na.value = "transparent") +\n')
  }
  
  map_block <- paste0(
    "\n# Carte\n",
    "ggplot2::ggplot(sf_data) +\n",
    "  ggplot2::geom_sf(ggplot2::aes(fill = valeur), alpha = 0.75,\n",
    "                   color = '#1D4E6D', linewidth = 0.3) +\n",
    pal_code,
    "  ggplot2::coord_sf(xlim = c(", bbox[1], ", ", bbox[3], "),\n",
    "                    ylim = c(", bbox[2], ", ", bbox[4], "),\n",
    "                    expand = FALSE) +\n",
    "  ggplot2::labs(title   = '", titre,   "',\n",
    "               caption = '", caption, "') +\n",
    "  ggplot2::theme_minimal()\n"
  )
  
  paste0(header, shp_block, data_block, agg_block, join_block, map_block)
}

# =============================================================================
# 11. CONSTRUCTION CARTE LEAFLET — MODE POINTS PURS
# =============================================================================

#' Construit une carte leaflet interactive affichant des points bruts (sans shapefile)
#' @param sf_pts     objet sf de géométrie POINT
#' @param bbox       vecteur c(lon_min, lat_min, lon_max, lat_max)
#' @param col_color  colonne pour colorier les points (NULL ou "" = couleur fixe)
#' @param col_size   colonne numérique pour taille variable (NULL ou "" = taille fixe)
#' @param pt_size    taille fixe des points (rayon en pixels)
#' @param palette_nom palette HAL/viridis/etc. pour variables numériques
#' @param reverse_pal inverser la palette
#' @param alpha      opacité (0-1)
construire_carte_leaflet_points <- function(sf_pts,
                                            bbox,
                                            col_color    = NULL,
                                            col_size     = NULL,
                                            pt_size      = 6,
                                            palette_nom  = "hal",
                                            reverse_pal  = FALSE,
                                            alpha        = 0.75,
                                            legende_titre = NULL) {
  
  if (is.null(sf_pts)) {
    return(leaflet::leaflet() |>
             leaflet::addProviderTiles(leaflet::providers$CartoDB.DarkMatter) |>
             leaflet::setView(lng = -3, lat = 48, zoom = 6))
  }
  
  use_color <- !is.null(col_color) && nchar(col_color) > 0 && col_color %in% names(sf_pts)
  use_size  <- !is.null(col_size)  && nchar(col_size)  > 0 && col_size  %in% names(sf_pts)
  
  # Rayon : fixe ou proportionnel à une variable numérique
  radius_vals <- if (use_size) {
    sz_raw <- as.numeric(sf_pts[[col_size]])
    sz_raw[is.na(sz_raw)] <- 0
    sz_min <- min(sz_raw, na.rm = TRUE)
    sz_max <- max(sz_raw, na.rm = TRUE)
    if (sz_max > sz_min)
      2 + 12 * (sz_raw - sz_min) / (sz_max - sz_min)
    else
      rep(pt_size, nrow(sf_pts))
  } else {
    pt_size
  }
  
  m <- leaflet::leaflet(sf_pts) |>
    leaflet::addProviderTiles(
      leaflet::providers$CartoDB.DarkMatter,
      options = leaflet::providerTileOptions(opacity = 0.9)
    ) |>
    leaflet::fitBounds(
      lng1 = bbox[1], lat1 = bbox[2],
      lng2 = bbox[3], lat2 = bbox[4]
    )
  
  if (use_color) {
    vals <- sf_pts[[col_color]]
    
    if (is.numeric(vals)) {
      # Variable numérique → palette continue
      pal_fn  <- palette_map(palette_nom, reverse = reverse_pal, valeurs = vals)
      col_vec <- pal_fn(vals)
      popup_txt <- paste0(
        "<strong>", col_color, " : </strong>",
        format(round(vals, 3), big.mark = "\u202f")
      )
      m <- m |>
        leaflet::addCircleMarkers(
          radius      = radius_vals,
          color       = col_vec,
          fillColor   = col_vec,
          fillOpacity = alpha,
          opacity     = 1,
          weight      = 1,
          popup       = popup_txt
        ) |>
        leaflet::addLegend(
          position  = "bottomright",
          pal       = pal_fn,
          values    = vals,
          title     = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
            trimws(legende_titre) else col_color,
          opacity   = 0.9,
          labFormat = leaflet::labelFormat(big.mark = "\u202f", digits = 2)
        )
      
    } else {
      # Variable catégorielle → palette qualitative
      vals_chr <- as.character(vals)
      lvls     <- sort(unique(vals_chr[!is.na(vals_chr)]))
      # Palette robuste : Set1 jusqu'à 8 catégories, sinon palette étendue
      pal_cols <- if (length(lvls) <= 8) {
        RColorBrewer::brewer.pal(max(3, length(lvls)), "Set1")[seq_len(length(lvls))]
      } else {
        grDevices::rainbow(length(lvls))
      }
      pal_fn  <- leaflet::colorFactor(palette = pal_cols, domain = lvls)
      col_vec <- pal_fn(vals_chr)
      popup_txt <- paste0("<strong>", col_color, " : </strong>", vals_chr)
      m <- m |>
        leaflet::addCircleMarkers(
          radius      = radius_vals,
          color       = col_vec,
          fillColor   = col_vec,
          fillOpacity = alpha,
          opacity     = 1,
          weight      = 1,
          popup       = popup_txt
        ) |>
        leaflet::addLegend(
          position = "bottomright",
          pal      = pal_fn,
          values   = vals_chr,
          title    = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
            trimws(legende_titre) else col_color,
          opacity  = 0.9
        )
    }
    
  } else {
    # Pas de variable couleur → couleur fixe HAL
    m <- m |>
      leaflet::addCircleMarkers(
        radius      = radius_vals,
        color       = "#00B4D8",
        fillColor   = "#00B4D8",
        fillOpacity = alpha,
        opacity     = 1,
        weight      = 1
      )
  }
  
  m
}


# =============================================================================
# 12. CONSTRUCTION CARTE GGPLOT — MODE POINTS PURS
# =============================================================================

#' Construit une carte ggplot statique affichant des points bruts (sans shapefile)
#' @param sf_pts     objet sf de géométrie POINT
#' @param bbox       vecteur c(lon_min, lat_min, lon_max, lat_max)
#' @param col_color  colonne pour colorier les points (NULL ou "" = couleur fixe)
#' @param col_size   colonne numérique pour taille variable (NULL ou "" = taille fixe)
#' @param pt_size    taille fixe des points (unités ggplot)
#' @param alpha      opacité (0-1)
#' @param palette_nom palette pour variables numériques
#' @param reverse_pal inverser la palette
#' @param theme_nom  thème fond de carte
#' @param titre / soustitre / caption  textes de la figure
construire_carte_ggplot_points <- function(sf_pts,
                                           bbox,
                                           col_color     = NULL,
                                           col_size      = NULL,
                                           pt_size       = 2,
                                           alpha         = 0.75,
                                           palette_nom   = "hal",
                                           reverse_pal   = FALSE,
                                           theme_nom     = "hal_dark",
                                           titre         = "",
                                           soustitre     = "",
                                           caption       = "",
                                           legende_titre = NULL) {
  
  if (is.null(sf_pts)) return(ggplot2::ggplot() + ggplot2::theme_void())
  
  th   <- theme_map_gg(theme_nom)
  cols <- palette_map(palette_nom, reverse = reverse_pal)
  
  sf_land <- tryCatch(
    rnaturalearth::ne_countries(scale = "medium", returnclass = "sf"),
    error = function(e) NULL
  )
  
  use_color <- !is.null(col_color) && nchar(col_color) > 0 && col_color %in% names(sf_pts)
  use_size  <- !is.null(col_size)  && nchar(col_size)  > 0 && col_size  %in% names(sf_pts)
  
  # Construction de l'aes dynamique
  aes_list <- list()
  if (use_color) aes_list$color <- as.name(col_color)
  if (use_size)  aes_list$size  <- as.name(col_size)
  pts_aes <- if (length(aes_list) > 0) do.call(ggplot2::aes, aes_list) else ggplot2::aes()
  
  p <- ggplot2::ggplot() +
    # 1. Couche terres en fond
    { if (!is.null(sf_land))
      ggplot2::geom_sf(data = sf_land, fill = th$land, color = th$border,
                       linewidth = 0.3, inherit.aes = FALSE)
    } +
    # 2. Points
    if (use_color) {
      ggplot2::geom_sf(data = sf_pts, mapping = pts_aes,
                       size = if (!use_size) pt_size else NULL,
                       alpha = alpha, inherit.aes = FALSE)
    } else {
      ggplot2::geom_sf(data = sf_pts, mapping = pts_aes,
                       color = "#00B4D8", fill = "#00B4D8",
                       size = if (!use_size) pt_size else NULL,
                       alpha = alpha, inherit.aes = FALSE)
    }
  
  # 3. Échelle couleur
  if (use_color) {
    if (is.numeric(sf_pts[[col_color]])) {
      p <- p + ggplot2::scale_color_gradientn(
        colours = cols,
        name    = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
          trimws(legende_titre) else col_color,
        na.value = "#555555"
      )
    } else {
      n_cats <- length(unique(sf_pts[[col_color]][!is.na(sf_pts[[col_color]])]))
      if (n_cats <= 8) {
        p <- p + ggplot2::scale_color_brewer(
          palette = "Set1",
          name    = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
            trimws(legende_titre) else col_color)
      } else {
        p <- p + ggplot2::scale_color_viridis_d(
          name   = if (!is.null(legende_titre) && nchar(trimws(legende_titre)) > 0)
            trimws(legende_titre) else col_color,
          option = "turbo")
      }
    }
  }
  
  # 4. Échelle taille
  if (use_size) {
    p <- p + ggplot2::scale_size_continuous(name = col_size, range = c(0.5, 5))
  }
  
  p <- p +
    ggplot2::coord_sf(
      xlim        = c(bbox[1], bbox[3]),
      ylim        = c(bbox[2], bbox[4]),
      expand      = FALSE,
      default_crs = sf::st_crs(4326)
    ) +
    ggplot2::labs(title = titre, subtitle = soustitre, caption = caption) +
    th$gg_theme
  
  p
}