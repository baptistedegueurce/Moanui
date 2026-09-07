# =============================================================================
# server_viz.R — Serveur onglet Représentation des données
# Exploite intégralement functions_viz.R
# =============================================================================

server_viz <- function(input, output, session, rv) {
  
  # ===========================================================================
  # 1. SOURCE DE DONNÉES (composant partagé)
  # ===========================================================================
  
  df_source <- app_source_server(
    input    = input,
    output   = output,
    session  = session,
    input_id = "viz",
    rv       = rv
  )
  
  # ===========================================================================
  # 2. INFO + KPI
  # ===========================================================================
  
  output$viz_kpi_preview <- shiny::renderUI({
    df <- df_source()
    if (is.null(df)) return(NULL)
    
    # ── KPI 1 : débarquement_Kg moyen (ou première colonne numérique) ────────
    kg_col <- if ("debarquement_Kg" %in% names(df)) "debarquement_Kg"
    else if (length(cols_numeriques(df)) > 0) cols_numeriques(df)[1]
    else NULL
    val_kg <- if (!is.null(kg_col))
      format(round(mean(df[[kg_col]], na.rm = TRUE)), big.mark = "\u202f")
    else "—"
    lbl_kg <- if (!is.null(kg_col))
      paste0(label_variable(kg_col), " moyen")
    else "Aucune col. num."
    
    # ── KPI 2 : nombre de lignes ──────────────────────────────────────────────
    val_lignes <- format(nrow(df), big.mark = "\u202f")
    
    # ── KPI 3 : nombre de colonnes ────────────────────────────────────────────
    val_cols <- ncol(df)
    
    # ── KPI 4 : navires distincts (nom_navire ou première col. catégorielle) ──
    nav_col <- if ("nom_navire" %in% names(df)) "nom_navire"
    else if (length(cols_categories(df)) > 0) cols_categories(df)[1]
    else NULL
    val_nav <- if (!is.null(nav_col))
      format(dplyr::n_distinct(df[[nav_col]], na.rm = TRUE), big.mark = "\u202f")
    else "—"
    lbl_nav <- if (!is.null(nav_col) && nav_col == "nom_navire") "Navires"
    else if (!is.null(nav_col)) paste0("Distinct. (", nav_col, ")")
    else "Navires"
    
    kpi_box <- function(val, lbl)
      shiny::div(class = "hal-kpi",
                 shiny::div(class = "hal-kpi-val", val),
                 shiny::div(class = "hal-kpi-lbl", lbl)
      )
    
    shiny::fluidRow(
      shiny::column(3, kpi_box(val_kg,     lbl_kg)),
      shiny::column(3, kpi_box(val_lignes, "Lignes")),
      shiny::column(3, kpi_box(as.character(val_cols), "Colonnes")),
      shiny::column(3, kpi_box(val_nav,    lbl_nav))
    )
  })
  
  # ===========================================================================
  # 3. MISE À JOUR SELECTINPUT
  # ===========================================================================
  
  shiny::observe({
    df <- df_source()
    if (is.null(df)) return()
    
    all_cols <- names(df)
    num_cols <- cols_numeriques(df)
    cat_cols <- cols_categories(df)
    
    lbl_all <- stats::setNames(all_cols, sapply(all_cols, label_variable))
    lbl_num <- stats::setNames(num_cols, sapply(num_cols, label_variable))
    lbl_cat <- stats::setNames(cat_cols, sapply(cat_cols, label_variable))
    
    choices_cat <- c("— Aucun —"  = "", lbl_cat)
    choices_num <- c("— Aucune —" = "", lbl_num)
    
    sel_x <- if ("esp_cod_fao"     %in% cat_cols) "esp_cod_fao"
    else if ("an_ref"    %in% all_cols) "an_ref"
    else all_cols[1]
    sel_y <- if ("debarquement_Kg" %in% num_cols) "debarquement_Kg"
    else if (length(num_cols) > 0) num_cols[1] else ""
    
    shiny::updateSelectInput(session, "viz_x_var",      choices = lbl_all,    selected = sel_x)
    shiny::updateSelectInput(session, "viz_y_var",      choices = choices_num, selected = sel_y)
    shiny::updateSelectInput(session, "viz_color_var",  choices = choices_cat)
    shiny::updateSelectInput(session, "viz_facet_var",  choices = choices_cat)
    shiny::updateSelectInput(session, "viz_incert_var", choices = choices_num)
  })
  
  # Forcer agg_fun par défaut selon le type de graphique
  # - boites / violon : "aucune" (les données brutes sont requises)
  # - points          : "aucune" (données brutes)
  # - lignes+points   : géré en interne (ligne=moyenne, points=bruts), on affiche "moyenne"
  # - lignes / aire   : "somme"
  # - barres / lollipop / camembert / donut / histogramme : "somme"
  shiny::observeEvent(input$viz_type_viz, {
    req_type <- input$viz_type_viz
    if (is.null(req_type)) return()
    
    default_agg <- switch(req_type,
                          "boites"       = "aucune",
                          "violon"       = "aucune",
                          "points"       = "aucune",
                          "lignes+points"= "moyenne",
                          "somme"   # défaut pour tous les autres
    )
    shiny::updateSelectInput(session, "viz_agg_fun", selected = default_agg)
  }, ignoreInit = TRUE)
  
  shiny::observeEvent(input$viz_palette_nom, {
    pal <- PALETTES_DISPONIBLES[[input$viz_palette_nom]] %||% palette_hal
    shiny::updateTextInput(session, "viz_couleur_fixe", value = pal[1])
  })
  
  # ===========================================================================
  # 4. PANNEAU PARAMÈTRES CONDITIONNEL
  # ===========================================================================
  
  output$viz_params_conditionnel <- shiny::renderUI({
    type_viz <- input$viz_type_viz %||% "barres"
    
    shiny::tagList(
      
      
      # Barmode
      if (type_viz %in% c("barres","aire"))
        shiny::div(class = "viz-param-block",
                   shiny::tags$label(class = "viz-param-label", "Mode barres"),
                   shiny::selectInput("viz_barmode", label = NULL,
                                      choices  = c("Empilees" = "stack",
                                                   "Groupees" = "group",
                                                   "100%"     = "fill"),
                                      selected = "stack")
        ),
      
      # Orientation
      if (type_viz %in% c("barres","boites","violon","lollipop"))
        shiny::div(class = "viz-param-block",
                   shiny::tags$label(class = "viz-param-label", "Orientation"),
                   shiny::radioButtons("viz_orientation", label = NULL, inline = TRUE,
                                       choices  = c("Verticale"   = "vertical",
                                                    "Horizontale" = "horizontal"),
                                       selected = "vertical")
        ),
      
      # Histogramme bins
      if (type_viz == "histogramme")
        shiny::div(class = "viz-param-block",
                   shiny::tags$label(class = "viz-param-label", "Nombre de classes"),
                   shiny::sliderInput("viz_hist_bins", label = NULL,
                                      min = 5, max = 100, value = 30, step = 5)
        ),
      
      # Taille points / épaisseur lignes
      if (type_viz %in% c("points","lignes","lignes+points","lollipop","violon"))
        shiny::div(class = "viz-param-block",
                   shiny::fluidRow(
                     shiny::column(6,
                                   shiny::tags$label(class = "viz-param-label", "Taille points"),
                                   shiny::sliderInput("viz_taille_pt", label = NULL,
                                                      min = 1, max = 10, value = 3, step = 0.5)
                     ),
                     shiny::column(6,
                                   shiny::tags$label(class = "viz-param-label", "Epaisseur lignes"),
                                   shiny::sliderInput("viz_epaisseur_l", label = NULL,
                                                      min = 0.3, max = 4, value = 1.2, step = 0.1)
                     )
                   )
        ),
      
      # Lissage
      if (type_viz %in% c("points","lignes","lignes+points"))
        shiny::div(class = "viz-param-block",
                   shiny::fluidRow(
                     shiny::column(6,
                                   shiny::checkboxInput("viz_smooth", "Courbe de lissage", value = FALSE)
                     ),
                     shiny::column(6,
                                   shiny::conditionalPanel("input.viz_smooth == true",
                                                           shiny::selectInput("viz_smooth_method", label = NULL,
                                                                              choices = c("LOESS" = "loess",
                                                                                          "LM (lineaire)" = "lm",
                                                                                          "GAM" = "gam",
                                                                                          "GLMM" = "glm"))
                                   )
                     )
                   ),
                   shiny::conditionalPanel(
                     "input.viz_smooth == true && input.viz_smooth_method == 'lm'",
                     shiny::checkboxInput("viz_show_equation",
                                          "Afficher l'equation de regression (y = ax + b, R\u00b2)",
                                          value = TRUE)
                   )
        ),
      
      # Incertitudes
      if (!type_viz %in% c("camembert","donut","histogramme"))
        shiny::div(class = "viz-param-block",
                   shiny::checkboxInput("viz_calc_sd", "Afficher barres d'ecart-type", value = FALSE),
                   shiny::conditionalPanel("input.viz_calc_sd == true",
                                           shiny::div(style = "font-size:11px; color:#7FB3D3; margin-bottom:4px;",
                                                      "Ou specifier une colonne SD pre-calculee :"),
                                           shiny::selectInput("viz_incert_var", label = NULL,
                                                              choices = c("— Calculer auto —" = ""))
                   )
        ),
      
      # Top N
      shiny::div(class = "viz-param-block",
                 shiny::tags$label(class = "viz-param-label",
                                   "Limiter aux N premieres modalites (0 = tout)"),
                 shiny::numericInput("viz_top_n", label = NULL,
                                     value = 0, min = 0, max = 500, step = 5)
      ),
      
      # Facettes — contrôle ncol et hauteur
      shiny::div(class = "viz-param-block",
                 shiny::tags$label(class = "viz-param-label",
                                   "Facettes : colonnes & hauteur par panel"),
                 shiny::fluidRow(
                   shiny::column(6,
                                 shiny::numericInput("viz_facet_ncol", "Nb colonnes",
                                                     value = 2, min = 1, max = 6, step = 1)
                   ),
                   shiny::column(6,
                                 shiny::numericInput("viz_facet_height", "Haut./panel (px)",
                                                     value = 280, min = 150, max = 600, step = 20)
                   )
                 )
      ),
      
      # Aide contextuelle
      aide_type_graphique(type_viz)
    )
  })
  
  # ===========================================================================
  # 5. PANNEAU APPARENCE
  # FIX 1 : opacite et angle_x sont dans l'UI STATIQUE de tab_viz
  #          (inputs permanents, jamais recréés = valeur conservée)
  #          On les retire du renderUI pour éviter le reset
  # ===========================================================================
  
  output$viz_apparence_panel <- shiny::renderUI({
    # Les inputs show_values, legend_pos, titre_leg, ligne_ref, palette_nom, couleur_fixe
    # sont des inputs STATIQUES définis dans tab_viz.R (hors renderUI)
    # Ce renderUI ne contient plus que le preview de palette (qui n'est pas un input)
    shiny::uiOutput("viz_palette_preview")
  })
  
  output$viz_palette_preview <- shiny::renderUI({
    pal <- PALETTES_DISPONIBLES[[input$viz_palette_nom %||% "CRPMEM (défaut)"]] %||% palette_hal
    swatches <- lapply(pal, function(col)
      shiny::tags$div(style = sprintf(
        "display:inline-block; width:22px; height:22px; border-radius:4px;
         background:%s; margin:2px; vertical-align:middle;", col))
    )
    shiny::div(style = "padding:6px 0;", shiny::tagList(swatches))
  })
  
  # ===========================================================================
  # 6. PANNEAU AXES
  # ===========================================================================
  
  output$viz_axes_panel <- shiny::renderUI({
    shiny::tagList(
      
      shiny::div(class = "viz-param-block",
                 shiny::fluidRow(
                   shiny::column(6,
                                 shiny::tags$label(class = "viz-param-label", "Echelle X"),
                                 shiny::selectInput("viz_scale_x", label = NULL,
                                                    choices = c("Lineaire" = "lineaire",
                                                                "Log10"    = "log",
                                                                "Inverse"  = "inverse"))
                   ),
                   shiny::column(6,
                                 shiny::tags$label(class = "viz-param-label", "Echelle Y"),
                                 shiny::selectInput("viz_scale_y", label = NULL,
                                                    choices = c("Lineaire" = "lineaire",
                                                                "Log10"    = "log",
                                                                "Inverse"  = "inverse"))
                   )
                 )
      ),
      
      shiny::div(class = "viz-param-block",
                 shiny::tags$label(class = "viz-param-label",
                                   "Limites axe Y (laisser vide = auto)"),
                 shiny::fluidRow(
                   shiny::column(6, shiny::numericInput("viz_lim_y_min", "Min Y", value = NA)),
                   shiny::column(6, shiny::numericInput("viz_lim_y_max", "Max Y", value = NA))
                 )
      ),
      
      shiny::div(class = "viz-param-block",
                 shiny::tags$label(class = "viz-param-label",
                                   "Limites axe X numerique (laisser vide = auto)"),
                 shiny::fluidRow(
                   shiny::column(6, shiny::numericInput("viz_lim_x_min", "Min X", value = NA)),
                   shiny::column(6, shiny::numericInput("viz_lim_x_max", "Max X", value = NA))
                 )
      )
    )
  })
  
  # ===========================================================================
  # 7. APERÇU TABLE
  # ===========================================================================
  
  output$viz_table_preview <- DT::renderDataTable({
    df <- df_source()
    shiny::req(df)
    DT::datatable(
      head(df, input$viz_nrows_preview %||% 100),
      rownames   = FALSE,
      filter     = "top",
      extensions = "Scroller",
      options    = list(
        dom        = "frti",
        scrollX    = TRUE,
        scrollY    = "380px",
        scroller   = TRUE,
        pageLength = 50,
        language   = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/French.json")
      ),
      class = "display compact nowrap"
    )
  })
  
  # ===========================================================================
  # 8. PARAMS CENTRALISÉS
  # FIX 1 : viz_opacite et viz_angle_x sont des inputs STATIQUES dans tab_viz
  #          (placés hors du renderUI) → leur valeur est lue ici normalement
  # ===========================================================================
  
  params_viz <- shiny::reactive({
    df <- df_source()
    shiny::req(df, input$viz_x_var, nzchar(input$viz_x_var))
    
    list(
      df          = df,
      
      type_viz    = input$viz_type_viz   %||% "barres",
      x_var       = input$viz_x_var,
      y_var       = if (nzchar(input$viz_y_var     %||% "")) input$viz_y_var     else NULL,
      color_var   = if (nzchar(input$viz_color_var %||% "")) input$viz_color_var else NULL,
      facet_var   = if (nzchar(input$viz_facet_var %||% "")) input$viz_facet_var else NULL,
      
      agg_fun     = input$viz_agg_fun   %||% "somme",
      calc_sd     = isTRUE(input$viz_calc_sd),
      incert_var  = if (nzchar(input$viz_incert_var %||% "")) input$viz_incert_var else NULL,
      top_n       = as.integer(input$viz_top_n %||% 0),
      
      anonymiser  = isTRUE(input$viz_anonymiser),
      
      titre       = input$viz_titre     %||% "",
      soustitre   = input$viz_soustitre %||% "",
      titre_x     = input$viz_titre_x   %||% "",
      titre_y     = input$viz_titre_y   %||% "",
      titre_leg   = input$viz_titre_leg %||% "",
      caption     = input$viz_caption   %||% "",
      
      palette_nom  = input$viz_palette_nom  %||% "CRPMEM (défaut)",
      couleur_fixe = input$viz_couleur_fixe %||% "#0077B6",
      barmode      = input$viz_barmode      %||% "stack",
      orientation  = input$viz_orientation  %||% "vertical",
      show_values  = isTRUE(input$viz_show_values),
      legend_pos   = input$viz_legend_pos   %||% "right",
      # FIX 1 : inputs statiques → valeur toujours disponible, jamais réinitialisée
      opacite      = as.numeric(input$viz_opacite    %||% 0.85),
      angle_x      = as.numeric(input$viz_angle_x    %||% 0),
      taille_pt    = as.numeric(input$viz_taille_pt  %||% 3),
      epaisseur_l  = as.numeric(input$viz_epaisseur_l %||% 1.2),
      smooth       = isTRUE(input$viz_smooth),
      smooth_method= input$viz_smooth_method %||% "loess",
      show_equation= isTRUE(input$viz_show_equation),
      ligne_ref    = suppressWarnings(as.numeric(input$viz_ligne_ref)),
      
      scale_x      = input$viz_scale_x %||% "lineaire",
      scale_y      = input$viz_scale_y %||% "lineaire",
      lim_y_min    = input$viz_lim_y_min,
      lim_y_max    = input$viz_lim_y_max,
      lim_x_min    = input$viz_lim_x_min,
      lim_x_max    = input$viz_lim_x_max,
      
      hist_bins    = as.integer(input$viz_hist_bins %||% 30),
      
      # FIX 5 : paramètres facettes pour hauteur dynamique
      facet_ncol   = as.integer(input$viz_facet_ncol   %||% 2),
      facet_height = as.integer(input$viz_facet_height  %||% 280),
      
      sort_x         = input$viz_sort_x %||% "aucun",
      
      hauteur_display = as.integer(input$viz_hauteur_display %||% 600),
      largeur_export = as.integer(input$viz_largeur_export %||% 1400),
      hauteur_export = as.integer(input$viz_hauteur_export %||% 800)
    )
  })
  
  # ===========================================================================
  # 9. GRAPHIQUE PRINCIPAL
  # ===========================================================================
  
  output$viz_graphique <- plotly::renderPlotly({
    shiny::req(input$viz_refresh)
    shiny::isolate({
      tryCatch(
        construire_graphique_viz(params_viz()),
        error = function(e) plotly_vide(paste("Erreur :", e$message))
      )
    })
  }) |> shiny::bindEvent(input$viz_refresh, ignoreNULL = FALSE)
  
  # ===========================================================================
  # PUSH COMPOSITION — capture le ggplot statique après chaque rendu
  # ===========================================================================
  shiny::observeEvent(input$viz_refresh, {
    push <- session$userData$compo_push
    if (!is.function(push)) return()
    
    p <- tryCatch(shiny::isolate(params_viz()), error = function(e) NULL)
    if (is.null(p)) return()
    
    gg <- tryCatch(construire_ggplot_viz(p), error = function(e) NULL)
    if (is.null(gg)) return()   # camembert/donut ou données vides : on ignore
    
    lbl <- paste0(
      p$type_viz, " \u2014 ",
      if (!is.null(p$y_var) && nzchar(p$y_var)) label_variable(p$y_var) else "n",
      " / ", label_variable(p$x_var),
      if (!is.null(p$titre) && nzchar(p$titre)) paste0(" (", p$titre, ")") else ""
    )
    push(plot_gg = gg, label = lbl, source = "viz")
  }, ignoreInit = TRUE)
  
  # Injecte la hauteur CSS du container ET du plotly selon facettes
  output$viz_plot_height_css <- shiny::renderUI({
    p  <- shiny::req(params_viz())
    df <- df_source()
    has_facets <- !is.null(df) && !is.null(p$facet_var) &&
      nzchar(p$facet_var %||% "") && p$facet_var %in% names(df)
    
    if (has_facets) {
      # Avec facettes : hauteur fixe calculée dynamiquement
      n_facets <- dplyr::n_distinct(df[[p$facet_var]], na.rm = TRUE)
      ncol_f   <- max(1L, p$facet_ncol)
      nrow_f   <- ceiling(n_facets / ncol_f)
      hauteur  <- max(500L, nrow_f * p$facet_height)
      hauteur_container <- min(hauteur + 20L, 1400L)
      shiny::tags$style(shiny::HTML(sprintf(
        "#viz_graphique { height: %dpx !important; }
         #viz_graphique .plotly { height: %dpx !important; }
         #viz_graphique .js-plotly-plot { height: %dpx !important; }
         .viz-plot-wrap { height: %dpx !important; max-height: unset !important;
                          overflow: auto !important; }",
        hauteur, hauteur, hauteur, hauteur_container
      )))
    } else {
      # Sans facettes : hauteur basée sur hauteur_display (indépendant de l'export)
      hauteur_def <- max(400L, as.integer(p$hauteur_display %||% 600L))
      shiny::tags$style(shiny::HTML(sprintf(
        "#viz_graphique { height: %dpx !important; }
         #viz_graphique .plotly { height: %dpx !important; }
         #viz_graphique .js-plotly-plot { height: %dpx !important; }
         .viz-plot-wrap { height: %dpx !important; }",
        hauteur_def, hauteur_def, hauteur_def, hauteur_def + 20L
      )))
    }
  })
  
  # ===========================================================================
  # 10. CODE R ÉQUIVALENT
  # ===========================================================================
  
  output$viz_code_r <- shiny::renderText({
    df <- df_source()
    if (is.null(df) || is.null(input$viz_x_var)) return("# Chargez des donnees.")
    p <- params_viz()
    paste0(
      '# Charger\ndf <- readRDS("votre_fichier.rds")\n\n',
      '# Preparer\nprep <- preparer_donnees_viz(\n',
      '  df       = df,\n',
      '  x_var    = "', p$x_var, '",\n',
      if (!is.null(p$y_var))     paste0('  y_var    = "', p$y_var, '",\n') else '',
      if (!is.null(p$color_var)) paste0('  color_var = "', p$color_var, '",\n') else '',
      '  agg_fun  = "', p$agg_fun, '",\n',
      '  top_n    = ', p$top_n, '\n',
      ')\ndf_plot <- prep$df\n\n',
      '# Graphique\nggplot2::ggplot(df_plot, ggplot2::aes(x = .data[["', p$x_var, '"]]',
      if (!is.null(p$y_var))     paste0(', y = .data[["', p$y_var, '"]]') else '',
      if (!is.null(p$color_var)) paste0(', fill = .data[["', p$color_var, '"]]') else '',
      ')) +\n',
      switch(p$type_viz,
             "barres"        = '  ggplot2::geom_col() +\n',
             "lignes"        = '  ggplot2::geom_line(aes(group = 1)) +\n',
             "lignes+points" = '  ggplot2::geom_line(aes(group = 1)) + ggplot2::geom_point() +\n',
             "points"        = '  ggplot2::geom_point() +\n',
             "boites"        = '  ggplot2::geom_boxplot() +\n',
             "violon"        = '  ggplot2::geom_violin() + ggplot2::geom_boxplot(width = 0.08) +\n',
             "histogramme"   = paste0('  ggplot2::geom_histogram(bins = ', p$hist_bins, ') +\n'),
             "lollipop"      = '  ggplot2::geom_segment(...) + ggplot2::geom_point() +\n',
             '  ggplot2::geom_col() +\n'
      ),
      '  ggplot2::labs(title = "', p$titre, '", x = "', p$titre_x, '", y = "', p$titre_y, '") +\n',
      '  theme_crpmem()'
    )
  })
  
  # ===========================================================================
  # 11. EXPORTS
  # ===========================================================================
  
  output$viz_export_png <- shiny::downloadHandler(
    filename = function() paste0("graphique_", format(Sys.Date(), "%Y%m%d_%H%M"), ".png"),
    content  = function(file) {
      p <- params_viz()
      shiny::withProgress(message = "Rendu PNG...", {
        tryCatch(
          exporter_ggplot_png(p, file, width_px = p$largeur_export, height_px = p$hauteur_export),
          error = function(e)
            shiny::showNotification(paste("Export PNG echoue :", e$message),
                                    type = "error", duration = 6)
        )
      })
    }
  )
  
  output$viz_export_html <- shiny::downloadHandler(
    filename = function() paste0("graphique_", format(Sys.Date(), "%Y%m%d_%H%M"), ".html"),
    content  = function(file) {
      p_plotly <- tryCatch(construire_graphique_viz(params_viz()),
                           error = function(e) plotly_vide(e$message))
      htmlwidgets::saveWidget(p_plotly, file, selfcontained = TRUE)
    }
  )
  
  output$viz_export_csv <- shiny::downloadHandler(
    filename = function() paste0("donnees_graphique_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content  = function(file) {
      p    <- params_viz()
      prep <- preparer_donnees_viz(
        df = p$df, x_var = p$x_var, y_var = p$y_var,
        color_var = p$color_var, facet_var = p$facet_var,
        agg_fun = p$agg_fun, calc_sd = p$calc_sd,
        anonymiser = p$anonymiser, top_n = p$top_n,
        sort_x = p$sort_x
      )
      readr::write_csv(prep$df, file)
    }
  )
}

# =============================================================================
# HELPER : aide contextuelle selon le type de graphique
# =============================================================================

aide_type_graphique <- function(type_viz) {
  info <- switch(type_viz,
                 
                 "violon" = list(
                   icon  = "music",
                   titre = "Graphique en violon",
                   texte = "Montre la distribution d'une variable numerique (Y) pour chaque modalite d'une \
variable categorielle (X). La largeur indique la densite : plus c'est large, plus il y a de valeurs \
a cette hauteur. La boite a moustaches centrale donne Q1, mediane, Q3. \
Ex : distribution des debarquements (Y) par espece (X)."
                 ),
                 
                 "lollipop" = list(
                   icon  = "dot-circle",
                   titre = "Graphique en lollipop",
                   texte = "Alternative lisible aux barres quand il y a beaucoup de categories : \
une tige + un point par modalite de X. Necessite une variable X categorielle et Y numerique. \
Le Top N dans les options permet de ne garder que les N plus grands."
                 ),
                 
                 "histogramme" = list(
                   icon  = "align-left",
                   titre = "Histogramme — variable X uniquement",
                   texte = "Montre la distribution d'une seule variable numerique (axe X). \
Ne necessite PAS de variable Y : l'axe Y est le comptage automatique. \
Si vous voyez l'erreur 'stat_bin must have x', verifiez que la variable X est bien numerique \
(pas une colonne texte)."
                 ),
                 
                 "boites" = list(
                   icon  = "box",
                   titre = "Boites a moustaches",
                   texte = "Resument la distribution de Y pour chaque modalite de X : mediane (trait), \
Q1-Q3 (boite), extremes (moustaches). La variable Couleur permet de comparer des sous-groupes \
cote a cote."
                 ),
                 
                 NULL
  )
  
  if (is.null(info)) return(NULL)
  
  shiny::div(
    style = "margin-top:12px; padding:10px 12px; background:#061A2B;
             border:1px solid #1D4E6D; border-radius:6px;
             font-size:11px; color:#7FB3D3; line-height:1.5;",
    shiny::div(style = "font-weight:600; color:#EAF2F8; margin-bottom:6px;",
               shiny::icon(info$icon), " ", info$titre),
    info$texte
  )
}