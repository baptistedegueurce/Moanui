# =============================================================================
# functions_context_layers.R — Couches de contexte cartographique
# Gère la détection, le chargement et le rendu des shapefiles stockés dans
# www/shapefile/mapping/
#
# Principe couleurs : palette cyclique de 9 couleurs appliquées dans l'ordre
# de détection des fichiers, indépendamment de leur nom ou contenu.
# =============================================================================


# =============================================================================
# 1. PALETTE CYCLIQUE DES COUCHES DE CONTEXTE
# =============================================================================

# 9 couleurs bien distinctes, lisibles sur fonds sombres ET clairs.
# Utilisées dans l'ordre de détection des fichiers, cycliquement.
CONTEXT_PALETTE <- c(
  "#E74C3C",   # 1 — rouge vif
  "#3498DB",   # 2 — bleu ciel
  "#2ECC71",   # 3 — vert émeraude
  "#F39C12",   # 4 — orange
  "#9B59B6",   # 5 — violet
  "#1ABC9C",   # 6 — turquoise
  "#E91E63",   # 7 — rose
  "#CDDC39",   # 8 — jaune-vert
  "#FF5722"    # 9 — orange brûlé
)

# Variantes atténuées pour les thèmes clairs (même teinte, plus sombre/saturée)
CONTEXT_PALETTE_DARK <- c(
  "#C0392B",   # 1
  "#1A6DA8",   # 2
  "#1A8B4E",   # 3
  "#B7770D",   # 4
  "#7D3C98",   # 5
  "#148F77",   # 6
  "#AD1457",   # 7
  "#9EA800",   # 8
  "#BF360C"    # 9
)

#' Retourne la couleur d'une couche (index 1-based) selon le thème ggplot actif
#' @param idx      index de la couche (1 = première détectée, etc.)
#' @param theme_nom thème ggplot actif
#' @return couleur hex
couleur_contexte <- function(idx, theme_nom = "hal_dark") {
  palette <- switch(theme_nom,
                    "hal_light" = CONTEXT_PALETTE_DARK,
                    "classic"   = CONTEXT_PALETTE_DARK,
                    "minimal"   = CONTEXT_PALETTE_DARK,
                    "relief"    = CONTEXT_PALETTE_DARK,
                    CONTEXT_PALETTE   # hal_dark, ocean → palette vive
  )
  palette[((idx - 1L) %% length(palette)) + 1L]
}

#' Retourne la couleur leaflet d'une couche (toujours palette vive)
couleur_contexte_leaflet <- function(idx) {
  CONTEXT_PALETTE[((idx - 1L) %% length(CONTEXT_PALETTE)) + 1L]
}


# =============================================================================
# 2. TYPE PAR DÉFAUT SELON LE NOM DU FICHIER (heuristique)
# =============================================================================

# Si le nom du fichier contient un de ces motifs → "line", sinon → "polygon"
.LINE_PATTERNS <- c(
  "limite", "limit", "boundary", "border", "miles?", "nm", "nautical",
  "ligne", "line", "contour", "isobathe", "isoba"
)

#' Détecte si un shapefile est probablement une couche de type ligne
#' @param filename nom du fichier sans extension (en minuscules)
#' @return "line" ou "polygon"
.deviner_type <- function(filename) {
  fn_low <- tolower(filename)
  pattern <- paste(.LINE_PATTERNS, collapse = "|")
  if (grepl(pattern, fn_low)) "line" else "polygon"
}

#' Formate un nom de fichier en label lisible
#' "amp_francaises" → "Amp francaises"
#' "limite_3_miles" → "Limite 3 miles"
.formater_label <- function(filename) {
  lbl <- gsub("[_\\-\\.]", " ", filename)
  lbl <- trimws(lbl)
  paste0(toupper(substr(lbl, 1, 1)), substr(lbl, 2, nchar(lbl)))
}


# =============================================================================
# 3. DÉTECTION DES COUCHES DISPONIBLES
# =============================================================================

#' Scanne www/shapefile/mapping/ et retourne un data.frame décrivant les couches
#' disponibles, triées par nom de fichier.
#'
#' Colonnes retournées :
#'   id       — identifiant unique (nom sans extension)
#'   label    — label lisible pour l'UI
#'   path     — chemin complet vers le .shp (ou .geojson/.gpkg)
#'   type     — "polygon" ou "line"
#'   idx      — index (1-based) pour la palette cyclique
#'
#' @param mapping_dir chemin vers le dossier de mapping
#'   (défaut : "www/shapefile/mapping")
#' @return data.frame, 0 ligne si aucun fichier trouvé
detecter_couches_contexte <- function(mapping_dir = file.path("www", "shapefile", "mapping")) {
  
  if (!dir.exists(mapping_dir)) {
    return(data.frame(
      id    = character(0),
      label = character(0),
      path  = character(0),
      type  = character(0),
      idx   = integer(0),
      stringsAsFactors = FALSE
    ))
  }
  
  # Extensions supportées par sf::st_read
  extensions <- c("\\.shp$", "\\.geojson$", "\\.gpkg$", "\\.json$")
  pattern    <- paste(extensions, collapse = "|")
  
  files <- list.files(
    mapping_dir,
    pattern    = pattern,
    recursive  = FALSE,   # pas de sous-dossiers
    full.names = TRUE,
    ignore.case = TRUE
  )
  
  if (length(files) == 0) {
    return(data.frame(
      id    = character(0),
      label = character(0),
      path  = character(0),
      type  = character(0),
      idx   = integer(0),
      stringsAsFactors = FALSE
    ))
  }
  
  # Tri alphabétique pour un ordre déterministe = couleurs stables
  files <- sort(files)
  
  ids    <- tools::file_path_sans_ext(basename(files))
  labels <- vapply(ids, .formater_label, character(1))
  types  <- vapply(ids, .deviner_type,   character(1))
  
  data.frame(
    id    = ids,
    label = labels,
    path  = files,
    type  = types,
    idx   = seq_along(files),
    stringsAsFactors = FALSE
  )
}


# =============================================================================
# 4. CHARGEMENT AVEC CACHE EN MÉMOIRE
# =============================================================================

# Environnement interne pour le cache (évite de relire les .shp à chaque render)
.ctx_cache <- new.env(parent = emptyenv())

#' Charge un shapefile de contexte (avec cache par chemin)
#' @param path chemin complet vers le fichier
#' @return objet sf reprojeté en WGS84, ou NULL si erreur
charger_couche_contexte <- function(path) {
  
  cache_key <- gsub("[^a-zA-Z0-9]", "_", path)
  
  if (exists(cache_key, envir = .ctx_cache)) {
    return(get(cache_key, envir = .ctx_cache))
  }
  
  sf_obj <- tryCatch({
    obj <- sf::st_read(path, quiet = TRUE)
    if (!sf::st_is_longlat(obj)) {
      obj <- sf::st_transform(obj, crs = 4326)
    }
    obj <- sf::st_make_valid(obj)
    message(sprintf("[ctx_layers] Couche chargée : %s (%d entités)",
                    basename(path), nrow(obj)))
    obj
  }, error = function(e) {
    warning(sprintf("[ctx_layers] Erreur lecture '%s' : %s", path, e$message))
    NULL
  })
  
  if (!is.null(sf_obj)) {
    assign(cache_key, sf_obj, envir = .ctx_cache)
  }
  
  sf_obj
}

#' Vide le cache (utile si les fichiers sur disque changent)
vider_cache_contexte <- function() {
  rm(list = ls(.ctx_cache), envir = .ctx_cache)
  message("[ctx_layers] Cache vidé.")
}


# =============================================================================
# 5. AJOUT D'UNE COUCHE SUR UNE CARTE LEAFLET
# =============================================================================

#' Ajoute une couche de contexte sur une carte leaflet existante
#'
#' @param m        objet leaflet
#' @param sf_layer objet sf (WGS84)
#' @param layer_id identifiant unique de la couche (pour le groupe)
#' @param label    label pour la légende
#' @param type     "polygon" ou "line"
#' @param color    couleur hex
#' @param idx      index (pour positionner la légende)
#' @return objet leaflet modifié
ajouter_couche_leaflet <- function(m, sf_layer, layer_id, label, type, color, idx) {
  
  if (is.null(sf_layer) || nrow(sf_layer) == 0) return(m)
  
  group_name <- paste0("ctx_", layer_id)
  
  # Paramètres communs
  weight_line <- 1.5
  weight_poly <- 1.2
  
  if (type == "line") {
    
    m <- m |>
      leaflet::addPolylines(
        data    = sf_layer,
        color   = color,
        weight  = weight_line,
        opacity = 0.9,
        group   = group_name,
        popup   = paste0("<strong>", label, "</strong>")
      )
    
  } else {
    
    # Polygone : fill très transparent pour ne pas masquer les données
    fill_col   <- color
    fill_alpha <- 0.10
    
    m <- m |>
      leaflet::addPolygons(
        data        = sf_layer,
        color       = color,
        weight      = weight_poly,
        opacity     = 0.85,
        fill        = TRUE,
        fillColor   = fill_col,
        fillOpacity = fill_alpha,
        group       = group_name,
        popup       = paste0("<strong>", label, "</strong>"),
        highlight   = leaflet::highlightOptions(
          weight      = 2,
          color       = color,
          fillOpacity = 0.25,
          bringToFront = FALSE   # ne pas passer devant les données
        )
      )
  }
  
  # Légende individuelle pour cette couche
  # Position alternée selon l'index pour éviter les superpositions
  legend_pos <- if (idx %% 2 == 1) "topleft" else "topright"
  
  legend_html <- if (type == "line") {
    paste0(
      "<div style='display:flex;align-items:center;gap:6px;font-size:11px;'>",
      "<div style='width:20px;height:3px;background:", color,
      ";border-radius:2px;'></div>",
      "<span>", label, "</span></div>"
    )
  } else {
    paste0(
      "<div style='display:flex;align-items:center;gap:6px;font-size:11px;'>",
      "<div style='width:12px;height:12px;background:", color,
      ";opacity:0.7;border:2px solid ", color, ";border-radius:2px;'></div>",
      "<span>", label, "</span></div>"
    )
  }
  
  m <- m |>
    leaflet::addControl(
      html     = legend_html,
      position = legend_pos,
      layerId  = paste0("legend_ctx_", layer_id)
    )
  
  m
}


# =============================================================================
# 6. AJOUT D'UNE COUCHE SUR UNE CARTE GGPLOT
# =============================================================================

#' Ajoute une couche de contexte sur une carte ggplot existante
#'
#' La couche est rendue AU-DESSUS des terres mais SOUS les labels de zones.
#' Elle contribue à la légende via un aesthetic dédié.
#'
#' @param p         objet ggplot
#' @param sf_layer  objet sf (WGS84)
#' @param label     label pour la légende
#' @param type      "polygon" ou "line"
#' @param color     couleur hex adaptée au thème actif
#' @return objet ggplot modifié
ajouter_couche_ggplot <- function(p, sf_layer, label, type, color) {
  
  if (is.null(sf_layer) || nrow(sf_layer) == 0) return(p)
  
  if (type == "line") {
    
    p <- p +
      ggplot2::geom_sf(
        data        = sf_layer,
        color       = color,
        linewidth   = 0.8,
        linetype    = "solid",
        fill        = NA,
        inherit.aes = FALSE,
        show.legend = TRUE,
        # On mappe 'color' manuellement via un factor dummy pour la légende
        mapping     = ggplot2::aes(color = !!label)
      ) +
      ggplot2::scale_color_manual(
        values = stats::setNames(color, label),
        name   = "Couches de contexte",
        guide  = ggplot2::guide_legend(
          override.aes = list(linewidth = 1.2, linetype = "solid")
        )
      )
    
  } else {
    
    p <- p +
      ggplot2::geom_sf(
        data        = sf_layer,
        color       = color,
        linewidth   = 0.7,
        fill        = color,
        alpha       = 0.12,
        inherit.aes = FALSE,
        show.legend = TRUE,
        mapping     = ggplot2::aes(fill = !!label)
      ) +
      ggplot2::scale_fill_manual(
        values = stats::setNames(color, label),
        name   = "Couches de contexte",
        guide  = ggplot2::guide_legend(
          override.aes = list(alpha = 0.4, color = color, linewidth = 0.7)
        )
      )
  }
  
  p
}


# =============================================================================
# 7. WRAPPER PRINCIPAL : INJECTION DE TOUTES LES COUCHES ACTIVES
# =============================================================================

#' Injecte toutes les couches de contexte actives sur une carte leaflet
#'
#' @param m             objet leaflet de base (déjà construit)
#' @param layers_info   data.frame issu de detecter_couches_contexte()
#' @param active_ids    character vector des ids de couches à afficher
#' @return objet leaflet avec les couches injectées
injecter_couches_leaflet <- function(m, layers_info, active_ids) {
  
  if (is.null(layers_info) || nrow(layers_info) == 0 ||
      is.null(active_ids)  || length(active_ids) == 0) {
    return(m)
  }
  
  actives <- layers_info[layers_info$id %in% active_ids, ]
  if (nrow(actives) == 0) return(m)
  
  for (i in seq_len(nrow(actives))) {
    row   <- actives[i, ]
    sf_l  <- charger_couche_contexte(row$path)
    color <- couleur_contexte_leaflet(row$idx)
    
    m <- ajouter_couche_leaflet(
      m         = m,
      sf_layer  = sf_l,
      layer_id  = row$id,
      label     = row$label,
      type      = row$type,
      color     = color,
      idx       = row$idx
    )
  }
  
  m
}


#' Injecte toutes les couches de contexte actives sur une carte ggplot
#'
#' Doit être appelé APRÈS la construction du plot de base et AVANT coord_sf.
#' En pratique on l'appelle sur le plot complet — les geom_sf s'empilent
#' correctement par-dessus les terres grâce à l'ordre d'appel.
#'
#' @param p             objet ggplot de base
#' @param layers_info   data.frame issu de detecter_couches_contexte()
#' @param active_ids    character vector des ids de couches à afficher
#' @param theme_nom     thème ggplot actif (pour adapter les couleurs)
#' @return objet ggplot avec les couches injectées
injecter_couches_ggplot <- function(p, layers_info, active_ids, theme_nom = "hal_dark") {
  
  if (is.null(layers_info) || nrow(layers_info) == 0 ||
      is.null(active_ids)  || length(active_ids) == 0) {
    return(p)
  }
  
  actives <- layers_info[layers_info$id %in% active_ids, ]
  if (nrow(actives) == 0) return(p)
  
  # Détecter quels aesthetics sont déjà pris par le plot principal.
  # construire_carte_ggplot      → fill occupé (gradientn continu), color libre
  # construire_carte_ggplot_points avec col_color numérique → color occupé (gradientn), fill libre
  # construire_carte_ggplot_points avec col_color catégoriel → color occupé (brewer/viridis_d), fill libre
  # construire_carte_ggplot_points sans col_color → les deux libres
  #
  # Stratégie : inspecter les scales déjà présentes pour choisir l'aesthetic libre.
  scales_present <- vapply(p$scales$scales, function(s) s$aesthetics[1], character(1))
  color_pris <- any(scales_present %in% c("colour", "color"))
  fill_pris  <- any(scales_present %in% c("fill"))
  
  # Aesthetic cible pour la légende des couches de contexte :
  # on préfère "color" (pas fill) pour ne pas interférer avec la choroplèthe,
  # mais si color est déjà une échelle continue on bascule sur "fill".
  leg_aes <- if (!color_pris) "color" else if (!fill_pris) "fill" else "color"
  
  # Séparer lignes et polygones
  sf_lines    <- list()
  sf_polygons <- list()
  col_lines   <- c()
  col_polys   <- c()
  lbl_lines   <- c()
  lbl_polys   <- c()
  
  for (i in seq_len(nrow(actives))) {
    row   <- actives[i, ]
    sf_l  <- charger_couche_contexte(row$path)
    if (is.null(sf_l) || nrow(sf_l) == 0) next
    color <- couleur_contexte(row$idx, theme_nom)
    
    if (row$type == "line") {
      sf_lines[[row$id]]   <- sf_l
      col_lines[row$label] <- color
      lbl_lines <- c(lbl_lines, row$label)
    } else {
      sf_polygons[[row$id]] <- sf_l
      col_polys[row$label]  <- color
      lbl_polys <- c(lbl_polys, row$label)
    }
  }
  
  # ── Ajout des polygones (geom_sf hardcodé, sans contribution au scale) ───────
  if (length(sf_polygons) > 0) {
    for (nm in names(sf_polygons)) {
      sf_l  <- sf_polygons[[nm]]
      label <- actives$label[actives$id == nm]
      color <- col_polys[label]
      
      p <- p +
        ggplot2::geom_sf(
          data        = sf_l,
          color       = color,
          linewidth   = 0.7,
          fill        = color,
          alpha       = 0.12,
          inherit.aes = FALSE,
          show.legend = FALSE
        )
    }
  }
  
  # ── Ajout des lignes ────────────────────────────────────────────────────────
  if (length(sf_lines) > 0) {
    for (nm in names(sf_lines)) {
      sf_l  <- sf_lines[[nm]]
      label <- actives$label[actives$id == nm]
      color <- col_lines[label]
      
      p <- p +
        ggplot2::geom_sf(
          data        = sf_l,
          color       = color,
          linewidth   = 0.8,
          fill        = NA,
          inherit.aes = FALSE,
          show.legend = FALSE
        )
    }
  }
  
  # ── Légende unifiée (polygones + lignes) via geom_blank sur l'aesthetic libre ─
  all_colors <- c(col_polys, col_lines)
  all_labels <- c(lbl_polys, lbl_lines)
  
  if (length(all_labels) > 0) {
    df_ctx_leg <- data.frame(
      couche = factor(all_labels, levels = all_labels)
    )
    
    override <- if (length(col_polys) > 0 && length(col_lines) == 0) {
      # Que des polygones : carré rempli dans la légende
      list(fill = unname(col_polys), color = unname(col_polys),
           alpha = 0.4, linewidth = 0.7, linetype = "solid")
    } else if (length(col_lines) > 0 && length(col_polys) == 0) {
      # Que des lignes
      list(linewidth = 1.2, linetype = "solid")
    } else {
      # Mix : override générique
      list(linewidth = 1.0, linetype = "solid")
    }
    
    if (leg_aes == "color") {
      p <- p +
        ggplot2::geom_blank(
          data = df_ctx_leg, mapping = ggplot2::aes(color = couche),
          inherit.aes = FALSE
        ) +
        ggplot2::scale_color_manual(
          values   = all_colors,
          name     = "Couches de contexte",
          na.value = "transparent",
          guide    = ggplot2::guide_legend(override.aes = override)
        )
    } else {
      p <- p +
        ggplot2::geom_blank(
          data = df_ctx_leg, mapping = ggplot2::aes(fill = couche),
          inherit.aes = FALSE
        ) +
        ggplot2::scale_fill_manual(
          values   = all_colors,
          name     = "Couches de contexte",
          na.value = "transparent",
          guide    = ggplot2::guide_legend(override.aes = override)
        )
    }
  }
  
  p
}