# =============================================================================
# UTILITAIRE UTF-8
# Nettoie toutes les colonnes character d'un dataframe pour garantir un
# encodage UTF-8 valide avant export openxlsx (évite l'erreur stri_length).
# =============================================================================
sanitize_utf8 <- function(df) {
  df[] <- lapply(df, function(col) {
    if (is.character(col) || is.factor(col)) {
      stringi::stri_enc_toutf8(as.character(col), is_unknown_8bit = TRUE, validate = TRUE)
    } else {
      col
    }
  })
  df
}

import_data <- function(files, mois_vec) {
  
  liste_df <- lapply(seq_along(files), function(i) {
    
    if(file.exists(files[i])) {
      
      df <- read.csv(files[i], colClasses = c(stat_rect = "character"),
                     fileEncoding = "UTF-8-BOM")
      # Fallback : nettoie les bytes invalides UTF-8 résiduels (fichiers latin1/Windows-1252)
      df <- sanitize_utf8(df)
      df$mois <- mois_vec[i]
      return(df)
      
    } else {
      warning(paste("Fichier manquant :", files[i]))
      return(NULL)
    }
  })
  
  liste_df <- Filter(Negate(is.null), liste_df)
  df_final <- do.call(rbind, liste_df)
  
  return(df_final)
}

clean_donnees <- function(df, sp, OP = NULL) {
  
  library(dplyr)
  
  df_clean <- df %>%
    
    # =========================
  # 1. SUPPRESSION COLONNES (si présentes)
  # =========================
  select(-any_of(c(
    "X",
    "origine_esp_cod_fao",
    "ZEE_cod",
    "dimension_utilisation_id",
    "dimension_utilisation_sipa",
    "dimension",
    "dimension_physique_id",
    "dimension_physique",
    "maillage"
  ))) %>%
    
    # =========================
  # 2. FILTRES
  # =========================
  { if (!is.null(OP) && length(OP) > 0 && "op" %in% names(.)) filter(., op %in% OP) else . } %>%
    filter(esp_cod_fao == sp) %>%
    
    # =========================
  # 3. CONVERSIONS
  # =========================
  mutate(
    date = as.Date(date),
    
    # Dériver MM et YYYY depuis date si colonnes absentes ou vides
    MM   = if ("MM"   %in% names(.) && !all(is.na(MM)))   as.character(MM)   else format(date, "%m"),
    YYYY = if ("YYYY" %in% names(.) && !all(is.na(YYYY))) as.character(YYYY) else format(date, "%Y"),
    
    # an_ref (optionnel)
    an_ref = if ("an_ref" %in% names(.)) as.numeric(an_ref) else as.numeric(format(date, "%Y")),
    
    # facteurs (sécurisé)
    across(any_of(c(
      "div_ciem_cod_sipa","stat_rect","entreprise","quartier_cod",
      "nom_navire","engin_cod","engin_lib","esp_lib_fao_francais",
      "port_debarque_cod","port_debarque","NS","MM","YYYY","maree_id"
    )), as.factor),
    
    # numériques
    debarquement_Kg    = as.numeric(gsub(",", ".", debarquement_Kg)),
    debarquement_euros = as.numeric(gsub(",", ".", debarquement_euros))
  ) %>%
    
    # =========================
  # 4. AGREGER PAR MAREE
  # =========================
  group_by(maree_id) %>%
    summarise(
      across(where(is.factor), ~ first(.)),
      an_ref = first(an_ref),
      date = first(date),
      
      debarquement_Kg = sum(debarquement_Kg, na.rm = TRUE),
      debarquement_euros = sum(debarquement_euros, na.rm = TRUE),
      
      .groups = "drop"
    ) %>%
    
    # =========================
  # 5. AJOUT MOIS / ANNEE
  # =========================
  mutate(
    mois  = as.character(MM),
    annee = as.character(YYYY)
  )
  
  return(df_clean)
}

analyse_numerique <- function(df) {
  
  library(dplyr)
  
  res <- list()
  
  ################################################################################
  # 1. NOMBRE DE NAVIRES PAR QUARTIER
  ################################################################################
  
  res$navires_par_quartier <- df %>%
    group_by(quartier_cod) %>%
    summarise(nb_navires = n_distinct(nom_navire)) %>%
    arrange(desc(nb_navires))
  
  ################################################################################
  # 2. NAVIRES ET MAREES PAR MOIS
  ################################################################################
  
  res$navires_marees_mois <- df %>%
    group_by(annee, mois) %>%
    summarise(
      nb_navires = n_distinct(nom_navire),
      nb_marees = n_distinct(maree_id),
      .groups = "drop"
    ) %>%
    arrange(annee, mois)
  
  ################################################################################
  # 3. DUREE DE L’ECHANTILLON
  ################################################################################
  
  date_min <- min(df$date, na.rm = TRUE)
  date_max <- max(df$date, na.rm = TRUE)
  
  res$duree_echantillon <- data.frame(
    date_debut = date_min,
    date_fin = date_max,
    nb_jours = as.numeric(date_max - date_min)
  )
  
  ################################################################################
  # 4. NOMBRE DE JOURS ECHANTILLONNES PAR MOIS
  ################################################################################
  
  res$jours_par_mois <- df %>%
    group_by(annee, mois) %>%
    summarise(
      nb_jours = n_distinct(date),
      .groups = "drop"
    ) %>%
    arrange(annee, mois)
  
  ################################################################################
  # 5. NOMBRE TOTAL DE NAVIRES ET MAREES
  ################################################################################
  
  res$totaux <- data.frame(
    nb_navires_total = n_distinct(df$nom_navire),
    nb_marees_total = n_distinct(df$maree_id),
    nb_quartiers = n_distinct(df$quartier_cod)
  )
  
  ################################################################################
  # 6. ACTIVITE PAR NAVIRE (bonus très utile)
  ################################################################################
  
  res$activite_navires <- df %>%
    group_by(nom_navire) %>%
    summarise(
      nb_marees = n_distinct(maree_id),
      nb_jours = n_distinct(date),
      .groups = "drop"
    ) %>%
    arrange(desc(nb_marees))
  
  return(res)
}

check_engins_incoherents <- function(df, engin_incoh) {
  
  library(dplyr)
  
  ################################################################################
  # 1. FILTRER LES LIGNES INCOHERENTES
  ################################################################################
  
  df_incoh <- df %>%
    filter(!engin_cod %in% engin_incoh)
  
  ################################################################################
  # 2. RESUME PAR NAVIRE
  ################################################################################
  
  resume_navire <- df_incoh %>%
    group_by(nom_navire, quartier_cod) %>%
    summarise(
      nb_lignes  = n(),
      total_kg   = sum(debarquement_Kg, na.rm = TRUE),
      engins     = paste(unique(as.character(engin_cod)), collapse = "/"),
      .groups    = "drop"
    ) %>%
    arrange(desc(total_kg))
  
  ################################################################################
  # 3. RESUME PAR ENGIN
  ################################################################################
  
  resume_engin <- df_incoh %>%
    group_by(engin_cod) %>%
    summarise(
      nb_navires = n_distinct(nom_navire),
      nb_marees  = n_distinct(maree_id),
      total_kg   = sum(debarquement_Kg, na.rm = TRUE),
      .groups    = "drop"
    ) %>%
    arrange(desc(total_kg))
  
  ################################################################################
  # 4. STATS GLOBALES
  ################################################################################
  
  stats <- data.frame(
    nb_lignes_incoherentes = nrow(df_incoh),
    nb_navires_concernes   = n_distinct(df_incoh$nom_navire),
    total_kg_incoherent    = sum(df_incoh$debarquement_Kg, na.rm = TRUE)
  )
  
  ################################################################################
  # 5. OUTPUT
  ################################################################################
  
  return(list(
    lignes_incoherentes = df_incoh,
    resume_navire       = resume_navire,
    resume_engin        = resume_engin,
    stats               = stats
  ))
}

suivi_quota <- function(df, q, q_dgampa) {
  
  total <- sum(df$debarquement_Kg, na.rm = TRUE)
  
  ratio <- total / q
  
  diff_pct <- ((total - q_dgampa) / q_dgampa) * 100
  
  res <- data.frame(
    total_debarquement = total,
    quota = q,
    consommation_pct = ratio * 100,
    quota_annonce_dgampa = q_dgampa,
    ecart_avec_dgampa = diff_pct
  )
  
  return(res)
}

theme_perso <- function() {
  theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom",
      plot.margin = margin(5,5,5,5)
    )
}

# changez la destination à celle de votre choix #
create_plots <- function(df, output_dir, q) {
  library(ggplot2)
  dir.create(output_dir, showWarnings = FALSE)
  
  # 1️⃣ Nombre de navires par mois
  p1 <- df %>%
    group_by(mois) %>%
    summarise(nb_navires = n_distinct(nom_navire)) %>%
    ggplot(aes(x = mois, y = nb_navires)) +
    geom_col(fill = "steelblue") +
    labs(title = "Nombre de navires par mois", x = "Mois", y = "Nombre de navires") +
    theme_perso()
  
  # 2️⃣ Navires par quartier
  p2 <- df %>%
    group_by(quartier_cod) %>%
    summarise(nb_navires = n_distinct(nom_navire)) %>%
    arrange(desc(nb_navires)) %>%
    ggplot(aes(x = reorder(quartier_cod, nb_navires), y = nb_navires)) +
    geom_col(fill = "darkgreen") +
    coord_flip() +
    labs(title = "Nombre de navires par quartier", x = "", y = "Nombre de navires") +
    theme_perso()
  
  # 3️⃣ Navires par engin
  p3 <- df %>%
    group_by(engin_cod) %>%
    summarise(nb_navires = n_distinct(nom_navire)) %>%
    ggplot(aes(x = reorder(engin_cod, nb_navires), y = nb_navires)) +
    geom_col(fill = "orange") +
    labs(title = "Nombre de navires par engin", x = "Type d'engin", y = "Nombre de navires") +
    theme_perso()
  
  # 4️⃣ Proportion de chaque navire dans les débarquements (top 10 + "Autres")
  df_navire <- df %>%
    group_by(nom_navire) %>%
    summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
    arrange(desc(total)) %>%
    mutate(rank = row_number(),
           # forcer en character pour éviter les niveaux factor numérisés
           nom_navire = as.character(nom_navire),
           nom_navire_mod = ifelse(rank <= 10, nom_navire, "Autres")) %>%
    group_by(nom_navire_mod) %>%
    summarise(total = sum(total)) %>%
    ungroup() %>%
    mutate(pct = total / sum(total) * 100,
           label = paste0(nom_navire_mod, " (", round(pct,1), "%)"))
  
  # transformer en facteur pour que ggplot respecte l'ordre
  df_navire <- df %>%
    mutate(navire_id = paste0(nom_navire, " (", quartier_cod, ")")) %>%
    group_by(navire_id) %>%
    summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
    arrange(desc(total)) %>%
    mutate(rank = row_number(),
           navire_id_mod = ifelse(rank <= 10, navire_id, "Autres")) %>%
    group_by(navire_id_mod) %>%
    summarise(total = sum(total)) %>%
    ungroup() %>%
    mutate(pct = total / sum(total) * 100,
           label = paste0(navire_id_mod, " (", round(pct,1), "%)"))
  
  df_navire$navire_id_mod <- factor(df_navire$navire_id_mod, levels = df_navire$navire_id_mod)
  
  p4 <- ggplot(df_navire, aes(x = "", y = total, fill = label)) +
    geom_col(color = "white") +
    coord_polar("y") +
    labs(title = "Proportion des navires dans les débarquements (Top 10)", fill = "Navire") +
    theme_void() +
    theme(plot.title = element_text(face = "bold", size = 14),
          legend.text = element_text(size = 10))
  
  library(patchwork)
  
  # Assure-toi que chaque plot est un ggplot pur
  p1 <- p1 + labs(tag = "A")
  p2 <- p2 + labs(tag = "B")
  p3 <- p3 + labs(tag = "C")
  p4 <- p4 + labs(tag = "D")
  
  # Combine avec wrap_plots
  panel_navires <- patchwork::wrap_plots(
    p1, p2, p3, p4,
    ncol = 2, nrow = 2
  )
  
  ggsave(paste0(output_dir, "/panel_navires.png"), panel_navires, width = 14, height = 10)
  
  # 🌊 Débarquements cumulés
  df_cumul <- df %>%
    arrange(date) %>%
    mutate(cumul = cumsum(debarquement_Kg))
  
  p_cumul <- ggplot(df_cumul, aes(x = date, y = cumul)) +
    geom_line(linewidth = 0.5, color = "blue") +
    geom_point(size = 0.5, color = "darkblue") +
    geom_hline(yintercept = q, color = "red", linetype = "dashed") +
    annotate("text", x = max(df_cumul$date), y = q,
             label = paste0("Quota (", q, " kg)"), color = "red", hjust = 1, vjust = -0.5) +
    labs(title = "Cumul des débarquements", x = "Date", y = "Débarquement cumulé (Kg)") +
    theme_perso()
  
  ggsave(paste0(output_dir, "/cumul_debarquements.png"), p_cumul, width = 10, height = 5)
  
  # 📊 Débarquements par mois
  p_mois <- df %>%
    group_by(mois) %>%
    summarise(total = sum(debarquement_Kg, na.rm = TRUE)) %>%
    ggplot(aes(x = mois, y = total)) +
    geom_col(fill = "skyblue") +
    labs(title = "Débarquements par mois", x = "Mois", y = "Total débarqué (Kg)") +
    theme_perso()
  
  ggsave(paste0(output_dir, "/debarquement_mois.png"), p_mois, width = 10, height = 5)
  
  message("Tous les plots ont été créés et sauvegardés dans ", output_dir)
}

plot_cartes_ices <- function(df, input_ices, 
                             output_dir,
                             xlim, 
                             ylim) {
  
  library(dplyr)
  library(ggplot2)
  library(sf)
  library(rnaturalearth)
  ices_sf = st_read(input_ices)
  dir.create(output_dir, showWarnings = FALSE)
  
  # -----------------------------
  # Préparation des données
  # -----------------------------
  df <- df %>%
    mutate(stat_rect = as.character(stat_rect))
  
  ices_sf <- ices_sf %>%
    mutate(ICESNAME = as.character(ICESNAME))
  
  df_map <- df %>%
    group_by(stat_rect) %>%
    summarise(
      nb_marees = n(),
      kg = sum(debarquement_Kg, na.rm = TRUE),
      euros = sum(debarquement_euros, na.rm = TRUE),
      .groups = "drop"
    )
  
  map_data <- ices_sf %>%
    left_join(df_map, by = c("ICESNAME" = "stat_rect")) %>%
    filter(!is.na(nb_marees))  # supprimer rectangles sans données
  
  # fond carte monde
  world <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")
  
  # -----------------------------
  # Fonction interne pour plot
  # -----------------------------
  make_map <- function(variable, titre, filename) {
    
    vals <- map_data[[variable]]
    min_val <- min(vals, na.rm = TRUE)
    max_val <- max(vals, na.rm = TRUE)
    
    p <- ggplot() +
      
      geom_sf(data = ices_sf, fill = NA, color = "grey80", linewidth = 0.2) +
      geom_sf(data = map_data, aes(fill = .data[[variable]])) +
      geom_sf(data = world, fill = "grey95", color = NA) +
      # légende adaptée
      scale_fill_viridis_c(option = "magma", limits = c(min_val, max_val)) +
      
      coord_sf(xlim = xlim, ylim = ylim, expand = FALSE) +
      
      labs(
        title = titre,
        fill = variable
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(face = "bold"),
        legend.position = "right"
      )
    
    ggsave(
      paste0(output_dir, filename),
      p,
      width = 8,
      height = 6, create.dir = TRUE
    )
    
    return(p)
  }
  
  # -----------------------------
  # Création des cartes
  # -----------------------------
  p1 <- make_map("nb_marees", "Nombre de marées", "map_nb_marees.png")
  p2 <- make_map("kg", "Débarquement (Kg)", "map_kg.png")
  p3 <- make_map("euros", "Débarquement (€)", "map_euros.png")
  
  return(list(nb_marees = p1, kg = p2, euros = p3))
}

check_depassement_dynamique <- function(df, regles) {
  
  library(dplyr)
  library(lubridate)
  
  ##############################################################################
  # 1. CREATION DES PERIODES
  ##############################################################################
  
  df <- df %>%
    mutate(
      mois_id = floor_date(date, "month"),
      trimestre_id = floor_date(date, "quarter")
    )
  
  ##############################################################################
  # 2. FONCTION GENERIQUE
  ##############################################################################
  
  calc_periode <- function(data, group_var, type_periode) {
    
    data %>%
      group_by(nom_navire, quartier_cod, engin_cod, esp_lib_fao_francais, !!sym(group_var)) %>%
      summarise(
        total = sum(debarquement_Kg, na.rm = TRUE),
        date_ref = min(date),
        .groups = "drop"
      ) %>%
      mutate(
        periode_id = as.character(!!sym(group_var)),
        type_periode = type_periode
      )
  }
  
  ##############################################################################
  # 3. CALCUL DES 3 ECHELLES 🔥
  ##############################################################################
  
  dep_maree <- calc_periode(df, "maree_id", "maree")
  dep_mois  <- calc_periode(df, "mois_id", "mois")
  dep_trim  <- calc_periode(df, "trimestre_id", "trimestre")
  
  dep_all <- bind_rows(dep_maree, dep_mois, dep_trim)
  
  ##############################################################################
  # 4. JOIN AVEC REGLES
  ##############################################################################
  
  dep_all <- dep_all %>%
    inner_join(regles, by = c("esp_lib_fao_francais", "type_periode")) %>%
    filter(date_ref >= date_debut & date_ref <= date_fin)
  
  ##############################################################################
  # 5. CALCUL DEPASSEMENT
  ##############################################################################
  
  dep_all <- dep_all %>%
    mutate(
      depassement = pmax(total - limite, 0),
      flag = total > limite
    )
  
  ##############################################################################
  # 6. RESUME NAVIRE (IMPORTANT 🔥)
  ##############################################################################
  
  resume_navire <- dep_all %>%
    group_by(nom_navire, quartier_cod, engin_cod, esp_lib_fao_francais) %>%
    summarise(
      nb_depassements = sum(flag),
      kg_depassement = sum(depassement),
      .groups = "drop"
    ) %>%
    filter(nb_depassements > 0) %>%
    arrange(desc(kg_depassement))
  
  ##############################################################################
  # 7. OUTPUT
  ##############################################################################
  
  return(list(
    detail = dep_all,
    resume_navire = resume_navire
  ))
}

export_results <- function(df_clean,
                           suivi,
                           table_navires,
                           res,
                           res_incoh,
                           res_dep,
                           output_dir) {
  
  library(openxlsx)
  
  # =========================
  # 1. CREATION DOSSIER
  # =========================
  if(!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # =========================
  # 2. EXPORT SIMPLES
  # =========================
  dfs_simples <- list(
    data_utilisee = df_clean,
    suivi_du_quota = suivi,
    infos_navires = table_navires
  )
  
  for(nom in names(dfs_simples)) {
    
    wb <- createWorkbook()
    addWorksheet(wb, nom)
    writeData(wb, nom, sanitize_utf8(dfs_simples[[nom]]))
    
    saveWorkbook(
      wb,
      file = file.path(output_dir, paste0(nom, ".xlsx")),
      overwrite = TRUE
    )
  }
  
  # =========================
  # 3. EXPORT LISTES MULTI-FEUILLES
  # =========================
  liste_resultats <- list(
    resume_flotte = res,
    resume_incoherence = res_incoh,
    resume_depassements = res_dep
  )
  
  nom_feuilles <- list(
    resume_flotte = c(
      "navires_par_quartier",
      "navires_marees_mois",
      "duree_echantillon",
      "jours_par_mois",
      "totaux",
      "activite_navires"
    ),
    
    resume_incoherence = c(
      "lignes_incoherentes",
      "resume_navire",
      "stats"
    ),
    
    resume_depassements = c(
      "detail",
      "resume_navire"
    )
  )
  
  # =========================
  # 4. BOUCLE EXPORT LISTES
  # =========================
  for(lst_name in names(liste_resultats)) {
    
    wb <- createWorkbook()
    lst <- liste_resultats[[lst_name]]
    sheets <- nom_feuilles[[lst_name]]
    
    # sécurité
    if(length(lst) != length(sheets)) {
      warning(paste(
        "Mismatch feuilles pour", lst_name,
        "- export partiel"
      ))
    }
    
    for(i in seq_along(lst)) {
      
      sheet_name <- sheets[i]
      
      addWorksheet(wb, sheet_name)
      writeData(wb, sheet_name, sanitize_utf8(lst[[i]]))
    }
    
    saveWorkbook(
      wb,
      file = file.path(output_dir, paste0(lst_name, ".xlsx")),
      overwrite = TRUE
    )
  }
  
  message("Exports réalisés dans : ", output_dir)
}

run_quota_pipeline <- function(df,
                               sp,
                               regles,
                               engin_incoh,
                               q,
                               q_dgampa,
                               input_ices,
                               output_tab,
                               output_plot,
                               progress = NULL) {
  
  if(!is.null(progress)) progress$set(0.1, "Clean")
  df_clean <- clean_donnees(df, sp)
  
  if(!is.null(progress)) progress$set(0.25, "Analyse")
  res <- analyse_numerique(df_clean)
  
  if(!is.null(progress)) progress$set(0.4, "Incohérences")
  incoh <- check_engins_incoherents(df_clean, engin_incoh)
  
  if(!is.null(progress)) progress$set(0.55, "Quota")
  quota <- suivi_quota(df_clean, q, q_dgampa)
  
  if(!is.null(progress)) progress$set(0.7, "Plots")
  plots <- create_plots(df_clean, q, output_plot)
  
  if(!is.null(progress)) progress$set(0.85, "Carte")
  map <- plot_cartes_ices(df_clean, input_ices, output_plot)
  
  if(!is.null(progress)) progress$set(1, "Export")
  nav_table <- table_navires(df_clean)
  
  export_results(
    list(
      quota = quota,
      navires = nav_table
    ),
    output_tab
  )
  
  return(list(
    data = df_clean,
    res = res,
    incoh = incoh,
    quota = quota,
    plots = plots,
    map = map,
    table = nav_table
  ))
}