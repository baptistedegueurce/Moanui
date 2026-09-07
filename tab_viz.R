# =============================================================================
# tab_viz.R — UI onglet Représentation des données
# Exploite intégralement server_viz + functions_viz
# =============================================================================

tab_viz <- bslib::nav_panel(
  title = "Representation des donnees",
  icon  = shiny::icon("chart-line"),
  
  shiny::tags$style(shiny::HTML("

    /* ---- Cards ---- */
    .viz-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      padding: 14px 16px;
      margin-bottom: 12px;
    }
    .viz-card-title {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .06em;
      color: #7FB3D3;
      margin-bottom: 10px;
    }

    /* ---- Blocs parametres ---- */
    .viz-param-block {
      margin-bottom: 10px;
    }
    .viz-param-label {
      font-size: 11px;
      color: #7FB3D3;
      font-weight: 600;
      display: block;
      margin-bottom: 3px;
    }

    /* ---- Selectize dans viz ---- */
    .viz-card .selectize-input {
      background: #061A2B !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
      min-height: 34px !important;
      font-size: 12px !important;
    }
    .viz-card .selectize-dropdown {
      background: #0B2A3D !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
    }
    .viz-card .selectize-dropdown-content .option:hover {
      background: #123A52 !important;
    }

    /* ---- Boutons ---- */
    .btn-viz-primary {
      background-color: #0077B6 !important;
      color: #fff !important;
      border: none !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 600;
      padding: 8px 14px !important;
      transition: 0.2s;
    }
    .btn-viz-primary:hover { background-color: #005F8E !important; }

    .btn-viz-secondary {
      background-color: #0B2A3D !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 7px 12px !important;
    }
    .btn-viz-secondary:hover { background-color: #123A52 !important; }

    .btn-viz-export {
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
    .btn-viz-export:hover { background-color: #1D4E6D !important; }

    /* ---- Type graphique : grille de boutons ---- */
    .viz-type-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 5px;
      margin-bottom: 4px;
    }
    .viz-type-btn {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 8px 4px;
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
    .viz-type-btn:hover { background: #123A52; color: #EAF2F8; }
    .viz-type-btn.active {
      background: #0077B6;
      border-color: #0077B6;
      color: #fff;
      font-weight: 600;
    }
    .viz-type-btn i { font-size: 16px; }

    /* ---- Tabs ---- */
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

    /* ---- Graphique container — hauteur dynamique ---- */
    .viz-plot-wrap {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 8px;
      padding: 10px;
      /* Hauteur minimale ; s'agrandit selon le contenu plotly (hauteur injectée dynamiquement) */
      min-height: 400px;
      width: 100%;
      overflow: visible;
      transition: height 0.2s ease;
    }
    /* Sans facettes : hauteur confortable par défaut */
    .viz-plot-wrap > .plotly-output-container,
    .viz-plot-wrap > .shiny-plot-output { width: 100%; }

    /* ---- Code R bloc ---- */
    .viz-code-block {
      background: #061A2B;
      border: 1px solid #1D4E6D;
      border-radius: 6px;
      padding: 10px 14px;
      font-family: 'Courier New', monospace;
      font-size: 11px;
      color: #90E0EF;
      white-space: pre-wrap;
      overflow-x: auto;
      max-height: 220px;
    }

    /* ---- Info box ---- */
    .viz-info-box {
      font-size: 12px;
      color: #7FB3D3;
      padding: 4px 0;
    }

    /* ---- Slider dark ---- */
    .viz-card .irs--shiny .irs-bar { background: #0077B6 !important; }
    .viz-card .irs--shiny .irs-handle { background: #0077B6 !important; }
    .viz-card .irs--shiny .irs-single { background: #0077B6 !important; }
    .viz-card .irs--shiny .irs-from, .viz-card .irs--shiny .irs-to { background: #0077B6 !important; }

    /* ---- Checkbox ---- */
    .viz-card .shiny-input-checkboxgroup label,
    .viz-card label { color: #C9D6DF !important; font-size: 12px !important; }
    .viz-card .form-control { font-size: 12px !important; }

    /* ---- Source badge ---- */
    .viz-source-badge {
      display: inline-block;
      font-size: 10px;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 10px;
      margin-left: 6px;
      vertical-align: middle;
    }
    .viz-source-import  { background: #0077B6; color: #fff; }
    .viz-source-nettoye { background: #2E9E6B; color: #fff; }

  ")),
  
  shiny::fluidRow(
    
    # =========================================================================
    # COL GAUCHE — Panneau de configuration
    # =========================================================================
    shiny::column(3,
                  
                  # ── Source de données ─────────────────────────────────────────────────
                  app_card(titre = "Source de données", icone = "database", accent = TRUE,
                           app_source_ui(
                             input_id          = "viz",
                             accept            = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".rds"),
                             multiple          = FALSE,
                             use_btn_label     = "Utiliser les données de l'app",
                             extra_accept_hint = "CSV, XLSX, RDS..."
                           )
                  ),
                  
                  # ── Type de graphique ─────────────────────────────────────────────────
                  shiny::div(class = "viz-card",
                             shiny::div(class = "viz-card-title",
                                        shiny::icon("palette"), " Type de graphique"),
                             
                             # Grille de boutons type (JS met à jour un input caché)
                             shiny::tags$div(class = "viz-type-grid",
                                             
                                             shiny::tags$div(class = "viz-type-btn active", id = "vtype_barres",
                                                             onclick = "setVizType('barres')",
                                                             shiny::icon("chart-bar"), "Barres"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_lignes",
                                                             onclick = "setVizType('lignes')",
                                                             shiny::icon("chart-line"), "Lignes"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_lignes_points",
                                                             onclick = "setVizType('lignes+points')",
                                                             shiny::icon("project-diagram"), "L + Points"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_points",
                                                             onclick = "setVizType('points')",
                                                             shiny::icon("circle"), "Points"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_aire",
                                                             onclick = "setVizType('aire')",
                                                             shiny::icon("water"), "Aire"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_boites",
                                                             onclick = "setVizType('boites')",
                                                             shiny::icon("box"), "Boites"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_violon",
                                                             onclick = "setVizType('violon')",
                                                             shiny::icon("music"), "Violon"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_histogramme",
                                                             onclick = "setVizType('histogramme')",
                                                             shiny::icon("align-left"), "Histo."),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_lollipop",
                                                             onclick = "setVizType('lollipop')",
                                                             shiny::icon("dot-circle"), "Lollipop"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_camembert",
                                                             onclick = "setVizType('camembert')",
                                                             shiny::icon("chart-pie"), "Camebert"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_donut",
                                                             onclick = "setVizType('donut')",
                                                             shiny::icon("circle-notch"), "Donut"),
                                             
                                             shiny::tags$div(class = "viz-type-btn", id = "vtype_placeholder",
                                                             style   = "opacity:0.3; cursor:default;",
                                                             shiny::icon("plus"), "Bientot")
                             ),
                             
                             # Input caché alimenté par le JS
                             shiny::tags$input(type = "hidden", id = "viz_type_viz", value = "barres"),
                             shiny::tags$script(shiny::HTML("
          function setVizType(type) {
            // Met à jour l'input Shiny caché
            Shiny.setInputValue('viz_type_viz', type, {priority: 'event'});
            // Mise à jour visuelle
            document.querySelectorAll('.viz-type-btn').forEach(function(el) {
              el.classList.remove('active');
            });
            var btn = document.getElementById('vtype_' + type.replace('+','_'));
            if (btn) btn.classList.add('active');
          }
        "))
                  ),
                  
                  # ── Variables ─────────────────────────────────────────────────────────
                  shiny::div(class = "viz-card",
                             shiny::div(class = "viz-card-title",
                                        shiny::icon("table"), " Variables"),
                             
                             shiny::div(class = "viz-param-block",
                                        shiny::tags$label(class = "viz-param-label", "Axe X"),
                                        shiny::selectInput("viz_x_var", label = NULL, choices = NULL)
                             ),
                             
                             shiny::div(class = "viz-param-block",
                                        shiny::tags$label(class = "viz-param-label", "Axe Y (numerique)"),
                                        shiny::selectInput("viz_y_var", label = NULL, choices = c("— Aucune —" = ""))
                             ),
                             
                             shiny::div(class = "viz-param-block",
                                        shiny::tags$label(class = "viz-param-label",
                                                          "Couleur / Groupe (categorielle)"),
                                        shiny::selectInput("viz_color_var", label = NULL,
                                                           choices = c("— Aucun —" = ""))
                             ),
                             
                             shiny::div(class = "viz-param-block",
                                        shiny::tags$label(class = "viz-param-label",
                                                          "Facettes (sous-graphiques par)"),
                                        shiny::selectInput("viz_facet_var", label = NULL,
                                                           choices = c("— Aucun —" = ""))
                             ),
                             
                             # Anonymisation
                             shiny::div(style = "margin-top:6px;",
                                        shiny::checkboxInput("viz_anonymiser",
                                                             "Anonymiser les navires (NAV_001...)",
                                                             value = FALSE)
                             )
                  ),
                  
                  # ── Titres ────────────────────────────────────────────────────────────
                  shiny::div(class = "viz-card",
                             shiny::div(class = "viz-card-title",
                                        shiny::icon("heading"), " Titres & etiquettes"),
                             
                             shiny::textInput("viz_titre",    label = "Titre",
                                              placeholder = "Ex : Debarquements par espece"),
                             shiny::textInput("viz_soustitre",label = "Sous-titre", placeholder = ""),
                             shiny::fluidRow(
                               shiny::column(6,
                                             shiny::textInput("viz_titre_x", label = "Label X", placeholder = "Axe X")),
                               shiny::column(6,
                                             shiny::textInput("viz_titre_y", label = "Label Y", placeholder = "Axe Y"))
                             ),
                             shiny::textInput("viz_caption", label = "Note de bas de page",
                                              placeholder = "Source : SACROIS / DGAMPA")
                  ),
                  
                  # ── Bouton Afficher ───────────────────────────────────────────────────
                  shiny::div(class = "viz-card",
                             shiny::actionButton("viz_refresh", "Afficher le graphique",
                                                 icon  = shiny::icon("play"),
                                                 class = "btn btn-sm btn-viz-primary",
                                                 style = "width:100%; font-size:13px; padding:10px;")
                  )
                  
    ), # fin col gauche
    
    # =========================================================================
    # COL DROITE — Graphique + Onglets de configuration avancée
    # =========================================================================
    shiny::column(9,
                  
                  # KPI résumé
                  shiny::uiOutput("viz_kpi_preview"),
                  
                  # Tabs : Graphique / Paramètres / Apparence / Axes / Aperçu données / Code R
                  shiny::tabsetPanel(id = "viz_tabs", type = "tabs",
                                     
                                     # ── Graphique ──────────────────────────────────────────────────────
                                     shiny::tabPanel("Graphique",
                                                     shiny::br(),
                                                     # Injection CSS dynamique (hauteur selon facettes)
                                                     shiny::uiOutput("viz_plot_height_css"),
                                                     shiny::div(class = "viz-plot-wrap",
                                                                plotly::plotlyOutput("viz_graphique", height = "100%")
                                                     ),
                                                     
                                                     shiny::br(),
                                                     
                                                     # Exports
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("download"), " Exporter"),
                                                                shiny::fluidRow(
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("viz_export_png",  "PNG haute resolution",
                                                                                                      class = "btn btn-sm btn-viz-export")
                                                                  ),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("viz_export_html", "HTML interactif",
                                                                                                      class = "btn btn-sm btn-viz-export")
                                                                  ),
                                                                  shiny::column(4,
                                                                                shiny::downloadButton("viz_export_csv",  "CSV (donnees agreges)",
                                                                                                      class = "btn btn-sm btn-viz-export")
                                                                  )
                                                                )
                                                     )
                                     ),
                                     
                                     # ── Paramètres graphique ───────────────────────────────────────────
                                     shiny::tabPanel("Parametres",
                                                     shiny::br(),
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("sliders-h"), " Options du graphique"),
                                                                
                                                                # INPUT STATIQUE — jamais recree par renderUI
                                                                # => updateSelectInput() fonctionne sans etre ecrase
                                                                shiny::conditionalPanel(
                                                                  condition = "input.viz_type_viz != 'histogramme'",
                                                                  shiny::div(class = "viz-param-block",
                                                                             shiny::tags$label(class = "viz-param-label",
                                                                                               "Fonction d'agregation"),
                                                                             shiny::selectInput("viz_agg_fun", label = NULL,
                                                                                                choices = c(
                                                                                                  "Somme"           = "somme",
                                                                                                  "Cumul"           = "cumul",
                                                                                                  "Moyenne"         = "moyenne",
                                                                                                  "Mediane"         = "mediane",
                                                                                                  "Comptage (n)"    = "n",
                                                                                                  "Aucune (brutes)" = "aucune"
                                                                                                ),
                                                                                                selected = "somme")
                                                                  )
                                                                ),
                                                                
                                                                shiny::uiOutput("viz_params_conditionnel")
                                                     )
                                     ),
                                     
                                     # ── Apparence ─────────────────────────────────────────────────────
                                     shiny::tabPanel("Apparence",
                                                     shiny::br(),
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("paint-brush"), " Styles & couleurs"),
                                                                
                                                                # Inputs STATIQUES — jamais recréés par renderUI pour conserver la valeur
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::fluidRow(
                                                                             shiny::column(6,
                                                                                           shiny::tags$label(class = "viz-param-label", "Opacite"),
                                                                                           shiny::sliderInput("viz_opacite", label = NULL,
                                                                                                              min = 0.1, max = 1, value = 0.85, step = 0.05)
                                                                             ),
                                                                             shiny::column(6,
                                                                                           shiny::tags$label(class = "viz-param-label", "Rotation etiquettes X (deg)"),
                                                                                           shiny::sliderInput("viz_angle_x", label = NULL,
                                                                                                              min = 0, max = 90, value = 0, step = 5)
                                                                             )
                                                                           )
                                                                ),
                                                                
                                                                # Tri axe X — input statique
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label", "Tri axe X"),
                                                                           shiny::selectInput("viz_sort_x", label = NULL,
                                                                                              choices  = c("Aucun"      = "aucun",
                                                                                                           "Croissant"  = "croissant",
                                                                                                           "Decroissant"= "decroissant"),
                                                                                              selected = "aucun")
                                                                ),
                                                                
                                                                # Valeurs sur barres
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::checkboxInput("viz_show_values",
                                                                                                "Afficher les valeurs sur les barres", value = FALSE)
                                                                ),
                                                                
                                                                # Legende
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::fluidRow(
                                                                             shiny::column(7,
                                                                                           shiny::tags$label(class = "viz-param-label", "Position legende"),
                                                                                           shiny::selectInput("viz_legend_pos", label = NULL,
                                                                                                              choices  = c("Droite"  = "right",
                                                                                                                           "Bas"     = "bottom",
                                                                                                                           "Haut"    = "top",
                                                                                                                           "Masquee" = "none"),
                                                                                                              selected = "right")
                                                                             ),
                                                                             shiny::column(5,
                                                                                           shiny::tags$label(class = "viz-param-label", "Titre legende"),
                                                                                           shiny::textInput("viz_titre_leg", label = NULL,
                                                                                                            placeholder = "Legende...")
                                                                             )
                                                                           )
                                                                ),
                                                                
                                                                # Valeur seuil y = k
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label",
                                                                                             "Valeur seuil (ligne y = k)"),
                                                                           shiny::div(style = "font-size:10px; color:#7FB3D3; margin-bottom:4px;",
                                                                                      "Ligne de reference — horizontale en vertical, verticale si orientation H"),
                                                                           shiny::numericInput("viz_ligne_ref", label = NULL, value = NA)
                                                                ),
                                                                
                                                                # Palette
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label", "Palette couleurs"),
                                                                           shiny::selectInput("viz_palette_nom", label = NULL,
                                                                                              choices  = c("CRPMEM (défaut)", "Catégoriel riche",
                                                                                                           "Bleus océan", "Verts nature",
                                                                                                           "Chaleur", "Pastel marin", "Monochrome bleu"),
                                                                                              selected = "CRPMEM (défaut)")
                                                                ),
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label",
                                                                                             "Couleur unique (sans variable couleur)"),
                                                                           shiny::textInput("viz_couleur_fixe", label = NULL,
                                                                                            value = "#0077B6", placeholder = "#0077B6")
                                                                ),
                                                                
                                                                shiny::uiOutput("viz_apparence_panel")
                                                     )
                                     ),
                                     
                                     # ── Axes & échelles ────────────────────────────────────────────────
                                     shiny::tabPanel("Axes & echelles",
                                                     shiny::br(),
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("arrows-alt"), " Echelles & limites"),
                                                                shiny::uiOutput("viz_axes_panel"),
                                                                
                                                                # Inputs STATIQUES — jamais dans renderUI pour ne pas reset
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label",
                                                                                             "Hauteur d'affichage (px, sans facettes)"),
                                                                           shiny::numericInput("viz_hauteur_display", label = NULL,
                                                                                               value = 600, min = 300, max = 1200, step = 50)
                                                                ),
                                                                shiny::div(class = "viz-param-block",
                                                                           shiny::tags$label(class = "viz-param-label",
                                                                                             "Dimensions export PNG (px) — n'affecte pas l'affichage"),
                                                                           shiny::fluidRow(
                                                                             shiny::column(6,
                                                                                           shiny::numericInput("viz_largeur_export", "Largeur export",
                                                                                                               value = 1400, min = 400, max = 4000, step = 100)
                                                                             ),
                                                                             shiny::column(6,
                                                                                           shiny::numericInput("viz_hauteur_export", "Hauteur export",
                                                                                                               value = 800, min = 300, max = 3000, step = 100)
                                                                             )
                                                                           )
                                                                )
                                                     )
                                     ),
                                     
                                     # ── Aperçu données ─────────────────────────────────────────────────
                                     shiny::tabPanel("Apercu donnees",
                                                     shiny::br(),
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("table"), " Donnees chargees"),
                                                                shiny::fluidRow(
                                                                  shiny::column(3,
                                                                                shiny::numericInput("viz_nrows_preview", "Lignes affichees",
                                                                                                    value = 200, min = 10, max = 5000, step = 50)
                                                                  )
                                                                ),
                                                                DT::dataTableOutput("viz_table_preview")
                                                     )
                                     ),
                                     
                                     # ── Code R équivalent ──────────────────────────────────────────────
                                     shiny::tabPanel("Code R equivalent",
                                                     shiny::br(),
                                                     shiny::div(class = "viz-card",
                                                                shiny::div(class = "viz-card-title",
                                                                           shiny::icon("code"), " Code ggplot2 equivalent"),
                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                         "Ce code correspond au graphique actuellement configure.
               Copiez-le pour le reutiliser dans vos propres scripts."),
                                                                shiny::div(class = "viz-code-block",
                                                                           shiny::verbatimTextOutput("viz_code_r")
                                                                )
                                                     )
                                     )
                                     
                  ) # fin tabsetPanel
    ) # fin col droite
  ) # fin fluidRow
)