# Universal Input Handler Module
# Provides cross-platform input functionality for both interactive and non-interactive R sessions

# Main input function that works across execution contexts
get_user_input <- function(prompt, default = NULL) {
  # Check if we're in non-interactive mode with explicit flag
  if (getOption("season_transition.non_interactive", FALSE)) {
    if (!is.null(default)) {
      cat(prompt, "[Using default:", default, "]\n")
      return(as.character(default))
    } else {
      stop("Non-interactive mode requires default values for all inputs")
    }
  }
  
  # Check if we're in an interactive R session
  if (interactive()) {
    # Standard interactive mode - use readline
    response <- readline(prompt)
    
    # Handle empty response with default
    if (trimws(response) == "" && !is.null(default)) {
      cat("Using default:", default, "\n")
      return(as.character(default))
    }
    
    return(response)
  }
  
  # Non-interactive mode (Rscript) - check if we have a terminal
  if (isatty(stdin())) {
    # We have a terminal - use scan() to read input
    cat(prompt)
    flush.console()
    
    # Use scan() to read a single line from stdin
    response <- tryCatch({
      scan(file = "stdin", what = character(), nlines = 1, quiet = TRUE, sep = "\n")
    }, error = function(e) {
      # If scan fails, return empty character
      character(0)
    })
    
    # Handle empty response
    if (length(response) == 0 || response[1] == "") {
      if (!is.null(default)) {
        cat("Using default:", default, "\n")
        return(as.character(default))
      }
      return("")
    }
    
    return(response[1])
  }
  
  # No terminal available (piped input, CI/CD, etc.)
  if (!is.null(default)) {
    cat(prompt, "[No terminal - using default:", default, "]\n")
    return(as.character(default))
  }
  
  # No terminal and no default - this is an error
  stop("Cannot read input in non-interactive, non-TTY environment without default value")
}

# Check if we can accept user input
can_accept_input <- function() {
  # Explicitly non-interactive mode
  if (getOption("season_transition.non_interactive", FALSE)) {
    return(FALSE)
  }
  
  # Interactive R session
  if (interactive()) {
    return(TRUE)
  }
  
  # Check for terminal in non-interactive mode
  return(isatty(stdin()))
}

# Safe confirmation prompt with default acceptance
confirm_action <- function(prompt, default = "y") {
  response <- get_user_input(prompt, default = default)
  
  # Normalize response
  response <- tolower(trimws(response))
  
  # Empty response uses default
  if (response == "") {
    response <- tolower(default)
  }
  
  return(response %in% c("y", "yes", "1", "true"))
}

# Get numeric input with validation
get_numeric_input <- function(prompt, default = NULL, min = NULL, max = NULL) {
  max_attempts <- 3
  attempts <- 0
  
  while (attempts < max_attempts) {
    response <- get_user_input(prompt, default = default)
    
    # Try to convert to numeric
    value <- suppressWarnings(as.numeric(response))
    
    if (!is.na(value)) {
      # Validate range if specified
      if (!is.null(min) && value < min) {
        cat("Value must be at least", min, "\n")
        attempts <- attempts + 1
        next
      }
      
      if (!is.null(max) && value > max) {
        cat("Value must be at most", max, "\n")
        attempts <- attempts + 1
        next
      }
      
      return(value)
    }
    
    cat("Invalid numeric input. Please enter a number.\n")
    attempts <- attempts + 1
  }
  
  # Max attempts reached
  if (!is.null(default)) {
    cat("Maximum attempts reached. Using default:", default, "\n")
    return(as.numeric(default))
  }
  
  stop("Failed to get valid numeric input after", max_attempts, "attempts")
}

# Get choice from a list of options
get_choice_input <- function(prompt, choices, default = NULL) {
  # Display choices
  cat(prompt, "\n")
  for (i in seq_along(choices)) {
    cat(sprintf("%d. %s\n", i, choices[i]))
  }
  
  choice_prompt <- "Enter choice (1-" %+% length(choices) %+% "): "
  
  max_attempts <- 3
  attempts <- 0
  
  while (attempts < max_attempts) {
    response <- get_user_input(choice_prompt, default = default)
    
    # Check if response is a number
    choice_num <- suppressWarnings(as.integer(response))
    
    if (!is.na(choice_num) && choice_num >= 1 && choice_num <= length(choices)) {
      return(choices[choice_num])
    }
    
    # Check if response matches a choice directly
    if (response %in% choices) {
      return(response)
    }
    
    cat("Invalid choice. Please select from the options.\n")
    attempts <- attempts + 1
  }
  
  # Max attempts reached
  if (!is.null(default)) {
    cat("Maximum attempts reached. Using default:", default, "\n")
    return(default)
  }
  
  stop("Failed to get valid choice after", max_attempts, "attempts")
}

# Helper function for string concatenation
`%+%` <- function(a, b) paste0(a, b)
