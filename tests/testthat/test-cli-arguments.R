# Test file for CLI argument parsing

# Source the parse_arguments function from season_transition.R
# Extract just the function we need to avoid running the main script
parse_args_code <- readLines("../../scripts/season_transition.R")
func_start <- which(grepl("^parse_arguments", parse_args_code))
func_end <- which(grepl("^\\}", parse_args_code) & seq_along(parse_args_code) > func_start)[1]
eval(parse(text = parse_args_code[func_start:func_end]))

test_that("parse_arguments correctly handles season arguments", {
  # Test basic season arguments
  args <- parse_arguments(c("2024", "2025"))
  expect_true(args$valid)
  expect_equal(args$from_season, "2024")
  expect_equal(args$to_season, "2025")
  expect_false(args$non_interactive)
  expect_true(args$interactive_mode)
})

test_that("parse_arguments handles --non-interactive flag", {
  # Test with --non-interactive flag
  args <- parse_arguments(c("2024", "2025", "--non-interactive"))
  expect_true(args$valid)
  expect_equal(args$from_season, "2024")
  expect_equal(args$to_season, "2025")
  expect_true(args$non_interactive)
  expect_false(args$interactive_mode)
})

test_that("parse_arguments handles -n shorthand flag", {
  # Test with -n flag
  args <- parse_arguments(c("2024", "2025", "-n"))
  expect_true(args$valid)
  expect_equal(args$from_season, "2024")
  expect_equal(args$to_season, "2025")
  expect_true(args$non_interactive)
  expect_false(args$interactive_mode)
})

test_that("parse_arguments rejects invalid argument counts", {
  # Test with too few arguments
  args <- parse_arguments(c("2024"))
  expect_false(args$valid)
  
  # Test with too many arguments (without flag)
  args <- parse_arguments(c("2023", "2024", "2025"))
  expect_false(args$valid)
})

test_that("parse_arguments handles flag in different positions", {
  # Flag before seasons
  args <- parse_arguments(c("--non-interactive", "2024", "2025"))
  expect_true(args$valid)
  expect_equal(args$from_season, "2024")
  expect_equal(args$to_season, "2025")
  expect_true(args$non_interactive)
  
  # Flag between seasons
  args <- parse_arguments(c("2024", "--non-interactive", "2025"))
  expect_true(args$valid)
  expect_equal(args$from_season, "2024")
  expect_equal(args$to_season, "2025")
  expect_true(args$non_interactive)
})