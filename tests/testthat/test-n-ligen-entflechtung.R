library(testthat)
library(mockery)

# Phase 2 des Ligen-Ausbaus: Update-Loop und Seitengenerator von "genau drei
# Ligen" auf "n Ligen" entflechten, gesteuert über die Liga-Registry.
#
# Diese Phase ist VERHALTENSNEUTRAL. Solange league_ids() nur die drei
# Altligen liefert, muss alles beim Alten bleiben -- insbesondere bleibt
# test-update-loop-gating.R (526 Zeilen, 12 Tests) unverändert grün. Diese
# Datei prüft, dass die Mechanik darüber hinaus n-fähig ist.
#
# Zwei Randbedingungen, an denen der Umbau scheitern würde:
#
#  1. mockery::stub() bindet an die Funktionsumgebung von
#     update_all_leagues_loop(). Verifiziert: Wandert ein Aufruf in eine
#     separate Top-Level-Funktion, greift der Stub NICHT mehr -- zehn Tests
#     bräche das auf einen Schlag. Der lapply-Umbau muss INLINE bleiben.
#  2. Die Aufrufe müssen weiterhin BENANNT erfolgen
#     (retrieveResults(league =, season =), generate_static_site(output_dir =,
#     league_data =)), weil die Stubs auf diese Namen hören.

# --- Registry-Helfer für die Verdrahtung ------------------------------------

test_that("die Registry liefert Schluessel in Fetch-Reihenfolge", {
  # league_data und league_views() sind über diese Schlüssel verbunden; der
  # Loop baut sie, der Generator indiziert damit. Die Reihenfolge bestimmt
  # zudem, in welcher Folge die Ligen abgerufen werden -- sie darf sich nicht
  # unbemerkt ändern (test-update-loop-league-data.R pinnt SENTINEL-1/2/3).
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  expect_equal(env$active_league_keys(),
               c("bundesliga", "zweite_bundesliga", "dritte_liga"))
  expect_equal(env$active_league_keys(), names(env$active_leagues()))
})

test_that("active_leagues liefert die vollstaendigen Eintraege", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  aktiv <- env$active_leagues()
  expect_length(aktiv, 3)
  expect_equal(aktiv$bundesliga$api_id, "78")
  expect_equal(aktiv$dritte_liga$api_id, "80")
  expect_true(all(vapply(aktiv, function(l) isTRUE(l$active), logical(1))))
})

test_that("die Registry weiss, welche Liga einen Aufstiegslauf braucht", {
  # Der -50-Malus für Zweitvertretungen ist heute für Liga 3 hartkodiert. Er
  # hängt an einer Liga-Eigenschaft, nicht an einer ID -- und gilt künftig
  # auch für die Regionalligen, deren Zweitvertretungen ebenfalls nicht in
  # die 3. Liga aufsteigen dürfen.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)

  expect_true(env$has_promotion_restriction("80"))
  expect_false(env$has_promotion_restriction("78"))
  expect_false(env$has_promotion_restriction("79"))
})

# --- generate_static_site: Liste statt vier Argumente -----------------------

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

make_ergebnis <- function(teams, n = teams) {
  m <- matrix(1 / n, nrow = teams, ncol = n,
              dimnames = list(paste0("T", seq_len(teams)), as.character(seq_len(n))))
  as.table(m)
}

test_that("generate_static_site nimmt eine benannte Ergebnisliste", {
  # Die neue Form. Schlüssel sind die Registry-/league_views()-Schlüssel;
  # der Aufstiegslauf der 3. Liga bekommt einen EIGENEN Schlüssel, weil er
  # ein zweiter Lauf derselben Liga ist und league_views() ihn über den
  # Namen "Ergebnis3_Aufstieg" auflöst.
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-08-01 12:00", tz = "Europe/Berlin"),
    ergebnisse = list(
      bundesliga = make_ergebnis(18),
      zweite_bundesliga = make_ergebnis(18),
      dritte_liga = make_ergebnis(20),
      dritte_liga_aufstieg = make_ergebnis(20)
    )
  )

  expect_length(paths, 4)
  expect_true(file.exists(file.path(out, "index.html")))
  expect_true(file.exists(file.path(out, "3-liga.html")))
})

test_that("die alte Aufrufform funktioniert unveraendert weiter", {
  # Kompatibilitätspfad: scripts/preview_site.R und sieben Testaufrufe rufen
  # mit den vier Einzelargumenten auf -- teils positional. Sie müssen ohne
  # Änderung weiterlaufen, sonst ist der Umbau nicht verhaltensneutral.
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    make_ergebnis(18), make_ergebnis(18), make_ergebnis(20), make_ergebnis(20),
    output_dir = out,
    now = as.POSIXct("2026-08-01 12:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 4)
  expect_true(file.exists(file.path(out, "index.html")))
})

test_that("beide Aufrufformen erzeugen dieselben Seiten", {
  # Der schärfste Nachweis der Verhaltensneutralität: byteweise identisch.
  gen <- source_generator()
  now <- as.POSIXct("2026-08-01 12:00", tz = "Europe/Berlin")
  e <- list(bl = make_ergebnis(18), bl2 = make_ergebnis(18),
            l3 = make_ergebnis(20), l3a = make_ergebnis(20))

  alt_dir <- withr::local_tempdir()
  gen$generate_static_site(e$bl, e$bl2, e$l3, e$l3a,
                           output_dir = alt_dir, now = now)

  neu_dir <- withr::local_tempdir()
  gen$generate_static_site(
    output_dir = neu_dir, now = now,
    ergebnisse = list(bundesliga = e$bl, zweite_bundesliga = e$bl2,
                      dritte_liga = e$l3, dritte_liga_aufstieg = e$l3a)
  )

  for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html")) {
    expect_identical(
      readLines(file.path(alt_dir, f), warn = FALSE),
      readLines(file.path(neu_dir, f), warn = FALSE),
      info = f
    )
  }
})

test_that("die Fallback-Seite greift bei leerer Ergebnisliste", {
  # Bisher prüfte der Guard drei hartkodierte Objekte auf NULL. Generisch
  # muss er erkennen, dass keine Prognose vorliegt -- in beiden Aufrufformen.
  gen <- source_generator()

  out_alt <- withr::local_tempdir()
  p_alt <- gen$generate_static_site(NULL, NULL, NULL, NULL, output_dir = out_alt)
  expect_length(p_alt, 1)
  expect_match(paste(readLines(p_alt, warn = FALSE), collapse = " "),
               "Noch keine Prognosedaten")

  out_neu <- withr::local_tempdir()
  p_neu <- gen$generate_static_site(output_dir = out_neu, ergebnisse = list())
  expect_length(p_neu, 1)
})

test_that("eine fehlende Liga in der Ergebnisliste bricht ab", {
  # Ein fehlender Schlüssel wäre sonst ein stiller Fehler: get() auf ein
  # emptyenv() liefert einen kryptischen Fehler tief im Renderer. Die
  # Meldung muss die fehlende Liga nennen.
  gen <- source_generator()
  out <- withr::local_tempdir()

  err <- expect_error(gen$generate_static_site(
    output_dir = out,
    ergebnisse = list(bundesliga = make_ergebnis(18),
                      zweite_bundesliga = make_ergebnis(18))
  ))
  expect_match(conditionMessage(err), "dritte_liga")
})

# --- Update-Loop: n Ligen statt drei Variablen ------------------------------

source("../../RCode/update_all_leagues_loop.R")

with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))
  force(expr)
}

fake_fixtures_min <- function(statuses = c("FT", "NS"), ids = c(1L, 2L)) {
  list(
    fixture = list(
      id = ids,
      date = rep("2026-08-01T13:00:00+00:00", length(ids)),
      status = list(short = statuses, elapsed = rep(NA, length(ids)))
    ),
    goals = list(home = rep(0L, length(ids)), away = rep(0L, length(ids)))
  )
}

fake_transformed_min <- function() {
  data.frame(
    TeamHeim = "AAA", TeamGast = "BBB", ToreHeim = 1, ToreGast = 0,
    AAA = 1500, BBB = 1500
  )
}

#' Führt einen Loop-Durchlauf aus und protokolliert die Kollaborateur-Aufrufe.
run_loop_capturing <- function() {
  cap <- new.env()
  cap$fetched <- character()
  cap$sim_frames <- 0L
  cap$league_data <- NULL
  cap$ergebnisse <- NULL

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    cap$fetched <- c(cap$fetched, league)
    fake_fixtures_min()
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(...) fake_transformed_min())
  stub(update_all_leagues_loop, "leagueSimulatorRust", function(...) {
    cap$sim_frames <- cap$sim_frames + 1L
    matrix(1 / 18, nrow = 18, ncol = 18)
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(...) {
    args <- list(...)
    cap$league_data <- args$league_data
    cap$ergebnisse <- args$ergebnisse
    invisible(NULL)
  })

  with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = 1, initial_wait = 0, n = 10, saison = "2024",
      TeamList_file = "tests/testthat/fixtures/rust-required/TeamList_minimal.csv",
      static_site_dir = tempdir(), full_fetch_every = 30
    )
  })
  cap
}

test_that("der Loop holt die Ligen aus der Registry, in Registry-Reihenfolge", {
  # Vorher standen die drei retrieveResults-Aufrufe einzeln im Code. Jetzt
  # iteriert der Loop -- die Reihenfolge muss dieselbe bleiben, weil
  # test-update-loop-league-data.R sie über SENTINEL-1/2/3 pinnt.
  cap <- run_loop_capturing()

  expect_equal(cap$fetched, c("78", "79", "80"))
})

test_that("der Loop uebergibt die Ergebnisse als benannte Liste", {
  # Die neue Form. Der Aufstiegslauf der 3. Liga hat einen eigenen Schlüssel.
  cap <- run_loop_capturing()

  expect_type(cap$ergebnisse, "list")
  expect_setequal(
    names(cap$ergebnisse),
    c("bundesliga", "zweite_bundesliga", "dritte_liga", "dritte_liga_aufstieg")
  )
  expect_false(any(vapply(cap$ergebnisse, is.null, logical(1))))
})

test_that("league_data behaelt seine Schluessel und Reihenfolge", {
  # Der Generator indiziert league_data[[key]] mit den league_views()-
  # Schlüsseln. Weicht die Benennung ab, bekommt jede Liga stillschweigend
  # keine Tabellendaten -- die Seite degradiert, ohne zu scheitern.
  cap <- run_loop_capturing()

  expect_equal(names(cap$league_data),
               c("bundesliga", "zweite_bundesliga", "dritte_liga"))
})

test_that("Loop 1 simuliert jede Liga plus den Aufstiegslauf", {
  # Drei Ligen + ein Aufstiegslauf = 4. Die Zahl folgt der Registry, nicht
  # einer festen Annahme -- test-update-loop-gating.R pinnt sie als 4 bzw. 8.
  cap <- run_loop_capturing()

  expect_equal(cap$sim_frames, 4L)
})
