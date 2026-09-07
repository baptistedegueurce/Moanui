# =============================================================================
# tab_map.R — UI onglet Cartographie
# Deux sous-onglets : Exploration (leaflet interactif) / Export (ggplot statique)
# Shapefiles :
#   stat_rect → www/shapefile/rect_stat/ICES_Statistical_Rectangles_Eco.shp
#   div_ciem  → www/shapefile/zone_ciem/ICES_Areas_20160601_cut_dense_3857.shp
# =============================================================================

tab_map <- bslib::nav_panel(
  title = "Cartographie",
  icon  = shiny::icon("map"),
  
  shiny::tags$style(shiny::HTML("

    .map-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      padding: 14px 16px;
      margin-bottom: 12px;
    }
    .map-card-title {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .06em;
      color: #7FB3D3;
      margin-bottom: 10px;
    }
    .map-param-label {
      font-size: 11px;
      color: #7FB3D3;
      font-weight: 600;
      display: block;
      margin-bottom: 3px;
    }
    .map-card .selectize-input {
      background: #061A2B !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
      min-height: 34px !important;
      font-size: 12px !important;
    }
    .map-card .selectize-dropdown {
      background: #0B2A3D !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
    }
    .map-card .selectize-dropdown-content .option:hover {
      background: #123A52 !important;
    }
    .btn-map-primary {
      background-color: #0077B6 !important;
      color: #fff !important;
      border: none !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 600;
      padding: 8px 14px !important;
      transition: 0.2s;
    }
    .btn-map-primary:hover { background-color: #005F8E !important; }
    .btn-map-secondary {
      background-color: #0B2A3D !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 7px 12px !important;
    }
    .btn-map-secondary:hover { background-color: #123A52 !important; }
    .btn-map-export {
      background-color: #123A52 !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 11px !important;
      font-weight: 500;
      padding: 6px 10px !important;
      width: 100%;
      margin-bottom: 6px;
    }
    .btn-map-export:hover { background-color: #1D4E6D !important; }
    .map-preset-grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 6px;
      margin-bottom: 4px;
    }
    .map-preset-btn {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 7px 4px;
      background: #061A2B;
      border: 1px solid #1D4E6D;
      border-radius: 6px;
      cursor: pointer;
      font-size: 10px;
      color: #7FB3D3;
      transition: 0.15s;
      gap: 3px;
      text-align: center;
      line-height: 1.2;
    }
    .map-preset-btn:hover { background: #123A52; color: #EAF2F8; }
    .map-preset-btn.active {
      background: #0077B6;
      border-color: #0077B6;
      color: #fff;
      font-weight: 600;
    }
    .map-preset-btn i { font-size: 15px; }
    .map-leaflet-wrap {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      overflow: hidden;
    }
    .map-ggplot-wrap {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      padding: 12px;
    }
    .map-geo-badge {
      display: inline-block;
      font-size: 10px;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 20px;
      background: #0077B6;
      color: #fff;
      margin-left: 6px;
      vertical-align: middle;
    }
    .nav-tabs { border-bottom: 1px solid #123A52 !important; }
    .nav-tabs .nav-link {
      color: #7FB3D3 !important;
      font-size: 12px !important;
      border: none !important;
      border-bottom: 2px solid transparent !important;
      padding: 6px 12px !important;
    }
    .nav-tabs .nav-link.active {
      background: transparent !important;
      color: #EAF2F8 !important;
      border-bottom: 2px solid #0077B6 !important;
      font-weight: 600;
    }
    .map-card .form-control {
      background: #061A2B !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
      font-size: 12px !important;
    }
    .map-card .irs--shiny .irs-bar { background: #0077B6 !important; }
    .map-card .irs--shiny .irs-handle { border-color: #0077B6 !important; }
    .map-shp-status {
      font-size: 11px;
      margin-top: 4px;
      padding: 4px 8px;
      border-radius: 4px;
    }
    .map-shp-status.ok  { color: #2E9E6B; background: rgba(46,158,107,.12); }
    .map-shp-status.err { color: #E05252; background: rgba(224,82,82,.12); }
    .map-ndistinct-hint {
      font-size: 10px;
      color: #7FB3D3;
      font-style: italic;
      margin-top: 3px;
    }
    /* ── Couches de contexte ── */
    .ctx-layer-row {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 5px 0;
      border-bottom: 1px solid rgba(29,78,109,.35);
    }
    .ctx-layer-row:last-child { border-bottom: none; }
    .ctx-color-dot {
      width: 12px;
      height: 12px;
      border-radius: 3px;
      flex-shrink: 0;
      border: 1px solid rgba(255,255,255,.2);
    }
    .ctx-color-line {
      width: 18px;
      height: 3px;
      border-radius: 2px;
      flex-shrink: 0;
    }
    .ctx-layer-row label {
      font-size: 11px !important;
      color: #EAF2F8 !important;
      margin: 0 !important;
      cursor: pointer;
      flex: 1;
    }
    .ctx-layer-row input[type='checkbox'] {
      margin: 0 !important;
      accent-color: #0077B6;
    }
    .ctx-empty-msg {
      font-size: 11px;
      color: #7FB3D3;
      font-style: italic;
      padding: 6px 0;
    }
    .ctx-dir-hint {
      font-size: 10px;
      color: #4A7FA5;
      margin-top: 6px;
      line-height: 1.4;
    }

  ")),
  
  shiny::tags$script(shiny::HTML("
    function mapSetPreset(val) {
      Shiny.setInputValue('map_preset', val, {priority: 'event'});
      document.querySelectorAll('.map-preset-btn').forEach(function(b) {
        b.classList.toggle('active', b.getAttribute('data-preset') === val);
      });
    }
    document.addEventListener('DOMContentLoaded', function() {
      var def = document.querySelector('.map-preset-btn[data-preset=\"bretagne\"]');
      if (def) def.classList.add('active');
    });
  ")),
  
  shiny::fluidRow(
    
    # =========================================================================
    # COL GAUCHE — Paramètres
    # =========================================================================
    shiny::column(3,
                  
                  # ── Import données ────────────────────────────────────────────────────────
                  app_card(titre = "Source de données", icone = "database", accent = TRUE,
                           app_source_ui(
                             input_id          = "map",
                             accept            = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".rds"),
                             multiple          = FALSE,
                             use_btn_label     = "Utiliser les données de l'app",
                             extra_accept_hint = "CSV, Excel, RDS..."
                           )
                  ),
                  
                  # ── Couche shapefile ──────────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title", shiny::icon("layer-group"), " Couche shapefile"),
                             
                             shiny::div(class = "map-param-block",
                                        shiny::tags$label(class = "map-param-label", "Couche active"),
                                        shiny::selectInput("map_shapefile", label = NULL,
                                                           choices = c(
                                                             "Rectangles statistiques ICES" = "stat_rect",
                                                             "Divisions FAO / CIEM"         = "div_ciem",
                                                             "Shapefile personnalise"        = "custom",
                                                             "Points seuls (lat/lon)"        = "none"
                                                           ))
                             ),
                             
                             # Panneau shapefile custom
                             shiny::conditionalPanel(
                               condition = "input.map_shapefile === 'custom'",
                               
                               shiny::tags$hr(style = "border-color:#1D4E6D; margin:8px 0;"),
                               shiny::div(class = "map-card-title",
                                          style = "margin-bottom:6px;",
                                          shiny::icon("folder-open"), " Import shapefile"),
                               
                               shiny::fileInput("map_shp_fichier", label = NULL,
                                                accept      = c(".shp", ".geojson", ".gpkg", ".zip"),
                                                placeholder = ".shp / .geojson / .gpkg / .zip"),
                               
                               shiny::p(style = "font-size:10px; color:#7FB3D3; margin:2px 0 8px;",
                                        shiny::icon("info-circle"),
                                        " Pour un shapefile multi-fichiers (.shp + .dbf + .prj...),",
                                        " compressez-les dans un .zip avant d'importer."),
                               
                               shiny::actionButton("map_charger_shp_btn",
                                                   shiny::tagList(shiny::icon("upload"), " Charger le shapefile"),
                                                   class = "btn btn-sm btn-map-primary",
                                                   style = "width:100%; margin-bottom:8px;"),
                               
                               shiny::uiOutput("map_shp_status"),
                               shiny::uiOutput("map_shp_col_join_ui"),
                               shiny::uiOutput("map_shp_col_data_ui")
                             ),
                             
                             # Panneau personnalisation points (mode "none")
                             shiny::conditionalPanel(
                               condition = "input.map_shapefile === 'none'",
                               
                               shiny::tags$hr(style = "border-color:#1D4E6D; margin:8px 0;"),
                               shiny::div(class = "map-card-title",
                                          style = "margin-bottom:6px;",
                                          shiny::icon("dot-circle"), " Personnalisation des points"),
                               
                               shiny::uiOutput("map_pts_color_ui"),
                               shiny::uiOutput("map_pts_size_col_ui"),
                               
                               shiny::div(class = "map-param-block",
                                          shiny::tags$label(class = "map-param-label",
                                                            "Taille des points"),
                                          shiny::sliderInput("map_pt_size", label = NULL,
                                                             min = 2, max = 20,
                                                             value = 6, step = 1)
                               )
                             ),
                             
                             shiny::tags$hr(style = "border-color:#1D4E6D; margin:8px 0;"),
                             shiny::conditionalPanel(
                               condition = "input.map_shapefile !== 'none'",
                               shiny::checkboxInput("map_show_labels", "Afficher les labels des zones",
                                                    value = FALSE)
                             )
                  ),
                  
                  # ── Mode géo ──────────────────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title", shiny::icon("crosshairs"), " Mode geolocalisation"),
                             
                             shiny::uiOutput("map_geo_badge"),
                             
                             shiny::div(class = "map-param-block", style = "margin-top:8px;",
                                        shiny::tags$label(class = "map-param-label", "Type de jointure"),
                                        shiny::selectInput("map_geo_mode", label = NULL,
                                                           choices = c(
                                                             "Rectangles statistiques ICES" = "rect_stat",
                                                             "Divisions FAO / CIEM"         = "div_ciem",
                                                             "Latitude / Longitude"         = "latlon"
                                                           ),
                                                           selected = "rect_stat")
                             ),
                             
                             shiny::uiOutput("map_geo_colonnes")
                  ),
                  
                  # ── Variable & agrégation ─────────────────────────────────────────────────
                  shiny::conditionalPanel(
                    condition = "input.map_shapefile !== 'none'",
                    shiny::div(class = "map-card",
                               shiny::div(class = "map-card-title", shiny::icon("calculator"), " Variable & agregation"),
                               
                               shiny::div(class = "map-param-block",
                                          shiny::tags$label(class = "map-param-label", "Variable a cartographier"),
                                          shiny::selectInput("map_var_value", label = NULL, choices = NULL),
                                          # Note contextuelle pour n_distinct
                                          shiny::conditionalPanel(
                                            condition = "input.map_agg_fun === 'n_distinct'",
                                            shiny::p(class = "map-ndistinct-hint",
                                                     shiny::icon("info-circle"),
                                                     " Choisissez la colonne dont vous voulez",
                                                     " compter les valeurs uniques (ex: immatriculation bateau).")
                                          )
                               ),
                               
                               shiny::div(class = "map-param-block",
                                          shiny::tags$label(class = "map-param-label", "Fonction"),
                                          shiny::selectInput("map_agg_fun", label = NULL,
                                                             choices = c(
                                                               "Somme"                  = "sum",
                                                               "Moyenne"                = "mean",
                                                               "Mediane"                = "median",
                                                               "Comptage (n lignes)"    = "n",
                                                               "Nb unique (n_distinct)" = "n_distinct",
                                                               "Maximum"                = "max",
                                                               "Minimum"                = "min"
                                                             ),
                                                             selected = "sum")
                               ),
                               
                    )
                  ), # fin conditionalPanel Variable & agrégation
                  
                  # ── Filtre (toujours visible, tous modes shapefile) ───────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title", shiny::icon("filter"), " Filtre (optionnel)"),
                             shiny::uiOutput("map_filtre_ui")
                  ),
                  
                  # ── Palette heatmap ───────────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title", shiny::icon("palette"), " Palette heatmap"),
                             shiny::div(class = "map-param-block",
                                        shiny::selectInput("map_palette", label = NULL,
                                                           choices = c(
                                                             "Bleu -> Jaune (HAL)" = "hal",
                                                             "Viridis"             = "viridis",
                                                             "Plasma"              = "plasma",
                                                             "YlOrRd"              = "YlOrRd",
                                                             "Blues"               = "Blues",
                                                             "RdYlGn (divergent)"  = "RdYlGn",
                                                             "Spectral"            = "Spectral"
                                                           ),
                                                           selected = "hal")
                             ),
                             shiny::checkboxInput("map_reverse_pal", "Inverser la palette", value = FALSE),
                             shiny::div(class = "map-param-block",
                                        shiny::tags$label(class = "map-param-label", "Transparence (0-1)"),
                                        shiny::sliderInput("map_alpha", label = NULL,
                                                           min = 0.1, max = 1, value = 0.75, step = 0.05)
                             ),
                             shiny::div(class = "map-param-block",
                                        shiny::tags$label(class = "map-param-label",
                                                          "Titre de la legende (affiché sur carte et export)"),
                                        shiny::textInput("map_legende_titre", label = NULL,
                                                         value = "",
                                                         placeholder = "Laissez vide = titre automatique")
                             )
                  ),
                  
                  # ── Couches de contexte ───────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title",
                                        shiny::icon("layer-group"), " Couches de contexte"),
                             shiny::uiOutput("map_context_layers_ui"),
                             shiny::div(class = "ctx-dir-hint",
                                        shiny::icon("info-circle"),
                                        " Placez vos shapefiles dans ",
                                        shiny::tags$code(
                                          style = "font-size:10px; background:#061A2B;
                                                   padding:1px 4px; border-radius:3px;",
                                          "www/shapefile/mapping/"
                                        ))
                  ),
                  
                  # ── Presets zone ──────────────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::div(class = "map-card-title", shiny::icon("map"), " Preset de zone"),
                             
                             shiny::div(class = "map-preset-grid",
                                        shiny::tags$button(class = "map-preset-btn active",
                                                           `data-preset` = "bretagne",
                                                           onclick = "mapSetPreset('bretagne')",
                                                           shiny::icon("anchor"), "Bretagne"),
                                        shiny::tags$button(class = "map-preset-btn",
                                                           `data-preset` = "golfe_gascogne",
                                                           onclick = "mapSetPreset('golfe_gascogne')",
                                                           shiny::icon("water"), "Golfe Gascogne"),
                                        shiny::tags$button(class = "map-preset-btn",
                                                           `data-preset` = "manche",
                                                           onclick = "mapSetPreset('manche')",
                                                           shiny::icon("ship"), "Manche"),
                                        shiny::tags$button(class = "map-preset-btn",
                                                           `data-preset` = "mer_nord",
                                                           onclick = "mapSetPreset('mer_nord')",
                                                           shiny::icon("compass"), "Mer du Nord"),
                                        shiny::tags$button(class = "map-preset-btn",
                                                           `data-preset` = "atlantique_ne",
                                                           onclick = "mapSetPreset('atlantique_ne')",
                                                           shiny::icon("globe-europe"), "Atlantique NE"),
                                        shiny::tags$button(class = "map-preset-btn",
                                                           `data-preset` = "custom",
                                                           onclick = "mapSetPreset('custom')",
                                                           shiny::icon("crop"), "Personnalise")
                             ),
                             
                             shiny::conditionalPanel(
                               condition = "input.map_preset === 'custom'",
                               shiny::br(),
                               shiny::fluidRow(
                                 shiny::column(6,
                                               shiny::numericInput("map_lon_min", "Lon min", value = -6,  step = 0.5)),
                                 shiny::column(6,
                                               shiny::numericInput("map_lon_max", "Lon max", value =  2,  step = 0.5))
                               ),
                               shiny::fluidRow(
                                 shiny::column(6,
                                               shiny::numericInput("map_lat_min", "Lat min", value = 46,  step = 0.5)),
                                 shiny::column(6,
                                               shiny::numericInput("map_lat_max", "Lat max", value = 50,  step = 0.5))
                               )
                             )
                  ),
                  
                  # ── Bouton Générer ────────────────────────────────────────────────────────
                  shiny::div(class = "map-card",
                             shiny::actionButton("map_refresh", "Generer la carte",
                                                 icon  = shiny::icon("play"),
                                                 class = "btn btn-sm btn-map-primary",
                                                 style = "width:100%; font-size:13px; padding:10px;")
                  )
                  
    ), # fin col gauche
    
    
    # =========================================================================
    # COL DROITE — Carte + onglets
    # =========================================================================
    shiny::column(9,
                  
                  shiny::uiOutput("map_kpi"),
                  
                  shiny::tabsetPanel(id = "map_tabs", type = "tabs",
                                     
                                     # ── Exploration leaflet ─────────────────────────────────────────────────
                                     shiny::tabPanel("Exploration interactive",
                                                     shiny::br(),
                                                     shiny::div(class = "map-leaflet-wrap",
                                                                leaflet::leafletOutput("map_leaflet", height = "560px")
                                                     ),
                                                     shiny::br(),
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title", shiny::icon("download"), " Exporter"),
                                                                shiny::fluidRow(
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_html", "HTML interactif",
                                                                                                      class = "btn btn-sm btn-map-export")),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_csv_agg", "CSV agrege",
                                                                                                      class = "btn btn-sm btn-map-export")),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_gpkg", "GeoPackage (.gpkg)",
                                                                                                      class = "btn btn-sm btn-map-export"))
                                                                ),
                                                                shiny::p(style = "font-size:10px; color:#7FB3D3; margin: 6px 0 0;",
                                                                         shiny::icon("info-circle"),
                                                                         " Le GeoPackage contient les geometries spatiales agregees",
                                                                         " (polygones pour shapefile, points pour lat/lon),",
                                                                         " ouvrable dans QGIS, ArcGIS ou R (sf::st_read).")
                                                     )
                                     ),
                                     
                                     # ── Export ggplot ───────────────────────────────────────────────────────
                                     shiny::tabPanel("Export ggplot",
                                                     shiny::br(),
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title",
                                                                           shiny::icon("paint-brush"), " Options ggplot"),
                                                                shiny::fluidRow(
                                                                  shiny::column(4,
                                                                                shiny::tags$label(class = "map-param-label", "Theme fond de carte"),
                                                                                shiny::selectInput("map_gg_theme", label = NULL,
                                                                                                   choices = c(
                                                                                                     "HAL (sombre)"         = "hal_dark",
                                                                                                     "HAL (clair)"          = "hal_light",
                                                                                                     "Classique blanc"      = "classic",
                                                                                                     "Minimal gris"         = "minimal",
                                                                                                     "Oceanographique bleu" = "ocean",
                                                                                                     "Relief ombrage"       = "relief"
                                                                                                   ),
                                                                                                   selected = "hal_dark")
                                                                  ),
                                                                  shiny::column(4,
                                                                                shiny::tags$label(class = "map-param-label", "Taille police labels"),
                                                                                shiny::sliderInput("map_gg_label_size", label = NULL,
                                                                                                   min = 2, max = 8, value = 3, step = 0.5)
                                                                  ),
                                                                  shiny::column(4,
                                                                                shiny::tags$label(class = "map-param-label", "Frontieres"),
                                                                                shiny::checkboxInput("map_gg_borders", "Afficher les frontieres des pays", value = TRUE)
                                                                  )
                                                                ),
                                                                shiny::fluidRow(
                                                                  shiny::column(6,
                                                                                shiny::textInput("map_gg_titre", "Titre",
                                                                                                 placeholder = "Carte des debarquements")),
                                                                  shiny::column(6,
                                                                                shiny::textInput("map_gg_soustitre", "Sous-titre", placeholder = ""))
                                                                ),
                                                                shiny::textInput("map_gg_caption", "Note de bas de page",
                                                                                 placeholder = "Source : SACROIS / DGAMPA"),
                                                                shiny::fluidRow(
                                                                  shiny::column(6,
                                                                                shiny::numericInput("map_gg_width",  "Largeur export (px)",
                                                                                                    value = 1600, step = 100)),
                                                                  shiny::column(6,
                                                                                shiny::numericInput("map_gg_height", "Hauteur export (px)",
                                                                                                    value = 1000, step = 100))
                                                                )
                                                     ),
                                                     
                                                     shiny::div(class = "map-ggplot-wrap",
                                                                shiny::plotOutput("map_ggplot", height = "500px")
                                                     ),
                                                     
                                                     shiny::br(),
                                                     
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title",
                                                                           shiny::icon("download"), " Exporter la carte ggplot"),
                                                                shiny::fluidRow(
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_png", "PNG haute resolution",
                                                                                                      class = "btn btn-sm btn-map-export")),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_pdf", "PDF vectoriel",
                                                                                                      class = "btn btn-sm btn-map-export")),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("map_export_svg", "SVG",
                                                                                                      class = "btn btn-sm btn-map-export"))
                                                                )
                                                     )
                                     ),
                                     
                                     # ── Aperçu fichier importé ──────────────────────────────────────────────
                                     shiny::tabPanel("Apercu fichier",
                                                     shiny::br(),
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title",
                                                                           shiny::icon("table"), " Donnees importees"),
                                                                shiny::fluidRow(
                                                                  shiny::column(3,
                                                                                shiny::numericInput("map_nrows_preview", "Lignes affichees",
                                                                                                    value = 200, min = 10, max = 5000, step = 50))
                                                                ),
                                                                DT::dataTableOutput("map_table_preview")
                                                     )
                                     ),
                                     
                                     # ── Données agrégées ────────────────────────────────────────────────────
                                     shiny::tabPanel("Donnees agregees",
                                                     shiny::br(),
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title",
                                                                           shiny::icon("chart-bar"), " Valeurs par zone"),
                                                                DT::dataTableOutput("map_table_agg")
                                                     )
                                     ),
                                     
                                     # ── Code R ─────────────────────────────────────────────────────────────
                                     shiny::tabPanel("Code R equivalent",
                                                     shiny::br(),
                                                     shiny::div(class = "map-card",
                                                                shiny::div(class = "map-card-title",
                                                                           shiny::icon("code"), " Code sf + ggplot2 equivalent"),
                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                         "Reproduisez cette carte dans vos propres scripts."),
                                                                shiny::div(class = "viz-code-block",
                                                                           shiny::verbatimTextOutput("map_code_r"))
                                                     )
                                     )
                                     
                  ) # fin tabsetPanel
                  
    ) # fin col droite
    
  ) # fin fluidRow
)