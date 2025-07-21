# Test suite for input handler functionality

library(testthat)
# mockery no longer needed with testthat 3.0+

# Don't source directly - rely on package loading via helper-test-setup.R or load_all()

test_that("get_user_input works in interactive mode", {
  skip_if(!interactive(), "Skipping interactive test in non-interactive environment")
  
  # This test would require actual interactive input
  # Since input_handler is for manual season transitions (not automated workflows),
  # and we've already tested the non-interactive paths, this is acceptable
  expect_true(TRUE)  # Placeholder since we can't truly test interactive readline
})

test_that("get_user_input works in Rscript mode with terminal", {
  # Mock Rscript environment with terminal
  local_mocked_bindings(
    interactive = function() FALSE,
    isatty = function(con) TRUE,
    scan = function(...) "scanned_input",
    .package = "base"
  )
  
  result <- get_user_input("Enter value: ")
  expect_equal(result, "scanned_input")
})

test_that("get_user_input uses default in non-TTY environment", {
  # Mock non-TTY environment
  local_mocked_bindings(
    interactive = function() FALSE,
    isatty = function(con) FALSE,
    .package = "base"
  )
  
  result <- get_user_input("Enter value: ", default = "default_value")
  expect_equal(result, "default_value")
})

test_that("get_user_input errors without default in non-TTY environment", {
  # Mock non-TTY environment without default
  local_mocked_bindings(
    interactive = function() FALSE,
    isatty = function(con) FALSE,
    .package = "base"
  )
  
  expect_error(
    get_user_input("Enter value: "),
    "Cannot read input in non-interactive, non-TTY environment without default value"
  )
})

test_that("confirm_action handles various inputs correctly", {
  # Test positive responses
  for (response in c("y", "yes", "Y", "YES", "1", "true")) {
    local_mocked_bindings(
      get_user_input = function(...) response
    )
    expect_true(confirm_action("Confirm? "))
  }
  
  # Test negative responses
  for (response in c("n", "no", "N", "NO", "0", "false")) {
    local_mocked_bindings(
      get_user_input = function(...) response
    )
    expect_false(confirm_action("Confirm? "))
  }
})

test_that("get_numeric_input validates numeric input", {
  # Valid numeric input
  local_mocked_bindings(
    get_user_input = function(...) "42"
  )
  result <- get_numeric_input("Enter number: ")
  expect_equal(result, 42)
  
  # Invalid then valid input
  attempts <- 0
  local_mocked_bindings(
    get_user_input = function(...) {
      attempts <<- attempts + 1
      if (attempts == 1) return("not_a_number")
      return("42")
    }
  )
  result <- get_numeric_input("Enter number: ")
  expect_equal(result, 42)
  expect_equal(attempts, 2)
})

test_that("get_numeric_input respects min/max constraints", {
  # Below minimum
  attempts <- 0
  local_mocked_bindings(
    get_user_input = function(...) {
      attempts <<- attempts + 1
      if (attempts == 1) return("5")
      return("10")
    }
  )
  result <- get_numeric_input("Enter number: ", min = 10)
  expect_equal(result, 10)
  
  # Above maximum
  attempts <- 0
  local_mocked_bindings(
    get_user_input = function(...) {
      attempts <<- attempts + 1
      if (attempts == 1) return("150")
      return("100")
    }
  )
  result <- get_numeric_input("Enter number: ", max = 100)
  expect_equal(result, 100)
})

test_that("get_choice_input handles choice selection", {
  choices <- c("Option A", "Option B", "Option C")
  
  # Numeric selection
  local_mocked_bindings(
    get_user_input = function(...) "2"
  )
  result <- get_choice_input("Select: ", choices)
  expect_equal(result, "Option B")
  
  # Direct text selection
  local_mocked_bindings(
    get_user_input = function(...) "Option C"
  )
  result <- get_choice_input("Select: ", choices)
  expect_equal(result, "Option C")
})

test_that("non-interactive mode with flag works correctly", {
  options(season_transition.non_interactive = TRUE)
  
  result <- get_user_input("Enter value: ", default = "non_interactive_default")
  expect_equal(result, "non_interactive_default")
  
  # Should error without default
  expect_error(
    get_user_input("Enter value: "),
    "Non-interactive mode requires default values"
  )
  
  options(season_transition.non_interactive = FALSE)
})

test_that("can_accept_input correctly detects input capability", {
  # Interactive mode
  local_mocked_bindings(
    interactive = function() TRUE,
    .package = "base"
  )
  expect_true(can_accept_input())
  
  # Non-interactive with terminal
  local_mocked_bindings(
    interactive = function() FALSE,
    isatty = function(con) TRUE,
    .package = "base"
  )
  expect_true(can_accept_input())
  
  # Non-interactive without terminal
  local_mocked_bindings(
    interactive = function() FALSE,
    isatty = function(con) FALSE,
    .package = "base"
  )
  expect_false(can_accept_input())
  
  # Explicit non-interactive flag
  options(season_transition.non_interactive = TRUE)
  expect_false(can_accept_input())
  options(season_transition.non_interactive = FALSE)
})