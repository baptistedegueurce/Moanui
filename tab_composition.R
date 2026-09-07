# =============================================================================
# tab_composition.R — UI onglet Composition de graphiques
# Permet d'assembler plusieurs graphiques (viz + carte + vms) en une planche.
# =============================================================================

tab_composition <- bslib::nav_panel(
  title = "Composition",
  icon  = shiny::icon("table-cells-large"),
  
  shiny::tags$style(shiny::HTML("

    /* ====== Cards ====== */
    .compo-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      padding: 14px 16px;
      margin-bottom: 12px;
      overflow: hidden;
    }
    .compo-card-title {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .06em;
      color: #7FB3D3;
      margin-bottom: 10px;
    }
    .compo-param-label {
      font-size: 11px;
      color: #7FB3D3;
      font-weight: 600;
      display: block;
      margin-bottom: 3px;
    }

    /* ====== Boutons ====== */
    .btn-compo-primary {
      background-color: #0077B6 !important;
      color: #fff !important;
      border: none !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 600;
      padding: 8px 14px !important;
      transition: background-color 0.2s;
    }
    .btn-compo-primary:hover { background-color: #005F8E !important; }

    .btn-compo-secondary {
      background-color: #0B2A3D !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 12px !important;
      font-weight: 500;
      padding: 7px 12px !important;
    }
    .btn-compo-secondary:hover { background-color: #123A52 !important; }

    .btn-compo-danger {
      background-color: #4A1020 !important;
      color: #EAF2F8 !important;
      border: 1px solid #7A1030 !important;
      border-radius: 6px !important;
      font-size: 11px !important;
      font-weight: 500;
      padding: 5px 10px !important;
    }
    .btn-compo-danger:hover { background-color: #7A1030 !important; }

    .btn-compo-export {
      background-color: #123A52 !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 11px !important;
      font-weight: 500;
      padding: 6px 10px !important;
      width: 100%;
      margin-bottom: 0;
    }
    .btn-compo-export:hover { background-color: #1D4E6D !important; }

    /* ====== Galerie ====== */
    .compo-gallery {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 8px;
      width: 100%;
      min-width: 0;
    }
    .compo-gallery > * { min-width: 0; overflow: hidden; }

    .compo-thumb {
      background: #061A2B;
      border: 1px solid #1D4E6D;
      border-radius: 8px;
      padding: 8px;
      cursor: pointer;
      transition: border-color 0.15s, background 0.15s;
      position: relative;
      box-sizing: border-box;
      overflow: hidden;
      min-width: 0;
    }
    .compo-thumb:hover       { border-color: #0077B6; background: #0B2A3D; }
    .compo-thumb.selected    { border-color: #0077B6; background: #0B2A3D; box-shadow: 0 0 0 2px #0077B6; }
    .compo-thumb.in-slot     { border-color: #2E9E6B; }

    .compo-thumb-label {
      font-size: 10px;
      color: #7FB3D3;
      font-weight: 600;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      margin-bottom: 2px;
    }
    .compo-thumb-meta { font-size: 9px; color: #4A7A99; }

    .compo-thumb-del {
      position: absolute;
      top: 4px; right: 4px;
      background: #4A1020;
      border: none;
      border-radius: 3px;
      color: #EAF2F8;
      font-size: 9px;
      padding: 1px 5px;
      cursor: pointer;
      opacity: 0;
      transition: opacity 0.15s;
    }
    .compo-thumb:hover .compo-thumb-del { opacity: 1; }

    /* ====== Slots ====== */
    .compo-slots { display: flex; flex-direction: column; gap: 8px; }

    .compo-slot {
      background: #061A2B;
      border: 1px dashed #1D4E6D;
      border-radius: 8px;
      padding: 10px 12px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .compo-slot-num  { font-size: 18px; font-weight: 700; color: #0077B6; min-width: 28px; text-align: center; }
    .compo-slot-label { font-size: 11px; color: #EAF2F8; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

    .compo-slot-up, .compo-slot-down, .compo-slot-rm {
      background: transparent;
      border: 1px solid #1D4E6D;
      border-radius: 4px;
      color: #7FB3D3;
      font-size: 10px;
      padding: 2px 6px;
      cursor: pointer;
      line-height: 1;
    }
    .compo-slot-rm { border-color: #4A1020; color: #E07B39; }
    .compo-slot-up:hover, .compo-slot-down:hover { background: #123A52; }
    .compo-slot-rm:hover  { background: #4A1020; }

    /* ====== Miniature ====== */
    .compo-mini-preview {
      width: 100%; height: 90px;
      background: #0B2A3D;
      border-radius: 4px;
      display: flex; align-items: center; justify-content: center;
      overflow: hidden;
      margin-bottom: 4px;
    }
    .compo-mini-preview img {
      width: 100%; height: 90px;
      object-fit: contain; display: block;
    }

    /* ====== Zone résultat ====== */
    .compo-result-wrap {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 8px;
      padding: 10px 10px 24px 10px;
      min-height: 500px;
      width: 100%;
      overflow: auto;
    }

    /* ====== Inputs dans compo ====== */
    .compo-card .selectize-input {
      background: #061A2B !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
      min-height: 32px !important;
      font-size: 12px !important;
    }
    .compo-card .selectize-dropdown {
      background: #0B2A3D !important;
      border: 1px solid #1D4E6D !important;
      color: #EAF2F8 !important;
    }
    .compo-card .selectize-dropdown-content .option:hover { background: #123A52 !important; }
    .compo-card label  { color: #C9D6DF !important; font-size: 12px !important; }
    .compo-card .form-control {
      font-size: 12px !important;
      background: #061A2B !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
    }
    .compo-card .shiny-input-container { margin-bottom: 0; }

    /* ====== Badges source ====== */
    .compo-badge-viz {
      background: #0077B6; color: #fff;
      font-size: 9px; font-weight: 600;
      padding: 1px 6px; border-radius: 8px; margin-right: 4px;
    }
    .compo-badge-map {
      background: #2E9E6B; color: #fff;
      font-size: 9px; font-weight: 600;
      padding: 1px 6px; border-radius: 8px; margin-right: 4px;
    }
    .compo-badge-vms {
      background: #7B3FA0; color: #fff;
      font-size: 9px; font-weight: 600;
      padding: 1px 6px; border-radius: 8px; margin-right: 4px;
    }
    .compo-badge-img {
      background: #B05A00; color: #fff;
      font-size: 9px; font-weight: 600;
      padding: 1px 6px; border-radius: 8px; margin-right: 4px;
    }

    /* ====== Import PNG ====== */
    .compo-card .shiny-input-container.shiny-input-container-inline { width: 100%; }
    .compo-card .input-group {
      display: flex; gap: 6px; align-items: center; width: 100%;
    }
    .compo-card .btn-file {
      background: #123A52 !important;
      color: #EAF2F8 !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      font-size: 11px !important;
      padding: 5px 10px !important;
      white-space: nowrap;
    }
    .compo-card .btn-file:hover { background: #1D4E6D !important; }
    .compo-card .form-control[readonly] {
      font-size: 11px !important;
      color: #4A7A99 !important;
      background: #061A2B !important;
      border: 1px solid #1D4E6D !important;
      border-radius: 6px !important;
      padding: 5px 8px !important;
    }

    /* ====== Info vide ====== */
    .compo-empty-info {
      text-align: center;
      padding: 30px 10px;
      color: #4A7A99;
      font-size: 12px;
      line-height: 1.7;
    }
    .compo-empty-info i { font-size: 32px; margin-bottom: 10px; display: block; }

  ")),
  
  shiny::fluidRow(
    
    # =========================================================================
    # COL GAUCHE — Galerie + Slots
    # =========================================================================
    shiny::column(3,
                  
                  # ── Galerie des graphiques en mémoire ──────────────────────────────────
                  shiny::div(class = "compo-card",
                             
                             shiny::div(class = "compo-card-title",
                                        shiny::icon("images"), " Graphiques en memoire",
                                        shiny::tags$span(
                                          style = "float:right; font-size:10px; color:#4A7A99;",
                                          "(20 max)"
                                        )
                             ),
                             
                             shiny::p(
                               style = "font-size:10px; color:#4A7A99; margin-bottom:8px;",
                               "Les graphiques affiches dans 'Representation des donnees',",
                               " 'Cartographie' ou 'VMS' sont automatiquement captures ici.",
                               " Cliquez pour selectionner."
                             ),
                             
                             # ── Import PNG externe ────────────────────────────────────────
                             shiny::div(
                               style = "margin-bottom: 8px;",
                               shiny::fileInput(
                                 "compo_import_png",
                                 label = NULL,
                                 accept = c("image/png", "image/jpeg", ".png", ".jpg", ".jpeg"),
                                 multiple = TRUE,
                                 placeholder = "Importer PNG / JPG...",
                                 buttonLabel = shiny::tagList(shiny::icon("upload"), " Importer")
                               )
                             ),
                             
                             shiny::uiOutput("compo_gallery_ui"),
                             
                             shiny::br(),
                             shiny::actionButton(
                               "compo_clear_gallery", "Vider la galerie",
                               icon  = shiny::icon("trash"),
                               class = "btn btn-sm btn-compo-danger",
                               style = "width:100%;"
                             )
                  ),
                  
                  # ── Slots de la composition ────────────────────────────────────────────
                  shiny::div(class = "compo-card",
                             
                             shiny::div(class = "compo-card-title",
                                        shiny::icon("layer-group"), " Graphiques a composer"
                             ),
                             
                             shiny::p(
                               style = "font-size:10px; color:#4A7A99; margin-bottom:8px;",
                               "Selectionnez des graphiques dans la galerie puis ajoutez-les.",
                               " Reordonnez avec les fleches."
                             ),
                             
                             shiny::uiOutput("compo_slots_ui"),
                             
                             shiny::br(),
                             shiny::fluidRow(
                               shiny::column(6,
                                             shiny::actionButton(
                                               "compo_clear_slots", "Vider",
                                               icon  = shiny::icon("trash"),
                                               class = "btn btn-sm btn-compo-danger",
                                               style = "width:100%;"
                                             )
                               ),
                               shiny::column(6,
                                             shiny::actionButton(
                                               "compo_add_selected", "Ajouter \u2192",
                                               icon  = shiny::icon("plus"),
                                               class = "btn btn-sm btn-compo-secondary",
                                               style = "width:100%;"
                                             )
                               )
                             )
                  )
                  
    ), # fin col gauche
    
    # =========================================================================
    # COL DROITE — Paramètres + Aperçu
    # =========================================================================
    shiny::column(9,
                  
                  # ── Paramètres globaux de la composition ──────────────────────────────
                  shiny::div(class = "compo-card",
                             
                             shiny::div(class = "compo-card-title",
                                        shiny::icon("sliders-h"), " Parametres de la composition"
                             ),
                             
                             # Ligne 1 : titres
                             shiny::fluidRow(
                               shiny::column(4,
                                             shiny::tags$label(class = "compo-param-label", "Titre"),
                                             shiny::textInput("compo_titre", label = NULL,
                                                              placeholder = "Ex : Bilan debarquements 2024")
                               ),
                               shiny::column(4,
                                             shiny::tags$label(class = "compo-param-label", "Sous-titre (optionnel)"),
                                             shiny::textInput("compo_soustitre", label = NULL,
                                                              placeholder = "Contexte ou methode...")
                               ),
                               shiny::column(4,
                                             shiny::tags$label(class = "compo-param-label", "Note de bas de page"),
                                             shiny::textInput("compo_caption", label = NULL,
                                                              placeholder = "Source : SACROIS / DGAMPA")
                               )
                             ),
                             
                             # Ligne 2 : disposition et légendes
                             shiny::fluidRow(
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Colonnes"),
                                             shiny::numericInput("compo_ncol", label = NULL,
                                                                 value = 2, min = 1, max = 6, step = 1)
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Etiquettes panneaux"),
                                             shiny::selectInput("compo_tag_style", label = NULL,
                                                                choices = c(
                                                                  "Aucune"        = "none",
                                                                  "A, B, C..."    = "ABC",
                                                                  "a, b, c..."    = "abc",
                                                                  "1, 2, 3..."    = "123",
                                                                  "i, ii, iii..." = "roman"
                                                                ),
                                                                selected = "ABC")
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Position etiquettes"),
                                             shiny::selectInput("compo_tag_pos", label = NULL,
                                                                choices = c(
                                                                  "Haut gauche"  = "topleft",
                                                                  "Haut droit"   = "topright",
                                                                  "Bas gauche"   = "bottomleft",
                                                                  "Bas droit"    = "bottomright"
                                                                ),
                                                                selected = "topleft")
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Legende"),
                                             shiny::selectInput("compo_legend", label = NULL,
                                                                choices = c(
                                                                  "Independantes"    = "keep",
                                                                  "Commune (bas)"    = "bottom",
                                                                  "Commune (droite)" = "right",
                                                                  "Commune (gauche)" = "left",
                                                                  "Commune (haut)"   = "top",
                                                                  "Ind. positionnees en bas"   = "keep_bottom",
                                                                  "Ind. positionnees a droite" = "keep_right",
                                                                  "Masquees"         = "none"
                                                                ),
                                                                selected = "keep")
                               )
                             ),
                             
                             # Ligne 3 : export
                             shiny::fluidRow(
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Largeur export (px)"),
                                             shiny::numericInput("compo_largeur", label = NULL,
                                                                 value = 2400, min = 800, max = 6000, step = 200)
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Hauteur export (px)"),
                                             shiny::numericInput("compo_hauteur", label = NULL,
                                                                 value = 1600, min = 600, max = 5000, step = 200)
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Resolution (DPI)"),
                                             shiny::numericInput("compo_dpi", label = NULL,
                                                                 value = 150, min = 72, max = 300, step = 25)
                               ),
                               shiny::column(3,
                                             shiny::tags$label(class = "compo-param-label", "Espacement (cm)"),
                                             shiny::numericInput("compo_gap", label = NULL,
                                                                 value = 0.5, min = 0, max = 3, step = 0.1)
                               )
                             )
                  ),
                  
                  # ── Légendes individuelles par slot ───────────────────────────────────
                  shiny::uiOutput("compo_slots_legends_ui"),
                  
                  # ── Boutons action ─────────────────────────────────────────────────────
                  shiny::div(class = "compo-card",
                             shiny::fluidRow(
                               shiny::column(4,
                                             shiny::actionButton(
                                               "compo_refresh", "Composer et apercevoir",
                                               icon  = shiny::icon("play"),
                                               class = "btn btn-sm btn-compo-primary",
                                               style = "width:100%; font-size:13px; padding:10px;"
                                             )
                               ),
                               shiny::column(4,
                                             shiny::downloadButton(
                                               "compo_export_png", "Exporter PNG haute resolution",
                                               class = "btn btn-sm btn-compo-export"
                                             )
                               ),
                               shiny::column(4,
                                             shiny::downloadButton(
                                               "compo_export_pdf", "Exporter PDF",
                                               class = "btn btn-sm btn-compo-export"
                                             )
                               )
                             )
                  ),
                  
                  # ── Aperçu ─────────────────────────────────────────────────────────────
                  shiny::div(class = "compo-result-wrap",
                             shiny::uiOutput("compo_preview_ui")
                  )
                  
    ) # fin col droite
  ) # fin fluidRow
)