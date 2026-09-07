# =============================================================================
# functions_home.R — Fonctions utilitaires pour l'onglet Accueil
#
# Contient uniquement des helpers légers, sans dépendance à l'environnement
# réactif Shiny (pas de input/output/session ici).
# =============================================================================


# -----------------------------------------------------------------------------
# envoyer_feedback_email()
# 
# Tente d'envoyer un email via le package {blastula} si disponible,
# sinon log le message dans la console.
#
# Usage (appelé depuis server_home si on bascule vers un envoi côté R) :
#   envoyer_feedback_email(nom = "Jean", categorie = "Bug",
#                          message = "L'export PNG ne fonctionne pas.")
#
# Paramètres :
#   nom        – Nom de l'expéditeur (peut être vide)
#   categorie  – "suggestion" | "bug" | "question" | "autre"
#   message    – Corps du retour
#   dest       – Adresse email du destinataire
# -----------------------------------------------------------------------------

envoyer_feedback_email <- function(sujet, corps,
                                   dest = "bdegueurce@bretagne-peches.org") {
  tryCatch({
    api_key <- Sys.getenv("HAL_BREVO_API_KEY")
    
    if (nchar(api_key) == 0) {
      message("[functions_home] Clé API Brevo manquante dans .Renviron")
      return(FALSE)
    }
    
    response <- httr::POST(
      url = "https://api.brevo.com/v3/smtp/email",
      httr::add_headers(
        "api-key"      = api_key,
        "Content-Type" = "application/json"
      ),
      body = jsonlite::toJSON(list(
        sender  = list(name = "Plateforme HAL", email = "plateforme.hal.crpmem@gmail.com"),
        to      = list(list(email = dest)),
        subject = sujet,
        textContent = corps
      ), auto_unbox = TRUE)
    )
    
    if (httr::status_code(response) %in% c(200, 201)) {
      message("[functions_home] Email envoyé via API Brevo → ", dest)
      TRUE
    } else {
      message("[functions_home] Erreur API Brevo : ", httr::content(response, "text"))
      FALSE
    }
    
  }, error = function(e) {
    message("[functions_home] Erreur : ", e$message)
    FALSE
  })
}


# -----------------------------------------------------------------------------
# formater_categorie_feedback()
#
# Retourne le libellé lisible d'une catégorie de feedback.
# -----------------------------------------------------------------------------

formater_categorie_feedback <- function(cat) {
  switch(cat,
         "suggestion" = "Suggestion",
         "bug"        = "Bug",
         "question"   = "Question",
         "autre"      = "Autre",
         cat   # fallback : valeur brute
  )
}


# -----------------------------------------------------------------------------
# stats_accueil()
#
# Calcule les chiffres clés affichés dans la section hero de l'accueil,
# à partir du rv partagé (liste ou reactiveValues).
#
# Retourne une liste nommée : lignes, colonnes, modules
# -----------------------------------------------------------------------------

stats_accueil <- function(rv) {
  
  df <- tryCatch(rv$data_clean, error = function(e) NULL)
  
  list(
    lignes   = if (!is.null(df)) format(nrow(df),  big.mark = "\u202f") else "\u2014",
    colonnes = if (!is.null(df)) format(ncol(df),  big.mark = "\u202f") else "\u2014",
    modules  = 4L   # nombre d'onglets actifs (à adapter si l'app évolue)
  )
}