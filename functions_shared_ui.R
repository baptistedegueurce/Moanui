# =============================================================================
# functions_shared_ui.R — Composants UI partagés entre tous les modules
# =============================================================================
# Fournit :
#   app_source_ui()     → panneau "Source de données" homogène (UI)
#   app_source_server() → logique serveur associée (reactive → data.frame)
#   app_info_source()   → badge de confirmation de chargement (renderUI)
# =============================================================================

# ---------------------------------------------------------------------------
# Helpers génériques (card + label) — utilisables dans tous les modules
# ---------------------------------------------------------------------------

#' Carte générique avec titre et icône
#' @param ...     contenu de la carte
#' @param titre   titre affiché
#' @param icone   nom FontAwesome
#' @param accent  TRUE pour ajouter le liseré bleu gauche
app_card <- function(..., titre, icone = "cog", accent = FALSE) {
  cls <- paste0("app-card", if (accent) " app-card-accent" else "")
  shiny::div(
    class = cls,
    shiny::div(class = "app-card-title", shiny::icon(icone), " ", titre),
    ...
  )
}

#' Label de champ avec hint optionnel
app_lbl <- function(txt, hint = NULL) {
  shiny::tagList(
    shiny::tags$span(class = "app-label", txt),
    if (!is.null(hint)) shiny::tags$span(class = "app-hint", hint)
  )
}

#' En-tête d'onglet standardisé
app_tab_header <- function(titre, desc, icone = "circle") {
  shiny::div(
    class = "app-tab-header",
    shiny::div(class = "app-tab-header-icon", shiny::icon(icone)),
    shiny::div(
      shiny::div(class = "app-tab-header-title", titre),
      shiny::div(class = "app-tab-header-desc",  desc)
    )
  )
}

#' Placeholder vide standardisé
app_empty <- function(msg = "Lancez l'analyse pour voir les résultats.", icone = "chart-bar") {
  shiny::div(class = "app-empty", shiny::icon(icone), shiny::br(), msg)
}

# ---------------------------------------------------------------------------
# app_source_ui() — panneau Source de données unifié
# ---------------------------------------------------------------------------
# Paramètres :
#   ns          : namespace (pour modules, sinon identity)
#   input_id    : préfixe des IDs générés (ex. "sq", "viz", "map", "sv")
#   accept      : vecteur d'extensions acceptées
#   multiple    : autoriser multi-fichiers
#   use_btn_label : libellé du bouton "Utiliser les données globales"
#   show_global : afficher ou non le bouton données globales (défaut TRUE)

app_source_ui <- function(
    ns            = shiny::NS(NULL),
    input_id      = "src",
    accept        = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".rds"),
    multiple      = FALSE,
    use_btn_label = "Utiliser les données de l'app",
    show_global   = TRUE,
    extra_accept_hint = "CSV, XLSX, RDS..."
) {
  pfx <- function(id) ns(paste0(input_id, "_", id))
  
  shiny::tagList(
    
    # ── Bouton données globales ─────────────────────────────────────────────
    if (show_global) shiny::tagList(
      shiny::actionButton(
        pfx("use_global"),
        label = shiny::tagList(shiny::icon("link"), " ", use_btn_label),
        class = "btn btn-sm app-btn-secondary",
        style = "width:100%; margin-bottom:8px;"
      ),
      shiny::div(
        style = "font-size:10px; color:#7FB3D3; text-align:center; margin-bottom:10px;",
        "— ou importer un fichier —"
      )
    ),
    
    # ── fileInput ───────────────────────────────────────────────────────────
    app_lbl("Fichier(s)", hint = extra_accept_hint),
    shiny::fileInput(
      pfx("fichier"),
      label       = NULL,
      accept      = accept,
      multiple    = multiple,
      buttonLabel = shiny::icon("folder-open"),
      placeholder = "Aucun fichier sélectionné"
    ),
    
    # ── Options CSV (visibles uniquement si fichier CSV sélectionné) ────────
    shiny::conditionalPanel(
      condition = paste0("output['", pfx("is_csv"), "'] === 'true'"),
      shiny::div(
        style = "display:flex; gap:6px; align-items:flex-end; margin-bottom:6px;",
        
        # Séparateur
        shiny::div(
          style = "flex:1; min-width:0;",
          shiny::tags$label(
            style = "font-size:10px; color:#7FB3D3; font-weight:600; display:block; margin-bottom:2px;",
            "Sépar."
          ),
          shiny::selectInput(
            pfx("csv_sep"), label = NULL,
            choices  = c("Virgule ,"      = ",",
                         "Point-virgule ;" = ";",
                         "Tabulation"     = "\t",
                         "Espace"         = " "),
            selected = ","
          )
        ),
        
        # Décimale
        shiny::div(
          style = "flex:1; min-width:0;",
          shiny::tags$label(
            style = "font-size:10px; color:#7FB3D3; font-weight:600; display:block; margin-bottom:2px;",
            "Décim."
          ),
          shiny::selectInput(
            pfx("csv_dec"), label = NULL,
            choices  = c("Point ." = ".", "Virgule ," = ","),
            selected = "."
          )
        ),
        
        # Encodage
        shiny::div(
          style = "flex:1; min-width:0;",
          shiny::tags$label(
            style = "font-size:10px; color:#7FB3D3; font-weight:600; display:block; margin-bottom:2px;",
            "Encod."
          ),
          shiny::selectInput(
            pfx("csv_enc"), label = NULL,
            choices  = c("UTF-8"        = "UTF-8",
                         "Latin-1"      = "latin1",
                         "Windows-1252" = "windows-1252"),
            selected = "UTF-8"
          )
        )
      ),
      
      # Bouton charger (CSV seulement)
      shiny::actionButton(
        pfx("csv_load"),
        label = shiny::tagList(shiny::icon("check"), " Charger le CSV"),
        class = "btn btn-sm app-btn-primary",
        style = "width:100%; margin-bottom:8px;"
      )
    ),
    
    # ── Feedback de chargement ──────────────────────────────────────────────
    shiny::uiOutput(pfx("info_source"))
  )
}


# ---------------------------------------------------------------------------
# app_source_server() — logique serveur unifiée pour le panneau source
# ---------------------------------------------------------------------------
# Retourne une reactive() qui fournit le data.frame chargé (ou NULL).
# Paramètres :
#   input, output, session : contexte Shiny
#   input_id  : même préfixe que app_source_ui()
#   rv        : reactiveValues global (doit exposer rv$data_clean)
#   loader_fn : fonction pour charger des formats non-CSV (défaut : charger_fichier_data)
#               Signature : function(path, ext, sep, dec, enc) → data.frame|NULL

app_source_server <- function(
    input, output, session,
    input_id  = "src",
    rv        = NULL,
    loader_fn = NULL
) {
  pfx <- function(id) paste0(input_id, "_", id)
  
  if (is.null(loader_fn)) loader_fn <- charger_fichier_data
  
  # Stockage local
  local_data <- shiny::reactiveVal(NULL)
  
  # ── Détection CSV (pour conditionalPanel) ───────────────────────────────
  output[[pfx("is_csv")]] <- shiny::renderText({
    fi <- input[[pfx("fichier")]]
    if (is.null(fi)) return("")
    ext <- tolower(tools::file_ext(fi$name[1]))
    if (ext %in% c("csv", "tsv", "txt")) "true" else ""
  })
  shiny::outputOptions(output, pfx("is_csv"), suspendWhenHidden = FALSE)
  
  # ── Bouton "Utiliser données globales" ──────────────────────────────────
  shiny::observeEvent(input[[pfx("use_global")]], {
    df_candidate <- NULL
    if (!is.null(rv)) {
      df_candidate <- tryCatch(rv$data_clean, error = function(e) NULL)
    }
    
    if (is.null(df_candidate)) {
      shiny::showNotification(
        shiny::tagList(
          shiny::icon("exclamation-triangle"), " ",
          shiny::strong("Aucune donnée disponible dans l'app."), shiny::br(),
          shiny::tags$span(style = "font-size:11px;",
                           "Chargez d'abord un fichier dans l'onglet Gestion de la donnée.")
        ),
        type = "warning", duration = 7
      )
      return()
    }
    
    local_data(as.data.frame(df_candidate))
    .notify_loaded(df_candidate, source = "Données de l'app chargées")
  })
  
  # ── Import fichier (non-CSV : chargement immédiat) ───────────────────────
  shiny::observeEvent(input[[pfx("fichier")]], {
    fi <- input[[pfx("fichier")]]
    shiny::req(fi)
    
    exts <- tolower(tools::file_ext(fi$name))
    
    # CSV → attendre le bouton dédié
    if (any(exts %in% c("csv", "tsv", "txt"))) return(NULL)
    
    .load_files(fi, exts,
                sep = ",", dec = ".", enc = "UTF-8",
                loader_fn = loader_fn,
                local_data = local_data)
  })
  
  # ── Import CSV (via bouton) ──────────────────────────────────────────────
  shiny::observeEvent(input[[pfx("csv_load")]], {
    fi <- input[[pfx("fichier")]]
    shiny::req(fi)
    
    exts <- tolower(tools::file_ext(fi$name))
    sep  <- input[[pfx("csv_sep")]] %||% ","
    dec  <- input[[pfx("csv_dec")]] %||% "."
    enc  <- input[[pfx("csv_enc")]] %||% "UTF-8"
    
    .load_files(fi, exts,
                sep = sep, dec = dec, enc = enc,
                loader_fn = loader_fn,
                local_data = local_data)
  })
  
  # ── Badge d'info source ──────────────────────────────────────────────────
  output[[pfx("info_source")]] <- shiny::renderUI({
    df <- local_data()
    if (is.null(df)) {
      # Vérifier si données globales disponibles sans les forcer
      df_g <- if (!is.null(rv)) tryCatch(rv$data_clean, error = function(e) NULL) else NULL
      if (is.null(df_g)) return(shiny::div(
        style = "font-size:11px; color:#7FB3D3; margin-top:4px;",
        shiny::icon("info-circle"), " Aucune donnée chargée."
      ))
      return(NULL)  # données globales → pas de badge ici
    }
    .source_badge(df)
  })
  
  # ── Reactive principal ───────────────────────────────────────────────────
  shiny::reactive({
    # Priorité : données importées localement
    ld <- local_data()
    if (!is.null(ld)) return(ld)
    # Fallback : données globales de l'app
    if (!is.null(rv)) tryCatch(rv$data_clean, error = function(e) NULL) else NULL
  })
}

# ---------------------------------------------------------------------------
# Helpers internes (non exportés)
# ---------------------------------------------------------------------------

.load_files <- function(fi, exts, sep, dec, enc, loader_fn, local_data) {
  liste <- stats::setNames(
    lapply(seq_len(nrow(fi)), function(i) {
      loader_fn(fi$datapath[i], exts[i], sep = sep, dec = dec, enc = enc)
    }),
    fi$name
  )
  liste <- Filter(Negate(is.null), liste)
  if (length(liste) == 0) return(NULL)
  
  df <- if (length(liste) == 1) liste[[1]] else empiler_fichiers(liste)
  
  if (!is.null(df)) {
    local_data(as.data.frame(df))
    src_label <- if (length(liste) > 1)
      paste0(length(liste), " fichiers empilés")
    else
      fi$name[1]
    .notify_loaded(df, source = src_label)
  }
}

.notify_loaded <- function(df, source = "Données chargées") {
  shiny::showNotification(
    shiny::tagList(
      shiny::icon("check-circle"), " ",
      shiny::strong(source), shiny::br(),
      shiny::tags$span(
        style = "font-size:11px;",
        sprintf("%s lignes \u00d7 %s colonnes",
                format(nrow(df), big.mark = "\u202f"),
                ncol(df))
      )
    ),
    type     = "message",
    duration = 5
  )
}

.source_badge <- function(df) {
  shiny::div(
    class = "app-source-badge",
    shiny::icon("check-circle", style = "color:#2E9E6B;"),
    sprintf(" %s lignes \u00d7 %s colonnes",
            format(nrow(df), big.mark = "\u202f"),
            ncol(df))
  )
}

# ---------------------------------------------------------------------------
# CSS partagé à injecter dans ui_main.R (ou dans chaque tab via tags$style)
# ---------------------------------------------------------------------------
app_shared_css <- shiny::tags$style(shiny::HTML("

  /* ── Card générique ──────────────────────────────────────────────────── */
  .app-card {
    background:    #0B2A3D;
    border:        1px solid #123A52;
    border-radius: 10px;
    padding:       14px 16px;
    margin-bottom: 12px;
  }
  .app-card-title {
    font-size:      10px;
    font-weight:    700;
    text-transform: uppercase;
    letter-spacing: .08em;
    color:          #7FB3D3;
    margin-bottom:  10px;
  }
  .app-card-title i { color: #0077B6; }
  .app-card-accent  { border-left: 3px solid #0077B6; padding-left: 13px; }
  .app-card-warn    { border-left: 3px solid #E67E22; padding-left: 13px; }
  .app-card-ok      { border-left: 3px solid #2E9E6B; padding-left: 13px; }

  /* ── Labels ─────────────────────────────────────────────────────────── */
  .app-label {
    font-size:     11px;
    font-weight:   600;
    color:         #EAF2F8;
    display:       block;
    margin-bottom: 2px;
  }
  .app-hint {
    font-size:     10px;
    color:         #4A7A9B;
    display:       block;
    margin-bottom: 4px;
  }

  /* ── Tab header ──────────────────────────────────────────────────────── */
  .app-tab-header {
    display:       flex;
    align-items:   center;
    gap:           12px;
    padding:       12px 16px;
    background:    #0B2A3D;
    border-radius: 10px;
    margin-bottom: 14px;
  }
  .app-tab-header-icon {
    font-size: 22px;
    color:     #0077B6;
    min-width: 28px;
    text-align:center;
  }
  .app-tab-header-title {
    font-size:   15px;
    font-weight: 700;
    color:       #EAF2F8;
  }
  .app-tab-header-desc {
    font-size: 11px;
    color:     #7FB3D3;
    margin-top: 2px;
  }

  /* ── Empty placeholder ───────────────────────────────────────────────── */
  .app-empty {
    text-align: center;
    color:      #4A7A9B;
    font-size:  13px;
    padding:    40px 20px;
  }
  .app-empty i { font-size: 28px; margin-bottom: 10px; display:block; }

  /* ── Boutons primaire / secondaire génériques ────────────────────────── */
  .app-btn-primary {
    background:   #0077B6;
    border-color: #0077B6;
    color:        #fff;
  }
  .app-btn-primary:hover { background: #005F8F; border-color: #005F8F; }

  .app-btn-secondary {
    background:   transparent;
    border:       1px solid #0077B6;
    color:        #7FB3D3;
  }
  .app-btn-secondary:hover { background: rgba(0,119,182,.12); color:#EAF2F8; }

  .app-btn-danger {
    background:   transparent;
    border:       1px solid #C0392B;
    color:        #E07070;
  }
  .app-btn-danger:hover { background: rgba(192,57,43,.15); }

  /* ── Badge source ────────────────────────────────────────────────────── */
  .app-source-badge {
    font-size:    11px;
    color:        #2E9E6B;
    margin-top:   6px;
    padding:      4px 8px;
    background:   rgba(46,158,107,.08);
    border-radius:6px;
    border:       1px solid rgba(46,158,107,.2);
  }

  /* ── Divider ─────────────────────────────────────────────────────────── */
  .app-divider {
    border:        none;
    border-top:    1px solid #123A52;
    margin:        10px 0;
  }

"))