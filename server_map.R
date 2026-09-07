# =============================================================================
# server_map.R — Serveur onglet Cartographie
# Exploite functions_map.R et functions_data.R (charger_fichier_data)
# =============================================================================

server_map <- function(input, output, session, rv) {
  
  # Fallback au cas où functions_data.R n'est pas encore sourcé
  if (!exists("label_variable", mode = "function")) {
    label_variable <- function(x) x
  }
  # Note : charger_fichier_data() est défini dans functions_data.R et gère
  # le forçage character (stat_rect, codes…). Pas de fallback ici pour
  # garantir que la version complète est toujours utilisée.
  
  rv_map <- shiny::reactiveValues(
    data             = NULL,   # dataframe source (import ou données app)
    sf_rect          = NULL,   # shapefile rectangles stat (chargé une fois)
    sf_ciem          = NULL,   # shapefile divisions CIEM (chargé une fois)
    sf_custom        = NULL,   # shapefile importé par l'utilisateur
    geo_mode         = NULL,   # mode géo détecté
    col_sf_zone      = NULL,   # colonne de jointure active dans le sf (pour labels)
    pts_mode         = FALSE,  # TRUE quand mode "Points seuls" (pas de shapefile)
    ctx_layers_info  = NULL,   # data.frame des couches de contexte détectées
    ctx_layers_sf    = list()  # cache sf des couches chargées (named list par id)
  )
  
  
  # ===========================================================================
  # 0. CHARGEMENT SHAPEFILES ICES (une seule fois au démarrage)
  # ===========================================================================
  
  shiny::observe({
    if (is.null(rv_map$sf_rect)) {
      rv_map$sf_rect <- charger_shapefile("stat_rect")
      if (is.null(rv_map$sf_rect))
        shiny::showNotification(
          "Shapefile stat_rect introuvable dans www/shapefile/rect_stat/",
          type = "warning", duration = 5)
    }
    if (is.null(rv_map$sf_ciem)) {
      rv_map$sf_ciem <- charger_shapefile("div_ciem")
      if (is.null(rv_map$sf_ciem))
        shiny::showNotification(
          "Shapefile div_ciem introuvable dans www/shapefile/zone_ciem/",
          type = "warning", duration = 5)
    }
  }) |> shiny::bindEvent(TRUE, once = TRUE)
  
  
  # ===========================================================================
  # 0b. DÉTECTION DES COUCHES DE CONTEXTE (une seule fois au démarrage)
  # ===========================================================================
  
  shiny::observe({
    rv_map$ctx_layers_info <- detecter_couches_contexte(
      file.path("www", "shapefile", "mapping")
    )
    n <- nrow(rv_map$ctx_layers_info)
    if (n > 0) {
      message(sprintf("[server_map] %d couche(s) de contexte détectée(s) : %s",
                      n, paste(rv_map$ctx_layers_info$id, collapse = ", ")))
    } else {
      message("[server_map] Aucune couche de contexte dans www/shapefile/mapping/")
    }
  }) |> shiny::bindEvent(TRUE, once = TRUE)
  
  
  # ===========================================================================
  # 1. SOURCE DE DONNÉES (composant partagé)
  # ===========================================================================
  
  df_source <- app_source_server(
    input    = input,
    output   = output,
    session  = session,
    input_id = "map",
    rv       = rv
  )
  
  
  # ===========================================================================
  # 1b. UI COUCHES DE CONTEXTE — checkboxes dynamiques
  # ===========================================================================
  
  output$map_context_layers_ui <- shiny::renderUI({
    
    info <- rv_map$ctx_layers_info
    
    # Cas : dossier vide ou absent
    if (is.null(info) || nrow(info) == 0) {
      return(shiny::div(
        class = "ctx-empty-msg",
        shiny::icon("exclamation-circle"),
        " Aucun shapefile détecté dans le dossier de mapping."
      ))
    }
    
    # Construction des lignes checkbox avec pastille couleur
    rows <- lapply(seq_len(nrow(info)), function(i) {
      row   <- info[i, ]
      color <- couleur_contexte_leaflet(row$idx)
      
      # Pastille visuelle : carré pour polygone, trait pour ligne
      dot_el <- if (row$type == "line") {
        shiny::tags$div(
          class = "ctx-color-line",
          style = paste0("background:", color, ";")
        )
      } else {
        shiny::tags$div(
          class = "ctx-color-dot",
          style = paste0("background:", color, ";")
        )
      }
      
      shiny::div(
        class = "ctx-layer-row",
        dot_el,
        shiny::checkboxInput(
          inputId = paste0("map_ctx_", row$id),
          label   = row$label,
          value   = FALSE
        )
      )
    })
    
    shiny::tagList(rows)
  })
  
  
  # ── Reactive : ids des couches actuellement cochées ────────────────────────
  ctx_active_ids <- shiny::reactive({
    info <- rv_map$ctx_layers_info
    if (is.null(info) || nrow(info) == 0) return(character(0))
    
    active <- vapply(info$id, function(id) {
      val <- input[[paste0("map_ctx_", id)]]
      isTRUE(val)
    }, logical(1))
    
    info$id[active]
  })
  
  shiny::observeEvent(input$map_charger_shp_btn, {
    
    fi_shp <- input$map_shp_fichier
    if (is.null(fi_shp)) {
      shiny::showNotification(
        shiny::tagList(shiny::icon("exclamation-triangle"),
                       " Sélectionnez d'abord un shapefile (.shp, .geojson, .gpkg, .zip)."),
        type = "warning", duration = 4)
      return()
    }
    
    path <- fi_shp$datapath
    ext  <- tolower(tools::file_ext(fi_shp$name))
    
    if (ext == "zip") {
      tmp_dir <- tempfile()
      dir.create(tmp_dir)
      tryCatch(
        utils::unzip(path, exdir = tmp_dir),
        error = function(e) {
          shiny::showNotification(
            paste("Impossible de décompresser le zip :", e$message),
            type = "error", duration = 8)
          return()
        }
      )
      shp_files <- list.files(tmp_dir, pattern = "\\.shp$",
                              recursive = TRUE, full.names = TRUE)
      if (length(shp_files) == 0) {
        shiny::showNotification(
          "Aucun fichier .shp trouvé dans l'archive ZIP.",
          type = "error", duration = 6)
        return()
      }
      path <- shp_files[1]
    }
    
    shiny::withProgress(message = "Chargement du shapefile…", value = 0.5, {
      sf_obj <- charger_shapefile_custom(path)
    })
    
    if (!is.null(sf_obj)) {
      rv_map$sf_custom <- sf_obj
      n_col <- ncol(sf_obj) - 1L
      shiny::showNotification(
        shiny::tagList(
          shiny::icon("check-circle"), " ",
          shiny::strong(fi_shp$name), shiny::br(),
          shiny::span(style = "font-size:11px;",
                      sprintf("%s zones · %s attributs", nrow(sf_obj), n_col))
        ),
        type = "message", duration = 5)
    } else {
      shiny::showNotification(
        "Échec du chargement du shapefile. Vérifiez le fichier.",
        type = "error", duration = 7)
    }
  })
  
  # ── Auto-switch geo_mode vers latlon quand shapefile = "none" ───────────────
  shiny::observeEvent(input$map_shapefile, {
    if (!is.null(input$map_shapefile) && input$map_shapefile == "none") {
      shiny::updateSelectInput(session, "map_geo_mode", selected = "latlon")
    }
  })
  
  
  # ===========================================================================
  # 2b. UI PERSONNALISATION POINTS (mode "none")
  # ===========================================================================
  
  output$map_pts_color_ui <- shiny::renderUI({
    df <- df_source()
    if (is.null(df)) return(NULL)
    cols_all <- c("— Aucune —" = "", names(df))
    shiny::div(class = "map-param-block",
               shiny::tags$label(class = "map-param-label",
                                 "Variable couleur des points"),
               shiny::selectInput("map_pts_color_col", label = NULL,
                                  choices  = cols_all,
                                  selected = ""))
  })
  
  output$map_pts_size_col_ui <- shiny::renderUI({
    df <- df_source()
    if (is.null(df)) return(NULL)
    num_cols <- c("— Taille fixe —" = "",
                  names(df)[sapply(df, is.numeric)])
    shiny::div(class = "map-param-block",
               shiny::tags$label(class = "map-param-label",
                                 "Variable taille des points (optionnel)"),
               shiny::selectInput("map_pts_size_col", label = NULL,
                                  choices  = num_cols,
                                  selected = ""))
  })
  
  
  output$map_shp_status <- shiny::renderUI({
    shiny::req(input$map_shapefile == "custom")
    if (is.null(rv_map$sf_custom)) {
      shiny::div(class = "map-shp-status err",
                 shiny::icon("times-circle"), " Aucun shapefile chargé.")
    } else {
      shiny::div(class = "map-shp-status ok",
                 shiny::icon("check-circle"),
                 sprintf(" %s zones — %s attributs",
                         nrow(rv_map$sf_custom),
                         ncol(rv_map$sf_custom) - 1L))
    }
  })
  
  output$map_shp_col_join_ui <- shiny::renderUI({
    shiny::req(input$map_shapefile == "custom", rv_map$sf_custom)
    cols_shp <- setdiff(names(rv_map$sf_custom), "geometry")
    shiny::div(class = "map-param-block", style = "margin-top:8px;",
               shiny::tags$label(class = "map-param-label",
                                 "Colonne de jointure dans le shapefile"),
               shiny::selectInput("map_shp_col_join", label = NULL,
                                  choices  = cols_shp,
                                  selected = cols_shp[1]))
  })
  
  output$map_shp_col_data_ui <- shiny::renderUI({
    shiny::req(input$map_shapefile == "custom", rv_map$sf_custom)
    df <- df_source()
    shiny::req(df)
    cols_df <- names(df)
    shiny::div(class = "map-param-block",
               shiny::tags$label(class = "map-param-label",
                                 "Colonne de jointure dans les données"),
               shiny::selectInput("map_shp_col_data", label = NULL,
                                  choices  = cols_df,
                                  selected = cols_df[1]))
  })
  
  
  # ===========================================================================
  # 3. INFO FICHIER + BADGE GÉODÉTECTION
  # ===========================================================================
  
  shiny::observe({
    df <- df_source()
    if (is.null(df)) return()
    mode <- detecter_mode_geo(df)
    rv_map$geo_mode <- mode
    if (mode != "inconnu")
      shiny::updateSelectInput(session, "map_geo_mode", selected = mode)
  })
  
  output$map_geo_badge <- shiny::renderUI({
    mode <- rv_map$geo_mode %||% "inconnu"
    label <- switch(mode,
                    "rect_stat" = "Rectangles ICES",
                    "div_ciem"  = "Divisions CIEM",
                    "latlon"    = "Lat / Lon",
                    "Auto-détection en cours…")
    shiny::tags$span(class = "map-geo-badge",
                     shiny::icon("magic"), " ", label)
  })
  
  
  # ===========================================================================
  # 4. UI COLONNES GÉOGRAPHIQUES
  # ===========================================================================
  
  output$map_geo_colonnes <- shiny::renderUI({
    df   <- df_source()
    mode <- input$map_geo_mode %||% "rect_stat"
    if (is.null(df)) return(NULL)
    
    noms <- names(df)
    geo  <- colonnes_geo_probables(df, mode)
    
    if (mode == "latlon") {
      shiny::tagList(
        shiny::div(class = "map-param-block",
                   shiny::tags$label(class = "map-param-label", "Colonne Latitude"),
                   shiny::selectInput("map_col_lat", label = NULL,
                                      choices = noms, selected = geo$lat)),
        shiny::div(class = "map-param-block",
                   shiny::tags$label(class = "map-param-label", "Colonne Longitude"),
                   shiny::selectInput("map_col_lon", label = NULL,
                                      choices = noms, selected = geo$lon))
      )
    } else {
      shiny::div(class = "map-param-block",
                 shiny::tags$label(class = "map-param-label", "Colonne zone"),
                 shiny::selectInput("map_col_zone", label = NULL,
                                    choices = noms, selected = geo$zone))
    }
  })
  
  
  # ===========================================================================
  # 5. MISE À JOUR LISTE DES VARIABLES + FILTRE
  # ===========================================================================
  
  # ── Choix de la variable en fonction de la fonction d'agrégation ────────────
  # - "n"         → comptage simple, pas de colonne nécessaire → choix forcé à __n__
  # - "n_distinct" → toutes les colonnes (on veut souvent compter des id texte)
  # - autres      → colonne numérique (__n__ proposé également)
  shiny::observe({
    df      <- df_source()
    agg_fun <- input$map_agg_fun %||% "sum"
    if (is.null(df)) return()
    
    if (agg_fun == "n") {
      # Comptage pur : pas de colonne, on force __n__
      shiny::updateSelectInput(session, "map_var_value",
                               choices  = c("Comptage (n lignes)" = "__n__"),
                               selected = "__n__")
      return()
    }
    
    if (agg_fun == "n_distinct") {
      # Toutes les colonnes disponibles (id bateau, port, espèce…)
      all_cols <- names(df)
      choices  <- stats::setNames(all_cols, sapply(all_cols, label_variable))
      shiny::updateSelectInput(session, "map_var_value",
                               choices  = choices,
                               selected = choices[1])
      return()
    }
    
    # Fonctions numériques classiques
    num_cols <- names(df)[sapply(df, is.numeric)]
    if (length(num_cols) == 0) {
      shiny::updateSelectInput(session, "map_var_value",
                               choices  = c("Comptage (n lignes)" = "__n__"),
                               selected = "__n__")
      return()
    }
    choices <- c("Comptage (n lignes)" = "__n__",
                 stats::setNames(num_cols, sapply(num_cols, label_variable)))
    shiny::updateSelectInput(session, "map_var_value",
                             choices  = choices,
                             selected = choices[2])
    
  }) |> shiny::bindEvent(df_source(), input$map_agg_fun, ignoreInit = FALSE)
  
  
  # ── UI filtre (colonne catégorielle optionnelle) ────────────────────────────
  output$map_filtre_ui <- shiny::renderUI({
    df <- df_source()
    if (is.null(df)) return(
      shiny::p(style = "font-size:11px; color:#7FB3D3; font-style:italic; margin:4px 0;",
               "Chargez des données pour activer le filtre.")
    )
    cat_cols <- c("— Aucun —" = "",
                  names(df)[sapply(df, function(x) is.character(x) | is.factor(x))])
    shiny::tagList(
      shiny::div(class = "map-param-block",
                 shiny::tags$label(class = "map-param-label", "Variable filtre"),
                 shiny::selectInput("map_filtre_col", label = NULL, choices = cat_cols)
      ),
      shiny::conditionalPanel(
        condition = "input.map_filtre_col !== ''",
        shiny::uiOutput("map_filtre_vals")
      )
    )
  })
  
  output$map_filtre_vals <- shiny::renderUI({
    df  <- df_source()
    col <- input$map_filtre_col
    shiny::req(df, col, nchar(col) > 0)
    vals <- sort(unique(as.character(df[[col]])))
    shiny::selectizeInput("map_filtre_valeurs", "Valeur(s)",
                          choices  = vals,
                          multiple = TRUE,
                          selected = vals[1])
  })
  
  
  # ===========================================================================
  # 6. DONNÉES AGRÉGÉES — reactive cœur
  # ===========================================================================
  
  sf_data_agg <- shiny::eventReactive(input$map_refresh, {
    df   <- df_source()
    mode <- input$map_geo_mode %||% "rect_stat"
    shiny::req(df)
    
    # ── Filtre optionnel ──────────────────────────────────────────────────────
    col_filtre <- input$map_filtre_col %||% ""
    if (nchar(col_filtre) > 0 &&
        !is.null(input$map_filtre_valeurs) &&
        length(input$map_filtre_valeurs) > 0) {
      df <- df[df[[col_filtre]] %in% input$map_filtre_valeurs, ]
    }
    
    # ── Shapefile actif ───────────────────────────────────────────────────────
    shp_choix <- input$map_shapefile %||% "stat_rect"
    
    # ── MODE POINTS PURS : pas de jointure shapefile ──────────────────────────
    if (shp_choix == "none") {
      shiny::req(mode == "latlon",
                 cancelOutput = TRUE)
      col_lat <- input$map_col_lat
      col_lon <- input$map_col_lon
      shiny::req(col_lat, col_lon)
      
      df_valid <- df[!is.na(df[[col_lat]]) & !is.na(df[[col_lon]]), ]
      if (nrow(df_valid) == 0) {
        shiny::showNotification(
          "Aucune coordonnée valide dans les colonnes sélectionnées.",
          type = "error", duration = 6)
        return(NULL)
      }
      
      sf_pts <- tryCatch(
        sf::st_as_sf(df_valid, coords = c(col_lon, col_lat), crs = 4326),
        error = function(e) {
          shiny::showNotification(
            paste("Erreur conversion lat/lon :", e$message),
            type = "error", duration = 6)
          NULL
        }
      )
      shiny::req(sf_pts)
      
      shiny::showNotification(
        shiny::tagList(
          shiny::icon("check-circle"), " ",
          shiny::strong(format(nrow(sf_pts), big.mark = "\u202f")),
          " points tracés"
        ),
        type = "message", duration = 4)
      
      rv_map$pts_mode    <- TRUE
      rv_map$col_sf_zone <- NULL
      return(sf_pts)
    }
    
    # Mode normal (avec shapefile) ─────────────────────────────────────────────
    rv_map$pts_mode <- FALSE
    
    if (shp_choix == "custom") {
      sf_zones <- rv_map$sf_custom
      if (is.null(sf_zones)) {
        shiny::showNotification(
          shiny::tagList(shiny::icon("exclamation-triangle"),
                         " Importez d'abord un shapefile personnalisé."),
          type = "error", duration = 5)
        return(NULL)
      }
      col_sf_zone <- input$map_shp_col_join %||% names(sf_zones)[1]
      col_zone_df <- input$map_shp_col_data %||% names(df)[1]
      
    } else {
      sf_zones    <- if (shp_choix == "stat_rect") rv_map$sf_rect else rv_map$sf_ciem
      if (is.null(sf_zones)) {
        shiny::showNotification("Shapefile non chargé.", type = "error")
        return(NULL)
      }
      col_sf_zone <- col_jointure_shp(shp_choix)
      col_zone_df <- input$map_col_zone
    }
    
    # ── Variable valeur ───────────────────────────────────────────────────────
    # Pour "n" : col_val = NULL (comptage pur, pas de colonne nécessaire)
    # Pour "n_distinct" : col_val = colonne choisie
    # Pour les autres : col_val = colonne choisie (NULL si __n__ sélectionné)
    agg_fun_sel <- input$map_agg_fun %||% "sum"
    
    col_val <- if (agg_fun_sel == "n") {
      NULL
    } else if (!is.null(input$map_var_value) && input$map_var_value == "__n__") {
      NULL  # l'utilisateur a quand même choisi "Comptage" manuellement
    } else {
      input$map_var_value
    }
    
    # Forcer agg_fun à "n" si aucune colonne valeur
    agg_fun_eff <- if (is.null(col_val)) "n" else agg_fun_sel
    
    # ── Agrégation selon mode ─────────────────────────────────────────────────
    if (mode == "latlon") {
      col_lat <- input$map_col_lat
      col_lon <- input$map_col_lon
      shiny::req(col_lat, col_lon)
      result <- agreger_par_zone(
        df          = df,
        sf_zones    = sf_zones,
        col_sf_zone = col_sf_zone,
        col_valeur  = col_val,
        agg_fun     = agg_fun_eff,
        col_lat     = col_lat,
        col_lon     = col_lon
      )
    } else {
      shiny::req(col_zone_df)
      result <- agreger_par_zone(
        df          = df,
        sf_zones    = sf_zones,
        col_zone    = col_zone_df,
        col_sf_zone = col_sf_zone,
        col_valeur  = col_val,
        agg_fun     = agg_fun_eff
      )
    }
    
    if (is.null(result)) {
      shiny::showNotification(
        "Échec de la jointure spatiale. Vérifiez les colonnes de jointure.",
        type = "error", duration = 6)
      return(NULL)
    }
    
    rv_map$col_sf_zone <- col_sf_zone
    result
  })
  
  
  # ===========================================================================
  # 7. KPI
  # ===========================================================================
  
  output$map_kpi <- shiny::renderUI({
    sf_d <- sf_data_agg()
    if (is.null(sf_d)) return(NULL)
    
    fmt <- function(x) format(round(x, 1), big.mark = "\u202f")
    
    # ── Mode points purs ──────────────────────────────────────────────────────
    if (isTRUE(rv_map$pts_mode)) {
      n_pts     <- nrow(sf_d)
      col_color <- shiny::isolate(input$map_pts_color_col) %||% ""
      
      if (nchar(col_color) > 0 && col_color %in% names(sf_d)) {
        vals <- sf_d[[col_color]]
        if (is.numeric(vals)) {
          vals_ok <- vals[!is.na(vals)]
          return(shiny::fluidRow(
            shiny::column(3, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val",
                                                   format(n_pts, big.mark = "\u202f")),
                                        shiny::div(class = "hal-kpi-lbl", "Points tracés"))),
            shiny::column(3, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val", fmt(sum(vals_ok))),
                                        shiny::div(class = "hal-kpi-lbl", paste("Total", col_color)))),
            shiny::column(3, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val", fmt(mean(vals_ok))),
                                        shiny::div(class = "hal-kpi-lbl", "Moyenne"))),
            shiny::column(3, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val", fmt(max(vals_ok))),
                                        shiny::div(class = "hal-kpi-lbl", "Maximum")))
          ))
        } else {
          n_cat <- length(unique(vals[!is.na(vals)]))
          return(shiny::fluidRow(
            shiny::column(6, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val",
                                                   format(n_pts, big.mark = "\u202f")),
                                        shiny::div(class = "hal-kpi-lbl", "Points tracés"))),
            shiny::column(6, shiny::div(class = "hal-kpi",
                                        shiny::div(class = "hal-kpi-val", n_cat),
                                        shiny::div(class = "hal-kpi-lbl",
                                                   paste("Catégories —", col_color))))
          ))
        }
      } else {
        return(shiny::fluidRow(
          shiny::column(4, shiny::div(class = "hal-kpi",
                                      shiny::div(class = "hal-kpi-val",
                                                 format(n_pts, big.mark = "\u202f")),
                                      shiny::div(class = "hal-kpi-lbl", "Points tracés")))
        ))
      }
    }
    
    # ── Mode zones (comportement original) ────────────────────────────────────
    if (!"valeur" %in% names(sf_d)) return(NULL)
    vals    <- sf_d$valeur
    vals_ok <- vals[!is.na(vals)]
    if (length(vals_ok) == 0) return(NULL)
    
    shiny::fluidRow(
      shiny::column(3, shiny::div(class = "hal-kpi",
                                  shiny::div(class = "hal-kpi-val", length(vals_ok)),
                                  shiny::div(class = "hal-kpi-lbl", "Zones avec données"))),
      shiny::column(3, shiny::div(class = "hal-kpi",
                                  shiny::div(class = "hal-kpi-val", fmt(sum(vals_ok))),
                                  shiny::div(class = "hal-kpi-lbl", "Total"))),
      shiny::column(3, shiny::div(class = "hal-kpi",
                                  shiny::div(class = "hal-kpi-val", fmt(mean(vals_ok))),
                                  shiny::div(class = "hal-kpi-lbl", "Moyenne / zone"))),
      shiny::column(3, shiny::div(class = "hal-kpi",
                                  shiny::div(class = "hal-kpi-val", fmt(max(vals_ok))),
                                  shiny::div(class = "hal-kpi-lbl", "Maximum")))
    )
  })
  
  
  # ===========================================================================
  # 8. BBOX ACTIVE — figée au clic sur map_refresh uniquement
  # ===========================================================================
  
  # bbox_active est une reactiveVal qui ne se met a jour QUE quand l'utilisateur
  # clique sur Generer la carte. Cela evite que chaque changement de preset /
  # coordonnee relance toute la chaine de rendu.
  bbox_active <- shiny::reactiveVal(NULL)
  
  .bbox_depuis_inputs <- function() {
    preset <- shiny::isolate(input$map_preset) %||% "bretagne"
    if (identical(preset, "custom")) {
      c(shiny::isolate(input$map_lon_min) %||% -5.5,
        shiny::isolate(input$map_lat_min) %||% 47.0,
        shiny::isolate(input$map_lon_max) %||%  -0.5,
        shiny::isolate(input$map_lat_max) %||%  49.5)
    } else {
      bbox_preset(preset)
    }
  }
  
  shiny::observeEvent(input$map_refresh, {
    bbox_active(.bbox_depuis_inputs())
  }, ignoreInit = TRUE)
  
  
  # ===========================================================================
  # 9. CARTE LEAFLET
  # ===========================================================================
  
  output$map_leaflet <- leaflet::renderLeaflet({
    sf_d <- sf_data_agg()          # seul declencheur reactif
    shiny::req(sf_d)
    shiny::isolate({
      # ── Construction carte de base ───────────────────────────────────────────
      m <- if (isTRUE(rv_map$pts_mode)) {
        construire_carte_leaflet_points(
          sf_pts        = sf_d,
          bbox          = bbox_active(),
          col_color     = input$map_pts_color_col %||% "",
          col_size      = input$map_pts_size_col  %||% "",
          pt_size       = input$map_pt_size       %||% 6,
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          alpha         = input$map_alpha         %||% 0.75,
          legende_titre = input$map_legende_titre %||% ""
        )
      } else {
        construire_carte_leaflet(
          sf_data       = sf_d,
          bbox          = bbox_active(),
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          alpha         = input$map_alpha         %||% 0.75,
          show_labels   = input$map_show_labels   %||% FALSE,
          col_label     = rv_map$col_sf_zone,
          agg_fun       = input$map_agg_fun       %||% "sum",
          legende_titre = input$map_legende_titre %||% ""
        )
      }
      
      # ── Injection des couches de contexte déjà cochées ───────────────────────
      active_ids <- ctx_active_ids()
      if (length(active_ids) > 0) {
        m <- injecter_couches_leaflet(
          m          = m,
          layers_info = rv_map$ctx_layers_info,
          active_ids  = active_ids
        )
      }
      
      m
    })
  })
  
  
  # ===========================================================================
  # 9b. MISE À JOUR LEAFLET VIA PROXY (ajout/retrait sans régénération)
  # Déclenché uniquement quand ctx_active_ids change ET qu'il y a déjà une carte
  # ===========================================================================
  
  # Snapshot précédent pour détecter les deltas (couches ajoutées / retirées)
  .prev_ctx_ids <- shiny::reactiveVal(character(0))
  
  shiny::observe({
    # Ne réagit qu'aux changements de couches cochées, pas au refresh carte
    active_now  <- ctx_active_ids()
    active_prev <- .prev_ctx_ids()
    
    added   <- setdiff(active_now,  active_prev)
    removed <- setdiff(active_prev, active_now)
    
    if (length(added) == 0 && length(removed) == 0) return()
    
    # Mettre à jour le snapshot
    .prev_ctx_ids(active_now)
    
    # Pas de carte encore générée → rien à proxier
    if (is.null(sf_data_agg())) return()
    
    info <- rv_map$ctx_layers_info
    if (is.null(info) || nrow(info) == 0) return()
    
    proxy <- leaflet::leafletProxy("map_leaflet")
    
    # ── Retrait des couches décochées ──────────────────────────────────────────
    for (id in removed) {
      group_name <- paste0("ctx_", id)
      legend_id  <- paste0("legend_ctx_", id)
      proxy <- proxy |>
        leaflet::clearGroup(group_name) |>
        leaflet::removeControl(legend_id)
    }
    
    # ── Ajout des couches nouvellement cochées ─────────────────────────────────
    if (length(added) > 0) {
      added_rows <- info[info$id %in% added, ]
      for (i in seq_len(nrow(added_rows))) {
        row   <- added_rows[i, ]
        sf_l  <- charger_couche_contexte(row$path)
        color <- couleur_contexte_leaflet(row$idx)
        
        proxy <- ajouter_couche_leaflet(
          m        = proxy,
          sf_layer = sf_l,
          layer_id = row$id,
          label    = row$label,
          type     = row$type,
          color    = color,
          idx      = row$idx
        )
      }
    }
    
  }) |> shiny::bindEvent(ctx_active_ids(), ignoreInit = TRUE)
  
  
  # ===========================================================================
  # 10. CARTE GGPLOT
  # ===========================================================================
  
  output$map_ggplot <- shiny::renderPlot({
    sf_d <- sf_data_agg()          # seul declencheur reactif
    shiny::req(sf_d)
    shiny::isolate({
      theme_nom <- input$map_gg_theme %||% "hal_dark"
      
      p <- if (isTRUE(rv_map$pts_mode)) {
        construire_carte_ggplot_points(
          sf_pts        = sf_d,
          bbox          = bbox_active(),
          col_color     = input$map_pts_color_col %||% "",
          col_size      = input$map_pts_size_col  %||% "",
          pt_size       = (input$map_pt_size      %||% 6) / 3,
          alpha         = input$map_alpha         %||% 0.75,
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          theme_nom     = theme_nom,
          titre         = input$map_gg_titre      %||% "",
          soustitre     = input$map_gg_soustitre  %||% "",
          caption       = input$map_gg_caption    %||% "",
          legende_titre = input$map_legende_titre %||% ""
        )
      } else {
        construire_carte_ggplot(
          sf_data       = sf_d,
          bbox          = bbox_active(),
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          alpha         = input$map_alpha         %||% 0.75,
          theme_nom     = theme_nom,
          titre         = input$map_gg_titre      %||% "",
          soustitre     = input$map_gg_soustitre  %||% "",
          caption       = input$map_gg_caption    %||% "",
          show_labels   = input$map_show_labels   %||% FALSE,
          label_size    = input$map_gg_label_size %||% 3,
          show_borders  = input$map_gg_borders    %||% TRUE,
          col_label     = rv_map$col_sf_zone,
          agg_fun       = input$map_agg_fun       %||% "sum",
          legende_titre = input$map_legende_titre %||% ""
        )
      }
      
      # Injection couches de contexte
      p <- injecter_couches_ggplot(
        p           = p,
        layers_info = rv_map$ctx_layers_info,
        active_ids  = ctx_active_ids(),
        theme_nom   = theme_nom
      )
      
      p
    })
  }, bg = "transparent")
  
  # ===========================================================================
  # PUSH COMPOSITION — capture le ggplot carte après chaque rendu (map_refresh)
  # ===========================================================================
  shiny::observeEvent(input$map_refresh, {
    push <- session$userData$compo_push
    if (!is.function(push)) return()
    
    sf_d <- tryCatch(sf_data_agg(), error = function(e) NULL)
    if (is.null(sf_d)) return()
    
    gg <- tryCatch(.build_ggplot_export(sf_d), error = function(e) NULL)
    if (is.null(gg)) return()
    
    titre_carte <- input$map_gg_titre %||% ""
    lbl <- paste0(
      "Carte",
      if (nzchar(titre_carte)) paste0(" \u2014 ", titre_carte)
      else paste0(" \u2014 ", format(Sys.time(), "%H:%M"))
    )
    push(plot_gg = gg, label = lbl, source = "map")
  }, ignoreInit = TRUE)
  
  
  # ===========================================================================
  # 11. APERÇU FICHIER IMPORTÉ
  # ===========================================================================
  
  output$map_table_preview <- DT::renderDataTable({
    df <- df_source()
    shiny::req(df)
    n_max <- input$map_nrows_preview %||% 200
    DT::datatable(
      head(df, n_max),
      options  = list(pageLength = 25, scrollX = TRUE),
      rownames = FALSE
    )
  })
  
  
  # ===========================================================================
  # 12. TABLEAU AGRÉGÉ
  # ===========================================================================
  
  output$map_table_agg <- DT::renderDataTable({
    sf_d <- sf_data_agg()
    shiny::req(sf_d)
    df_tbl <- sf::st_drop_geometry(sf_d)
    df_tbl <- df_tbl[!is.na(df_tbl$valeur), ]
    df_tbl <- df_tbl[order(-df_tbl$valeur), ]
    DT::datatable(df_tbl,
                  options  = list(pageLength = 20, scrollX = TRUE),
                  rownames = FALSE)
  })
  
  
  # ===========================================================================
  # 13. CODE R ÉQUIVALENT
  # ===========================================================================
  
  output$map_code_r <- shiny::renderText({
    sf_data_agg()                  # declencheur : uniquement apres refresh
    shiny::isolate({
      shp_nom  <- input$map_shapefile %||% "stat_rect"
      col_z    <- input$map_col_zone  %||% "col_zone"
      col_v    <- input$map_var_value %||% "valeur"
      agg_fun  <- input$map_agg_fun   %||% "sum"
      col_v_eff <- if (col_v == "__n__" || agg_fun == "n") NULL else col_v
      generer_code_r_map(
        shapefile_nom = shp_nom,
        col_zone      = col_z,
        col_valeur    = col_v_eff,
        agg_fun       = agg_fun,
        palette_nom   = input$map_palette    %||% "hal",
        theme_nom     = input$map_gg_theme   %||% "hal_dark",
        bbox          = bbox_active(),
        titre         = input$map_gg_titre   %||% "",
        caption       = input$map_gg_caption %||% ""
      )
    })
  })
  
  
  # ===========================================================================
  # 14. EXPORTS
  # ===========================================================================
  
  # Helper interne pour construire le plot ggplot selon le mode actif
  # Inclut les couches de contexte actives au moment de l'appel.
  .build_ggplot_export <- function(sf_d) {
    theme_nom <- input$map_gg_theme %||% "hal_dark"
    
    p <- if (isTRUE(rv_map$pts_mode)) {
      construire_carte_ggplot_points(
        sf_pts        = sf_d,
        bbox          = bbox_active(),
        col_color     = input$map_pts_color_col %||% "",
        col_size      = input$map_pts_size_col  %||% "",
        pt_size       = (input$map_pt_size      %||% 6) / 3,
        alpha         = input$map_alpha         %||% 0.75,
        palette_nom   = input$map_palette       %||% "hal",
        reverse_pal   = input$map_reverse_pal   %||% FALSE,
        theme_nom     = theme_nom,
        titre         = input$map_gg_titre      %||% "",
        soustitre     = input$map_gg_soustitre  %||% "",
        caption       = input$map_gg_caption    %||% "",
        legende_titre = input$map_legende_titre %||% ""
      )
    } else {
      construire_carte_ggplot(
        sf_data       = sf_d,
        bbox          = bbox_active(),
        palette_nom   = input$map_palette       %||% "hal",
        reverse_pal   = input$map_reverse_pal   %||% FALSE,
        alpha         = input$map_alpha         %||% 0.75,
        theme_nom     = theme_nom,
        titre         = input$map_gg_titre      %||% "",
        soustitre     = input$map_gg_soustitre  %||% "",
        caption       = input$map_gg_caption    %||% "",
        show_labels   = input$map_show_labels   %||% FALSE,
        label_size    = input$map_gg_label_size %||% 3,
        show_borders  = input$map_gg_borders    %||% TRUE,
        col_label     = rv_map$col_sf_zone,
        agg_fun       = input$map_agg_fun       %||% "sum",
        legende_titre = input$map_legende_titre %||% ""
      )
    }
    
    # Injection couches de contexte dans l'export
    p <- injecter_couches_ggplot(
      p           = p,
      layers_info = rv_map$ctx_layers_info,
      active_ids  = shiny::isolate(ctx_active_ids()),
      theme_nom   = theme_nom
    )
    
    p
  }
  
  # ── HTML (leaflet) ──────────────────────────────────────────────────────────
  output$map_export_html <- shiny::downloadHandler(
    filename = function() paste0("carte_", format(Sys.Date(), "%Y%m%d"), ".html"),
    content  = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      
      m <- if (isTRUE(rv_map$pts_mode)) {
        construire_carte_leaflet_points(
          sf_pts        = sf_d,
          bbox          = bbox_active(),
          col_color     = input$map_pts_color_col %||% "",
          col_size      = input$map_pts_size_col  %||% "",
          pt_size       = input$map_pt_size       %||% 6,
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          alpha         = input$map_alpha         %||% 0.75,
          legende_titre = input$map_legende_titre %||% ""
        )
      } else {
        construire_carte_leaflet(
          sf_data       = sf_d,
          bbox          = bbox_active(),
          palette_nom   = input$map_palette       %||% "hal",
          reverse_pal   = input$map_reverse_pal   %||% FALSE,
          alpha         = input$map_alpha         %||% 0.75,
          show_labels   = input$map_show_labels   %||% FALSE,
          col_label     = rv_map$col_sf_zone,
          agg_fun       = input$map_agg_fun       %||% "sum",
          legende_titre = input$map_legende_titre %||% ""
        )
      }
      
      # Injection couches de contexte dans l'export HTML
      m <- injecter_couches_leaflet(
        m           = m,
        layers_info = rv_map$ctx_layers_info,
        active_ids  = shiny::isolate(ctx_active_ids())
      )
      
      htmlwidgets::saveWidget(m, file, selfcontained = TRUE)
    }
  )
  
  # ── PNG ─────────────────────────────────────────────────────────────────────
  output$map_export_png <- shiny::downloadHandler(
    filename = function() paste0("carte_", format(Sys.Date(), "%Y%m%d"), ".png"),
    content  = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      shiny::withProgress(message = "Rendu PNG…", {
        p <- .build_ggplot_export(sf_d)
        ggplot2::ggsave(file, plot = p,
                        width  = (input$map_gg_width  %||% 1600) / 96,
                        height = (input$map_gg_height %||% 1000) / 96,
                        dpi = 96, bg = "transparent")
      })
    }
  )
  
  # ── PDF ─────────────────────────────────────────────────────────────────────
  output$map_export_pdf <- shiny::downloadHandler(
    filename = function() paste0("carte_", format(Sys.Date(), "%Y%m%d"), ".pdf"),
    content  = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      p <- .build_ggplot_export(sf_d)
      ggplot2::ggsave(file, plot = p, device = "pdf",
                      width  = (input$map_gg_width  %||% 1600) / 96,
                      height = (input$map_gg_height %||% 1000) / 96)
    }
  )
  
  # ── SVG ─────────────────────────────────────────────────────────────────────
  output$map_export_svg <- shiny::downloadHandler(
    filename = function() paste0("carte_", format(Sys.Date(), "%Y%m%d"), ".svg"),
    content  = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      p <- .build_ggplot_export(sf_d)
      ggplot2::ggsave(file, plot = p, device = "svg",
                      width  = (input$map_gg_width  %||% 1600) / 96,
                      height = (input$map_gg_height %||% 1000) / 96)
    }
  )
  
  # ── CSV (points ou zones agrégées) ──────────────────────────────────────────
  output$map_export_csv_agg <- shiny::downloadHandler(
    filename = function() {
      prefix <- if (isTRUE(rv_map$pts_mode)) "points_" else "zones_agregees_"
      paste0(prefix, format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content  = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      readr::write_csv2(sf::st_drop_geometry(sf_d), file)
    }
  )
  
  # ── GeoPackage — géométries agrégées (polygones ou points selon le mode) ─────
  output$map_export_gpkg <- shiny::downloadHandler(
    filename = function() {
      prefix <- if (isTRUE(rv_map$pts_mode)) "points_" else "zones_agregees_"
      paste0(prefix, format(Sys.Date(), "%Y%m%d"), ".gpkg")
    },
    content = function(file) {
      sf_d <- sf_data_agg()
      shiny::req(sf_d)
      
      tryCatch({
        # En mode points purs : sf_d contient déjà des géométries POINT,
        # pas de colonne 'valeur' mais toutes les colonnes du df d'origine.
        # En mode zones : sf_d contient les polygones du shapefile + colonne valeur.
        # Dans les deux cas on écrit le sf directement.
        sf::st_write(sf_d, dsn = file, layer = "data", driver = "GPKG",
                     delete_dsn = TRUE, quiet = TRUE)
        shiny::showNotification(
          shiny::tagList(shiny::icon("check-circle"),
                         " GeoPackage exporté (",
                         format(nrow(sf_d), big.mark = "\u202f"),
                         " entités)"),
          type = "message", duration = 4)
      }, error = function(e) {
        shiny::showNotification(
          paste("Erreur export GeoPackage :", e$message),
          type = "error", duration = 8)
      })
    }
  )
  
}