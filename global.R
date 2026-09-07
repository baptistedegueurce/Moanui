# =========================
# PACKAGES
# =========================

library(shiny)
library(dplyr)
library(ggplot2)
library(purrr)       # pour resumer_donnees() dans functions_data

# UI
library(DT)
library(shinyWidgets)
library(shinyFiles)
library(shinybusy)
library(bslib)
library(shinyjs)

# Data
library(data.table)
library(lubridate)

# Export
library(openxlsx)
library(plotly)
library(rpivotTable)
library(readr); library(readxl); library(jsonlite)
library(emayili)
library(shinyjs)
library(httr)
library(jsonlite)
library(sf)
library(leaflet)
library(viridis)
library(RColorBrewer)
library(scales)

library(sf)       # croisement spatial
library(terra)    # rasters SHOM
library(tidyterra) # geom_spatraster_rgb pour le fond de carte
library(zip)      # export ZIP
library(ggplot2)
library(dplyr)
library(webshot)
library(patchwork)

library(rnaturalearth)   # cartes quota + map
library(base64enc)       # server_composition
library(stringi)         # functions_quota
library(webshot2)        # functions_viz (en plus de webshot)
library(htmlwidgets)     # export widgets
# Source functions
source("R/functions/functions_shared_ui.R")  # composants UI partagés
source("R/functions/functions_home.R")
source("R/functions/functions_data.R")  
source("R/functions/functions_viz.R")
source("R/functions/functions_map.R")
source("R/functions/functions_context_layers.R")  # couches de contexte cartographique
source("R/functions/functions_quota.R")


source("R/server/server_main.R")
source("R/ui/ui_main.R")

options(shiny.maxRequestSize = 500 * 1024^2)