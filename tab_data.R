# =============================================================================
# tab_data.R — UI onglet Gestion de la donnée (thème sombre CRPMEM)
# =============================================================================

tab_data <- bslib::nav_panel(
  title = "Gestion de la donnée",
  icon  = shiny::icon("database"),
  
  shiny::tags$style(shiny::HTML("

    /* ---- Cards (réutilise dyn-card pour cohérence) ---- */
    .data-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      padding: 16px 18px;
      margin-bottom: 14px;
    }
    .data-card-title {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .06em;
      color: #7FB3D3;
      margin-bottom: 10px;
    }

    /* ---- Barre d'action principale ---- */
    .data-action-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 14px;
    }

    /* ---- Boutons d'action (violet pour opérations destructives) ---- */
    .btn-data-action {
      background-color: #0B2A3D !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 6px 12px !important;
      transition: 0.2s;
    }
    .btn-data-action:hover { background-color: #123A52 !important; }

    .btn-data-danger {
      background-color: #4A1020 !important;
      color: #EAF2F8 !important;
      border: 1px solid #7B1535 !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 6px 12px !important;
    }
    .btn-data-danger:hover { background-color: #7B1535 !important; }

    .btn-data-primary {
      background-color: #0077B6 !important;
      color: #fff !important;
      border: none !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 6px 12px !important;
    }
    .btn-data-primary:hover { background-color: #005F8E !important; }

    .btn-routine {
      background: linear-gradient(135deg, #0077B6, #2E9E6B) !important;
      color: #fff !important;
      border: none !important;
      border-radius: 8px !important;
      font-size: 13px !important;
      font-weight: 600;
      padding: 9px 18px !important;
      width: 100%;
      margin-top: 4px;
    }
    .btn-routine:hover { opacity: 0.88; }

    /* ---- Badge type colonne ---- */
    .col-badge {
      display: inline-block;
      font-size: 9px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .05em;
      padding: 2px 6px;
      border-radius: 4px;
      margin-left: 5px;
      vertical-align: middle;
    }
    .col-badge-num  { background:#0077B6; color:#fff; }
    .col-badge-chr  { background:#2E9E6B; color:#fff; }
    .col-badge-fct  { background:#9B59B6; color:#fff; }
    .col-badge-dat  { background:#E07B39; color:#fff; }
    .col-badge-lgl  { background:#7FB3D3; color:#061A2B; }
    .col-badge-oth  { background:#123A52; color:#EAF2F8; }

    /* ---- Info résumé colonnes ---- */
    .col-info-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 6px 8px;
      border-radius: 6px;
      margin-bottom: 4px;
      background: #061A2B;
      border: 1px solid #0D2C40;
      font-size: 12px;
      cursor: pointer;
      transition: background 0.15s;
    }
    .col-info-row:hover { background: #123A52; }
    .col-info-row.selected { border-color: #0077B6; background: #0B2A3D; }

    /* ---- Modal dark ---- */
    .modal-content {
      background-color: #0B2A3D !important;
      color: #EAF2F8 !important;
      border: 1px solid #123A52 !important;
    }
    .modal-header { border-bottom: 1px solid #123A52 !important; }
    .modal-footer { border-top: 1px solid #123A52 !important; }
    .modal-title  { color: #EAF2F8 !important; font-weight: 600; }
    .btn-close    { filter: invert(1) !important; }

    /* ---- Tabs dark ---- */
    .nav-tabs { border-bottom: 1px solid #123A52 !important; }
    .nav-tabs .nav-link {
      color: #7FB3D3 !important;
      border: none !important;
      border-bottom: 2px solid transparent !important;
    }
    .nav-tabs .nav-link.active {
      background: transparent !important;
      color: #EAF2F8 !important;
      border-bottom: 2px solid #0077B6 !important;
      font-weight: 600;
    }

    /* ---- Notification opération ---- */
    .data-op-info {
      font-size: 11px;
      color: #7FB3D3;
      padding: 6px 8px;
      background: #061A2B;
      border-radius: 6px;
      border-left: 3px solid #0077B6;
      margin-top: 8px;
    }

    /* ---- Pastilles de filtres actifs (supprimables) ---- */
    .filter-pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      font-weight: 500;
      color: #EAF2F8;
      background: #123A52;
      border: 1px solid #1D4E6D;
      border-radius: 14px;
      padding: 4px 6px 4px 10px;
    }
    .filter-pill-remove {
      background: transparent;
      border: none;
      color: #7FB3D3;
      font-size: 14px;
      line-height: 1;
      cursor: pointer;
      padding: 0 4px;
      border-radius: 50%;
      transition: 0.15s;
    }
    .filter-pill-remove:hover {
      background: #7B1535;
      color: #fff;
    }

    /* ---- Historique des opérations ---- */
    .op-history-item {
      font-size: 11px;
      color: #A9B7C6;
      padding: 4px 8px;
      border-left: 2px solid #2E9E6B;
      margin-bottom: 4px;
    }

    /* ---- Table preview ---- */
    .data-table-wrapper {
      overflow-x: auto;
      border-radius: 8px;
    }

    /* ---- Slider dark ---- */
    .irs--shiny .irs-bar { background: #0077B6 !important; }
    .irs--shiny .irs-handle { background: #0077B6 !important; border-color: #0077B6 !important; }
    .irs--shiny .irs-from, .irs--shiny .irs-to,
    .irs--shiny .irs-single { background: #0077B6 !important; }

    /* ---- Checkbox list ---- */
    .shiny-input-checkboxgroup label {
      font-size: 12px !important;
      color: #C9D6DF !important;
    }

  ")),
  
  shiny::fluidRow(
    
    # =========================================================
    # COL GAUCHE — Import + Outils
    # =========================================================
    shiny::column(3,
                  
                  # --- Import fichier principal ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("upload"), " Import fichier"),
                             shiny::fileInput("data_fichier", label = NULL,
                                              accept   = c(".csv", ".tsv", ".txt", ".xlsx",
                                                           ".xls", ".rds", ".json"),
                                              multiple = TRUE,
                                              placeholder = "CSV, XLSX, RDS…",
                                              buttonLabel = "Parcourir"),
                             shiny::uiOutput("data_info_fichier")
                  ),
                  
                  # --- Options CSV (affiché si CSV détecté) ---
                  shiny::uiOutput("data_csv_options_ui"),
                  
                  # --- Routine automatique ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("magic"), " Traitement automatique"),
                             shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                             "Routine de traitement"),
                             shiny::uiOutput("data_routine_select_ui"),
                             shiny::uiOutput("data_routine_desc_ui"),
                             shiny::actionButton("data_routine", "Lancer la routine",
                                                 icon  = shiny::icon("play-circle"),
                                                 class = "btn btn-sm btn-routine"),
                             shiny::uiOutput("data_routine_status")
                  ),
                  
                  # --- Fusion de fichiers additionnels ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("code-merge"), " Fusionner un fichier"),
                             shiny::fileInput("data_fichier2", label = NULL,
                                              accept   = c(".csv", ".tsv", ".txt", ".xlsx",
                                                           ".xls", ".rds"),
                                              multiple = TRUE,
                                              placeholder = "Fichier(s) à joindre",
                                              buttonLabel = "Parcourir"),
                             shiny::uiOutput("data_merge_ui")
                  ),
                  
                  # --- Export ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("download"), " Exporter"),
                             shiny::div(class = "data-action-bar",
                                        shiny::downloadButton("data_export_csv",  "CSV",
                                                              class = "btn btn-sm btn-data-action"),
                                        shiny::downloadButton("data_export_rds",  "RDS",
                                                              class = "btn btn-sm btn-data-action"),
                                        shiny::downloadButton("data_export_xlsx", "XLSX",
                                                              class = "btn btn-sm btn-data-primary")
                             ),
                             shiny::br(),
                             shiny::uiOutput("data_export_info")
                  ),
                  
                  # --- Exports automatisés ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("magic"), " Exports automatis\u00e9s"),
                             shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                             "Type d'export"),
                             shiny::uiOutput("data_export_auto_select_ui"),
                             shiny::uiOutput("data_export_auto_config_ui"),
                             shiny::uiOutput("data_export_auto_status_ui"),
                             shiny::uiOutput("data_export_auto_btn_ui")
                  ),
                  
                  # --- Historique des opérations ---
                  shiny::div(class = "data-card",
                             shiny::div(class = "data-card-title",
                                        shiny::icon("history"), " Historique"),
                             shiny::div(style = "max-height:180px; overflow-y:auto;",
                                        shiny::uiOutput("data_historique")
                             ),
                             shiny::br(),
                             shiny::actionButton("data_undo", "Annuler dernière op.",
                                                 icon  = shiny::icon("undo"),
                                                 class = "btn btn-sm btn-data-danger",
                                                 style = "width:100%;")
                  )
                  
    ),
    
    # =========================================================
    # COL DROITE — Tableau + Opérations
    # =========================================================
    shiny::column(9,
                  
                  # --- Barre d'opérations sur colonnes ---
                  shiny::uiOutput("data_ops_bar"),
                  
                  # --- Tabs principales ---
                  shiny::tabsetPanel(id = "data_onglets", type = "tabs",
                                     
                                     # ---- Aperçu des données ----
                                     shiny::tabPanel("Aperçu des données",
                                                     shiny::br(),
                                                     
                                                     # KPI résumé
                                                     shiny::uiOutput("data_kpi_row"),
                                                     
                                                     shiny::div(class = "data-card",
                                                                shiny::div(class = "data-card-title",
                                                                           shiny::icon("eye"), " Tableau"),
                                                                # Filtre rapide global
                                                                shiny::fluidRow(
                                                                  shiny::column(6,
                                                                                shiny::textInput("data_search_global", label = NULL,
                                                                                                 placeholder = "Recherche rapide dans le tableau…")
                                                                  ),
                                                                  shiny::column(3,
                                                                                shiny::numericInput("data_nrows_preview", label = NULL,
                                                                                                    value = 100, min = 10, max = 10000, step = 50)
                                                                  ),
                                                                  shiny::column(3,
                                                                                shiny::tags$small(style = "color:#7FB3D3; line-height:36px;",
                                                                                                  "lignes affichées")
                                                                  )
                                                                ),
                                                                shiny::div(class = "data-table-wrapper",
                                                                           DT::dataTableOutput("data_table_preview")
                                                                )
                                                     )
                                     ),
                                     
                                     # ---- Colonnes ----
                                     shiny::tabPanel("Colonnes",
                                                     shiny::br(),
                                                     shiny::fluidRow(
                                                       # Liste des colonnes avec badges type
                                                       shiny::column(5,
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("columns"), " Colonnes du fichier"),
                                                                                shiny::div(style = "margin-bottom:8px;",
                                                                                           shiny::div(class = "data-action-bar",
                                                                                                      shiny::actionButton("data_col_select_all", "Tout sélectionner",
                                                                                                                          class = "btn btn-sm btn-data-action"),
                                                                                                      shiny::actionButton("data_col_deselect_all", "Tout désélectionner",
                                                                                                                          class = "btn btn-sm btn-data-action")
                                                                                           )
                                                                                ),
                                                                                shiny::div(style = "max-height:500px; overflow-y:auto;",
                                                                                           shiny::uiOutput("data_col_list")
                                                                                )
                                                                     )
                                                       ),
                                                       
                                                       # Opérations sur la/les colonne(s) sélectionnée(s)
                                                       shiny::column(7,
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("tools"), " Opérations sur la sélection"),
                                                                                shiny::uiOutput("data_col_ops_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("plus-circle"), " Créer une nouvelle colonne"),
                                                                                shiny::uiOutput("data_new_col_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("calendar-alt"), " G\u00e9rer les dates"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Convertissez une colonne en Date et extrayez ann\u00e9e, mois, trimestre, semaine\u2026"),
                                                                                shiny::uiOutput("data_date_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("exchange-alt"), " Conversion d'unit\u00e9s"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "S\u00e9lectionnez une colonne num\u00e9rique, choisissez l'unit\u00e9 source et cible."),
                                                                                shiny::uiOutput("data_conv_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("ship"), " Colonne M\u00e9tier"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "G\u00e9n\u00e8re une colonne m\u00e9tier (large et/ou d\u00e9taill\u00e9) depuis engin_cod via le r\u00e9f\u00e9rentiel."),
                                                                                shiny::uiOutput("data_metier_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("compress-arrows-alt"), " Fusion de colonnes"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Comble les NA de la colonne 1 avec les valeurs de la colonne 2 (col1 \u2192 priorit\u00e9, col2 \u2192 appoint)."),
                                                                                shiny::uiOutput("data_col_merge_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("code-branch"), " Cr\u00e9er une colonne (Case When)"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Cr\u00e9ez une nouvelle colonne en d\u00e9finissant des r\u00e8gles conditionnelles sur une colonne de r\u00e9f\u00e9rence (\u00e9quivalent dplyr::case_when)."),
                                                                                shiny::uiOutput("data_casewhen_panel")
                                                                     ),
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("layer-group"), " Regrouper la donn\u00e9e (Group By)"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Agr\u00e9gez le tableau en regroupant par une ou plusieurs colonnes et en choisissant les m\u00e9triques \u00e0 calculer."),
                                                                                shiny::uiOutput("data_groupby_panel")
                                                                     )
                                                       )
                                                     )
                                     ),
                                     
                                     # ---- Filtres ----
                                     shiny::tabPanel("Filtres",
                                                     shiny::br(),
                                                     shiny::div(class = "data-card",
                                                                shiny::div(class = "data-card-title",
                                                                           shiny::icon("filter"), " Filtrer les lignes"),
                                                                shiny::p(style = "font-size:11px; color:#7FB3D3;",
                                                                         "Les filtres s'appliquent successivement. Utilisez le bouton
               'Appliquer' pour ajouter un filtre actif, puis retirez-le individuellement via sa pastille ci-dessous (ou 'Réinitialiser' pour tout effacer)."),
                                                                shiny::uiOutput("data_filtres_dynamiques"),
                                                                shiny::br(),
                                                                shiny::div(class = "data-action-bar",
                                                                           shiny::actionButton("data_apply_filters", "Ajouter le(s) filtre(s)",
                                                                                               icon  = shiny::icon("check"),
                                                                                               class = "btn btn-sm btn-data-primary"),
                                                                           shiny::actionButton("data_reset_filters", "Réinitialiser",
                                                                                               icon  = shiny::icon("times"),
                                                                                               class = "btn btn-sm btn-data-danger")
                                                                ),
                                                                shiny::uiOutput("data_filter_summary")
                                                     ),
                                                     
                                                     shiny::div(class = "data-card",
                                                                shiny::div(class = "data-card-title",
                                                                           shiny::icon("trash-alt"), " Supprimer des lignes"),
                                                                shiny::fluidRow(
                                                                  shiny::column(5,
                                                                                shiny::uiOutput("data_rm_col_sel"),
                                                                                shiny::uiOutput("data_rm_val_sel")
                                                                  ),
                                                                  shiny::column(3,
                                                                                shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                                                                                "Condition"),
                                                                                shiny::selectInput("data_rm_condition", label = NULL,
                                                                                                   choices = c("égal à"       = "eq",
                                                                                                               "différent de" = "neq",
                                                                                                               "contient"     = "contains",
                                                                                                               "est NA"       = "isna",
                                                                                                               "n'est pas NA" = "notna",
                                                                                                               "> (numérique)"= "gt",
                                                                                                               "< (numérique)"= "lt"))
                                                                  ),
                                                                  shiny::column(4,
                                                                                shiny::br(),
                                                                                shiny::actionButton("data_rm_rows_go", "Supprimer ces lignes",
                                                                                                    icon  = shiny::icon("trash"),
                                                                                                    class = "btn btn-sm btn-data-danger",
                                                                                                    style = "width:100%; margin-top:4px;")
                                                                  )
                                                                )
                                                     )
                                     ),
                                     
                                     # ---- Résumé statistique ----
                                     shiny::tabPanel("Résumé",
                                                     shiny::br(),
                                                     shiny::div(class = "data-card",
                                                                shiny::div(class = "data-card-title",
                                                                           shiny::icon("chart-bar"), " Statistiques descriptives"),
                                                                DT::dataTableOutput("data_summary_table")
                                                     )
                                     ),
                                     
                                     # ---- Valeurs uniques ----
                                     shiny::tabPanel("Valeurs uniques",
                                                     shiny::br(),
                                                     shiny::div(class = "data-card",
                                                                shiny::div(class = "data-card-title",
                                                                           shiny::icon("list-ol"), " Valeurs uniques par colonne"),
                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                         "Sélectionnez une colonne pour voir toutes ses valeurs distinctes et leur effectif."),
                                                                shiny::fluidRow(
                                                                  shiny::column(6,
                                                                                shiny::uiOutput("data_uniques_col_sel")
                                                                  ),
                                                                  shiny::column(6,
                                                                                shiny::div(style = "line-height:36px;",
                                                                                           shiny::uiOutput("data_uniques_kpi")
                                                                                )
                                                                  )
                                                                ),
                                                                shiny::div(class = "data-table-wrapper",
                                                                           DT::dataTableOutput("data_uniques_table")
                                                                )
                                                     )
                                     ),
                                     
                                     # ---- Correction de la donnée engin ----
                                     shiny::tabPanel("Correction de la donnée engin",
                                                     shiny::br(),
                                                     
                                                     shiny::fluidRow(
                                                       
                                                       # ── Colonne gauche : mapping + actions ──────────────────────
                                                       shiny::column(4,
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("columns"), " Mapping des colonnes"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Indiquez quelles colonnes du tableau courant correspondent aux champs attendus."),
                                                                                shiny::uiOutput("data_engin_mapping_ui")
                                                                     ),
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("database"), " Base des incohérences connues"),
                                                                                shiny::uiOutput("data_engin_base_info"),
                                                                                shiny::br(),
                                                                                shiny::actionButton("data_engin_reload_base", "Recharger la base",
                                                                                                    icon  = shiny::icon("sync"),
                                                                                                    class = "btn btn-sm btn-data-action",
                                                                                                    style = "width:100%;")
                                                                     ),
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("search"), " Analyse de cohérence"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Détecte, par navire et par espèce, les engins non cohérents (référentiel du Suivi des quotas)."),
                                                                                shiny::actionButton("data_engin_run", "Lancer l'analyse",
                                                                                                    icon  = shiny::icon("play-circle"),
                                                                                                    class = "btn btn-sm btn-routine",
                                                                                                    style = "width:100%;"),
                                                                                shiny::br(), shiny::br(),
                                                                                shiny::uiOutput("data_engin_kpi")
                                                                     ),
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("magic"), " Appliquer la suggestion"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Ajoute au tableau une colonne 'engin_sug' : engin corrigé si connu, sinon engin déclaré suffixé d'une * si incohérent."),
                                                                                shiny::actionButton("data_engin_apply_sug", "Créer la colonne engin_sug",
                                                                                                    icon  = shiny::icon("plus-circle"),
                                                                                                    class = "btn btn-sm btn-data-primary",
                                                                                                    style = "width:100%;")
                                                                     )
                                                                     
                                                       ),
                                                       
                                                       # ── Colonne droite : résultats ──────────────────────────────
                                                       shiny::column(8,
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("exclamation-triangle"), " Navires non encore référencés comme incohérents"),
                                                                                shiny::p(style = "font-size:11px; color:#7FB3D3; margin-bottom:8px;",
                                                                                         "Ces combinaisons navire / engin / espèce sont incohérentes au regard du référentiel mais absentes de la base. Exportez-les pour les transmettre à l'admin."),
                                                                                shiny::div(class = "data-action-bar",
                                                                                           shiny::downloadButton("data_engin_export_nouveaux", "Exporter les nouveaux cas",
                                                                                                                 class = "btn btn-sm btn-data-primary")
                                                                                ),
                                                                                shiny::br(),
                                                                                shiny::div(class = "data-table-wrapper",
                                                                                           DT::dataTableOutput("data_engin_table_nouveaux")
                                                                                )
                                                                     ),
                                                                     
                                                                     shiny::div(class = "data-card",
                                                                                shiny::div(class = "data-card-title",
                                                                                           shiny::icon("list"), " Toutes les incohérences détectées"),
                                                                                shiny::div(class = "data-table-wrapper",
                                                                                           DT::dataTableOutput("data_engin_table_toutes")
                                                                                )
                                                                     )
                                                                     
                                                       )
                                                       
                                                     )
                                     )
                                     
                  ) # fin tabsetPanel
    )
  ), # fin fluidRow
  
)