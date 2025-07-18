# Test suite for interactive prompts with fix for infinite loop

library(testthat)
library(mockery)

# Source the modules (adjust paths as needed)
source("../../RCode/input_handler.R")
source("../../RCode/interactive_prompts.R")

# Mock helper functions that might not be available
get_league_name <- function(league) {
  switch(league,
    "78" = "Bundesliga",
    "79" = "2. Bundesliga", 
    "80" = "3. Liga",
    league
  )
}

get_team_short_name <- function(team_name) {
  # Simple implementation for testing
  toupper(substr(gsub("[^A-Za-z]", "", team_name), 1, 3))
}

detect_second_teams <- function(team_name) {
  grepl(" II$| 2$", team_name)
}

convert_second_team_short_name <- function(short_name, is_second, promotion_value) {
  if (is_second && promotion_value == -50) {
    # Convert last character to "2"
    paste0(substr(short_name, 1, 2), "2")
  } else {
    short_name
  }
}

get_initial_elo_for_new_team <- function(league) {
  switch(league,
    "78" = 1300,
    "79" = 1150,
    "80" = 1046,
    1000
  )
}

validate_team_short_name <- function(short_name) {
  if (nchar(short_name) != 3) {
    return(list(valid = FALSE, message = "Must be exactly 3 characters"))
  }
  if (short_name != toupper(short_name)) {
    return(list(valid = FALSE, message = "Must be uppercase"))
  }
  if (grepl("[^A-Z0-9]", short_name)) {
    return(list(valid = FALSE, message = "Only letters and numbers allowed"))
  }
  list(valid = TRUE, message = "Valid")
}

validate_elo_input <- function(elo) {
  if (is.na(elo) || elo < 0 || elo > 3000) {
    return(list(valid = FALSE, message = "ELO must be between 0 and 3000"))
  }
  list(valid = TRUE, message = "Valid")
}

test_that("prompt_for_team_info accepts valid input", {
  # Mock user inputs
  mock_inputs <- list("ENE", "1046", "y")
  input_index <- 0
  
  with_mock(
    get_user_input = function(prompt, ...) {
      input_index <<- input_index + 1
      mock_inputs[[input_index]]
    },
    can_accept_input = function() TRUE,
    confirm_action = function(...) TRUE,
    {
      result <- prompt_for_team_info("Energie Cottbus", "80")
      
      expect_equal(result$name, "Energie Cottbus")
      expect_equal(result$short_name, "ENE")
      expect_equal(result$initial_elo, 1046)
      expect_equal(result$promotion_value, 0)
    }
  )
})

test_that("prompt_for_team_info retries when user says no", {
  # First attempt: user says no, second attempt: user says yes
  attempt <- 0
  
  with_mock(
    get_user_input = function(prompt, default = NULL) {
      if (grepl("short name", prompt)) return("ENE")
      if (grepl("ELO", prompt)) return(default)  # Use default
      return("y")
    },
    can_accept_input = function() TRUE,
    confirm_action = function(...) {
      attempt <<- attempt + 1
      return(attempt > 1)  # First time no, second time yes
    },
    {
      result <- prompt_for_team_info("Energie Cottbus", "80")
      
      expect_equal(result$short_name, "ENE")
      expect_equal(attempt, 2)  # Should have tried twice
    }
  )
})

test_that("prompt_for_team_info prevents infinite loops", {
  # Always say no to trigger retry limit
  with_mock(
    get_user_input = function(prompt, default = NULL) {
      if (grepl("short name", prompt)) return("ENE")
      if (grepl("ELO", prompt)) return(default)
      return("n")
    },
    can_accept_input = function() TRUE,
    confirm_action = function(...) FALSE,
    {
      expect_error(
        prompt_for_team_info("Test Team", "80"),
        "Maximum retry limit reached"
      )
    }
  )
})

test_that("prompt_for_team_info handles empty confirmation gracefully", {
  mock_inputs <- list("ENE", "", "")  # Empty ELO and confirmation
  input_index <- 0
  
  with_mock(
    get_user_input = function(prompt, default = NULL) {
      input_index <<- input_index + 1
      if (!is.null(default) && mock_inputs[[input_index]] == "") {
        return(default)
      }
      mock_inputs[[input_index]]
    },
    can_accept_input = function() TRUE,
    confirm_action = function(...) TRUE,  # Empty treated as yes
    {
      result <- prompt_for_team_info("Energie Cottbus", "80")
      
      # Should accept defaults
      expect_equal(result$short_name, "ENE")
      expect_equal(result$initial_elo, 1046)  # Default for Liga 3
    }
  )
})

test_that("second team detection and conversion works", {
  with_mock(
    get_user_input = function(prompt, default = NULL) {
      if (grepl("short name", prompt)) return("BAY")
      if (grepl("ELO", prompt)) return(default)
      if (grepl("second team", prompt)) return("y")
      return("y")
    },
    can_accept_input = function() TRUE,
    confirm_action = function(...) TRUE,
    {
      result <- prompt_for_team_info("Bayern Munich II", "80")
      
      expect_equal(result$promotion_value, -50)
      expect_equal(result$short_name, "BA2")  # Converted to second team format
    }
  )
})

test_that("non-interactive mode uses defaults", {
  options(season_transition.non_interactive = TRUE)
  
  with_mock(
    can_accept_input = function() FALSE,
    check_interactive_mode = function() FALSE,
    {
      result <- prompt_for_team_info("Energie Cottbus", "80")
      
      expect_equal(result$short_name, "ENE")
      expect_equal(result$initial_elo, 1046)
    }
  )
  
  options(season_transition.non_interactive = FALSE)
})

test_that("get_team_short_name_interactive validates format", {
  attempts <- 0
  
  with_mock(
    check_interactive_mode = function() TRUE,
    get_user_input = function(...) {
      attempts <<- attempts + 1
      if (attempts == 1) return("ab")   # Too short
      if (attempts == 2) return("abcd") # Too long
      if (attempts == 3) return("ab!")  # Invalid char
      return("ABC")  # Valid
    },
    {
      result <- get_team_short_name_interactive("Test Team")
      expect_equal(result, "ABC")
      expect_equal(attempts, 4)
    }
  )
})

test_that("get_initial_elo_interactive validates range", {
  attempts <- 0
  
  with_mock(
    check_interactive_mode = function() TRUE,
    get_user_input = function(...) {
      attempts <<- attempts + 1
      if (attempts == 1) return("-100")  # Negative
      if (attempts == 2) return("5000")  # Too high
      if (attempts == 3) return("abc")   # Not numeric
      return("1200")  # Valid
    },
    {
      result <- get_initial_elo_interactive("78")
      expect_equal(result, 1200)
      expect_equal(attempts, 4)
    }
  )
})

test_that("confirm_overwrite respects user choice", {
  # Test yes
  with_mock(
    check_interactive_mode = function() TRUE,
    get_user_input = function(...) "y",
    {
      expect_true(confirm_overwrite("test.csv"))
    }
  )
  
  # Test no
  with_mock(
    check_interactive_mode = function() TRUE,
    get_user_input = function(...) "n",
    {
      expect_false(confirm_overwrite("test.csv"))
    }
  )
  
  # Non-interactive mode
  with_mock(
    check_interactive_mode = function() FALSE,
    {
      expect_false(confirm_overwrite("test.csv"))
    }
  )
})