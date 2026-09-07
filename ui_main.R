# =============================================================================
# ui_main.R — UI principale (thème sombre CRPMEM)
# =============================================================================

ui_main <- function() {
  source("R/ui/tab_home.R")
  source("R/ui/tab_data.R")      # ← NOUVEAU
  source("R/ui/tab_viz.R")
  source("R/ui/tab_map.R")
  source("R/ui/tab_quota.R")
  source("R/ui/tab_vms.R")
  source("R/ui/tab_composition.R")
  
  tagList(
    bslib::page_navbar(
      title = tagList(
        tags$img(
          src = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAASwAAADcCAYAAADKmJzYAAAEs2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4KPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNS41LjAiPgogPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iCiAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUuY29tL2V4aWYvMS4wLyIKICAgIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIKICAgIHhtbG5zOnhtcD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wLyIKICAgIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIgogICAgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIKICAgdGlmZjpJbWFnZUxlbmd0aD0iMjIwIgogICB0aWZmOkltYWdlV2lkdGg9IjMwMCIKICAgdGlmZjpSZXNvbHV0aW9uVW5pdD0iMiIKICAgdGlmZjpYUmVzb2x1dGlvbj0iNzIuMCIKICAgdGlmZjpZUmVzb2x1dGlvbj0iNzIuMCIKICAgZXhpZjpQaXhlbFhEaW1lbnNpb249IjMwMCIKICAgZXhpZjpQaXhlbFlEaW1lbnNpb249IjIyMCIKICAgZXhpZjpDb2xvclNwYWNlPSIxIgogICBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIgogICBwaG90b3Nob3A6SUNDUHJvZmlsZT0ic1JHQiBJRUM2MTk2Ni0yLjEiCiAgIHhtcDpNb2RpZnlEYXRlPSIyMDIy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",
          height = "30px",
          style  = "margin-right:10px; vertical-align:middle;"
        ),
        "Plateforme d'analyse halieutique"
      ),
      theme = bslib::bs_theme(
        bg        = "#061A2B",
        fg        = "#EAF2F8",
        primary   = "#0077B6",
        base_font = bslib::font_google("Inter"),
        "navbar-padding-y" = "0.6rem"
      ),
      navbar_options = bslib::navbar_options(position = "fixed-top"),
      header = tagList(
        app_shared_css,
        tags$head(
          tags$link(
            rel  = "stylesheet",
            href = "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&display=swap"
          ),
          
          tags$style(HTML("
 
        /* ================================================
           NAVBAR
           ================================================ */
        .navbar {
          background-color: #061A2B !important;
          border-bottom: 1px solid #0E3A56 !important;
          padding: 0 16px !important;
        }
        .navbar-brand {
          color: #EAF2F8 !important;
          font-weight: 600 !important;
          font-size: 15px !important;
          display: flex;
          align-items: center;
        }
        .nav-link {
          color: #A9C4D4 !important;
          font-size: 13px !important;
          font-weight: 500 !important;
          padding: 0.6rem 1rem !important;
          transition: color 0.15s ease !important;
        }
        .nav-link:hover {
          color: #EAF2F8 !important;
        }
        .nav-link.active {
          color: #EAF2F8 !important;
          border-bottom: 2px solid #0077B6 !important;
          background: transparent !important;
        }
 
        /* ================================================
           BASE
           ================================================ */
        body {
          font-family: 'Inter', sans-serif;
          background-color: #061A2B;
          color: #EAF2F8;
          padding-top: 70px !important;
        }
 
        .bslib-page-navbar {
          padding-top: 70px !important;
        }
 
        /* ================================================
           TITRES
           ================================================ */
        h1 { font-size:26px; font-weight:600; color:#EAF2F8; margin-bottom:15px; }
        h2 { font-size:22px; font-weight:600; color:#EAF2F8; margin-bottom:12px; }
        h3 { font-size:18px; font-weight:500; color:#EAF2F8; margin-bottom:10px; }
        h4 { font-size:16px; font-weight:500; color:#C9D6DF; margin-bottom:8px;  }
        p  { font-size:14px; font-weight:300; color:#C9D6DF; line-height:1.5;    }
 
        /* ================================================
           INPUTS
           ================================================ */
        .btn-file {
          background-color: #EAF2F8 !important;
          color: #061A2B !important;
          border: 1px solid #EAF2F8 !important;
        }
        .btn-file:hover {
          background-color: #C9D6DF !important;
          color: #061A2B !important;
        }
        .form-control {
          background-color: #0B2A3D !important;
          color: #EAF2F8 !important;
          border: 1px solid #123A52 !important;
        }
 
        /* ================================================
           DT TABLES
           ================================================ */
        table.dataTable {
          background-color: #0B2A3D !important;
          color: #EAF2F8 !important;
          border: 1px solid #123A52 !important;
          font-size: 12px !important;
        }
        table.dataTable thead {
          background-color: #123A52 !important;
          color: #FFFFFF !important;
        }
        table.dataTable tbody tr { background-color: #0B2A3D !important; }
        table.dataTable tbody tr:hover { background-color: #123A52 !important; }
        .dataTables_wrapper { overflow-x: hidden !important; }
 
        /* ================================================
           KPI (partagé data + dyn)
           ================================================ */
        .hal-kpi {
          text-align: center;
          padding: 12px 8px;
          background: #0B2A3D;
          border: 1px solid #123A52;
          border-radius: 8px;
          margin-bottom: 14px;
        }
        .hal-kpi-val {
          font-size: 22px;
          font-weight: 700;
          color: #0077B6;
        }
        .hal-kpi-lbl {
          font-size: 11px;
          color: #7FB3D3;
          margin-top: 3px;
        }
 
        /* ================================================
           WORKFLOW BAR
           ================================================ */
        .workflow {
          display: flex;
          justify-content: space-between;
          margin: 15px 0 25px 0;
          padding: 10px;
          background-color: #0B2A3D;
          border: 1px solid #123A52;
          border-radius: 8px;
        }
        .step {
          flex: 1;
          text-align: center;
          font-size: 13px;
          padding: 8px;
          color: #A9B7C6;
          border-right: 1px solid #123A52;
        }
        .step:last-child { border-right: none; }
        .step.active {
          color: #FFFFFF;
          font-weight: 600;
          background-color: #0077B6;
          border-radius: 6px;
        }
        .step.done { color: #EAF2F8; font-weight: 500; }
 
        /* ================================================
           BOUTONS GLOBAUX
           ================================================ */
        .btn-success       { background-color: #1E8449 !important; border: none !important; }
        .btn-success:hover { background-color: #196F3D !important; }
 
        #export_folder {
          background-color: #0B2A3D !important;
          color: white !important;
          border: 1px solid #1B4F72 !important;
          border-radius: 6px !important;
          padding: 8px 12px !important;
          font-weight: 500;
        }
        #export_folder:hover { background-color: #123A52 !important; }
 
        /* ================================================
           SELECTIZE GLOBAL
           ================================================ */
        .selectize-control { width: 100% !important; }
        .selectize-input {
          min-height: 38px !important;
          padding: 8px 10px !important;
          font-size: 13px !important;
          background-color: #0B2A3D !important;
          color: #EAF2F8 !important;
          border: 1px solid #123A52 !important;
        }
        .selectize-input > div {
          background-color: #1B4F72 !important;
          color: white !important;
          padding: 3px 7px !important;
          margin: 2px !important;
          border-radius: 4px !important;
        }
        .selectize-input > div .remove { color: white !important; margin-left: 5px !important; }
        .selectize-dropdown {
          background-color: #0B2A3D !important;
          border: 1px solid #1D4E6D !important;
          color: #EAF2F8 !important;
        }
        .selectize-dropdown-content .option:hover { background-color: #123A52 !important; }
 
        /* ================================================
           DROPDOWN MENUS
           ================================================ */
        .tcd-filter-btn {
          background-color: #123A52 !important;
          color: white !important;
          border: 1px solid #1D4E6D !important;
          border-radius: 8px !important;
          padding: 6px 10px !important;
          font-size: 12px !important;
          font-weight: 500;
          min-width: 160px;
          text-align: left;
          transition: 0.2s ease;
        }
        .tcd-filter-btn:hover { background-color: #1D4E6D !important; }
 
        .dropdown-menu {
          background-color: #0B2A3D !important;
          border: 1px solid #123A52 !important;
          border-radius: 10px !important;
          padding: 10px !important;
          box-shadow: none !important;
        }
        .dropdown-menu label,
        .dropdown-menu .control-label,
        .dropdown-menu { color: white !important; }
 
        /* ================================================
           FOOTER GLOBAL — collé en bas de fenêtre
           ================================================ */
        .acc-footer {
          padding: 10px 24px;
          width: 100%;
          box-sizing: border-box;
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 11px;
          color: #2E5A7A;
        }
        .acc-footer strong { color: #5A8FAA; }
        .acc-footer-wrap {
          position: fixed;
          bottom: 0;
          left: 0;
          right: 0;
          z-index: 999;
          width: 100%;
          background-color: #061A2B;
          border-top: 1px solid #0E3A56;
        }
        /* Espace en bas du contenu pour ne pas être caché par le footer fixe */
        body { padding-bottom: 46px !important; }
 
        @media (max-width: 768px) {
          .acc-footer { padding: 10px 16px; flex-direction: column; gap: 4px; text-align: center; }
        }
        
        /* Masquer la scroll bar tout en gardant le scroll possible */
        ::-webkit-scrollbar{
        width: 0px;
        background: transparent
        }
 
      "))
        )),
      tab_home,
      tab_data,       # ← NOUVEAU
      tab_viz,
      tab_map,
      tab_quota,
      tab_vms,
      tab_composition
    ),
    # Footer global stylisé (identique page d'accueil)
    tags$div(class = "acc-footer-wrap",
             tags$div(class = "acc-footer",
                      tags$span(
                        "Plateforme d’analyse halieutique — ",
                        tags$strong("Bretagne Pêches"),
                        " © ", format(Sys.Date(), "%Y")
                      ),
                      tags$span("Développé avec R Shiny — © B. DEGUEURCE")
             )
    )
  ) # fin tagList
}
