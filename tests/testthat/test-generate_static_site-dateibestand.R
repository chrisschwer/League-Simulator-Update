# Dateibestand des Ausgabeverzeichnisses ueber mehrere Zyklen (Issue #289).
#
# Entscheidung: Fehlen einer Liga in einem Zyklus die Verlaufsdaten oder
# scheitert das Schreiben, bleibt ihre Verlaufsseite aus dem letzten guten
# Zyklus stehen und bleibt verlinkt; das Stale-Banner kennzeichnet sie ueber
# ihren alten Zeitstempel. Navigation und Dateibestand stimmen nach jedem
# Zyklus ueberein. Seiten von Ligen, die nicht mehr in league_views() stehen,
# werden geloescht -- nur Seiten, die eindeutig vom Generator stammen.

gsd_zyklus1 <- as.POSIXct("2026-10-09 12:00:00", tz = "Europe/Berlin")
gsd_zyklus2 <- as.POSIXct("2026-10-10 12:00:00", tz = "Europe/Berlin")

# Ein Zyklus des Generators in `out`. `gen` darf eine praeparierte
# Modulumgebung sein (Write-Fehler, Registry-Wechsel).
gsd_zyklus <- function(out, league_data, now, gen = source_module("generate_static_site"),
                       ergebnisse = ergebnisse_aus_env(make_data_env())) {
  suppressMessages(gen$generate_static_site(
    ergebnisse = ergebnisse, output_dir = out, now = now, league_data = league_data
  ))
}

gsd_seite <- function(dir, name) html_lesen(file.path(dir, paste0(name, ".html")))

gsd_nav <- function(html) sub("(?s).*?(<nav aria-label=\"Ligen\">.*?</nav>).*", "\\1", html, perl = TRUE)

gsd_zeitstempel <- function(html) sub('(?s).*<time id="generated" datetime="([^"]+)".*', "\\1", html, perl = TRUE)

gsd_beide <- function() {
  list(bundesliga = verlauf_beispiel(), zweite_bundesliga = verlauf_beispiel())
}

# Alle Verlaufsziele einer Seite (Navigation und Verlaufslink).
gsd_verlaufsziele <- function(html) {
  hrefs <- regmatches(html, gregexpr('href="[^"]+"', html))[[1]]
  hrefs <- sub('^href="([^"]+)"$', "\\1", hrefs)
  unique(hrefs[grepl("^[a-z0-9-]+-verlauf\\.html$", hrefs)])
}

# Navigation und Dateibestand stimmen ueberein: Kein Verlaufslink einer Seite
# zeigt ins Leere, und jede vorhandene Verlaufsseite einer Liga steht in der
# Navigation jeder Verlaufsseite und als Link auf ihrer Ligaseite. (Die
# Hauptnavigation fuehrt alle Registry-Ligen; dass deren Ligaseiten in der
# Test-Fixture nicht alle entstehen, ist nicht Gegenstand von #289.)
gsd_erwarte_konsistent <- function(dir, gen = source_module("generate_static_site")) {
  seiten <- list.files(dir, pattern = "\\.html$")
  for (s in seiten) {
    fehlend <- setdiff(gsd_verlaufsziele(html_lesen(file.path(dir, s))), seiten)
    expect_identical(fehlend, character(0), info = paste("Links ins Leere auf", s))
  }
  views <- Filter(function(v) !is.null(v$verlauf_slug), gen$league_views())
  vorhanden <- Filter(function(v) file.exists(file.path(dir, paste0(v$verlauf_slug, ".html"))), views)
  for (v in vorhanden) {
    ziel <- paste0("href=\"", v$verlauf_slug, ".html\"")
    for (w in vorhanden) {
      expect_match(gsd_nav(gsd_seite(dir, w$verlauf_slug)), ziel, fixed = TRUE,
                   info = paste("Navigation von", w$verlauf_slug))
    }
    if (file.exists(file.path(dir, paste0(v$slug, ".html")))) {
      expect_match(gsd_seite(dir, v$slug), ziel, fixed = TRUE, info = paste("Ligaseite", v$slug))
    }
  }
}

# Modulumgebung, deren render_verlauf_page() fuer die Liga mit `slug` scheitert.
gsd_gen_schreibfehler <- function(slug) {
  gen <- source_module("generate_static_site")
  original <- gen$render_verlauf_page
  gen$render_verlauf_page <- function(view, ...) {
    if (identical(view$slug, slug)) stop("Platte voll")
    original(view, ...)
  }
  gen
}

# Scheitert eine Ligaseite, entstehen die uebrigen Seiten trotzdem und die
# alte Datei bleibt stehen -- wie bei den Verlaufsseiten. Vorher brach der
# ganze Zyklus ab, der Scheduler beendete sich und startete in einer
# Schleife neu, solange der Datensatz im Feed stand (Security-Audit
# 2026-10-17).
test_that("scheitert eine Ligaseite, bleibt ihre alte Datei stehen und die uebrigen Seiten entstehen", {
  gen <- source_module("generate_static_site")
  original <- gen$render_league_page
  gen$render_league_page <- function(view, ...) {
    if (identical(view$slug, "index")) stop("kaputter Datensatz")
    original(view, ...)
  }
  out <- withr::local_tempdir()
  gsd_zyklus(out, gsd_beide(), gsd_zyklus1)
  alt_index <- gsd_seite(out, "index")

  expect_warning(gsd_zyklus(out, gsd_beide(), gsd_zyklus2, gen = gen),
                 "Ligaseite bundesliga nicht geschrieben: kaputter Datensatz")

  expect_identical(gsd_seite(out, "index"), alt_index)
  neu <- format(gsd_zyklus2, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  expect_identical(gsd_zeitstempel(gsd_seite(out, "2-bundesliga")), neu)
  expect_identical(gsd_zeitstempel(gsd_seite(out, "methodik")), neu)
})

test_that("fehlen einer Liga die Verlaufsdaten, bleibt ihre Seite aus dem letzten guten Zyklus und bleibt verlinkt", {
  kaputt <- verlauf_beispiel()
  kaputt$tabelle$elo[kaputt$tabelle$team_id == 104] <- 1500
  faelle <- list(
    "Eintrag fehlt" = list(zweite_bundesliga = verlauf_beispiel()),
    "ohne matches" = list(bundesliga = list(tabelle = verlauf_beispiel()$tabelle),
                          zweite_bundesliga = verlauf_beispiel()),
    "Aufbereitung scheitert" = list(bundesliga = kaputt, zweite_bundesliga = verlauf_beispiel())
  )
  for (fall in names(faelle)) {
    out <- withr::local_tempdir()
    gsd_zyklus(out, gsd_beide(), gsd_zyklus1)
    alt <- gsd_seite(out, "bundesliga-verlauf")

    suppressWarnings(gsd_zyklus(out, faelle[[fall]], gsd_zyklus2))

    expect_true(file.exists(file.path(out, "bundesliga-verlauf.html")), info = fall)
    neu <- gsd_seite(out, "bundesliga-verlauf")
    expect_identical(gsd_zeitstempel(neu), gsd_zeitstempel(alt), info = fall)
    expect_match(gsd_seite(out, "index"), '<a href="bundesliga-verlauf.html">ELO-Verlauf der Saison ansehen',
                 fixed = TRUE, info = fall)
    expect_match(gsd_nav(gsd_seite(out, "2-bundesliga-verlauf")), '<a href="bundesliga-verlauf.html">Bundesliga</a>',
                 fixed = TRUE, info = fall)
    gsd_erwarte_konsistent(out)
  }
})

test_that("die behaltene Verlaufsseite fuehrt in ihrer Navigation auch Verlaufsseiten, die erst danach entstanden", {
  out <- withr::local_tempdir()
  gsd_zyklus(out, list(bundesliga = verlauf_beispiel()), gsd_zyklus1)
  expect_false(grepl("2-bundesliga-verlauf.html", gsd_seite(out, "bundesliga-verlauf"), fixed = TRUE))

  gsd_zyklus(out, list(zweite_bundesliga = verlauf_beispiel()), gsd_zyklus2)

  nav <- gsd_nav(gsd_seite(out, "bundesliga-verlauf"))
  expect_match(nav, '<a class="nav-current" aria-current="page" href="bundesliga-verlauf.html">Bundesliga</a>',
               fixed = TRUE)
  expect_match(nav, '<a href="2-bundesliga-verlauf.html">2. Bundesliga</a>', fixed = TRUE)
  gsd_erwarte_konsistent(out)
})

test_that("die behaltene Verlaufsseite zeigt nach der Schwelle das Stale-Banner", {
  skip_ohne_js()
  out <- withr::local_tempdir()
  gsd_zyklus(out, gsd_beide(), gsd_zyklus1)
  gsd_zyklus(out, list(zweite_bundesliga = verlauf_beispiel()), gsd_zyklus1 + 26 * 3600)

  html <- gsd_seite(out, "bundesliga-verlauf")
  erzeugt <- as.numeric(as.POSIXct(gsd_zeitstempel(html), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) * 1000
  expect_equal(erzeugt, as.numeric(gsd_zyklus1) * 1000)

  r <- js_szenario(html, "stale", list(now = (as.numeric(gsd_zyklus1) + 26 * 3600) * 1000))
  expect_length(r$fehler, 0)
  expect_false(r$verborgen)
  expect_identical(r$stunden, "26")
})

test_that("scheitert das Schreiben ohne alte Datei, verlinkt keine Seite die fehlende Verlaufsseite", {
  out <- withr::local_tempdir()
  gen <- gsd_gen_schreibfehler("index")
  expect_warning(gsd_zyklus(out, gsd_beide(), gsd_zyklus1, gen = gen),
                 "Verlaufsseite bundesliga nicht geschrieben")

  expect_false(file.exists(file.path(out, "bundesliga-verlauf.html")))
  expect_false(grepl("bundesliga-verlauf.html", gsd_seite(out, "index"), fixed = TRUE))
  expect_match(gsd_nav(gsd_seite(out, "2-bundesliga-verlauf")), '<a href="index.html">Bundesliga</a>', fixed = TRUE)
  gsd_erwarte_konsistent(out)
})

test_that("scheitert das Schreiben bei vorhandener Datei, bleibt die alte Seite stehen und verlinkt", {
  out <- withr::local_tempdir()
  gsd_zyklus(out, gsd_beide(), gsd_zyklus1)
  alt <- gsd_seite(out, "bundesliga-verlauf")

  gen <- gsd_gen_schreibfehler("index")
  expect_warning(gsd_zyklus(out, gsd_beide(), gsd_zyklus2, gen = gen),
                 "Verlaufsseite bundesliga nicht geschrieben")

  expect_identical(gsd_zeitstempel(gsd_seite(out, "bundesliga-verlauf")), gsd_zeitstempel(alt))
  expect_match(gsd_seite(out, "index"), '<a href="bundesliga-verlauf.html">', fixed = TRUE)
  expect_match(gsd_nav(gsd_seite(out, "2-bundesliga-verlauf")), '<a href="bundesliga-verlauf.html">Bundesliga</a>',
               fixed = TRUE)
  gsd_erwarte_konsistent(out)
})

test_that("Liga- und Verlaufsseiten einer Liga, die aus der Registry faellt, werden geloescht", {
  out <- withr::local_tempdir()
  ld <- list(bundesliga = verlauf_beispiel(), dritte_liga = verlauf_beispiel())
  gsd_zyklus(out, ld, gsd_zyklus1)
  expect_true(file.exists(file.path(out, "3-liga.html")))
  expect_true(file.exists(file.path(out, "3-liga-verlauf.html")))
  # Eine Seite unter einem frueheren Slug, wie sie ein Registry-Wechsel hinterlaesst.
  file.copy(file.path(out, "3-liga.html"), file.path(out, "alte-liga.html"))
  file.copy(file.path(out, "3-liga-verlauf.html"), file.path(out, "alte-liga-verlauf.html"))

  gen <- source_module("generate_static_site")
  original <- gen$league_views
  gen$league_views <- function() {
    v <- original()
    v$dritte_liga <- NULL
    v
  }
  gsd_zyklus(out, ld, gsd_zyklus2, gen = gen)

  for (weg in c("3-liga.html", "3-liga-verlauf.html", "alte-liga.html", "alte-liga-verlauf.html")) {
    expect_false(file.exists(file.path(out, weg)), info = weg)
  }
  expect_true(file.exists(file.path(out, "index.html")))
  expect_true(file.exists(file.path(out, "bundesliga-verlauf.html")))
  for (s in list.files(out, pattern = "\\.html$")) {
    expect_false(grepl("3-liga|alte-liga", html_lesen(file.path(out, s))), info = s)
  }
  gsd_erwarte_konsistent(out, gen = gen)
})

test_that("eine Liga ohne Ergebnisse in diesem Zyklus behaelt Liga- und Verlaufsseite", {
  out <- withr::local_tempdir()
  ld <- list(bundesliga = verlauf_beispiel(), dritte_liga = verlauf_beispiel())
  gsd_zyklus(out, ld, gsd_zyklus1)

  ergebnisse <- ergebnisse_aus_env(make_data_env())
  ergebnisse$dritte_liga <- NULL
  ergebnisse$dritte_liga_aufstieg <- NULL
  gsd_zyklus(out, ld, gsd_zyklus2, ergebnisse = ergebnisse)

  expect_true(file.exists(file.path(out, "3-liga.html")))
  expect_true(file.exists(file.path(out, "3-liga-verlauf.html")))
  expect_match(gsd_nav(gsd_seite(out, "bundesliga-verlauf")), '<a href="3-liga-verlauf.html">3. Liga</a>',
               fixed = TRUE)
  gsd_erwarte_konsistent(out)
})

test_that("Assets, Methodik, Aufstiegsseite und fremde Dateien bleiben unangetastet", {
  out <- withr::local_tempdir()
  gsd_zyklus(out, gsd_beide(), gsd_zyklus1)

  fremd <- c(
    "impressum.html" = "<!doctype html><p>Impressum</p>",
    "notizen-verlauf.html" = "<!doctype html><p>Handgeschrieben</p>",
    "robots.txt" = "User-agent: *",
    "rl-aufstieg.html" = "<!doctype html><p>Platzhalter</p>",
    "archiv/2025-verlauf.html" = "<!doctype html><p>Archiv</p>"
  )
  dir.create(file.path(out, "archiv"))
  for (name in names(fremd)) writeLines(fremd[[name]], file.path(out, name))
  # Eine generierte Seite in einem Unterordner gehoert nicht zum Muster.
  file.copy(file.path(out, "2-bundesliga-verlauf.html"), file.path(out, "archiv", "alt-verlauf.html"))
  vorher_assets <- list.files(file.path(out, "assets"), recursive = TRUE)

  gsd_zyklus(out, gsd_beide(), gsd_zyklus2)

  for (name in names(fremd)) {
    expect_identical(paste(readLines(file.path(out, name)), collapse = "\n"), fremd[[name]], info = name)
  }
  expect_true(file.exists(file.path(out, "archiv", "alt-verlauf.html")))
  expect_true(file.exists(file.path(out, "methodik.html")))
  expect_identical(list.files(file.path(out, "assets"), recursive = TRUE), vorher_assets)
})
