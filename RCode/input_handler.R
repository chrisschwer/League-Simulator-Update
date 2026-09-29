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
    response <- tryCatch(
      {
        scan(file = "stdin", what = character(), nlines = 1, quiet = TRUE, sep = "\n")
      },
      error = function(e) {
        # If scan fails, return empty character
        character(0)
      }
    )

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
