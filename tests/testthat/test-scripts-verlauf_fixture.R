# scripts/verlauf_fixture.R (Issue #184): erzeugt synthetische league_data fuer
# die Sichtpruefung -- drei Staende, ELO aus dem echten /league-details.
# Braucht den Rust-Server; ohne ihn skippt der Test (in der CI laeuft er).

test_that("verlauf_fixture.R schreibt drei Ligen, deren Verlauf sich aufbereiten laesst", {
  skip_if_no_rust(source_module("rust_integration"))
  rscript <- Sys.which("Rscript")
  skip_if(!nzchar(rscript), "Rscript nicht im PATH")
  skript <- normalizePath(test_path("..", "..", "scripts", "verlauf_fixture.R"), mustWork = TRUE)
  ziel <- withr::local_tempfile(fileext = ".rds")

  ausgabe <- suppressWarnings(system2(rscript, c(shQuote(skript), shQuote(ziel)), stdout = TRUE, stderr = TRUE))
  status <- attr(ausgabe, "status")
  expect_true(is.null(status) || status == 0L, info = paste(ausgabe, collapse = "\n"))

  ld <- readRDS(ziel)
  expect_setequal(names(ld), c("bundesliga", "zweite_bundesliga", "dritte_liga"))
  daten <- lapply(ld, fn(source_module("elo_verlauf"), "elo_verlauf_daten"))

  # Frueh: 18 Vereine nach 3 Spielen, Achse mit Ueberhang
  expect_length(daten$bundesliga$teams, 18)
  expect_identical(daten$bundesliga$achse_spiele_max, 4L)

  # Saisonmitte ueber die Winterpause: eine Luecke von mehr als 18 Tagen
  tage <- unique(unlist(lapply(daten$zweite_bundesliga$teams, function(t) {
    vapply(t$punkte[-1], function(p) p$datum, "")
  })))
  expect_gt(max(as.numeric(diff(sort(as.Date(tage))))), 18)

  # 20er-Liga mit Nachholspiel und einem gewerteten Spiel
  expect_length(daten$dritte_liga$teams, 20)
  nachhol <- unlist(lapply(daten$dritte_liga$teams, function(t) {
    vapply(t$punkte[-1], function(p) p$nachhol, logical(1))
  }))
  expect_true(any(nachhol))
  expect_true("AWD" %in% ld$dritte_liga$matches$status)

  expect_true(all(vapply(daten, function(d) d$saison_laeuft, logical(1))))
})
