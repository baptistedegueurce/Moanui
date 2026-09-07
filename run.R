app_dir <- Sys.getenv("APP_DIR")

if (nchar(app_dir) == 0) app_dir <- getwd()

app_dir <- gsub("\\\\", "/", app_dir)

.libPaths(file.path(app_dir, "R-portable", "library"))

log_file <- file.path(app_dir, "crash_log.txt")

tryCatch({
  
  writeLines(c(
    
    paste("=== DÉMARRAGE", Sys.time(), "==="),
    
    paste("app_dir:", app_dir),
    
    paste("libPaths:", paste(.libPaths(), collapse=", ")),
    
    paste("Packages installés:", paste(rownames(installed.packages()), collapse=", "))
    
  ), log_file)
  
  options(shiny.port = 3838, shiny.host = "127.0.0.1")
  
  setwd(app_dir)
  
  source("global.R")
  
  shiny::runApp(
    
    shinyApp(ui = ui_main(), server = server_main),
    
    port = 3838,
    
    host = "127.0.0.1",
    
    launch.browser = FALSE
    
  )
  
}, error = function(e) {
  
  write(paste("ERREUR:", conditionMessage(e)), log_file, append = TRUE)
  
  write(paste(capture.output(traceback()), collapse="\n"), log_file, append = TRUE)
  
})
