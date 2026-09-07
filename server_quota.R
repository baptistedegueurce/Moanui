# =============================================================================
# server_quota.R — Serveur onglet "Analyses secondaires"
# Signature : server_quota(input, output, session, rv)
# IDs UI préfixés "sq_" pour éviter les collisions
# Dépendances : functions_quota.R, tab_quota.R (SQ_ENGINS_COHERENTS)
# =============================================================================

server_quota <- function(input, output, session, rv) {
  
  # =============================================================================
  # 0. DONNÉES RÉACTIVES — source + import (composant partagé)
  # =============================================================================
  
  sq_raw_data <- app_source_server(
    input    = input,
    output   = output,
    session  = session,
    input_id = "sq",
    rv       = rv
  )
  
  # =============================================================================
  # 0b. MAPPING COLONNES — UI auto-détection
  # Colonnes attendues et leurs noms par défaut tentés
  SQ_COLS_ATTENDUES <- list(
    op                = c("op"),
    esp_cod_fao       = c("esp_cod_fao", "cod_fao", "espece_cod"),
    nom_navire        = c("nom_navire", "navire"),
    quartier_cod      = c("quartier_cod", "quartier"),
    engin_cod         = c("engin_cod", "engin"),
    maree_id          = c("maree_id", "id_maree"),
    date              = c("date"),
    debarquement_Kg   = c("debarquement_Kg", "debarquement_kg", "poids_kg", "poids"),
    debarquement_euros = c("debarquement_euros", "valeur_euros", "valeur"),
    stat_rect         = c("stat_rect", "rect_stat", "ices_rect"),
    div_ciem_cod_sipa = c("div_ciem_cod_sipa", "zone_ciem", "div_ciem"),
    MM                = c("MM", "mois_num"),
    YYYY              = c("YYYY", "annee_num")
  )
  
  # Labels lisibles pour chaque variable technique
  SQ_COLS_LABELS <- c(
    op                = "Statut / Opérateur",
    esp_cod_fao       = "Espèce (code FAO)",
    nom_navire        = "Nom du navire",
    quartier_cod      = "Quartier maritime",
    engin_cod         = "Engin de pêche (code)",
    maree_id          = "Identifiant de marée",
    date              = "Date de débarquement",
    debarquement_Kg   = "Poids débarqué (kg)",
    debarquement_euros = "Valeur débarquée (€)",
    stat_rect         = "Rectangle statistique ICES",
    div_ciem_cod_sipa = "Division CIEM",
    MM                = "Mois (numérique)",
    YYYY              = "Année (numérique)"
  )
  
  output$sq_mapping_ui <- renderUI({
    df <- sq_raw_data()
    req(df)
    cols_dispo <- c("(auto-detect)", names(df))
    
    lapply(names(SQ_COLS_ATTENDUES), function(var) {
      # Cherche un match automatique
      candidats  <- SQ_COLS_ATTENDUES[[var]]
      match_auto <- intersect(candidats, names(df))
      selected   <- if (length(match_auto) > 0) match_auto[1] else "(auto-detect)"
      
      # Libellé lisible + nom technique en sous-titre
      label_human   <- SQ_COLS_LABELS[[var]]
      detected_flag <- selected != "(auto-detect)"
      
      shiny::div(
        style = "margin-bottom: 10px;",
        
        # Titre lisible
        shiny::div(
          style = "font-size:11px; font-weight:600; color:#EAF2F8; margin-bottom:1px;",
          label_human
        ),
        # Nom technique + badge détection auto
        shiny::div(
          style = "font-size:10px; color:#4A7A9B; margin-bottom:4px; display:flex; align-items:center; gap:5px;",
          shiny::code(
            style = "background:transparent; color:#4A7A9B; padding:0; font-size:10px;",
            var
          ),
          if (detected_flag)
            shiny::span(
              style = paste0(
                "background:#0D3B27; color:#2E9E6B; border:1px solid #1A6641;",
                "border-radius:10px; padding:1px 7px; font-size:9px; font-weight:700;"
              ),
              "\u2713 détectée"
            )
          else
            shiny::span(
              style = paste0(
                "background:#2C1A09; color:#E67E22; border:1px solid #7D4B0D;",
                "border-radius:10px; padding:1px 7px; font-size:9px; font-weight:700;"
              ),
              "! à mapper"
            )
        ),
        
        shiny::selectInput(
          inputId  = paste0("sq_map_", var),
          label    = NULL,
          choices  = cols_dispo,
          selected = selected
        )
      )
    })
  })
  
  # Applique le mapping pour renommer les colonnes + dérive MM/YYYY depuis date
  sq_data_mapped <- reactive({
    df <- sq_raw_data()
    req(df)
    
    for (var in names(SQ_COLS_ATTENDUES)) {
      id  <- paste0("sq_map_", var)
      val <- input[[id]]
      if (!is.null(val) && val != "(auto-detect)" && val %in% names(df) && val != var) {
        names(df)[names(df) == val] <- var
      }
    }
    
    # Dériver MM et YYYY depuis date si absentes ou non reconnues
    if ("date" %in% names(df)) {
      df$date <- tryCatch(as.Date(df$date), error = function(e) as.Date(NA))
      if (!"MM" %in% names(df) || all(is.na(df$MM))) {
        df$MM <- format(df$date, "%m")
      }
      if (!"YYYY" %in% names(df) || all(is.na(df$YYYY))) {
        df$YYYY <- format(df$date, "%Y")
      }
    }
    
    df
  })
  
  # Valeurs disponibles dans la colonne op (pour le filtre dynamique)
  sq_op_choices <- reactive({
    df <- sq_data_mapped()
    if (!"op" %in% names(df)) return(character(0))
    sort(unique(as.character(df$op[!is.na(df$op)])))
  })
  
  # UI filtre OP (rendu dynamiquement car dépend des données)
  output$sq_op_filtre_ui <- renderUI({
    choices <- sq_op_choices()
    if (length(choices) == 0) {
      return(shiny::p(style = "font-size:11px; color:#7FB3D3;",
                      shiny::icon("info-circle"),
                      " Colonne 'op' absente — aucun filtre appliqué."))
    }
    # Pré-sélectionner les valeurs "Hors OP" détectées automatiquement
    default_hors_op <- choices[grepl("hors.?op|hop", choices, ignore.case = TRUE)]
    selected <- if (length(default_hors_op) > 0) default_hors_op else choices
    
    tagList(
      sq_lbl("Filtrer sur la colonne 'op'"),
      shiny::checkboxGroupInput(
        "sq_op_filtre",
        label = NULL,
        choices  = choices,
        selected = selected
      ),
      shiny::p(style = "font-size:10px; color:#7FB3D3; margin-top:4px;",
               "Cocher les valeurs à CONSERVER. Décocher tout = pas de filtre OP.")
    )
  })
  
  # =============================================================================
  # 0d. KPI aperçu données
  # =============================================================================
  
  output$sq_kpi_row <- renderUI({
    df <- sq_data_mapped()
    req(df)
    shiny::fluidRow(
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val", format(nrow(df), big.mark = " ")),
                                  shiny::div(class = "sq-kpi-lbl", "Lignes")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val", ncol(df)),
                                  shiny::div(class = "sq-kpi-lbl", "Colonnes")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val",
                                             if ("nom_navire" %in% names(df)) n_distinct(df$nom_navire) else "–"),
                                  shiny::div(class = "sq-kpi-lbl", "Navires")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val",
                                             if ("esp_cod_fao" %in% names(df)) n_distinct(df$esp_cod_fao) else "–"),
                                  shiny::div(class = "sq-kpi-lbl", "Espèces")
      ))
    )
  })
  
  output$sq_table_preview <- DT::renderDataTable({
    df <- sq_data_mapped()
    req(df)
    n <- min(input$sq_nrows %||% 200, nrow(df))
    DT::datatable(
      head(df, n),
      options = list(scrollX = TRUE, pageLength = 25, dom = "tip"),
      rownames = FALSE
    )
  })
  
  # =============================================================================
  # 1. DONNÉES NETTOYÉES — reactive centrale
  # =============================================================================
  
  # OP sélectionnés par l'utilisateur (NULL = pas de filtre)
  sq_op_selected <- reactive({
    choices <- sq_op_choices()
    if (length(choices) == 0) return(NULL)          # pas de colonne op
    sel <- input$sq_op_filtre
    if (is.null(sel) || length(sel) == 0) return(NULL)  # tout décoché = pas de filtre
    sel
  })
  
  # Espèce sélectionnée (ui générée côté serveur pour chaque sous-onglet)
  sq_esp_choices <- reactive({
    df <- sq_data_mapped()
    req(df, "esp_cod_fao" %in% names(df))
    sort(unique(as.character(df$esp_cod_fao)))
  })
  
  # Met à jour les selectInput espèce des différents sous-onglets
  observe({
    esps <- sq_esp_choices()
    shiny::updateSelectizeInput(session, "sq_esp_engin",
                                choices = esps, server = TRUE)
  })
  
  output$sq_dep_esp_ui <- renderUI({
    shiny::selectizeInput("sq_dep_esp", label = NULL,
                          choices  = sq_esp_choices(),
                          multiple = FALSE,
                          options  = list(placeholder = "Choisir une espèce…"))
  })
  
  output$sq_quota_esp_ui <- renderUI({
    shiny::selectizeInput("sq_quota_esp", label = NULL,
                          choices  = sq_esp_choices(),
                          multiple = FALSE,
                          options  = list(placeholder = "Choisir une espèce…"))
  })
  
  # Données nettoyées (agrégées à la marée) pour l'espèce quota
  sq_df_clean <- eventReactive(input$sq_run_global, {
    df  <- sq_data_mapped()
    req(df)
    
    sp <- input$sq_quota_esp %||% sq_esp_choices()[1]
    req(sp)
    
    withProgress(message = "Nettoyage des données…", value = 0.1, {
      clean_donnees(df, sp, OP = sq_op_selected())
    })
  }, ignoreNULL = FALSE)
  
  # =============================================================================
  # 2. SOUS-ONGLET — INCOHÉRENCES ENGINS
  # =============================================================================
  
  # Affiche les engins cohérents de référence pour les espèces choisies
  output$sq_engins_ref_ui <- renderUI({
    esps <- input$sq_esp_engin
    req(esps)
    
    tags_list <- lapply(esps, function(sp) {
      info <- SQ_ENGINS_COHERENTS[[sp]]
      if (is.null(info)) return(NULL)
      shiny::div(style = "margin-bottom:6px;",
                 shiny::div(class = "sq-card-title", info$nom),
                 shiny::div(
                   lapply(info$coherents, function(e)
                     shiny::span(class = "sq-esp-badge", e)
                   )
                 )
      )
    })
    do.call(tagList, tags_list)
  })
  
  # Résultats incohérences engins
  sq_res_engins <- eventReactive(input$sq_run_engins, {
    df   <- sq_data_mapped()
    esps <- input$sq_esp_engin
    req(df, length(esps) > 0)
    
    withProgress(message = "Analyse des engins…", value = 0.2, {
      
      # Construit la liste des engins cohérents pour les espèces choisies
      engins_coherents <- unique(unlist(lapply(esps, function(sp) {
        SQ_ENGINS_COHERENTS[[sp]]$coherents
      })))
      
      # Filtre sur les espèces d'intérêt
      df_esp <- df %>%
        dplyr::filter(esp_cod_fao %in% esps)
      
      req(nrow(df_esp) > 0)
      
      # Lignes avec engin incohérent
      df_incoh <- df_esp %>%
        dplyr::filter(!engin_cod %in% engins_coherents)
      
      # Résumé par engin
      resume_engin <- df_incoh %>%
        dplyr::group_by(engin_cod, esp_cod_fao) %>%
        dplyr::summarise(
          nb_marees  = dplyr::n_distinct(maree_id),
          nb_navires = dplyr::n_distinct(nom_navire),
          total_kg   = sum(debarquement_Kg, na.rm = TRUE),
          .groups    = "drop"
        ) %>%
        dplyr::arrange(dplyr::desc(total_kg))
      
      # Résumé par navire
      resume_navire <- df_incoh %>%
        dplyr::group_by(nom_navire, quartier_cod, engin_cod, esp_cod_fao) %>%
        dplyr::summarise(
          nb_marees = dplyr::n_distinct(maree_id),
          total_kg  = sum(debarquement_Kg, na.rm = TRUE),
          .groups   = "drop"
        ) %>%
        dplyr::arrange(dplyr::desc(total_kg))
      
      stats <- data.frame(
        nb_lignes_incoherentes = nrow(df_incoh),
        nb_navires_concernes   = dplyr::n_distinct(df_incoh$nom_navire),
        total_kg_incoherent    = sum(df_incoh$debarquement_Kg, na.rm = TRUE)
      )
      
      list(
        lignes        = df_incoh,
        resume_engin  = resume_engin,
        resume_navire = resume_navire,
        stats         = stats
      )
    })
  })
  
  # KPI incohérences engins
  output$sq_engins_kpi_row <- renderUI({
    res <- sq_res_engins()
    req(res)
    s <- res$stats
    shiny::fluidRow(
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-warn",
                                             format(s$nb_lignes_incoherentes, big.mark = " ")),
                                  shiny::div(class = "sq-kpi-lbl", "Lignes incohérentes")
      )),
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-warn", s$nb_navires_concernes),
                                  shiny::div(class = "sq-kpi-lbl", "Navires concernés")
      )),
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-err",
                                             paste0(format(round(s$total_kg_incoherent), big.mark = " "), " kg")),
                                  shiny::div(class = "sq-kpi-lbl", "Kg incohérents")
      ))
    )
  })
  
  output$sq_engins_table_resume <- DT::renderDataTable({
    req(sq_res_engins())
    DT::datatable(sq_res_engins()$resume_engin,
                  options = list(scrollX = TRUE, pageLength = 20), rownames = FALSE)
  })
  
  output$sq_engins_table_navires <- DT::renderDataTable({
    req(sq_res_engins())
    DT::datatable(sq_res_engins()$resume_navire,
                  options = list(scrollX = TRUE, pageLength = 20), rownames = FALSE)
  })
  
  output$sq_engins_plot <- renderPlot({
    res <- sq_res_engins()
    req(res, nrow(res$resume_engin) > 0)
    ggplot2::ggplot(res$resume_engin,
                    ggplot2::aes(x = reorder(engin_cod, total_kg), y = total_kg / 1000, fill = esp_cod_fao)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(title = "Poids incohérent par engin (tonnes)",
                    x = "Engin", y = "Tonnes", fill = "Espèce") +
      theme_perso()
  })
  
  # Export engins — ZIP unique
  output$sq_export_engins_zip <- downloadHandler(
    filename = function() paste0("incoherences_engins_", Sys.Date(), ".zip"),
    content  = function(file) {
      res <- sq_res_engins()
      req(res)
      tmp <- file.path(tempdir(), paste0("engins_", format(Sys.time(), "%H%M%S")))
      dir.create(tmp, showWarnings = FALSE)
      
      # Tableur
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "resume_engin");  openxlsx::writeData(wb, "resume_engin",  res$resume_engin)
      openxlsx::addWorksheet(wb, "resume_navire"); openxlsx::writeData(wb, "resume_navire", res$resume_navire)
      openxlsx::addWorksheet(wb, "lignes");        openxlsx::writeData(wb, "lignes",        res$lignes)
      openxlsx::saveWorkbook(wb, file.path(tmp, "incoherences_engins.xlsx"))
      
      # Graphique
      if (nrow(res$resume_engin) > 0) {
        p <- ggplot2::ggplot(res$resume_engin,
                             ggplot2::aes(x = reorder(as.character(engin_cod), total_kg),
                                          y = total_kg / 1000, fill = esp_cod_fao)) +
          ggplot2::geom_col() + ggplot2::coord_flip() +
          ggplot2::labs(title = "Poids incohérent par engin", x = "Engin", y = "Tonnes", fill = "Espèce") +
          theme_perso()
        ggplot2::ggsave(file.path(tmp, "incoherences_engins.png"), p, width = 10, height = 6, dpi = 150)
      }
      
      old_wd <- getwd(); setwd(tmp)
      zip::zip(file, files = list.files(tmp), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
  # =============================================================================
  # 3. SOUS-ONGLET — INCOHÉRENCES NUMÉRIQUES
  # =============================================================================
  
  sq_res_numerique <- eventReactive(input$sq_run_num, {
    df    <- sq_data_mapped()
    types <- input$sq_num_types
    req(df, length(types) > 0,
        all(c("debarquement_Kg", "debarquement_euros") %in% names(df)))
    
    withProgress(message = "Détection incohérences numériques…", value = 0.3, {
      
      df <- df %>%
        dplyr::mutate(
          debarquement_Kg    = as.numeric(gsub(",", ".", debarquement_Kg)),
          debarquement_euros = as.numeric(gsub(",", ".", debarquement_euros))
        )
      
      lignes_list <- list()
      
      if ("zero_kg" %in% types) {
        lignes_list$zero_kg <- df %>%
          dplyr::filter(debarquement_Kg == 0 | is.na(debarquement_Kg),
                        debarquement_euros > 0) %>%
          dplyr::mutate(type_incoherence = "0 kg / euros > 0")
      }
      
      if ("zero_eur" %in% types) {
        lignes_list$zero_eur <- df %>%
          dplyr::filter(debarquement_euros == 0 | is.na(debarquement_euros),
                        debarquement_Kg > 0) %>%
          dplyr::mutate(type_incoherence = "0 € / kg > 0")
      }
      
      lignes <- do.call(rbind, lignes_list)
      if (is.null(lignes) || nrow(lignes) == 0) {
        lignes <- data.frame(message = "Aucune incohérence détectée.")
        resume <- data.frame(type = character(), n = integer(),
                             pct = numeric())
      } else {
        resume <- lignes %>%
          dplyr::group_by(type_incoherence) %>%
          dplyr::summarise(
            n_lignes  = dplyr::n(),
            n_navires = dplyr::n_distinct(nom_navire),
            .groups   = "drop"
          ) %>%
          dplyr::mutate(pct_total = round(n_lignes / nrow(df) * 100, 2))
      }
      
      list(lignes = lignes, resume = resume)
    })
  })
  
  output$sq_num_kpi_row <- renderUI({
    res <- sq_res_numerique()
    req(res)
    if ("message" %in% names(res$lignes)) {
      return(shiny::div(class = "sq-kpi",
                        shiny::div(class = "sq-kpi-val sq-kpi-ok", "0"),
                        shiny::div(class = "sq-kpi-lbl", "Aucune incohérence")))
    }
    n_tot <- nrow(res$lignes)
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-warn", format(n_tot, big.mark = " ")),
                                  shiny::div(class = "sq-kpi-lbl", "Lignes incohérentes")
      )),
      shiny::column(6, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val",
                                             if ("nom_navire" %in% names(res$lignes))
                                               dplyr::n_distinct(res$lignes$nom_navire) else "–"),
                                  shiny::div(class = "sq-kpi-lbl", "Navires concernés")
      ))
    )
  })
  
  output$sq_num_table_resume <- DT::renderDataTable({
    req(sq_res_numerique())
    DT::datatable(sq_res_numerique()$resume,
                  options = list(scrollX = TRUE, pageLength = 10), rownames = FALSE)
  })
  
  output$sq_num_table_detail <- DT::renderDataTable({
    req(sq_res_numerique())
    DT::datatable(sq_res_numerique()$lignes,
                  options = list(scrollX = TRUE, pageLength = 25), rownames = FALSE)
  })
  
  output$sq_num_plot <- renderPlot({
    res <- sq_res_numerique()
    req(res, !("message" %in% names(res$lignes)))
    ggplot2::ggplot(res$resume,
                    ggplot2::aes(x = type_incoherence, y = n_lignes, fill = type_incoherence)) +
      ggplot2::geom_col(show.legend = FALSE) +
      ggplot2::geom_text(ggplot2::aes(label = paste0(n_lignes, " (", pct_total, "%)")),
                         vjust = -0.4, size = 4) +
      ggplot2::labs(title = "Répartition des incohérences numériques",
                    x = NULL, y = "Nombre de lignes") +
      theme_perso()
  })
  
  # Export num — ZIP unique
  output$sq_export_num_zip <- downloadHandler(
    filename = function() paste0("incoherences_num_", Sys.Date(), ".zip"),
    content  = function(file) {
      res <- sq_res_numerique()
      req(res)
      tmp <- file.path(tempdir(), paste0("num_", format(Sys.time(), "%H%M%S")))
      dir.create(tmp, showWarnings = FALSE)
      
      # Tableur
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "resume"); openxlsx::writeData(wb, "resume", res$resume)
      openxlsx::addWorksheet(wb, "lignes"); openxlsx::writeData(wb, "lignes", res$lignes)
      openxlsx::saveWorkbook(wb, file.path(tmp, "incoherences_numeriques.xlsx"))
      
      # Graphique
      if (!("message" %in% names(res$lignes)) && nrow(res$resume) > 0) {
        p <- ggplot2::ggplot(res$resume,
                             ggplot2::aes(x = type_incoherence, y = n_lignes, fill = type_incoherence)) +
          ggplot2::geom_col(show.legend = FALSE) +
          ggplot2::geom_text(ggplot2::aes(label = paste0(n_lignes, " (", pct_total, "%)")),
                             vjust = -0.4, size = 4) +
          ggplot2::labs(title = "Incohérences numériques", x = NULL, y = "Lignes") +
          theme_perso()
        ggplot2::ggsave(file.path(tmp, "incoherences_numeriques.png"), p, width = 8, height = 5, dpi = 150)
      }
      
      old_wd <- getwd(); setwd(tmp)
      zip::zip(file, files = list.files(tmp), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
  # =============================================================================
  # 4. SOUS-ONGLET — DÉPASSEMENTS
  # =============================================================================
  
  # Stockage réactif des règles ajoutées par l'utilisateur
  sq_regles_rv <- reactiveVal(data.frame(
    esp_lib_fao_francais = character(),
    type_periode         = character(),
    date_debut           = as.Date(character()),
    date_fin             = as.Date(character()),
    limite               = numeric(),
    stringsAsFactors     = FALSE
  ))
  
  # Ajouter une règle
  observeEvent(input$sq_dep_add, {
    req(input$sq_dep_esp, input$sq_dep_type,
        input$sq_dep_debut, input$sq_dep_fin, input$sq_dep_limite)
    
    # Retrouve le libellé FAO à partir du code
    df  <- sq_data_mapped()
    req(df, "esp_cod_fao" %in% names(df), "esp_lib_fao_francais" %in% names(df))
    
    lib <- df %>%
      dplyr::filter(esp_cod_fao == input$sq_dep_esp) %>%
      dplyr::pull(esp_lib_fao_francais) %>%
      as.character() %>%
      unique()
    lib <- if (length(lib) == 0) input$sq_dep_esp else lib[1]
    
    nouvelle <- data.frame(
      esp_lib_fao_francais = lib,
      type_periode         = input$sq_dep_type,
      date_debut           = as.Date(input$sq_dep_debut),
      date_fin             = as.Date(input$sq_dep_fin),
      limite               = as.numeric(input$sq_dep_limite),
      stringsAsFactors     = FALSE
    )
    
    sq_regles_rv(rbind(sq_regles_rv(), nouvelle))
    showNotification("Règle ajoutée.", type = "message", duration = 2)
  })
  
  # Affiche les règles actives + bouton suppression par ligne
  output$sq_dep_regles_ui <- renderUI({
    regles <- sq_regles_rv()
    if (nrow(regles) == 0) {
      return(shiny::p(style = "font-size:11px; color:#7FB3D3;", "Aucune règle définie."))
    }
    rows <- lapply(seq_len(nrow(regles)), function(i) {
      r <- regles[i, ]
      shiny::div(class = "sq-regle-row",
                 shiny::fluidRow(
                   shiny::column(10,
                                 shiny::p(style = "font-size:11px; margin:0; color:#EAF2F8;",
                                          sprintf("%s — %s — limite %s kg/navire (%s → %s)",
                                                  r$esp_lib_fao_francais, r$type_periode,
                                                  format(r$limite, big.mark = " "),
                                                  r$date_debut, r$date_fin))
                   ),
                   shiny::column(2,
                                 shiny::actionButton(
                                   inputId = paste0("sq_del_regle_", i),
                                   label   = NULL,
                                   icon    = shiny::icon("trash"),
                                   class   = "btn btn-sq-danger btn-sm",
                                   style   = "padding:3px 6px;"
                                 )
                   )
                 )
      )
    })
    do.call(tagList, rows)
  })
  
  # Observateurs dynamiques pour supprimer chaque règle
  # On utilise un reactiveVal pour transmettre l'indice à supprimer
  # et on évite le pattern once=TRUE qui casse la suppression après le 1er clic
  sq_del_index_rv <- reactiveVal(NULL)
  
  observe({
    regles <- sq_regles_rv()
    lapply(seq_len(nrow(regles)), function(i) {
      btn_id <- paste0("sq_del_regle_", i)
      # ignoreInit=TRUE + ignoreNULL=TRUE suffisent ;
      # PAS de once=TRUE pour que l'observer reste actif après re-render
      observeEvent(input[[btn_id]], {
        sq_del_index_rv(i)
      }, ignoreInit = TRUE, ignoreNULL = TRUE)
    })
  })
  
  # Réaction séparée qui effectue la suppression
  observeEvent(sq_del_index_rv(), {
    idx <- sq_del_index_rv()
    req(!is.null(idx))
    r <- sq_regles_rv()
    if (idx >= 1 && idx <= nrow(r)) {
      sq_regles_rv(r[-idx, , drop = FALSE])
      showNotification("Règle supprimée.", type = "warning", duration = 2)
    }
    sq_del_index_rv(NULL)   # reset pour éviter une double suppression
  }, ignoreNULL = TRUE, ignoreInit = TRUE)
  
  # Analyse des dépassements
  sq_res_dep <- eventReactive(input$sq_run_dep, {
    df     <- sq_data_mapped()
    regles <- sq_regles_rv()
    req(df, nrow(regles) > 0)
    
    withProgress(message = "Analyse des dépassements…", value = 0.3, {
      # Nettoyage minimal si pas encore fait
      sp_list <- unique(regles$esp_lib_fao_francais)
      
      df_work <- df %>%
        dplyr::mutate(
          date               = as.Date(date),
          debarquement_Kg    = as.numeric(gsub(",", ".", debarquement_Kg)),
          debarquement_euros = as.numeric(gsub(",", ".", debarquement_euros))
        )
      
      check_depassement_dynamique(df_work, regles)
    })
  })
  
  output$sq_dep_kpi_row <- renderUI({
    res <- sq_res_dep()
    req(res)
    rv_dep  <- res$resume_navire
    shiny::fluidRow(
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-err",
                                             sum(res$detail$flag, na.rm = TRUE)),
                                  shiny::div(class = "sq-kpi-lbl", "Dépassements détectés")
      )),
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-warn", nrow(rv_dep)),
                                  shiny::div(class = "sq-kpi-lbl", "Navires en dépassement")
      )),
      shiny::column(4, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val sq-kpi-err",
                                             paste0(format(round(sum(rv_dep$kg_depassement, na.rm = TRUE)), big.mark = " "), " kg")),
                                  shiny::div(class = "sq-kpi-lbl", "Kg en dépassement")
      ))
    )
  })
  
  output$sq_dep_table_resume <- DT::renderDataTable({
    res <- sq_res_dep()
    req(res)
    resume_periode <- res$detail %>%
      dplyr::filter(flag) %>%
      dplyr::group_by(type_periode, esp_lib_fao_francais) %>%
      dplyr::summarise(
        nb_depassements = dplyr::n(),
        kg_total        = sum(depassement, na.rm = TRUE),
        .groups         = "drop"
      )
    DT::datatable(resume_periode,
                  options = list(scrollX = TRUE, pageLength = 15), rownames = FALSE)
  })
  
  output$sq_dep_table_navires <- DT::renderDataTable({
    req(sq_res_dep())
    DT::datatable(sq_res_dep()$resume_navire,
                  options = list(scrollX = TRUE, pageLength = 20), rownames = FALSE)
  })
  
  output$sq_dep_table_detail <- DT::renderDataTable({
    res <- sq_res_dep()
    req(res)
    df_flag <- res$detail %>% dplyr::filter(flag)
    DT::datatable(df_flag,
                  options = list(scrollX = TRUE, pageLength = 25), rownames = FALSE)
  })
  
  # ── Helpers graphiques dépassements par mois×engin ──────────────────────────
  sq_dep_plots_mois_engin <- reactive({
    res <- sq_res_dep()
    req(res)
    df_flag <- res$detail %>% dplyr::filter(flag)
    req(nrow(df_flag) > 0)
    
    # Dériver mois depuis date_ref
    df_flag <- df_flag %>%
      dplyr::mutate(
        mois_lbl = format(as.Date(date_ref), "%Y-%m"),
        engin    = as.character(engin_cod)
      )
    
    # Agrégation par mois + engin
    df_kg <- df_flag %>%
      dplyr::group_by(mois_lbl, engin) %>%
      dplyr::summarise(kg_dep = sum(depassement, na.rm = TRUE) / 1000, .groups = "drop")
    
    df_nb <- df_flag %>%
      dplyr::group_by(mois_lbl, engin) %>%
      dplyr::summarise(nb_dep = dplyr::n(), .groups = "drop")
    
    p_kg <- ggplot2::ggplot(df_kg, ggplot2::aes(x = mois_lbl, y = kg_dep, fill = engin)) +
      ggplot2::geom_col(position = "stack") +
      ggplot2::labs(title = "Dépassements (tonnes) par mois et engin",
                    x = "Mois", y = "Tonnes dépassées", fill = "Engin") +
      theme_perso()
    
    p_nb <- ggplot2::ggplot(df_nb, ggplot2::aes(x = mois_lbl, y = nb_dep, fill = engin)) +
      ggplot2::geom_col(position = "stack") +
      ggplot2::labs(title = "Nombre de dépassements par mois et engin",
                    x = "Mois", y = "Nombre de dépassements", fill = "Engin") +
      theme_perso()
    
    list(p_kg = p_kg, p_nb = p_nb)
  })
  
  output$sq_dep_plot_kg <- renderPlot({
    pl <- sq_dep_plots_mois_engin()
    req(pl)
    pl$p_kg
  })
  
  output$sq_dep_plot_nb <- renderPlot({
    pl <- sq_dep_plots_mois_engin()
    req(pl)
    pl$p_nb
  })
  
  # Export dep — ZIP unique
  output$sq_export_dep_zip <- downloadHandler(
    filename = function() paste0("depassements_", Sys.Date(), ".zip"),
    content  = function(file) {
      res <- sq_res_dep()
      req(res)
      tmp <- file.path(tempdir(), paste0("dep_", format(Sys.time(), "%H%M%S")))
      dir.create(tmp, showWarnings = FALSE)
      
      # Tableur
      wb <- openxlsx::createWorkbook()
      resume_periode <- res$detail %>%
        dplyr::filter(flag) %>%
        dplyr::group_by(type_periode, esp_lib_fao_francais) %>%
        dplyr::summarise(nb_dep = dplyr::n(), kg_total = sum(depassement, na.rm = TRUE), .groups = "drop")
      openxlsx::addWorksheet(wb, "resume_periode");  openxlsx::writeData(wb, "resume_periode",  resume_periode)
      openxlsx::addWorksheet(wb, "resume_navire");   openxlsx::writeData(wb, "resume_navire",   res$resume_navire)
      openxlsx::addWorksheet(wb, "detail");          openxlsx::writeData(wb, "detail",          res$detail)
      openxlsx::saveWorkbook(wb, file.path(tmp, "depassements.xlsx"))
      
      # Graphiques
      pl <- tryCatch(sq_dep_plots_mois_engin(), error = function(e) NULL)
      if (!is.null(pl)) {
        ggplot2::ggsave(file.path(tmp, "dep_kg_mois_engin.png"),  pl$p_kg, width = 12, height = 5, dpi = 150)
        ggplot2::ggsave(file.path(tmp, "dep_nb_mois_engin.png"),  pl$p_nb, width = 12, height = 5, dpi = 150)
      }
      
      old_wd <- getwd(); setwd(tmp)
      zip::zip(file, files = list.files(tmp), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
  # =============================================================================
  # 5. SOUS-ONGLET — SUIVI DES QUOTAS
  # =============================================================================
  
  sq_res_quota <- eventReactive(input$sq_run_quota, {
    df <- sq_data_mapped()
    sp <- input$sq_quota_esp
    q  <- input$sq_quota_total
    q_dgampa <- input$sq_quota_dgampa
    req(df, sp, q, q_dgampa)
    
    withProgress(message = "Calcul du suivi quota…", value = 0.3, {
      
      df_clean_q <- clean_donnees(df, sp, OP = sq_op_selected())
      req(nrow(df_clean_q) > 0)
      
      # Suivi global
      suivi <- suivi_quota(df_clean_q, q, q_dgampa)
      
      # Tableau mensuel
      df_mois <- df_clean_q %>%
        dplyr::group_by(annee, mois) %>%
        dplyr::summarise(
          mensuel_kg = sum(debarquement_Kg, na.rm = TRUE),
          .groups    = "drop"
        ) %>%
        dplyr::mutate(mois_num = as.integer(as.character(mois)),
                      annee_num = as.integer(as.character(annee))) %>%
        dplyr::arrange(annee_num, mois_num) %>%
        dplyr::mutate(
          cumul_kg   = cumsum(mensuel_kg),
          pct_quota  = round(mensuel_kg / q * 100, 2),
          pct_cumul  = round(cumul_kg   / q * 100, 2)
        ) %>%
        dplyr::select(-mois_num, -annee_num)
      
      list(
        suivi    = suivi,
        df_mois  = df_mois,
        df_clean = df_clean_q,
        q        = q,
        q_dgampa = q_dgampa,
        sp       = sp
      )
    })
  })
  
  # KPI quotas
  output$sq_quota_kpi_row <- renderUI({
    res <- sq_res_quota()
    req(res)
    s <- res$suivi
    
    pct    <- round(s$consommation_pct, 1)
    col_pct <- if (pct >= 100) "sq-kpi-err" else if (pct >= 80) "sq-kpi-warn" else "sq-kpi-ok"
    ecart   <- round(s$ecart_avec_dgampa, 1)
    
    shiny::fluidRow(
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val",
                                             paste0(format(round(s$total_debarquement), big.mark = " "), " kg")),
                                  shiny::div(class = "sq-kpi-lbl", "Total débarqué")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = paste("sq-kpi-val", col_pct), paste0(pct, "%")),
                                  shiny::div(class = "sq-kpi-lbl", "Consommation quota")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = "sq-kpi-val",
                                             paste0(format(round(s$quota_annonce_dgampa), big.mark = " "), " kg")),
                                  shiny::div(class = "sq-kpi-lbl", "Annoncé DGAMPA")
      )),
      shiny::column(3, shiny::div(class = "sq-kpi",
                                  shiny::div(class = if (ecart > 0) "sq-kpi-val sq-kpi-err" else "sq-kpi-val sq-kpi-ok",
                                             paste0(ifelse(ecart > 0, "+", ""), ecart, "%")),
                                  shiny::div(class = "sq-kpi-lbl", "Écart vs DGAMPA")
      ))
    )
  })
  
  output$sq_quota_table <- DT::renderDataTable({
    req(sq_res_quota())
    DT::datatable(sq_res_quota()$df_mois,
                  options = list(scrollX = TRUE, pageLength = 12), rownames = FALSE)
  })
  
  output$sq_quota_plot_cumul <- renderPlot({
    res <- sq_res_quota()
    req(res)
    df_c  <- res$df_mois
    q     <- res$q
    q_dgampa <- res$q_dgampa
    
    df_c <- df_c %>%
      dplyr::mutate(date_label = paste(annee, sprintf("%02d", as.integer(mois)), "01", sep = "-") %>%
                      as.Date())
    
    p <- ggplot2::ggplot(df_c, ggplot2::aes(x = date_label, y = cumul_kg)) +
      ggplot2::geom_line(linewidth = 1, color = "#0077B6") +
      ggplot2::geom_point(size = 2, color = "#0077B6") +
      ggplot2::geom_hline(yintercept = q, color = "#C0392B", linetype = "dashed", linewidth = 0.8) +
      ggplot2::geom_hline(yintercept = q_dgampa, color = "#E67E22", linetype = "dotted", linewidth = 0.8) +
      ggplot2::annotate("text", x = max(df_c$date_label), y = q,
                        label = paste0("Quota (", format(q, big.mark = " "), " kg)"),
                        color = "#C0392B", hjust = 1.05, vjust = -0.5, size = 3.5) +
      ggplot2::annotate("text", x = max(df_c$date_label), y = q_dgampa,
                        label = paste0("DGAMPA (", format(q_dgampa, big.mark = " "), " kg)"),
                        color = "#E67E22", hjust = 1.05, vjust = -0.5, size = 3.5) +
      ggplot2::labs(title = "Débarquements cumulés vs quotas",
                    x = "Date", y = "Kg cumulés") +
      theme_perso()
    p
  })
  
  output$sq_quota_plot_mensuel <- renderPlot({
    res <- sq_res_quota()
    req(res)
    df_m <- res$df_mois %>%
      dplyr::mutate(mois_lbl = paste(annee, sprintf("%02d", as.integer(mois)), sep = "-"))
    
    ggplot2::ggplot(df_m, ggplot2::aes(x = mois_lbl, y = mensuel_kg / 1000)) +
      ggplot2::geom_col(fill = "#0077B6") +
      ggplot2::geom_text(ggplot2::aes(label = paste0(round(pct_quota), "%")),
                         vjust = -0.4, size = 3.5) +
      ggplot2::labs(title = "Consommation mensuelle du quota",
                    x = "Mois", y = "Tonnes") +
      theme_perso()
  })
  
  # Export quota — ZIP unique (tableau + les 2 graphiques)
  output$sq_export_quota_xlsx <- downloadHandler(
    filename = function() paste0("suivi_quota_", Sys.Date(), ".zip"),
    content  = function(file) {
      res <- sq_res_quota()
      if (is.null(res)) {
        showNotification(
          "Lancez d'abord le suivi quota (bouton 'Calculer') avant d'exporter.",
          type = "error", duration = 6
        )
        return(NULL)
      }
      tmp <- file.path(tempdir(), paste0("quota_", format(Sys.time(), "%H%M%S")))
      dir.create(tmp, showWarnings = FALSE)
      
      # Tableur
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "suivi_global")
      openxlsx::writeData(wb, "suivi_global", res$suivi)
      openxlsx::addWorksheet(wb, "mensuel")
      openxlsx::writeData(wb, "mensuel", res$df_mois)
      openxlsx::saveWorkbook(wb, file.path(tmp, "suivi_quota.xlsx"))
      
      # Graphique cumulé
      df_c  <- res$df_mois
      q     <- res$q
      q_dgampa <- res$q_dgampa
      df_c <- df_c %>%
        dplyr::mutate(date_label = paste(annee, sprintf("%02d", as.integer(as.character(mois))), "01", sep = "-") %>%
                        as.Date())
      p_cumul <- ggplot2::ggplot(df_c, ggplot2::aes(x = date_label, y = cumul_kg)) +
        ggplot2::geom_line(linewidth = 1, color = "#0077B6") +
        ggplot2::geom_point(size = 2, color = "#0077B6") +
        ggplot2::geom_hline(yintercept = q, color = "#C0392B", linetype = "dashed", linewidth = 0.8) +
        ggplot2::geom_hline(yintercept = q_dgampa, color = "#E67E22", linetype = "dotted", linewidth = 0.8) +
        ggplot2::annotate("text", x = max(df_c$date_label), y = q,
                          label = paste0("Quota (", format(q, big.mark = " "), " kg)"),
                          color = "#C0392B", hjust = 1.05, vjust = -0.5, size = 3.5) +
        ggplot2::annotate("text", x = max(df_c$date_label), y = q_dgampa,
                          label = paste0("DGAMPA (", format(q_dgampa, big.mark = " "), " kg)"),
                          color = "#E67E22", hjust = 1.05, vjust = -0.5, size = 3.5) +
        ggplot2::labs(title = "Débarquements cumulés vs quotas", x = "Date", y = "Kg cumulés") +
        theme_perso()
      ggplot2::ggsave(file.path(tmp, "suivi_quota_cumul.png"), p_cumul, width = 12, height = 6, dpi = 150)
      
      # Graphique mensuel
      df_m <- res$df_mois %>%
        dplyr::mutate(mois_lbl = paste(annee, sprintf("%02d", as.integer(as.character(mois))), sep = "-"))
      p_mensuel <- ggplot2::ggplot(df_m, ggplot2::aes(x = mois_lbl, y = mensuel_kg / 1000)) +
        ggplot2::geom_col(fill = "#0077B6") +
        ggplot2::geom_text(ggplot2::aes(label = paste0(round(pct_quota), "%")),
                           vjust = -0.4, size = 3.5) +
        ggplot2::labs(title = "Consommation mensuelle du quota", x = "Mois", y = "Tonnes") +
        theme_perso()
      ggplot2::ggsave(file.path(tmp, "suivi_quota_mensuel.png"), p_mensuel, width = 10, height = 5, dpi = 150)
      
      old_wd <- getwd(); setwd(tmp)
      zip::zip(file, files = list.files(tmp), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
  # Garde le handler PNG pour compatibilité UI (redirige vers le ZIP)
  output$sq_export_quota_png <- downloadHandler(
    filename = function() paste0("suivi_quota_mensuel_", Sys.Date(), ".png"),
    content  = function(file) {
      res <- sq_res_quota()
      req(res)
      df_m <- res$df_mois %>%
        dplyr::mutate(mois_lbl = paste(annee, sprintf("%02d", as.integer(as.character(mois))), sep = "-"))
      p <- ggplot2::ggplot(df_m, ggplot2::aes(x = mois_lbl, y = mensuel_kg / 1000)) +
        ggplot2::geom_col(fill = "#0077B6") +
        ggplot2::geom_text(ggplot2::aes(label = paste0(round(pct_quota), "%")),
                           vjust = -0.4, size = 3.5) +
        ggplot2::labs(title = "Consommation mensuelle", x = "Mois", y = "Tonnes") +
        theme_perso()
      ggplot2::ggsave(file, p, width = 10, height = 5, dpi = 150)
    }
  )
  
  # =============================================================================
  # 6. SOUS-ONGLET — VISUALISATION (graphiques flotte + carte ICES)
  # =============================================================================
  
  # ── Graphiques flotte ────────────────────────────────────────────────────────
  sq_plots_rv <- reactiveVal(NULL)
  
  observeEvent(input$sq_run_plots, {
    df <- sq_data_mapped()
    sp <- input$sq_quota_esp %||% sq_esp_choices()[1]
    q  <- input$sq_quota_total %||% 1
    req(df, sp)
    
    withProgress(message = "Génération des graphiques…", value = 0.2, {
      df_c <- tryCatch(clean_donnees(df, sp, OP = sq_op_selected()), error = function(e) NULL)
      req(df_c, nrow(df_c) > 0)
      # create_plots retourne une liste nommée (panel, cumul, mois)
      plots <- create_plots(df_c, output_dir = tempdir(), q = q)
      sq_plots_rv(list(data = df_c, plots = plots, q = q))
    })
  })
  
  output$sq_visu_panel <- renderPlot({
    pv <- sq_plots_rv()
    req(pv)
    # create_plots retourne les 3 plots (panel_navires, p_cumul, p_mois)
    # On reconstruit le panel ici pour l'affichage
    df_c <- pv$data
    q    <- pv$q
    
    p1 <- df_c %>%
      dplyr::group_by(mois) %>%
      dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
      dplyr::mutate(mois_num = as.integer(as.character(mois))) %>%
      dplyr::arrange(mois_num) %>%
      ggplot2::ggplot(ggplot2::aes(x = factor(mois_num), y = nb)) +
      ggplot2::geom_col(fill = "steelblue") +
      ggplot2::labs(title = "Navires par mois", x = "Mois", y = "Nb navires") +
      theme_perso() + ggplot2::labs(tag = "A")
    
    p2 <- df_c %>%
      dplyr::group_by(quartier_cod) %>%
      dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
      ggplot2::ggplot(ggplot2::aes(x = reorder(quartier_cod, nb), y = nb)) +
      ggplot2::geom_col(fill = "darkgreen") + ggplot2::coord_flip() +
      ggplot2::labs(title = "Navires par quartier", x = "", y = "Nb navires") +
      theme_perso() + ggplot2::labs(tag = "B")
    
    p3 <- df_c %>%
      dplyr::group_by(engin_cod) %>%
      dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
      ggplot2::ggplot(ggplot2::aes(x = reorder(engin_cod, nb), y = nb)) +
      ggplot2::geom_col(fill = "orange") +
      ggplot2::labs(title = "Navires par engin", x = "Engin", y = "Nb navires") +
      theme_perso() + ggplot2::labs(tag = "C")
    
    df_nav <- df_c %>%
      dplyr::mutate(navire_id = paste0(nom_navire, " (", quartier_cod, ")")) %>%
      dplyr::group_by(navire_id) %>%
      dplyr::summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
      dplyr::arrange(dplyr::desc(total)) %>%
      dplyr::mutate(rank = dplyr::row_number(),
                    navire_id_mod = ifelse(rank <= 10, navire_id, "Autres")) %>%
      dplyr::group_by(navire_id_mod) %>%
      dplyr::summarise(total = sum(total)) %>%
      dplyr::mutate(pct   = total / sum(total) * 100,
                    label = paste0(navire_id_mod, " (", round(pct, 1), "%)"))
    df_nav$navire_id_mod <- factor(df_nav$navire_id_mod, levels = df_nav$navire_id_mod)
    
    p4 <- ggplot2::ggplot(df_nav, ggplot2::aes(x = "", y = total, fill = label)) +
      ggplot2::geom_col(color = "white") + ggplot2::coord_polar("y") +
      ggplot2::labs(title = "Part des navires (Top 10)", fill = "Navire") +
      ggplot2::theme_void() +
      ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 13)) +
      ggplot2::labs(tag = "D")
    
    patchwork::wrap_plots(p1, p2, p3, p4, ncol = 2)
  })
  
  output$sq_visu_cumul <- renderPlot({
    pv <- sq_plots_rv()
    req(pv)
    df_c <- pv$data
    q    <- pv$q
    
    df_cumul <- df_c %>%
      dplyr::arrange(date) %>%
      dplyr::mutate(cumul = cumsum(debarquement_Kg))
    
    ggplot2::ggplot(df_cumul, ggplot2::aes(x = date, y = cumul)) +
      ggplot2::geom_line(linewidth = 0.7, color = "blue") +
      ggplot2::geom_point(size = 0.8, color = "darkblue") +
      ggplot2::geom_hline(yintercept = q, color = "red", linetype = "dashed") +
      ggplot2::annotate("text", x = max(df_cumul$date), y = q,
                        label = paste0("Quota (", format(q, big.mark = " "), " kg)"),
                        color = "red", hjust = 1, vjust = -0.5, size = 3.5) +
      ggplot2::labs(title = "Cumul des débarquements", x = "Date", y = "Kg cumulés") +
      theme_perso()
  })
  
  output$sq_visu_mois <- renderPlot({
    pv <- sq_plots_rv()
    req(pv)
    df_c <- pv$data
    
    df_c %>%
      dplyr::group_by(mois) %>%
      dplyr::summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
      dplyr::mutate(mois_num = as.integer(as.character(mois))) %>%
      dplyr::arrange(mois_num) %>%
      ggplot2::ggplot(ggplot2::aes(x = factor(mois_num), y = total / 1000)) +
      ggplot2::geom_col(fill = "skyblue") +
      ggplot2::labs(title = "Débarquements par mois", x = "Mois", y = "Tonnes") +
      theme_perso()
  })
  
  # Export plots — ZIP complet (panel navires + cumul + mois)
  output$sq_export_plots_png <- downloadHandler(
    filename = function() paste0("visualisation_flotte_", Sys.Date(), ".zip"),
    content  = function(file) {
      pv <- sq_plots_rv()
      req(pv)
      df_c <- pv$data
      q    <- pv$q
      
      tmp <- file.path(tempdir(), paste0("plots_", format(Sys.time(), "%H%M%S")))
      dir.create(tmp, showWarnings = FALSE)
      
      # Panel navires (A-B-C-D)
      p1 <- df_c %>%
        dplyr::group_by(mois) %>%
        dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
        dplyr::mutate(mois_num = as.integer(as.character(mois))) %>%
        dplyr::arrange(mois_num) %>%
        ggplot2::ggplot(ggplot2::aes(x = factor(mois_num), y = nb)) +
        ggplot2::geom_col(fill = "steelblue") +
        ggplot2::labs(title = "Navires par mois", x = "Mois", y = "Nb navires", tag = "A") +
        theme_perso()
      
      p2 <- df_c %>%
        dplyr::group_by(quartier_cod) %>%
        dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
        ggplot2::ggplot(ggplot2::aes(x = reorder(quartier_cod, nb), y = nb)) +
        ggplot2::geom_col(fill = "darkgreen") + ggplot2::coord_flip() +
        ggplot2::labs(title = "Navires par quartier", x = "", y = "Nb navires", tag = "B") +
        theme_perso()
      
      p3 <- df_c %>%
        dplyr::group_by(engin_cod) %>%
        dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
        ggplot2::ggplot(ggplot2::aes(x = reorder(engin_cod, nb), y = nb)) +
        ggplot2::geom_col(fill = "orange") +
        ggplot2::labs(title = "Navires par engin", x = "Engin", y = "Nb navires", tag = "C") +
        theme_perso()
      
      df_nav <- df_c %>%
        dplyr::mutate(navire_id = paste0(nom_navire, " (", quartier_cod, ")")) %>%
        dplyr::group_by(navire_id) %>%
        dplyr::summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
        dplyr::arrange(dplyr::desc(total)) %>%
        dplyr::mutate(rank = dplyr::row_number(),
                      navire_id_mod = ifelse(rank <= 10, navire_id, "Autres")) %>%
        dplyr::group_by(navire_id_mod) %>%
        dplyr::summarise(total = sum(total)) %>%
        dplyr::mutate(pct = total / sum(total) * 100,
                      label = paste0(navire_id_mod, " (", round(pct, 1), "%)"))
      df_nav$navire_id_mod <- factor(df_nav$navire_id_mod, levels = df_nav$navire_id_mod)
      p4 <- ggplot2::ggplot(df_nav, ggplot2::aes(x = "", y = total, fill = label)) +
        ggplot2::geom_col(color = "white") + ggplot2::coord_polar("y") +
        ggplot2::labs(title = "Part des navires (Top 10)", fill = "Navire", tag = "D") +
        ggplot2::theme_void() +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 13))
      
      panel <- patchwork::wrap_plots(p1, p2, p3, p4, ncol = 2)
      ggplot2::ggsave(file.path(tmp, "panel_navires.png"), panel, width = 14, height = 10, dpi = 150)
      
      # Cumul débarquements
      df_cumul <- df_c %>%
        dplyr::arrange(date) %>%
        dplyr::mutate(cumul = cumsum(debarquement_Kg))
      p_cumul <- ggplot2::ggplot(df_cumul, ggplot2::aes(x = date, y = cumul)) +
        ggplot2::geom_line(linewidth = 0.7, color = "blue") +
        ggplot2::geom_point(size = 0.8, color = "darkblue") +
        ggplot2::geom_hline(yintercept = q, color = "red", linetype = "dashed") +
        ggplot2::annotate("text", x = max(df_cumul$date), y = q,
                          label = paste0("Quota (", format(q, big.mark = " "), " kg)"),
                          color = "red", hjust = 1, vjust = -0.5, size = 3.5) +
        ggplot2::labs(title = "Cumul des débarquements", x = "Date", y = "Kg cumulés") +
        theme_perso()
      ggplot2::ggsave(file.path(tmp, "cumul_debarquements.png"), p_cumul, width = 12, height = 6, dpi = 150)
      
      # Mensuel
      df_m <- df_c %>%
        dplyr::group_by(mois) %>%
        dplyr::summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
        dplyr::mutate(mois_num = as.integer(as.character(mois))) %>%
        dplyr::arrange(mois_num)
      p_mois <- ggplot2::ggplot(df_m, ggplot2::aes(x = factor(mois_num), y = total / 1000)) +
        ggplot2::geom_col(fill = "skyblue") +
        ggplot2::labs(title = "Débarquements par mois", x = "Mois", y = "Tonnes") +
        theme_perso()
      ggplot2::ggsave(file.path(tmp, "debarquements_mois.png"), p_mois, width = 10, height = 5, dpi = 150)
      
      old_wd <- getwd(); setwd(tmp)
      zip::zip(file, files = list.files(tmp), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
  # ── Carte ICES ───────────────────────────────────────────────────────────────
  sq_map_rv <- reactiveVal(NULL)
  
  # Reactive : charge le shapefile ICES une seule fois (mis en cache dans rv)
  sq_ices_sf <- reactive({
    # 1. Déjà disponible dans rv (partagé par server_map) ?
    if (!is.null(rv$sf_rect)) return(rv$sf_rect)
    
    # 2. Chemin standard de l'application
    shp_path <- file.path("www", "shapefile", "rectangle_stat",
                          "ICES_Statistical_Rectangles.shp")
    if (!file.exists(shp_path)) {
      # Tentative avec le dossier rect_stat (nom alternatif)
      shp_path <- file.path("www", "shapefile", "rect_stat",
                            "ICES_Statistical_Rectangles.shp")
    }
    if (!file.exists(shp_path)) {
      showNotification(
        paste0("Shapefile ICES introuvable. Chemin attendu : ",
               "www/shapefile/rectangle_stat/ICES_Statistical_Rectangles.shp"),
        type = "error", duration = 8
      )
      return(NULL)
    }
    tryCatch(
      sf::st_read(shp_path, quiet = TRUE),
      error = function(e) {
        showNotification(paste("Erreur lecture shapefile ICES :", e$message),
                         type = "error", duration = 8)
        NULL
      }
    )
  })
  
  observeEvent(input$sq_run_map, {
    pv <- sq_plots_rv()
    req(pv)
    
    ices_sf <- sq_ices_sf()
    if (is.null(ices_sf)) {
      req(FALSE)   # notification déjà affichée dans sq_ices_sf()
    }
    
    df_c    <- pv$data
    var     <- input$sq_map_var
    palette <- input$sq_map_palette
    xlim    <- c(input$sq_map_xmin, input$sq_map_xmax)
    ylim    <- c(input$sq_map_ymin, input$sq_map_ymax)
    
    withProgress(message = "Génération de la carte…", value = 0.4, {
      
      df_map <- df_c %>%
        dplyr::mutate(stat_rect = as.character(stat_rect)) %>%
        dplyr::group_by(stat_rect) %>%
        dplyr::summarise(
          nb_marees = dplyr::n(),
          kg        = sum(debarquement_Kg, na.rm = TRUE),
          euros     = sum(debarquement_euros, na.rm = TRUE),
          .groups   = "drop"
        )
      
      map_data <- ices_sf %>%
        dplyr::mutate(ICESNAME = as.character(ICESNAME)) %>%
        dplyr::left_join(df_map, by = c("ICESNAME" = "stat_rect")) %>%
        dplyr::filter(!is.na(nb_marees))
      
      world <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")
      
      titre_map <- switch(var,
                          nb_marees = "Nombre de marées",
                          kg        = "Débarquement (kg)",
                          euros     = "Débarquement (€)"
      )
      
      vals    <- map_data[[var]]
      min_val <- min(vals, na.rm = TRUE)
      max_val <- max(vals, na.rm = TRUE)
      
      p_map <- ggplot2::ggplot() +
        ggplot2::geom_sf(data = ices_sf, fill = NA, color = "grey80", linewidth = 0.2) +
        ggplot2::geom_sf(data = map_data,
                         ggplot2::aes(fill = .data[[var]])) +
        ggplot2::geom_sf(data = world, fill = "grey95", color = NA) +
        ggplot2::scale_fill_viridis_c(option = palette,
                                      limits = c(min_val, max_val),
                                      na.value = "transparent") +
        ggplot2::coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
        ggplot2::labs(title = titre_map, fill = var) +
        ggplot2::theme_minimal() +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"),
                       legend.position = "right")
      
      sq_map_rv(p_map)
    })
  })
  
  output$sq_visu_map <- renderPlot({
    req(sq_map_rv())
    sq_map_rv()
  })
  
  output$sq_export_map_png <- downloadHandler(
    filename = function() paste0("carte_ices_", input$sq_map_var, "_", Sys.Date(), ".png"),
    content  = function(file) {
      req(sq_map_rv())
      ggplot2::ggsave(file, sq_map_rv(), width = 10, height = 8, dpi = 150)
    }
  )
  
  # =============================================================================
  # 7. ANALYSE GLOBALE (bouton "Lancer l'analyse complète")
  # =============================================================================
  
  # Stocke le chemin du dossier de résultats généré par l'analyse globale
  sq_export_dir_rv <- reactiveVal(NULL)
  
  observeEvent(input$sq_run_global, {
    
    df       <- sq_data_mapped()
    sp       <- input$sq_quota_esp %||% sq_esp_choices()[1]
    q        <- as.numeric(input$sq_quota_total   %||% 16000)
    q_dgampa <- as.numeric(input$sq_quota_dgampa  %||% 1000)
    req(df, sp)
    
    # Nom du dossier : SQ-<ESP>-<YYYY>-<MM>
    folder_name <- paste0("SQ-", toupper(sp), "-", format(Sys.Date(), "%Y-%m"))
    export_dir  <- file.path(tempdir(), folder_name)
    if (dir.exists(export_dir)) unlink(export_dir, recursive = TRUE)
    dir.create(export_dir, recursive = TRUE)
    
    withProgress(message = "Analyse complète en cours…", value = 0, {
      
      # ── 1. Nettoyage ─────────────────────────────────────────────────────────
      setProgress(0.05, "Nettoyage…")
      df_c <- tryCatch(clean_donnees(df, sp, OP = sq_op_selected()), error = function(e) {
        showNotification(paste("Erreur nettoyage :", e$message), type = "error")
        NULL
      })
      req(df_c)
      
      # ── 2. Analyse numérique ──────────────────────────────────────────────────
      setProgress(0.15, "Analyse numérique…")
      res_analyse <- analyse_numerique(df_c)
      
      # ── 3. Incohérences engins ────────────────────────────────────────────────
      setProgress(0.25, "Incohérences engins…")
      engins_coh <- SQ_ENGINS_COHERENTS[[sp]]$coherents %||% character(0)
      res_incoh  <- check_engins_incoherents(df_c, engins_coh)
      
      # ── 4. Suivi quota ────────────────────────────────────────────────────────
      setProgress(0.35, "Suivi quota…")
      res_suivi  <- suivi_quota(df_c, q, q_dgampa)
      
      df_mois <- df_c %>%
        dplyr::group_by(annee, mois) %>%
        dplyr::summarise(mensuel_kg = sum(debarquement_Kg, na.rm = TRUE), .groups = "drop") %>%
        dplyr::mutate(mois_num = as.integer(as.character(mois)),
                      annee_num = as.integer(as.character(annee))) %>%
        dplyr::arrange(annee_num, mois_num) %>%
        dplyr::mutate(
          cumul_kg  = cumsum(mensuel_kg),
          pct_quota = round(mensuel_kg / q * 100, 2),
          pct_cumul = round(cumul_kg   / q * 100, 2)
        ) %>%
        dplyr::select(-mois_num, -annee_num)
      
      # ── 5. Dépassements ───────────────────────────────────────────────────────
      setProgress(0.45, "Dépassements…")
      regles  <- sq_regles_rv()
      res_dep <- if (nrow(regles) > 0) {
        tryCatch(check_depassement_dynamique(df_c, regles), error = function(e) NULL)
      } else NULL
      
      # ── 6. Export tableurs ───────────────────────────────────────────────────
      setProgress(0.55, "Export tableurs…")
      
      # --- Sanitize UTF-8 (fixe l'erreur stri_length d\'openxlsx sur CSV latin1/Windows-1252) ---
      df_c        <- sanitize_utf8(df_c)
      res_suivi   <- sanitize_utf8(res_suivi)
      df_mois     <- sanitize_utf8(df_mois)
      res_analyse <- lapply(res_analyse, sanitize_utf8)
      res_incoh$resume_engin        <- sanitize_utf8(res_incoh$resume_engin)
      res_incoh$resume_navire       <- sanitize_utf8(res_incoh$resume_navire)
      res_incoh$lignes_incoherentes <- sanitize_utf8(res_incoh$lignes_incoherentes)
      res_incoh$stats               <- sanitize_utf8(res_incoh$stats)
      if (!is.null(res_dep)) {
        res_dep$detail        <- sanitize_utf8(res_dep$detail)
        res_dep$resume_navire <- sanitize_utf8(res_dep$resume_navire)
      }
      
      # 6a. Données nettoyées
      wb_data <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb_data, "donnees_propres")
      openxlsx::writeData(wb_data, "donnees_propres", df_c)
      openxlsx::saveWorkbook(wb_data, file.path(export_dir, "01_donnees_propres.xlsx"))
      
      # 6b. Suivi quota
      wb_q <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb_q, "suivi_global")
      openxlsx::writeData(wb_q, "suivi_global", res_suivi)
      openxlsx::addWorksheet(wb_q, "mensuel")
      openxlsx::writeData(wb_q, "mensuel", df_mois)
      openxlsx::saveWorkbook(wb_q, file.path(export_dir, "02_suivi_quota.xlsx"))
      
      # 6c. Analyse flotte
      wb_a <- openxlsx::createWorkbook()
      for (nm in names(res_analyse)) {
        openxlsx::addWorksheet(wb_a, nm)
        openxlsx::writeData(wb_a, nm, res_analyse[[nm]])
      }
      openxlsx::saveWorkbook(wb_a, file.path(export_dir, "03_analyse_flotte.xlsx"))
      
      # 6d. Incohérences engins
      wb_i <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb_i, "resume_engin")
      openxlsx::writeData(wb_i, "resume_engin", res_incoh$resume_engin)
      openxlsx::addWorksheet(wb_i, "resume_navire")
      openxlsx::writeData(wb_i, "resume_navire", res_incoh$resume_navire)
      openxlsx::addWorksheet(wb_i, "lignes")
      openxlsx::writeData(wb_i, "lignes", res_incoh$lignes_incoherentes)
      openxlsx::addWorksheet(wb_i, "stats")
      openxlsx::writeData(wb_i, "stats", res_incoh$stats)
      openxlsx::saveWorkbook(wb_i, file.path(export_dir, "04_incoherences_engins.xlsx"))
      
      # 6e. Dépassements (si règles définies)
      if (!is.null(res_dep)) {
        wb_d <- openxlsx::createWorkbook()
        openxlsx::addWorksheet(wb_d, "detail")
        openxlsx::writeData(wb_d, "detail", res_dep$detail)
        openxlsx::addWorksheet(wb_d, "resume_navire")
        openxlsx::writeData(wb_d, "resume_navire", res_dep$resume_navire)
        openxlsx::saveWorkbook(wb_d, file.path(export_dir, "05_depassements.xlsx"))
      }
      
      # ── 7. Graphiques PNG ────────────────────────────────────────────────────
      setProgress(0.70, "Graphiques…")
      
      tryCatch({
        
        # 7a. Panel flotte (navires/mois, /quartier, /engin, top débarquements)
        p_nav_mois <- df_c %>%
          dplyr::group_by(mois) %>%
          dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
          ggplot2::ggplot(ggplot2::aes(x = mois, y = nb)) +
          ggplot2::geom_col(fill = "steelblue") +
          ggplot2::labs(title = "Navires par mois", x = "Mois", y = "Nb navires") +
          theme_perso() + ggplot2::labs(tag = "A")
        
        p_nav_quartier <- df_c %>%
          dplyr::group_by(quartier_cod) %>%
          dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
          ggplot2::ggplot(ggplot2::aes(x = reorder(quartier_cod, nb), y = nb)) +
          ggplot2::geom_col(fill = "darkgreen") + ggplot2::coord_flip() +
          ggplot2::labs(title = "Navires par quartier", x = "", y = "Nb navires") +
          theme_perso() + ggplot2::labs(tag = "B")
        
        p_nav_engin <- df_c %>%
          dplyr::group_by(engin_cod) %>%
          dplyr::summarise(nb = dplyr::n_distinct(nom_navire)) %>%
          ggplot2::ggplot(ggplot2::aes(x = reorder(engin_cod, nb), y = nb)) +
          ggplot2::geom_col(fill = "orange") +
          ggplot2::labs(title = "Navires par engin", x = "Engin", y = "Nb navires") +
          theme_perso() + ggplot2::labs(tag = "C")
        
        df_nav_top <- df_c %>%
          dplyr::mutate(navire_id = paste0(as.character(nom_navire), " (", as.character(quartier_cod), ")")) %>%
          dplyr::group_by(navire_id) %>%
          dplyr::summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
          dplyr::arrange(dplyr::desc(total)) %>%
          dplyr::mutate(rank = dplyr::row_number(),
                        navire_id_mod = ifelse(rank <= 10, navire_id, "Autres")) %>%
          dplyr::group_by(navire_id_mod) %>%
          dplyr::summarise(total = sum(total)) %>%
          dplyr::mutate(pct = total / sum(total) * 100,
                        label = paste0(navire_id_mod, " (", round(pct, 1), "%)"))
        df_nav_top$navire_id_mod <- factor(df_nav_top$navire_id_mod, levels = df_nav_top$navire_id_mod)
        p_nav_top <- ggplot2::ggplot(df_nav_top, ggplot2::aes(x = "", y = total, fill = label)) +
          ggplot2::geom_col(color = "white") + ggplot2::coord_polar("y") +
          ggplot2::labs(title = "Part des navires (Top 10)", fill = "Navire") +
          ggplot2::theme_void() +
          ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 13)) +
          ggplot2::labs(tag = "D")
        
        panel_flotte <- patchwork::wrap_plots(p_nav_mois, p_nav_quartier, p_nav_engin, p_nav_top, ncol = 2)
        ggplot2::ggsave(file.path(export_dir, "06_panel_flotte.png"),
                        panel_flotte, width = 14, height = 10, dpi = 150)
        
        # 7b. Débarquements cumulés vs quota
        df_cumul <- df_c %>%
          dplyr::arrange(date) %>%
          dplyr::mutate(cumul = cumsum(debarquement_Kg))
        
        p_cumul <- ggplot2::ggplot(df_cumul, ggplot2::aes(x = date, y = cumul)) +
          ggplot2::geom_line(linewidth = 0.8, color = "#0077B6") +
          ggplot2::geom_point(size = 1, color = "#0077B6") +
          ggplot2::geom_hline(yintercept = q, color = "#C0392B", linetype = "dashed", linewidth = 0.8) +
          ggplot2::geom_hline(yintercept = q_dgampa, color = "#E67E22", linetype = "dotted", linewidth = 0.8) +
          ggplot2::annotate("text", x = max(df_cumul$date), y = q,
                            label = paste0("Quota (", format(round(q), big.mark = " "), " kg)"),
                            color = "#C0392B", hjust = 1.05, vjust = -0.5, size = 3.5) +
          ggplot2::annotate("text", x = max(df_cumul$date), y = q_dgampa,
                            label = paste0("DGAMPA (", format(round(q_dgampa), big.mark = " "), " kg)"),
                            color = "#E67E22", hjust = 1.05, vjust = -0.5, size = 3.5) +
          ggplot2::labs(title = paste0("Débarquements cumulés — ", toupper(sp)),
                        x = "Date", y = "Kg cumulés") +
          theme_perso()
        ggplot2::ggsave(file.path(export_dir, "07_cumul_quota.png"),
                        p_cumul, width = 12, height = 6, dpi = 150)
        
        # 7c. Consommation mensuelle
        df_mois_lbl <- df_mois %>%
          dplyr::mutate(mois_lbl = paste(annee, sprintf("%02d", as.integer(mois)), sep = "-"))
        p_mensuel <- ggplot2::ggplot(df_mois_lbl, ggplot2::aes(x = mois_lbl, y = mensuel_kg / 1000)) +
          ggplot2::geom_col(fill = "#0077B6") +
          ggplot2::geom_text(ggplot2::aes(label = paste0(round(pct_quota), "%")),
                             vjust = -0.4, size = 3.5) +
          ggplot2::labs(title = paste0("Consommation mensuelle — ", toupper(sp)),
                        x = "Mois", y = "Tonnes") +
          theme_perso()
        ggplot2::ggsave(file.path(export_dir, "08_mensuel_quota.png"),
                        p_mensuel, width = 12, height = 5, dpi = 150)
        
        # 7d. Graphique dépassements (si données)
        if (!is.null(res_dep)) {
          df_flag <- res_dep$detail %>% dplyr::filter(flag)
          if (nrow(df_flag) > 0) {
            p_dep <- ggplot2::ggplot(df_flag,
                                     ggplot2::aes(x = reorder(periode_id, depassement),
                                                  y = depassement / 1000, fill = type_periode)) +
              ggplot2::geom_col() + ggplot2::coord_flip() +
              ggplot2::labs(title = "Quantité en dépassement par période",
                            x = "Période", y = "Kg dépassés (tonnes)", fill = "Type") +
              theme_perso()
            ggplot2::ggsave(file.path(export_dir, "09_depassements.png"),
                            p_dep, width = 12, height = 6, dpi = 150)
          }
        }
        
        # 7e. Graphique incohérences engins
        if (!is.null(res_incoh$resume_engin) && nrow(res_incoh$resume_engin) > 0) {
          
          # 05a — par engin
          p_incoh_engin <- ggplot2::ggplot(
            res_incoh$resume_engin,
            ggplot2::aes(x = reorder(as.character(engin_cod), total_kg), y = total_kg / 1000)
          ) +
            ggplot2::geom_col(fill = "#E67E22") + ggplot2::coord_flip() +
            ggplot2::geom_text(ggplot2::aes(label = paste0(round(total_kg / 1000, 1), " t")),
                               hjust = -0.1, size = 3) +
            ggplot2::labs(title = "Poids incohérent par engin",
                          x = "Engin", y = "Tonnes") +
            theme_perso()
          
          # 05b — top navires incohérents
          p_incoh_navire <- ggplot2::ggplot(
            head(res_incoh$resume_navire, 20),
            ggplot2::aes(
              x = reorder(paste0(as.character(nom_navire), " (", as.character(quartier_cod), ")"), total_kg),
              y = total_kg / 1000
            )
          ) +
            ggplot2::geom_col(fill = "#C0392B") + ggplot2::coord_flip() +
            ggplot2::labs(title = "Top 20 navires — poids incohérent",
                          x = "", y = "Tonnes") +
            theme_perso()
          
          panel_incoh <- patchwork::wrap_plots(p_incoh_engin, p_incoh_navire, ncol = 2)
          ggplot2::ggsave(file.path(export_dir, "05_incoherences_engins.png"),
                          panel_incoh, width = 14, height = 7, dpi = 150)
        }
        
      }, error = function(e) {
        showNotification(paste("Avertissement graphiques :", e$message), type = "warning")
      })
      
      # ── 8. Carte ICES (si disponible) ────────────────────────────────────────
      setProgress(0.90, "Carte ICES…")
      if (!is.null(sq_map_rv())) {
        tryCatch(
          ggplot2::ggsave(file.path(export_dir, "11_carte_ices.png"),
                          sq_map_rv(), width = 10, height = 8, dpi = 150),
          error = function(e) NULL
        )
      }
      
      # ── 9. Finalisation ──────────────────────────────────────────────────────
      setProgress(1, "Terminé.")
      sq_export_dir_rv(export_dir)
      sq_plots_rv(list(data = df_c, plots = NULL, q = q))
    })
    
    showNotification(
      paste0("Analyse terminée — dossier prêt : ", basename(sq_export_dir_rv())),
      type = "message", duration = 6
    )
  })
  
  # Statut global
  output$sq_global_status <- renderUI({
    dir <- sq_export_dir_rv()
    if (is.null(dir)) return(NULL)
    n_files <- length(list.files(dir))
    shiny::div(style = "font-size:12px; color:#2E9E6B; margin-top:6px;",
               shiny::icon("check-circle"),
               sprintf(" Analyse terminée — %d fichiers prêts dans %s", n_files, basename(dir))
    )
  })
  
  # =============================================================================
  # 8. EXPORT GLOBAL (archive ZIP)
  # =============================================================================
  
  output$sq_export_global <- downloadHandler(
    filename = function() {
      sp  <- input$sq_quota_esp %||% "SQ"
      paste0("SQ-", toupper(sp), "-", format(Sys.Date(), "%Y-%m"), ".zip")
    },
    content = function(file) {
      export_dir <- sq_export_dir_rv()
      
      # Si l'analyse globale n'a pas encore été lancée, on construit quand même
      # un ZIP minimal depuis les résultats des sous-onglets individuels
      if (is.null(export_dir) || !dir.exists(export_dir)) {
        showNotification("Lancez d'abord l'analyse complète pour obtenir le ZIP complet.",
                         type = "warning", duration = 5)
        req(FALSE)
      }
      
      files_in_dir <- list.files(export_dir, full.names = TRUE)
      req(length(files_in_dir) > 0)
      
      # zip::zip avec mode cherry-pick pour ne pas inclure le chemin absolu
      old_wd <- getwd()
      setwd(export_dir)
      zip::zip(file, files = basename(files_in_dir), mode = "cherry-pick")
      setwd(old_wd)
    }
  )
  
} # fin server_quota()