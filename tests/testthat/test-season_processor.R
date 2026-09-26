# Test suite for season processor functionality

library(testthat)
library(mockery)

# Source required files directly - the helper seems to not be working in test context
source("../../RCode/season_processor.R")
source("../../RCode/team_data_carryover.R")

context("Season Processor - Team Data Carryover")

test_that("process_league_teams carries over ShortText from previous season", {
  # Setup: Create mock previous season data
  prev_season_data <- data.frame(
    TeamID = c(168, 167, 165),
    ShortText = c("B04", "HOF", "BVB"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1765, 1628, 1885),
    stringsAsFactors = FALSE
  )
  
  # Mock API response with same teams
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE),
    list(id = 167, name = "Hoffenheim", is_second_team = FALSE),
    list(id = 165, name = "Borussia Dortmund", is_second_team = FALSE)
  )
  
  # Mock final ELOs
  final_elos <- data.frame(
    TeamID = c(168, 167, 165),
    FinalELO = c(1800, 1650, 1900)
  )
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Extract short names from result
  short_names <- sapply(result, function(t) t$short_name)
  team_ids <- sapply(result, function(t) t$id)
  
  # Assertions
  expect_equal(short_names[team_ids == 168], "B04")
  expect_equal(short_names[team_ids == 167], "HOF")
  expect_equal(short_names[team_ids == 165], "BVB")
})

test_that("process_league_teams generates ShortText only for new teams", {
  # Setup: Previous season has teams 168, 167
  prev_season_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628),
    stringsAsFactors = FALSE
  )
  
  # API returns existing teams plus new team 1320
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE),
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)  # New team
  )
  
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1800)
  )
  
  # Mock prompt_for_team_info to return FCE for new team
  mock_prompt <- mock(list(short_name = "FCE", initial_elo = 1100, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Extract data
  short_names <- sapply(result, function(t) t$short_name)
  team_ids <- sapply(result, function(t) t$id)
  
  # Assertions
  expect_equal(short_names[team_ids == 168], "B04")  # Existing
  expect_equal(short_names[team_ids == 1320], "FCE") # New
  
  # Verify prompt was called only for new team
  expect_called(mock_prompt, 1)
})

test_that("process_league_teams uses final ELO for existing teams", {
  # Setup
  prev_season_data <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),  # Initial ELO from previous season start
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  )
  
  # Final ELO after all matches
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1823)  # Different from initial
  )
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Assertions
  expect_equal(result[[1]]$initial_elo, 1823)  # Should use final ELO, not 1765
})

context("Season Processor - ELO Baseline Passing")

test_that("Liga3 baseline is passed to prompt_for_team_info", {
  # Setup
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  final_elos <- data.frame(TeamID = numeric(), FinalELO = numeric())
  
  # Mock prompt function to capture baseline
  captured_baseline <- NULL
  mock_prompt <- mock(
    list(short_name = "FCE", initial_elo = 1234, promotion_value = 0),
    cycle = TRUE
  )
  
  stub(process_league_teams, "prompt_for_team_info", function(name, league, existing, baseline) {
    captured_baseline <<- baseline
    mock_prompt()
  })
  
  # Test with baseline 1234
  process_league_teams(api_teams, "80", "2025", final_elos, 1234, NULL)
  
  # Assertions
  expect_equal(captured_baseline, 1234)
})

context("Season Processor - Season Validation")

test_that("process_single_season validates previous season completion", {
  # Mock validation to return FALSE
  stub(process_single_season, "validate_season_completion", FALSE)
  
  # Test - process_single_season returns a list with success = FALSE on error
  result <- process_single_season("2025", "2024")
  
  expect_false(result$success)
  expect_equal(result$error, "Season 2024 not finished, no season transition possible.")
})

context("Team Data Carryover Module")

test_that("load_previous_team_list loads valid team data", {
  # Create temporary test file
  test_dir <- tempdir()
  test_file <- file.path(test_dir, "RCode", "TeamList_2024.csv")
  dir.create(file.path(test_dir, "RCode"), recursive = TRUE, showWarnings = FALSE)
  
  # Write test data
  test_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock file path
  stub(load_previous_team_list, "paste0", function(...) test_file)
  stub(load_previous_team_list, "safe_file_read", function(path, ...) test_data)
  
  # Test
  result <- load_previous_team_list("2024")
  
  # Assertions
  expect_equal(nrow(result), 2)
  expect_equal(result$ShortText[1], "B04")
  
  # Cleanup
  unlink(file.path(test_dir, "RCode"), recursive = TRUE)
})

test_that("get_existing_team_data returns correct team info", {
  # Setup
  prev_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, -50),
    stringsAsFactors = FALSE
  )
  
  # Test existing team
  result <- get_existing_team_data(168, prev_data)
  expect_equal(result$short_name, "B04")
  expect_equal(result$promotion_value, 0)
  
  # Test second team
  result <- get_existing_team_data(167, prev_data)
  expect_equal(result$short_name, "HOF")
  expect_equal(result$promotion_value, -50)
  
  # Test non-existing team
  result <- get_existing_team_data(999, prev_data)
  expect_null(result)
})

# ENTFERNT (Issue #195): Hier standen zwei Tests fuer
# validate_short_name_uniqueness() und ensure_unique_short_names().
#
# Beide Funktionen sind mit diesem PR geloescht. ensure_unique_short_names()
# hatte keinen einzigen Produktivaufrufer -- nur diesen Test -- und er
# nagelte mit expect_match(short_names[2], "B0[0-9]") ausgerechnet die
# STILLE UMBENENNUNG als Sollverhalten fest. Genau die widerspricht dem
# Kuerzel-Vertrag (ADR 0007): Eine Kollision wird gemeldet, nicht durch ein
# Kunstkuerzel verdeckt. validate_short_name_uniqueness() prueft zudem
# global -- nach einer Regel, die seit PR #183 nicht mehr gilt.
#
# Was an ihre Stelle tritt: test-transform_data-kuerzel.R.

# --- aus test-season-transition-validators.R ---
# Tests for the season-transition validator escalations introduced by issue #74.
#
# 1. process_single_season: validate_team_count failure must abort (return
#    success=FALSE), no longer just warn and return success=TRUE.
# 2. process_season_transition: validate_season_processing failure at end of
#    pipeline must produce success=FALSE.

test_that("process_single_season fails when validate_team_count rejects merged file", {
  # Stub all the network-and-CSV-touching helpers process_single_season calls
  # before validate_team_count. We only care that, when validate_team_count
  # returns valid=FALSE, the function returns success=FALSE.
  stub(process_single_season, "validate_season_completion", TRUE)
  stub(process_single_season, "load_previous_team_list", data.frame())
  stub(process_single_season, "calculate_final_elos", data.frame())
  stub(process_single_season, "calculate_liga3_relegation_baseline", 1100)
  stub(process_single_season, "fetch_all_leagues_teams", list("78" = list(list(id = 1))))
  stub(process_single_season, "process_league_teams", list(list(id = 1)))
  stub(process_single_season, "generate_league_csv", "RCode/TeamList_2099_League78.csv")
  stub(process_single_season, "merge_league_files", "RCode/TeamList_2099.csv")
  stub(process_single_season, "get_league_name", "Bundesliga")
  stub(process_single_season, "validate_team_count", list(
    valid = FALSE,
    message = "Too few teams: 5 - expected at least 56"
  ))

  result <- process_single_season("2099", "2098")

  expect_false(result$success)
  expect_match(result$error, "Too few teams", fixed = TRUE)
})

test_that("process_single_season fails when merge_league_files returns NULL", {
  # Sibling defect to validate_team_count: a NULL return from merge_league_files
  # used to fall through to success=TRUE with only a warning. After issue #74
  # it must structurally fail.
  stub(process_single_season, "validate_season_completion", TRUE)
  stub(process_single_season, "load_previous_team_list", data.frame())
  stub(process_single_season, "calculate_final_elos", data.frame())
  stub(process_single_season, "calculate_liga3_relegation_baseline", 1100)
  stub(process_single_season, "fetch_all_leagues_teams", list("78" = list(list(id = 1))))
  stub(process_single_season, "process_league_teams", list(list(id = 1)))
  stub(process_single_season, "generate_league_csv", "RCode/TeamList_2099_League78.csv")
  stub(process_single_season, "merge_league_files", NULL)  # the failure mode
  stub(process_single_season, "get_league_name", "Bundesliga")

  result <- process_single_season("2099", "2098")

  expect_false(result$success)
  expect_match(result$error, "Failed to merge league files", fixed = TRUE)
})

test_that("process_season_transition fails when end-of-pipeline validate_season_processing rejects target season", {
  # Stub the inner pipeline so the loop succeeds, but make the new end-of-pipeline
  # validate_season_processing call return valid=FALSE.
  stub(process_season_transition, "display_welcome_message", invisible(NULL))
  stub(process_season_transition, "validate_season_range", invisible(NULL))
  stub(process_season_transition, "validate_api_access", TRUE)
  stub(process_season_transition, "get_seasons_to_process", "2099")
  stub(process_season_transition, "process_single_season", list(
    success = TRUE,
    teams_processed = 60,
    files_created = c("RCode/TeamList_2099.csv")
  ))
  stub(process_season_transition, "display_progress", invisible(NULL))
  stub(process_season_transition, "display_season_summary", invisible(NULL))
  stub(process_season_transition, "display_completion_message", invisible(NULL))
  stub(process_season_transition, "validate_season_processing", list(
    valid = FALSE,
    message = "Duplicate team IDs found"
  ))

  result <- process_season_transition("2098", "2099")

  expect_false(result$success)
  expect_match(result$error, "Duplicate team IDs", fixed = TRUE)
})

# --- aus test-saisonwechsel-schutzgrenzen.R ---
# Zwei Schutzmechanismen des Saisonwechsels, die heute nicht schuetzen.
#
# 1. merge_league_files() benennt Kollisionen STILL um (season_processor.R:378).
#    Einzige Spur ist eine cat-Zeile; der Lauf meldet Erfolg. Beim Lauf 2027
#    traefe das rund vierzig absichtlich gleiche Kuerzel.
#    Kuenftig: melden statt umbenennen (ADR 0007).
#
# 2. validate_team_count() misst gegen die kleinste EINZELNE Liga (12).
#    Eine Liste, der ganze Ligen fehlen, bestuende sie -- und genau das
#    passiert, wenn api-football die Spielplaene der neuen Saison noch nicht
#    hinterlegt hat: season_processor.R:164 warnt bei einer leeren Antwort
#    nur und ueberspringt die Liga.
#    Kuenftig: gegen die Sollstaerke der tatsaechlich abgerufenen Ligen.

lade_input_validation <- function() {
  # validate_team_count() lebt seit #209 in season_processor.R (vormals
  # input_validation.R) -- season_processor.R sourct seinerseits
  # RCode/team_data_carryover.R mit.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "season_validation.R"), local = env)
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  source(test_path("..", "..", "RCode", "season_processor.R"), local = env)
  env
}

schreibe_teamliste <- function(n) {
  f <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame(2))
  utils::write.table(
    data.frame(TeamID = seq_len(n), ShortText = sprintf("T%03d", seq_len(n)),
               Promotion = 0, InitialELO = 1500),
    f, sep = ";", row.names = FALSE, quote = FALSE
  )
  f
}

# Sollstaerke der Ligen, die der Saisonwechsel TATSAECHLICH abruft.
#
# ANGEPASST nach Christophs Entscheidung: Erst hiess es "alle aktiven
# Ligen" -- dann haette die Pruefung jeden gueltigen Lauf abgelehnt, denn
# der Saisonwechsel deckt ueber SEASON_TRANSITION_LEAGUES nur 78/79/80 ab
# (aufgezeichnete API-Antworten gibt es nur dafuer). Sobald die Kassetten
# fuer die uebrigen Ligen da sind, waechst die Grenze von selbst mit.
soll_teams <- function(env) {
  sum(vapply(lapply(env$SEASON_TRANSITION_LEAGUES, env$league_teams_range),
             function(r) r[[2]], integer(1)))
}

# ---------------------------------------------------------------------------

test_that("validate_team_count lehnt eine Liste ab, der ganze Ligen fehlen", {
  # Der Kernfall: Die API hat die Spielplaene der neuen Saison noch nicht,
  # Ligen kommen leer zurueck, season_processor.R warnt nur und ueberspringt
  # sie. Heute besteht das Ergebnis die Pruefung, weil ihre Untergrenze die
  # kleinste EINZELNE Liga ist.
  env <- lade_input_validation()

  # Eine von drei geprueften Ligen -- zwei fehlen.
  expect_false(env$validate_team_count(schreibe_teamliste(18))$valid)
  # Zwei von dreien.
  expect_false(env$validate_team_count(schreibe_teamliste(36))$valid)
})

test_that("validate_team_count akzeptiert eine vollstaendige Liste", {
  env <- lade_input_validation()

  # Alle drei geprueften Ligen in Sollstaerke.
  expect_true(env$validate_team_count(schreibe_teamliste(soll_teams(env)))$valid)
  # Und die echte TeamList_2026 mit ihren historischen Eintraegen.
  expect_true(env$validate_team_count(schreibe_teamliste(248))$valid)
})

test_that("die Untergrenze folgt der Registry, nicht einer festen Zahl", {
  # Sobald eine Liga dazukommt, muss die Grenze mitwachsen -- sonst faellt
  # der Schutz beim naechsten Ausbau wieder auf die alte Luecke zurueck.
  env <- lade_input_validation()
  soll <- soll_teams(env)

  # Knapp darunter reicht nicht.
  expect_false(env$validate_team_count(schreibe_teamliste(round(soll * 0.5)))$valid)
})

test_that("die Fehlermeldung nennt die erwartete Groessenordnung", {
  # "Too few teams: 56" allein laesst offen, was erwartet war -- und der
  # Lauf findet einmal im Juli statt.
  env <- lade_input_validation()

  ergebnis <- env$validate_team_count(schreibe_teamliste(56))

  expect_match(ergebnis$message, "56", fixed = TRUE)
  expect_match(ergebnis$message, as.character(soll_teams(env)), fixed = TRUE)
})

# --- merge_league_files: melden statt umbenennen ---------------------------

lade_season_processor <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  source(test_path("..", "..", "RCode", "season_processor.R"), local = env)
  env
}

schreibe_ligadatei <- function(dir, season, league, kuerzel, ids) {
  pfad <- file.path(dir, sprintf("TeamList_%s_League%s_temp.csv", season, league))
  utils::write.table(
    data.frame(TeamID = ids, ShortText = kuerzel, Promotion = 0,
               InitialELO = 1500, League = league, Region = "",
               Name = paste("Verein", ids)),
    pfad, sep = ";", row.names = FALSE, quote = FALSE
  )
  pfad
}

test_that("merge_league_files behaelt gleiche Kuerzel verschiedener Ligen", {
  # FCH steht in Liga 79 (Heidenheim) und 80 (Hansa Rostock) -- gewollt seit
  # PR #186. Heute benennt der Merge das zweite Vorkommen in "FC1" um und
  # meldet Erfolg. Das ist der Test, den Issue #195 unter "Erwartung"
  # ausdruecklich verlangt.
  env <- lade_season_processor()
  dir <- withr::local_tempdir()

  d1 <- schreibe_ligadatei(dir, "2027", "79", c("FCH", "SVW"), c(101, 102))
  d2 <- schreibe_ligadatei(dir, "2027", "80", c("FCH", "RWE"), c(201, 202))

  geschrieben <- NULL
  mockery::stub(env$merge_league_files, "generate_team_list_csv",
                function(data, season, output_dir = "RCode") {
                  geschrieben <<- data
                  file.path(dir, "TeamList_2027.csv")
                })

  env$merge_league_files(c(d1, d2), "2027")

  expect_equal(sort(geschrieben$ShortText), sort(c("FCH", "FCH", "SVW", "RWE")))
  expect_named(geschrieben, c("TeamID", "ShortText", "Promotion", "InitialELO",
                              "League", "Region", "Name"))
})

test_that("merge_league_files meldet eine Kollision INNERHALB einer Liga, statt sie zu verstecken", {
  # Der echte Konfliktfall. Er darf nicht durch ein Kunstkuerzel verdeckt
  # werden -- der Betreiber muss entscheiden, welcher Verein sein Kuerzel
  # behaelt (ADR 0007).
  env <- lade_season_processor()
  dir <- withr::local_tempdir()

  d1 <- schreibe_ligadatei(dir, "2027", "79", c("FCH", "FCH"), c(101, 102))

  mockery::stub(env$merge_league_files, "generate_team_list_csv",
                function(data, season, output_dir = "RCode") {
                  file.path(dir, "TeamList_2027.csv")
                })

  expect_warning(ergebnis <- env$merge_league_files(d1, "2027"), "FCH")
  expect_null(ergebnis)
})

# --- aus test-team-count-validation.R ---
# Test file for team count validation

# validate_team_count() lebt seit #209 in season_processor.R (vormals
# input_validation.R); season_processor.R braucht seinerseits die Registry
# sowie transform_data.R/csv_generation.R (fuer merge_league_files() &co.)
# und sourct team_data_carryover.R selbst mit.
source("../../RCode/league_registry.R")
source("../../RCode/transform_data.R")
source("../../RCode/csv_generation.R")

test_that("validate_team_count validates correct range", {
  # Create a temporary test file with valid team count
  test_file <- tempfile(fileext = ".csv")
  
  # Create test data with 58 teams (valid)
  test_data <- data.frame(
    TeamID = 1:58,
    ShortText = paste0("TM", 1:58),
    Promotion = rep(0, 58),
    InitialELO = rep(1500, 58)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 58)
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count rejects too few teams", {
  # Die Untergrenze folgt seit der Liga-Registry der kleinsten Liga (12 Teams,
  # Frauen-Bundesliga) statt der festen 56 fuer drei Ligen: Der Saisonwechsel
  # validiert auch Einzelligen-Dateien, nicht nur die zusammengefuehrte Liste.
  test_file <- tempfile(fileext = ".csv")

  test_data <- data.frame(
    TeamID = 1:8,
    ShortText = paste0("TM", 1:8),
    Promotion = rep(0, 8),
    InitialELO = rep(1500, 8)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too few teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count rejects too many teams", {
  # Die Obergrenze folgt der Summe aller zehn Ligen (mit Reserve, weil die
  # TeamList alle je aufgetretenen Teams fuehrt) statt der festen 62. Die
  # echte TeamList_2026 mit 237 Teams muss durchgehen -- das prueft
  # test-league_registry.R.
  test_file <- tempfile(fileext = ".csv")

  n <- 2000
  test_data <- data.frame(
    TeamID = 1:n,
    ShortText = paste0("TM", 1:n),
    Promotion = rep(0, n),
    InitialELO = rep(1500, n)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too many teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count handles file errors", {
  # Test non-existent file
  result <- validate_team_count("non_existent_file.csv")
  expect_false(result$valid)
  expect_true(grepl("File does not exist", result$message))
  
  # Test invalid CSV file
  test_file <- tempfile(fileext = ".csv")
  writeLines("This is not a valid CSV", test_file)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too few teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count accepts boundary values", {
  # Test minimum valid count (56)
  test_file <- tempfile(fileext = ".csv")
  test_data <- data.frame(
    TeamID = 1:56,
    ShortText = paste0("TM", 1:56),
    Promotion = rep(0, 56),
    InitialELO = rep(1500, 56)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 56)
  
  unlink(test_file)
  
  # Test maximum valid count (62)
  test_file <- tempfile(fileext = ".csv")
  test_data <- data.frame(
    TeamID = 1:62,
    ShortText = paste0("TM", 1:62),
    Promotion = rep(0, 62),
    InitialELO = rep(1500, 62)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 62)
  
  unlink(test_file)
})
