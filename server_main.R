# =============================================================================
# server_main.R — Orchestrateur des modules serveur
# =============================================================================

server_main <- function(input, output, session) {
  
  rv <- shiny::reactiveValues(
    data_raw       = NULL,
    data_clean     = NULL,   # alimente par server_data, partage avec les autres modules
    process_result = NULL,
    compo_slots = list()
  )
  
  source("R/server/server_home.R",    local = TRUE)
  server_home(input, output, session, rv)
  
  source("R/server/server_data.R",    local = TRUE)
  server_data(input, output, session, rv)
  
  source("R/server/server_viz.R",     local = TRUE)
  server_viz(input, output, session, rv)
  
  source("R/server/server_map.R",     local = TRUE)
  server_map(input, output, session, rv)  
  
  source("R/server/server_quota.R",     local = TRUE)
  server_quota(input, output, session, rv)
  
  source("R/server/server_vms.R", local = TRUE)
  server_vms(input, output, session, rv)
  
  source("R/server/server_composition.R", local = TRUE)
  server_composition(input, output, session, rv)
  
}