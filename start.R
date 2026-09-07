library(shiny)

source("global.R")

shinyApp(
  ui = ui_main(),
  server = server_main
)
