# =============================================================================
# tab_vms.R — UI onglet "Traitement VMS"
# Sous-onglets :
#   1. Données  — import / détection colonnes / KPI / filtre vitesse / traitement
#   2. Cartes   — affichage par navire × mois + export PNG + export SHP
# Préfixe IDs : "sv_"
# =============================================================================

# ── CSS ───────────────────────────────────────────────────────────────────────
vms_css <- shiny::tags$style(shiny::HTML("

  /* ====================================================
     ROOT VARIABLES
     ==================================================== */
  .sv-root {
    --sv-bg0: #061A2B; --sv-bg1: #0B2A3D; --sv-bg2: #123A52;
    --sv-bg3: #1D4E6D; --sv-blue: #0077B6; --sv-blue2: #005F8E;
    --sv-text: #EAF2F8; --sv-muted: #7FB3D3;
    --sv-ok: #2E9E6B; --sv-warn: #E67E22; --sv-err: #C0392B;
    --sv-radius: 10px;
  }

  /* ====================================================
     CARDS
     ==================================================== */
  .sv-card {
    background: var(--sv-bg1, #0B2A3D);
    border: 1px solid var(--sv-bg2, #123A52);
    border-radius: var(--sv-radius, 10px);
    padding: 14px 16px;
    margin-bottom: 14px;
  }
  .sv-card-accent { border-left: 3px solid var(--sv-blue, #0077B6); }
  .sv-card-title {
    font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .06em;
    color: var(--sv-muted, #7FB3D3); margin-bottom: 12px;
  }
  .sv-card-title i { margin-right: 5px; }

  /* ====================================================
     LABELS & HINTS
     ==================================================== */
  .sv-label {
    font-size: 11px; font-weight: 600; color: #C9D6DF;
    display: block; margin-bottom: 3px; margin-top: 6px;
  }
  .sv-hint {
    font-size: 10px; color: var(--sv-muted, #7FB3D3);
    display: block; margin-bottom: 4px;
  }

  /* ====================================================
     TAB HEADER
     ==================================================== */
  .sv-tab-header {
    display: flex; align-items: center; gap: 14px;
    background: linear-gradient(135deg, #062A3F 0%, #0B2A3D 60%, #0D3550 100%);
    border: 1px solid #1D4E6D; border-radius: 12px;
    padding: 16px 20px; margin-bottom: 18px;
  }
  .sv-tab-header-icon { font-size: 28px; color: var(--sv-blue, #0077B6); opacity: 0.85; }
  .sv-tab-header-title { font-size: 15px; font-weight: 700; color: #EAF2F8; margin-bottom: 3px; }
  .sv-tab-header-desc { font-size: 12px; color: #7FB3D3; line-height: 1.4; }

  /* ====================================================
     KPI TILES
     ==================================================== */
  .sv-kpi {
    text-align: center; padding: 12px 10px;
    background: #0B2A3D; border: 1px solid #123A52;
    border-radius: 8px; margin-bottom: 14px; transition: border-color 0.2s;
  }
  .sv-kpi-val { font-size: 22px; font-weight: 700; color: #0077B6; }
  .sv-kpi-lbl { font-size: 11px; color: #7FB3D3; margin-top: 3px; }
  .sv-kpi-warn { border-color: #E67E22 !important; background: #1C1000 !important; }
  .sv-kpi-warn .sv-kpi-val { color: #E67E22 !important; }
  .sv-kpi-warn .sv-kpi-lbl { color: #D68910 !important; }

  /* ====================================================
     BADGES MAPPING COLONNES
     ==================================================== */
  .sv-badge-ok {
    background: #0D3B27; color: #2E9E6B; border: 1px solid #1A6641;
    border-radius: 10px; padding: 1px 7px; font-size: 9px;
    font-weight: 700; margin-left: 5px;
  }
  .sv-badge-ko {
    background: #2C1A09; color: #E67E22; border: 1px solid #7D4B0D;
    border-radius: 10px; padding: 1px 7px; font-size: 9px;
    font-weight: 700; margin-left: 5px;
  }
  .sv-type-badge {
    display: inline-block; font-size: 10px; font-weight: 700;
    padding: 2px 9px; border-radius: 10px;
    margin-left: 6px; vertical-align: middle;
  }
  .sv-type-cls      { background: #0D3B27; color: #2E9E6B; border: 1px solid #1A6641; }
  .sv-type-agiltech { background: #0A1E3A; color: #4FC3F7; border: 1px solid #1565C0; }

  /* ====================================================
     BOUTONS
     ==================================================== */
  .btn-sv-primary {
    background-color: #0077B6 !important; color: #fff !important;
    border: none !important; border-radius: 6px !important;
    font-size: 12px !important; font-weight: 600;
    padding: 8px 14px !important; transition: 0.2s;
  }
  .btn-sv-primary:hover { background-color: #005F8E !important; }

  .btn-sv-secondary {
    background-color: #0B2A3D !important; color: #EAF2F8 !important;
    border: 1px solid #1D4E6D !important; border-radius: 6px !important;
    font-size: 12px !important; padding: 7px 12px !important;
  }
  .btn-sv-secondary:hover { background-color: #123A52 !important; }

  .btn-sv-export {
    background-color: #123A52 !important; color: #EAF2F8 !important;
    border: 1px solid #1D4E6D !important; border-radius: 6px !important;
    font-size: 11px !important; padding: 6px 10px !important;
    width: 100%; margin-bottom: 6px;
  }
  .btn-sv-export:hover { background-color: #1D4E6D !important; }

  /* ====================================================
     SLIDER dark
     ==================================================== */
  .sv-card .irs--shiny .irs-bar    { background: #0077B6 !important; }
  .sv-card .irs--shiny .irs-handle { background: #0077B6 !important; }
  .sv-card .irs--shiny .irs-single { background: #0077B6 !important; }
  .sv-card .irs--shiny .irs-from,
  .sv-card .irs--shiny .irs-to     { background: #0077B6 !important; }

  /* ====================================================
     GRILLE CARTES PAR MOIS
     ==================================================== */
  .sv-maps-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    gap: 14px;
  }
  .sv-map-cell {
    background: #0B2A3D; border: 1px solid #123A52;
    border-radius: 8px; padding: 10px;
  }
  .sv-map-cell-title { font-size: 11px; font-weight: 600; color: #7FB3D3; margin-bottom: 6px; }

  /* ====================================================
     TABS INTERNES
     ==================================================== */
  .sv-root .nav-tabs { border-bottom: 1px solid #123A52 !important; }
  .sv-root .nav-tabs .nav-link {
    color: #7FB3D3 !important; font-size: 12px !important;
    border: none !important; border-bottom: 2px solid transparent !important;
    padding: 6px 12px !important;
  }
  .sv-root .nav-tabs .nav-link.active {
    background: transparent !important; color: #EAF2F8 !important;
    border-bottom: 2px solid #0077B6 !important; font-weight: 600;
  }

  /* ====================================================
     EMPTY STATE
     ==================================================== */
  .sv-empty { text-align: center; padding: 40px 20px; color: #4A7A9B; font-size: 13px; }
  .sv-empty i { font-size: 32px; display: block; margin-bottom: 10px; opacity: 0.5; }

"))

# ── Helpers UI ────────────────────────────────────────────────────────────────

sv_card <- function(..., titre, icone = "cog", accent = FALSE) {
  cls <- paste0("sv-card", if (accent) " sv-card-accent" else "")
  shiny::div(class = cls,
             shiny::div(class = "sv-card-title", shiny::icon(icone), titre),
             ...)
}

sv_lbl <- function(txt, hint = NULL) {
  shiny::tagList(
    shiny::tags$span(class = "sv-label", txt),
    if (!is.null(hint)) shiny::tags$span(class = "sv-hint", hint)
  )
}

sv_tab_header <- function(titre, desc, icone = "circle") {
  shiny::div(class = "sv-tab-header",
             shiny::div(class = "sv-tab-header-icon", shiny::icon(icone)),
             shiny::div(
               shiny::div(class = "sv-tab-header-title", titre),
               shiny::div(class = "sv-tab-header-desc", desc)
             ))
}

sv_empty <- function(msg = "Lancez le traitement pour voir les résultats.", icone = "map") {
  shiny::div(class = "sv-empty", shiny::icon(icone), shiny::br(), msg)
}

# =============================================================================
# SOUS-ONGLET 1 — DONNÉES
# =============================================================================

sv_tab_donnees <- shiny::tabPanel(
  "Données",
  shiny::br(),
  shiny::div(
    class = "sv-root",
    
    sv_tab_header(
      "Import & préparation des données VMS",
      "Importez vos fichiers VMS (CLS ou Agiltech), vérifiez la détection des colonnes et appliquez les filtres avant traitement.",
      "satellite-dish"
    ),
    
    shiny::fluidRow(
      
      # ── Sidebar gauche ────────────────────────────────────────────────────
      shiny::column(3,
                    
                    app_card(titre = "Source de données", icone = "database", accent = TRUE,
                             app_source_ui(
                               input_id          = "sv",
                               accept            = c(".csv", ".txt", ".rds"),
                               multiple          = TRUE,
                               use_btn_label     = "Utiliser les données de l'app",
                               extra_accept_hint = "CSV (CLS / Agiltech) ou RDS"
                             )
                    ),
                    
                    # Mapping colonnes
                    sv_card(titre = "Mapping des colonnes", icone = "columns",
                            shiny::p(
                              class = "sv-hint",
                              shiny::icon("info-circle"),
                              " Colonnes pré-détectées automatiquement. Corrigez si nécessaire."
                            ),
                            shiny::uiOutput("sv_mapping_ui")
                    ),
                    
                    # Filtre vitesse
                    sv_card(titre = "Filtre vitesse", icone = "tachometer-alt",
                            # Le hint (plage observée, badge CLS) reste dynamique
                            shiny::uiOutput("sv_speed_hint_ui"),
                            # Le slider est STATIQUE — valeur initiale neutre 0-100.
                            # updateSliderInput() le recale dès les données chargées.
                            # Ainsi input$sv_speed_slider est TOUJOURS disponible
                            # côté serveur, même au premier clic sur Lancer.
                            shiny::sliderInput(
                              "sv_speed_slider",
                              label = "Vitesse (n\u0153uds)",
                              min   = 0, max = 100,
                              value = c(0, 100),
                              step  = 0.5, width = "100%"
                            ),
                            shiny::div(
                              style = "display:flex; gap:8px; margin-top:4px;",
                              shiny::div(style = "flex:1;",
                                         shiny::tags$label(class = "sv-label", "Min"),
                                         shiny::numericInput("sv_speed_min", NULL,
                                                             value = 0, min = 0, max = 100, step = 0.1)),
                              shiny::div(style = "flex:1;",
                                         shiny::tags$label(class = "sv-label", "Max"),
                                         shiny::numericInput("sv_speed_max", NULL,
                                                             value = 100, min = 0, max = 100, step = 0.1))
                            ),
                            # Sync JS : numericInput → slider seulement (pas l'inverse)
                            shiny::tags$script(shiny::HTML("
                              $(document).on('shiny:inputchanged', function(e) {
                                if (e.name === 'sv_speed_min' || e.name === 'sv_speed_max') {
                                  var mn = parseFloat($('#sv_speed_min').find('input').val());
                                  var mx = parseFloat($('#sv_speed_max').find('input').val());
                                  if (!isNaN(mn) && !isNaN(mx))
                                    Shiny.setInputValue('sv_speed_slider', [mn, mx]);
                                }
                              });
                            "))
                    ),
                    
                    # Lancement traitement
                    sv_card(titre = "Traitement", icone = "play",
                            shiny::actionButton(
                              "sv_run", "Lancer le traitement",
                              icon  = shiny::icon("cogs"),
                              class = "btn btn-sv-primary",
                              style = "width:100%;"
                            ),
                            shiny::br(), shiny::br(),
                            shiny::uiOutput("sv_run_status")
                    )
                    
      ), # fin col gauche
      
      # ── Zone droite ───────────────────────────────────────────────────────
      shiny::column(9,
                    
                    shiny::uiOutput("sv_kpi_row"),
                    
                    sv_card(titre = "Aperçu des données brutes", icone = "table",
                            shiny::fluidRow(
                              shiny::column(4,
                                            sv_lbl("Lignes affichées"),
                                            shiny::numericInput("sv_nrows_preview", NULL, value = 200, min = 10, max = 5000, step = 50)
                              )
                            ),
                            shiny::br(),
                            DT::dataTableOutput("sv_table_preview")
                    )
                    
      ) # fin col droite
    )
  )
)

# =============================================================================
# SOUS-ONGLET 2 — CARTES
# =============================================================================

sv_tab_cartes <- shiny::tabPanel(
  "Cartes",
  shiny::br(),
  shiny::div(
    class = "sv-root",
    
    sv_tab_header(
      "Cartes de présence VMS par navire et par mois",
      paste0(
        "Croisement des points VMS avec les rectangles statistiques (maille_valpena). ",
        "Pour chaque mois, les rectangles actifs sont affichés sur le fond de carte SHOM correspondant."
      ),
      "map"
    ),
    
    shiny::fluidRow(
      
      # ── Sidebar ──────────────────────────────────────────────────────────
      shiny::column(3,
                    
                    sv_card(titre = "Sélection navire", icone = "ship", accent = TRUE,
                            sv_lbl("Navire"),
                            shiny::selectInput(
                              "sv_sel_navire", label = NULL,
                              choices = c("— Chargez les données —" = "")
                            )
                    ),
                    
                    sv_card(titre = "Fichiers géographiques", icone = "folder-open",
                            sv_lbl("Shapefile rectangles (maille_valpena)"),
                            shiny::uiOutput("sv_shp_status"),
                            shiny::br(),
                            sv_lbl("Assemblage cartes marines"),
                            shiny::uiOutput("sv_assemblage_status"),
                            shiny::br(),
                            sv_lbl("Dossier rasters SHOM"),
                            shiny::div(
                              style = "font-size:10px; color:#7FB3D3; margin-bottom:4px;",
                              shiny::icon("folder"), " www/shapefile/raster_shom/"
                            ),
                            shiny::uiOutput("sv_raster_status")
                    ),
                    
                    sv_card(titre = "Génération", icone = "play-circle", accent = TRUE,
                            shiny::p(
                              class = "sv-hint",
                              shiny::icon("info-circle"),
                              " Chargement des rasters SHOM et calcul des intersections — opération lourde, lancez manuellement."
                            ),
                            shiny::actionButton(
                              "sv_generate_maps", "Générer les cartes",
                              icon  = shiny::icon("map"),
                              class = "btn btn-sv-primary",
                              style = "width:100%;"
                            )
                    ),
                    
                    sv_card(titre = "Affichage", icone = "palette",
                            shiny::checkboxInput("sv_show_raster", "Fond de carte SHOM", value = TRUE),
                            shiny::checkboxInput("sv_show_grid",   "Rectangles contexte (zone, éteints)", value = TRUE)
                    ),
                    
                    sv_card(titre = "Export", icone = "download",
                            sv_lbl("Navire sélectionné — tous les mois"),
                            
                            # ── Qualité PNG ───────────────────────────────
                            sv_lbl("Qualité des cartes PNG"),
                            shiny::radioButtons(
                              "sv_export_quality",
                              label    = NULL,
                              choices  = c(
                                "Basse  — rapide   (150 dpi)"  = "low",
                                "Moyenne — équilibré (200 dpi)" = "mid",
                                "Haute  — lente    (300 dpi)"  = "high"
                              ),
                              selected = "mid",
                              inline   = FALSE
                            ),
                            shiny::div(
                              style = "font-size:10px; color:#7FB3D3; margin-bottom:8px;",
                              shiny::icon("clock"),
                              " Basse ≈ 1-2 min | Moyenne ≈ 5-8 min | Haute ≈ 15-25 min"
                            ),
                            
                            shiny::downloadButton(
                              "sv_export_png_zip",
                              "PNG — toutes les cartes (ZIP)",
                              icon  = shiny::icon("file-archive"),
                              class = "btn btn-sv-export"
                            ),
                            shiny::downloadButton(
                              "sv_export_shp_zip",
                              "Shapefile tous mois (ZIP)",
                              icon  = shiny::icon("file-archive"),
                              class = "btn btn-sv-export"
                            ),
                            shiny::div(
                              style = "font-size:10px; color:#7FB3D3; margin-top:4px;",
                              shiny::icon("info-circle"),
                              " Le shapefile regroupe tous les mois avec une colonne 'mois'."
                            )
                    )
                    
      ), # fin sidebar
      
      # ── Zone cartes ───────────────────────────────────────────────────────
      shiny::column(9,
                    shiny::uiOutput("sv_maps_output")
      )
      
    )
  )
)

# =============================================================================
# ONGLET PRINCIPAL VMS
# =============================================================================

tab_vms <- bslib::nav_panel(
  title = "VMS",
  icon  = shiny::icon("satellite-dish"),
  
  vms_css,
  shinyjs::useShinyjs(),
  
  shiny::tabsetPanel(
    id   = "sv_tabs",
    type = "tabs",
    sv_tab_donnees,
    sv_tab_cartes
  )
)