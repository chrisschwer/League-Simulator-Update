# Helper functions for the Shiny app. Kept in a separate file so they are
# unit-testable; deployed alongside app.R (see updateShiny.R appFiles).

load_results <- function(path, envir) {
  tryCatch(
    {
      load(path, envir = envir)
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
}

data_age_hours <- function(mtime, now = Sys.time()) {
  as.numeric(difftime(now, mtime, units = "hours"))
}

stale_warning_text <- function(age_hours, threshold_hours = 24) {
  if (is.na(age_hours) || age_hours <= threshold_hours) {
    return(NULL)
  }
  sprintf(
    "Achtung: Diese Prognosen sind %.0f Stunden alt und werden derzeit nicht aktualisiert.",
    age_hours
  )
}
