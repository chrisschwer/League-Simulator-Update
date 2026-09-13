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

library(testthat)

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
