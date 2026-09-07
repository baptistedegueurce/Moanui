# =============================================================================
# server_data.R — Serveur module Gestion de la donnée
# Signature : server_data(input, output, session, rv)
# IDs UI préfixés "data_" pour éviter les collisions
# =============================================================================

server_data <- function(input, output, session, rv) {
  
  # ===========================================================================
  # ÉTAT LOCAL
  # ===========================================================================
  dv <- shiny::reactiveValues(
    df_courant   = NULL,   # data.frame courant (après toutes les opérations)
    df_history   = list(), # historique pour undo (liste de data.frames)
    ops_log      = character(0), # log lisible des opérations
    cols_sel     = character(0), # colonnes sélectionnées dans l'onglet Colonnes
    filtres_actifs   = list(),     # filtres en cours (chacun avec un $id unique)
    filtre_next_id   = 1L,         # compteur pour générer des ids de filtre uniques
    df_avant_filtres = NULL,       # snapshot du df juste avant le 1er filtre (pour pouvoir retirer un filtre)
    df2_liste    = list(),  # liste de data.frames additionnels pour fusion
    df_sources   = list(),  # liste des df AVANT fusion (pour pastilles)
    ref_metier      = NULL,    # référentiel métier chargé une fois
    groupby_preview = NULL     # résultat du group by pour prévisualisation
  )
  
  # ---------------------------------------------------------------------------
  # Helpers internes
  # ---------------------------------------------------------------------------
  
  # Chargement du référentiel métier (une seule fois)
  shiny::observe({
    if (is.null(dv$ref_metier)) {
      dv$ref_metier <- charger_ref_metier()
    }
  })
  
  # Sauvegarde l'état avant une opération (pour undo)
  push_history <- function(msg) {
    if (!is.null(dv$df_courant)) {
      dv$df_history <- c(dv$df_history, list(dv$df_courant))
      if (length(dv$df_history) > 30) dv$df_history <- tail(dv$df_history, 30)
    }
    dv$ops_log <- c(dv$ops_log, paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", msg))
  }
  
  # ===========================================================================
  # 1. IMPORT FICHIER PRINCIPAL
  # ===========================================================================
  
  shiny::observeEvent(input$data_fichier, {
    shiny::req(input$data_fichier)
    # Supporte maintenant plusieurs fichiers (multiple = TRUE dans l'UI)
    fichiers <- input$data_fichier   # data.frame avec name / datapath / etc.
    exts     <- tolower(tools::file_ext(fichiers$name))
    
    # Pour CSV on attend les options (sep/dec/enc) → UI d'abord
    if (any(exts %in% c("csv", "tsv", "txt"))) return(NULL)
    
    liste_df <- stats::setNames(
      lapply(seq_len(nrow(fichiers)), function(i) {
        charger_fichier_data(fichiers$datapath[i], exts[i])
      }),
      fichiers$name
    )
    liste_df <- Filter(Negate(is.null), liste_df)
    
    if (length(liste_df) == 0) return(NULL)
    
    df <- if (length(liste_df) == 1) liste_df[[1]] else empiler_fichiers(liste_df)
    
    if (!is.null(df)) {
      dv$df_history  <- list()
      dv$ops_log     <- character(0)
      dv$df_courant  <- df
      dv$df_sources  <- liste_df   # mémoriser les sources
      dv$filtres_actifs   <- list()
      dv$df_avant_filtres <- NULL
      msg <- if (length(liste_df) > 1)
        paste0(length(liste_df), " fichiers empilés — ",
               nrow(df), " × ", ncol(df))
      else
        paste0(fichiers$name[1], " (", nrow(df), " × ", ncol(df), ")")
      push_history(paste0("Import : ", msg))
      shiny::showNotification(msg, type = "message", duration = 4)
    }
  })
  
  # Options CSV
  output$data_csv_options_ui <- shiny::renderUI({
    shiny::req(input$data_fichier)
    exts <- tolower(tools::file_ext(input$data_fichier$name))
    if (!any(exts %in% c("csv", "tsv", "txt"))) return(NULL)
    
    shiny::div(class = "data-card",
               shiny::div(class = "data-card-title",
                          shiny::icon("sliders-h"), " Options CSV"),
               shiny::fluidRow(
                 shiny::column(4,
                               shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                               "Séparateur"),
                               shiny::selectInput("data_csv_sep", label = NULL,
                                                  choices = c("Virgule ,"=",","Point-virgule ;"=";",
                                                              "Tabulation"="\t","Espace"=" "),
                                                  selected = ",")
                 ),
                 shiny::column(4,
                               shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                               "Décimale"),
                               shiny::selectInput("data_csv_dec", label = NULL,
                                                  choices = c("Point ."=".","Virgule ,"=","),
                                                  selected = ".")
                 ),
                 shiny::column(4,
                               shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                               "Encodage"),
                               shiny::selectInput("data_csv_enc", label = NULL,
                                                  choices = c("UTF-8","latin1","windows-1252"),
                                                  selected = "UTF-8")
                 )
               ),
               shiny::actionButton("data_csv_load", "Charger le CSV",
                                   icon  = shiny::icon("check"),
                                   class = "btn btn-sm btn-data-primary",
                                   style = "width:100%; margin-top:6px;")
    )
  })
  
  shiny::observeEvent(input$data_csv_load, {
    shiny::req(input$data_fichier)
    fichiers <- input$data_fichier
    exts     <- tolower(tools::file_ext(fichiers$name))
    
    liste_df <- stats::setNames(
      lapply(seq_len(nrow(fichiers)), function(i) {
        charger_fichier_data(fichiers$datapath[i], exts[i],
                             sep = input$data_csv_sep %||% ",",
                             dec = input$data_csv_dec %||% ".",
                             enc = input$data_csv_enc %||% "UTF-8")
      }),
      fichiers$name
    )
    liste_df <- Filter(Negate(is.null), liste_df)
    if (length(liste_df) == 0) return(NULL)
    
    df <- if (length(liste_df) == 1) liste_df[[1]] else empiler_fichiers(liste_df)
    if (!is.null(df)) {
      dv$df_history <- list()
      dv$ops_log    <- character(0)
      dv$df_courant <- df
      dv$df_sources <- liste_df
      dv$filtres_actifs   <- list()
      dv$df_avant_filtres <- NULL
      msg <- if (length(liste_df) > 1)
        paste0(length(liste_df), " CSV empilés (sep='", input$data_csv_sep, "') — ",
               nrow(df), " × ", ncol(df))
      else
        paste0("CSV chargé : ", fichiers$name[1], " (sep='", input$data_csv_sep, "') — ",
               nrow(df), " × ", ncol(df))
      push_history(paste0("Import : ", msg))
      shiny::showNotification(msg, type = "message", duration = 4)
    }
  })
  
  # ===========================================================================
  # 2. INFO FICHIER + KPI
  # ===========================================================================
  
  output$data_info_fichier <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    shiny::tags$small(style = "color:#7FB3D3;",
                      shiny::icon("check-circle", style = "color:#2E9E6B;"),
                      sprintf(" %s lignes \u00d7 %s colonnes",
                              format(nrow(df), big.mark = "\u202f"), ncol(df))
    )
  })
  
  output$data_kpi_row <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    n_num  <- sum(sapply(df, is.numeric))
    n_chr  <- sum(sapply(df, is.character))
    n_fct  <- sum(sapply(df, is.factor))
    n_na   <- sum(is.na(df))
    pct_na <- round(n_na / (nrow(df) * ncol(df)) * 100, 1)
    
    kpis <- list(
      list(val = format(nrow(df), big.mark = "\u202f"), lbl = "Lignes"),
      list(val = ncol(df),                              lbl = "Colonnes"),
      list(val = n_num,                                 lbl = "Col. num."),
      list(val = n_chr + n_fct,                         lbl = "Col. texte/fact."),
      list(val = paste0(pct_na, "%"),                   lbl = "% valeurs NA")
    )
    
    shiny::fluidRow(
      lapply(kpis, function(k)
        shiny::column(2,
                      shiny::div(class = "hal-kpi",
                                 shiny::div(class = "hal-kpi-val", k$val),
                                 shiny::div(class = "hal-kpi-lbl", k$lbl)
                      )
        )
      )
    )
  })
  
  # ===========================================================================
  # 3. APERÇU TABLE
  # ===========================================================================
  
  output$data_table_preview <- DT::renderDataTable({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    n  <- min(nrow(df), input$data_nrows_preview %||% 100)
    df_show <- head(df, n)
    
    # Filtre texte global côté serveur
    q <- input$data_search_global
    if (!is.null(q) && nzchar(q)) {
      mask <- apply(df_show, 1, function(r) any(grepl(q, r, ignore.case = TRUE)))
      df_show <- df_show[mask, , drop = FALSE]
    }
    
    DT::datatable(
      df_show,
      options = list(
        pageLength   = 25,
        scrollX      = TRUE,
        dom          = "tip",
        language     = list(
          url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/French.json"
        )
      ),
      rownames  = FALSE,
      class     = "display nowrap"
    )
  })
  
  # ===========================================================================
  # 4. ONGLET COLONNES — liste avec badges
  # ===========================================================================
  
  output$data_col_list <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df      <- dv$df_courant
    sources <- dv$df_sources   # liste nommée des df sources
    
    # Pour chaque colonne, savoir dans quels df sources elle est présente
    # Si on a des sources mémorisées on construit la map, sinon on met rien
    n_sources <- length(sources)
    col_names <- names(df)
    
    # Pour chaque colonne (par position), liste des indices de sources où elle est présente
    col_presence <- if (n_sources > 0) {
      lapply(col_names, function(col) {
        which(vapply(sources, function(s) col %in% names(s), logical(1)))
      })
    } else {
      vector("list", ncol(df))
    }
    
    shiny::tagList(
      lapply(seq_along(col_names), function(i) {
        col    <- col_names[i]
        type   <- type_colonne(df[[col]])
        is_sel <- col %in% dv$cols_sel
        n_na   <- sum(is.na(df[[col]]))
        n_uniq <- dplyr::n_distinct(df[[col]], na.rm = TRUE)
        present_in <- col_presence[[i]]  # indexation par position, robuste aux noms spéciaux
        
        # Pastilles DF (allumée si présente, éteinte sinon)
        badges_df <- if (n_sources > 1) {
          shiny::div(
            style = "display:inline-flex; gap:3px; margin-left:6px; align-items:center;",
            lapply(seq_len(n_sources), function(k) {
              allume <- k %in% present_in
              shiny::tags$span(
                style = paste0(
                  "display:inline-flex; align-items:center; justify-content:center;",
                  "width:16px; height:16px; border-radius:50%; font-size:9px; font-weight:700;",
                  if (allume)
                    "background:#0077B6; color:#fff; border:1px solid #0077B6;"
                  else
                    "background:transparent; color:#4A7A9B; border:1px solid #1D4E6D;"
                ),
                k
              )
            })
          )
        } else NULL
        
        shiny::div(
          class = paste("col-info-row", if (is_sel) "selected" else ""),
          id    = paste0("colrow_", col),
          onclick = paste0(
            "Shiny.setInputValue('data_col_clicked', '", col,
            "', {priority:'event'});"
          ),
          shiny::div(
            style = "display:flex; align-items:center; flex-wrap:wrap; gap:2px;",
            shiny::strong(style = "font-size:12px;", col),
            badge_type(type),
            badges_df
          ),
          shiny::div(
            style = "font-size:10px; color:#7FB3D3;",
            paste0(n_uniq, " uniques · ", n_na, " NA")
          )
        )
      })
    )
  })
  
  # Gestion clic sur colonne
  shiny::observeEvent(input$data_col_clicked, {
    col <- input$data_col_clicked
    if (col %in% dv$cols_sel) {
      dv$cols_sel <- setdiff(dv$cols_sel, col)
    } else {
      dv$cols_sel <- c(dv$cols_sel, col)
    }
  })
  
  shiny::observeEvent(input$data_col_select_all, {
    shiny::req(dv$df_courant)
    dv$cols_sel <- names(dv$df_courant)
  })
  shiny::observeEvent(input$data_col_deselect_all, {
    dv$cols_sel <- character(0)
  })
  
  # ===========================================================================
  # 5. PANNEAU OPÉRATIONS SUR COLONNE(S) SÉLECTIONNÉE(S)
  # ===========================================================================
  
  output$data_col_ops_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    sel <- dv$cols_sel
    df  <- dv$df_courant
    
    if (length(sel) == 0) {
      return(shiny::p(style = "font-size:12px; color:#7FB3D3;",
                      "Cliquez sur une ou plusieurs colonnes à gauche."))
    }
    
    shiny::tagList(
      shiny::tags$div(class = "data-op-info",
                      shiny::icon("info-circle"),
                      paste0(" Sélection : ", paste(sel, collapse = ", "))
      ),
      shiny::br(),
      
      # --- Supprimer ---
      shiny::div(class = "data-action-bar",
                 shiny::actionButton("data_col_drop", "Supprimer la sélection",
                                     icon  = shiny::icon("trash"),
                                     class = "btn btn-sm btn-data-danger")
      ),
      
      shiny::hr(style = "border-color:#123A52;"),
      
      # --- Renommer (mono seulement) ---
      if (length(sel) == 1) shiny::tagList(
        shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                        "Renommer"),
        shiny::fluidRow(
          shiny::column(8,
                        shiny::textInput("data_col_rename_new", label = NULL,
                                         value   = sel,
                                         placeholder = "Nouveau nom")
          ),
          shiny::column(4,
                        shiny::actionButton("data_col_rename_go", "OK",
                                            class = "btn btn-sm btn-data-primary",
                                            style = "margin-top:0;")
          )
        )
      ),
      
      shiny::hr(style = "border-color:#123A52;"),
      
      # --- Changer le type (mono seulement) ---
      if (length(sel) == 1) shiny::tagList(
        shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                        "Changer le type"),
        shiny::fluidRow(
          shiny::column(8,
                        shiny::selectInput("data_col_type_cible", label = NULL,
                                           choices = c("Numérique"  = "numeric",
                                                       "Texte"      = "character",
                                                       "Facteur"    = "factor",
                                                       "Date"       = "Date",
                                                       "Logique"    = "logical"),
                                           selected = {
                                             t <- type_colonne(df[[sel]])
                                             switch(t,
                                                    "Numérique" = "numeric",
                                                    "Texte"     = "character",
                                                    "Facteur"   = "factor",
                                                    "Date"      = "Date",
                                                    "Logique"   = "logical",
                                                    "character"
                                             )
                                           })
          ),
          shiny::column(4,
                        shiny::actionButton("data_col_type_go", "Convertir",
                                            class = "btn btn-sm btn-data-primary")
          )
        )
      ),
      
      shiny::hr(style = "border-color:#123A52;"),
      
      # --- Transformer (mono seulement) ---
      if (length(sel) == 1) shiny::tagList(
        shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                        "Transformer la colonne"),
        shiny::fluidRow(
          shiny::column(8,
                        shiny::selectInput("data_col_op", label = NULL,
                                           choices = c(
                                             "Mettre en majuscules"  = "uppercase",
                                             "Mettre en minuscules"  = "lowercase",
                                             "Supprimer espaces"     = "trim",
                                             "Arrondir"              = "arrondir",
                                             "Valeur absolue"        = "abs",
                                             "Log naturel"           = "log",
                                             "Racine carrée"         = "sqrt",
                                             "Remplacer les NA"      = "replace_na",
                                             "Recoder une valeur"    = "recode_valeur",
                                             "Discrétiser (nb égal)" = "bin_egal",
                                             "Discrétiser (quantile)"= "bin_quantile"
                                           ))
          ),
          shiny::column(4,
                        shiny::actionButton("data_col_transfo_go", "Appliquer",
                                            class = "btn btn-sm btn-data-primary")
          )
        ),
        shiny::uiOutput("data_col_op_params")
      )
    )
  })
  
  # Paramètres supplémentaires selon l'opération choisie
  output$data_col_op_params <- shiny::renderUI({
    op <- input$data_col_op
    if (is.null(op)) return(NULL)
    
    switch(op,
           "arrondir" = shiny::numericInput("data_op_digits", "Nb décimales",
                                            value = 2, min = 0, max = 10),
           "replace_na" = shiny::textInput("data_op_valeur_na",
                                           "Valeur de remplacement", value = "0"),
           "recode_valeur" = shiny::fluidRow(
             shiny::column(6,
                           shiny::textInput("data_op_recode_old", "Valeur actuelle")
             ),
             shiny::column(6,
                           shiny::textInput("data_op_recode_new", "Nouvelle valeur")
             )
           ),
           "bin_egal" = , "bin_quantile" =
             shiny::numericInput("data_op_nbins", "Nb de classes",
                                 value = 4, min = 2, max = 20),
           NULL
    )
  })
  
  # --- Exécution : supprimer colonnes ---
  shiny::observeEvent(input$data_col_drop, {
    shiny::req(dv$df_courant, length(dv$cols_sel) > 0)
    push_history(paste0("Colonnes supprimées : ", paste(dv$cols_sel, collapse = ", ")))
    dv$df_courant <- supprimer_colonnes(dv$df_courant, dv$cols_sel)
    dv$cols_sel   <- character(0)
    shiny::showNotification("Colonnes supprimées.", type = "message", duration = 3)
  })
  
  # --- Exécution : renommer ---
  shiny::observeEvent(input$data_col_rename_go, {
    shiny::req(dv$df_courant, length(dv$cols_sel) == 1,
               nzchar(input$data_col_rename_new))
    old <- dv$cols_sel
    new <- trimws(input$data_col_rename_new)
    push_history(paste0("Renommage : '", old, "' → '", new, "'"))
    dv$df_courant <- renommer_colonnes(dv$df_courant, old, new)
    dv$cols_sel   <- new
    shiny::showNotification(paste0("'", old, "' renommé en '", new, "'"),
                            type = "message", duration = 3)
  })
  
  # --- Exécution : changer type ---
  shiny::observeEvent(input$data_col_type_go, {
    shiny::req(dv$df_courant, length(dv$cols_sel) == 1, input$data_col_type_cible)
    col  <- dv$cols_sel
    type <- input$data_col_type_cible
    push_history(paste0("Type '", col, "' → ", type))
    dv$df_courant <- changer_type(dv$df_courant, col, type)
    shiny::showNotification(paste0("'", col, "' converti en ", type),
                            type = "message", duration = 3)
  })
  
  # --- Exécution : transformer ---
  shiny::observeEvent(input$data_col_transfo_go, {
    shiny::req(dv$df_courant, length(dv$cols_sel) == 1, input$data_col_op)
    col <- dv$cols_sel
    op  <- input$data_col_op
    params <- list(
      digits     = input$data_op_digits,
      valeur_na  = input$data_op_valeur_na,
      old        = input$data_op_recode_old,
      new        = input$data_op_recode_new,
      n_bins     = input$data_op_nbins
    )
    push_history(paste0("Transformation '", op, "' sur '", col, "'"))
    dv$df_courant <- transformer_colonne(dv$df_courant, col, op, params)
    shiny::showNotification(paste0(op, " appliqué à '", col, "'"),
                            type = "message", duration = 3)
  })
  
  # ===========================================================================
  # 6. CRÉER UNE NOUVELLE COLONNE
  # ===========================================================================
  
  output$data_new_col_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(4,
                      shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Nom de la nouvelle colonne"),
                      shiny::textInput("data_newcol_nom", label = NULL,
                                       placeholder = "ex: ratio_prix")
        ),
        shiny::column(8,
                      shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Expression R (les colonnes sont accessibles directement)"),
                      shiny::textInput("data_newcol_expr", label = NULL,
                                       placeholder = "ex: debarquement_Kg / duree_maree")
        )
      ),
      shiny::div(
        style = "font-size:10px; color:#7FB3D3; margin-bottom:8px;",
        shiny::icon("lightbulb"),
        " Colonnes disponibles : ",
        shiny::tags$em(paste(names(df), collapse = ", "))
      ),
      shiny::actionButton("data_newcol_go", "Créer la colonne",
                          icon  = shiny::icon("plus"),
                          class = "btn btn-sm btn-data-primary")
    )
  })
  
  shiny::observeEvent(input$data_newcol_go, {
    shiny::req(dv$df_courant,
               nzchar(input$data_newcol_nom),
               nzchar(input$data_newcol_expr))
    nom  <- trimws(input$data_newcol_nom)
    expr <- input$data_newcol_expr
    push_history(paste0("Nouvelle colonne '", nom, "' = ", expr))
    dv$df_courant <- creer_colonne(dv$df_courant, nom, expr)
    shiny::showNotification(paste0("Colonne '", nom, "' créée."),
                            type = "message", duration = 3)
  })
  
  # ===========================================================================
  # 6b. PANEL GESTION DES DATES (onglet Colonnes)
  # ===========================================================================
  
  output$data_date_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df   <- dv$df_courant
    cols <- names(df)
    
    # Pré-sélection : colonne sélectionnée si unique, sinon première colonne date/chr
    sel_default <- {
      if (length(dv$cols_sel) == 1) dv$cols_sel
      else {
        date_cols <- cols[sapply(df, function(x)
          inherits(x, c("Date","POSIXct","POSIXlt")))]
        if (length(date_cols) > 0) date_cols[1] else cols[1]
      }
    }
    
    # Détecter si la colonne sélectionnée est déjà une Date
    col_type <- if (!is.null(sel_default) && sel_default %in% cols)
      type_colonne(df[[sel_default]]) else ""
    is_already_date <- col_type == "Date"
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(5,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Colonne source"),
                      shiny::selectInput("data_date_col", label = NULL,
                                         choices  = stats::setNames(cols, cols),
                                         selected = sel_default)
        ),
        shiny::column(4,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Format d'entrée (optionnel)"),
                      shiny::textInput("data_date_format", label = NULL,
                                       placeholder = "%d/%m/%Y",
                                       value = "")
        ),
        shiny::column(3,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "\u00a0"),
                      shiny::checkboxInput("data_date_convertir",
                                           "Convertir en Date", value = !is_already_date)
        )
      ),
      
      shiny::uiOutput("data_date_col_info"),
      
      shiny::hr(style = "border-color:#123A52; margin:8px 0;"),
      
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:6px;",
                      "Composantes \u00e0 extraire (nouvelles colonnes)"),
      
      shiny::fluidRow(
        shiny::column(4,
                      shiny::checkboxGroupInput("data_date_ops", label = NULL,
                                                choices = c(
                                                  "Ann\u00e9e (num\u00e9rique)"            = "annee",
                                                  "Mois (num\u00e9rique 1\u201312)"         = "mois_num",
                                                  "Mois (libell\u00e9 : Janvier\u2026)"     = "mois_label",
                                                  "Trimestre (1\u20134)"                    = "trimestre",
                                                  "Semestre (1\u20132)"                     = "semestre"
                                                )
                      )
        ),
        shiny::column(4,
                      shiny::checkboxGroupInput("data_date_ops2", label = NULL,
                                                choices = c(
                                                  "Semaine ISO (1\u201353)"                 = "semaine_iso",
                                                  "Jour du mois (1\u201331)"                = "jour_mois",
                                                  "Jour sem. (num\u00e9rique)"              = "jour_semaine_num",
                                                  "Jour sem. (libell\u00e9)"                = "jour_semaine_label",
                                                  "Jour de l'ann\u00e9e (1\u2013366)"      = "jour_annee"
                                                )
                      )
        ),
        shiny::column(4,
                      shiny::checkboxGroupInput("data_date_ops3", label = NULL,
                                                choices = c(
                                                  "Date tronqu\u00e9e au mois"             = "date_tronquee_mois",
                                                  "Date tronqu\u00e9e au trimestre"        = "date_tronquee_trim",
                                                  "Date tronqu\u00e9e \u00e0 la semaine"   = "date_tronquee_sem"
                                                )
                      )
        )
      ),
      
      shiny::actionButton("data_date_go", "Appliquer",
                          icon  = shiny::icon("calendar-check"),
                          class = "btn btn-sm btn-data-primary",
                          style = "width:100%; margin-top:4px;")
    )
  })
  
  # Info sur la colonne date sélectionnée (feedback immédiat)
  output$data_date_col_info <- shiny::renderUI({
    shiny::req(dv$df_courant, input$data_date_col)
    col <- input$data_date_col
    if (!col %in% names(dv$df_courant)) return(NULL)
    x    <- dv$df_courant[[col]]
    type <- type_colonne(x)
    n_na <- sum(is.na(x))
    ex   <- head(na.omit(as.character(x)), 3)
    
    color <- if (type == "Date") "#2E9E6B" else "#E07B39"
    icon_name <- if (type == "Date") "check-circle" else "exclamation-triangle"
    
    shiny::div(class = "data-op-info",
               style = paste0("border-left-color:", color, ";"),
               shiny::icon(icon_name, style = paste0("color:", color, ";")),
               paste0(" Type actuel : ", type,
                      " \u2022 ", n_na, " NA",
                      " \u2022 Ex. : ", paste(ex, collapse = ", "))
    )
  })
  
  # Exécution : convertir + extraire composantes
  shiny::observeEvent(input$data_date_go, {
    shiny::req(dv$df_courant, input$data_date_col)
    
    col  <- input$data_date_col
    ops  <- c(input$data_date_ops, input$data_date_ops2, input$data_date_ops3)
    fmt  <- trimws(input$data_date_format %||% "")
    conv <- isTRUE(input$data_date_convertir)
    
    df <- dv$df_courant
    
    # --- Étape 1 : conversion en Date si demandée ---
    if (conv) {
      x_raw <- df[[col]]
      x_conv <- tryCatch({
        if (nzchar(fmt)) {
          res <- suppressWarnings(as.Date(as.character(x_raw), format = fmt))
          if (sum(!is.na(res), na.rm = TRUE) / max(length(x_raw), 1) < 0.5)
            stop("Moins de 50 % de valeurs converties avec le format '", fmt, "'")
          res
        } else {
          parser_date(x_raw)
        }
      }, error = function(e) {
        shiny::showNotification(
          paste0("Conversion '\u00e9chou\u00e9e pour '", col, "' : ", e$message),
          type = "error", duration = 7
        )
        NULL
      })
      if (is.null(x_conv)) return()
      push_history(paste0("Conversion en Date : '", col, "'",
                          if (nzchar(fmt)) paste0(" (format ", fmt, ")") else ""))
      df[[col]] <- x_conv
    }
    
    # --- Étape 2 : extraction des composantes temporelles ---
    if (length(ops) > 0) {
      df_res <- creer_colonnes_temporelles(df, col, ops)
      cols_crees <- attr(df_res, "cols_creees")
      attr(df_res, "cols_creees") <- NULL
      
      if (length(cols_crees) > 0) {
        push_history(paste0("Composantes temporelles extraites depuis '", col, "' : ",
                            paste(cols_crees, collapse = ", ")))
        shiny::showNotification(
          paste0(length(cols_crees), " colonne(s) cr\u00e9\u00e9e(s) : ",
                 paste(cols_crees, collapse = ", ")),
          type = "message", duration = 5
        )
      } else {
        shiny::showNotification("Aucune composante extraite.", type = "warning", duration = 3)
      }
      dv$df_courant <- df_res
    } else if (conv) {
      # Juste la conversion, pas d'extraction
      dv$df_courant <- df
      shiny::showNotification(
        paste0("'", col, "' converti en Date."), type = "message", duration = 3
      )
    } else {
      shiny::showNotification(
        "S\u00e9lectionnez au moins une composante \u00e0 extraire.", type = "warning", duration = 3
      )
    }
  })
  
  # ===========================================================================
  # 7. FILTRES DYNAMIQUES (onglet Filtres)
  # ===========================================================================
  
  # Recalcule df_courant à partir du snapshot pré-filtres + liste de filtres actifs.
  # Permet de retirer un filtre individuellement sans perdre les autres.
  recalculer_filtres <- function() {
    base <- dv$df_avant_filtres
    if (is.null(base)) return(invisible(NULL))
    dv$df_courant <- appliquer_filtres_data(base, dv$filtres_actifs)
  }
  
  # Libellé lisible d'un filtre pour l'affichage en pastille
  .libelle_filtre <- function(f) {
    cond_lbl <- c(eq = "=", neq = "\u2260", contains = "contient",
                  in_list = "dans", isna = "est NA", notna = "n'est pas NA",
                  gt = ">", lt = "<")[f$condition]
    if (is.null(cond_lbl) || is.na(cond_lbl)) cond_lbl <- f$condition
    if (f$condition %in% c("isna", "notna")) {
      sprintf("%s %s", f$col, cond_lbl)
    } else if (f$condition == "in_list") {
      vals <- f$valeur
      apercu <- paste(utils::head(vals, 3), collapse = ", ")
      if (length(vals) > 3) apercu <- paste0(apercu, ", \u2026")
      sprintf("%s %s [%s]", f$col, cond_lbl, apercu)
    } else {
      sprintf("%s %s %s", f$col, cond_lbl, f$valeur)
    }
  }
  
  output$data_filtres_dynamiques <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df  <- dv$df_courant
    n_filtres <- min(ncol(df), 8)
    
    shiny::tagList(
      lapply(seq_len(n_filtres), function(i) {
        col_choices <- stats::setNames(names(df), names(df))
        col_def     <- names(df)[i]
        shiny::fluidRow(
          style = "margin-bottom:6px;",
          shiny::column(3,
                        shiny::selectInput(paste0("data_filt_col_", i), label = NULL,
                                           choices  = col_choices,
                                           selected = col_def)
          ),
          shiny::column(3,
                        shiny::selectInput(paste0("data_filt_cond_", i), label = NULL,
                                           choices = c("égal à"          = "eq",
                                                       "différent de"    = "neq",
                                                       "contient"        = "contains",
                                                       "est dans la liste" = "in_list",
                                                       "est NA"          = "isna",
                                                       "n'est pas NA"    = "notna",
                                                       "> (num)"         = "gt",
                                                       "< (num)"         = "lt"))
          ),
          shiny::column(4,
                        shiny::uiOutput(paste0("data_filt_val_ui_", i))
          ),
          shiny::column(2,
                        shiny::checkboxInput(paste0("data_filt_actif_", i),
                                             label = "Actif", value = FALSE)
          )
        )
      })
    )
  })
  
  # Génère le widget de valeur adapté selon la condition choisie pour chaque filtre
  lapply(seq_len(8), function(i) {
    output[[paste0("data_filt_val_ui_", i)]] <- shiny::renderUI({
      cond <- input[[paste0("data_filt_cond_", i)]]
      col  <- input[[paste0("data_filt_col_",  i)]]
      
      # Pas de champ valeur pour les conditions sans valeur
      if (!is.null(cond) && cond %in% c("isna", "notna")) return(NULL)
      
      # Champ multi-sélection pour "est dans la liste"
      if (!is.null(cond) && cond == "in_list" && !is.null(col) &&
          !is.null(dv$df_courant) && col %in% names(dv$df_courant)) {
        vals <- sort(unique(na.omit(as.character(dv$df_courant[[col]]))))
        vals_trunc <- head(vals, 300)
        return(
          shiny::selectizeInput(
            paste0("data_filt_val_", i),
            label   = NULL,
            choices = vals_trunc,
            selected = NULL,
            multiple = TRUE,
            options  = list(
              plugins     = list("remove_button"),
              placeholder = "Choisir des valeurs…",
              maxItems    = NULL
            )
          )
        )
      }
      
      # Champ texte libre pour les autres conditions
      shiny::textInput(paste0("data_filt_val_", i), label = NULL,
                       placeholder = "Valeur…")
    })
  })
  
  shiny::observeEvent(input$data_apply_filters, {
    shiny::req(dv$df_courant)
    n_filtres <- min(ncol(dv$df_courant), 8)
    nouveaux  <- list()
    for (i in seq_len(n_filtres)) {
      actif <- isTRUE(input[[paste0("data_filt_actif_", i)]])
      if (!actif) next
      col  <- input[[paste0("data_filt_col_",  i)]]
      cond <- input[[paste0("data_filt_cond_", i)]]
      val  <- input[[paste0("data_filt_val_",  i)]]
      # Pour in_list, val est un vecteur (selectize multiple) ; pour isna/notna, val peut être NULL
      if (!is.null(col)) {
        id_filtre <- dv$filtre_next_id
        dv$filtre_next_id <- dv$filtre_next_id + 1L
        nouveaux <- c(nouveaux, list(list(id = id_filtre, col = col,
                                          condition = cond, valeur = val)))
      }
    }
    if (length(nouveaux) == 0) {
      shiny::showNotification("Aucun filtre actif à ajouter.", type = "warning", duration = 3)
      return()
    }
    # Premier filtre appliqué : on capture le snapshot pré-filtres
    if (is.null(dv$df_avant_filtres)) {
      dv$df_avant_filtres <- dv$df_courant
    }
    dv$filtres_actifs <- c(dv$filtres_actifs, nouveaux)
    push_history(paste0("Filtres appliqués : +", length(nouveaux), " filtre(s)"))
    recalculer_filtres()
    shiny::showNotification(
      paste0("Filtres appliqués — ", nrow(dv$df_courant), " lignes restantes"),
      type = "message", duration = 4
    )
  })
  
  # Retrait d'un filtre individuel via le bouton "x" de sa pastille
  shiny::observeEvent(input$data_filtre_remove_id, {
    id_a_retirer <- input$data_filtre_remove_id
    if (is.null(id_a_retirer)) return()
    dv$filtres_actifs <- Filter(function(f) f$id != id_a_retirer, dv$filtres_actifs)
    recalculer_filtres()
    shiny::showNotification("Filtre retiré.", type = "message", duration = 2)
  })
  
  shiny::observeEvent(input$data_reset_filters, {
    if (!is.null(dv$df_avant_filtres)) {
      dv$df_courant <- dv$df_avant_filtres
    }
    dv$filtres_actifs   <- list()
    dv$df_avant_filtres <- NULL
    shiny::showNotification("Tous les filtres ont été retirés.",
                            type = "warning", duration = 4)
  })
  
  # Pastilles des filtres actifs, supprimables individuellement
  output$data_filter_summary <- shiny::renderUI({
    if (length(dv$filtres_actifs) == 0) return(NULL)
    
    shiny::tagList(
      shiny::div(class = "data-op-info",
                 shiny::icon("filter"),
                 paste0(" ", length(dv$filtres_actifs), " filtre(s) actif(s) — ",
                        nrow(dv$df_courant), " lignes")
      ),
      shiny::div(style = "display:flex; flex-wrap:wrap; gap:6px; margin-top:8px;",
                 lapply(dv$filtres_actifs, function(f) {
                   shiny::tags$span(
                     class = "filter-pill",
                     .libelle_filtre(f),
                     shiny::tags$button(
                       class = "filter-pill-remove",
                       onclick = sprintf(
                         "Shiny.setInputValue('data_filtre_remove_id', %d, {priority: 'event'})",
                         f$id
                       ),
                       shiny::HTML("&times;")
                     )
                   )
                 })
      )
    )
  })
  
  # --- Suppression de lignes par condition ---
  output$data_rm_col_sel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    shiny::tagList(
      shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                      "Colonne"),
      shiny::selectInput("data_rm_col", label = NULL,
                         choices = names(dv$df_courant))
    )
  })
  
  output$data_rm_val_sel <- shiny::renderUI({
    shiny::req(dv$df_courant, input$data_rm_col)
    col   <- input$data_rm_col
    cond  <- input$data_rm_condition
    if (cond %in% c("isna", "notna")) return(NULL)
    
    vals <- sort(unique(na.omit(as.character(dv$df_courant[[col]]))))
    vals_trunc <- head(vals, 200)
    
    shiny::tagList(
      shiny::tags$div(style="font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                      "Valeur"),
      shiny::selectizeInput("data_rm_val", label = NULL,
                            choices  = vals_trunc,
                            options  = list(create = TRUE,
                                            placeholder = "Valeur ou saisir"))
    )
  })
  
  shiny::observeEvent(input$data_rm_rows_go, {
    shiny::req(dv$df_courant, input$data_rm_col, input$data_rm_condition)
    
    col  <- input$data_rm_col
    cond <- input$data_rm_condition
    val  <- input$data_rm_val %||% ""
    
    df_avant <- nrow(dv$df_courant)
    
    # Pour "contains" on gere manuellement (grepl inverse)
    if (cond == "contains") {
      x      <- dv$df_courant[[col]]
      keep   <- !grepl(val, as.character(x), ignore.case = TRUE)
      df_res <- dv$df_courant[keep, , drop = FALSE]
    } else {
      # On garde les lignes qui NE correspondent PAS a la condition
      cond_inverse <- switch(cond,
                             "eq"    = "neq",
                             "neq"   = "eq",
                             "isna"  = "notna",
                             "notna" = "isna",
                             "gt"    = "lt",
                             "lt"    = "gt",
                             "neq"   # fallback
      )
      df_res <- appliquer_filtres_data(
        dv$df_courant,
        list(list(col = col, condition = cond_inverse, valeur = val))
      )
    }
    
    lignes_suppr <- df_avant - nrow(df_res)
    push_history(paste0("Suppression ", lignes_suppr, " lignes : ",
                        col, " ", cond, " '", val, "'"))
    dv$df_courant <- df_res
    shiny::showNotification(
      paste0(lignes_suppr, " ligne(s) supprimee(s)."),
      type = "message", duration = 4
    )
  })
  
  # ===========================================================================
  # 8. ROUTINE AUTOMATIQUE (multi-routine)
  # ===========================================================================
  
  output$data_routine_select_ui <- shiny::renderUI({
    choices <- stats::setNames(
      sapply(ROUTINES_DISPONIBLES, `[[`, "id"),
      sapply(ROUTINES_DISPONIBLES, `[[`, "label")
    )
    shiny::selectInput("data_routine_id", label = NULL,
                       choices = choices, selected = choices[1])
  })
  
  output$data_routine_desc_ui <- shiny::renderUI({
    shiny::req(input$data_routine_id)
    routine <- Filter(function(r) r$id == input$data_routine_id, ROUTINES_DISPONIBLES)
    if (length(routine) == 0) return(NULL)
    desc <- routine[[1]]$description
    shiny::div(class = "data-op-info", style = "margin-bottom:8px;",
               shiny::tags$ul(
                 style = "padding-left:14px; margin:0;",
                 lapply(desc, function(d)
                   shiny::tags$li(style = "font-size:11px; color:#A8C8E8; margin-bottom:2px;", d)
                 )
               )
    )
  })
  
  shiny::observeEvent(input$data_routine, {
    shiny::req(dv$df_courant, input$data_routine_id)
    id <- input$data_routine_id
    push_history(paste0("Routine lancée : ", id))
    df_res <- appliquer_routine(dv$df_courant, id)
    ops    <- attr(df_res, "ops_routine")
    attr(df_res, "ops_routine") <- NULL
    dv$df_courant <- df_res
    
    if (!is.null(ops) && length(ops) > 0) {
      for (op in ops) dv$ops_log <- c(dv$ops_log, paste0("[routine] ", op))
    }
    
    shiny::showNotification(
      paste0("Routine '", id, "' appliquée — ",
             if (!is.null(ops)) paste(ops, collapse = " | ") else "aucun changement"),
      type = "message", duration = 6
    )
  })
  
  output$data_routine_status <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    has_date  <- any(c("an_ref","mois_ref") %in% names(df))
    has_cpue  <- "cpue_kg_jdm" %in% names(df)
    has_ns    <- "NS" %in% names(df)
    
    shiny::div(class = "data-op-info", style = "margin-top:8px;",
               shiny::tags$ul(style = "padding-left:14px; margin:0;",
                              shiny::tags$li(style = if (has_date) "color:#2E9E6B;" else "color:#7FB3D3;",
                                             if (has_date) "\u2713 Dates parsées" else "\u25cb Dates non parsées"),
                              shiny::tags$li(style = if (has_ns) "color:#2E9E6B;" else "color:#7FB3D3;",
                                             if (has_ns) "\u2713 Nord/Sud présent" else "\u25cb Nord/Sud absent"),
                              shiny::tags$li(style = if (has_cpue) "color:#2E9E6B;" else "color:#7FB3D3;",
                                             if (has_cpue) "\u2713 CPUE calculée" else "\u25cb CPUE absente")
               )
    )
  })
  
  # ===========================================================================
  # 8b. CONVERSION D'UNITÉS
  # ===========================================================================
  
  output$data_conv_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df      <- dv$df_courant
    # Colonnes numériques uniquement
    cols_num <- names(df)[sapply(df, is.numeric)]
    if (length(cols_num) == 0) {
      return(shiny::p(style = "font-size:11px; color:#7FB3D3;",
                      "Aucune colonne numérique disponible."))
    }
    units_ch <- get_units_choices()
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(12,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Colonne source (numérique)"),
                      shiny::selectInput("data_conv_col", label = NULL,
                                         choices  = cols_num,
                                         selected = if (length(dv$cols_sel) == 1 &&
                                                        dv$cols_sel %in% cols_num)
                                           dv$cols_sel else cols_num[1])
        )
      ),
      shiny::fluidRow(
        shiny::column(6,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Unité d'entrée"),
                      shiny::selectInput("data_conv_in", label = NULL,
                                         choices = units_ch)
        ),
        shiny::column(6,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Unité de sortie"),
                      shiny::selectInput("data_conv_out", label = NULL,
                                         choices = units_ch)
        )
      ),
      shiny::fluidRow(
        shiny::column(8,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Nom colonne résultat (laisser vide = auto)"),
                      shiny::textInput("data_conv_dest", label = NULL, value = "",
                                       placeholder = "ex: poids_g")
        ),
        shiny::column(4,
                      shiny::br(),
                      shiny::actionButton("data_conv_go", "Convertir",
                                          icon  = shiny::icon("sync-alt"),
                                          class = "btn btn-sm btn-data-primary",
                                          style = "margin-top:4px; width:100%;")
        )
      )
    )
  })
  
  shiny::observeEvent(input$data_conv_go, {
    shiny::req(dv$df_courant, input$data_conv_col,
               input$data_conv_in, input$data_conv_out)
    col      <- input$data_conv_col
    u_in     <- input$data_conv_in
    u_out    <- input$data_conv_out
    col_dest <- trimws(input$data_conv_dest %||% "")
    col_dest <- if (nzchar(col_dest)) col_dest else NULL
    
    push_history(paste0("Conversion ", col, " : ", u_in, " \u2192 ", u_out))
    dv$df_courant <- convertir_unite(dv$df_courant, col, u_in, u_out, col_dest)
  })
  
  # ===========================================================================
  # 8c. COLONNE MÉTIER
  # ===========================================================================
  
  output$data_metier_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df  <- dv$df_courant
    ref <- dv$ref_metier
    
    # Colonnes candidates pour engin_cod
    cols_engin <- names(df)[grepl("engin|gear|metier", names(df), ignore.case = TRUE)]
    if (length(cols_engin) == 0) cols_engin <- names(df)
    
    # Vérification référentiel
    ref_ok <- !is.null(ref) && nrow(ref) > 0 && "metier" %in% names(ref)
    if (!ref_ok) {
      return(shiny::div(class = "data-op-info",
                        style = "border-left-color:#E07B39;",
                        shiny::icon("exclamation-triangle", style = "color:#E07B39;"),
                        " Référentiel métier introuvable ou vide."))
    }
    
    # Valeurs pour les deux niveaux
    metiers_larges <- sort(unique(ref$metier[!is.na(ref$metier)]))
    metiers_detail <- if ("metier_detail" %in% names(ref))
      sort(unique(ref$metier_detail[!is.na(ref$metier_detail)]))
    else character(0)
    
    shiny::tagList(
      # Colonne engin source
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                      "Colonne engin"),
      shiny::selectInput("data_metier_col", label = NULL,
                         choices  = names(df),
                         selected = if (length(cols_engin) > 0) cols_engin[1] else names(df)[1]),
      
      shiny::hr(style = "border-color:#123A52; margin:8px 0;"),
      
      # Niveau large — TOUJOURS proposé, coché par défaut
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                      shiny::icon("layer-group"), " Métier large (toujours créé)"),
      shiny::div(
        style = "max-height:120px; overflow-y:auto; background:#061A2B; border-radius:6px; padding:6px; border:1px solid #0D2C40; margin-bottom:8px;",
        shiny::checkboxGroupInput("data_metier_sel_large", label = NULL,
                                  choices  = stats::setNames(metiers_larges, metiers_larges),
                                  selected = metiers_larges)
      ),
      
      # Option colonne détaillée — décochée par défaut
      shiny::checkboxInput("data_metier_avec_detail",
                           label = shiny::tags$span(
                             style = "font-size:11px; color:#A8C8E8;",
                             shiny::icon("tag"), " Créer aussi la colonne métier détaillé"
                           ),
                           value = FALSE),
      
      # Panneau détail conditionnel
      shiny::conditionalPanel(
        condition = "input.data_metier_avec_detail == true",
        shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin:6px 0 4px;",
                        "Métiers détaillés à inclure"),
        shiny::div(
          style = "max-height:120px; overflow-y:auto; background:#061A2B; border-radius:6px; padding:6px; border:1px solid #0D2C40; margin-bottom:8px;",
          if (length(metiers_detail) > 0)
            shiny::checkboxGroupInput("data_metier_sel_detail", label = NULL,
                                      choices  = stats::setNames(metiers_detail, metiers_detail),
                                      selected = metiers_detail)
          else
            shiny::tags$em(style = "font-size:11px; color:#7FB3D3;",
                           "Aucun métier détaillé dans le référentiel.")
        )
      ),
      
      shiny::actionButton("data_metier_go", "Créer colonne(s) métier",
                          icon  = shiny::icon("tag"),
                          class = "btn btn-sm btn-data-primary",
                          style = "width:100%;")
    )
  })
  
  shiny::observeEvent(input$data_metier_go, {
    shiny::req(dv$df_courant, input$data_metier_col, dv$ref_metier)
    col          <- input$data_metier_col
    sel_large    <- input$data_metier_sel_large
    avec_detail  <- isTRUE(input$data_metier_avec_detail)
    sel_detail   <- if (avec_detail) input$data_metier_sel_detail else character(0)
    niveau       <- if (avec_detail) "les_deux" else "large"
    
    push_history(paste0("Colonne métier créée depuis '", col,
                        "' (niveau: ", niveau, ")"))
    dv$df_courant <- creer_colonne_metier(
      df          = dv$df_courant,
      col_engin   = col,
      ref         = dv$ref_metier,
      metiers_sel = if (avec_detail) sel_detail else sel_large,
      niveau      = niveau
    )
  })
  
  # ===========================================================================
  # 8d. FUSION DE COLONNES (coalesce col1 ← col2)
  # ===========================================================================
  
  output$data_col_merge_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df   <- dv$df_courant
    cols <- names(df)
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(5,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Colonne 1 (prioritaire)"),
                      shiny::selectInput("data_colmerge_c1", label = NULL,
                                         choices = cols, selected = cols[1])
        ),
        shiny::column(2,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;", "\u00a0"),
                      shiny::div(style = "text-align:center; line-height:34px; font-size:14px; color:#0077B6;",
                                 "1 \u2192 2")
        ),
        shiny::column(5,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Colonne 2 (appoint NA)"),
                      shiny::selectInput("data_colmerge_c2", label = NULL,
                                         choices = cols, selected = if (length(cols) > 1) cols[2] else cols[1])
        )
      ),
      shiny::div(class = "data-op-info", style = "margin-bottom:8px;",
                 shiny::icon("info-circle"),
                 " Les valeurs non-NA de la colonne 1 sont conservées. Les NA de 1 sont remplacés par les valeurs correspondantes de 2."
      ),
      shiny::fluidRow(
        shiny::column(7,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Nom colonne résultat (défaut = col 1)"),
                      shiny::textInput("data_colmerge_dest", label = NULL, value = "",
                                       placeholder = "laisser vide = écrase col 1")
        ),
        shiny::column(5,
                      shiny::checkboxInput("data_colmerge_suppr", "Supprimer col 2", value = TRUE)
        )
      ),
      shiny::actionButton("data_colmerge_go", "Fusionner",
                          icon  = shiny::icon("compress-arrows-alt"),
                          class = "btn btn-sm btn-data-primary",
                          style = "width:100%;")
    )
  })
  
  shiny::observeEvent(input$data_colmerge_go, {
    shiny::req(dv$df_courant, input$data_colmerge_c1, input$data_colmerge_c2)
    c1   <- input$data_colmerge_c1
    c2   <- input$data_colmerge_c2
    dest <- trimws(input$data_colmerge_dest %||% "")
    dest <- if (nzchar(dest)) dest else c1
    suppr <- isTRUE(input$data_colmerge_suppr)
    
    if (c1 == c2) {
      shiny::showNotification("Les deux colonnes sont identiques.", type = "warning", duration = 3)
      return()
    }
    
    push_history(paste0("Fusion colonnes : '", c1, "' \u2190 NA comblés par '", c2, "'"))
    dv$df_courant <- fusionner_colonnes(dv$df_courant, c1, c2,
                                        col_dest = dest, suppr = suppr)
    shiny::showNotification(
      paste0("Colonnes fusionnées \u2192 '", dest, "'",
             if (suppr) paste0(" ('", c2, "' supprimée)") else ""),
      type = "message", duration = 4
    )
  })
  
  
  # ===========================================================================
  # 8b. PANEL CASE WHEN (onglet Colonnes)
  # ===========================================================================
  
  # Valeurs réactives pour stocker les règles case_when
  cw_rules <- shiny::reactiveVal(list())
  
  output$data_casewhen_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df   <- dv$df_courant
    cols <- names(df)
    
    shiny::tagList(
      shiny::fluidRow(
        shiny::column(4,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Nom de la nouvelle colonne"),
                      shiny::textInput("data_cw_newcol", label = NULL,
                                       placeholder = "ex: categorie_poids")
        ),
        shiny::column(4,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Colonne de r\u00e9f\u00e9rence"),
                      shiny::selectInput("data_cw_refcol", label = NULL,
                                         choices = cols, selected = cols[1])
        ),
        shiny::column(4,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      "Valeur par d\u00e9faut (sinon NA)"),
                      shiny::textInput("data_cw_default", label = NULL,
                                       placeholder = "laisser vide = NA")
        )
      ),
      
      shiny::hr(style = "border-color:#123A52; margin:8px 0;"),
      
      # R\u00e8gles dynamiques
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:6px;",
                      shiny::icon("list-ol"), " R\u00e8gles (si ... alors ...)"),
      
      shiny::uiOutput("data_cw_rules_ui"),
      
      shiny::br(),
      shiny::div(class = "data-action-bar",
                 shiny::actionButton("data_cw_add_rule", "Ajouter une r\u00e8gle",
                                     icon  = shiny::icon("plus"),
                                     class = "btn btn-sm btn-data-action"),
                 shiny::actionButton("data_cw_rm_rule", "Supprimer derni\u00e8re",
                                     icon  = shiny::icon("minus"),
                                     class = "btn btn-sm btn-data-danger"),
                 shiny::actionButton("data_cw_go", "Cr\u00e9er la colonne",
                                     icon  = shiny::icon("code-branch"),
                                     class = "btn btn-sm btn-data-primary")
      )
    )
  })
  
  # Ajouter une r\u00e8gle
  shiny::observeEvent(input$data_cw_add_rule, {
    rules <- cw_rules()
    n     <- length(rules) + 1
    rules[[n]] <- list(id = n)
    cw_rules(rules)
  })
  
  # Supprimer la derni\u00e8re r\u00e8gle
  shiny::observeEvent(input$data_cw_rm_rule, {
    rules <- cw_rules()
    if (length(rules) > 0) cw_rules(rules[-length(rules)])
  })
  
  # UI des r\u00e8gles dynamiques
  output$data_cw_rules_ui <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df    <- dv$df_courant
    rules <- cw_rules()
    
    if (length(rules) == 0) {
      return(shiny::div(class = "data-op-info",
                        shiny::icon("info-circle"),
                        " Cliquez sur \"Ajouter une r\u00e8gle\" pour d\u00e9finir vos conditions."))
    }
    
    # D\u00e9tecter le type de la colonne de r\u00e9f\u00e9rence pour les valeurs sugg\u00e9r\u00e9es
    ref_col    <- input$data_cw_refcol
    col_vals   <- character(0)
    is_numeric <- FALSE
    if (!is.null(ref_col) && ref_col %in% names(df)) {
      col_data   <- df[[ref_col]]
      is_numeric <- is.numeric(col_data)
      if (!is_numeric) {
        col_vals <- sort(unique(as.character(stats::na.omit(col_data))))
        if (length(col_vals) > 100) col_vals <- col_vals[1:100]
      }
    }
    
    conditions_num <- c(
      "= (\u00e9gal)"           = "eq",
      "\u2260 (diff\u00e9rent)" = "neq",
      "> (sup\u00e9rieur)"      = "gt",
      "< (inf\u00e9rieur)"      = "lt",
      ">= (sup. ou \u00e9gal)"  = "gte",
      "<= (inf. ou \u00e9gal)"  = "lte",
      "entre (inclus)"           = "between",
      "est NA"                   = "isna",
      "n'est pas NA"             = "notna"
    )
    conditions_chr <- c(
      "= (\u00e9gal)"           = "eq",
      "\u2260 (diff\u00e9rent)" = "neq",
      "contient"                 = "contains",
      "ne contient pas"          = "not_contains",
      "commence par"             = "startswith",
      "se termine par"           = "endswith",
      "est dans la liste"        = "in_list",
      "est NA"                   = "isna",
      "n'est pas NA"             = "notna"
    )
    
    conds <- if (is_numeric) conditions_num else conditions_chr
    
    rule_rows <- lapply(seq_along(rules), function(i) {
      id_cond   <- paste0("data_cw_cond_",   i)
      id_val1   <- paste0("data_cw_val1_",   i)
      id_val2   <- paste0("data_cw_val2_",   i)
      id_result <- paste0("data_cw_result_", i)
      
      cur_cond <- if (!is.null(input[[id_cond]])) input[[id_cond]] else "eq"
      needs_val <- !cur_cond %in% c("isna", "notna")
      needs_v2  <- cur_cond == "between"
      
      shiny::div(style = "background:#061A2B; border:1px solid #123A52; border-radius:6px; padding:8px; margin-bottom:6px;",
                 shiny::tags$div(style = "font-size:10px; color:#0077B6; font-weight:600; margin-bottom:4px;",
                                 paste0("R\u00e8gle ", i)),
                 shiny::fluidRow(
                   shiny::column(3,
                                 shiny::tags$div(style = "font-size:10px;color:#7FB3D3;", "Condition"),
                                 shiny::selectInput(id_cond, label = NULL, choices = conds,
                                                    selected = cur_cond)
                   ),
                   shiny::column(3,
                                 shiny::tags$div(style = "font-size:10px;color:#7FB3D3;",
                                                 if (needs_v2) "Valeur min" else "Valeur"),
                                 if (needs_val) {
                                   if (length(col_vals) > 0 && !cur_cond %in% c("in_list","contains","not_contains","startswith","endswith")) {
                                     # Valeur unique : dropdown simple
                                     shiny::selectInput(id_val1, label = NULL, choices = col_vals)
                                   } else if (length(col_vals) > 0 && cur_cond == "in_list") {
                                     # Liste multiple : selectize multi
                                     shiny::selectInput(id_val1, label = NULL, choices = col_vals,
                                                        multiple = TRUE,
                                                        options = list(placeholder = "Choisir valeur(s)..."))
                                   } else if (length(col_vals) > 0 && cur_cond %in% c("contains","not_contains","startswith","endswith")) {
                                     # Contient : selectize avec saisie libre ET valeurs suggérées
                                     shiny::selectizeInput(id_val1, label = NULL,
                                                           choices  = col_vals,
                                                           selected = NULL,
                                                           options  = list(create = TRUE,
                                                                           placeholder = "Choisir ou saisir..."))
                                   } else {
                                     shiny::textInput(id_val1, label = NULL,
                                                      placeholder = if (is_numeric) "ex: 100" else "ex: OUI")
                                   }
                                 } else {
                                   shiny::tags$div()
                                 }
                   ),
                   shiny::column(3,
                                 if (needs_v2) {
                                   shiny::tagList(
                                     shiny::tags$div(style = "font-size:10px;color:#7FB3D3;", "Valeur max"),
                                     shiny::textInput(id_val2, label = NULL, placeholder = "ex: 500")
                                   )
                                 } else {
                                   shiny::tags$div()
                                 }
                   ),
                   shiny::column(3,
                                 shiny::tags$div(style = "font-size:10px;color:#7FB3D3;", "Alors = "),
                                 shiny::textInput(id_result, label = NULL,
                                                  placeholder = "ex: Grand")
                   )
                 )
      )
    })
    
    do.call(shiny::tagList, rule_rows)
  })
  
  # Cr\u00e9er la colonne case_when
  shiny::observeEvent(input$data_cw_go, {
    shiny::req(dv$df_courant)
    df      <- dv$df_courant
    rules   <- cw_rules()
    new_col <- trimws(input$data_cw_newcol %||% "")
    ref_col <- input$data_cw_refcol
    default_val <- trimws(input$data_cw_default %||% "")
    
    if (!nzchar(new_col)) {
      shiny::showNotification("Veuillez entrer un nom pour la nouvelle colonne.", type = "warning"); return()
    }
    if (!ref_col %in% names(df)) {
      shiny::showNotification("Colonne de r\u00e9f\u00e9rence introuvable.", type = "warning"); return()
    }
    if (length(rules) == 0) {
      shiny::showNotification("Ajoutez au moins une r\u00e8gle.", type = "warning"); return()
    }
    
    col_data   <- df[[ref_col]]
    is_numeric <- is.numeric(col_data)
    result_vec <- rep(if (nzchar(default_val)) default_val else NA_character_, nrow(df))
    
    tryCatch({
      # Appliquer les r\u00e8gles en ordre inverse (derni\u00e8re r\u00e8gle = plus basse priorit\u00e9)
      for (i in rev(seq_along(rules))) {
        cond   <- input[[paste0("data_cw_cond_",   i)]]
        val1_r <- input[[paste0("data_cw_val1_",   i)]]
        val2_r <- input[[paste0("data_cw_val2_",   i)]]
        res_r  <- input[[paste0("data_cw_result_", i)]]
        
        val1 <- if (!is.null(val1_r)) trimws(val1_r) else ""
        val2 <- if (!is.null(val2_r)) trimws(val2_r) else ""
        res  <- if (!is.null(res_r))  trimws(res_r)  else ""
        
        mask <- switch(cond,
                       "eq"          = if (is_numeric) !is.na(col_data) & col_data == suppressWarnings(as.numeric(val1)) else !is.na(col_data) & as.character(col_data) == val1,
                       "neq"         = if (is_numeric) !is.na(col_data) & col_data != suppressWarnings(as.numeric(val1)) else !is.na(col_data) & as.character(col_data) != val1,
                       "gt"          = !is.na(col_data) & col_data >  suppressWarnings(as.numeric(val1)),
                       "lt"          = !is.na(col_data) & col_data <  suppressWarnings(as.numeric(val1)),
                       "gte"         = !is.na(col_data) & col_data >= suppressWarnings(as.numeric(val1)),
                       "lte"         = !is.na(col_data) & col_data <= suppressWarnings(as.numeric(val1)),
                       "between"     = !is.na(col_data) & col_data >= suppressWarnings(as.numeric(val1)) & col_data <= suppressWarnings(as.numeric(val2)),
                       "isna"        = is.na(col_data),
                       "notna"       = !is.na(col_data),
                       "contains"    = !is.na(col_data) & grepl(val1, as.character(col_data), fixed = TRUE),
                       "not_contains"= !is.na(col_data) & !grepl(val1, as.character(col_data), fixed = TRUE),
                       "startswith"  = !is.na(col_data) & startsWith(as.character(col_data), val1),
                       "endswith"    = !is.na(col_data) & endsWith(as.character(col_data), val1),
                       "in_list"     = {
                         # val1 peut être un vecteur (selectize multiple) ou une string CSV
                         vals_list <- if (length(val1) > 1) trimws(val1) else trimws(strsplit(val1, ",")[[1]])
                         !is.na(col_data) & as.character(col_data) %in% vals_list
                       },
                       rep(FALSE, nrow(df))
        )
        
        result_vec[mask] <- res
      }
      
      push_history(paste0("Case When : colonne \'", new_col, "\' cr\u00e9\u00e9e depuis \'", ref_col, "\'"))
      dv$df_courant[[new_col]] <- result_vec
      shiny::showNotification(paste0("Colonne \'", new_col, "\' cr\u00e9\u00e9e avec succ\u00e8s !"),
                              type = "message", duration = 4)
      
      # Reset r\u00e8gles
      cw_rules(list())
      
    }, error = function(e) {
      shiny::showNotification(paste0("Erreur : ", e$message), type = "error", duration = 6)
    })
  })
  
  # ===========================================================================
  # 8c. PANEL GROUP BY (onglet Colonnes)
  # ===========================================================================
  
  output$data_groupby_panel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df       <- dv$df_courant
    cols     <- names(df)
    num_cols <- cols[sapply(df, is.numeric)]
    
    shiny::tagList(
      # Info explicative
      shiny::div(class = "data-op-info", style = "margin-bottom:10px;",
                 shiny::icon("info-circle"),
                 " Choisissez les colonnes de regroupement. Toutes les colonnes num\u00e9riques restantes seront agr\u00e9g\u00e9es automatiquement."
      ),
      
      # Ligne 1 : group by + colonnes + bouton (toujours visible)
      shiny::fluidRow(
        shiny::column(5,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      shiny::icon("layer-group"), " Regrouper par"),
                      shiny::selectInput("data_gb_by", label = NULL,
                                         choices  = cols,
                                         multiple = TRUE,
                                         selected = cols[1])
        ),
        shiny::column(4,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                      shiny::icon("hashtag"), " Colonnes \u00e0 agr\u00e9ger"),
                      shiny::selectInput("data_gb_cols", label = NULL,
                                         choices  = if (length(num_cols) > 0) num_cols else cols,
                                         multiple = TRUE,
                                         selected = num_cols)
        ),
        shiny::column(3,
                      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;", "\u00a0"),
                      shiny::actionButton("data_gb_go", "Agr\u00e9ger",
                                          icon  = shiny::icon("layer-group"),
                                          class = "btn btn-sm btn-data-primary",
                                          style = "width:100%; margin-top:2px;"),
                      shiny::br(), shiny::br(),
                      shiny::checkboxInput("data_gb_replace", "Remplacer le tableau", value = FALSE),
                      shiny::tags$div(style = "font-size:10px;color:#7FB3D3;", "Si non coch\u00e9 : pr\u00e9visualisation")
        )
      ),
      
      shiny::hr(style = "border-color:#123A52; margin:8px 0;"),
      
      # Ligne 2 : fonctions en horizontal via CSS
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:6px;",
                      shiny::icon("calculator"), " Fonction(s) \u00e0 calculer"),
      shiny::tags$style(shiny::HTML("
        #data_gb_funs .shiny-options-group {
          display: flex !important;
          flex-wrap: wrap !important;
          gap: 6px 18px !important;
        }
        #data_gb_funs .shiny-options-group label {
          font-size: 12px !important;
          color: #C9D6DF !important;
          display: flex !important;
          align-items: center !important;
          gap: 5px !important;
          cursor: pointer;
        }
        #data_gb_funs .shiny-options-group input[type=checkbox] {
          accent-color: #0077B6;
          width: 14px; height: 14px;
        }
      ")),
      shiny::checkboxGroupInput("data_gb_funs", label = NULL,
                                choices  = c("Somme"       = "sum",
                                             "Moyenne"     = "mean",
                                             "M\u00e9diane" = "median",
                                             "Max"         = "max",
                                             "Min"         = "min",
                                             "Nb lignes"   = "n",
                                             "Nb distincts"= "n_distinct"),
                                selected = "sum"),
      
      shiny::br(),
      shiny::uiOutput("data_gb_preview")
    )
  })
  
  shiny::observeEvent(input$data_gb_go, {
    shiny::req(dv$df_courant, input$data_gb_by, input$data_gb_funs)
    df      <- dv$df_courant
    by_cols <- input$data_gb_by
    funs    <- input$data_gb_funs
    replace <- isTRUE(input$data_gb_replace)
    
    # Colonnes \u00e0 agr\u00e9ger : s\u00e9lection utilisateur ou toutes les num\u00e9riques hors group by
    agg_cols <- input$data_gb_cols
    if (is.null(agg_cols) || length(agg_cols) == 0) {
      agg_cols <- names(df)[sapply(df, is.numeric) & !names(df) %in% by_cols]
    } else {
      agg_cols <- agg_cols[!agg_cols %in% by_cols]
    }
    
    # "n" (nb lignes) ne n\u00e9cessite pas de colonnes num\u00e9riques
    needs_agg_cols <- any(!funs %in% c("n"))
    if (needs_agg_cols && length(agg_cols) == 0) {
      shiny::showNotification(
        "Aucune colonne num\u00e9rique \u00e0 agr\u00e9ger. S\u00e9lectionnez des colonnes ou ajoutez 'Nb lignes'.",
        type = "warning", duration = 5
      )
      return()
    }
    
    tryCatch({
      parts <- list()
      
      # --- Nb lignes (n) : une seule colonne r\u00e9sultat ---
      if ("n" %in% funs) {
        ref_col <- if (length(agg_cols) > 0) agg_cols[1] else names(df)[!names(df) %in% by_cols][1]
        tmp <- stats::aggregate(df[[ref_col]],
                                by  = df[, by_cols, drop = FALSE],
                                FUN = length)
        names(tmp)[ncol(tmp)] <- "n_lignes"
        parts[["n_lignes"]] <- tmp
      }
      
      # --- Fonctions sur les colonnes num\u00e9riques ---
      funs_num <- funs[funs != "n"]
      for (fun in funs_num) {
        FUN <- switch(fun,
                      "sum"       = function(x) sum(x,  na.rm = TRUE),
                      "mean"      = function(x) mean(x, na.rm = TRUE),
                      "median"    = function(x) stats::median(x, na.rm = TRUE),
                      "max"       = function(x) max(x,  na.rm = TRUE),
                      "min"       = function(x) min(x,  na.rm = TRUE),
                      "n_distinct"= function(x) length(unique(x[!is.na(x)])),
                      function(x) sum(x, na.rm = TRUE)
        )
        for (col in agg_cols) {
          tmp <- stats::aggregate(df[[col]],
                                  by  = df[, by_cols, drop = FALSE],
                                  FUN = FUN)
          new_nm <- if (length(funs_num) == 1 && length(agg_cols) >= 1) col
          else paste0(col, "_", fun)
          names(tmp)[ncol(tmp)] <- new_nm
          parts[[paste0(col, "_", fun)]] <- tmp
        }
      }
      
      # --- Fusion des parties ---
      if (length(parts) == 0) {
        shiny::showNotification("Aucune agr\u00e9gation produite.", type = "warning"); return()
      }
      result <- Reduce(function(a, b) merge(a, b, by = by_cols, all = TRUE), parts)
      
      # Tri
      result <- result[do.call(order, result[, by_cols, drop = FALSE]), ]
      rownames(result) <- NULL
      
      if (replace) {
        push_history(paste0("Group By : ", paste(by_cols, collapse = ", ")))
        dv$df_courant      <- result
        dv$groupby_preview <- NULL
        shiny::showNotification(
          paste0("Tableau agr\u00e9g\u00e9 : ", nrow(result), " lignes \u00d7 ", ncol(result), " colonnes"),
          type = "message", duration = 5
        )
      } else {
        dv$groupby_preview <- result
        shiny::showNotification(
          paste0("Pr\u00e9visualisation : ", nrow(result), " lignes. Cochez 'Remplacer' pour appliquer."),
          type = "message", duration = 4
        )
      }
      
    }, error = function(e) {
      shiny::showNotification(paste0("Erreur Group By : ", e$message), type = "error", duration = 6)
    })
  })
  
  output$data_gb_preview <- shiny::renderUI({
    shiny::req(dv$groupby_preview)
    df_prev <- dv$groupby_preview
    shiny::tagList(
      shiny::hr(style = "border-color:#123A52; margin:8px 0;"),
      shiny::div(style = "font-size:11px;color:#2E9E6B;margin-bottom:6px;",
                 shiny::icon("eye"),
                 paste0(" R\u00e9sultat : ", nrow(df_prev), " lignes \u00d7 ", ncol(df_prev), " colonnes")),
      DT::renderDataTable(
        df_prev,
        options  = list(pageLength = 10, scrollX = TRUE, dom = "tip",
                        initComplete = DT::JS(
                          "function(settings,json){",
                          "$(this.api().table().header()).css({'background-color':'#123A52','color':'#fff'});",
                          "}"
                        )),
        rownames = FALSE,
        class    = "compact stripe"
      )
    )
  })
  
  # ===========================================================================
  # 9. FUSION FICHIER
  # ===========================================================================
  
  # Chargement d'un fichier additionnel (déclencheur : bouton "Ajouter un fichier")
  shiny::observeEvent(input$data_fichier2, {
    shiny::req(input$data_fichier2)
    fichiers <- input$data_fichier2   # peut contenir plusieurs fichiers si multiple=TRUE
    for (i in seq_len(nrow(fichiers))) {
      ext <- tolower(tools::file_ext(fichiers$name[i]))
      df_new <- charger_fichier_data(fichiers$datapath[i], ext)
      if (!is.null(df_new)) {
        # On ajoute à la liste cumulative en évitant les doublons de nom
        nom <- fichiers$name[i]
        noms_existants <- names(dv$df2_liste)
        if (nom %in% noms_existants) {
          # Suffixer si le fichier est déjà dans la liste
          nom <- make.unique(c(noms_existants, nom), sep = "_")[length(noms_existants) + 1]
        }
        dv$df2_liste <- c(dv$df2_liste, stats::setNames(list(df_new), nom))
        shiny::showNotification(
          paste0("\u2795 \"", nom, "\" ajouté (",
                 nrow(df_new), "\u00d7", ncol(df_new), ") — ",
                 length(dv$df2_liste), " fichier(s) en file"),
          type = "message", duration = 3
        )
      }
    }
  })
  
  # Suppression d'un fichier de la liste (bouton "×" dans l'UI)
  shiny::observeEvent(input$data_merge_remove, {
    idx <- as.integer(input$data_merge_remove)
    if (!is.na(idx) && idx >= 1 && idx <= length(dv$df2_liste)) {
      nom_retire <- names(dv$df2_liste)[idx]
      dv$df2_liste <- dv$df2_liste[-idx]
      shiny::showNotification(
        paste0("\"", nom_retire, "\" retiré de la file."),
        type = "warning", duration = 2
      )
    }
  })
  
  output$data_merge_ui <- shiny::renderUI({
    shiny::req(dv$df_courant)
    
    # --- Liste des fichiers en attente ---
    liste_ui <- if (length(dv$df2_liste) == 0) {
      shiny::tags$p(style = "font-size:11px; color:#7FB3D3; margin:4px 0 8px;",
                    "Aucun fichier ajouté.")
    } else {
      shiny::tagList(
        shiny::tags$div(
          style = "font-size:11px; color:#2E9E6B; margin-bottom:6px;",
          shiny::icon("layer-group"),
          paste0(" ", length(dv$df2_liste), " fichier(s) en file :")
        ),
        shiny::tags$ul(
          style = "padding-left:12px; margin:0 0 8px;",
          lapply(seq_along(dv$df2_liste), function(i) {
            df_i <- dv$df2_liste[[i]]
            shiny::tags$li(
              style = "font-size:11px; color:#A8C8E8; margin-bottom:2px;",
              shiny::tags$span(
                style = "margin-right:6px;",
                names(dv$df2_liste)[i],
                shiny::tags$span(
                  style = "color:#7FB3D3;",
                  paste0(" (", nrow(df_i), "\u00d7", ncol(df_i), ")")
                )
              ),
              shiny::actionLink(
                inputId = "data_merge_remove",
                label   = "\u2715",
                style   = "color:#E05050; font-size:11px;",
                onclick = paste0(
                  "Shiny.setInputValue('data_merge_remove', ", i,
                  ", {priority: 'event'});"
                )
              )
            )
          })
        )
      )
    }
    
    # --- Options de fusion (seulement pertinentes si ≥1 fichier) ---
    cols_communes <- if (length(dv$df2_liste) > 0)
      Reduce(intersect, c(list(names(dv$df_courant)),
                          lapply(dv$df2_liste, names)))
    else character(0)
    
    options_ui <- shiny::fluidRow(
      shiny::column(6,
                    shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                    "Type de fusion"),
                    shiny::selectInput("data_merge_type", label = NULL,
                                       choices = c("Jointure gauche"   = "left",
                                                   "Jointure droite"   = "right",
                                                   "Jointure interne"  = "inner",
                                                   "Jointure totale"   = "full",
                                                   "Empilement (rbind)" = "rbind"))
      ),
      shiny::column(6,
                    if (length(cols_communes) > 0)
                      shiny::tagList(
                        shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                                        "Clé(s) de jointure"),
                        shiny::selectizeInput("data_merge_by", label = NULL,
                                              choices  = cols_communes,
                                              selected = cols_communes[1],
                                              multiple = TRUE,
                                              options  = list(plugins = list("remove_button")))
                      )
      )
    )
    
    shiny::tagList(
      liste_ui,
      if (length(dv$df2_liste) > 0) options_ui,
      if (length(dv$df2_liste) > 0)
        shiny::actionButton("data_merge_go", "Fusionner",
                            icon  = shiny::icon("code-merge"),
                            class = "btn btn-sm btn-data-primary",
                            style = "width:100%; margin-top:4px;")
    )
  })
  
  shiny::observeEvent(input$data_merge_go, {
    shiny::req(dv$df_courant, length(dv$df2_liste) > 0)
    type <- input$data_merge_type %||% "rbind"
    by   <- input$data_merge_by
    
    push_history(paste0("Fusion ", type,
                        " (", length(dv$df2_liste), " fichier(s)) sur [",
                        paste(by, collapse = ","), "]"))
    
    df_result <- dv$df_courant
    erreurs   <- character(0)
    
    for (i in seq_along(dv$df2_liste)) {
      df_extra <- dv$df2_liste[[i]]
      df_result <- tryCatch(
        fusionner_fichiers(df_result, df_extra,
                           type = type,
                           by   = if (type != "rbind") by else NULL),
        error = function(e) {
          erreurs <<- c(erreurs, paste0("Fichier ", i, " : ", e$message))
          df_result  # on continue avec l'état actuel
        }
      )
    }
    
    if (length(erreurs) > 0) {
      shiny::showNotification(
        paste("Erreur(s) lors de la fusion :", paste(erreurs, collapse = " | ")),
        type = "error", duration = 8
      )
    }
    
    dv$df_courant <- df_result
    dv$df2_liste  <- list()   # vider la file après fusion réussie
    
    shiny::showNotification(
      paste0("Fusion terminée — ", nrow(dv$df_courant), " × ", ncol(dv$df_courant)),
      type = "message", duration = 4
    )
  })
  
  # ===========================================================================
  # 10. RÉSUMÉ STATISTIQUE
  # ===========================================================================
  
  output$data_summary_table <- DT::renderDataTable({
    shiny::req(dv$df_courant)
    df_sum <- resumer_donnees(dv$df_courant)
    DT::datatable(
      df_sum,
      options = list(
        pageLength = 30, scrollX = TRUE, dom = "tip",
        language = list(
          url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/French.json"
        )
      ),
      rownames = FALSE,
      class    = "display nowrap"
    ) |>
      DT::formatStyle("Pct_NA",
                      backgroundColor = DT::styleInterval(
                        c(5, 20, 50),
                        c("#0B2A3D", "#1A3A20", "#3A2A0B", "#4A1020")
                      )
      )
  })
  
  # ===========================================================================
  # 10bis. VALEURS UNIQUES PAR COLONNE
  # ===========================================================================
  
  output$data_uniques_col_sel <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    shiny::selectInput("data_uniques_col", label = NULL,
                       choices  = stats::setNames(names(df), names(df)),
                       selected = names(df)[1])
  })
  
  output$data_uniques_kpi <- shiny::renderUI({
    shiny::req(dv$df_courant, input$data_uniques_col)
    col <- input$data_uniques_col
    shiny::req(col %in% names(dv$df_courant))
    x <- dv$df_courant[[col]]
    n_uniq <- length(unique(x))
    n_na   <- sum(is.na(x))
    shiny::tags$small(style = "color:#7FB3D3;",
                      shiny::icon("list-ol", style = "color:#0077B6;"),
                      sprintf(" %s valeur(s) unique(s)", format(n_uniq, big.mark = "\u202f")),
                      if (n_na > 0) sprintf(" \u2014 %s valeur(s) NA", format(n_na, big.mark = "\u202f")) else NULL
    )
  })
  
  output$data_uniques_table <- DT::renderDataTable({
    shiny::req(dv$df_courant, input$data_uniques_col)
    col <- input$data_uniques_col
    shiny::req(col %in% names(dv$df_courant))
    
    x <- dv$df_courant[[col]]
    tab <- table(x, useNA = "ifany")
    df_uniq <- data.frame(
      Valeur    = names(tab),
      Effectif  = as.integer(tab),
      stringsAsFactors = FALSE
    )
    df_uniq$Valeur[is.na(df_uniq$Valeur)] <- "(NA)"
    df_uniq <- df_uniq[order(-df_uniq$Effectif), , drop = FALSE]
    df_uniq$Pourcentage <- round(100 * df_uniq$Effectif / sum(df_uniq$Effectif), 1)
    
    DT::datatable(
      df_uniq,
      options = list(
        pageLength = 25, scrollX = TRUE, dom = "ftip",
        language = list(
          url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/French.json"
        )
      ),
      rownames = FALSE,
      class    = "display nowrap"
    ) |>
      DT::formatStyle("Effectif",
                      background = DT::styleColorBar(df_uniq$Effectif, "#0077B6"),
                      backgroundSize  = "98% 70%",
                      backgroundRepeat = "no-repeat",
                      backgroundPosition = "center"
      )
  })
  
  # ===========================================================================
  # 10ter. CORRECTION DE LA DONNÉE ENGIN
  # ===========================================================================
  
  # Colonnes attendues pour l'analyse de cohérence engin/espèce, et leurs
  # noms par défaut tentés (même esprit que SQ_COLS_ATTENDUES du module Quotas)
  DATA_ENGIN_COLS_ATTENDUES <- list(
    nom_navire   = c("nom_navire", "navire"),
    cfr_cod      = c("cfr_cod", "cfr"),
    quartier_cod = c("quartier_cod", "quartier"),
    esp_cod_fao  = c("esp_cod_fao", "cod_fao", "espece_cod"),
    engin_cod    = c("engin_cod", "engin")
  )
  DATA_ENGIN_COLS_LABELS <- c(
    nom_navire   = "Nom du navire",
    cfr_cod      = "Code CFR",
    quartier_cod = "Quartier maritime",
    esp_cod_fao  = "Espèce (code FAO)",
    engin_cod    = "Engin de pêche (code)"
  )
  
  output$data_engin_mapping_ui <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    cols_dispo <- c("(auto-detect)", names(df))
    
    shiny::tagList(
      lapply(names(DATA_ENGIN_COLS_ATTENDUES), function(var) {
        candidats  <- DATA_ENGIN_COLS_ATTENDUES[[var]]
        match_auto <- intersect(candidats, names(df))
        selected   <- if (length(match_auto) > 0) match_auto[1] else "(auto-detect)"
        
        shiny::div(
          style = "margin-bottom:8px;",
          shiny::div(style = "font-size:11px; font-weight:600; color:#EAF2F8;",
                     DATA_ENGIN_COLS_LABELS[[var]]),
          shiny::selectInput(paste0("data_engin_map_", var), label = NULL,
                             choices  = cols_dispo,
                             selected = selected)
        )
      })
    )
  })
  
  # Applique le mapping et renvoie un df réduit aux 5 colonnes standardisées
  data_engin_mapped <- shiny::reactive({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    
    out <- list()
    for (var in names(DATA_ENGIN_COLS_ATTENDUES)) {
      val <- input[[paste0("data_engin_map_", var)]]
      if (is.null(val) || val == "(auto-detect)" || !val %in% names(df)) {
        candidats  <- DATA_ENGIN_COLS_ATTENDUES[[var]]
        match_auto <- intersect(candidats, names(df))
        val <- if (length(match_auto) > 0) match_auto[1] else NA
      }
      out[[var]] <- val
    }
    
    manquantes <- names(out)[vapply(out, is.na, logical(1))]
    shiny::validate(
      shiny::need(length(manquantes) == 0,
                  paste0("Colonnes non mappées : ", paste(manquantes, collapse = ", ")))
    )
    
    df_out <- stats::setNames(
      df[, unlist(out), drop = FALSE],
      names(out)
    )
    df_out
  })
  
  # ── Base des incohérences connues (fichier www/, rechargeable) ──────────
  data_engin_base_rv <- shiny::reactiveVal(NULL)
  
  shiny::observe({
    if (is.null(data_engin_base_rv())) {
      data_engin_base_rv(charger_base_incoherences())
    }
  })
  
  shiny::observeEvent(input$data_engin_reload_base, {
    data_engin_base_rv(charger_base_incoherences())
    shiny::showNotification("Base des incohérences rechargée.", type = "message", duration = 3)
  })
  
  output$data_engin_base_info <- shiny::renderUI({
    base <- data_engin_base_rv()
    if (is.null(base) || nrow(base) == 0) {
      return(shiny::tags$small(style = "color:#E07B39;",
                               shiny::icon("exclamation-circle"),
                               " Aucune base trouvée (ou base vide) — toutes les incohérences seront considérées comme nouvelles."))
    }
    shiny::tags$small(style = "color:#7FB3D3;",
                      shiny::icon("check-circle", style = "color:#2E9E6B;"),
                      sprintf(" %s entrée(s) référencée(s)", format(nrow(base), big.mark = "\u202f"))
    )
  })
  
  # ── Lancement de l'analyse de cohérence ──────────────────────────────────
  data_engin_resultats <- shiny::eventReactive(input$data_engin_run, {
    df_mapped <- tryCatch(data_engin_mapped(), error = function(e) {
      shiny::showNotification(paste("Erreur mapping :", e$message), type = "error", duration = 6)
      NULL
    })
    shiny::req(df_mapped)
    
    if (!exists("SQ_ENGINS_COHERENTS")) {
      shiny::showNotification(
        "Référentiel SQ_ENGINS_COHERENTS introuvable (module Suivi des quotas non chargé).",
        type = "error", duration = 8
      )
      shiny::req(FALSE)
    }
    
    base <- data_engin_base_rv()
    if (is.null(base)) base <- charger_base_incoherences()
    
    shiny::withProgress(message = "Analyse de cohérence engin/espèce…", value = 0.3, {
      toutes    <- tryCatch(detecter_incoherences_engin(df_mapped, SQ_ENGINS_COHERENTS),
                            error = function(e) {
                              shiny::showNotification(paste("Erreur détection :", e$message),
                                                      type = "error", duration = 8)
                              NULL
                            })
      shiny::req(toutes)
      nouveaux <- incoherences_non_referencees(toutes, base)
      
      list(toutes = toutes, nouveaux = nouveaux)
    })
  })
  
  output$data_engin_kpi <- shiny::renderUI({
    res <- data_engin_resultats()
    shiny::req(res)
    shiny::tagList(
      shiny::div(class = "data-op-info",
                 shiny::icon("exclamation-triangle"),
                 sprintf(" %s combinaison(s) incohérente(s) détectée(s)", nrow(res$toutes))
      ),
      shiny::div(class = "data-op-info", style = "margin-top:6px; border-left-color:#E07B39;",
                 shiny::icon("plus-circle"),
                 sprintf(" dont %s non encore référencée(s) dans la base", nrow(res$nouveaux))
      )
    )
  })
  
  output$data_engin_table_nouveaux <- DT::renderDataTable({
    res <- data_engin_resultats()
    shiny::req(res)
    DT::datatable(
      res$nouveaux,
      options = list(pageLength = 15, scrollX = TRUE, dom = "ftip",
                     language = list(url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/French.json")),
      rownames = FALSE,
      class    = "display nowrap"
    )
  })
  
  output$data_engin_table_toutes <- DT::renderDataTable({
    res <- data_engin_resultats()
    shiny::req(res)
    DT::datatable(
      res$toutes,
      options = list(pageLength = 15, scrollX = TRUE, dom = "ftip",
                     language = list(url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/French.json")),
      rownames = FALSE,
      class    = "display nowrap"
    )
  })
  
  # Export des nouveaux cas non référencés, prêt à compléter (colonne
  # engin_corrige vide) et à intégrer à la base par l'admin
  output$data_engin_export_nouveaux <- shiny::downloadHandler(
    filename = function()
      paste0("nouvelles_incoherences_engin_", format(Sys.Date(), "%Y%m%d"), ".xlsx"),
    content = function(file) {
      res <- data_engin_resultats()
      shiny::req(res)
      df_export <- res$nouveaux
      df_export$engin_corrige <- NA_character_   # colonne à compléter par l'admin
      
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "nouvelles_incoherences")
      openxlsx::writeData(wb, "nouvelles_incoherences", df_export)
      openxlsx::addStyle(wb, "nouvelles_incoherences",
                         style = openxlsx::createStyle(
                           fontColour = "#FFFFFF", fgFill = "#0077B6",
                           halign = "center", textDecoration = "bold"
                         ),
                         rows = 1, cols = seq_len(ncol(df_export)), gridExpand = TRUE)
      openxlsx::setColWidths(wb, "nouvelles_incoherences",
                             cols = seq_len(ncol(df_export)), widths = "auto")
      openxlsx::saveWorkbook(wb, file, overwrite = TRUE)
    }
  )
  
  # ── Application de la suggestion : ajoute engin_sug au df courant ───────
  shiny::observeEvent(input$data_engin_apply_sug, {
    df_mapped <- tryCatch(data_engin_mapped(), error = function(e) {
      shiny::showNotification(paste("Erreur mapping :", e$message), type = "error", duration = 6)
      NULL
    })
    shiny::req(df_mapped)
    
    if (!exists("SQ_ENGINS_COHERENTS")) {
      shiny::showNotification(
        "Référentiel SQ_ENGINS_COHERENTS introuvable (module Suivi des quotas non chargé).",
        type = "error", duration = 8
      )
      return()
    }
    
    base <- data_engin_base_rv()
    if (is.null(base)) base <- charger_base_incoherences()
    
    shiny::withProgress(message = "Calcul de engin_sug…", value = 0.4, {
      df_avec_sug <- tryCatch(
        construire_engin_suggere(df_mapped, SQ_ENGINS_COHERENTS, base),
        error = function(e) {
          shiny::showNotification(paste("Erreur engin_sug :", e$message), type = "error", duration = 8)
          NULL
        }
      )
      shiny::req(df_avec_sug)
      
      push_history("Colonne 'engin_sug' créée (correction de la donnée engin)")
      dv$df_courant$engin_sug <- df_avec_sug$engin_sug
      
      n_etoile <- sum(grepl("\\*$", df_avec_sug$engin_sug))
      shiny::showNotification(
        sprintf("Colonne 'engin_sug' ajoutée — %s ligne(s) marquée(s) d'une * (incohérence non corrigée).", n_etoile),
        type = "message", duration = 5
      )
    })
  })
  
  # ===========================================================================
  # 11. HISTORIQUE + UNDO
  # ===========================================================================
  
  output$data_historique <- shiny::renderUI({
    if (length(dv$ops_log) == 0)
      return(shiny::p(style="font-size:11px; color:#7FB3D3;",
                      "Aucune opération pour l'instant."))
    
    ops_rev <- rev(dv$ops_log)
    shiny::tagList(
      lapply(ops_rev, function(op)
        shiny::div(class = "op-history-item", op)
      )
    )
  })
  
  shiny::observeEvent(input$data_undo, {
    if (length(dv$df_history) == 0) {
      shiny::showNotification("Rien à annuler.", type = "warning", duration = 2)
      return()
    }
    dv$df_courant <- dv$df_history[[length(dv$df_history)]]
    dv$df_history <- dv$df_history[-length(dv$df_history)]
    n <- length(dv$ops_log)
    if (n > 0) dv$ops_log <- dv$ops_log[-n]
    shiny::showNotification("Dernière opération annulée.", type = "message", duration = 3)
  })
  
  # ===========================================================================
  # 12. EXPORT
  # ===========================================================================
  
  output$data_export_csv <- shiny::downloadHandler(
    filename = function()
      paste0("donnees_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      shiny::req(dv$df_courant)
      readr::write_csv(.forcer_character_post(dv$df_courant), file)
    }
  )
  
  output$data_export_rds <- shiny::downloadHandler(
    filename = function()
      paste0("donnees_", format(Sys.Date(), "%Y%m%d"), ".rds"),
    content = function(file) {
      shiny::req(dv$df_courant)
      saveRDS(.forcer_character_post(dv$df_courant), file)
    }
  )
  
  output$data_export_xlsx <- shiny::downloadHandler(
    filename = function()
      paste0("donnees_", format(Sys.Date(), "%Y%m%d"), ".xlsx"),
    content = function(file) {
      shiny::req(dv$df_courant)
      exporter_xlsx_data(dv$df_courant, file)
    }
  )
  
  output$data_export_info <- shiny::renderUI({
    shiny::req(dv$df_courant)
    df <- dv$df_courant
    shiny::div(class = "data-op-info",
               sprintf("%s lignes \u00d7 %s colonnes pr\u00eates \u00e0 l'export",
                       format(nrow(df), big.mark="\u202f"), ncol(df))
    )
  })
  
  # ===========================================================================
  # 12b. EXPORTS AUTOMATISÉS — panneau unifié (découpage + espèces)
  # ===========================================================================
  
  # Registre des exports automatisés : id → méta
  EXPORTS_AUTO <- list(
    list(id="annee",      label="Découpage par ann\u00e9e",        groupe="D\u00e9coupage"),
    list(id="mois",       label="D\u00e9coupage par mois",         groupe="D\u00e9coupage"),
    list(id="mois_annee", label="D\u00e9coupage mois \u00d7 ann\u00e9e", groupe="D\u00e9coupage"),
    list(id="espece",     label="D\u00e9coupage par esp\u00e8ce",   groupe="D\u00e9coupage"),
    list(id="quartier",   label="D\u00e9coupage par quartier",     groupe="D\u00e9coupage"),
    list(id="MAC",        label="Maquereau (MAC)",                 groupe="Esp\u00e8ces"),
    list(id="POL",        label="Lieu jaune (POL)",                groupe="Esp\u00e8ces"),
    list(id="SOL",        label="Sole (SOL)",                      groupe="Esp\u00e8ces")
  )
  
  # Choices groupées pour le selectInput
  .exports_auto_choices <- function() {
    groupes <- unique(sapply(EXPORTS_AUTO, `[[`, "groupe"))
    lapply(stats::setNames(groupes, groupes), function(g) {
      items <- Filter(function(x) x$groupe == g, EXPORTS_AUTO)
      stats::setNames(
        sapply(items, `[[`, "id"),
        sapply(items, `[[`, "label")
      )
    })
  }
  
  # ── Sélecteur ──────────────────────────────────────────────────────────────
  output$data_export_auto_select_ui <- shiny::renderUI({
    shiny::selectInput(
      "data_export_auto_type",
      label   = NULL,
      choices = .exports_auto_choices()
    )
  })
  
  # ── Zone de statut (disponibilité, colonnes détectées, nb fichiers) ────────
  output$data_export_auto_status_ui <- shiny::renderUI({
    shiny::req(dv$df_courant, input$data_export_auto_type)
    df   <- dv$df_courant
    type <- input$data_export_auto_type
    
    # Cas espèces spécifiques
    if (type %in% c("MAC","POL","SOL")) {
      info <- verifier_export_espece(df, type)
      ok   <- isTRUE(info$dispo)
      
      detail_lines <- switch(type,
                             MAC = c("Filtre esp_cod_fao = MAC",
                                     "D\u00e9coupage par ann\u00e9e \u2192 MAC_YYYY.xlsx"),
                             POL = c("Filtre esp_cod_fao = POL",
                                     "Colonne mois ajout\u00e9e si absente",
                                     "Segments : POL + POL_Nord (27.7.x) + POL_Sud (27.8.x)",
                                     "D\u00e9coupage par ann\u00e9e dans chaque segment"),
                             SOL = c("Filtre esp_cod_fao = SOL",
                                     "Colonnes mois + semestre ajout\u00e9es si absentes",
                                     "Segments : SOL + SOL_Nord (27.7.x) + SOL_Sud (27.8.x)",
                                     "D\u00e9coupage par ann\u00e9e dans chaque segment")
      )
      
      shiny::tagList(
        shiny::div(
          class = "data-op-info",
          style = paste0("margin-top:8px; border-left-color:",
                         if (ok) "#2E9E6B" else "#E05050", ";"),
          shiny::icon(if (ok) "check-circle" else "times-circle",
                      style = paste0("color:", if (ok) "#2E9E6B" else "#E05050", ";")),
          paste0(" ", info$message)
        ),
        shiny::div(
          style = "font-size:10px; color:#7FB3D3; margin-top:6px;",
          shiny::tagList(lapply(detail_lines, function(l)
            shiny::div(shiny::icon("angle-right"), " ", l)
          ))
        )
      )
      
      # Cas découpages génériques
    } else {
      dispo  <- verifier_decoupages_disponibles(df)[[type]]
      ok     <- isTRUE(dispo$dispo)
      detail <- label_decoupage_info(df, type)
      
      shiny::div(
        class = "data-op-info",
        style = paste0("margin-top:8px; border-left-color:",
                       if (ok) "#2E9E6B" else "#E05050", ";"),
        shiny::icon(if (ok) "check-circle" else "times-circle",
                    style = paste0("color:", if (ok) "#2E9E6B" else "#E05050", ";")),
        paste0(" ", detail)
      )
    }
  })
  
  # ── Config contextuelle (préfixe pour les découpages génériques) ───────────
  output$data_export_auto_config_ui <- shiny::renderUI({
    shiny::req(input$data_export_auto_type)
    type <- input$data_export_auto_type
    
    # Les espèces pré-configurées n'ont pas besoin de préfixe
    if (type %in% c("MAC","POL","SOL")) return(NULL)
    
    shiny::div(
      style = "margin-top:8px;",
      shiny::tags$div(style = "font-size:11px;color:#7FB3D3;margin-bottom:4px;",
                      "Pr\u00e9fixe du nom de fichier (ex\u00a0: MAC)"),
      shiny::textInput("data_export_auto_prefixe", label = NULL,
                       value       = toupper(type),
                       placeholder = "ex\u00a0: MAC")
    )
  })
  
  # ── Bouton de téléchargement ───────────────────────────────────────────────
  output$data_export_auto_btn_ui <- shiny::renderUI({
    shiny::req(dv$df_courant, input$data_export_auto_type)
    df   <- dv$df_courant
    type <- input$data_export_auto_type
    
    # Vérification disponibilité
    ok <- if (type %in% c("MAC","POL","SOL")) {
      isTRUE(verifier_export_espece(df, type)$dispo)
    } else {
      isTRUE(verifier_decoupages_disponibles(df)[[type]]$dispo)
    }
    
    shiny::div(
      style = "margin-top:10px;",
      shiny::downloadButton(
        "data_export_auto_dl",
        label = if (ok) "T\u00e9l\u00e9charger le ZIP" else "Non disponible",
        icon  = shiny::icon("file-zipper"),
        class = paste("btn btn-sm",
                      if (ok) "btn-routine" else "btn-data-action"),
        style = paste0("width:100%;",
                       if (!ok) " opacity:0.45; pointer-events:none;" else "")
      )
    )
  })
  
  # ── Handler téléchargement unifié ─────────────────────────────────────────
  output$data_export_auto_dl <- shiny::downloadHandler(
    filename = function() {
      type <- input$data_export_auto_type %||% "export"
      if (type %in% c("MAC","POL","SOL")) {
        paste0(type, "_", format(Sys.Date(), "%Y%m%d"), ".zip")
      } else {
        pfx <- trimws(input$data_export_auto_prefixe %||% toupper(type))
        if (!nzchar(pfx)) pfx <- toupper(type)
        paste0(pfx, "_", type, "_", format(Sys.Date(), "%Y%m%d"), ".zip")
      }
    },
    content = function(file) {
      shiny::req(dv$df_courant)
      type <- input$data_export_auto_type
      df   <- dv$df_courant
      
      shiny::withProgress(
        message = paste0("Export \u00ab ", type, " \u00bb en cours\u2026"),
        value = 0.3, {
          tryCatch({
            if (type == "MAC") {
              exporter_mac(df, file)
              push_history("Export esp\u00e8ce MAC (par ann\u00e9e)")
            } else if (type == "POL") {
              exporter_pol(df, file)
              push_history("Export esp\u00e8ce POL (Nord/Sud \u00d7 ann\u00e9e)")
            } else if (type == "SOL") {
              exporter_sol(df, file)
              push_history("Export esp\u00e8ce SOL (Nord/Sud \u00d7 ann\u00e9e, semestre inclus)")
            } else {
              pfx <- trimws(input$data_export_auto_prefixe %||% toupper(type))
              if (!nzchar(pfx)) pfx <- toupper(type)
              exporter_decoupage_zip(df, type, pfx, file)
              push_history(paste0("Export d\u00e9coup\u00e9 \u00ab ", type,
                                  " \u00bb (pr\u00e9fixe\u00a0: ", pfx, ")"))
            }
          }, error = function(e) {
            shiny::showNotification(
              paste0("Erreur export \u00ab ", type, " \u00bb\u00a0: ", e$message),
              type = "error", duration = 8
            )
          })
        }
      )
    },
    contentType = "application/zip"
  )
  
  # ===========================================================================
  # 13. PARTAGE dans rv (pour les autres modules)
  # ===========================================================================
  
  shiny::observe({
    rv$data_clean <- dv$df_courant
  })
}