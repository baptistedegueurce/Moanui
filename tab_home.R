# =============================================================================
# tab_accueil.R — Page d'accueil de la Plateforme d'analyse halieutique
# Design cohérent avec le thème sombre CRPMEM
# Formulaire de retour → mailto bdegueurce@bretagne-peches.org
# =============================================================================

tab_home <- bslib::nav_panel(
  title = "Accueil",
  icon  = shiny::icon("house"),
  
  shiny::tags$head(
    shiny::tags$link(
      rel  = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=Inter:wght@300;400;500;600&display=swap"
    )
  ),
  
  shiny::tags$style(shiny::HTML("

    /* ================================================================
       RESET & BASE
    ================================================================ */
    .accueil-root {
      font-family: 'Inter', sans-serif;
      color: #C9D6DF;
      background: #061A2B;
      min-height: 100vh;
      padding: 0;
      margin: -14px -15px 0 -15px; /* couvre les marges bslib */
    }

    /* ================================================================
       HERO
    ================================================================ */
    .acc-hero {
      position: relative;
      overflow: hidden;
      background: linear-gradient(135deg, #03111E 0%, #061A2B 45%, #082D47 100%);
      padding: 72px 60px 64px;
      border-bottom: 1px solid #0E3A56;
    }

    /* Grille décorative en arrière-plan */
    .acc-hero::before {
      content: '';
      position: absolute;
      inset: 0;
      background-image:
        linear-gradient(rgba(0,119,182,0.06) 1px, transparent 1px),
        linear-gradient(90deg, rgba(0,119,182,0.06) 1px, transparent 1px);
      background-size: 48px 48px;
      pointer-events: none;
    }

    /* Halo lumineux */
    .acc-hero::after {
      content: '';
      position: absolute;
      top: -120px;
      right: -80px;
      width: 600px;
      height: 600px;
      background: radial-gradient(circle, rgba(0,119,182,0.18) 0%, transparent 65%);
      pointer-events: none;
    }

    .acc-hero-inner {
      position: relative;
      z-index: 1;
      max-width: 1100px;
      margin: 0 auto;
    }

    .acc-badge {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      background: rgba(0,119,182,0.15);
      border: 1px solid rgba(0,119,182,0.4);
      border-radius: 20px;
      padding: 5px 14px;
      font-size: 11px;
      font-weight: 600;
      letter-spacing: .08em;
      text-transform: uppercase;
      color: #7FB3D3;
      margin-bottom: 24px;
    }
    .acc-badge i { font-size: 10px; color: #0077B6; }

    .acc-hero h1 {
      font-family: 'Syne', sans-serif;
      font-size: clamp(32px, 4vw, 52px);
      font-weight: 800;
      color: #EAF2F8;
      line-height: 1.1;
      margin: 0 0 10px;
      letter-spacing: -.02em;
    }
    .acc-hero h1 span {
      background: linear-gradient(90deg, #0096C7, #00B4D8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }

    .acc-hero-sub {
      font-size: 16px;
      color: #7FB3D3;
      font-weight: 300;
      max-width: 580px;
      line-height: 1.65;
      margin: 0 0 36px;
    }

    .acc-hero-stats {
      display: flex;
      gap: 40px;
      flex-wrap: wrap;
    }
    .acc-stat {
      display: flex;
      flex-direction: column;
    }
    .acc-stat-val {
      font-family: 'Syne', sans-serif;
      font-size: 28px;
      font-weight: 700;
      color: #EAF2F8;
      line-height: 1;
    }
    .acc-stat-lbl {
      font-size: 11px;
      color: #5A8FAA;
      text-transform: uppercase;
      letter-spacing: .07em;
      margin-top: 4px;
    }
    .acc-stat-sep {
      width: 1px;
      background: #0E3A56;
      align-self: stretch;
    }

    /* ================================================================
       SECTION GÉNÉRALE
    ================================================================ */
    .acc-section {
      max-width: 1100px;
      margin: 0 auto;
      padding: 52px 60px;
    }
    .acc-section + .acc-section {
      padding-top: 0;
    }

    .acc-section-title {
      font-family: 'Syne', sans-serif;
      font-size: 13px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: .12em;
      color: #0096C7;
      margin-bottom: 6px;
    }
    .acc-section-heading {
      font-family: 'Syne', sans-serif;
      font-size: clamp(20px, 2.5vw, 28px);
      font-weight: 700;
      color: #EAF2F8;
      margin: 0 0 32px;
      line-height: 1.2;
    }

    /* ================================================================
       CARDS MODULES
    ================================================================ */
    .acc-modules-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
      gap: 16px;
    }

    .acc-module-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 12px;
      padding: 24px;
      transition: border-color .2s, transform .2s, box-shadow .2s;
      cursor: default;
      position: relative;
      overflow: hidden;
    }
    .acc-module-card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 3px;
      background: var(--accent, #0077B6);
      border-radius: 12px 12px 0 0;
      opacity: 0;
      transition: opacity .2s;
    }
    .acc-module-card:hover {
      border-color: #1D4E6D;
      transform: translateY(-3px);
      box-shadow: 0 12px 32px rgba(0,0,0,0.35);
    }
    .acc-module-card:hover::before { opacity: 1; }

    .acc-module-icon {
      width: 44px;
      height: 44px;
      border-radius: 10px;
      background: rgba(0,119,182,0.12);
      border: 1px solid rgba(0,119,182,0.25);
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 16px;
      font-size: 18px;
      color: var(--accent, #0077B6);
    }
    .acc-module-title {
      font-family: 'Syne', sans-serif;
      font-size: 15px;
      font-weight: 700;
      color: #EAF2F8;
      margin-bottom: 8px;
    }
    .acc-module-desc {
      font-size: 12.5px;
      color: #7FB3D3;
      line-height: 1.65;
      margin-bottom: 14px;
    }
    .acc-module-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
    }
    .acc-tag {
      font-size: 10px;
      font-weight: 600;
      padding: 3px 9px;
      border-radius: 10px;
      background: rgba(0,119,182,0.1);
      border: 1px solid rgba(0,119,182,0.25);
      color: #7FB3D3;
      letter-spacing: .04em;
    }

    /* ================================================================
       WORKFLOW (COMMENT ÇA MARCHE)
    ================================================================ */
    .acc-divider {
      border: none;
      border-top: 1px solid #0E3A56;
      margin: 0;
    }

    .acc-workflow {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 0;
      position: relative;
    }
    .acc-workflow::before {
      content: '';
      position: absolute;
      top: 28px;
      left: 10%;
      right: 10%;
      height: 1px;
      background: linear-gradient(90deg, transparent, #1D4E6D 20%, #1D4E6D 80%, transparent);
    }

    .acc-wf-step {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      padding: 0 16px 24px;
      position: relative;
      z-index: 1;
    }
    .acc-wf-num {
      width: 56px;
      height: 56px;
      border-radius: 50%;
      background: #061A2B;
      border: 2px solid #0077B6;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: 'Syne', sans-serif;
      font-size: 18px;
      font-weight: 800;
      color: #0096C7;
      margin-bottom: 14px;
      box-shadow: 0 0 0 6px rgba(0,119,182,0.08);
    }
    .acc-wf-title {
      font-family: 'Syne', sans-serif;
      font-size: 13px;
      font-weight: 700;
      color: #EAF2F8;
      margin-bottom: 6px;
    }
    .acc-wf-desc {
      font-size: 11.5px;
      color: #5A8FAA;
      line-height: 1.6;
    }

    /* ================================================================
       EXEMPLES GRAPHIQUES (grille visuelle)
    ================================================================ */
    .acc-examples-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 12px;
    }

    .acc-example-card {
      background: #0B2A3D;
      border: 1px solid #123A52;
      border-radius: 10px;
      overflow: hidden;
      transition: border-color .2s, transform .2s;
    }
    .acc-example-card:hover {
      border-color: #1D4E6D;
      transform: translateY(-2px);
    }

    .acc-example-visual {
      height: 110px;
      display: flex;
      align-items: flex-end;
      justify-content: center;
      padding: 12px 16px 8px;
      background: #082030;
      gap: 6px;
    }

    /* Mini bar chart */
    .mini-bar {
      border-radius: 3px 3px 0 0;
      flex: 1;
      max-width: 28px;
      background: #0077B6;
      opacity: .85;
      transition: opacity .2s;
    }
    .acc-example-card:hover .mini-bar { opacity: 1; }

    /* Mini line chart */
    .mini-line-wrap {
      width: 100%;
      height: 80px;
      position: relative;
    }
    .mini-line-wrap svg { width: 100%; height: 100%; }

    /* Mini scatter */
    .mini-dot {
      width: 8px; height: 8px;
      border-radius: 50%;
      background: #2E9E6B;
      position: absolute;
    }

    .acc-example-label {
      padding: 10px 14px;
      font-size: 12px;
      font-weight: 600;
      color: #C9D6DF;
      display: flex;
      align-items: center;
      gap: 7px;
    }
    .acc-example-label i { color: #0077B6; font-size: 11px; }

    /* ================================================================
       FORMATS FICHIERS
    ================================================================ */
    .acc-formats {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 8px;
    }
    .acc-format-pill {
      background: #082030;
      border: 1px solid #123A52;
      border-radius: 8px;
      padding: 8px 16px;
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;
      font-weight: 600;
      color: #C9D6DF;
      transition: border-color .15s;
    }
    .acc-format-pill:hover { border-color: #1D4E6D; }
    .acc-format-pill i { color: #0077B6; }

    /* ================================================================
       FORMULAIRE RETOURS
    ================================================================ */
    .acc-feedback-wrap {
      background: linear-gradient(135deg, #061A2B 0%, #082030 100%);
      border-top: 1px solid #0E3A56;
    }

    .acc-feedback-inner {
      max-width: 1100px;
      margin: 0 auto;
      padding: 52px 60px;
      display: grid;
      grid-template-columns: 1fr 1.6fr;
      gap: 60px;
      align-items: start;
    }

    .acc-feedback-left h2 {
      font-family: 'Syne', sans-serif;
      font-size: 24px;
      font-weight: 800;
      color: #EAF2F8;
      margin: 0 0 10px;
      line-height: 1.2;
    }
    .acc-feedback-left p {
      font-size: 13px;
      color: #5A8FAA;
      line-height: 1.7;
      margin: 0 0 24px;
    }
    .acc-feedback-contact {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 12px;
      color: #7FB3D3;
      padding: 10px 14px;
      background: rgba(0,119,182,0.08);
      border: 1px solid rgba(0,119,182,0.2);
      border-radius: 8px;
    }
    .acc-feedback-contact i { color: #0077B6; }
    .acc-feedback-contact strong { color: #EAF2F8; }

    /* Catégories feedback */
    .acc-fb-cats {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-bottom: 16px;
    }
    .acc-fb-cat {
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 11px;
      font-weight: 600;
      border: 1px solid #123A52;
      background: #082030;
      color: #7FB3D3;
      cursor: pointer;
      transition: all .15s;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .acc-fb-cat:hover,
    .acc-fb-cat.selected {
      background: rgba(0,119,182,0.15);
      border-color: rgba(0,119,182,0.5);
      color: #EAF2F8;
    }
    .acc-fb-cat i { font-size: 10px; }

    /* Champs formulaire */
    .acc-fb-form {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .acc-fb-field label {
      display: block;
      font-size: 11px;
      font-weight: 600;
      color: #7FB3D3;
      text-transform: uppercase;
      letter-spacing: .06em;
      margin-bottom: 5px;
    }
    .acc-fb-field input,
    .acc-fb-field textarea {
      width: 100%;
      background: #082030 !important;
      border: 1px solid #123A52 !important;
      border-radius: 8px !important;
      color: #EAF2F8 !important;
      font-family: 'Inter', sans-serif !important;
      font-size: 13px !important;
      padding: 10px 14px !important;
      box-sizing: border-box;
      transition: border-color .15s !important;
      resize: vertical;
    }
    .acc-fb-field input:focus,
    .acc-fb-field textarea:focus {
      border-color: #0077B6 !important;
      outline: none !important;
      box-shadow: 0 0 0 3px rgba(0,119,182,0.12) !important;
    }
    .acc-fb-field input::placeholder,
    .acc-fb-field textarea::placeholder { color: #2E5A7A !important; }

    .acc-fb-submit {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-top: 4px;
      gap: 12px;
    }
    .acc-fb-btn {
      background: #0077B6;
      color: #fff;
      border: none;
      border-radius: 8px;
      padding: 11px 24px;
      font-family: 'Syne', sans-serif;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      transition: background .15s, transform .1s;
      display: flex;
      align-items: center;
      gap: 8px;
      letter-spacing: .03em;
    }
    .acc-fb-btn:hover { background: #005F8E; transform: translateY(-1px); }
    .acc-fb-btn:active { transform: none; }

    .acc-fb-notice {
      font-size: 11px;
      color: #2E5A7A;
      line-height: 1.5;
    }

    .acc-fb-success {
      display: none;
      padding: 14px 18px;
      background: rgba(46,158,107,0.12);
      border: 1px solid rgba(46,158,107,0.35);
      border-radius: 8px;
      font-size: 13px;
      color: #2E9E6B;
      align-items: center;
      gap: 10px;
    }
    .acc-fb-success.visible { display: flex; }


    /* ================================================================
       RESPONSIVE
    ================================================================ */
    @media (max-width: 768px) {
      .acc-hero { padding: 40px 24px 36px; }
      .acc-section { padding: 36px 24px; }
      .acc-feedback-inner {
        grid-template-columns: 1fr;
        gap: 32px;
        padding: 36px 24px;
      }
      .acc-footer { padding: 16px 24px; flex-direction: column; gap: 6px; text-align: center; }
      .acc-workflow::before { display: none; }
      .acc-hero-stats { gap: 24px; }
    }

  ")),
  
  shiny::div(class = "accueil-root",
             
             # ===========================================================================
             # HERO
             # ===========================================================================
             shiny::div(class = "acc-hero",
                        shiny::div(class = "acc-hero-inner",
                                   
                                   shiny::div(class = "acc-badge",
                                              shiny::icon("fish"), "Plateforme d\u00e9di\u00e9e \u00e0 la p\u00eache bretonne"
                                   ),
                                   
                                   shiny::tags$h1(
                                     "Analyse halieutique", shiny::tags$br(),
                                     shiny::tags$span("int\u00e9gr\u00e9e & interactive")
                                   ),
                                   
                                   shiny::div(class = "acc-hero-sub",
                                              "Explorez, nettoyez et visualisez vos donn\u00e9es de d\u00e9barquements, de CPUE et de prix
           avec un environnement d\u2019analyse complet, sans \u00e9crire une ligne de code."
                                   ),
                                   
                                   shiny::div(class = "acc-hero-stats",
                                              shiny::div(class = "acc-stat",
                                                         shiny::div(class = "acc-stat-val", "4"),
                                                         shiny::div(class = "acc-stat-lbl", "Modules")
                                              ),
                                              shiny::div(class = "acc-stat-sep"),
                                              shiny::div(class = "acc-stat",
                                                         shiny::div(class = "acc-stat-val", "11+"),
                                                         shiny::div(class = "acc-stat-lbl", "Types de graphiques")
                                              ),
                                              shiny::div(class = "acc-stat-sep"),
                                              shiny::div(class = "acc-stat",
                                                         shiny::div(class = "acc-stat-val", "7"),
                                                         shiny::div(class = "acc-stat-lbl", "Formats import\u00e9s")
                                              ),
                                              shiny::div(class = "acc-stat-sep"),
                                              shiny::div(class = "acc-stat",
                                                         shiny::div(class = "acc-stat-val", "100\u00a0%"),
                                                         shiny::div(class = "acc-stat-lbl", "Sans code")
                                              )
                                   )
                        )
             ),
             
             # ===========================================================================
             # MODULES
             # ===========================================================================
             shiny::div(class = "acc-section",
                        
                        shiny::div(class = "acc-section-title", shiny::icon("cubes"), " Modules"),
                        shiny::div(class = "acc-section-heading", "Tout ce que vous pouvez faire"),
                        
                        shiny::div(class = "acc-modules-grid",
                                   
                                   # Import & nettoyage
                                   shiny::div(class = "acc-module-card", style = "--accent:#0077B6;",
                                              shiny::div(class = "acc-module-icon", style = "--accent:#0077B6;",
                                                         shiny::icon("upload")),
                                              shiny::div(class = "acc-module-title", "Import & Nettoyage"),
                                              shiny::div(class = "acc-module-desc",
                                                         "Chargez vos fichiers CSV, XLSX, RDS ou JSON. D\u00e9tection automatique
             des colonnes, gestion des valeurs manquantes, filtrage par p\u00e9riode,
             esp\u00e8ce, engin ou quartier. Export des donn\u00e9es nettoy\u00e9es."
                                              ),
                                              shiny::div(class = "acc-module-tags",
                                                         shiny::div(class = "acc-tag", "CSV / XLSX / RDS"),
                                                         shiny::div(class = "acc-tag", "Valeurs manquantes"),
                                                         shiny::div(class = "acc-tag", "Filtres avanc\u00e9s")
                                              )
                                   ),
                                   
                                   # Visualisation
                                   shiny::div(class = "acc-module-card", style = "--accent:#2E9E6B;",
                                              shiny::div(class = "acc-module-icon", style = "background:rgba(46,158,107,0.12); border-color:rgba(46,158,107,0.3); color:#2E9E6B;",
                                                         shiny::icon("chart-bar")),
                                              shiny::div(class = "acc-module-title", "Repr\u00e9sentation des donn\u00e9es"),
                                              shiny::div(class = "acc-module-desc",
                                                         "Cr\u00e9ez des graphiques interactifs en quelques clics : barres, lignes,
             points, bo\u00eetes, violons, camemberts, lollipops\u2026 Facettes,
             r\u00e9gression lin\u00e9aire avec \u00e9quation, export PNG haute r\u00e9solution."
                                              ),
                                              shiny::div(class = "acc-module-tags",
                                                         shiny::div(class = "acc-tag", "11 types"),
                                                         shiny::div(class = "acc-tag", "Facettes"),
                                                         shiny::div(class = "acc-tag", "R\u00e9gression"),
                                                         shiny::div(class = "acc-tag", "Export PNG / HTML")
                                              )
                                   ),
                                   
                                   # Statistiques
                                   shiny::div(class = "acc-module-card", style = "--accent:#E07B39;",
                                              shiny::div(class = "acc-module-icon", style = "background:rgba(224,123,57,0.12); border-color:rgba(224,123,57,0.3); color:#E07B39;",
                                                         shiny::icon("calculator")),
                                              shiny::div(class = "acc-module-title", "Statistiques descriptives"),
                                              shiny::div(class = "acc-module-desc",
                                                         "R\u00e9sum\u00e9s automatiques par variable, tableaux crois\u00e9s dynamiques,
             distributions, corr\u00e9lations. Identifiez les tendances et anomalies
             dans vos s\u00e9ries de d\u00e9barquements."
                                              ),
                                              shiny::div(class = "acc-module-tags",
                                                         shiny::div(class = "acc-tag", "R\u00e9sum\u00e9s"),
                                                         shiny::div(class = "acc-tag", "Corr\u00e9lations"),
                                                         shiny::div(class = "acc-tag", "Distributions")
                                              )
                                   ),
                                   
                                   # Cartographie
                                   shiny::div(class = "acc-module-card", style = "--accent:#9B59B6;",
                                              shiny::div(class = "acc-module-icon", style = "background:rgba(155,89,182,0.12); border-color:rgba(155,89,182,0.3); color:#9B59B6;",
                                                         shiny::icon("map")),
                                              shiny::div(class = "acc-module-title", "Cartographie"),
                                              shiny::div(class = "acc-module-desc",
                                                         "Visualisez vos donn\u00e9es sur carte : rectangles statistiques CIEM,
             zones de p\u00eache, ports de d\u00e9barquement. Agr\u00e9gation spatiale
             et s\u00e9lection g\u00e9ographique interactive."
                                              ),
                                              shiny::div(class = "acc-module-tags",
                                                         shiny::div(class = "acc-tag", "Rectangles CIEM"),
                                                         shiny::div(class = "acc-tag", "Ports"),
                                                         shiny::div(class = "acc-tag", "Couches interactives")
                                              )
                                   )
                                   
                        )
             ),
             
             shiny::tags$hr(class = "acc-divider"),
             
             # ===========================================================================
             # COMMENT ÇA MARCHE
             # ===========================================================================
             shiny::div(class = "acc-section",
                        
                        shiny::div(class = "acc-section-title", shiny::icon("route"), " Workflow"),
                        shiny::div(class = "acc-section-heading", "Comment \u00e7a marche"),
                        
                        shiny::div(class = "acc-workflow",
                                   
                                   shiny::div(class = "acc-wf-step",
                                              shiny::div(class = "acc-wf-num", "1"),
                                              shiny::div(class = "acc-wf-title", "Chargez vos donn\u00e9es"),
                                              shiny::div(class = "acc-wf-desc",
                                                         "Importez un fichier CSV, XLSX, RDS ou JSON depuis le module Import,
             ou utilisez les donn\u00e9es d\u00e9j\u00e0 pr\u00e9sentes dans l\u2019application.")
                                   ),
                                   
                                   shiny::div(class = "acc-wf-step",
                                              shiny::div(class = "acc-wf-num", "2"),
                                              shiny::div(class = "acc-wf-title", "Nettoyez & filtrez"),
                                              shiny::div(class = "acc-wf-desc",
                                                         "Appliquez des filtres par p\u00e9riode, esp\u00e8ce ou engin.
             G\u00e9rez les valeurs aberrantes et exportez les donn\u00e9es nettoy\u00e9es.")
                                   ),
                                   
                                   shiny::div(class = "acc-wf-step",
                                              shiny::div(class = "acc-wf-num", "3"),
                                              shiny::div(class = "acc-wf-title", "Choisissez un graphique"),
                                              shiny::div(class = "acc-wf-desc",
                                                         "S\u00e9lectionnez le type de visualisation, les axes X/Y,
             la variable de couleur et les options avanc\u00e9es (facettes, r\u00e9gression...).")
                                   ),
                                   
                                   shiny::div(class = "acc-wf-step",
                                              shiny::div(class = "acc-wf-num", "4"),
                                              shiny::div(class = "acc-wf-title", "Exportez & partagez"),
                                              shiny::div(class = "acc-wf-desc",
                                                         "T\u00e9l\u00e9chargez vos graphiques en PNG haute r\u00e9solution ou HTML interactif.
             Exportez les donn\u00e9es agr\u00e9g\u00e9es en CSV.")
                                   )
                                   
                        )
             ),
             
             shiny::tags$hr(class = "acc-divider"),
             
             # ===========================================================================
             # EXEMPLES DE GRAPHIQUES
             # ===========================================================================
             shiny::div(class = "acc-section",
                        
                        shiny::div(class = "acc-section-title", shiny::icon("chart-area"), " Exemples"),
                        shiny::div(class = "acc-section-heading", "Types de visualisations disponibles"),
                        
                        shiny::div(class = "acc-examples-grid",
                                   
                                   # Barres
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::div(class = "mini-bar", style = "height:40%; background:#0077B6;"),
                                                         shiny::div(class = "mini-bar", style = "height:75%; background:#0077B6;"),
                                                         shiny::div(class = "mini-bar", style = "height:55%; background:#0077B6;"),
                                                         shiny::div(class = "mini-bar", style = "height:90%; background:#0096C7;"),
                                                         shiny::div(class = "mini-bar", style = "height:62%; background:#0077B6;"),
                                                         shiny::div(class = "mini-bar", style = "height:45%; background:#0077B6;")
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("chart-bar"), "Barres (empil\u00e9es / group\u00e9es / 100\u00a0%)")
                                   ),
                                   
                                   # Lignes
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$div(class = "mini-line-wrap",
                                                                         shiny::tags$svg(viewBox = "0 0 200 80", preserveAspectRatio = "none",
                                                                                         shiny::tags$polyline(
                                                                                           points = "0,65 30,50 60,55 90,30 120,38 150,18 200,25",
                                                                                           style  = "fill:none; stroke:#2E9E6B; stroke-width:2.5;"),
                                                                                         shiny::tags$polygon(
                                                                                           points = "0,65 30,50 60,55 90,30 120,38 150,18 200,25 200,80 0,80",
                                                                                           style  = "fill:rgba(46,158,107,0.12);")
                                                                         )
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("chart-line"), "Lignes + \u00e9volutions temporelles")
                                   ),
                                   
                                   # Points / Scatter
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$div(style = "position:relative; width:100%; height:80px;",
                                                                         shiny::div(class = "mini-dot", style = "left:12%; top:60%; background:#E07B39;"),
                                                                         shiny::div(class = "mini-dot", style = "left:25%; top:40%; background:#E07B39;"),
                                                                         shiny::div(class = "mini-dot", style = "left:40%; top:55%; background:#0077B6;"),
                                                                         shiny::div(class = "mini-dot", style = "left:55%; top:20%; background:#0077B6;"),
                                                                         shiny::div(class = "mini-dot", style = "left:65%; top:35%; background:#9B59B6;"),
                                                                         shiny::div(class = "mini-dot", style = "left:75%; top:50%; background:#9B59B6;"),
                                                                         shiny::div(class = "mini-dot", style = "left:85%; top:15%; background:#E07B39;"),
                                                                         shiny::div(class = "mini-dot", style = "left:90%; top:65%; background:#0077B6;")
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("circle"), "Nuage de points + r\u00e9gression")
                                   ),
                                   
                                   # Boîtes à moustaches
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$svg(viewBox = "0 0 200 80", style = "width:100%; height:80px;",
                                                                         # Box 1
                                                                         shiny::tags$line(x1="40", y1="15", x2="40", y2="65", stroke="#7FB3D3", "stroke-width"="1.5"),
                                                                         shiny::tags$rect(x="25", y="28", width="30", height="25", fill="#0077B6", "fill-opacity"=".7", rx="2"),
                                                                         shiny::tags$line(x1="25", y1="40", x2="55", y2="40", stroke="#EAF2F8", "stroke-width"="2"),
                                                                         # Box 2
                                                                         shiny::tags$line(x1="100", y1="20", x2="100", y2="70", stroke="#7FB3D3", "stroke-width"="1.5"),
                                                                         shiny::tags$rect(x="85", y="32", width="30", height="22", fill="#2E9E6B", "fill-opacity"=".7", rx="2"),
                                                                         shiny::tags$line(x1="85", y1="43", x2="115", y2="43", stroke="#EAF2F8", "stroke-width"="2"),
                                                                         # Box 3
                                                                         shiny::tags$line(x1="160", y1="10", x2="160", y2="60", stroke="#7FB3D3", "stroke-width"="1.5"),
                                                                         shiny::tags$rect(x="145", y="22", width="30", height="27", fill="#E07B39", "fill-opacity"=".7", rx="2"),
                                                                         shiny::tags$line(x1="145", y1="35", x2="175", y2="35", stroke="#EAF2F8", "stroke-width"="2")
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("box"), "Bo\u00eetes \u00e0 moustaches / Violons")
                                   ),
                                   
                                   # Camembert
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$svg(viewBox = "0 0 100 80", style = "width:100%; height:80px;",
                                                                         shiny::tags$circle(cx="50", cy="40", r="30", fill="none", stroke="#0E3A56", "stroke-width"="1"),
                                                                         shiny::tags$path(d="M50,40 L50,10 A30,30 0 0,1 76,55 Z",  fill="#0077B6"),
                                                                         shiny::tags$path(d="M50,40 L76,55 A30,30 0 0,1 30,65 Z",  fill="#2E9E6B"),
                                                                         shiny::tags$path(d="M50,40 L30,65 A30,30 0 0,1 22,27 Z",  fill="#E07B39"),
                                                                         shiny::tags$path(d="M50,40 L22,27 A30,30 0 0,1 50,10 Z",  fill="#9B59B6"),
                                                                         shiny::tags$circle(cx="50", cy="40", r="14", fill="#082030")
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("chart-pie"), "Camembert & Donut")
                                   ),
                                   
                                   # Lollipop
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$svg(viewBox = "0 0 200 80", style = "width:100%; height:80px;",
                                                                         shiny::tags$line(x1="30",  y1="75", x2="30",  y2="30", stroke="#1D4E6D", "stroke-width"="1.5"),
                                                                         shiny::tags$circle(cx="30",  cy="28", r="6", fill="#0077B6"),
                                                                         shiny::tags$line(x1="70",  y1="75", x2="70",  y2="18", stroke="#1D4E6D", "stroke-width"="1.5"),
                                                                         shiny::tags$circle(cx="70",  cy="16", r="6", fill="#0096C7"),
                                                                         shiny::tags$line(x1="110", y1="75", x2="110", y2="40", stroke="#1D4E6D", "stroke-width"="1.5"),
                                                                         shiny::tags$circle(cx="110", cy="38", r="6", fill="#0077B6"),
                                                                         shiny::tags$line(x1="150", y1="75", x2="150", y2="55", stroke="#1D4E6D", "stroke-width"="1.5"),
                                                                         shiny::tags$circle(cx="150", cy="53", r="6", fill="#2E9E6B"),
                                                                         shiny::tags$line(x1="185", y1="75", x2="185", y2="22", stroke="#1D4E6D", "stroke-width"="1.5"),
                                                                         shiny::tags$circle(cx="185", cy="20", r="6", fill="#E07B39")
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("dot-circle"), "Lollipop")
                                   ),
                                   
                                   # Histogramme
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::div(class = "mini-bar", style = "height:15%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:35%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:70%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:95%; background:#8E44AD; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:85%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:55%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:30%; background:#9B59B6; max-width:22px;"),
                                                         shiny::div(class = "mini-bar", style = "height:12%; background:#9B59B6; max-width:22px;")
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("align-left"), "Histogramme de distribution")
                                   ),
                                   
                                   # Aire
                                   shiny::div(class = "acc-example-card",
                                              shiny::div(class = "acc-example-visual",
                                                         shiny::tags$div(class = "mini-line-wrap",
                                                                         shiny::tags$svg(viewBox = "0 0 200 80", preserveAspectRatio = "none",
                                                                                         shiny::tags$polygon(
                                                                                           points = "0,75 0,55 30,42 60,48 90,28 120,35 150,15 200,22 200,75",
                                                                                           style  = "fill:rgba(0,180,216,0.25); stroke:none;"),
                                                                                         shiny::tags$polygon(
                                                                                           points = "0,75 0,65 30,58 60,62 90,50 120,52 150,45 200,48 200,75",
                                                                                           style  = "fill:rgba(46,158,107,0.25); stroke:none;"),
                                                                                         shiny::tags$polyline(
                                                                                           points = "0,55 30,42 60,48 90,28 120,35 150,15 200,22",
                                                                                           style  = "fill:none; stroke:#00B4D8; stroke-width:2;"),
                                                                                         shiny::tags$polyline(
                                                                                           points = "0,65 30,58 60,62 90,50 120,52 150,45 200,48",
                                                                                           style  = "fill:none; stroke:#2E9E6B; stroke-width:2;")
                                                                         )
                                                         )
                                              ),
                                              shiny::div(class = "acc-example-label",
                                                         shiny::icon("water"), "Aire (empil\u00e9e ou superpos\u00e9e)")
                                   )
                                   
                        )
             ),
             
             shiny::tags$hr(class = "acc-divider"),
             
             # ===========================================================================
             # FORMATS SUPPORTÉS
             # ===========================================================================
             shiny::div(class = "acc-section",
                        
                        shiny::div(class = "acc-section-title", shiny::icon("file-import"), " Import"),
                        shiny::div(class = "acc-section-heading", "Formats de fichiers support\u00e9s"),
                        
                        shiny::div(class = "acc-formats",
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-csv"),   "CSV"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-excel"), "XLSX / XLS"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-code"),  "RDS (R)"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-code"),  "JSON"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-alt"),   "TSV"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("file-alt"),   "TXT (sep ;\u00a0)"),
                                   shiny::div(class = "acc-format-pill", shiny::icon("link"),       "Donn\u00e9es nettoy\u00e9es de l\u2019app")
                        )
             ),
             
             shiny::tags$hr(class = "acc-divider"),
             
             # ===========================================================================
             # FORMULAIRE RETOURS / BUGS
             # ===========================================================================
             shiny::div(class = "acc-feedback-wrap",
                        shiny::div(class = "acc-feedback-inner",
                                   
                                   # Colonne gauche
                                   shiny::div(class = "acc-feedback-left",
                                              shiny::tags$h2("Commentaires\u00a0/\u00a0Retours\u00a0/\u00a0Bugs"),
                                              shiny::tags$p(
                                                "Une suggestion d\u2019am\u00e9lioration, un comportement inattendu,
             un type de graphique manquant\u00a0? Votre retour est pr\u00e9cieux
             pour faire \u00e9voluer la plateforme."
                                              ),
                                              shiny::div(class = "acc-feedback-contact",
                                                         shiny::icon("envelope"),
                                                         shiny::tags$span(
                                                           "Envoy\u00e9 directement \u00e0 ",
                                                           shiny::tags$strong("bdegueurce@bretagne-peches.org")
                                                         )
                                              )
                                   ),
                                   
                                   # Formulaire
                                   shiny::div(class = "acc-fb-form",
                                              
                                              # Catégories
                                              shiny::div(class = "acc-fb-cats", id = "acc_fb_cats",
                                                         shiny::div(class = "acc-fb-cat selected", id = "fbcat_suggestion",
                                                                    onclick = "accFbCat('suggestion')",
                                                                    shiny::icon("lightbulb"), "Suggestion"),
                                                         shiny::div(class = "acc-fb-cat", id = "fbcat_bug",
                                                                    onclick = "accFbCat('bug')",
                                                                    shiny::icon("bug"), "Bug"),
                                                         shiny::div(class = "acc-fb-cat", id = "fbcat_question",
                                                                    onclick = "accFbCat('question')",
                                                                    shiny::icon("question-circle"), "Question"),
                                                         shiny::div(class = "acc-fb-cat", id = "fbcat_autre",
                                                                    onclick = "accFbCat('autre')",
                                                                    shiny::icon("comment"), "Autre")
                                              ),
                                              shiny::tags$input(type = "hidden", id = "acc_fb_category", value = "suggestion"),
                                              
                                              shiny::div(class = "acc-fb-field",
                                                         shiny::tags$label("Votre nom (optionnel)"),
                                                         shiny::tags$input(type = "text", id = "acc_fb_nom",
                                                                           placeholder = "Pr\u00e9nom Nom")
                                              ),
                                              
                                              shiny::div(class = "acc-fb-field",
                                                         shiny::tags$label("Message \u2a"),
                                                         shiny::tags$textarea(id = "acc_fb_msg", rows = "5",
                                                                              placeholder = "D\u00e9crivez votre retour, suggestion ou le bug rencontr\u00e9...")
                                              ),
                                              
                                              shiny::div(class = "acc-fb-submit",
                                                         shiny::actionButton(
                                                           "acc_fb_send",
                                                           label = tagList(shiny::icon("paper-plane"), "Envoyer"),
                                                           class = "acc-fb-btn"
                                                         ),
                                                         shiny::div(class = "acc-fb-notice",
                                                                    "Aucune donn\u00e9e personnelle n\u2019est stock\u00e9e.\u00a0",
                                                                    shiny::tags$br(), "Le message est envoy\u00e9 par email uniquement."
                                                         )
                                              ),
                                              
                                              shiny::div(class = "acc-fb-success", id = "acc_fb_success",
                                                         shiny::icon("check-circle"),
                                                         "Merci\u00a0! Votre message a bien \u00e9t\u00e9 envoy\u00e9."
                                              )
                                   )
                        )
             ),
             
             
             # ===========================================================================
             # JS — catégories feedback + envoi mailto
             # ===========================================================================
             shiny::tags$script(shiny::HTML("

      /* Sélection catégorie */
      function accFbCat(cat) {
        document.querySelectorAll('.acc-fb-cat').forEach(function(el) {
          el.classList.remove('selected');
        });
        var btn = document.getElementById('fbcat_' + cat);
        if (btn) btn.classList.add('selected');
        document.getElementById('acc_fb_category').value = cat;
      }

    "))
             
  ) # fin accueil-root
)