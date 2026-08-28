# Rendering primitives shared by the static site generator
# (RCode/generate_static_site.R). Also holds the result-loading and
# staleness helpers formerly in ShinyApp/app_helpers.R (removed when the
# Shiny app was retired, Phase 3) — generate_static_site() still needs
# stale_warning_text() for the "data is stale" banner.

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

prozent <- function (x) {
  if (!is.numeric(x)) {return (x)}
  if ((x >= .01) && (x <= .99)) {
    return (round (100 * x, digits = 0))
  } else if (x == 1) {
    return (intToUtf8(0x2713)) # Tick mark instead of 100 percent
  } else if (x == 0) {
    return (0)
  } else if (x > 0.99) {
    return (">99")
  } else if (x < 0.01) {
    return ("<1")
  }
}

groupResultsDF <- function (results,
                            labels = c("Meister", "Champions League", "Europa League",
                                       "Conference League Quali", "Mittelfeld", "Relegation", "Abstieg"),
                            groups = cbind(c(1,1), c(2,4), c(5,5),
                                           c(6,6), c(7,15), c(16,16), c(17,18))) {
  
  # groups results into a data frame of labeled groups
  # results : data frame with n probabilities for n teams
  # labels : vector of strings, labels for the groups
  # groups : 2xn matrix of integers, lower and upper bounds for groups
  
  outputDF <- data.frame (matrix(ncol=length(labels), nrow=dim(results)[1]))
  colnames (outputDF) <- labels
  rownames (outputDF) <- rownames (results)
  
  for (i in 1:length(labels)) {
    lower <- groups [1,i]
    upper <- groups [2,i]
    if (lower == upper) {
      newcol <- results[,lower]
    } else {
      range <- c(lower:upper)
      newcol <- rowSums(results[, range])
    }
    outputDF[,i] <- newcol
    
  }
  
  return (outputDF)
}
