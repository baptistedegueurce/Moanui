# =============================================================================
# functions_viz.R — Moteur graphique complet (ggplot2 → plotly)
# Objectif : couvrir tout ggplot via interface, sans code utilisateur
# =============================================================================

# -----------------------------------------------------------------------------
# 1. PALETTES
# -----------------------------------------------------------------------------

palette_hal <- c(
  "#0077B6","#2E9E6B","#E07B39","#9B59B6",
  "#C0392B","#16A085","#F39C12","#7FB3D3",
  "#27AE60","#8E44AD","#D35400","#1ABC9C"
)

palette_categories_rich <- c(
  "#0077B6","#2E9E6B","#E07B39","#9B59B6","#C0392B",
  "#16A085","#F39C12","#7FB3D3","#27AE60","#8E44AD",
  "#D35400","#1ABC9C","#34495E","#D68910","#6C3483",
  "#117A65","#A93226","#512E5F","#0C5460","#7D6608"
)

PALETTES_DISPONIBLES <- list(
  "CRPMEM (défaut)"   = palette_hal,
  "Catégoriel riche"  = palette_categories_rich,
  "Bleus océan"       = c("#03045E","#0077B6","#00B4D8","#90E0EF","#CAF0F8"),
  "Verts nature"      = c("#1B4332","#2D6A4F","#40916C","#52B788","#95D5B2"),
  "Chaleur"           = c("#370617","#6A040F","#9D0208","#D00000","#E85D04",
                          "#F48C06","#FAA307","#FFBA08"),
  "Pastel marin"      = c("#264653","#2A9D8F","#E9C46A","#F4A261","#E76F51"),
  "Monochrome bleu"   = c("#03045E","#023E8A","#0077B6","#0096C7","#00B4D8",
                          "#48CAE4","#90E0EF","#ADE8F4","#CAF0F8")
)

# -----------------------------------------------------------------------------
# 2. HELPERS
# -----------------------------------------------------------------------------

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

cols_numeriques <- function(df) {
  if (is.null(df)) return(character(0))
  names(df)[sapply(df, is.numeric)]
}

cols_categories <- function(df) {
  if (is.null(df)) return(character(0))
  names(df)[sapply(df, function(x) is.character(x) || is.factor(x))]
}

label_variable <- function(var) {
  if (is.null(var) || !nzchar(var)) return("")
  lbls <- c(
    engin_cod          = "Engin",
    esp_cod_fao        = "Espece (FAO)",
    div_ciem_cod_sipa  = "Division CIEM",
    stat_rect          = "Rectangle stat.",
    quartier_cod       = "Quartier",
    nom_navire         = "Navire",
    port_debarque      = "Port de debarque",
    NS                 = "Nord / Sud",
    an_ref             = "Annee",
    mois_ref           = "Mois",
    trim_ref           = "Trimestre",
    debarquement_Kg    = "Debarquements (kg)",
    debarquement_euros = "Debarquements (EUR)",
    cpue_kg_jdm        = "CPUE (kg/JdM)",
    prix_moyen_kg      = "Prix moyen (EUR/kg)",
    duree_maree        = "Duree maree (j)"
  )
  if (var %in% names(lbls)) lbls[[var]] else var
}

anonymiser_navires <- function(df, col = "nom_navire") {
  if (!col %in% names(df)) return(df)
  navires_uniq <- sort(unique(na.omit(df[[col]])))
  codes        <- paste0("NAV_", sprintf("%03d", seq_along(navires_uniq)))
  mapping      <- stats::setNames(codes, navires_uniq)
  df[[col]]    <- unname(mapping[as.character(df[[col]])])
  df
}

# -----------------------------------------------------------------------------
# 3. THÈME GGPLOT SOMBRE CRPMEM
# -----------------------------------------------------------------------------

theme_crpmem <- function(base_size = 12, legend_pos = "right") {
  bg_paper <- "#061A2B"
  bg_plot  <- "#0B2A3D"
  col_text <- "#C9D6DF"
  col_grid <- "#1A3A52"
  col_axis <- "#7FB3D3"
  
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = bg_paper, color = NA),
      panel.background = ggplot2::element_rect(fill = bg_plot,  color = NA),
      panel.grid.major = ggplot2::element_line(color = col_grid, linewidth = 0.4),
      panel.grid.minor = ggplot2::element_line(color = col_grid, linewidth = 0.2),
      axis.text        = ggplot2::element_text(color = col_axis,  size = base_size * 0.85),
      axis.title       = ggplot2::element_text(color = col_text,  size = base_size, face = "bold"),
      axis.ticks       = ggplot2::element_line(color = col_grid),
      axis.line        = ggplot2::element_line(color = col_grid),
      plot.title       = ggplot2::element_text(color = "#EAF2F8", size = base_size * 1.3,
                                               face = "bold", hjust = 0,
                                               margin = ggplot2::margin(b = 8)),
      plot.subtitle    = ggplot2::element_text(color = col_text,  size = base_size * 0.95,
                                               hjust = 0, margin = ggplot2::margin(b = 12)),
      plot.caption     = ggplot2::element_text(color = col_axis,  size = base_size * 0.75, hjust = 1),
      legend.position  = legend_pos,
      legend.background= ggplot2::element_rect(fill = bg_paper, color = col_grid),
      legend.text      = ggplot2::element_text(color = col_text,  size = base_size * 0.85),
      legend.title     = ggplot2::element_text(color = col_text,  size = base_size * 0.9, face = "bold"),
      legend.key       = ggplot2::element_rect(fill = bg_plot, color = NA),
      strip.background = ggplot2::element_rect(fill = "#123A52", color = col_grid),
      strip.text       = ggplot2::element_text(color = "#EAF2F8", size = base_size * 0.9, face = "bold"),
      plot.margin      = ggplot2::margin(t = 16, r = 20, b = 16, l = 12)
    )
}

# -----------------------------------------------------------------------------
# 4. PRÉ-TRAITEMENT
# -----------------------------------------------------------------------------

preparer_donnees_viz <- function(df, x_var, y_var = NULL,
                                 color_var = NULL, facet_var = NULL,
                                 agg_fun = "somme",
                                 incert_var = NULL, calc_sd = FALSE,
                                 anonymiser = FALSE, top_n = 0,
                                 sort_x = "aucun") {
  
  if (is.null(df) || nrow(df) == 0) return(list(df = df, sd_col = NULL, y_var_eff = y_var))
  
  if (anonymiser) df <- anonymiser_navires(df)
  
  grp_vars <- unique(c(x_var,
                       if (!is.null(color_var) && nzchar(color_var)) color_var,
                       if (!is.null(facet_var) && nzchar(facet_var)) facet_var))
  grp_vars <- intersect(grp_vars, names(df))
  
  sd_col <- NULL
  
  if (agg_fun == "n") {
    df <- df |>
      dplyr::group_by(dplyr::across(dplyr::all_of(grp_vars))) |>
      dplyr::summarise(n = dplyr::n(), .groups = "drop")
    y_var <- "n"
    
  } else if (agg_fun == "cumul" && !is.null(y_var) && nzchar(y_var) && y_var %in% names(df)) {
    # ── Cumul : somme agrégée par groupe puis cumsum ordonné sur X ──────────
    df[[y_var]] <- suppressWarnings(as.numeric(df[[y_var]]))
    
    # 1. Agrégation par somme sur tous les groupes (x + couleur + facette)
    df <- df |>
      dplyr::group_by(dplyr::across(dplyr::all_of(grp_vars))) |>
      dplyr::summarise(!!y_var := sum(.data[[y_var]], na.rm = TRUE), .groups = "drop")
    
    # 2. Cumsum par groupe couleur/facette (séries indépendantes)
    grp_cumul <- unique(c(
      if (!is.null(color_var) && nzchar(color_var %||% "")) color_var,
      if (!is.null(facet_var) && nzchar(facet_var %||% "")) facet_var
    ))
    grp_cumul <- intersect(grp_cumul, names(df))
    
    if (length(grp_cumul) > 0) {
      df <- df |>
        dplyr::arrange(dplyr::across(dplyr::all_of(c(grp_cumul, x_var)))) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(grp_cumul))) |>
        dplyr::mutate(!!y_var := cumsum(.data[[y_var]])) |>
        dplyr::ungroup()
    } else {
      df <- df |>
        dplyr::arrange(dplyr::across(dplyr::all_of(x_var))) |>
        dplyr::mutate(!!y_var := cumsum(.data[[y_var]]))
    }
    
    if (top_n > 0 && x_var %in% names(df)) {
      top_vals <- df |>
        dplyr::group_by(.data[[x_var]]) |>
        dplyr::summarise(tot = max(.data[[y_var]], na.rm = TRUE), .groups = "drop") |>
        dplyr::arrange(dplyr::desc(.data$tot)) |>
        dplyr::slice_head(n = top_n) |>
        dplyr::pull(.data[[x_var]])
      df <- df[df[[x_var]] %in% top_vals, , drop = FALSE]
    }
    
  } else if (!is.null(y_var) && nzchar(y_var) && y_var %in% names(df) && agg_fun != "aucune") {
    
    df[[y_var]] <- suppressWarnings(as.numeric(df[[y_var]]))
    
    agg_fn <- switch(agg_fun,
                     "somme"   = function(x) sum(x,           na.rm = TRUE),
                     "moyenne" = function(x) mean(x,          na.rm = TRUE),
                     "mediane" = function(x) stats::median(x, na.rm = TRUE),
                     function(x) sum(x, na.rm = TRUE)
    )
    
    if (calc_sd && agg_fun %in% c("somme", "moyenne")) {
      sd_col <- paste0(y_var, "_sd")
      df <- df |>
        dplyr::group_by(dplyr::across(dplyr::all_of(grp_vars))) |>
        dplyr::summarise(
          !!sd_col := stats::sd(.data[[y_var]], na.rm = TRUE),
          !!y_var  := agg_fn(.data[[y_var]]),
          .groups = "drop"
        )
    } else {
      df <- df |>
        dplyr::group_by(dplyr::across(dplyr::all_of(grp_vars))) |>
        dplyr::summarise(
          !!y_var := agg_fn(.data[[y_var]]),
          .groups = "drop"
        )
    }
    
    if (!is.null(incert_var) && nzchar(incert_var) && incert_var %in% names(df))
      sd_col <- incert_var
    
    if (top_n > 0 && x_var %in% names(df)) {
      top_vals <- df |>
        dplyr::group_by(.data[[x_var]]) |>
        dplyr::summarise(tot = sum(.data[[y_var]], na.rm = TRUE), .groups = "drop") |>
        dplyr::arrange(dplyr::desc(.data$tot)) |>
        dplyr::slice_head(n = top_n) |>
        dplyr::pull(.data[[x_var]])
      df <- df[df[[x_var]] %in% top_vals, , drop = FALSE]
    }
  }
  
  # ── Tri axe X ─────────────────────────────────────────────────────────────
  if (!is.null(sort_x) && sort_x != "aucun" && x_var %in% names(df)) {
    y_sort <- if (!is.null(y_var) && nzchar(y_var %||% "") && y_var %in% names(df)) y_var else NULL
    if (!is.null(y_sort)) {
      totaux <- df |>
        dplyr::group_by(.data[[x_var]]) |>
        dplyr::summarise(.sort_val = sum(.data[[y_sort]], na.rm = TRUE), .groups = "drop")
      df <- dplyr::left_join(df, totaux, by = x_var)
      df <- if (sort_x == "croissant")
        dplyr::arrange(df, .data$.sort_val)
      else
        dplyr::arrange(df, dplyr::desc(.data$.sort_val))
      df$.sort_val <- NULL
    } else {
      df <- if (sort_x == "croissant")
        dplyr::arrange(df, .data[[x_var]])
      else
        dplyr::arrange(df, dplyr::desc(.data[[x_var]]))
    }
    # Convertir x en facteur ordonné pour que ggplot respecte l'ordre
    df[[x_var]] <- factor(df[[x_var]], levels = unique(df[[x_var]]))
  }
  
  list(df = df, sd_col = sd_col, y_var_eff = y_var)
}

# -----------------------------------------------------------------------------
# 5. MOTEUR GRAPHIQUE PRINCIPAL (ggplot2 → ggplotly)
# -----------------------------------------------------------------------------

construire_graphique_viz <- function(params) {
  
  df       <- params$df
  type_viz <- params$type_viz  %||% "barres"
  x_var    <- params$x_var
  y_var    <- params$y_var     %||% NULL
  color_var<- params$color_var %||% NULL
  facet_var<- params$facet_var %||% NULL
  agg_fun  <- params$agg_fun   %||% "somme"
  calc_sd  <- isTRUE(params$calc_sd)
  incert_var <- params$incert_var %||% NULL
  anonymiser <- isTRUE(params$anonymiser)
  top_n    <- as.integer(params$top_n %||% 0)
  
  titre    <- params$titre     %||% ""
  soustitre<- params$soustitre %||% ""
  titre_x  <- params$titre_x  %||% label_variable(x_var)
  titre_y  <- params$titre_y  %||% label_variable(y_var %||% "n")
  titre_leg<- params$titre_leg %||% ""
  caption  <- params$caption  %||% ""
  
  palette_nom  <- params$palette_nom  %||% "CRPMEM (défaut)"
  couleur_fixe <- params$couleur_fixe %||% "#0077B6"
  barmode      <- params$barmode      %||% "stack"
  orientation  <- params$orientation  %||% "vertical"
  show_values  <- isTRUE(params$show_values)
  legend_pos   <- params$legend_pos   %||% "right"
  lim_y_min    <- params$lim_y_min    %||% NA
  lim_y_max    <- params$lim_y_max    %||% NA
  lim_x_min    <- params$lim_x_min    %||% NA
  lim_x_max    <- params$lim_x_max    %||% NA
  scale_x      <- params$scale_x      %||% "lineaire"
  scale_y      <- params$scale_y      %||% "lineaire"
  # FIX 1 : angle_x et opacite lus depuis params (pas depuis input directement)
  # Le server isole ces valeurs dans params_viz() pour éviter le reset du renderUI
  angle_x      <- as.numeric(params$angle_x    %||% 0)
  taille_pt    <- as.numeric(params$taille_pt  %||% 3)
  opacite      <- as.numeric(params$opacite    %||% 0.85)
  epaisseur_l  <- as.numeric(params$epaisseur_l %||% 1.2)
  smooth       <- isTRUE(params$smooth)
  smooth_method<- params$smooth_method %||% "loess"
  ligne_ref    <- suppressWarnings(as.numeric(params$ligne_ref))
  largeur_export <- as.integer(params$largeur_export %||% 1400)
  hauteur_export <- as.integer(params$hauteur_export %||% 800)
  # Nombre de colonnes facettes et hauteur par panel
  facet_ncol   <- as.integer(params$facet_ncol %||% 2)
  facet_height <- as.integer(params$facet_height %||% 280)
  sort_x       <- params$sort_x %||% "aucun"
  
  # ── Vérifications ─────────────────────────────────────────────────────────
  if (is.null(df) || nrow(df) == 0 || is.null(x_var) || !nzchar(x_var))
    return(plotly_vide("Aucune donnee a afficher — chargez un fichier et configurez les axes."))
  if (!x_var %in% names(df))
    return(plotly_vide(paste0("Colonne X '", x_var, "' introuvable dans le fichier.")))
  
  # ── Pré-traitement ────────────────────────────────────────────────────────
  # Pour lignes+points : ligne = moyenne agrégée, points = données brutes
  # boites/violon : forcer brutes même si l utilisateur a laissé "somme"
  agg_fun_eff <- if (type_viz == "lignes+points") "moyenne"
  else if (type_viz %in% c("boites", "violon")) "aucune"
  else agg_fun
  
  prep <- preparer_donnees_viz(
    df         = df,
    x_var      = x_var,
    y_var      = y_var,
    color_var  = color_var,
    facet_var  = facet_var,
    agg_fun    = agg_fun_eff,
    incert_var = incert_var,
    calc_sd    = calc_sd,
    anonymiser = anonymiser,
    top_n      = top_n,
    sort_x     = sort_x
  )
  df_plot  <- prep$df
  sd_col   <- prep$sd_col
  y_eff    <- prep$y_var_eff %||% y_var
  
  # Données brutes pour les points du mode lignes+points
  df_raw <- if (type_viz == "lignes+points" && !is.null(y_var) && y_var %in% names(df)) {
    prep_raw <- preparer_donnees_viz(
      df         = df,
      x_var      = x_var,
      y_var      = y_var,
      color_var  = color_var,
      facet_var  = facet_var,
      agg_fun    = "aucune",
      incert_var = NULL,
      calc_sd    = FALSE,
      anonymiser = anonymiser,
      top_n      = 0
    )
    prep_raw$df
  } else NULL
  
  if (is.null(df_plot) || nrow(df_plot) == 0)
    return(plotly_vide("Aucune donnee apres filtrage / aggregation."))
  
  # ── Mappings esthétiques ──────────────────────────────────────────────────
  has_color <- !is.null(color_var) && nzchar(color_var) && color_var %in% names(df_plot)
  has_facet <- !is.null(facet_var) && nzchar(facet_var) && facet_var %in% names(df_plot)
  has_sd    <- !is.null(sd_col)    && nzchar(sd_col)    && sd_col    %in% names(df_plot)
  has_y     <- !is.null(y_eff)     && nzchar(y_eff %||% "") && y_eff %in% names(df_plot)
  
  # FIX 2 : palette adaptative — calculée APRÈS avoir df_plot et has_color
  pal_base <- PALETTES_DISPONIBLES[[palette_nom]] %||% palette_hal
  n_modalites <- if (has_color && color_var %in% names(df_plot))
    dplyr::n_distinct(df_plot[[color_var]], na.rm = TRUE) else 1L
  # Interpolation automatique si trop de modalités
  pal <- if (n_modalites > length(pal_base)) {
    colorRampPalette(pal_base)(n_modalites)
  } else {
    pal_base
  }
  # Détection variable couleur continue
  color_est_continue <- has_color && is.numeric(df_plot[[color_var]])
  
  # ── Aes de base ───────────────────────────────────────────────────────────
  # FIX 3 : histogramme — ne jamais mettre y dans l'aes de base
  if (type_viz == "histogramme") {
    aes_base <- if (has_color)
      ggplot2::aes(x = .data[[x_var]], fill = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[x_var]])
  } else if (orientation == "horizontal" && has_y) {
    aes_base <- if (has_color)
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]],
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]])
  } else {
    aes_base <- if (has_color)
      ggplot2::aes(x = .data[[x_var]],
                   y = if (has_y) .data[[y_eff]] else NULL,
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[x_var]],
                   y = if (has_y) .data[[y_eff]] else NULL)
  }
  
  p <- ggplot2::ggplot(df_plot, aes_base)
  
  # ── Couche géométrique principale ─────────────────────────────────────────
  p <- switch(type_viz,
              
              "barres" = {
                pos <- switch(barmode,
                              "group" = ggplot2::position_dodge(width = 0.8),
                              "fill"  = "fill",
                              "stack"
                )
                if (has_color)
                  p + ggplot2::geom_col(position = pos, alpha = opacite, width = 0.75)
                else
                  p + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite, width = 0.75)
              },
              
              "lignes" = {
                if (has_color)
                  p + ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]),
                                         linewidth = epaisseur_l, alpha = opacite)
                else
                  p + ggplot2::geom_line(ggplot2::aes(group = 1),
                                         color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
              },
              
              "lignes+points" = {
                # Ligne sur moyenne agrégée, points sur données brutes
                df_points <- if (!is.null(df_raw) && nrow(df_raw) > 0) df_raw else df_plot
                if (has_color) {
                  aes_raw <- ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]],
                                          color = .data[[color_var]])
                  p +
                    ggplot2::geom_point(data = df_points, mapping = aes_raw,
                                        size = taille_pt, alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]),
                                       linewidth = epaisseur_l, alpha = opacite)
                } else {
                  aes_raw <- ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]])
                  p +
                    ggplot2::geom_point(data = df_points, mapping = aes_raw,
                                        color = couleur_fixe, size = taille_pt,
                                        alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = 1),
                                       color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
                }
              },
              
              "points" = {
                if (has_color)
                  p + ggplot2::geom_point(size = taille_pt, alpha = opacite)
                else
                  p + ggplot2::geom_point(color = couleur_fixe, size = taille_pt, alpha = opacite)
              },
              
              "aire" = {
                if (has_color)
                  p + ggplot2::geom_area(ggplot2::aes(group = .data[[color_var]]),
                                         alpha = opacite * 0.8,
                                         position = if (barmode == "stack") "stack" else "identity")
                else
                  p + ggplot2::geom_area(ggplot2::aes(group = 1),
                                         fill = couleur_fixe, color = couleur_fixe,
                                         alpha = opacite * 0.6, linewidth = epaisseur_l)
              },
              
              "boites" = {
                if (has_color)
                  p + ggplot2::geom_boxplot(alpha = opacite, outlier.size = taille_pt * 0.6,
                                            position = ggplot2::position_dodge(width = 0.8))
                else
                  p + ggplot2::geom_boxplot(fill = couleur_fixe, alpha = opacite,
                                            outlier.size = taille_pt * 0.6)
              },
              
              "violon" = {
                if (has_color)
                  p + ggplot2::geom_violin(alpha = opacite,
                                           position = ggplot2::position_dodge(width = 0.8)) +
                  ggplot2::geom_boxplot(width = 0.08, alpha = 0.6,
                                        position = ggplot2::position_dodge(width = 0.8))
                else
                  p + ggplot2::geom_violin(fill = couleur_fixe, alpha = opacite) +
                  ggplot2::geom_boxplot(width = 0.08, fill = "white", alpha = 0.4)
              },
              
              # FIX 3 : histogramme — aes_base sans y, donc geom_histogram marche
              "histogramme" = {
                bins <- as.integer(params$hist_bins %||% 30)
                if (has_color)
                  p + ggplot2::geom_histogram(bins = bins, alpha = opacite,
                                              position = if (barmode == "group") "dodge" else "stack")
                else
                  p + ggplot2::geom_histogram(bins = bins, fill = couleur_fixe,
                                              color = "#061A2B", alpha = opacite)
              },
              
              "camembert" = {
                if (!has_y) return(plotly_vide("Variable Y requise pour un camembert."))
                df_pie <- df_plot |>
                  dplyr::group_by(label = .data[[x_var]]) |>
                  dplyr::summarise(val = sum(.data[[y_eff]], na.rm = TRUE), .groups = "drop") |>
                  dplyr::arrange(dplyr::desc(.data$val))
                n_pie <- nrow(df_pie)
                pal_pie <- if (n_pie > length(pal_base)) colorRampPalette(pal_base)(n_pie) else pal_base
                return(
                  plotly::plot_ly(df_pie,
                                  labels = ~label, values = ~val, type = "pie", hole = 0.35,
                                  marker = list(colors = pal_pie),
                                  textinfo = "label+percent",
                                  hovertemplate = "<b>%{label}</b><br>%{value:,.1f} (%{percent})<extra></extra>",
                                  insidetextfont = list(color = "#FFFFFF", size = 11)
                  ) |>
                    plotly::layout(
                      title = list(text = titre, font = list(color = "#EAF2F8", size = 14)),
                      paper_bgcolor = "#061A2B",
                      legend = list(font = list(color = "#EAF2F8")),
                      font = list(family = "Inter", color = "#C9D6DF")
                    ) |>
                    plotly::config(displaylogo = FALSE,
                                   toImageButtonOptions = list(format = "png",
                                                               filename = paste0("graphique_", format(Sys.Date(), "%Y%m%d")),
                                                               width = largeur_export, height = hauteur_export, scale = 2))
                )
              },
              
              "donut" = {
                if (!has_y) return(plotly_vide("Variable Y requise pour un donut."))
                df_don <- df_plot |>
                  dplyr::group_by(label = .data[[x_var]]) |>
                  dplyr::summarise(val = sum(.data[[y_eff]], na.rm = TRUE), .groups = "drop") |>
                  dplyr::arrange(dplyr::desc(.data$val))
                n_don <- nrow(df_don)
                pal_don <- if (n_don > length(pal_base)) colorRampPalette(pal_base)(n_don) else pal_base
                return(
                  plotly::plot_ly(df_don,
                                  labels = ~label, values = ~val, type = "pie", hole = 0.55,
                                  marker = list(colors = pal_don),
                                  textinfo = "label+percent",
                                  hovertemplate = "<b>%{label}</b><br>%{value:,.1f} (%{percent})<extra></extra>"
                  ) |>
                    plotly::layout(
                      title = list(text = titre, font = list(color = "#EAF2F8", size = 14)),
                      paper_bgcolor = "#061A2B",
                      legend = list(font = list(color = "#EAF2F8")),
                      font = list(family = "Inter", color = "#C9D6DF")
                    ) |>
                    plotly::config(displaylogo = FALSE,
                                   toImageButtonOptions = list(format = "png",
                                                               filename = paste0("graphique_", format(Sys.Date(), "%Y%m%d")),
                                                               width = largeur_export, height = hauteur_export, scale = 2))
                )
              },
              
              "lollipop" = {
                if (has_color)
                  p +
                  ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]],
                                                     y = 0, yend = .data[[y_eff]]),
                                        color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(size = taille_pt + 1, alpha = opacite)
                else
                  p +
                  ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]],
                                                     y = 0, yend = .data[[y_eff]]),
                                        color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(color = couleur_fixe, size = taille_pt + 1, alpha = opacite)
              },
              
              # Fallback
              p + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite)
  )
  
  # ── Barres d'erreur ────────────────────────────────────────────────────────
  if (has_sd && type_viz %in% c("barres","lignes","lignes+points","points","lollipop")) {
    if (orientation == "horizontal") {
      p <- p + ggplot2::geom_errorbarh(
        ggplot2::aes(xmin = .data[[y_eff]] - .data[[sd_col]],
                     xmax = .data[[y_eff]] + .data[[sd_col]]),
        height = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity"
      )
    } else {
      p <- p + ggplot2::geom_errorbar(
        ggplot2::aes(ymin = .data[[y_eff]] - .data[[sd_col]],
                     ymax = .data[[y_eff]] + .data[[sd_col]]),
        width = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity"
      )
    }
  }
  
  # ── Lissage + équation régression ─────────────────────────────────────────
  show_equation <- isTRUE(params$show_equation)
  if (smooth && type_viz %in% c("points","lignes","lignes+points")) {
    p <- p + ggplot2::geom_smooth(method = smooth_method, se = TRUE,
                                  color = "#E07B39", fill = "#E07B39",
                                  alpha = 0.15, linewidth = 1)
    # Équation uniquement pour régression linéaire (lm) avec X et Y numériques
    if (smooth_method == "lm" && show_equation && has_y &&
        is.numeric(df_plot[[x_var]]) && is.numeric(df_plot[[y_eff]])) {
      tryCatch({
        fit <- stats::lm(stats::as.formula(paste(y_eff, "~", x_var)), data = df_plot)
        cf  <- stats::coef(fit)
        r2  <- summary(fit)$r.squared
        eq_label <- sprintf(
          "y = %s x %s %s   (R\u00b2 = %.3f)",
          formatC(cf[2], format = "g", digits = 4),
          if (cf[1] >= 0) "+" else "-",
          formatC(abs(cf[1]), format = "g", digits = 4),
          r2
        )
        x_pos <- min(df_plot[[x_var]], na.rm = TRUE)
        y_pos <- max(df_plot[[y_eff]],  na.rm = TRUE)
        p <- p + ggplot2::annotate(
          "text",
          x = x_pos, y = y_pos,
          label    = eq_label,
          hjust    = 0, vjust = 1.3,
          size     = 3.2,
          color    = "#E07B39",
          fontface = "italic"
        )
      }, error = function(e) NULL)
    }
  }
  
  # ── Valeurs sur les barres ─────────────────────────────────────────────────
  # Note : geom_text est évité ici car ggplotly le rend mal (doublons, mauvaise position)
  # Les labels sont ajoutés via plotly::add_text après ggplotly() (voir plus bas)
  
  # FIX 4 : Ligne de référence — geom_vline si horizontal, geom_hline sinon
  if (!is.null(ligne_ref) && !is.na(ligne_ref)) {
    if (orientation == "horizontal") {
      p <- p + ggplot2::geom_vline(xintercept = ligne_ref,
                                   linetype = "dashed", color = "#E07B39",
                                   linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", y = Inf, x = ligne_ref,
                          label = paste0("Seuil : ", ligne_ref),
                          hjust = -0.1, vjust = 1.4,
                          color = "#E07B39", size = 3)
    } else {
      p <- p + ggplot2::geom_hline(yintercept = ligne_ref,
                                   linetype = "dashed", color = "#E07B39",
                                   linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", x = Inf, y = ligne_ref,
                          label = paste0("Seuil : ", ligne_ref),
                          hjust = 1.05, vjust = -0.4,
                          color = "#E07B39", size = 3)
    }
  }
  
  # FIX 5 : Facettes avec hauteur adaptative pour le scroll
  # On calcule ncol et nrow réels pour ajuster la hauteur totale dans le server
  n_facets <- if (has_facet) dplyr::n_distinct(df_plot[[facet_var]], na.rm = TRUE) else 1L
  if (has_facet) {
    p <- p + ggplot2::facet_wrap(ggplot2::vars(.data[[facet_var]]),
                                 scales = "free_y", ncol = facet_ncol)
  }
  
  # ── Palettes couleurs ──────────────────────────────────────────────────────
  if (has_color) {
    if (color_est_continue) {
      # Variable numérique continue → gradient
      p <- p +
        ggplot2::scale_fill_gradientn(colors = pal_base, name = titre_leg) +
        ggplot2::scale_color_gradientn(colors = pal_base, name = titre_leg)
    } else {
      # Variable catégorielle → couleurs discrètes (palette interpolée si besoin)
      p <- p +
        ggplot2::scale_fill_manual(values  = pal, name = titre_leg) +
        ggplot2::scale_color_manual(values = pal, name = titre_leg)
    }
  }
  
  # ── Échelles X / Y ─────────────────────────────────────────────────────────
  y_lims <- c(
    if (!is.na(lim_y_min)) as.numeric(lim_y_min) else NA,
    if (!is.na(lim_y_max)) as.numeric(lim_y_max) else NA
  )
  y_trans <- switch(scale_y, "log" = "log10", "inverse" = "reverse", "identity")
  if (has_y && orientation != "horizontal" && !type_viz %in% c("histogramme")) {
    p <- p + ggplot2::scale_y_continuous(
      trans  = y_trans,
      limits = if (all(is.na(y_lims))) NULL else y_lims,
      labels = scales::number_format(big.mark = " ", accuracy = 0.1)
    )
  }
  
  if (has_y && is.numeric(df_plot[[x_var]])) {
    x_lims <- c(
      if (!is.na(lim_x_min)) as.numeric(lim_x_min) else NA,
      if (!is.na(lim_x_max)) as.numeric(lim_x_max) else NA
    )
    x_trans <- switch(scale_x, "log" = "log10", "inverse" = "reverse", "identity")
    p <- p + ggplot2::scale_x_continuous(
      trans  = x_trans,
      limits = if (all(is.na(x_lims))) NULL else x_lims
    )
  }
  
  # ── Titres & labels ────────────────────────────────────────────────────────
  p <- p + ggplot2::labs(
    title    = titre,
    subtitle = soustitre,
    caption  = caption,
    x        = if (orientation == "horizontal") titre_y else titre_x,
    y        = if (orientation == "horizontal") titre_x else titre_y
  )
  
  # ── Thème & rotation X ─────────────────────────────────────────────────────
  leg_ggplot <- switch(legend_pos,
                       "right"  = "right",
                       "bottom" = "bottom",
                       "top"    = "top",
                       "none"   = "none",
                       "right"
  )
  p <- p + theme_crpmem(legend_pos = leg_ggplot)
  if (angle_x != 0) {
    p <- p + ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = angle_x, hjust = 1, vjust = 1)
    )
  }
  
  # ── Conversion plotly ──────────────────────────────────────────────────────
  # Hauteur d'AFFICHAGE : basée sur facettes ou hauteur_display (indépendante de l'export)
  hauteur_display <- if (has_facet) {
    nrow_facets <- ceiling(n_facets / facet_ncol)
    max(500L, nrow_facets * facet_height)
  } else {
    as.integer(params$hauteur_display %||% 600L)
  }
  
  tryCatch({
    pp <- plotly::ggplotly(p, tooltip = "all", height = hauteur_display) |>
      plotly::layout(
        paper_bgcolor = "#061A2B",
        plot_bgcolor  = "#0B2A3D",
        # Sous-titre et caption injectés via annotations plotly (ggplotly les perd)
        annotations = Filter(Negate(is.null), list(
          if (nzchar(soustitre)) list(
            text      = soustitre,
            x         = 0, xref = "paper", xanchor = "left",
            y         = 1, yref = "paper", yanchor = "bottom",
            yshift    = -28,
            showarrow = FALSE,
            font      = list(color = "#C9D6DF", size = 12),
            align     = "left"
          ) else NULL,
          if (nzchar(caption)) list(
            text      = paste0("<i>", caption, "</i>"),
            x         = 1, xref = "paper", xanchor = "right",
            y         = 0, yref = "paper", yanchor = "top",
            yshift    = -30,
            showarrow = FALSE,
            font      = list(color = "#7FB3D3", size = 10),
            align     = "right"
          ) else NULL
        )),
        legend = list(
          bgcolor     = "#061A2B",
          bordercolor = "#123A52",
          font        = list(color = "#EAF2F8", size = 11)
        ),
        font   = list(family = "Inter, sans-serif", color = "#C9D6DF")
      ) |>
      plotly::config(
        displaylogo = FALSE,
        toImageButtonOptions = list(
          format   = "png",
          filename = paste0("graphique_", format(Sys.Date(), "%Y%m%d_%H%M%S")),
          width    = largeur_export,
          height   = hauteur_export,
          scale    = 2
        ),
        modeBarButtonsToRemove = list("sendDataToCloud","lasso2d","select2d")
      )
    
    # ── Valeurs sur les barres via plotly (évite les artefacts geom_text + ggplotly) ──
    if (show_values && has_y && type_viz %in% c("barres", "lollipop") &&
        !has_facet && nrow(df_plot) > 0) {
      tryCatch({
        lbl <- scales::number(df_plot[[y_eff]], accuracy = 0.1, big.mark = "\u202f")
        if (orientation == "horizontal") {
          pp <- pp |> plotly::add_text(
            data = df_plot,
            x = ~.data[[y_eff]], y = ~.data[[x_var]],
            text = lbl, textposition = "middle right",
            textfont = list(color = "#EAF2F8", size = 10),
            inherit = FALSE, showlegend = FALSE
          )
        } else {
          pp <- pp |> plotly::add_text(
            data = df_plot,
            x = ~.data[[x_var]], y = ~.data[[y_eff]],
            text = lbl, textposition = "top center",
            textfont = list(color = "#EAF2F8", size = 10),
            inherit = FALSE, showlegend = FALSE
          )
        }
      }, error = function(e) NULL)
    }
    
    pp
  }, error = function(e) {
    plotly_vide(paste("Erreur rendu graphique :", e$message))
  })
}

# -----------------------------------------------------------------------------
# 6. MOTEUR GGPLOT STATIQUE (pour composition patchwork)
# Même logique que construire_graphique_viz() mais retourne un objet ggplot
# au lieu de le convertir en plotly. Utilisé par server_composition via push.
# Les types camembert/donut ne sont pas supportés (plotly uniquement).
# -----------------------------------------------------------------------------

construire_ggplot_viz <- function(params) {
  
  df       <- params$df
  type_viz <- params$type_viz   %||% "barres"
  x_var    <- params$x_var
  y_var    <- params$y_var      %||% NULL
  color_var<- params$color_var  %||% NULL
  facet_var<- params$facet_var  %||% NULL
  agg_fun  <- params$agg_fun    %||% "somme"
  calc_sd  <- isTRUE(params$calc_sd)
  incert_var <- params$incert_var %||% NULL
  anonymiser <- isTRUE(params$anonymiser)
  top_n    <- as.integer(params$top_n %||% 0)
  sort_x   <- params$sort_x %||% "aucun"
  
  titre       <- params$titre      %||% ""
  soustitre   <- params$soustitre  %||% ""
  titre_x     <- params$titre_x   %||% label_variable(x_var)
  titre_y     <- params$titre_y   %||% label_variable(y_var %||% "n")
  titre_leg   <- params$titre_leg  %||% ""
  caption     <- params$caption    %||% ""
  
  palette_nom  <- params$palette_nom  %||% "CRPMEM (défaut)"
  couleur_fixe <- params$couleur_fixe %||% "#0077B6"
  barmode      <- params$barmode      %||% "stack"
  orientation  <- params$orientation  %||% "vertical"
  show_values  <- isTRUE(params$show_values)
  legend_pos   <- params$legend_pos   %||% "right"
  angle_x      <- as.numeric(params$angle_x     %||% 0)
  opacite      <- as.numeric(params$opacite      %||% 0.85)
  taille_pt    <- as.numeric(params$taille_pt    %||% 3)
  epaisseur_l  <- as.numeric(params$epaisseur_l  %||% 1.2)
  smooth       <- isTRUE(params$smooth)
  smooth_method<- params$smooth_method %||% "loess"
  ligne_ref    <- suppressWarnings(as.numeric(params$ligne_ref))
  scale_x      <- params$scale_x %||% "lineaire"
  scale_y      <- params$scale_y %||% "lineaire"
  lim_y_min    <- params$lim_y_min %||% NA
  lim_y_max    <- params$lim_y_max %||% NA
  lim_x_min    <- params$lim_x_min %||% NA
  lim_x_max    <- params$lim_x_max %||% NA
  facet_ncol   <- as.integer(params$facet_ncol  %||% 2)
  
  # Types non supportés en ggplot statique
  if (type_viz %in% c("camembert", "donut")) return(NULL)
  if (is.null(df) || nrow(df) == 0 || is.null(x_var) || !nzchar(x_var)) return(NULL)
  if (!x_var %in% names(df)) return(NULL)
  
  agg_fun_eff <- if (type_viz == "lignes+points") "moyenne"
  else if (type_viz %in% c("boites", "violon")) "aucune"
  else agg_fun
  
  prep <- preparer_donnees_viz(
    df = df, x_var = x_var, y_var = y_var,
    color_var = color_var, facet_var = facet_var,
    agg_fun = agg_fun_eff, incert_var = incert_var,
    calc_sd = calc_sd, anonymiser = anonymiser,
    top_n = top_n, sort_x = sort_x
  )
  df_plot <- prep$df
  sd_col  <- prep$sd_col
  y_eff   <- prep$y_var_eff %||% y_var
  
  df_raw <- if (type_viz == "lignes+points" && !is.null(y_var) && y_var %in% names(df)) {
    preparer_donnees_viz(df = df, x_var = x_var, y_var = y_var,
                         color_var = color_var, agg_fun = "aucune",
                         anonymiser = anonymiser, sort_x = sort_x)$df
  } else NULL
  
  if (is.null(df_plot) || nrow(df_plot) == 0) return(NULL)
  
  has_color <- !is.null(color_var) && nzchar(color_var) && color_var %in% names(df_plot)
  has_facet <- !is.null(facet_var) && nzchar(facet_var) && facet_var %in% names(df_plot)
  has_sd    <- !is.null(sd_col)    && nzchar(sd_col %||% "") && sd_col %in% names(df_plot)
  has_y     <- !is.null(y_eff)     && nzchar(y_eff %||% "") && y_eff %in% names(df_plot)
  
  pal_base <- PALETTES_DISPONIBLES[[palette_nom]] %||% palette_hal
  n_mod    <- if (has_color) dplyr::n_distinct(df_plot[[color_var]], na.rm = TRUE) else 1L
  pal      <- if (n_mod > length(pal_base)) colorRampPalette(pal_base)(n_mod) else pal_base
  color_est_continue <- has_color && is.numeric(df_plot[[color_var]])
  
  # Aes de base
  if (type_viz == "histogramme") {
    aes_b <- if (has_color) ggplot2::aes(x = .data[[x_var]], fill = .data[[color_var]])
    else ggplot2::aes(x = .data[[x_var]])
  } else if (orientation == "horizontal" && has_y) {
    aes_b <- if (has_color)
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]],
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]])
  } else {
    aes_b <- if (has_color)
      ggplot2::aes(x = .data[[x_var]],
                   y = if (has_y) .data[[y_eff]] else NULL,
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[x_var]], y = if (has_y) .data[[y_eff]] else NULL)
  }
  
  g <- ggplot2::ggplot(df_plot, aes_b)
  
  g <- switch(type_viz,
              "barres" = {
                pos <- switch(barmode, "group" = ggplot2::position_dodge(width = 0.8), "fill" = "fill", "stack")
                if (has_color) g + ggplot2::geom_col(position = pos, alpha = opacite, width = 0.75)
                else           g + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite, width = 0.75)
              },
              "lignes" = {
                if (has_color) g + ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]), linewidth = epaisseur_l, alpha = opacite)
                else           g + ggplot2::geom_line(ggplot2::aes(group = 1), color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
              },
              "lignes+points" = {
                df_pts <- if (!is.null(df_raw) && nrow(df_raw) > 0) df_raw else df_plot
                if (has_color) {
                  g + ggplot2::geom_point(data = df_pts,
                                          mapping = ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]], color = .data[[color_var]]),
                                          size = taille_pt, alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]), linewidth = epaisseur_l, alpha = opacite)
                } else {
                  g + ggplot2::geom_point(data = df_pts,
                                          mapping = ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]]),
                                          color = couleur_fixe, size = taille_pt, alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = 1), color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
                }
              },
              "points" = {
                if (has_color) g + ggplot2::geom_point(size = taille_pt, alpha = opacite)
                else           g + ggplot2::geom_point(color = couleur_fixe, size = taille_pt, alpha = opacite)
              },
              "aire" = {
                pos_aire <- if (barmode == "stack") "stack" else "identity"
                if (has_color) g + ggplot2::geom_area(ggplot2::aes(group = .data[[color_var]]), alpha = opacite * 0.8, position = pos_aire)
                else           g + ggplot2::geom_area(ggplot2::aes(group = 1), fill = couleur_fixe, color = couleur_fixe, alpha = opacite * 0.6, linewidth = epaisseur_l)
              },
              "boites" = {
                if (has_color) g + ggplot2::geom_boxplot(alpha = opacite, outlier.size = taille_pt * 0.6, position = ggplot2::position_dodge(width = 0.8))
                else           g + ggplot2::geom_boxplot(fill = couleur_fixe, alpha = opacite, outlier.size = taille_pt * 0.6)
              },
              "violon" = {
                if (has_color) g + ggplot2::geom_violin(alpha = opacite, position = ggplot2::position_dodge(width = 0.8)) +
                  ggplot2::geom_boxplot(width = 0.08, alpha = 0.6, position = ggplot2::position_dodge(width = 0.8))
                else           g + ggplot2::geom_violin(fill = couleur_fixe, alpha = opacite) +
                  ggplot2::geom_boxplot(width = 0.08, fill = "white", alpha = 0.4)
              },
              "histogramme" = {
                bins <- as.integer(params$hist_bins %||% 30)
                if (has_color) g + ggplot2::geom_histogram(bins = bins, alpha = opacite, position = if (barmode == "group") "dodge" else "stack")
                else           g + ggplot2::geom_histogram(bins = bins, fill = couleur_fixe, color = "#061A2B", alpha = opacite)
              },
              "lollipop" = {
                if (has_color)
                  g + ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]], y = 0, yend = .data[[y_eff]]),
                                            color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(size = taille_pt + 1, alpha = opacite)
                else
                  g + ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]], y = 0, yend = .data[[y_eff]]),
                                            color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(color = couleur_fixe, size = taille_pt + 1, alpha = opacite)
              },
              g + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite)
  )
  
  # Barres d'erreur
  if (has_sd && type_viz %in% c("barres","lignes","lignes+points","points","lollipop")) {
    if (orientation == "horizontal") {
      g <- g + ggplot2::geom_errorbarh(
        ggplot2::aes(xmin = .data[[y_eff]] - .data[[sd_col]], xmax = .data[[y_eff]] + .data[[sd_col]]),
        height = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity")
    } else {
      g <- g + ggplot2::geom_errorbar(
        ggplot2::aes(ymin = .data[[y_eff]] - .data[[sd_col]], ymax = .data[[y_eff]] + .data[[sd_col]]),
        width = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity")
    }
  }
  
  # Lissage
  if (smooth && type_viz %in% c("points","lignes","lignes+points")) {
    g <- g + ggplot2::geom_smooth(method = smooth_method, se = TRUE,
                                  color = "#E07B39", fill = "#E07B39", alpha = 0.15, linewidth = 1)
  }
  
  # Ligne de référence
  if (!is.null(ligne_ref) && !is.na(ligne_ref)) {
    if (orientation == "horizontal") {
      g <- g + ggplot2::geom_vline(xintercept = ligne_ref, linetype = "dashed", color = "#E07B39", linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", y = Inf, x = ligne_ref, label = paste0("Seuil : ", ligne_ref),
                          hjust = -0.1, vjust = 1.4, color = "#E07B39", size = 3)
    } else {
      g <- g + ggplot2::geom_hline(yintercept = ligne_ref, linetype = "dashed", color = "#E07B39", linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", x = Inf, y = ligne_ref, label = paste0("Seuil : ", ligne_ref),
                          hjust = 1.05, vjust = -0.4, color = "#E07B39", size = 3)
    }
  }
  
  # Facettes
  if (has_facet) {
    g <- g + ggplot2::facet_wrap(ggplot2::vars(.data[[facet_var]]), scales = "free_y", ncol = facet_ncol)
  }
  
  # Palettes
  if (has_color) {
    if (color_est_continue) {
      g <- g + ggplot2::scale_fill_gradientn(colors = pal_base, name = titre_leg) +
        ggplot2::scale_color_gradientn(colors = pal_base, name = titre_leg)
    } else {
      g <- g + ggplot2::scale_fill_manual(values = pal, name = titre_leg) +
        ggplot2::scale_color_manual(values = pal, name = titre_leg)
    }
  }
  
  # Échelles
  y_lims  <- c(if (!is.na(lim_y_min %||% NA)) as.numeric(lim_y_min) else NA,
               if (!is.na(lim_y_max %||% NA)) as.numeric(lim_y_max) else NA)
  y_trans <- switch(scale_y, "log" = "log10", "inverse" = "reverse", "identity")
  if (has_y && orientation != "horizontal" && !type_viz %in% c("histogramme")) {
    g <- g + ggplot2::scale_y_continuous(trans = y_trans,
                                         limits = if (all(is.na(y_lims))) NULL else y_lims,
                                         labels = scales::number_format(big.mark = "\u202f", accuracy = 0.1))
  }
  if (has_y && is.numeric(df_plot[[x_var]])) {
    x_lims  <- c(if (!is.na(lim_x_min %||% NA)) as.numeric(lim_x_min) else NA,
                 if (!is.na(lim_x_max %||% NA)) as.numeric(lim_x_max) else NA)
    x_trans <- switch(scale_x, "log" = "log10", "inverse" = "reverse", "identity")
    g <- g + ggplot2::scale_x_continuous(trans = x_trans,
                                         limits = if (all(is.na(x_lims))) NULL else x_lims)
  }
  
  # Titres
  g <- g + ggplot2::labs(
    title    = titre,
    subtitle = soustitre,
    caption  = caption,
    x        = if (orientation == "horizontal") titre_y else titre_x,
    y        = if (orientation == "horizontal") titre_x else titre_y
  )
  
  # Thème
  leg_ggplot <- switch(legend_pos, "right" = "right", "bottom" = "bottom",
                       "top" = "top", "none" = "none", "right")
  g <- g + theme_crpmem(legend_pos = leg_ggplot)
  if (angle_x != 0) {
    g <- g + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = angle_x, hjust = 1, vjust = 1))
  }
  
  g
}

# -----------------------------------------------------------------------------
# 7. GRAPHIQUE VIDE
# -----------------------------------------------------------------------------

plotly_vide <- function(msg = "Aucune donnee") {
  plotly::plotly_empty() |>
    plotly::layout(
      title = list(text = msg, font = list(color = "#7FB3D3", size = 13)),
      paper_bgcolor = "#061A2B",
      plot_bgcolor  = "#0B2A3D"
    )
}

# -----------------------------------------------------------------------------
# 7. EXPORT GGPLOT PNG HAUTE RÉSOLUTION
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 7. EXPORT GGPLOT PNG HAUTE RÉSOLUTION
# Réutilise le même moteur que l'affichage pour garantir la cohérence complète.
# -----------------------------------------------------------------------------

exporter_ggplot_png <- function(params, file,
                                width_px  = 1400,
                                height_px = 800,
                                dpi       = 150) {
  
  df       <- params$df
  type_viz <- params$type_viz %||% "barres"
  x_var    <- params$x_var
  y_var    <- params$y_var    %||% NULL
  color_var<- params$color_var %||% NULL
  facet_var<- params$facet_var %||% NULL
  agg_fun  <- params$agg_fun  %||% "somme"
  titre    <- params$titre    %||% ""
  soustitre<- params$soustitre %||% ""
  titre_x  <- params$titre_x  %||% label_variable(x_var)
  titre_y  <- params$titre_y  %||% label_variable(y_var %||% "n")
  titre_leg<- params$titre_leg %||% ""
  caption  <- params$caption  %||% ""
  palette_nom  <- params$palette_nom  %||% "CRPMEM (défaut)"
  couleur_fixe <- params$couleur_fixe %||% "#0077B6"
  pal_base <- PALETTES_DISPONIBLES[[palette_nom]] %||% palette_hal
  orientation  <- params$orientation  %||% "vertical"
  barmode      <- params$barmode      %||% "stack"
  opacite      <- as.numeric(params$opacite %||% 0.85)
  taille_pt    <- as.numeric(params$taille_pt %||% 3)
  epaisseur_l  <- as.numeric(params$epaisseur_l %||% 1.2)
  show_values  <- isTRUE(params$show_values)
  legend_pos   <- params$legend_pos   %||% "right"
  angle_x      <- as.numeric(params$angle_x %||% 0)
  smooth       <- isTRUE(params$smooth)
  smooth_method<- params$smooth_method %||% "loess"
  ligne_ref    <- suppressWarnings(as.numeric(params$ligne_ref))
  scale_x      <- params$scale_x %||% "lineaire"
  scale_y      <- params$scale_y %||% "lineaire"
  lim_y_min    <- params$lim_y_min
  lim_y_max    <- params$lim_y_max
  lim_x_min    <- params$lim_x_min
  lim_x_max    <- params$lim_x_max
  facet_ncol   <- as.integer(params$facet_ncol %||% 2)
  top_n        <- as.integer(params$top_n %||% 0)
  sort_x       <- params$sort_x %||% "aucun"
  calc_sd      <- isTRUE(params$calc_sd)
  incert_var   <- params$incert_var %||% NULL
  
  # Agrégation effective (même logique que construire_graphique_viz)
  agg_fun_eff <- if (type_viz == "lignes+points") "moyenne"
  else if (type_viz %in% c("boites", "violon")) "aucune"
  else agg_fun
  
  prep <- preparer_donnees_viz(
    df = df, x_var = x_var, y_var = y_var,
    color_var = color_var, facet_var = facet_var,
    agg_fun = agg_fun_eff, incert_var = incert_var,
    calc_sd = calc_sd, anonymiser = isTRUE(params$anonymiser),
    top_n = top_n, sort_x = sort_x
  )
  df_plot <- prep$df
  sd_col  <- prep$sd_col
  y_eff   <- prep$y_var_eff %||% y_var
  
  has_color <- !is.null(color_var) && nzchar(color_var) && color_var %in% names(df_plot)
  has_facet <- !is.null(facet_var) && nzchar(facet_var) && facet_var %in% names(df_plot)
  has_y     <- !is.null(y_eff) && nzchar(y_eff %||% "") && y_eff %in% names(df_plot)
  has_sd    <- !is.null(sd_col) && nzchar(sd_col %||% "") && sd_col %in% names(df_plot)
  n_modalites <- if (has_color) dplyr::n_distinct(df_plot[[color_var]], na.rm = TRUE) else 1L
  pal <- if (n_modalites > length(pal_base)) colorRampPalette(pal_base)(n_modalites) else pal_base
  color_est_continue <- has_color && is.numeric(df_plot[[color_var]])
  
  # Camembert / donut : export via webshot
  if (type_viz %in% c("camembert", "donut")) {
    df_pie <- df_plot |>
      dplyr::group_by(label = .data[[x_var]]) |>
      dplyr::summarise(val = sum(.data[[y_eff]], na.rm = TRUE), .groups = "drop") |>
      dplyr::arrange(dplyr::desc(.data$val))
    n_pie <- nrow(df_pie)
    pal_pie <- if (n_pie > length(pal_base)) colorRampPalette(pal_base)(n_pie) else pal_base
    hole_val <- if (type_viz == "donut") 0.55 else 0.35
    pp <- plotly::plot_ly(df_pie,
                          labels = ~label, values = ~val, type = "pie", hole = hole_val,
                          marker = list(colors = pal_pie), textinfo = "label+percent") |>
      plotly::layout(title = list(text = titre, font = list(color = "#EAF2F8")),
                     paper_bgcolor = "#061A2B", font = list(family = "Inter", color = "#C9D6DF"))
    tmp_html <- tempfile(fileext = ".html")
    htmlwidgets::saveWidget(pp, tmp_html, selfcontained = TRUE)
    if (requireNamespace("webshot2", quietly = TRUE)) {
      webshot2::webshot(tmp_html, file, vwidth = width_px, vheight = height_px)
    } else if (requireNamespace("webshot", quietly = TRUE)) {
      webshot::webshot(tmp_html, file, vwidth = width_px, vheight = height_px)
    } else {
      file.copy(tmp_html, file, overwrite = TRUE)
    }
    return(invisible(NULL))
  }
  
  # ── Aes de base (identique à construire_graphique_viz) ────────────────────
  if (type_viz == "histogramme") {
    aes_b <- if (has_color) ggplot2::aes(x = .data[[x_var]], fill = .data[[color_var]])
    else            ggplot2::aes(x = .data[[x_var]])
  } else if (orientation == "horizontal" && has_y) {
    aes_b <- if (has_color)
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]],
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[y_eff]], y = .data[[x_var]])
  } else {
    aes_b <- if (has_color)
      ggplot2::aes(x = .data[[x_var]],
                   y = if (has_y) .data[[y_eff]] else NULL,
                   fill = .data[[color_var]], color = .data[[color_var]])
    else
      ggplot2::aes(x = .data[[x_var]], y = if (has_y) .data[[y_eff]] else NULL)
  }
  
  g <- ggplot2::ggplot(df_plot, aes_b)
  
  # ── Géométrie principale ──────────────────────────────────────────────────
  df_raw_exp <- if (type_viz == "lignes+points" && !is.null(y_var) && y_var %in% names(df)) {
    preparer_donnees_viz(df = df, x_var = x_var, y_var = y_var,
                         color_var = color_var, agg_fun = "aucune",
                         anonymiser = isTRUE(params$anonymiser), sort_x = sort_x)$df
  } else NULL
  
  g <- switch(type_viz,
              "barres" = {
                pos <- switch(barmode, "group" = ggplot2::position_dodge(width = 0.8), "fill" = "fill", "stack")
                if (has_color) g + ggplot2::geom_col(position = pos, alpha = opacite, width = 0.75)
                else           g + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite, width = 0.75)
              },
              "lignes" = {
                if (has_color) g + ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]), linewidth = epaisseur_l, alpha = opacite)
                else           g + ggplot2::geom_line(ggplot2::aes(group = 1), color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
              },
              "lignes+points" = {
                df_pts <- if (!is.null(df_raw_exp) && nrow(df_raw_exp) > 0) df_raw_exp else df_plot
                if (has_color) {
                  g + ggplot2::geom_point(data = df_pts,
                                          mapping = ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]], color = .data[[color_var]]),
                                          size = taille_pt, alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = .data[[color_var]]), linewidth = epaisseur_l, alpha = opacite)
                } else {
                  g + ggplot2::geom_point(data = df_pts,
                                          mapping = ggplot2::aes(x = .data[[x_var]], y = .data[[y_eff]]),
                                          color = couleur_fixe, size = taille_pt, alpha = opacite * 0.55, shape = 19) +
                    ggplot2::geom_line(ggplot2::aes(group = 1), color = couleur_fixe, linewidth = epaisseur_l, alpha = opacite)
                }
              },
              "points" = {
                if (has_color) g + ggplot2::geom_point(size = taille_pt, alpha = opacite)
                else           g + ggplot2::geom_point(color = couleur_fixe, size = taille_pt, alpha = opacite)
              },
              "aire" = {
                pos_aire <- if (barmode == "stack") "stack" else "identity"
                if (has_color) g + ggplot2::geom_area(ggplot2::aes(group = .data[[color_var]]), alpha = opacite * 0.8, position = pos_aire)
                else           g + ggplot2::geom_area(ggplot2::aes(group = 1), fill = couleur_fixe, color = couleur_fixe, alpha = opacite * 0.6, linewidth = epaisseur_l)
              },
              "boites" = {
                if (has_color) g + ggplot2::geom_boxplot(alpha = opacite, outlier.size = taille_pt * 0.6, position = ggplot2::position_dodge(width = 0.8))
                else           g + ggplot2::geom_boxplot(fill = couleur_fixe, alpha = opacite, outlier.size = taille_pt * 0.6)
              },
              "violon" = {
                if (has_color) g + ggplot2::geom_violin(alpha = opacite, position = ggplot2::position_dodge(width = 0.8)) +
                  ggplot2::geom_boxplot(width = 0.08, alpha = 0.6, position = ggplot2::position_dodge(width = 0.8))
                else           g + ggplot2::geom_violin(fill = couleur_fixe, alpha = opacite) +
                  ggplot2::geom_boxplot(width = 0.08, fill = "white", alpha = 0.4)
              },
              "histogramme" = {
                bins <- as.integer(params$hist_bins %||% 30)
                if (has_color) g + ggplot2::geom_histogram(bins = bins, alpha = opacite, position = if (barmode == "group") "dodge" else "stack")
                else           g + ggplot2::geom_histogram(bins = bins, fill = couleur_fixe, color = "#061A2B", alpha = opacite)
              },
              "lollipop" = {
                if (has_color)
                  g + ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]], y = 0, yend = .data[[y_eff]]),
                                            color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(size = taille_pt + 1, alpha = opacite)
                else
                  g + ggplot2::geom_segment(ggplot2::aes(x = .data[[x_var]], xend = .data[[x_var]], y = 0, yend = .data[[y_eff]]),
                                            color = "#1A3A52", linewidth = 0.8) +
                  ggplot2::geom_point(color = couleur_fixe, size = taille_pt + 1, alpha = opacite)
              },
              g + ggplot2::geom_col(fill = couleur_fixe, alpha = opacite)
  )
  
  # ── Barres d'erreur ───────────────────────────────────────────────────────
  if (has_sd && type_viz %in% c("barres","lignes","lignes+points","points","lollipop")) {
    if (orientation == "horizontal") {
      g <- g + ggplot2::geom_errorbarh(
        ggplot2::aes(xmin = .data[[y_eff]] - .data[[sd_col]], xmax = .data[[y_eff]] + .data[[sd_col]]),
        height = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity")
    } else {
      g <- g + ggplot2::geom_errorbar(
        ggplot2::aes(ymin = .data[[y_eff]] - .data[[sd_col]], ymax = .data[[y_eff]] + .data[[sd_col]]),
        width = 0.25, color = "#EAF2F8", alpha = 0.7,
        position = if (barmode == "group") ggplot2::position_dodge(width = 0.8) else "identity")
    }
  }
  
  # ── Lissage ───────────────────────────────────────────────────────────────
  if (smooth && type_viz %in% c("points","lignes","lignes+points")) {
    g <- g + ggplot2::geom_smooth(method = smooth_method, se = TRUE,
                                  color = "#E07B39", fill = "#E07B39", alpha = 0.15, linewidth = 1)
  }
  
  # ── Valeurs sur les barres (ggplot natif pour PNG) ────────────────────────
  if (show_values && has_y && type_viz %in% c("barres","lollipop")) {
    is_stacked <- has_color && barmode == "stack"
    
    if (is_stacked) {
      # Mode stack : un seul label = total de la barre, positionné au sommet
      grp_stack <- if (has_facet) c(x_var, facet_var) else x_var
      df_totaux <- df_plot |>
        dplyr::group_by(dplyr::across(dplyr::all_of(grp_stack))) |>
        dplyr::summarise(.total_bar = sum(.data[[y_eff]], na.rm = TRUE), .groups = "drop")
      
      if (orientation == "horizontal") {
        g <- g + ggplot2::geom_text(
          data         = df_totaux,
          mapping      = ggplot2::aes(
            x     = .data$.total_bar,
            y     = .data[[x_var]],
            label = scales::number(.data$.total_bar, accuracy = 0.1, big.mark = "\u202f")
          ),
          inherit.aes = FALSE,
          hjust = -0.15, vjust = 0.5, size = 3, color = "#EAF2F8"
        )
      } else {
        g <- g + ggplot2::geom_text(
          data         = df_totaux,
          mapping      = ggplot2::aes(
            x     = .data[[x_var]],
            y     = .data$.total_bar,
            label = scales::number(.data$.total_bar, accuracy = 0.1, big.mark = "\u202f")
          ),
          inherit.aes = FALSE,
          vjust = -0.4, hjust = 0.5, size = 3, color = "#EAF2F8"
        )
      }
      
    } else {
      # Mode simple / grouped : label au-dessus / à droite de la barre
      lbl_aes <- if (orientation == "horizontal")
        ggplot2::aes(label = scales::number(.data[[y_eff]], accuracy = 0.1, big.mark = "\u202f"), x = .data[[y_eff]])
      else
        ggplot2::aes(label = scales::number(.data[[y_eff]], accuracy = 0.1, big.mark = "\u202f"), y = .data[[y_eff]])
      pos <- if (has_color && barmode == "group")
        ggplot2::position_dodge(width = 0.8) else "identity"
      g <- g + ggplot2::geom_text(lbl_aes,
                                  position = pos,
                                  vjust = if (orientation == "horizontal") 0.5 else -0.4,
                                  hjust = if (orientation == "horizontal") -0.1 else 0.5,
                                  size = 3, color = "#EAF2F8")
    }
  }
  
  # ── Ligne de référence (y = k) ────────────────────────────────────────────
  if (!is.null(ligne_ref) && !is.na(ligne_ref)) {
    if (orientation == "horizontal") {
      g <- g + ggplot2::geom_vline(xintercept = ligne_ref, linetype = "dashed", color = "#E07B39", linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", y = Inf, x = ligne_ref, label = paste0("Seuil : ", ligne_ref),
                          hjust = -0.1, vjust = 1.4, color = "#E07B39", size = 3)
    } else {
      g <- g + ggplot2::geom_hline(yintercept = ligne_ref, linetype = "dashed", color = "#E07B39", linewidth = 0.9, alpha = 0.8) +
        ggplot2::annotate("text", x = Inf, y = ligne_ref, label = paste0("Seuil : ", ligne_ref),
                          hjust = 1.05, vjust = -0.4, color = "#E07B39", size = 3)
    }
  }
  
  # ── Facettes ──────────────────────────────────────────────────────────────
  if (has_facet) {
    g <- g + ggplot2::facet_wrap(ggplot2::vars(.data[[facet_var]]), scales = "free_y", ncol = facet_ncol)
  }
  
  # ── Palettes ──────────────────────────────────────────────────────────────
  if (has_color) {
    if (color_est_continue) {
      g <- g + ggplot2::scale_fill_gradientn(colors = pal_base, name = titre_leg) +
        ggplot2::scale_color_gradientn(colors = pal_base, name = titre_leg)
    } else {
      g <- g + ggplot2::scale_fill_manual(values = pal, name = titre_leg) +
        ggplot2::scale_color_manual(values = pal, name = titre_leg)
    }
  }
  
  # ── Échelles ──────────────────────────────────────────────────────────────
  y_lims <- c(if (!is.na(lim_y_min %||% NA)) as.numeric(lim_y_min) else NA,
              if (!is.na(lim_y_max %||% NA)) as.numeric(lim_y_max) else NA)
  y_trans <- switch(scale_y, "log" = "log10", "inverse" = "reverse", "identity")
  if (has_y && orientation != "horizontal" && !type_viz %in% c("histogramme")) {
    g <- g + ggplot2::scale_y_continuous(trans = y_trans,
                                         limits = if (all(is.na(y_lims))) NULL else y_lims,
                                         labels = scales::number_format(big.mark = "\u202f", accuracy = 0.1))
  }
  if (has_y && is.numeric(df_plot[[x_var]])) {
    x_lims <- c(if (!is.na(lim_x_min %||% NA)) as.numeric(lim_x_min) else NA,
                if (!is.na(lim_x_max %||% NA)) as.numeric(lim_x_max) else NA)
    x_trans <- switch(scale_x, "log" = "log10", "inverse" = "reverse", "identity")
    g <- g + ggplot2::scale_x_continuous(trans = x_trans,
                                         limits = if (all(is.na(x_lims))) NULL else x_lims)
  }
  
  # ── Titres & labels ───────────────────────────────────────────────────────
  g <- g + ggplot2::labs(
    title    = titre,
    subtitle = soustitre,
    caption  = caption,
    x        = if (orientation == "horizontal") titre_y else titre_x,
    y        = if (orientation == "horizontal") titre_x else titre_y
  )
  
  # ── Thème ─────────────────────────────────────────────────────────────────
  leg_ggplot <- switch(legend_pos,
                       "right" = "right", "bottom" = "bottom", "top" = "top", "none" = "none", "right")
  g <- g + theme_crpmem(legend_pos = leg_ggplot)
  if (angle_x != 0) {
    g <- g + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = angle_x, hjust = 1, vjust = 1))
  }
  
  ggplot2::ggsave(file, plot = g,
                  width  = width_px  / dpi,
                  height = height_px / dpi,
                  dpi    = dpi, bg = "#061A2B")
}