#' Wrapper Functions for C++ Function Output Transformation
#' 
#' These wrapper functions transform C++ function outputs to match test expectations
#' without modifying the underlying C++ code. This maintains backward compatibility
#' while allowing tests to pass.
#' 
#' Created to resolve issue #40: Fix C++ Function API Mismatches (37 failing tests)
#' 
#' @author Claude
#' @date 2025-07-20

#' simulationsCPP_wrapper
#' 
#' Transforms simulationsCPP output from 6-column matrix to 4-column matrix
#' with named columns to match test expectations.
#' 
#' @param ... All parameters passed through to simulationsCPP
#' @return 4-column matrix with columns: Team, Points, GoalDiff, GoalsScored
#' 
simulationsCPP_wrapper <- function(...) {
  # Call original function
  result <- simulationsCPP(...)
  
  # Transform 6-column matrix to 4-column matrix
  # Original columns: [team_number, rank, goals_for, goals_against, goal_diff, points]
  # New columns: [Team, Points, GoalDiff, GoalsScored]
  transformed <- result[, c(1, 6, 5, 3)]
  
  # Add column names
  colnames(transformed) <- c("Team", "Points", "GoalDiff", "GoalsScored")
  
  return(transformed)
}

#' SpielCPP_wrapper
#' 
#' Transforms SpielCPP output from unnamed numeric vector to named list
#' to match test expectations.
#' 
#' @param ... All parameters passed through to SpielCPP
#' @return Named list with elements: ELOHeim, ELOGast, ToreHeim, ToreGast
#' 
SpielCPP_wrapper <- function(...) {
  # Call original function
  result <- SpielCPP(...)
  
  # Transform to named list (taking first 4 elements, ignoring ELOProb)
  wrapped <- list(
    ELOHeim = result[1],
    ELOGast = result[2],
    ToreHeim = result[3],
    ToreGast = result[4]
  )
  
  return(wrapped)
}

#' SpielNichtSimulieren_wrapper
#' 
#' Transforms SpielNichtSimulieren output from unnamed numeric vector to named list
#' to match test expectations.
#' 
#' @param ... All parameters passed through to SpielNichtSimulieren
#' @return Named list with elements: ELOHeim, ELOGast, ToreHeim, ToreGast
#' 
SpielNichtSimulieren_wrapper <- function(...) {
  # Call original function
  result <- SpielNichtSimulieren(...)
  
  # Transform to named list (taking first 4 elements, ignoring ELOProb)
  wrapped <- list(
    ELOHeim = result[1],
    ELOGast = result[2],
    ToreHeim = result[3],
    ToreGast = result[4]
  )
  
  return(wrapped)
}