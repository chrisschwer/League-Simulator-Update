# Test suite for interactive prompts with fix for infinite loop

library(testthat)
library(mockery)

# Source the modules (adjust paths as needed)
source("../../RCode/input_handler.R")
# validate_team_short_name()/validate_elo_input() leben seit #209 in
# interactive_prompts.R (vormals input_validation.R).
source("../../RCode/interactive_prompts.R")

test_that("prompt_for_team_info accepts valid input", {
  # Stub the direct collaborators of prompt_for_team_info so its own
  # orchestration logic (wiring collaborator outputs into the result,
  # honoring the confirmation) is what's under test.
  stub(prompt_for_team_info, "get_team_short_name_interactive", function(...) "ENE")
  stub(prompt_for_team_info, "get_initial_elo_interactive", function(...) 1046)
  stub(prompt_for_team_info, "get_promotion_value_interactive", function(...) 0)
  stub(prompt_for_team_info, "can_accept_input", TRUE)
  stub(prompt_for_team_info, "confirm_action", TRUE)

  result <- prompt_for_team_info("Energie Cottbus", "80")

  expect_equal(result$name, "Energie Cottbus")
  expect_equal(result$short_name, "ENE")
  expect_equal(result$initial_elo, 1046)
  expect_equal(result$promotion_value, 0)
})

test_that("prompt_for_team_info retries when user says no", {
  # Die Rekursion in prompt_for_team_info() loest sich lexikalisch ueber den
  # globalen Namen auf -- eine normale stub()-Kopie fuer einen Mitspieler
  # griffe deshalb nur beim ersten Aufruf. Der Selbstaufruf muss darum
  # selbst gestubbt werden (der Trick, der bisher an "Mocking issues"
  # scheiterte).
  retry_mock <- mock("ZWEITE-RUNDE")
  stub(prompt_for_team_info, "prompt_for_team_info", retry_mock)
  stub(prompt_for_team_info, "get_team_short_name_interactive", function(...) "ENE")
  stub(prompt_for_team_info, "get_initial_elo_interactive", function(...) 1100)
  stub(prompt_for_team_info, "get_promotion_value_interactive", function(...) 0)
  stub(prompt_for_team_info, "can_accept_input", TRUE)
  stub(prompt_for_team_info, "confirm_action", FALSE)

  result <- prompt_for_team_info("Energie Cottbus", "80", c("AAA"), 1100)

  # Genau eine Wiederholung, mit allen Argumenten durchgereicht und
  # retry_count + 1.
  expect_called(retry_mock, 1)
  expect_equal(mock_args(retry_mock)[[1]],
              list("Energie Cottbus", "80", c("AAA"), 1100, 1))
  expect_equal(result, "ZWEITE-RUNDE")
})

test_that("prompt_for_team_info prevents infinite loops", {
  # prompt_for_team_info recurses into itself on retry. mockery::stub()
  # cannot express this: the stubbed copy it returns has collaborator
  # names rebound in a *new* child environment, but the function's own
  # recursive self-call is resolved by name through the lexical parent
  # chain, which still finds the original, unstubbed
  # prompt_for_team_info in globalenv - so the stubs would only apply to
  # the first call, not the retries actually under test here. Fall back
  # to plain reassignment of the collaborators with an on.exit restore.
  old_get_team_short_name_interactive <- get_team_short_name_interactive
  old_get_initial_elo_interactive <- get_initial_elo_interactive
  old_can_accept_input <- can_accept_input
  old_confirm_action <- confirm_action
  on.exit({
    get_team_short_name_interactive <<- old_get_team_short_name_interactive
    get_initial_elo_interactive <<- old_get_initial_elo_interactive
    can_accept_input <<- old_can_accept_input
    confirm_action <<- old_confirm_action
  }, add = TRUE)

  get_team_short_name_interactive <<- function(...) "ENE"
  get_initial_elo_interactive <<- function(...) 1046
  can_accept_input <<- function() TRUE
  confirm_action <<- function(...) FALSE

  expect_error(
    prompt_for_team_info("Test Team", "80"),
    "Maximum retry limit reached"
  )
})

test_that("prompt_for_team_info handles empty confirmation gracefully", {
  # Empty ELO input falls back to the default; empty confirmation is
  # treated as yes. Beide Pfade laufen durch die ECHTE Logik von
  # get_initial_elo_interactive() bzw. confirm_action() -- nur ihre
  # jeweiligen Blaetter (check_interactive_mode, get_user_input) sind
  # gestubbt, ueber gestubbte KOPIEN statt einer globalen Umschreibung:
  # stub(get_initial_elo_interactive, ...) direkt wuerde die globale
  # Funktion ersetzen und in spaetere Tests durchsickern; die vorherige
  # Fassung stubte confirm_action pauschal auf TRUE und pruefte die "leere
  # Bestaetigung" damit gar nicht.
  elo <- get_initial_elo_interactive
  stub(elo, "check_interactive_mode", TRUE)
  stub(elo, "get_user_input", function(prompt, default = NULL) "")

  bestaetigen <- confirm_action
  stub(bestaetigen, "get_user_input", function(prompt, default = NULL) "")

  stub(prompt_for_team_info, "get_team_short_name_interactive", function(...) "ENE")
  stub(prompt_for_team_info, "get_initial_elo_interactive", elo)
  stub(prompt_for_team_info, "can_accept_input", TRUE)
  stub(prompt_for_team_info, "confirm_action", bestaetigen)

  result <- prompt_for_team_info("Energie Cottbus", "80")

  # Should accept defaults
  expect_equal(result$short_name, "ENE")
  expect_equal(result$initial_elo, 1046) # Default for Liga 3
})

test_that("second team detection and conversion works", {
  # get_user_input sitzt eine Ebene unter prompt_for_team_info, in
  # get_promotion_value_interactive(). Statt get_promotion_value_interactive
  # selbst zu stubben (und damit seine echte Logik -- detect_second_teams(),
  # das y/n -50/0 -- zu umgehen), laeuft hier eine gestubbte KOPIE davon:
  # nur ihre Blaetter (check_interactive_mode, get_user_input) sind
  # gestubbt, die Kopie wird als Mitspieler untergeschoben.
  pv_ja <- get_promotion_value_interactive
  stub(pv_ja, "check_interactive_mode", TRUE)
  stub(pv_ja, "get_user_input", "y")

  stub(prompt_for_team_info, "get_promotion_value_interactive", pv_ja)
  stub(prompt_for_team_info, "get_team_short_name_interactive", function(...) "BAY")
  stub(prompt_for_team_info, "get_initial_elo_interactive", function(...) 1046)
  stub(prompt_for_team_info, "can_accept_input", TRUE)
  stub(prompt_for_team_info, "confirm_action", TRUE)

  result <- prompt_for_team_info("Bayern Munich II", "80")

  expect_equal(result$promotion_value, -50)
  expect_equal(result$short_name, "BA2") # convert_second_team_short_name()

  # Gegenprobe: "n" -> keine Zweitmannschafts-Konvertierung.
  pv_nein <- get_promotion_value_interactive
  stub(pv_nein, "check_interactive_mode", TRUE)
  stub(pv_nein, "get_user_input", "n")
  stub(prompt_for_team_info, "get_promotion_value_interactive", pv_nein)

  result2 <- prompt_for_team_info("Bayern Munich II", "80")

  expect_equal(result2$promotion_value, 0)
  expect_equal(result2$short_name, "BAY")
})

test_that("non-interactive mode uses defaults", {
  withr::local_options(season_transition.non_interactive = TRUE)

  # season_transition.non_interactive = TRUE above already makes the real
  # check_interactive_mode() return FALSE, so only can_accept_input (a
  # direct collaborator of prompt_for_team_info) needs stubbing here.
  stub(prompt_for_team_info, "can_accept_input", FALSE)

  result <- prompt_for_team_info("Energie Cottbus", "80")

  expect_equal(result$short_name, "ENE")
  expect_equal(result$initial_elo, 1046)
})

test_that("get_team_short_name_interactive validates format", {
  attempts <- 0

  stub(get_team_short_name_interactive, "check_interactive_mode", TRUE)
  stub(get_team_short_name_interactive, "get_user_input", function(...) {
    attempts <<- attempts + 1
    if (attempts == 1) return("a")     # Too short (1 char)
    if (attempts == 2) return("abcde") # Too long (5 chars)
    if (attempts == 3) return("ab!")   # Invalid char
    if (attempts == 4) return("abcd")  # 4 chars but doesn't end in 2
    return("AB")  # Valid (2 chars)
  })

  result <- get_team_short_name_interactive("Test Team")
  expect_equal(result, "AB")
  expect_equal(attempts, 5)
})

test_that("get_initial_elo_interactive validates range", {
  attempts <- 0

  stub(get_initial_elo_interactive, "check_interactive_mode", TRUE)
  stub(get_initial_elo_interactive, "get_user_input", function(...) {
    attempts <<- attempts + 1
    if (attempts == 1) return("-100")  # Negative
    if (attempts == 2) return("5000")  # Too high
    if (attempts == 3) return("abc")   # Not numeric
    return("1200")  # Valid
  })

  result <- get_initial_elo_interactive("78")
  expect_equal(result, 1200)
  expect_equal(attempts, 4)
})

test_that("get_initial_elo_interactive uses baseline for Liga3", {
  # Test with baseline
  stub(get_initial_elo_interactive, "check_interactive_mode", FALSE)
  elo <- get_initial_elo_interactive("80", baseline = 1234)
  expect_equal(elo, 1234)

  # Test without baseline (should use default)
  stub(get_initial_elo_interactive, "check_interactive_mode", FALSE)
  elo <- get_initial_elo_interactive("80", baseline = NULL)
  expect_equal(elo, 1046)

  # Test other leagues ignore baseline
  stub(get_initial_elo_interactive, "check_interactive_mode", FALSE)
  elo <- get_initial_elo_interactive("78", baseline = 1234)
  expect_equal(elo, 1500) # Should use default for Bundesliga, not baseline
})

test_that("prompt_for_team_info passes baseline through", {
  # Stub all direct collaborators
  stub(prompt_for_team_info, "get_team_short_name_interactive", function(...) "FCE")
  stub(prompt_for_team_info, "get_initial_elo_interactive", function(league, baseline = NULL) {
    if (!is.null(baseline) && league == "80") return(baseline)
    return(1046)
  })
  stub(prompt_for_team_info, "get_promotion_value_interactive", function(...) 0)
  stub(prompt_for_team_info, "can_accept_input", FALSE) # Skip confirmation

  # Test with baseline
  result <- prompt_for_team_info("Energie Cottbus", "80", NULL, baseline = 1150)

  expect_equal(result$initial_elo, 1150)
  expect_equal(result$short_name, "FCE")
})

test_that("confirm_overwrite respects user choice", {
  # Test yes
  stub(confirm_overwrite, "check_interactive_mode", TRUE)
  stub(confirm_overwrite, "get_user_input", "y")
  expect_true(confirm_overwrite("test.csv"))

  # Test no
  stub(confirm_overwrite, "check_interactive_mode", TRUE)
  stub(confirm_overwrite, "get_user_input", "n")
  expect_false(confirm_overwrite("test.csv"))

  # Non-interactive mode
  stub(confirm_overwrite, "check_interactive_mode", FALSE)
  expect_true(confirm_overwrite("test.csv")) # Non-interactive allows overwrite
})
