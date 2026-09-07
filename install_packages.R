install.packages(c(
  "shiny", "dplyr", "ggplot2", "purrr",
  "DT", "shinyWidgets", "shinyFiles", "shinybusy", "bslib", "shinyjs",
  "data.table", "lubridate",
  "openxlsx", "plotly",
  "readr", "readxl", "jsonlite", "zip",
  "sf", "leaflet", "terra", "tidyterra",
  "viridis", "RColorBrewer", "scales",
  "emayili", "httr", "webshot"
), repos = "https://cran.r-project.org")

install.packages("remotes", repos = "https://cran.r-project.org")
remotes::install_github("smartinsightsfromdata/rpivotTable")