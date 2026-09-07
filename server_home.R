# =============================================================================
# server_home.R
# =============================================================================

server_home <- function(input, output, session, rv) {
  
  # ---------------------------------------------------------------------------
  # ENVOI EMAIL FEEDBACK
  # ---------------------------------------------------------------------------
  
  shiny::observeEvent(input$acc_fb_send, {
    
    msg      <- trimws(input$acc_fb_msg      %||% "")
    nom      <- trimws(input$acc_fb_nom      %||% "")
    categorie <- trimws(input$acc_fb_category %||% "Autre")
    
    # Validation
    if (nchar(msg) == 0) {
      shiny::showNotification(
        "Veuillez saisir un message avant d'envoyer.",
        type = "warning", duration = 4
      )
      return()
    }
    
    expediteur <- if (nchar(nom) > 0) nom else "Utilisateur anonyme"
    cat_label  <- formater_categorie_feedback(categorie)
    sujet      <- sprintf("[Plateforme HAL] %s — %s", cat_label, expediteur)
    
    corps <- paste0(
      "**Catégorie :** ", cat_label, "\n",
      "**De :** ", expediteur, "\n",
      "**Horodatage :** ", format(Sys.time(), "%d/%m/%Y à %H:%M"), "\n\n",
      "---\n\n",
      msg
    )
    
    succes <- envoyer_feedback_email(
      sujet = sujet,
      corps = corps
    )
    
    if (succes) {
      # Réinitialise les champs via JS
      shinyjs::runjs("
        document.getElementById('acc_fb_msg').value = '';
        document.getElementById('acc_fb_nom').value = '';
        var ok = document.getElementById('acc_fb_success');
        ok.classList.add('visible');
        setTimeout(function() { ok.classList.remove('visible'); }, 5000);
      ")
      shiny::showNotification(
        tagList(shiny::icon("check-circle"), " Message envoyé avec succès !"),
        type = "message", duration = 5
      )
    } else {
      shiny::showNotification(
        "Erreur lors de l'envoi. Contactez directement bdegueurce@bretagne-peches.org",
        type = "error", duration = 8
      )
    }
  })
  
  # Notification de bienvenue
  shiny::observe({
    shiny::showNotification(
      tagList(
        shiny::icon("fish"),
        shiny::HTML(" Bienvenue ! Chargez un fichier dans <em>Données</em> pour commencer.")
      ),
      type = "message", duration = 6
    )
  }) |> shiny::bindEvent(session$clientData$url_pathname, once = TRUE, ignoreNULL = TRUE)
  
}