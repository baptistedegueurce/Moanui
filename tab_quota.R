# =============================================================================
# tab_quota.R — UI onglet "Suivi des quotas"  (UI refonte)
# Sous-onglets :
#   1. Données          — import / mapping colonnes / aperçu
#   2. Incohérences engins — couples engin×espèce incohérents
#   3. Incohérences numériques — 0 kg ↔ valeur non nulle
#   4. Dépassements     — limites marée / mois / trimestre / semestre
#   5. Suivi quotas     — consommation vs quota annoncé DGAMPA
#   6. Visualisation    — graphiques + cartes rectangles ICES
# =============================================================================

# ── CSS ────────────────────────────────────────────────────────────────────────
quota_css <- shiny::tags$style(shiny::HTML("

  /* ========================================================
     VARIABLES / RESET
     ======================================================== */
  .sq-root { --sq-bg0: #061A2B; --sq-bg1: #0B2A3D; --sq-bg2: #123A52;
              --sq-bg3: #1D4E6D; --sq-blue: #0077B6; --sq-blue2: #005F8E;
              --sq-text: #EAF2F8; --sq-muted: #7FB3D3;
              --sq-ok: #2E9E6B; --sq-warn: #E67E22; --sq-err: #C0392B;
              --sq-radius: 10px; }

  /* ========================================================
     BANNER ANALYSE GLOBALE
     ======================================================== */
  .sq-global-banner {
    background: linear-gradient(135deg, #062A3F 0%, #0B2A3D 60%, #0D3550 100%);
    border: 1px solid #1D4E6D;
    border-radius: 12px;
    padding: 20px 24px;
    margin-bottom: 18px;
    position: relative;
    overflow: hidden;
  }
  .sq-global-banner::before {
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
    background: linear-gradient(90deg, #0077B6, #2E9E6B, #0077B6);
    background-size: 200% 100%;
    animation: sq-shimmer 3s linear infinite;
  }
  @keyframes sq-shimmer {
    0%   { background-position: 200% 0; }
    100% { background-position: -200% 0; }
  }
  .sq-banner-title {
    font-size: 15px;
    font-weight: 700;
    color: #EAF2F8;
    letter-spacing: .04em;
    margin-bottom: 4px;
  }
  .sq-banner-sub {
    font-size: 12px;
    color: #7FB3D3;
    margin-bottom: 14px;
  }

  /* Module status chips */
  .sq-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 14px;
  }
  .sq-chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 10px;
    border-radius: 20px;
    font-size: 11px;
    font-weight: 600;
    background: #061A2B;
    border: 1px solid #1D4E6D;
    color: #7FB3D3;
  }
  .sq-chip i { font-size: 10px; }

  /* Bouton global */
  .btn-sq-global {
    background: linear-gradient(135deg, #0077B6, #005F8E) !important;
    color: #fff !important;
    border: none !important;
    border-radius: 8px !important;
    font-size: 13px !important;
    font-weight: 700;
    padding: 11px 20px !important;
    letter-spacing: .04em;
    transition: 0.2s;
  }
  .btn-sq-global:hover { opacity: 0.88; transform: translateY(-1px); }

  /* ========================================================
     NAVIGATION DES SOUS-ONGLETS
     ======================================================== */
  .sq-tabs-wrap .nav-tabs {
    border-bottom: 2px solid #123A52 !important;
    margin-bottom: 0 !important;
    background: #061A2B;
    border-radius: 8px 8px 0 0;
    padding: 0 8px;
  }
  .sq-tabs-wrap .nav-tabs .nav-link {
    color: #7FB3D3 !important;
    border: none !important;
    border-bottom: 3px solid transparent !important;
    border-radius: 0 !important;
    font-size: 12px !important;
    font-weight: 600;
    padding: 10px 14px !important;
    margin-bottom: -2px;
    letter-spacing: .03em;
    transition: 0.15s;
    background: transparent !important;
  }
  .sq-tabs-wrap .nav-tabs .nav-link:hover {
    color: #EAF2F8 !important;
    border-bottom-color: #1D4E6D !important;
  }
  .sq-tabs-wrap .nav-tabs .nav-link.active {
    color: #EAF2F8 !important;
    border-bottom: 3px solid #0077B6 !important;
  }
  .sq-tabs-wrap .tab-content {
    background: #061A2B;
    border: 1px solid #123A52;
    border-top: none;
    border-radius: 0 0 10px 10px;
    padding: 18px;
  }

  /* ========================================================
     CARDS
     ======================================================== */
  .sq-card {
    background: #0B2A3D;
    border: 1px solid #123A52;
    border-radius: 10px;
    padding: 14px 16px;
    margin-bottom: 12px;
  }
  .sq-card-title {
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: .08em;
    color: #7FB3D3;
    margin-bottom: 12px;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .sq-card-title i { color: #0077B6; }

  .sq-card-accent {
    border-left: 3px solid #0077B6;
    padding-left: 13px;
  }
  .sq-card-warn  { border-left: 3px solid #E67E22; padding-left: 13px; }
  .sq-card-ok    { border-left: 3px solid #2E9E6B; padding-left: 13px; }

  /* Section divider inside card */
  .sq-divider {
    border: none;
    border-top: 1px solid #123A52;
    margin: 12px 0;
  }

  /* ========================================================
     LABELS ET INPUTS
     ======================================================== */
  .sq-label {
    font-size: 11px;
    color: #7FB3D3;
    font-weight: 600;
    display: block;
    margin-bottom: 3px;
    margin-top: 8px;
  }
  .sq-hint {
    font-size: 10px;
    color: #4A7A9B;
    margin-top: 2px;
    margin-bottom: 6px;
  }
  .sq-card .selectize-input,
  .sq-card .form-control {
    background: #061A2B !important;
    border: 1px solid #1D4E6D !important;
    color: #EAF2F8 !important;
    min-height: 34px !important;
    font-size: 12px !important;
    border-radius: 6px !important;
  }
  .sq-card .selectize-input:focus,
  .sq-card .form-control:focus {
    border-color: #0077B6 !important;
    box-shadow: 0 0 0 2px rgba(0,119,182,.15) !important;
  }
  .sq-card .selectize-dropdown {
    background: #0B2A3D !important;
    border: 1px solid #1D4E6D !important;
    color: #EAF2F8 !important;
  }
  .sq-card .selectize-dropdown-content .option:hover { background: #123A52 !important; }
  .sq-card .selectize-dropdown-content .option.active { background: #0077B6 !important; }

  /* Radio / checkbox */
  .sq-card .radio label, .sq-card .checkbox label { font-size: 12px; color: #EAF2F8; }
  .sq-card .shiny-input-radiogroup .radio { margin-bottom: 4px; }

  /* File input */
  .sq-card .btn-file {
    background: #0077B6 !important;
    color: #fff !important;
    border: none !important;
    font-size: 11px !important;
    border-radius: 5px !important;
  }
  .sq-card .form-control[type=file] { color: #7FB3D3 !important; }

  /* ========================================================
     BOUTONS
     ======================================================== */
  .btn-sq-primary {
    background-color: #0077B6 !important;
    color: #fff !important;
    border: none !important;
    border-radius: 6px !important;
    font-size: 12px !important;
    font-weight: 600;
    padding: 8px 14px !important;
    transition: 0.2s;
    width: 100%;
  }
  .btn-sq-primary:hover { background-color: #005F8E !important; transform: translateY(-1px); }

  .btn-sq-secondary {
    background-color: #0B2A3D !important;
    color: #EAF2F8 !important;
    border: 1px solid #1D4E6D !important;
    border-radius: 6px !important;
    font-size: 12px !important;
    font-weight: 500;
    padding: 7px 12px !important;
    width: 100%;
    transition: 0.15s;
  }
  .btn-sq-secondary:hover { background-color: #123A52 !important; }

  .btn-sq-danger {
    background-color: #7B241C !important;
    color: #fff !important;
    border: none !important;
    border-radius: 6px !important;
    font-size: 11px !important;
    padding: 4px 8px !important;
  }
  .btn-sq-danger:hover { background-color: #C0392B !important; }

  .btn-sq-export {
    background-color: #123A52 !important;
    color: #EAF2F8 !important;
    border: 1px solid #1D4E6D !important;
    border-radius: 6px !important;
    font-size: 11px !important;
    font-weight: 500;
    padding: 7px 10px !important;
    width: 100%;
    transition: 0.15s;
  }
  .btn-sq-export:hover { background-color: #1D4E6D !important; }

  /* ========================================================
     KPI BOXES
     ======================================================== */
  .sq-kpi-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 8px;
    margin-bottom: 14px;
  }
  .sq-kpi {
    text-align: center;
    padding: 14px 8px;
    background: #0B2A3D;
    border: 1px solid #123A52;
    border-radius: 8px;
  }
  .sq-kpi:hover { border-color: #1D4E6D; }
  .sq-kpi-val  { font-size: 22px; font-weight: 700; color: #0077B6; line-height: 1.1; }
  .sq-kpi-lbl  { font-size: 10px; color: #7FB3D3; margin-top: 4px; text-transform: uppercase; letter-spacing: .05em; }
  .sq-kpi-warn { color: #E67E22 !important; }
  .sq-kpi-ok   { color: #2E9E6B !important; }
  .sq-kpi-err  { color: #C0392B !important; }
  .sq-kpi-blue { color: #0077B6 !important; }

  /* ========================================================
     RÈGLES DE DÉPASSEMENT
     ======================================================== */
  .sq-regle-row {
    background: #061A2B;
    border: 1px solid #123A52;
    border-radius: 6px;
    padding: 8px 10px;
    margin-bottom: 6px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    transition: border-color 0.15s;
  }
  .sq-regle-row:hover { border-color: #1D4E6D; }
  .sq-regle-text {
    font-size: 11px;
    color: #EAF2F8;
    line-height: 1.4;
  }
  .sq-regle-badge {
    display: inline-block;
    background: #1B4F72;
    color: #7FB3D3;
    border-radius: 4px;
    padding: 1px 6px;
    font-size: 10px;
    font-weight: 600;
    margin-right: 4px;
    text-transform: uppercase;
  }

  /* ========================================================
     BADGES ESPÈCE
     ======================================================== */
  .sq-esp-badge {
    display: inline-block;
    background: #1B4F72;
    color: #EAF2F8;
    border-radius: 12px;
    padding: 3px 10px;
    font-size: 11px;
    font-weight: 600;
    margin: 2px;
    border: 1px solid #2471A3;
  }

  /* ========================================================
     PLOT WRAP
     ======================================================== */
  .sq-plot-wrap {
    background: #061A2B;
    border: 1px solid #123A52;
    border-radius: 8px;
    padding: 10px;
    margin-top: 8px;
  }

  /* ========================================================
     PAGE HEADER SOUS-ONGLET
     ======================================================== */
  .sq-tab-header {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    margin-bottom: 16px;
    padding: 12px 14px;
    background: linear-gradient(90deg, #0B2A3D, transparent);
    border-left: 3px solid #0077B6;
    border-radius: 0 8px 8px 0;
  }
  .sq-tab-header-icon {
    font-size: 22px;
    color: #0077B6;
    margin-top: 2px;
  }
  .sq-tab-header-title {
    font-size: 14px;
    font-weight: 700;
    color: #EAF2F8;
    margin-bottom: 2px;
  }
  .sq-tab-header-desc {
    font-size: 11px;
    color: #7FB3D3;
    line-height: 1.5;
  }

  /* ========================================================
     TWO-COLUMN LAYOUT
     ======================================================== */
  .sq-sidebar { /* left panel */ }
  .sq-main    { /* right panel */ }

  /* ========================================================
     CHECKBOX / RADIO STYLED
     ======================================================== */
  .sq-card .checkbox-group-input .checkbox {
    background: #061A2B;
    border: 1px solid #123A52;
    border-radius: 6px;
    padding: 6px 10px;
    margin-bottom: 4px;
  }
  .sq-card .checkbox-group-input .checkbox:hover { border-color: #1D4E6D; }

  /* ========================================================
     FORM-GROUP SPACING
     ======================================================== */
  .sq-form-row { margin-bottom: 10px; }

  /* ========================================================
     DATE INPUTS
     ======================================================== */
  .sq-card .input-group .form-control { border-radius: 6px !important; }
  .sq-card .input-group-addon {
    background: #123A52 !important;
    border: 1px solid #1D4E6D !important;
    color: #7FB3D3 !important;
  }

  /* ========================================================
     QUOTA PROGRESS BAR (cosmétique KPI)
     ======================================================== */
  .sq-progress-wrap {
    background: #061A2B;
    border: 1px solid #123A52;
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 10px;
  }
  .sq-progress-label {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: #7FB3D3;
    margin-bottom: 6px;
  }
  .sq-progress-bar-track {
    height: 8px;
    background: #061A2B;
    border: 1px solid #123A52;
    border-radius: 4px;
    overflow: hidden;
  }
  .sq-progress-fill {
    height: 100%;
    border-radius: 4px;
    transition: width 0.4s ease;
  }

  /* ========================================================
     EMPTY STATE
     ======================================================== */
  .sq-empty {
    text-align: center;
    padding: 28px 16px;
    color: #4A7A9B;
    font-size: 12px;
  }
  .sq-empty i { font-size: 28px; margin-bottom: 8px; display: block; }

  /* ========================================================
     NUMERIC INPUT OVERRIDE
     ======================================================== */
  .sq-card .numeric-input input { text-align: right; }

"))

# =============================================================================
# HELPERS UI
# =============================================================================

sq_card <- function(..., titre, icone = "cog", accent = FALSE) {
  cls <- paste0("sq-card", if (accent) " sq-card-accent" else "")
  shiny::div(class = cls,
             shiny::div(class = "sq-card-title",
                        shiny::icon(icone), titre
             ),
             ...
  )
}

sq_lbl <- function(txt, hint = NULL) {
  tagList(
    shiny::tags$span(class = "sq-label", txt),
    if (!is.null(hint)) shiny::tags$span(class = "sq-hint", hint)
  )
}

sq_tab_header <- function(titre, desc, icone = "circle") {
  shiny::div(class = "sq-tab-header",
             shiny::div(class = "sq-tab-header-icon", shiny::icon(icone)),
             shiny::div(
               shiny::div(class = "sq-tab-header-title", titre),
               shiny::div(class = "sq-tab-header-desc", desc)
             )
  )
}

sq_empty <- function(msg = "Lancez l'analyse pour voir les résultats.", icone = "chart-bar") {
  shiny::div(class = "sq-empty",
             shiny::icon(icone),
             msg
  )
}

sq_export_btns <- function(id_xlsx = NULL, id_png = NULL) {
  shiny::fluidRow(
    if (!is.null(id_xlsx))
      shiny::column(6,
                    shiny::downloadButton(id_xlsx, "Export Excel",
                                          icon  = shiny::icon("file-excel"),
                                          class = "btn btn-sm btn-sq-export")
      ),
    if (!is.null(id_png))
      shiny::column(6,
                    shiny::downloadButton(id_png, "Export PNG",
                                          icon  = shiny::icon("image"),
                                          class = "btn btn-sm btn-sq-export")
      )
  )
}

# =============================================================================
# TABLE ENGINS COHÉRENTS (référence locale)
# =============================================================================

SQ_ENGINS_COHERENTS <- list(
  
  MAC = list(
    nom       = "Maquereau commun",
    coherents = c("PTM", "OTM", "PS", "LLS", "FPO", "LHP", "DRB", "SDN")
  ),
  
  POL = list(
    nom       = "Lieu jaune",
    coherents = c("OTB", "OTT", "PTB", "GNS", "GTN", "GTR", "LLS", "LHP", "LHM", "FPO", "SDN", "DRB")
  ),
  
  SOL = list(
    nom       = "Sole commune",
    coherents = c("OTB", "PTB", "SDN", "SSC", "GTR", "GNS", "FPO")
  )
  
  # ── AJOUTER DE NOUVELLES ESPÈCES ICI ─────────────────────────────────────
  # HKE = list(nom = "Merlu européen", coherents = c("OTB","OTT","PTB","LLS","LHP","GNS"))
)

# =============================================================================
# SOUS-ONGLET 1 — DONNÉES
# =============================================================================

sq_tab_donnees <- shiny::tabPanel("Données",
                                  shiny::br(),
                                  
                                  sq_tab_header(
                                    "Source et préparation des données",
                                    "Chargez vos données (fichier ou onglet Données), configurez le mapping de colonnes et vérifiez l'aperçu avant analyse.",
                                    "database"
                                  ),
                                  
                                  shiny::fluidRow(
                                    
                                    # ── Sidebar gauche ─────────────────────────────────────────────────────
                                    shiny::column(3,
                                                  
                                                  app_card(titre = "Source de données", icone = "database", accent = TRUE,
                                                           app_source_ui(
                                                             input_id          = "sq",
                                                             accept            = c(".csv", ".xlsx", ".xls", ".rds"),
                                                             multiple          = TRUE,
                                                             use_btn_label     = "Utiliser les données de l'app",
                                                             extra_accept_hint = "CSV, XLSX, XLS ou RDS"
                                                           ),
                                                           shiny::hr(class = "app-divider"),
                                                           app_lbl("Filtre opérateur"),
                                                           shiny::uiOutput("sq_op_filtre_ui")
                                                  ),
                                                  
                                                  sq_card(titre = "Mapping des colonnes", icone = "columns",
                                                          shiny::p(class = "sq-hint",
                                                                   shiny::icon("info-circle"), " Les colonnes sont pré-détectées automatiquement. Corrigez si nécessaire."
                                                          ),
                                                          shiny::uiOutput("sq_mapping_ui")
                                                  )
                                    ),
                                    
                                    # ── Colonne droite : aperçu ─────────────────────────────────────────────
                                    shiny::column(9,
                                                  
                                                  shiny::uiOutput("sq_kpi_row"),
                                                  
                                                  sq_card(titre = "Aperçu des données", icone = "table",
                                                          shiny::fluidRow(
                                                            shiny::column(4,
                                                                          sq_lbl("Lignes affichées"),
                                                                          shiny::numericInput("sq_nrows", NULL,
                                                                                              value = 200, min = 10, max = 5000, step = 50)
                                                            )
                                                          ),
                                                          shiny::br(),
                                                          DT::dataTableOutput("sq_table_preview")
                                                  )
                                    )
                                  )
)

# =============================================================================
# SOUS-ONGLET 2 — INCOHÉRENCES ENGINS
# =============================================================================

sq_tab_engins <- shiny::tabPanel("Incohérences engins",
                                 shiny::br(),
                                 
                                 sq_tab_header(
                                   "Détection des engins incohérents",
                                   "Identifie les lignes où l'engin de pêche déclaré n'est pas cohérent avec l'espèce ciblée (référentiel FAO).",
                                   "fish"
                                 ),
                                 
                                 shiny::fluidRow(
                                   
                                   # ── Sidebar ──────────────────────────────────────────────────────────
                                   shiny::column(3,
                                                 
                                                 sq_card(titre = "Espèce(s) analysée(s)", icone = "fish", accent = TRUE,
                                                         
                                                         sq_lbl("Sélectionner les espèces"),
                                                         shiny::selectizeInput("sq_esp_engin", label = NULL,
                                                                               choices  = NULL,
                                                                               multiple = TRUE,
                                                                               options  = list(plugins = list("remove_button"),
                                                                                               placeholder = "Toutes les espèces…")
                                                         ),
                                                         
                                                         shiny::div(id = "sq_engins_ref_wrap",
                                                                    shiny::hr(class = "sq-divider"),
                                                                    sq_lbl("Engins cohérents de référence"),
                                                                    shiny::uiOutput("sq_engins_ref_ui")
                                                         ),
                                                         
                                                         shiny::hr(class = "sq-divider"),
                                                         shiny::actionButton("sq_run_engins", "Analyser",
                                                                             icon  = shiny::icon("magnifying-glass"),
                                                                             class = "btn btn-sq-primary"
                                                         )
                                                 ),
                                                 
                                                 sq_card(titre = "Export", icone = "download",
                                                         shiny::downloadButton("sq_export_engins_zip", "Télécharger (ZIP)",
                                                                               icon  = shiny::icon("file-archive"),
                                                                               class = "btn btn-sq-export")
                                                 )
                                   ),
                                   
                                   # ── Résultats ─────────────────────────────────────────────────────────
                                   shiny::column(9,
                                                 
                                                 shiny::uiOutput("sq_engins_kpi_row"),
                                                 
                                                 shiny::tabsetPanel(
                                                   shiny::tabPanel("Résumé par engin",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Débarquements par engin incohérent", icone = "table",
                                                                           DT::dataTableOutput("sq_engins_table_resume")
                                                                   )
                                                   ),
                                                   shiny::tabPanel("Détail navires",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Navires et quartiers concernés", icone = "ship",
                                                                           DT::dataTableOutput("sq_engins_table_navires")
                                                                   )
                                                   ),
                                                   shiny::tabPanel("Graphique",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Poids incohérent par engin (kg)", icone = "chart-bar",
                                                                           shiny::div(class = "sq-plot-wrap",
                                                                                      shiny::plotOutput("sq_engins_plot", height = "400px")
                                                                           )
                                                                   )
                                                   )
                                                 )
                                   )
                                 )
)

# =============================================================================
# SOUS-ONGLET 3 — INCOHÉRENCES NUMÉRIQUES
# =============================================================================

sq_tab_numerique <- shiny::tabPanel("Incohérences numériques",
                                    shiny::br(),
                                    
                                    sq_tab_header(
                                      "Détection des incohérences numériques",
                                      "Repère les lignes avec des valeurs contradictoires : poids nul mais valeur monétaire non nulle, ou inversement.",
                                      "triangle-exclamation"
                                    ),
                                    
                                    shiny::fluidRow(
                                      
                                      shiny::column(3,
                                                    
                                                    sq_card(titre = "Types à détecter", icone = "sliders-h", accent = TRUE,
                                                            
                                                            shiny::checkboxGroupInput("sq_num_types", label = NULL,
                                                                                      choices  = c(
                                                                                        "0 kg — valeur > 0 (poids nul, euros présents)"  = "zero_kg",
                                                                                        "0 € — poids > 0 (valeur nulle, poids présent)"  = "zero_eur"
                                                                                      ),
                                                                                      selected = c("zero_kg", "zero_eur")
                                                            ),
                                                            
                                                            shiny::hr(class = "sq-divider"),
                                                            shiny::actionButton("sq_run_num", "Analyser",
                                                                                icon  = shiny::icon("magnifying-glass"),
                                                                                class = "btn btn-sq-primary"
                                                            )
                                                    ),
                                                    
                                                    sq_card(titre = "Export", icone = "download",
                                                            shiny::downloadButton("sq_export_num_zip", "Télécharger (ZIP)",
                                                                                  icon  = shiny::icon("file-archive"),
                                                                                  class = "btn btn-sq-export")
                                                    )
                                      ),
                                      
                                      shiny::column(9,
                                                    
                                                    shiny::uiOutput("sq_num_kpi_row"),
                                                    
                                                    shiny::tabsetPanel(
                                                      shiny::tabPanel("Résumé",
                                                                      shiny::br(),
                                                                      sq_card(titre = "Statistiques des incohérences", icone = "table",
                                                                              DT::dataTableOutput("sq_num_table_resume")
                                                                      )
                                                      ),
                                                      shiny::tabPanel("Lignes concernées",
                                                                      shiny::br(),
                                                                      sq_card(titre = "Détail des lignes incohérentes", icone = "list",
                                                                              DT::dataTableOutput("sq_num_table_detail")
                                                                      )
                                                      ),
                                                      shiny::tabPanel("Graphique",
                                                                      shiny::br(),
                                                                      sq_card(titre = "Répartition par type d'incohérence", icone = "chart-pie",
                                                                              shiny::div(class = "sq-plot-wrap",
                                                                                         shiny::plotOutput("sq_num_plot", height = "350px")
                                                                              )
                                                                      )
                                                      )
                                                    )
                                      )
                                    )
)

# =============================================================================
# SOUS-ONGLET 4 — DÉPASSEMENTS
# =============================================================================

sq_tab_depassements <- shiny::tabPanel("Dépassements",
                                       shiny::br(),
                                       
                                       sq_tab_header(
                                         "Contrôle des dépassements de capture",
                                         "Définissez des règles de limitation par navire (par marée, mois, trimestre ou semestre) et identifiez les dépassements.",
                                         "scale-balanced"
                                       ),
                                       
                                       shiny::fluidRow(
                                         
                                         # ── Sidebar : règles ──────────────────────────────────────────────────
                                         shiny::column(4,
                                                       
                                                       sq_card(titre = "Nouvelle règle", icone = "plus-circle", accent = TRUE,
                                                               
                                                               sq_lbl("Espèce concernée"),
                                                               shiny::uiOutput("sq_dep_esp_ui"),
                                                               
                                                               shiny::fluidRow(
                                                                 shiny::column(6,
                                                                               sq_lbl("Type de période"),
                                                                               shiny::selectInput("sq_dep_type", label = NULL,
                                                                                                  choices = c(
                                                                                                    "Marée"     = "maree",
                                                                                                    "Mois"      = "mois",
                                                                                                    "Trimestre" = "trimestre",
                                                                                                    "Semestre"  = "semestre"
                                                                                                  )
                                                                               )
                                                                 ),
                                                                 shiny::column(6,
                                                                               sq_lbl("Limite (kg/navire)"),
                                                                               shiny::numericInput("sq_dep_limite", label = NULL,
                                                                                                   value = 100, min = 0, step = 10)
                                                                 )
                                                               ),
                                                               
                                                               shiny::fluidRow(
                                                                 shiny::column(6,
                                                                               sq_lbl("Date début"),
                                                                               shiny::dateInput("sq_dep_debut", label = NULL,
                                                                                                value    = paste0(format(Sys.Date(), "%Y"), "-01-01"),
                                                                                                format   = "dd/mm/yyyy",
                                                                                                language = "fr")
                                                                 ),
                                                                 shiny::column(6,
                                                                               sq_lbl("Date fin"),
                                                                               shiny::dateInput("sq_dep_fin", label = NULL,
                                                                                                value    = paste0(format(Sys.Date(), "%Y"), "-12-31"),
                                                                                                format   = "dd/mm/yyyy",
                                                                                                language = "fr")
                                                                 )
                                                               ),
                                                               
                                                               shiny::hr(class = "sq-divider"),
                                                               shiny::actionButton("sq_dep_add", "Ajouter cette règle",
                                                                                   icon  = shiny::icon("plus"),
                                                                                   class = "btn btn-sq-secondary"
                                                               )
                                                       ),
                                                       
                                                       sq_card(titre = "Règles actives", icone = "list-check",
                                                               shiny::uiOutput("sq_dep_regles_ui"),
                                                               shiny::hr(class = "sq-divider"),
                                                               shiny::actionButton("sq_run_dep", "Analyser les dépassements",
                                                                                   icon  = shiny::icon("magnifying-glass"),
                                                                                   class = "btn btn-sq-primary"
                                                               )
                                                       ),
                                                       
                                                       sq_card(titre = "Export", icone = "download",
                                                               shiny::downloadButton("sq_export_dep_zip", "Télécharger (ZIP)",
                                                                                     icon  = shiny::icon("file-archive"),
                                                                                     class = "btn btn-sq-export")
                                                       )
                                         ),
                                         
                                         # ── Résultats ──────────────────────────────────────────────────────────
                                         shiny::column(8,
                                                       
                                                       shiny::uiOutput("sq_dep_kpi_row"),
                                                       
                                                       shiny::tabsetPanel(
                                                         shiny::tabPanel("Résumé global",
                                                                         shiny::br(),
                                                                         sq_card(titre = "Dépassements par type de période", icone = "table",
                                                                                 DT::dataTableOutput("sq_dep_table_resume")
                                                                         )
                                                         ),
                                                         shiny::tabPanel("Par navire",
                                                                         shiny::br(),
                                                                         sq_card(titre = "Navires en dépassement", icone = "ship",
                                                                                 DT::dataTableOutput("sq_dep_table_navires")
                                                                         )
                                                         ),
                                                         shiny::tabPanel("Détail",
                                                                         shiny::br(),
                                                                         sq_card(titre = "Toutes les lignes en dépassement", icone = "list",
                                                                                 DT::dataTableOutput("sq_dep_table_detail")
                                                                         )
                                                         ),
                                                         shiny::tabPanel("Graphiques",
                                                                         shiny::br(),
                                                                         sq_card(titre = "Dépassements (tonnes) par mois et engin", icone = "chart-bar",
                                                                                 shiny::div(class = "sq-plot-wrap",
                                                                                            shiny::plotOutput("sq_dep_plot_kg", height = "300px")
                                                                                 )
                                                                         ),
                                                                         sq_card(titre = "Nombre de dépassements par mois et engin", icone = "chart-column",
                                                                                 shiny::div(class = "sq-plot-wrap",
                                                                                            shiny::plotOutput("sq_dep_plot_nb", height = "300px")
                                                                                 )
                                                                         )
                                                         )
                                                       )
                                         )
                                       )
)

# =============================================================================
# SOUS-ONGLET 5 — SUIVI DES QUOTAS
# =============================================================================

sq_tab_quotas <- shiny::tabPanel("Suivi quotas",
                                 shiny::br(),
                                 
                                 sq_tab_header(
                                   "Suivi de la consommation des quotas",
                                   "Renseignez le quota annuel total et la valeur annoncée par la DGAMPA pour calculer l'écart et la consommation mensuelle.",
                                   "gauge"
                                 ),
                                 
                                 shiny::fluidRow(
                                   
                                   shiny::column(3,
                                                 
                                                 sq_card(titre = "Paramètres", icone = "gauge", accent = TRUE,
                                                         
                                                         sq_lbl("Espèce"),
                                                         shiny::uiOutput("sq_quota_esp_ui"),
                                                         
                                                         shiny::hr(class = "sq-divider"),
                                                         
                                                         sq_lbl("Quota annuel total (kg)"),
                                                         shiny::numericInput("sq_quota_total", label = NULL,
                                                                             value = 16000, min = 0, step = 100),
                                                         
                                                         sq_lbl("Annoncé DGAMPA (kg)"),
                                                         shiny::numericInput("sq_quota_dgampa", label = NULL,
                                                                             value = 1000, min = 0, step = 100),
                                                         
                                                         sq_lbl("Consommation supposée (kg)", hint = "Optionnel — pour comparaison"),
                                                         shiny::numericInput("sq_quota_suppose", label = NULL,
                                                                             value = NA, min = 0, step = 100),
                                                         
                                                         shiny::hr(class = "sq-divider"),
                                                         shiny::actionButton("sq_run_quota", "Calculer",
                                                                             icon  = shiny::icon("calculator"),
                                                                             class = "btn btn-sq-primary"
                                                         )
                                                 ),
                                                 
                                                 sq_card(titre = "Export", icone = "download",
                                                         shiny::downloadButton("sq_export_quota_zip", "Télécharger (ZIP)",
                                                                               icon  = shiny::icon("file-archive"),
                                                                               class = "btn btn-sq-export")
                                                 )
                                   ),
                                   
                                   shiny::column(9,
                                                 
                                                 shiny::uiOutput("sq_quota_kpi_row"),
                                                 
                                                 shiny::tabsetPanel(
                                                   shiny::tabPanel("Tableau de suivi",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Consommation mensuelle et cumulée", icone = "table",
                                                                           DT::dataTableOutput("sq_quota_table")
                                                                   )
                                                   ),
                                                   shiny::tabPanel("Graphique cumulé",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Débarquements cumulés vs quotas", icone = "chart-line",
                                                                           shiny::div(class = "sq-plot-wrap",
                                                                                      shiny::plotOutput("sq_quota_plot_cumul", height = "420px")
                                                                           )
                                                                   )
                                                   ),
                                                   shiny::tabPanel("Graphique mensuel",
                                                                   shiny::br(),
                                                                   sq_card(titre = "Consommation mensuelle du quota", icone = "chart-bar",
                                                                           shiny::div(class = "sq-plot-wrap",
                                                                                      shiny::plotOutput("sq_quota_plot_mensuel", height = "380px")
                                                                           )
                                                                   )
                                                   )
                                                 )
                                   )
                                 )
)

# =============================================================================
# SOUS-ONGLET 6 — VISUALISATION (graphiques flotte + carte ICES)
# =============================================================================

sq_tab_visu <- shiny::tabPanel("Visualisation",
                               shiny::br(),
                               
                               sq_tab_header(
                                 "Graphiques de flotte et cartographie ICES",
                                 "Visualisez la composition de la flotte (navires, engins, quartiers) et la répartition spatiale des débarquements par rectangle ICES.",
                                 "chart-area"
                               ),
                               
                               shiny::fluidRow(
                                 
                                 # ── Sidebar contrôle ──────────────────────────────────────────────────
                                 shiny::column(3,
                                               
                                               sq_card(titre = "Graphiques de flotte", icone = "chart-bar", accent = TRUE,
                                                       shiny::p(class = "sq-hint",
                                                                "Utilise l'espèce et le quota définis dans l'onglet ",
                                                                shiny::strong("Suivi quotas"), "."
                                                       ),
                                                       shiny::actionButton("sq_run_plots", "Générer les graphiques",
                                                                           icon  = shiny::icon("play"),
                                                                           class = "btn btn-sq-primary"
                                                       ),
                                                       shiny::hr(class = "sq-divider"),
                                                       shiny::downloadButton("sq_export_plots_png", "Exporter panel PNG",
                                                                             icon  = shiny::icon("image"),
                                                                             class = "btn btn-sq-export",
                                                                             style = "margin-top:4px;"
                                                       )
                                               ),
                                               
                                               sq_card(titre = "Carte ICES", icone = "map",
                                                       
                                                       sq_lbl("Variable à cartographier"),
                                                       shiny::selectInput("sq_map_var", label = NULL,
                                                                          choices  = c("Nombre de marées" = "nb_marees",
                                                                                       "Débarquement (kg)" = "kg",
                                                                                       "Débarquement (€)"  = "euros"),
                                                                          selected = "kg"
                                                       ),
                                                       
                                                       sq_lbl("Palette de couleurs"),
                                                       shiny::selectInput("sq_map_palette", label = NULL,
                                                                          choices  = c("Magma" = "magma", "Plasma" = "plasma",
                                                                                       "Viridis" = "viridis", "Inferno" = "inferno"),
                                                                          selected = "magma"
                                                       ),
                                                       
                                                       shiny::hr(class = "sq-divider"),
                                                       sq_lbl("Emprise longitude"),
                                                       shiny::fluidRow(
                                                         shiny::column(6,
                                                                       shiny::numericInput("sq_map_xmin", "Min", value = -10, step = 0.5)
                                                         ),
                                                         shiny::column(6,
                                                                       shiny::numericInput("sq_map_xmax", "Max", value = 5, step = 0.5)
                                                         )
                                                       ),
                                                       
                                                       sq_lbl("Emprise latitude"),
                                                       shiny::fluidRow(
                                                         shiny::column(6,
                                                                       shiny::numericInput("sq_map_ymin", "Min", value = 43, step = 0.5)
                                                         ),
                                                         shiny::column(6,
                                                                       shiny::numericInput("sq_map_ymax", "Max", value = 52, step = 0.5)
                                                         )
                                                       ),
                                                       
                                                       shiny::hr(class = "sq-divider"),
                                                       shiny::actionButton("sq_run_map", "Générer la carte",
                                                                           icon  = shiny::icon("map"),
                                                                           class = "btn btn-sq-primary"
                                                       ),
                                                       shiny::br(), shiny::br(),
                                                       shiny::downloadButton("sq_export_map_png", "Exporter carte PNG",
                                                                             icon  = shiny::icon("image"),
                                                                             class = "btn btn-sq-export"
                                                       )
                                               )
                                 ),
                                 
                                 # ── Graphiques ──────────────────────────────────────────────────────
                                 shiny::column(9,
                                               
                                               shiny::tabsetPanel(
                                                 shiny::tabPanel("Panel flotte",
                                                                 shiny::br(),
                                                                 sq_card(titre = "Navires par mois / quartier / engin / top débarquements", icone = "chart-bar",
                                                                         shiny::div(class = "sq-plot-wrap",
                                                                                    shiny::plotOutput("sq_visu_panel", height = "600px")
                                                                         )
                                                                 )
                                                 ),
                                                 shiny::tabPanel("Cumul vs quota",
                                                                 shiny::br(),
                                                                 sq_card(titre = "Débarquements cumulés vs quota", icone = "chart-line",
                                                                         shiny::div(class = "sq-plot-wrap",
                                                                                    shiny::plotOutput("sq_visu_cumul", height = "400px")
                                                                         )
                                                                 )
                                                 ),
                                                 shiny::tabPanel("Par mois",
                                                                 shiny::br(),
                                                                 sq_card(titre = "Débarquements par mois", icone = "chart-column",
                                                                         shiny::div(class = "sq-plot-wrap",
                                                                                    shiny::plotOutput("sq_visu_mois", height = "380px")
                                                                         )
                                                                 )
                                                 ),
                                                 shiny::tabPanel("Carte ICES",
                                                                 shiny::br(),
                                                                 sq_card(titre = "Carte des rectangles statistiques ICES", icone = "map",
                                                                         shiny::div(class = "sq-plot-wrap",
                                                                                    shiny::plotOutput("sq_visu_map", height = "500px")
                                                                         )
                                                                 )
                                                 )
                                               )
                                 )
                               )
)

# =============================================================================
# BANNIÈRE ANALYSE GLOBALE
# =============================================================================

sq_analyse_globale_ui <- shiny::div(class = "sq-global-banner",
                                    
                                    shiny::div(class = "sq-banner-title",
                                               shiny::icon("rocket"), "  Analyse complète — Suivi des quotas"
                                    ),
                                    shiny::div(class = "sq-banner-sub",
                                               "Lance tous les modules en séquence et prépare un dossier de résultats (tableurs XLSX + graphiques PNG) prêt à exporter."
                                    ),
                                    
                                    # Chips modules
                                    shiny::div(class = "sq-chips",
                                               shiny::span(class = "sq-chip", shiny::icon("database"),      "Nettoyage"),
                                               shiny::span(class = "sq-chip", shiny::icon("fish"),          "Engins"),
                                               shiny::span(class = "sq-chip", shiny::icon("triangle-exclamation"), "Numérique"),
                                               shiny::span(class = "sq-chip", shiny::icon("scale-balanced"),"Dépassements"),
                                               shiny::span(class = "sq-chip", shiny::icon("gauge"),         "Quota"),
                                               shiny::span(class = "sq-chip", shiny::icon("chart-area"),    "Graphiques"),
                                               shiny::span(class = "sq-chip", shiny::icon("map"),           "Carte ICES")
                                    ),
                                    
                                    shiny::fluidRow(
                                      shiny::column(8,
                                                    shiny::actionButton("sq_run_global", "Lancer l'analyse complète",
                                                                        icon  = shiny::icon("play-circle"),
                                                                        class = "btn btn-sq-global"
                                                    )
                                      ),
                                      shiny::column(4,
                                                    shiny::downloadButton("sq_export_global", "Tout exporter (ZIP)",
                                                                          icon  = shiny::icon("file-archive"),
                                                                          class = "btn btn-sq-primary",
                                                                          style = "width:100%; height:46px; font-size:12px; font-weight:600;"
                                                    )
                                      )
                                    ),
                                    
                                    shiny::uiOutput("sq_global_status")
)

# =============================================================================
# ASSEMBLAGE FINAL
# =============================================================================

tab_quota <- bslib::nav_panel(
  title = "Analyses complémentaires",
  icon  = shiny::icon("gauge"),
  
  quota_css,
  
  shiny::br(),
  sq_analyse_globale_ui,
  shiny::br(),
  
  shiny::div(class = "sq-tabs-wrap",
             shiny::tabsetPanel(id = "sq_tabs",
                                sq_tab_donnees,
                                sq_tab_engins,
                                sq_tab_numerique,
                                sq_tab_depassements,
                                sq_tab_quotas,
                                sq_tab_visu
             )
  ),
  shiny::br()
)