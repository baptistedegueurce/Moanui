# =============================================================================
# server_composition.R — Serveur onglet Composition de graphiques
#
# ARCHITECTURE :
#   • Galerie unifiée dans un reactiveVal local (liste nommée par id).
#   • Miniatures PNG pré-calculées et cachées dans un environment (thumb_cache).
#     Elles ne sont recalculées qu'à la première apparition d'un id.
#   • Les modules amont poussent leurs graphiques via session$userData$compo_push().
#   • compo_slots reste dans rv (partagé avec d'éventuels autres modules).
#
# INTÉGRATION dans server_main.R :
#   rv <- shiny::reactiveValues(
#     ...,
#     compo_slots = list()   # seul champ composition dans rv
#   )
#   source("R/server/server_composition.R", local = TRUE)
#   server_composition(input, output, session, rv)
#
# CAPTURE dans server_viz.R / server_map.R / server_vms.R :
#   push <- session$userData$compo_push
#   if (is.function(push)) push(plot_gg = p, label = "Mon graphique", source = "viz")
#   # source : "viz" | "map" | "vms"
# =============================================================================

server_composition <- function(input, output, session, rv) {
  
  MAX_GALLERY <- 20L
  
  # ── Opérateur null-coalescent local ──────────────────────────────────────
  `%||%` <- function(a, b) if (!is.null(a)) a else b
  
  # ===========================================================================
  # ÉTAT LOCAL
  # ===========================================================================
  
  # Liste nommée id → list(id, plot, label, source, timestamp)
  # Ordre : plus récent en tête
  gallery <- shiny::reactiveVal(list())
  
  # Cache miniatures base64 : id → data-URI
  thumb_cache <- new.env(parent = emptyenv())
  
  # IDs sélectionnés dans la galerie
  selected_ids <- shiny::reactiveVal(character(0))
  
  # ===========================================================================
  # HELPERS INTERNES
  # ===========================================================================
  
  .new_id <- function() {
    paste0("g_", format(Sys.time(), "%Y%m%d%H%M%S"), "_",
           sample.int(99999L, 1L))
  }
  
  .render_thumb <- function(plot_gg) {
    tmp <- tempfile(fileext = ".png")
    on.exit(unlink(tmp), add = TRUE)
    tryCatch({
      ggplot2::ggsave(tmp, plot = plot_gg,
                      width = 3, height = 2, dpi = 50, bg = "#0B2A3D")
      paste0("data:image/png;base64,", base64enc::base64encode(tmp))
    }, error = function(e) {
      # Pixel transparent 1×1 de secours
      "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    })
  }
  
  .ensure_thumb <- function(id, plot_gg) {
    if (!exists(id, envir = thumb_cache, inherits = FALSE)) {
      thumb_cache[[id]] <- .render_thumb(plot_gg)
    }
    thumb_cache[[id]]
  }
  
  .prune_cache <- function() {
    ids_gallery <- names(gallery())
    ids_cache   <- ls(envir = thumb_cache)
    orphans     <- setdiff(ids_cache, ids_gallery)
    if (length(orphans)) rm(list = orphans, envir = thumb_cache)
  }
  
  .etiquette <- function(i, style) {
    switch(style,
           "ABC"   = LETTERS[i],
           "abc"   = letters[i],
           "123"   = as.character(i),
           "roman" = tolower(as.character(utils::as.roman(i))),
           ""
    )
  }
  
  # ===========================================================================
  # INTERFACE DE PUSH exposée aux modules amont
  # ===========================================================================
  session$userData$compo_push <- function(plot_gg, label, source = "viz") {
    id <- .new_id()
    .ensure_thumb(id, plot_gg)
    
    entree <- list(
      id        = id,
      plot      = plot_gg,
      label     = label,
      source    = source,
      timestamp = Sys.time()
    )
    
    lst        <- c(list(entree), gallery())
    names(lst) <- vapply(lst, `[[`, character(1), "id")
    if (length(lst) > MAX_GALLERY) lst <- lst[seq_len(MAX_GALLERY)]
    gallery(lst)
  }
  
  # ===========================================================================
  # 0bis. IMPORT PNG EXTERNE
  # ===========================================================================
  
  .png_to_ggplot <- function(path) {
    img <- png::readPNG(path)
    # Convertir en raster et emballer dans un ggplot vide plein-cadre
    g   <- grid::rasterGrob(img, interpolate = TRUE,
                            width  = grid::unit(1, "npc"),
                            height = grid::unit(1, "npc"))
    ggplot2::ggplot() +
      ggplot2::annotation_custom(g, -Inf, Inf, -Inf, Inf) +
      ggplot2::theme_void() +
      ggplot2::theme(
        plot.background  = ggplot2::element_rect(fill = "#061A2B", color = NA),
        panel.background = ggplot2::element_rect(fill = "#061A2B", color = NA)
      )
  }
  
  .img_to_ggplot <- function(path, ext) {
    tryCatch({
      if (tolower(ext) %in% c("jpg", "jpeg")) {
        img <- jpeg::readJPEG(path)
      } else {
        img <- png::readPNG(path)
      }
      # Ratio width/height natif de l image
      img_ratio <- dim(img)[2] / dim(img)[1]
      
      g <- grid::rasterGrob(img, interpolate = TRUE,
                            width  = grid::unit(1, "npc"),
                            height = grid::unit(1, "npc"))
      p <- ggplot2::ggplot(data = data.frame(x = c(0, 1), y = c(0, 1)),
                           ggplot2::aes(x = x, y = y)) +
        ggplot2::annotation_custom(g, -Inf, Inf, -Inf, Inf) +
        ggplot2::scale_x_continuous(limits = c(0, 1), expand = c(0, 0)) +
        ggplot2::scale_y_continuous(limits = c(0, 1), expand = c(0, 0)) +
        ggplot2::theme_void() +
        ggplot2::theme(
          plot.background  = ggplot2::element_rect(fill = "#061A2B", color = NA),
          panel.background = ggplot2::element_rect(fill = "#061A2B", color = NA),
          aspect.ratio     = 1 / img_ratio
        )
      
      list(plot = p, ratio = img_ratio)
    }, error = function(e) NULL)
  }
  
  shiny::observeEvent(input$compo_import_png, {
    req_files <- input$compo_import_png
    if (is.null(req_files)) return()
    
    added <- 0L
    for (i in seq_len(nrow(req_files))) {
      path <- req_files$datapath[i]
      name <- tools::file_path_sans_ext(req_files$name[i])
      ext  <- tolower(tools::file_ext(req_files$name[i]))
      
      res <- .img_to_ggplot(path, ext)
      if (is.null(res)) next
      p         <- res$plot
      img_ratio <- res$ratio
      
      id <- .new_id()
      .ensure_thumb(id, p)
      
      entree <- list(
        id        = id,
        plot      = p,
        ratio     = img_ratio,   # ratio w/h stocke pour wrap_plots
        label     = name,
        source    = "img",       # badge distinct
        timestamp = Sys.time()
      )
      
      lst        <- c(list(entree), gallery())
      names(lst) <- vapply(lst, `[[`, character(1), "id")
      if (length(lst) > MAX_GALLERY) lst <- lst[seq_len(MAX_GALLERY)]
      gallery(lst)
      added <- added + 1L
    }
    
    if (added > 0L) {
      shiny::showNotification(
        sprintf("%d image(s) importee(s) dans la galerie.", added),
        type = "message", duration = 3
      )
    }
  })
  
  # ===========================================================================
  # 1. UI — GALERIE
  # ===========================================================================
  
  output$compo_gallery_ui <- shiny::renderUI({
    gal  <- gallery()
    sids <- selected_ids()
    
    if (length(gal) == 0) {
      return(shiny::div(
        class = "compo-empty-info",
        shiny::icon("images"), shiny::br(),
        "Aucun graphique en memoire.", shiny::br(),
        "Affichez un graphique dans 'Representation des donnees',", shiny::br(),
        "'Cartographie' ou 'VMS'."
      ))
    }
    
    ids_slots <- vapply(rv$compo_slots %||% list(), `[[`, character(1), "id")
    
    badge_map <- list(
      viz  = list(cls = "compo-badge-viz", lbl = "VIZ"),
      map  = list(cls = "compo-badge-map", lbl = "CARTE"),
      vms  = list(cls = "compo-badge-vms", lbl = "VMS"),
      img  = list(cls = "compo-badge-img", lbl = "IMG")
    )
    
    thumbs <- lapply(gal, function(g) {
      sel       <- g$id %in% sids
      in_slot   <- g$id %in% ids_slots
      b         <- badge_map[[g$source]] %||% badge_map[["viz"]]
      thumb_src <- .ensure_thumb(g$id, g$plot)
      
      shiny::div(
        class = paste0("compo-thumb",
                       if (sel)     " selected" else "",
                       if (in_slot) " in-slot"  else ""),
        id    = paste0("compo_thumb_wrap_", g$id),
        
        # Bouton supprimer
        shiny::tags$button(
          class   = "compo-thumb-del",
          title   = "Supprimer de la galerie",
          onclick = sprintf(
            "Shiny.setInputValue('compo_del_from_gallery','%s',{priority:'event'});",
            g$id),
          "\u00d7"
        ),
        
        # Miniature
        shiny::div(
          class = "compo-mini-preview",
          shiny::tags$img(src = thumb_src)
        ),
        
        # Label + badge
        shiny::div(
          class = "compo-thumb-label",
          shiny::tags$span(class = b$cls, b$lbl),
          g$label
        ),
        shiny::div(class = "compo-thumb-meta",
                   format(g$timestamp, "%H:%M:%S")),
        
        # Clic → toggle sélection
        onclick = sprintf(
          "Shiny.setInputValue('compo_thumb_click','%s',{priority:'event'});",
          g$id)
      )
    })
    
    shiny::div(class = "compo-gallery", thumbs)
  })
  
  # ===========================================================================
  # 2. SÉLECTIONS GALERIE
  # ===========================================================================
  
  shiny::observeEvent(input$compo_thumb_click, {
    id  <- input$compo_thumb_click
    sel <- selected_ids()
    selected_ids(if (id %in% sel) setdiff(sel, id) else c(sel, id))
  })
  
  # ===========================================================================
  # 3. ACTIONS GALERIE
  # ===========================================================================
  
  # Supprimer un item de la galerie
  shiny::observeEvent(input$compo_del_from_gallery, {
    id  <- input$compo_del_from_gallery
    gal <- gallery()
    gal[[id]] <- NULL
    gallery(gal)
    
    rv$compo_slots <- Filter(function(s) s$id != id, rv$compo_slots %||% list())
    selected_ids(setdiff(selected_ids(), id))
    
    if (exists(id, envir = thumb_cache, inherits = FALSE))
      rm(list = id, envir = thumb_cache)
  })
  
  # Vider toute la galerie
  shiny::observeEvent(input$compo_clear_gallery, {
    gallery(list())
    rv$compo_slots <- list()
    selected_ids(character(0))
    cache_ids <- ls(envir = thumb_cache)
    if (length(cache_ids)) rm(list = cache_ids, envir = thumb_cache)
  })
  
  # ===========================================================================
  # 4. GESTION DES SLOTS
  # ===========================================================================
  
  # Ajouter les graphiques sélectionnés aux slots
  shiny::observeEvent(input$compo_add_selected, {
    ids <- selected_ids()
    if (length(ids) == 0) {
      shiny::showNotification(
        "Selectionnez au moins un graphique dans la galerie.",
        type = "warning", duration = 3)
      return()
    }
    
    gal      <- gallery()
    ids_deja <- vapply(rv$compo_slots %||% list(), `[[`, character(1), "id")
    ids_new  <- setdiff(ids, ids_deja)
    ajouts   <- Filter(Negate(is.null), lapply(ids_new, function(id) gal[[id]]))
    
    if (length(ajouts) == 0) {
      shiny::showNotification(
        "Ces graphiques sont deja dans la composition.",
        type = "warning", duration = 3)
      return()
    }
    
    rv$compo_slots <- c(rv$compo_slots %||% list(), ajouts)
    selected_ids(character(0))
    
    shiny::showNotification(
      sprintf("%d graphique(s) ajoute(s) a la composition.", length(ajouts)),
      type = "message", duration = 2)
  })
  
  # Vider les slots
  shiny::observeEvent(input$compo_clear_slots, {
    rv$compo_slots <- list()
  })
  
  # Monter / descendre / retirer un slot
  shiny::observeEvent(input$compo_slot_action, {
    act   <- input$compo_slot_action   # "up|<id>", "down|<id>", "rm|<id>"
    if (is.null(act)) return()
    parts  <- strsplit(act, "\\|")[[1]]
    action <- parts[1]
    id     <- parts[2]
    lst    <- rv$compo_slots %||% list()
    idx    <- which(vapply(lst, `[[`, character(1), "id") == id)
    if (length(idx) == 0) return()
    
    lst <- switch(action,
                  "up"   = { if (idx > 1)           lst[c(idx-1, idx)] <- lst[c(idx, idx-1)]; lst },
                  "down" = { if (idx < length(lst)) lst[c(idx, idx+1)] <- lst[c(idx+1, idx)]; lst },
                  "rm"   = lst[-idx],
                  lst
    )
    rv$compo_slots <- lst
  })
  
  # ===========================================================================
  # 5. UI — SLOTS
  # ===========================================================================
  
  output$compo_slots_ui <- shiny::renderUI({
    slots <- rv$compo_slots %||% list()
    
    if (length(slots) == 0) {
      return(shiny::div(
        class = "compo-empty-info",
        shiny::icon("layer-group"), shiny::br(),
        "Aucun graphique dans la composition.", shiny::br(),
        "Selectionnez dans la galerie puis cliquez 'Ajouter'."
      ))
    }
    
    rows <- lapply(seq_along(slots), function(i) {
      s   <- slots[[i]]
      ico <- if (s$source %in% c("map", "vms")) "\U0001F5FA\uFE0F" else "\U0001F4CA"
      lbl <- paste0(ico, " ", s$label)
      
      shiny::div(
        class = "compo-slot",
        shiny::div(class = "compo-slot-num", as.character(i)),
        shiny::div(class = "compo-slot-label", title = lbl, lbl),
        shiny::tags$button(
          class   = "compo-slot-up",   title = "Monter",
          onclick = sprintf("Shiny.setInputValue('compo_slot_action','up|%s',{priority:'event'});", s$id),
          "\u25b2"),
        shiny::tags$button(
          class   = "compo-slot-down", title = "Descendre",
          onclick = sprintf("Shiny.setInputValue('compo_slot_action','down|%s',{priority:'event'});", s$id),
          "\u25bc"),
        shiny::tags$button(
          class   = "compo-slot-rm",   title = "Retirer",
          onclick = sprintf("Shiny.setInputValue('compo_slot_action','rm|%s',{priority:'event'});", s$id),
          "\u00d7")
      )
    })
    
    shiny::div(class = "compo-slots", rows)
  })
  
  # ===========================================================================
  # 6. LÉGENDES PAR SLOT
  # ===========================================================================
  
  output$compo_slots_legends_ui <- shiny::renderUI({
    slots <- rv$compo_slots %||% list()
    if (length(slots) == 0) return(NULL)
    
    tag_style <- input$compo_tag_style %||% "none"
    
    shiny::div(class = "compo-card",
               shiny::div(class = "compo-card-title",
                          shiny::icon("tag"), " Legendes individuelles (optionnel)"
               ),
               # Grille 3 colonnes : max 3 champs par ligne
               shiny::div(
                 style = "display: flex; flex-wrap: wrap; gap: 8px;",
                 lapply(seq_along(slots), function(i) {
                   s       <- slots[[i]]
                   etiq    <- .etiquette(i, tag_style)
                   lbl_txt <- if (nzchar(etiq)) paste0("[", etiq, "] ", s$label) else s$label
                   
                   shiny::div(
                     style = "flex: 1 1 calc(33.333% - 8px); min-width: 180px; max-width: calc(33.333% - 8px);",
                     shiny::tags$label(
                       class = "compo-param-label",
                       style = "font-size:10px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:block;",
                       title = lbl_txt,
                       lbl_txt
                     ),
                     shiny::textInput(
                       inputId     = paste0("compo_slot_leg_", s$id),
                       label       = NULL,
                       placeholder = "Legende du panneau...",
                       value       = shiny::isolate(input[[paste0("compo_slot_leg_", s$id)]]) %||% ""
                     )
                   )
                 })
               )
    )
  })
  
  # ===========================================================================
  # 7. CONSTRUCTION PATCHWORK
  # ===========================================================================
  
  compo_patchwork <- shiny::reactive({
    shiny::req(input$compo_refresh)
    shiny::isolate({
      
      slots <- rv$compo_slots %||% list()
      shiny::validate(
        shiny::need(length(slots) >= 1,
                    "Ajoutez au moins un graphique a composer.")
      )
      
      tag_style <- input$compo_tag_style %||% "none"
      tag_pos   <- input$compo_tag_pos   %||% "topleft"
      ncol_p    <- max(1L, as.integer(input$compo_ncol %||% 2L))
      legende   <- input$compo_legend    %||% "keep"
      gap_cm    <- as.numeric(input$compo_gap %||% 0.5)
      
      plots <- lapply(seq_along(slots), function(i) {
        s      <- slots[[i]]
        p      <- s$plot
        etiq   <- .etiquette(i, tag_style)
        leg_id <- paste0("compo_slot_leg_", s$id)
        leg_txt <- shiny::isolate(input[[leg_id]]) %||% ""
        
        # Étiquette (A, B, C…)
        if (nzchar(etiq)) {
          pos_x <- if (grepl("right",  tag_pos)) Inf  else -Inf
          pos_y <- if (grepl("top",    tag_pos)) Inf  else -Inf
          hjust <- if (grepl("right",  tag_pos)) 1.2  else -0.2
          vjust <- if (grepl("top",    tag_pos)) 1.3  else -0.3
          
          p <- p + ggplot2::annotate(
            "text",
            x = pos_x, y = pos_y,
            label    = etiq,
            hjust    = hjust, vjust = vjust,
            size     = 5, fontface = "bold",
            color    = "#EAF2F8"
          )
        }
        
        # Légende de panneau
        if (nzchar(leg_txt)) p <- p + ggplot2::labs(caption = leg_txt)
        p
      })
      
      # Gestion des légendes patchwork
      # "keep*" = légendes indépendantes mais repositionnées ; "left" = nouveau
      guides_pw <- switch(legende,
                          "bottom"       = ,
                          "right"        = ,
                          "left"         = ,
                          "top"          = "collect",
                          "keep"         # keep / keep_bottom / keep_right : pas de collect
      )
      legend_pos_pw <- switch(legende,
                              "bottom"       = "bottom",
                              "right"        = "right",
                              "left"         = "left",
                              "top"          = "top",
                              "none"         = "none",
                              "keep_bottom"  = "bottom",
                              "keep_right"   = "right",
                              "right"   # défaut keep
      )
      
      margin_pt <- gap_cm * 28
      
      # Appliquer le thème directement sur chaque plot (& et * cassés en patchwork S7)
      legend_scale <- max(0.45, 1 / sqrt(length(plots)))
      legend_theme <- ggplot2::theme(
        legend.position  = legend_pos_pw,
        legend.key.size  = ggplot2::unit(legend_scale * 0.8, "lines"),
        legend.text      = ggplot2::element_text(size = ggplot2::rel(legend_scale * 0.85)),
        legend.title     = ggplot2::element_text(size = ggplot2::rel(legend_scale * 0.9)),
        legend.spacing.y = ggplot2::unit(legend_scale * 2, "pt"),
        plot.margin      = ggplot2::margin(
          t = margin_pt, r = margin_pt,
          b = margin_pt, l = margin_pt,
          unit = "pt"
        )
      )
      plots <- lapply(plots, function(p) p + legend_theme)
      
      # Calcul des widths/heights pour respecter les ratios des images importees.
      # Pour les graphiques ggplot classiques (sans ratio stocke), on utilise 1.
      ratios <- vapply(slots, function(s) s$ratio %||% 1, numeric(1))
      n      <- length(plots)
      nrow_p <- ceiling(n / ncol_p)
      
      # widths  = ratio moyen de chaque colonne  (w/h → plus large = plus grand width)
      # heights = 1/ratio moyen de chaque ligne  (h/w → plus haute = plus grand height)
      col_idx <- ((seq_len(n) - 1L) %% ncol_p) + 1L
      row_idx <- ((seq_len(n) - 1L) %/% ncol_p) + 1L
      
      widths  <- vapply(seq_len(ncol_p), function(c)
        mean(ratios[col_idx == c]), numeric(1))
      heights <- vapply(seq_len(nrow_p), function(r)
        mean(1 / ratios[row_idx == r]), numeric(1))
      
      pw <- patchwork::wrap_plots(plots, ncol = ncol_p, guides = guides_pw,
                                  widths = widths, heights = heights)
      
      # Annotation globale
      titre     <- input$compo_titre     %||% ""
      soustitre <- input$compo_soustitre %||% ""
      caption   <- input$compo_caption   %||% ""
      
      if (nzchar(titre) || nzchar(soustitre) || nzchar(caption)) {
        pw <- pw + patchwork::plot_annotation(
          title    = if (nzchar(titre))     titre     else NULL,
          subtitle = if (nzchar(soustitre)) soustitre else NULL,
          caption  = if (nzchar(caption))   caption   else NULL,
          theme    = ggplot2::theme(
            plot.title      = ggplot2::element_text(color = "#EAF2F8", size = 15,
                                                    face = "bold", hjust = 0.5),
            plot.subtitle   = ggplot2::element_text(color = "#7FB3D3", size = 11,
                                                    hjust = 0.5),
            plot.caption    = ggplot2::element_text(color = "#4A7A99", size = 9,
                                                    hjust = 1),
            plot.background = ggplot2::element_rect(fill = "#061A2B", color = NA)
          )
        )
      }
      
      pw
    })
  }) |> shiny::bindEvent(input$compo_refresh, ignoreNULL = TRUE)
  
  # ===========================================================================
  # 8. APERÇU
  # ===========================================================================
  
  # Reactive qui indique si une composition est disponible (distinct de compo_patchwork
  # pour éviter d'avaler silencieusement le req() via tryCatch)
  compo_ready <- shiny::reactive({
    shiny::req(input$compo_refresh)          # propagation normale
    length(rv$compo_slots %||% list()) >= 1
  }) |> shiny::bindEvent(input$compo_refresh, ignoreNULL = TRUE)
  
  output$compo_preview_ui <- shiny::renderUI({
    ready <- tryCatch(isTRUE(compo_ready()), error = function(e) FALSE)
    
    if (!ready) {
      return(shiny::div(
        class = "compo-empty-info",
        shiny::icon("eye"), shiny::br(),
        "L'apercu apparaitra ici.", shiny::br(),
        "Ajoutez des graphiques et cliquez 'Composer et apercevoir'."
      ))
    }
    
    shiny::plotOutput("compo_preview_plot", width = "100%", height = "700px")
  })
  
  output$compo_preview_plot <- shiny::renderPlot({
    print(compo_patchwork())
  }, bg = "#061A2B")
  
  # ===========================================================================
  # 9. EXPORTS
  # ===========================================================================
  
  .make_export <- function(ext, device = NULL, bg = "#061A2B") {
    list(
      filename = function()
        paste0("composition_", format(Sys.time(), "%Y%m%d_%H%M"), ".", ext),
      
      content = function(file) {
        pw <- tryCatch(compo_patchwork(), error = function(e) NULL)
        shiny::validate(shiny::need(!is.null(pw), "Aucune composition a exporter."))
        
        w   <- as.integer(input$compo_largeur %||% 2400)
        h   <- as.integer(input$compo_hauteur %||% 1600)
        dpi <- as.integer(input$compo_dpi     %||% 150)
        
        shiny::withProgress(
          message = if (ext == "pdf") "Rendu PDF..." else "Rendu PNG haute resolution...",
          {
            args <- list(filename = file, plot = pw,
                         width = w / dpi, height = h / dpi,
                         dpi = dpi, bg = bg)
            if (!is.null(device)) args$device <- device
            
            tryCatch(
              do.call(ggplot2::ggsave, args),
              error = function(e)
                shiny::showNotification(
                  paste("Export", toupper(ext), "echoue :", e$message),
                  type = "error", duration = 6)
            )
          }
        )
      }
    )
  }
  
  png_handler <- .make_export("png")
  pdf_handler <- .make_export("pdf", device = "pdf", bg = "white")
  
  output$compo_export_png <- shiny::downloadHandler(
    filename = png_handler$filename,
    content  = png_handler$content
  )
  
  output$compo_export_pdf <- shiny::downloadHandler(
    filename = pdf_handler$filename,
    content  = pdf_handler$content
  )
  
}