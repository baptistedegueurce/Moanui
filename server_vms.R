# =============================================================================
# server_vms.R — Serveur onglet "Traitement VMS"
# Signature : server_vms(input, output, session, rv)
# IDs UI préfixés "sv_" pour éviter les collisions
# Dépendances : functions_vms.R, tab_vms.R
#
# Flux :
#   1. Import données brutes (fichier ou données globales)
#   2. Détection / mapping colonnes
#   3. Filtre vitesse
#   4. Traitement (process_vms_data) → df formaté avec col_lat/lon/date/immat/mois/annee
#   5. Croisement mensuel VMS × shapefile rectangles (maille_valpena)
#   6. Pour chaque mois → sélection carte SHOM → rendu ggplot
#   7. Exports : ZIP PNG + ZIP SHP consolidé (tous mois, colonne "mois")
# =============================================================================

server_vms <- function(input, output, session, rv) {
  
  source("R/functions/functions_vms.R", local = TRUE)
  
  # Chemins fixes
  RECT_SHP_PATH       <- "www/shapefile/valpena/maillage_valpena_2.shp"
  ASSEMBLAGE_SHP_PATH <- "www/shapefile/cartes_marines/assemblage_cartes_marines.shp"
  RASTER_DIR          <- "www/shapefile/raster_shom"
  
  # ===========================================================================
  # STOCKAGE CENTRALISÉ DES RÉSULTATS LOURDS
  # Tous les calculs géo (cross + SHOM + rasters) sont faits UNE SEULE FOIS
  # dans observeEvent(sv_generate_maps) et stockés ici. Les renderPlot
  # n'ont plus qu'à lire et dessiner.
  # ===========================================================================
  rv_maps <- shiny::reactiveValues(
    plots_data    = list(),      # liste nommée : "1" … "12" → list(sf_on, sf_context, raster_shom)
    mois_list     = integer(0),  # vecteur des mois disponibles dans l'ordre
    mois_index    = 1L,          # index courant dans mois_list (carousel)
    navire_genere = NULL,        # immat du navire pour lequel le cache a été généré
    annee_generee = NULL         # année correspondante
  )
  
  # ===========================================================================
  # 0. IMPORT DONNÉES BRUTES (composant partagé)
  # ===========================================================================
  
  sv_raw_data <- app_source_server(
    input    = input,
    output   = output,
    session  = session,
    input_id = "sv",
    rv       = rv,
    loader_fn = function(path, ext, sep = ";", dec = ".", enc = "UTF-8") {
      tryCatch(
        read_vms_file(path, basename(path), sep = sep, dec = dec),
        error = function(e) {
          shiny::showNotification(
            paste0("Erreur lecture : ", conditionMessage(e)),
            type = "error", duration = 8
          )
          NULL
        }
      )
    }
  )
  
  # ===========================================================================
  # 1. MAPPING COLONNES — auto-détection + sélecteurs
  # ===========================================================================
  
  output$sv_mapping_ui <- shiny::renderUI({
    df       <- sv_raw_data()
    shiny::req(df)
    detected <- autodetect_vms_cols(df)
    
    lapply(names(VMS_COLS_ATTENDUES), function(var) {
      sel   <- detected[[var]]
      found <- !is.na(sel)
      lbl   <- VMS_COLS_LABELS[[var]]
      
      shiny::div(
        style = "margin-bottom:10px;",
        
        # Label + badge
        shiny::div(
          style = "font-size:11px; font-weight:600; color:#EAF2F8;
                   margin-bottom:1px; display:flex; align-items:center;",
          lbl,
          if (found)
            shiny::tags$span(class = "sv-badge-ok", "\u2713 d\u00e9tect\u00e9e")
          else
            shiny::tags$span(class = "sv-badge-ko", "! \u00e0 mapper")
        ),
        
        shiny::div(
          style = "font-size:10px; color:#4A7A9B; margin-bottom:4px;",
          shiny::code(style = "background:transparent; color:#4A7A9B; padding:0; font-size:10px;", var)
        ),
        
        shiny::selectInput(
          inputId  = paste0("sv_map_", var),
          label    = NULL,
          choices  = setNames(c(NA_character_, names(df)), c("(non mapp\u00e9e)", names(df))),
          selected = if (found) sel else NA_character_
        )
      )
    })
  })
  
  # Mapping résolu : var → nom colonne source
  sv_mapping <- shiny::reactive({
    df <- sv_raw_data()
    shiny::req(df)
    lapply(names(VMS_COLS_ATTENDUES), function(var) {
      val <- input[[paste0("sv_map_", var)]]
      if (!is.null(val) && !is.na(val) && val %in% names(df)) val else NA_character_
    }) |> setNames(names(VMS_COLS_ATTENDUES))
  })
  
  # ===========================================================================
  # 2. TYPE VMS (CLS / Agiltech)
  # ===========================================================================
  
  sv_vms_type <- shiny::reactive({
    df  <- sv_raw_data()
    shiny::req(df)
    m   <- sv_mapping()
    col <- m[["col_immat"]]
    if (!is.na(col) && col %in% names(df))
      detect_vms_type(df, col)
    else
      detect_vms_type(df, "col_immat")
  })
  
  # ===========================================================================
  # 3. FILTRE VITESSE — UI dynamique
  # ===========================================================================
  
  # Hint dynamique seulement (plage observée + badge CLS)
  # Le slider lui-même est statique dans tab_vms.R → toujours dispo côté serveur
  output$sv_speed_hint_ui <- shiny::renderUI({
    df  <- sv_raw_data()
    m   <- sv_mapping()
    col <- if (!is.null(m)) m[["col_speed"]] else NA_character_
    if (is.null(df) || is.na(col) || !col %in% names(df))
      return(shiny::p(class = "sv-hint",
                      shiny::icon("exclamation-triangle"),
                      " Colonne vitesse non mapp\u00e9e."))
    speeds_raw  <- suppressWarnings(as.numeric(df[[col]]))
    speeds_raw  <- speeds_raw[!is.na(speeds_raw)]
    vms_type    <- sv_vms_type()
    speeds_disp <- if (vms_type == "cls") speeds_raw / 10 else speeds_raw
    v_min <- round(min(speeds_disp, na.rm = TRUE), 1)
    v_max <- round(max(speeds_disp, na.rm = TRUE), 1)
    shiny::div(
      style = "font-size:10px; color:#7FB3D3; margin-bottom:6px;",
      shiny::icon("info-circle"),
      " Plage observ\u00e9e : ", v_min, " \u2013 ", v_max, " n\u0153uds",
      if (vms_type == "cls") shiny::tags$span(
        style = "color:#E8870A; margin-left:6px;",
        "(CLS : valeurs \u00f7 10 d\u00e9j\u00e0 appliqu\u00e9es)"
      )
    )
  })
  
  # Met à jour le slider (bornes + valeur) quand les données changent
  shiny::observe({
    df  <- sv_raw_data()
    m   <- sv_mapping()
    col <- if (!is.null(m)) m[["col_speed"]] else NA_character_
    if (is.null(df) || is.na(col) || !col %in% names(df)) return()
    speeds_raw  <- suppressWarnings(as.numeric(df[[col]]))
    speeds_raw  <- speeds_raw[!is.na(speeds_raw)]
    vms_type    <- sv_vms_type()
    speeds_disp <- if (vms_type == "cls") speeds_raw / 10 else speeds_raw
    v_min <- floor(min(speeds_disp,   na.rm = TRUE))
    v_max <- ceiling(max(speeds_disp, na.rm = TRUE))
    v_max <- max(v_max, v_min + 1)
    shiny::updateSliderInput(session, "sv_speed_slider",
                             min   = v_min, max   = v_max,
                             value = c(v_min, v_max))
    shiny::updateNumericInput(session, "sv_speed_min",
                              value = v_min, min = v_min, max = v_max)
    shiny::updateNumericInput(session, "sv_speed_max",
                              value = v_max, min = v_min, max = v_max)
  })
  
  sv_speed_range <- shiny::reactive({
    # Le slider est la SEULE source de vérité pour le filtre vitesse.
    # Les numericInput (sv_speed_min / sv_speed_max) ne servent qu'à
    # l'affichage — leur valeur est synchronisée vers le slider via JS,
    # pas l'inverse. On ne les lit jamais ici pour éviter les conflits.
    slider_val <- input$sv_speed_slider
    if (!is.null(slider_val) && length(slider_val) == 2 &&
        all(is.finite(slider_val)))
      return(as.numeric(slider_val))
    c(0, Inf)   # fallback : UI pas encore rendue
  })
  
  # ===========================================================================
  # 4. KPI TILES
  # ===========================================================================
  
  output$sv_kpi_row <- shiny::renderUI({
    df <- sv_raw_data()
    shiny::req(df)
    m  <- sv_mapping()
    
    # Parsing dates pour les KPI
    # Utilise sv_data_navire() si disponible (déjà parsé correctement),
    # sinon applique le même parsing robuste multi-format que process_vms_data.
    annees    <- NULL
    mois_vals <- NULL
    df_proc <- tryCatch(sv_data_navire(), error = function(e) NULL)
    if (!is.null(df_proc) && nrow(df_proc) > 0 &&
        "annee" %in% names(df_proc) && "mois" %in% names(df_proc)) {
      # Données déjà parsées par process_vms_data → utiliser directement
      annees    <- sort(unique(df_proc$annee[!is.na(df_proc$annee) &
                                               df_proc$annee >= 1990]))
      mois_vals <- sort(unique(df_proc$mois[!is.na(df_proc$mois)]))
    } else if (!is.na(m[["col_date"]]) && m[["col_date"]] %in% names(df)) {
      # Parsing multi-format robuste (même logique que process_vms_data)
      d_chr <- as.character(df[[m[["col_date"]]]])
      date_formats <- c(
        "%Y%m%d", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d",
        "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y",
        "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y",
        "%d-%m-%Y %H:%M:%S", "%d-%m-%Y %H:%M", "%d-%m-%Y",
        "%d.%m.%Y %H:%M:%S", "%d.%m.%Y %H:%M", "%d.%m.%Y"
      )
      parsed    <- rep(as.Date(NA), length(d_chr))
      remaining <- seq_along(d_chr)
      for (fmt in date_formats) {
        if (length(remaining) == 0) break
        trial <- suppressWarnings(as.Date(d_chr[remaining], format = fmt))
        valid  <- !is.na(trial) & as.integer(format(trial, "%Y")) >= 1990
        parsed[remaining[valid]] <- trial[valid]
        remaining <- remaining[!valid]
      }
      annees    <- sort(unique(as.integer(format(parsed, "%Y"))))
      annees    <- annees[!is.na(annees) & annees >= 1990]
      mois_vals <- sort(unique(as.integer(format(parsed, "%m"))))
      mois_vals <- mois_vals[!is.na(mois_vals)]
    } else {
      if ("annee" %in% names(df)) annees    <- sort(unique(df$annee[!is.na(df$annee) & df$annee >= 1990]))
      if ("mois"  %in% names(df)) mois_vals <- sort(unique(df$mois[!is.na(df$mois)]))
    }
    
    n_navires   <- if (!is.na(m[["col_immat"]]) && m[["col_immat"]] %in% names(df))
      dplyr::n_distinct(df[[m[["col_immat"]]]], na.rm = TRUE) else "—"
    
    multi_annee <- !is.null(annees) && length(annees) > 1
    vms_type    <- sv_vms_type()
    
    kpi_box <- function(val, lbl, warn = FALSE) {
      shiny::div(
        class = paste0("sv-kpi", if (warn) " sv-kpi-warn" else ""),
        shiny::div(class = "sv-kpi-val", val),
        shiny::div(class = "sv-kpi-lbl", lbl)
      )
    }
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(2, kpi_box(if (!is.null(annees)) length(annees) else "?",
                                 "Ann\u00e9e(s)", warn = multi_annee)),
        shiny::column(2, kpi_box(if (!is.null(mois_vals)) length(mois_vals) else "?",
                                 "Mois distincts")),
        shiny::column(2, kpi_box(as.character(n_navires), "Navire(s)")),
        shiny::column(2, kpi_box(format(nrow(df), big.mark = "\u202f"), "Lignes brutes")),
        shiny::column(4,
                      shiny::div(
                        class = paste0("sv-kpi", if (multi_annee) " sv-kpi-warn" else ""),
                        shiny::div(
                          style = "font-size:11px; font-weight:600; color:#EAF2F8; margin-bottom:4px;",
                          "Type d\u00e9tect\u00e9",
                          shiny::tags$span(class = paste0("sv-type-badge sv-type-", vms_type), toupper(vms_type))
                        ),
                        if (vms_type == "cls")
                          shiny::div(style = "font-size:10px; color:#7FB3D3;",
                                     shiny::icon("divide"), " Vitesse \u00f7 10 appliqu\u00e9e automatiquement")
                        else
                          shiny::div(style = "font-size:10px; color:#7FB3D3;",
                                     shiny::icon("check"), " Vitesse non modifi\u00e9e"),
                        if (multi_annee)
                          shiny::div(style = "font-size:10px; color:#E67E22; margin-top:4px;",
                                     shiny::icon("exclamation-triangle"),
                                     " Plusieurs ann\u00e9es d\u00e9tect\u00e9es !")
                      )
        )
      )
    )
  })
  
  # ===========================================================================
  # 5. APERÇU DONNÉES BRUTES
  # ===========================================================================
  
  output$sv_table_preview <- DT::renderDataTable({
    # Afficher les données TRAITÉES si disponibles (vitesses converties,
    # filtre appliqué), sinon les données brutes en attente de traitement.
    df_proc <- tryCatch(sv_data_processed(), error = function(e) NULL)
    df      <- if (!is.null(df_proc)) df_proc else sv_raw_data()
    shiny::req(df)
    n  <- min(input$sv_nrows_preview %||% 200, nrow(df))
    # Colonnes à afficher : les colonnes métier renommées en priorité
    cols_show <- intersect(
      c("col_immat","col_date","col_lat","col_lon","col_speed",
        "annee","mois","vms_type"),
      names(df)
    )
    df_show <- if (length(cols_show) > 0) df[, cols_show, drop = FALSE] else df
    DT::datatable(
      head(df_show, n),
      options  = list(
        pageLength = 15, scrollX = TRUE, dom = "tip",
        language   = list(url = "//cdn.datatables.net/plug-ins/1.10.21/i18n/French.json")
      ),
      rownames = FALSE,
      class    = "compact stripe"
    )
  })
  
  # ===========================================================================
  # 6. TRAITEMENT PRINCIPAL
  #    process_vms_data → renomme colonnes, parse dates, filtre vitesse / NA
  # ===========================================================================
  
  sv_data_processed <- shiny::eventReactive(input$sv_run, {
    df <- sv_raw_data()
    shiny::req(df)
    m  <- sv_mapping()
    # Lire le slider directement ici — sv_speed_range() peut retourner
    # un cache obsolète si Shiny n'a pas encore propagé le changement.
    slider_raw <- shiny::isolate(input$sv_speed_slider)
    sr <- if (!is.null(slider_raw) && length(slider_raw) == 2 && all(is.finite(slider_raw)))
      as.numeric(slider_raw) else sv_speed_range()
    message(sprintf("[VMS] Lancer cliqué — slider=[%.2f, %.2f]", sr[1], sr[2]))
    
    shiny::withProgress(message = "Traitement VMS en cours...", value = 0, {
      shiny::incProgress(0.3, detail = "Application du mapping et parsing dates...")
      df_out <- process_vms_data(df, mapping = m, speed_range = sr)
      shiny::incProgress(0.7, detail = "Finalisation...")
      df_out
    })
  })
  
  output$sv_run_status <- shiny::renderUI({
    df <- sv_data_processed()
    shiny::req(df)
    shiny::tagList(
      shiny::div(
        style = "font-size:11px; color:#2E9E6B; margin-top:4px;",
        shiny::icon("check-circle"),
        sprintf(" Traitement termin\u00e9 \u2014 %s lignes conserv\u00e9es",
                format(nrow(df), big.mark = "\u202f"))
      ),
      shiny::div(
        style = "font-size:10px; color:#7FB3D3; margin-top:2px;",
        shiny::icon("arrow-right"), " Rendez-vous dans l'onglet Cartes."
      )
    )
  })
  
  # Mise à jour du sélecteur navire après traitement
  shiny::observe({
    df <- sv_data_processed()
    shiny::req(df)
    if (!"col_immat" %in% names(df)) return()
    navires <- sort(unique(as.character(df$col_immat[!is.na(df$col_immat)])))
    shiny::updateSelectInput(session, "sv_sel_navire",
                             choices  = navires,
                             selected = navires[1])
  })
  
  # ===========================================================================
  # 7. CHARGEMENT DES FICHIERS GÉOGRAPHIQUES
  # ===========================================================================
  
  # Shapefile rectangles (maille_valpena) — chargé une seule fois par session
  sv_sf_rect <- shiny::reactive({
    tryCatch(sf::st_read(RECT_SHP_PATH, quiet = TRUE), error = function(e) NULL)
  }) |> shiny::bindCache(RECT_SHP_PATH)
  
  # Version pré-traitée : st_make_valid + harmonisation CRS + centroïdes précalculés
  # Fait UNE SEULE FOIS plutôt qu'à chaque appel de cross_vms_rectangles (×12 mois)
  sv_sf_rect_prep <- shiny::reactive({
    sf_r <- sv_sf_rect()
    if (is.null(sf_r)) return(NULL)
    sf::sf_use_s2(FALSE)
    on.exit(sf::sf_use_s2(TRUE))
    sf_r <- tryCatch(sf::st_make_valid(sf_r), error = function(e) sf_r)
    if (!is.na(sf::st_crs(sf_r)) && sf::st_crs(sf_r) != sf::st_crs(4326))
      sf_r <- tryCatch(sf::st_transform(sf_r, 4326), error = function(e) sf_r)
    else if (is.na(sf::st_crs(sf_r)))
      sf_r <- sf::st_set_crs(sf_r, 4326)
    # Centroïdes pré-calculés stockés comme attribut — évite de les recalculer ×12
    attr(sf_r, "centroids_xy") <- sf::st_coordinates(
      suppressWarnings(sf::st_centroid(sf_r))
    )
    sf_r
  }) |> shiny::bindCache(RECT_SHP_PATH)
  
  output$sv_shp_status <- shiny::renderUI({
    sf_r <- sv_sf_rect()
    if (is.null(sf_r))
      shiny::div(style = "font-size:10px; color:#E67E22;",
                 shiny::icon("exclamation-triangle"),
                 " maillage_valpena_2.shp introuvable")
    else
      shiny::div(style = "font-size:10px; color:#2E9E6B;",
                 shiny::icon("check-circle"),
                 sprintf(" %d rectangles charg\u00e9s", nrow(sf_r)))
  })
  
  # Assemblage cartes marines — chargé une seule fois par session
  sv_assemblage <- shiny::reactive({
    load_assemblage_shp(ASSEMBLAGE_SHP_PATH)
  }) |> shiny::bindCache(ASSEMBLAGE_SHP_PATH)
  
  output$sv_assemblage_status <- shiny::renderUI({
    asm <- sv_assemblage()
    if (is.null(asm))
      shiny::div(style = "font-size:10px; color:#E67E22;",
                 shiny::icon("exclamation-triangle"),
                 " assemblage_cartes_marines.shp introuvable")
    else
      shiny::div(style = "font-size:10px; color:#2E9E6B;",
                 shiny::icon("check-circle"),
                 sprintf(" %d cartes marines charg\u00e9es", nrow(asm)))
  })
  
  # Rasters SHOM disponibles
  output$sv_raster_status <- shiny::renderUI({
    rasters <- list.files(RASTER_DIR, pattern = "\\.tif$", ignore.case = TRUE)
    if (length(rasters) == 0)
      shiny::div(style = "font-size:10px; color:#E67E22;",
                 shiny::icon("exclamation-triangle"),
                 " Aucun raster .tif trouv\u00e9")
    else
      shiny::div(style = "font-size:10px; color:#2E9E6B;",
                 shiny::icon("check-circle"),
                 sprintf(" %d raster(s) disponible(s)", length(rasters)))
  })
  
  # ===========================================================================
  # 8. DONNÉES FILTRÉES SUR LE NAVIRE SÉLECTIONNÉ
  # ===========================================================================
  
  sv_data_navire <- shiny::reactive({
    df <- sv_data_processed()
    shiny::req(df, input$sv_sel_navire, nzchar(input$sv_sel_navire))
    if (!"col_immat" %in% names(df)) return(df)
    df[df$col_immat == input$sv_sel_navire & !is.na(df$col_immat), ]
  })
  
  sv_mois_dispo <- shiny::reactive({
    df <- sv_data_navire()
    shiny::req(df)
    if (!"mois" %in% names(df)) return(integer(0))
    vals <- df$mois[!is.na(df$mois) & df$mois >= 1 & df$mois <= 12]
    sort(unique(as.integer(vals)))
  })
  
  sv_annee_courante <- shiny::reactive({
    df <- sv_data_navire()
    shiny::req(df)
    if (!"annee" %in% names(df)) return(NA_integer_)
    annees <- sort(unique(df$annee[!is.na(df$annee)]))
    annees[1]
  })
  
  # ===========================================================================
  # 9. GÉNÉRATION ET AFFICHAGE DES CARTES PAR MOIS
  #
  # Architecture : les 12 renderPlot sont enregistrés UNE SEULE FOIS au
  # démarrage du serveur (pas dans un observeEvent). Ils lisent rv_maps$plots_data
  # de façon réactive — dès qu'une clé est écrite, le plot correspondant se dessine.
  # L'observeEvent ne fait que le calcul lourd + écriture dans rv_maps.
  # ===========================================================================
  
  # ===========================================================================
  # 9b. CAROUSEL — un seul plot affiché, navigation mois par mois
  # ===========================================================================
  
  # Navigation flèche gauche
  shiny::observeEvent(input$sv_carousel_prev, {
    mois <- rv_maps$mois_list
    if (length(mois) == 0) return()
    idx <- rv_maps$mois_index
    rv_maps$mois_index <- if (idx <= 1L) length(mois) else idx - 1L
  })
  
  # Navigation flèche droite
  shiny::observeEvent(input$sv_carousel_next, {
    mois <- rv_maps$mois_list
    if (length(mois) == 0) return()
    idx <- rv_maps$mois_index
    rv_maps$mois_index <- if (idx >= length(mois)) 1L else idx + 1L
  })
  
  # Rendu unique du plot courant
  output$sv_carousel_plot <- shiny::renderPlot({
    mois <- rv_maps$mois_list
    idx  <- rv_maps$mois_index
    shiny::validate(shiny::need(length(mois) > 0 && idx >= 1 && idx <= length(mois), ""))
    m_num  <- mois[idx]
    data   <- rv_maps$plots_data[[as.character(m_num)]]
    navire <- shiny::isolate(input$sv_sel_navire) %||% ""
    annee  <- shiny::isolate(tryCatch(sv_annee_courante(), error = function(e) NA_integer_))
    shiny::validate(shiny::need(!is.null(data), "Calcul en cours…"))
    make_vms_map(
      sf_rect_on      = data$sf_on,
      sf_rect_context = data$sf_context,
      raster_shom     = data$raster_shom,
      navire          = navire,
      mois_num        = m_num,
      annee           = annee,
      downsample_px   = 2500   # résolution écran améliorée
    )
  }, bg = "#061A2B", res = 96)
  
  # UI : carousel complet (flèches + plot + indicateur de mois)
  output$sv_maps_output <- shiny::renderUI({
    
    if (is.null(input$sv_run) || input$sv_run == 0)
      return(sv_empty("Lancez d'abord le traitement dans l'onglet « Données ».", "database"))
    
    if (is.null(input$sv_generate_maps) || input$sv_generate_maps == 0)
      return(sv_empty("Cliquez sur « Générer les cartes » pour lancer l'affichage.", "map"))
    
    df      <- tryCatch(sv_data_navire(),    error = function(e) NULL)
    sf_rect <- sv_sf_rect()
    mois    <- rv_maps$mois_list
    navire  <- input$sv_sel_navire %||% ""
    annee   <- tryCatch(sv_annee_courante(), error = function(e) NA_integer_)
    
    if (is.null(df) || nrow(df) == 0 || is.null(sf_rect) || !nzchar(navire))
      return(sv_empty("Sélectionnez un navire après le traitement.", "ship"))
    if (length(mois) == 0)
      return(sv_empty("Aucune donnée mensuelle détectée pour ce navire.", "calendar"))
    
    idx <- rv_maps$mois_index
    if (is.null(idx) || idx < 1L || idx > length(mois)) idx <- 1L
    m_cur <- mois[idx]
    
    # Pastilles de navigation : un point par mois, coloré si actif
    dots <- lapply(seq_along(mois), function(i) {
      shiny::tags$span(
        style = paste0(
          "display:inline-block; width:8px; height:8px; border-radius:50%; margin:0 3px; cursor:pointer; ",
          if (i == idx) "background:#E8870A;" else "background:#2A5070;"
        ),
        onclick = sprintf("Shiny.setInputValue('sv_carousel_goto', %d, {priority:'event'})", i)
      )
    })
    
    shiny::tagList(
      # Bandeau info navire / année / compteur
      shiny::div(
        style = "font-size:11px; color:#7FB3D3; margin-bottom:8px; display:flex; align-items:center; gap:12px;",
        shiny::div(shiny::icon("ship"), shiny::tags$strong(style="color:#EAF2F8;", navire)),
        shiny::div(shiny::icon("calendar"), shiny::tags$strong(style="color:#EAF2F8;", if (is.na(annee)) "—" else as.character(annee))),
        shiny::div(style="color:#4A7A9B;", sprintf("%d/%d mois", idx, length(mois)))
      ),
      
      # Zone carousel : flèche gauche | plot | flèche droite
      shiny::div(
        style = "display:flex; align-items:center; gap:6px;",
        
        # Flèche précédent
        shiny::div(
          style = "flex-shrink:0;",
          shiny::actionButton(
            "sv_carousel_prev", label = NULL,
            icon  = shiny::icon("chevron-left"),
            style = paste0(
              "background:#0D2A44; border:1px solid #1D4E6D; color:#7FB3D3; ",
              "width:44px; height:44px; border-radius:50%; padding:0; font-size:18px; ",
              "display:flex; align-items:center; justify-content:center;"
            )
          )
        ),
        
        # Plot principal (grand)
        shiny::div(
          style = "flex:1; min-width:0;",
          shiny::plotOutput("sv_carousel_plot", height = "520px")
        ),
        
        # Flèche suivant
        shiny::div(
          style = "flex-shrink:0;",
          shiny::actionButton(
            "sv_carousel_next", label = NULL,
            icon  = shiny::icon("chevron-right"),
            style = paste0(
              "background:#0D2A44; border:1px solid #1D4E6D; color:#7FB3D3; ",
              "width:44px; height:44px; border-radius:50%; padding:0; font-size:18px; ",
              "display:flex; align-items:center; justify-content:center;"
            )
          )
        )
      ),
      
      # Pastilles de navigation + label mois courant
      shiny::div(
        style = "text-align:center; margin-top:10px;",
        shiny::div(do.call(shiny::tagList, dots)),
        shiny::div(
          style = "font-size:12px; color:#E8870A; font-weight:600; margin-top:6px;",
          mois_label(m_cur)
        )
      )
    )
  })
  
  # Navigation par clic sur pastille
  shiny::observeEvent(input$sv_carousel_goto, {
    mois <- rv_maps$mois_list
    idx  <- as.integer(input$sv_carousel_goto)
    if (length(mois) > 0 && idx >= 1L && idx <= length(mois))
      rv_maps$mois_index <- idx
  })
  
  # ── Calcul lourd — déclenché par "Générer les cartes" ──────────────────────
  # Ne fait QUE le calcul + écriture dans rv_maps. Aucun renderPlot ici.
  shiny::observeEvent(input$sv_generate_maps, {
    shiny::req(input$sv_generate_maps > 0)
    
    mois   <- tryCatch(sv_mois_dispo(),     error = function(e) integer(0))
    navire <- input$sv_sel_navire %||% ""
    annee  <- tryCatch(sv_annee_courante(), error = function(e) NA_integer_)
    
    shiny::req(length(mois) > 0, nzchar(navire))
    
    show_raster <- isTRUE(input$sv_show_raster)
    show_grid   <- isTRUE(input$sv_show_grid)
    
    df_nav  <- tryCatch(sv_data_navire(),   error = function(e) NULL)
    sf_rect <- tryCatch(sv_sf_rect_prep(), error = function(e) NULL)
    asm     <- if (show_raster) tryCatch(sv_assemblage(), error = function(e) NULL) else NULL
    
    # ── LOG DIAGNOSTIC GLOBAL ─────────────────────────────────────────────
    message(sprintf("[GEN] show_raster=%s | asm=%s (%d cartes) | RASTER_DIR=%s",
                    show_raster,
                    if (is.null(asm)) "NULL" else "OK",
                    if (is.null(asm)) 0L else nrow(asm),
                    RASTER_DIR))
    message(sprintf("[GEN] Rasters .tif dans RASTER_DIR : %d fichier(s)",
                    length(list.files(RASTER_DIR, pattern = "\\.tif$", ignore.case = TRUE))))
    # ─────────────────────────────────────────────────────────────────────
    
    shiny::req(!is.null(df_nav), !is.null(sf_rect))
    
    reset_raster_cache()
    rv_maps$plots_data    <- list()
    rv_maps$navire_genere <- navire
    rv_maps$annee_generee <- annee
    
    tous_mois <- 1:12
    n <- 12L
    shiny::withProgress(message = "G\u00e9n\u00e9ration des cartes...", value = 0, {
      for (i in seq_along(tous_mois)) {
        m_num <- tous_mois[i]
        shiny::incProgress(1 / n, detail = paste0(mois_label(m_num), " (", i, "/", n, ")"))
        
        df_m    <- df_nav[!is.na(df_nav$mois) & df_nav$mois == m_num, ]
        crossed <- tryCatch(
          cross_vms_rectangles(df_m, sf_rect),
          error = function(e) list(on = sf_rect[0, ], context = sf_rect[0, ])
        )
        sf_on      <- crossed$on
        sf_context <- if (show_grid) crossed$context else NULL
        
        raster_shom <- NULL
        if (show_raster && !is.null(asm) && nrow(sf_on) > 0) {
          shom_info <- tryCatch(
            select_shom_maps(sf_on, asm, RASTER_DIR),
            error = function(e) {
              message(sprintf("[SHOM m=%02d] ERREUR select_shom_maps : %s", m_num, conditionMessage(e)))
              NULL
            }
          )
          # ── LOG DIAGNOSTIC PAR MOIS ───────────────────────────────────
          message(sprintf("[SHOM m=%02d] sf_on=%d rects | shom_info=%s | rasters=%s",
                          m_num,
                          nrow(sf_on),
                          if (is.null(shom_info)) "NULL"
                          else paste0("mode=", shom_info$mode),
                          if (is.null(shom_info) || length(shom_info$rasters) == 0) "aucun"
                          else paste(basename(shom_info$rasters), collapse = ", ")))
          # ─────────────────────────────────────────────────────────────
          if (!is.null(shom_info) && length(shom_info$rasters) > 0) {
            raster_shom <- load_and_mosaic_rasters(shom_info$rasters)
            message(sprintf("[SHOM m=%02d] raster_shom apres load : %s",
                            m_num,
                            if (is.null(raster_shom)) "NULL"
                            else paste0(length(raster_shom), " tuile(s) chargee(s)")))
          }
        } else {
          message(sprintf("[SHOM m=%02d] SKIP — show_raster=%s | asm=%s | sf_on=%d",
                          m_num, show_raster,
                          if (is.null(asm)) "NULL" else "OK",
                          nrow(sf_on)))
        }
        
        # Écriture clé par clé → chaque renderPlot se réveille dès que son mois est prêt
        rv_maps$plots_data[[as.character(m_num)]] <- list(
          sf_on       = sf_on,
          sf_context  = sf_context,
          raster_shom = raster_shom   # liste de SpatRaster pleine résolution (ou NULL)
        )
      }
      # Carousel sur les 12 mois (mois sans data = carte vide)
      rv_maps$mois_list  <- tous_mois
      rv_maps$mois_index <- 1L
    })
  })
  
  # ===========================================================================
  # 10. EXPORTS
  # ===========================================================================
  
  # ── Export PNG — une image par mois, zippées ──────────────────────────────
  output$sv_export_png_zip <- shiny::downloadHandler(
    filename = function() {
      paste0("VMS_cartes_", input$sv_sel_navire, "_", sv_annee_courante(), ".zip")
    },
    content = function(file) {
      mois        <- sv_mois_dispo()
      navire      <- input$sv_sel_navire
      annee       <- sv_annee_courante()
      
      # Réutilise le cache seulement si généré pour le même navire/année
      cache_valide <- !is.null(rv_maps$navire_genere) &&
        identical(rv_maps$navire_genere, navire) &&
        identical(rv_maps$annee_generee, annee)
      cached_data <- if (cache_valide) rv_maps$plots_data else list()
      
      # Fallback : recalcul complet si les cartes n'ont pas encore été générées
      # ou si le cache correspond à un autre navire
      if (length(cached_data) == 0) {
        df         <- sv_data_navire()
        sf_rect    <- sv_sf_rect()
        assemblage <- sv_assemblage()
        show_raster <- isTRUE(input$sv_show_raster)
      }
      
      tmp_dir <- tempfile()
      dir.create(tmp_dir)
      
      shiny::withProgress(message = "Export PNG en cours...", value = 0, {
        for (i in seq_along(mois)) {
          m_num <- mois[i]
          shiny::incProgress(1 / length(mois), detail = mois_label(m_num))
          
          key  <- as.character(m_num)
          data <- cached_data[[key]]
          
          if (!is.null(data)) {
            sf_on       <- data$sf_on
            sf_context  <- data$sf_context
            raster_shom <- data$raster_shom   # pleine résolution, déjà chargé
          } else {
            # Fallback : recalcul à la demande
            df_m    <- df[!is.na(df$mois) & df$mois == m_num, ]
            crossed <- cross_vms_rectangles(df_m, sf_rect)
            sf_on       <- crossed$on
            sf_context  <- crossed$context
            raster_shom <- NULL
            if (show_raster && !is.null(assemblage) && nrow(sf_on) > 0) {
              shom_info <- tryCatch(
                select_shom_maps(sf_on, assemblage, RASTER_DIR),
                error = function(e) NULL
              )
              if (!is.null(shom_info) && length(shom_info$rasters) > 0)
                raster_shom <- load_and_mosaic_rasters(shom_info$rasters)
            }
          }
          
          # ── Paramètres qualité selon le choix utilisateur ────────────────
          qual <- tryCatch(input$sv_export_quality, error = function(e) "mid")
          if (is.null(qual) || !qual %in% c("low", "mid", "high")) qual <- "mid"
          qual_params <- list(
            low  = list(dpi = 150, ds = 1200, w = 24, h = 18),  # ~1417×1063 px, ~1-2 min
            mid  = list(dpi = 200, ds = 2500, w = 28, h = 21),  # ~2205×1654 px, ~5-8 min
            high = list(dpi = 300, ds = 4000, w = 32, h = 24)   # ~3780×2835 px, ~15-25 min
          )[[qual]]
          
          p <- make_vms_map(
            sf_rect_on      = sf_on,
            sf_rect_context = sf_context,
            raster_shom     = raster_shom,
            navire          = navire,
            mois_num        = m_num,
            annee           = annee,
            downsample_px   = qual_params$ds
          )
          
          png_path <- file.path(tmp_dir, sprintf("%s_%s_%02d.png", navire, annee, m_num))
          if (requireNamespace("ragg", quietly = TRUE)) {
            ragg::agg_png(png_path,
                          width = qual_params$w, height = qual_params$h,
                          units = "cm", res = qual_params$dpi, background = "white")
          } else {
            grDevices::png(png_path,
                           width = qual_params$w, height = qual_params$h,
                           units = "cm", res = qual_params$dpi, bg = "white")
          }
          print(p)
          grDevices::dev.off()
        }
      })
      
      zip::zipr(file, files = list.files(tmp_dir, full.names = TRUE), recurse = FALSE)
    }
  )
  
  # ── Export SHP — un seul shapefile consolidé, colonne "mois" ──────────────
  #    Contient UNIQUEMENT les rectangles actifs (avec points VMS),
  #    tous mois confondus, avec la colonne "mois" pour distinguer les périodes.
  output$sv_export_shp_zip <- shiny::downloadHandler(
    filename = function() {
      paste0("VMS_shapefiles_", input$sv_sel_navire, "_", sv_annee_courante(), ".zip")
    },
    content = function(file) {
      df      <- sv_data_navire()
      sf_rect <- sv_sf_rect()
      navire  <- input$sv_sel_navire
      annee   <- sv_annee_courante()
      
      tmp_dir <- tempfile()
      dir.create(tmp_dir)
      
      shiny::withProgress(message = "Construction du shapefile...", value = 0.2, {
        
        # Construit le SHP consolidé (tous mois, rectangles actifs seulement)
        sf_all <- tryCatch(
          build_export_shp(df, sf_rect),
          error = function(e) NULL
        )
        
        shiny::incProgress(0.6, detail = "Écriture du shapefile...")
        
        if (!is.null(sf_all) && nrow(sf_all) > 0) {
          shp_name <- sprintf("%s_%s_rectangles_actifs.shp", navire, annee)
          shp_path <- file.path(tmp_dir, shp_name)
          sf::st_write(sf_all, shp_path, quiet = TRUE, delete_dsn = TRUE)
        }
      })
      
      # Zipper tous les fichiers composants du shapefile
      shp_files <- list.files(tmp_dir, full.names = TRUE,
                              pattern = "\\.(shp|dbf|shx|prj|cpg)$")
      if (length(shp_files) == 0) {
        # Fichier vide pour éviter une erreur de téléchargement
        writeLines("Aucun rectangle actif trouvé.", file.path(tmp_dir, "vide.txt"))
        shp_files <- list.files(tmp_dir, full.names = TRUE)
      }
      zip::zipr(file, files = shp_files, recurse = FALSE)
    }
  )
  
}