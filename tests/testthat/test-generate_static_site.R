# Static site generation — Relaunch-Design (Phase 3).
#
# Verträge dieser Suite:
# - Vier Seiten (drei Ligen + Methodik) im 30-Punkte-Design, HTML-Heatmap
#   statt PNG, gemeinsames Stylesheet und selbst gehostete Fonts unter
#   assets/, Favicon; keinerlei externe Ressourcen.
# - Erhalten aus der Vor-Relaunch-Seite: Panels (inkl. 3.-Liga-Asymmetrie),
#   Stale-Banner-Mechanik, ISO-Zeitstempel, Fallback-Seite, Determinismus.
# Uses the real committed fixture shape (18x18, 18x18, 20x20, 20x20).
#
# library(mockery) nur fuer die #208-Tests zu .write_atomically() unten
# (stub() auf file.rename); der Rest der Datei kommt ohne Mocking aus.
library(mockery)

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

# Build a data environment with the same object names and shapes as the
# production ShinyApp/data/Ergebnis.Rds.
make_data_env <- function() {
  env <- new.env()
  mk <- function(n, teams) {
    m <- matrix(1 / n, nrow = teams, ncol = n,
                dimnames = list(paste0("T", seq_len(teams)), as.character(seq_len(n))))
    as.table(m)
  }
  env$Ergebnis <- mk(18, 18)
  env$Ergebnis2 <- mk(18, 18)
  env$Ergebnis3 <- mk(20, 20)
  env$Ergebnis3_Aufstieg <- mk(20, 20)
  env
}

read_html <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

# Der Block der Prognose-Heatmap einer Seite (erste table.heatmap).
heatmap_block <- function(html) {
  m <- regmatches(html, regexpr('<table class="heatmap"(.|\n)*?</table>', html))
  expect_length(m, 1)
  m
}

render_bundesliga <- function(gen, env, out,
                              now = as.POSIXct("2026-07-26 14:30:00",
                                               tz = "Europe/Berlin")) {
  gen$render_league_page(gen$league_views()$bundesliga, env, out, now = now)
}

# ---------------------------------------------------------------------------
# Zeitstempel (unverändert aus der Vor-Relaunch-Suite)
# ---------------------------------------------------------------------------

test_that("footer_timestamp labels summer time MESZ", {
  gen <- source_generator()
  ts <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  expect_match(gen$footer_timestamp(ts), "MESZ")
  expect_match(gen$footer_timestamp(ts), "26\\.07\\.2026 14:30")
})

test_that("footer_timestamp labels winter time MEZ", {
  gen <- source_generator()
  ts <- as.POSIXct("2026-01-15 14:30:00", tz = "Europe/Berlin")
  expect_match(gen$footer_timestamp(ts), "MEZ")
  expect_false(grepl("MESZ", gen$footer_timestamp(ts)))
})

# ---------------------------------------------------------------------------
# Panels (unverändert in der Sache, neues Umfeld)
# ---------------------------------------------------------------------------

test_that("render_panel_table emits one column per label", {
  gen <- source_generator()
  views <- gen$league_views()
  env <- make_data_env()
  html <- gen$render_panel_table(env$Ergebnis, views$bundesliga$top)

  for (lbl in views$bundesliga$top$labels) {
    expect_true(grepl(lbl, html, fixed = TRUE), info = lbl)
  }
  expect_match(html, "<table")
})

test_that("render_panel_table keeps its shape for a single-label panel", {
  gen <- source_generator()
  views <- gen$league_views()
  env <- make_data_env()
  html <- gen$render_panel_table(env$Ergebnis3, views$dritte_liga$bottom)
  expect_equal(lengths(regmatches(html, gregexpr("<tr><th scope=\"row\">", html))), 20L)
  expect_true(grepl("Abstieg", html, fixed = TRUE))
})

test_that("3. Liga page is built from Ergebnis3_Aufstieg on top and Ergebnis3 below", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  rownames(env$Ergebnis3_Aufstieg)[1] <- "AUFSTIEGONLY"
  rownames(env$Ergebnis3)[1] <- "ABSTIEGONLY"

  path <- gen$render_league_page(
    gen$league_views()$dritte_liga, env, out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )
  html <- read_html(path)

  expect_true(grepl("AUFSTIEGONLY", html, fixed = TRUE))
  expect_true(grepl("ABSTIEGONLY", html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Relaunch: HTML-Heatmap statt PNG
# ---------------------------------------------------------------------------

test_that("render_league_page writes an HTML page and no PNG asset", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  path <- render_bundesliga(gen, env, out)

  expect_true(file.exists(path))
  expect_equal(basename(path), "index.html")
  expect_length(list.files(out, pattern = "\\.png$", recursive = TRUE), 0)
})

test_that("the prognosis heatmap is an HTML table with one row per team", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))
  hm <- heatmap_block(html)

  expect_equal(lengths(regmatches(hm, gregexpr("<th scope=\"row\"", hm))), 18L)
  # 18 Platz-Spaltenköpfe
  for (platz in c(">1<", ">10<", ">18<")) {
    expect_true(grepl(platz, hm, fixed = TRUE), info = platz)
  }

  # 3. Liga: 20 Zeilen
  html3 <- read_html(gen$render_league_page(
    gen$league_views()$dritte_liga, env, out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  ))
  hm3 <- heatmap_block(html3)
  expect_equal(lengths(regmatches(hm3, gregexpr("<th scope=\"row\"", hm3))), 20L)
})

test_that("heatmap cells use the prozent notation", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  # Zeile 1 bekommt die vier Randfälle: >99, <1, 0 (leer) — Zeile 2 ein
  # sicheres Ergebnis (Haken).
  env$Ergebnis["T1", ] <- 0
  env$Ergebnis["T1", "1"] <- 0.995
  env$Ergebnis["T1", "2"] <- 0.005
  env$Ergebnis["T2", ] <- 0
  env$Ergebnis["T2", "2"] <- 1

  html <- read_html(render_bundesliga(gen, env, out))
  hm <- heatmap_block(html)

  expect_true(grepl("&gt;99", hm, fixed = TRUE))
  # "<1" nur als Färbung auf schmalen Bildschirmen: eigener Span
  expect_true(grepl('<span class="lt1">&lt;1</span>', hm, fixed = TRUE))
  expect_true(grepl("✓", hm, fixed = TRUE))
  # Nullzellen bleiben leer
  expect_true(grepl("></td>", hm, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Relaunch: Identität, Navigation, Metadaten
# ---------------------------------------------------------------------------

test_that("pages carry the 30-Punkte masthead and identity", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl("<title>30 Punkte · Bundesliga</title>", html, fixed = TRUE))
  expect_true(grepl(">30 Punkte<", html, fixed = TRUE))       # Wortmarke
  expect_true(grepl('class="mastrule"', html, fixed = TRUE))  # die eine rote Linie
  expect_true(grepl('<html lang="de">', html, fixed = TRUE))
  expect_true(grepl('name="viewport"', html, fixed = TRUE))
  expect_true(grepl('name="description"', html, fixed = TRUE))
  expect_true(grepl('property="og:title"', html, fixed = TRUE))
  expect_true(grepl("30punkte.wordpress.com", html, fixed = TRUE))
})

test_that("every page links all leagues and the Methodik page", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  # make_data_env() liefert nur die drei Altligen; seit Phase 5a kennt
  # league_views() auch die Frauen-Ligen. Gerendert wird, wofuer Daten da
  # sind -- die Aussage des Tests (jede Seite verlinkt alle anderen) gilt
  # unabhaengig davon, weil die Navigation aus league_views() kommt.
  #
  # ANGEPASST in Phase 5: Die Zielliste stand bis dahin als feste Aufzaehlung
  # der fuenf Slugs im Test. Mit den fuenf Regionalligen waeren es zehn --
  # und eine handgepflegte Liste, die bei der naechsten Liga wieder
  # nachgezogen werden muesste. Sie kommt jetzt aus league_views() selbst,
  # womit der Test dieselbe Aussage schaerfer traegt: JEDE bekannte Liga ist
  # verlinkt, nicht nur die, an die jemand gedacht hat.
  alle_slugs <- c(
    vapply(gen$league_views(), function(v) v$slug, character(1)),
    "methodik"
  )
  expect_gte(length(alle_slugs), 6)

  altligen <- c("bundesliga", "zweite_bundesliga", "dritte_liga")
  for (view in gen$league_views()[altligen]) {
    path <- gen$render_league_page(view, env, out, now = now)
    html <- read_html(path)
    for (slug in alle_slugs) {
      f <- paste0(slug, ".html")
      expect_true(grepl(f, html, fixed = TRUE), info = paste(view$slug, f))
    }
    expect_true(grepl('aria-current="page"', html, fixed = TRUE), info = view$slug)
  }
})

test_that("pages reference the shared stylesheet and favicon and load nothing external", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl('href="assets/site.css"', html, fixed = TRUE))
  expect_true(grepl('rel="icon"', html, fixed = TRUE))

  # Selbstenthaltend: keine externen Ressourcen, keine Bilder mehr
  expect_false(grepl("<script src=", html, fixed = TRUE))
  expect_false(grepl('<link[^>]+href="http', html))
  expect_false(grepl("fonts.googleapis", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Relaunch: Assets (Stylesheet, Fonts, Favicon)
# ---------------------------------------------------------------------------

test_that("generate_static_site ships stylesheet, self-hosted fonts and favicon", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  css_path <- file.path(out, "assets", "site.css")
  expect_true(file.exists(css_path))
  css <- read_html(css_path)
  expect_true(grepl("#B0261E", css, fixed = TRUE))
  expect_true(grepl("@font-face", css, fixed = TRUE))
  expect_true(grepl("Source Serif 4", css, fixed = TRUE))
  expect_false(grepl("googleapis", css, fixed = TRUE))

  fonts <- list.files(file.path(out, "assets", "fonts"), pattern = "\\.woff2$")
  expect_gte(length(fonts), 3)

  expect_true(file.exists(file.path(out, "assets", "favicon.svg")))
})

# ---------------------------------------------------------------------------
# Relaunch: Methodik-Seite
# ---------------------------------------------------------------------------

test_that("generate_static_site renders the Methodik page from the content file", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  paths <- gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  methodik <- file.path(out, "methodik.html")
  expect_true(methodik %in% paths)
  html <- read_html(methodik)

  # Inhalt kommt aus der redigierbaren Datei RCode/site_assets/methodik_content.html
  expect_true(grepl("Was die Prognosen mit Schach zu tun haben", html, fixed = TRUE))
  expect_true(grepl('class="provenienz"', html, fixed = TRUE))
  # aber ohne den Redaktions-Kommentarkopf der Quelldatei
  expect_false(grepl("ENTWURF", html, fixed = TRUE))

  expect_true(grepl("<title>30 Punkte · Methodik</title>", html, fixed = TRUE))
  expect_true(grepl('aria-current="page" href="methodik.html"', html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Erhalten: Zeitstempel, Stale-Banner, Fallback, Determinismus
# ---------------------------------------------------------------------------

test_that("the page embeds the generation time as ISO-8601 UTC", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))
  expect_true(grepl('<time id="generated" datetime="2026-07-26T12:30:00Z"',
                    html, fixed = TRUE))
})

test_that("the stale banner is embedded hidden and revealed by inline JS", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  html <- read_html(render_bundesliga(gen, env, out))

  expect_true(grepl('id="stale" hidden', html, fixed = TRUE))
  expect_true(grepl("werden derzeit nicht aktualisiert", html, fixed = TRUE))
  expect_true(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl("<script src=", html, fixed = TRUE))
  expect_true(grepl("getElementById(\"generated\")", html, fixed = TRUE))
  expect_true(grepl("> 24", html, fixed = TRUE))
})

test_that("generate_static_site rendert nur die Ligen, fuer die Daten vorliegen", {
  # ANGEPASST in Phase 5 (Regionalligen live). Der Test hiess bis dahin
  # "writes four pages" und zaehlte auf 4 -- drei Altligen plus Methodik.
  #
  # Diese Zahl war nie eine Aussage ueber die Ligen, sondern eine ueber die
  # FIXTURE: make_data_env() liefert genau die drei Altligen, und der
  # Generator ueberspringt seit Phase 2 jede Liga ohne Ergebnisse. Mit den
  # Frauen-Ligen (Phase 5a) und den fuenf Regionalligen (Phase 5) kennt
  # league_views() zehn Ligen; gerendert werden hier weiterhin drei.
  #
  # Statt die Zahl mitzufuehren, prueft der Test jetzt die AUSSAGE: Was
  # Daten hat, wird gerendert; was keine hat, taucht nicht auf. Diese Form
  # ueberlebt die naechste neue Liga.
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  paths <- gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 4)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
  # Ohne Ergebnisse keine Seite -- die Datei darf nicht halb gefuellt
  # entstehen.
  for (f in c("frauen-bundesliga.html", "rl-nord.html", "rl-bayern.html")) {
    expect_false(file.exists(file.path(out, f)), info = f)
  }
  expect_length(list.files(out, pattern = "\\.png$", recursive = TRUE), 0)
})

test_that("generate_static_site writes the fallback page when data is missing", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    NULL, NULL, NULL, NULL, output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(paths, 1)
  html <- read_html(file.path(out, "index.html"))
  expect_true(grepl("Noch keine Prognosedaten verfügbar", html, fixed = TRUE))
  expect_true(grepl("30punkte.wordpress.com", html, fixed = TRUE))
})

test_that("generate_static_site output is deterministic for fixed inputs", {
  gen <- source_generator()
  env <- make_data_env()
  now <- as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")

  out1 <- withr::local_tempdir()
  out2 <- withr::local_tempdir()
  gen$generate_static_site(env$Ergebnis, env$Ergebnis2, env$Ergebnis3,
                           env$Ergebnis3_Aufstieg, output_dir = out1, now = now)
  gen$generate_static_site(env$Ergebnis, env$Ergebnis2, env$Ergebnis3,
                           env$Ergebnis3_Aufstieg, output_dir = out2, now = now)

  for (f in c("index.html", "2-bundesliga.html", "3-liga.html", "methodik.html",
              file.path("assets", "site.css"))) {
    expect_equal(
      readLines(file.path(out1, f), warn = FALSE),
      readLines(file.path(out2, f), warn = FALSE),
      info = f
    )
  }
})

# ---------------------------------------------------------------------------
# Issue #208, Punkt 4: atomare Seiten-Schreibvorgaenge
#
# writeLines() direkt auf den Zielpfad hinterlaesst bei einem Absturz
# mittendrin eine halb geschriebene Datei -- Caddy kann sie waehrenddessen
# ausliefern. .write_atomically() schreibt in eine Temp-Datei im selben
# Verzeichnis (damit file.rename() ein guenstiger Rename bleibt, kein
# Kopiervorgang ueber ein Dateisystem hinweg) und benennt sie danach um.
# ---------------------------------------------------------------------------

test_that(".write_atomically hinterlaesst keine .tmp-Datei und den Inhalt korrekt", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  ziel <- file.path(out, "seite.html")

  gen$.write_atomically("<html>Inhalt</html>", ziel)

  expect_true(file.exists(ziel))
  expect_equal(readLines(ziel, warn = FALSE), "<html>Inhalt</html>")
  expect_length(list.files(out, pattern = "\\.tmp$"), 0)
})

test_that("generate_static_site hinterlaesst nach dem Rendern keine .tmp-Dateien", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- make_data_env()

  gen$generate_static_site(
    env$Ergebnis, env$Ergebnis2, env$Ergebnis3, env$Ergebnis3_Aufstieg,
    output_dir = out,
    now = as.POSIXct("2026-07-26 14:30:00", tz = "Europe/Berlin")
  )

  expect_length(list.files(out, pattern = "\\.tmp$", recursive = TRUE), 0)
})

test_that("ein fehlschlagendes file.rename laesst die alte Seite unangetastet", {
  # Simuliert einen Absturz zwischen Schreiben der Temp-Datei und dem
  # Umbenennen: file.rename() liefert FALSE (Disk voll, Rechteproblem, ...).
  # Der alte Seiteninhalt muss danach noch vollstaendig lesbar sein --
  # .write_atomically() darf die alte Datei nicht vor dem erfolgreichen
  # Rename antasten.
  gen <- source_generator()
  out <- withr::local_tempdir()
  ziel <- file.path(out, "seite.html")
  writeLines("<html>ALT</html>", ziel)

  stub(gen$.write_atomically, "file.rename", function(...) FALSE)
  expect_error(gen$.write_atomically("<html>NEU</html>", ziel))

  expect_equal(readLines(ziel, warn = FALSE), "<html>ALT</html>")
  expect_length(list.files(out, pattern = "\\.tmp$"), 0)
})


# ---------------------------------------------------------------------------
# Eingeschraenkter Service im Seitenfuss (Issue #224, Refs #190)
# ---------------------------------------------------------------------------
#
# Am 14.09.2026 lief der Scheduler den ganzen Tag im 83-Minuten-Takt, ohne
# dass die Seite davon etwas verriet: Sie zeigte "Letztes Update 18:51" und
# sah damit aus wie eine Seite, die gleich wieder aktualisiert wird. Ein
# Frauen-Bundesliga-Spiel um 18:00 fiel in die Luecke bis 20:15.
#
# Der Stale-Banner greift erst nach 24 Stunden und haette hier nie
# angeschlagen. Der Fuss muss den ABWEICHENDEN TAKT nennen, nicht nur den
# Zeitpunkt der letzten Aktualisierung -- sonst kann ein Leser nicht
# unterscheiden, ob die Zahlen zwei Minuten oder anderthalb Stunden alt
# sein duerfen.

test_that("footer_timestamp nennt den eingeschraenkten Takt, wenn er abweicht", {
  gen <- source_generator()
  ts <- as.POSIXct("2026-09-14 18:51:00", tz = "Europe/Berlin")

  zeile <- gen$footer_timestamp(ts, waittime = 83.1 * 60)

  expect_match(zeile, "Letztes Update")
  expect_match(zeile, "Eingeschr.nkter Service")
  expect_match(zeile, "alle 83 Minuten")
})

test_that("footer_timestamp schweigt beim Normaltakt", {
  # Der Hinweis ist eine Ausnahmemeldung. Stuende er immer da, waere er
  # nach einer Woche unsichtbar -- und im Ausnahmefall wertlos.
  gen <- source_generator()
  ts <- as.POSIXct("2026-09-14 18:51:00", tz = "Europe/Berlin")

  expect_false(grepl("Eingeschr", gen$footer_timestamp(ts, waittime = 120)))
  # Auch leicht darueber noch nicht: Ein Takt von 2:30 min ist kein
  # eingeschraenkter Service, sondern Rundung.
  expect_false(grepl("Eingeschr", gen$footer_timestamp(ts, waittime = 150)))
})

test_that("footer_timestamp ohne Taktangabe ist unveraendert", {
  # Der Produktionsaufruf aus scripts/preview_site.R und alle bestehenden
  # Tests rufen mit EINEM Argument auf. Der Default darf die Zeile nicht
  # anfassen.
  gen <- source_generator()
  ts <- as.POSIXct("2026-09-14 18:51:00", tz = "Europe/Berlin")

  expect_equal(gen$footer_timestamp(ts), gen$footer_timestamp(ts, waittime = NULL))
  expect_false(grepl("Eingeschr", gen$footer_timestamp(ts)))
})

test_that("generate_static_site traegt den Takt bis in den Seitenfuss", {
  # Der Weg vom Loop bis ins HTML: generate_static_site(waittime = ...)
  # muss auf JEDER gerenderten Seite ankommen, nicht nur auf der ersten.
  gen <- source_generator()
  env <- make_data_env()
  out <- file.path(tempdir(), "fuss-takt")
  unlink(out, recursive = TRUE)

  gen$generate_static_site(
    output_dir = out,
    ergebnisse = list(bundesliga = env$Ergebnis),
    now = as.POSIXct("2026-09-14 18:51:00", tz = "Europe/Berlin"),
    waittime = 83.1 * 60
  )

  seiten <- list.files(out, pattern = "\\.html$", full.names = TRUE)
  expect_gt(length(seiten), 0)
  for (p in seiten) {
    expect_match(read_html(p), "Eingeschr.nkter Service",
                 info = basename(p))
  }
})

test_that("generate_static_site ohne Taktangabe laesst den Fuss unveraendert", {
  # Gegenprobe: Ohne das Argument darf nichts im Fuss stehen, was vorher
  # nicht da war -- sonst braeche der Default alle Bestandsseiten.
  gen <- source_generator()
  env <- make_data_env()
  out <- file.path(tempdir(), "fuss-normal")
  unlink(out, recursive = TRUE)

  gen$generate_static_site(
    output_dir = out,
    ergebnisse = list(bundesliga = env$Ergebnis),
    now = as.POSIXct("2026-09-14 18:51:00", tz = "Europe/Berlin")
  )

  seiten <- list.files(out, pattern = "\\.html$", full.names = TRUE)
  expect_gt(length(seiten), 0)
  for (p in seiten) {
    expect_false(grepl("Eingeschr", read_html(p)), info = basename(p))
  }
})

# ---------------------------------------------------------------------------
# Issue #229: ganz berechnete Panels filtern Zeilen wie alle anderen
# ---------------------------------------------------------------------------
# Das Abstiegspanel der Regionalligen ist ganz berechnet (computed = TRUE).
# Es muss dasselbe 1-%-Kriterium anwenden wie die Platzgruppen-Panels der
# oberen Ligen: Eine Zeile bleibt, wenn die Summe der Panel-Spalten
# mindestens 1 % erreicht.

test_that("ganz berechnetes Panel laesst Teams unter 1 % weg (#229)", {
  gen <- source_generator()
  panel <- list(labels = "Abstieg", computed = TRUE)
  obj <- data.frame(Abstieg = c(0.40, 0.01, 0.009, 0),
                    row.names = c("GEFAEHRDET", "GRENZE", "KNAPPDRUNTER", "SICHER"))

  html <- gen$render_panel_table(obj, panel)

  expect_match(html, "GEFAEHRDET", fixed = TRUE)
  expect_match(html, "GRENZE", fixed = TRUE)
  expect_false(grepl("KNAPPDRUNTER", html, fixed = TRUE))
  expect_false(grepl("SICHER", html, fixed = TRUE))
})

test_that("bei zwei berechneten Spalten zaehlt deren Summe (Bayern, #229)", {
  gen <- source_generator()
  panel <- list(labels = c("Relegation", "Abstieg"), computed = TRUE)
  obj <- data.frame(Relegation = c(0.006, 0.004),
                    Abstieg = c(0.006, 0.004),
                    row.names = c("SUMMEREICHT", "SUMMEZUKLEIN"))

  html <- gen$render_panel_table(obj, panel)

  expect_match(html, "SUMMEREICHT", fixed = TRUE)
  expect_false(grepl("SUMMEZUKLEIN", html, fixed = TRUE))
})

test_that("ganz berechnetes Panel ohne gefaehrdetes Team rendert leer wie die anderen (#229)", {
  gen <- source_generator()
  panel <- list(labels = "Abstieg", computed = TRUE)
  obj <- data.frame(Abstieg = c(0, 0.001), row.names = c("A", "B"))

  expect_identical(gen$render_panel_table(obj, panel), "")
})

# --- aus test-live-na-guard.R ---
# Regressionstest für den 4b-Review-Übertrag (in 4c umgesetzt): api-football
# meldet Fixtures in den ersten Minuten nach Anpfiff als live, ohne die
# goals-Felder zu befüllen. Der Zwischenstand darf dann nie "NA:NA" zeigen,
# sondern einen Strich-Platzhalter.
test_that("Live-Zwischenstand ohne Tore rendert Striche, nie NA", {
  gen <- source_generator()
  lv <- data.frame(
    fixture_id = 7001, round = 2L,
    kickoff = as.POSIXct("2026-08-30 15:30", tz = "UTC"), status = "1H",
    home_id = 101, away_id = 102,
    home_name = "FC Alpha", away_name = "SV Beta",
    goals_home = NA_real_, goals_away = NA_real_,
    stringsAsFactors = FALSE
  )

  html <- gen$render_live(lv)

  expect_false(grepl("NA", html, fixed = TRUE))
  expect_match(html, "–:–", fixed = TRUE)
})

# --- aus test-frauen-ligen-live.R ---
library(testthat)

# Phase 5a des Ligen-Ausbaus: Die beiden Frauen-Bundesligen gehen live.
#
# Die fünf Regionalligen folgen erst nach Phase 6: Ihre Absteigerzahl hängt
# davon ab, wie viele Teams aus der 3. Liga in die jeweilige Staffel fallen
# (Verbandsrecherche). Ein Abstiegs-Panel mit fester Platzspanne wäre auf der
# veröffentlichten Seite sichtbar falsch.
#
# Vier Dinge müssen sich ändern, damit eine Liga mit 14 statt 18 Teams
# überhaupt gerendert werden kann:
#
#  1. Panel-Grenzen sind heute ABSOLUTE Platzindizes. "Abstieg 17:18" auf
#     eine 14-Team-Liga angewandt bricht mit "Indizierung außerhalb der
#     Grenzen" -- verifiziert. Abstiegspanels müssen von UNTEN zählen.
#  2. Die Teamzahl schwankt je Saison (Frauen-BL 12-14): Die Grenzen können
#     nicht statisch sein, sondern folgen der tatsächlichen Spaltenzahl.
#  3. Die zweistufige Navigation, weil zehn Ligen die flache Zeile sprengen.
#  4. scripts/preview_site.R muss weiterlaufen, obwohl seine Fixture nur die
#     drei Altligen kennt.
#
# Die europaeischen Plaetze stehen bewusst in league_views() und NICHT in der
# Registry -- wie schon bei der Bundesliga. Sie folgen dem UEFA-Koeffizienten
# und aendern sich unabhaengig von Auf- und Abstieg; ein Registry-Feld
# suggerierte eine Systematik, die es nicht gibt.

mk_ergebnis <- function(teams) {
  m <- matrix(1 / teams, nrow = teams, ncol = teams,
              dimnames = list(paste0("T", seq_len(teams)),
                              as.character(seq_len(teams))))
  as.table(m)
}

# --- 1. Panel-Grenzen relativ zur Teamzahl ----------------------------------

test_that("negative Panel-Grenzen zaehlen von unten", {
  # -1 ist der letzte Platz, -2 der vorletzte. Damit beschreibt ein
  # Abstiegspanel "die letzten beiden" unabhaengig von der Ligagroesse.
  gen <- source_generator()

  expect_equal(gen$.resolve_bounds(cbind(c(-2, -1)), n = 14), cbind(c(13, 14)))
  expect_equal(gen$.resolve_bounds(cbind(c(-2, -1)), n = 18), cbind(c(17, 18)))
  # Positive Grenzen bleiben, was sie sind.
  expect_equal(gen$.resolve_bounds(cbind(c(1, 1), c(2, 4)), n = 18),
               cbind(c(1, 1), c(2, 4)))
})

test_that("gemischte Grenzen werden korrekt aufgeloest", {
  gen <- source_generator()

  expect_equal(gen$.resolve_bounds(cbind(c(-3, -1)), n = 14), cbind(c(12, 14)))
})

test_that("render_panel_table rechnet mit den richtigen Spalten", {
  # ACHTUNG, subtile Falle: R liest negative Indizes als AUSSCHLUSS.
  # `data[, c(-2,-1)]` liefert alle Spalten AUSSER den ersten beiden -- das
  # Panel rendert dann klaglos, zeigt aber die Summe der falschen Spalten.
  # Bei Gleichverteilung ueber 14 Plaetze waeren das 86 % statt 14 %.
  #
  # Der Test prueft deshalb den WERT, nicht nur die Existenz der Tabelle.
  gen <- source_generator()
  panel <- list(source = "x", filter_cols = c(-2, -1),
                labels = "Abstieg", groups = cbind(c(-2, -1)))

  html <- gen$render_panel_table(mk_ergebnis(14), panel)

  expect_match(html, "<table class=\"panel\">")
  # Zwei von vierzehn Plaetzen, gleichverteilt: 14 %.
  expect_match(html, "<td>14</td>")
  expect_no_match(html, "<td>86</td>")
})

test_that("dieselbe Panel-Definition traegt 12 und 14 Teams", {
  # Die Frauen-Bundesliga wuchs 2025 von 12 auf 14. Eine Definition muss
  # beide Groessen ueberstehen, ohne dass jemand nachpflegt -- und in beiden
  # Faellen die letzten zwei Plaetze meinen.
  gen <- source_generator()
  panel <- list(source = "x", filter_cols = c(-2, -1),
                labels = "Abstieg", groups = cbind(c(-2, -1)))

  # 2/12 = 17 %, 2/14 = 14 %
  expect_match(gen$render_panel_table(mk_ergebnis(12), panel), "<td>17</td>")
  expect_match(gen$render_panel_table(mk_ergebnis(14), panel), "<td>14</td>")
})

test_that("die Altligen rendern unveraendert", {
  # Verhaltensneutralitaet: Absolute Grenzen bleiben erlaubt und wirken wie
  # bisher.
  gen <- source_generator()
  alt <- list(source = "x", filter_cols = 16:18, labels = c("Relegation", "Abstieg"),
              groups = cbind(c(16, 16), c(17, 18)))

  expect_match(gen$render_panel_table(mk_ergebnis(18), alt), "Relegation")
})

# Die folgenden Tests pruefen die GERENDERTE TABELLE, nicht die Konfiguration.
#
# Eine Zusicherung wie `expect_equal(v$bottom$groups, cbind(c(-2,-1)))` waere
# wertlos: Sie besteht, sobald die Zeichen "-2, -1" irgendwo stehen -- auch
# wenn die Aufloesung gar nicht existiert oder falsch rechnet. Sie pinnt eine
# Schreibweise, kein Verhalten.
#
# Gemessen wird deshalb an gleichverteilten Prognosen, wo jeder Platz
# 1/n traegt und die erwarteten Prozentwerte exakt bekannt sind.

test_that("die Frauen-Bundesliga zeigt Meister und CL-Qualifikation", {
  # "Der Meister erreicht direkt die Ligaphase der Champions League.
  # Vizemeister und Drittplatzierter erreichen die Qualifikation."
  # Zwei Gruppen, weil sich die Konsequenz unterscheidet.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  expect_equal(v$slug, "frauen-bundesliga")
  expect_equal(v$top$labels, c("Meister", "Champions League Quali"))

  # Bei 14 gleichverteilten Teams: Platz 1 = 7 %, Plaetze 2-3 = 14 %.
  html <- gen$render_panel_table(mk_ergebnis(14), v$top)
  expect_match(html, "Meister")
  expect_match(html, "Champions League Quali")
  expect_match(html, "<td>7</td><td>14</td>")
})

test_that("die Frauen-Bundesliga hat zwei Abstiegsplaetze", {
  # "Die letzten zwei Teams steigen ab" -- und zwar die letzten, egal ob die
  # Liga 12 oder 14 Teams hat. 2025 ist sie gewachsen.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  expect_equal(v$bottom$labels, "Abstieg")

  # 2/14 = 14 %, 2/12 = 17 %. Waere die Aufloesung kaputt (R liest negative
  # Indizes als Ausschluss), stuenden hier 86 % bzw. 83 %.
  expect_match(gen$render_panel_table(mk_ergebnis(14), v$bottom), "<td>14</td>")
  expect_match(gen$render_panel_table(mk_ergebnis(12), v$bottom), "<td>17</td>")
})

test_that("das Abstiegspanel trifft wirklich die letzten Plaetze", {
  # Schaerfster Test der Aufloesung: eine Prognose, in der ein Team sicher
  # Letzter wird. Nur wenn -2:-1 auf die Plaetze 13-14 zeigt, steht dort
  # 100 % -- zeigte es auf 1-12, waere es 0 %.
  gen <- source_generator()
  v <- gen$league_views()$frauen_bundesliga

  m <- matrix(0, nrow = 14, ncol = 14,
              dimnames = list(paste0("T", 1:14), as.character(1:14)))
  m[1, 14] <- 1      # T1 wird sicher Letzter
  m[2, 1] <- 1       # T2 wird sicher Meister
  for (i in 3:14) m[i, i - 1] <- 1

  html <- gen$render_panel_table(as.table(m), v$bottom)

  expect_match(html, "T1")
  expect_no_match(html, "T2")   # der Meister taucht im Abstiegspanel nicht auf
})

# --- 3. Zweistufige Navigation ----------------------------------------------

test_that("die Navigation gruppiert nach nav_group", {
  # Fuenf Ligen sprengen die flache Zeile. Gruppen: Herren, Frauen --
  # Methodik bleibt eigenstaendig.
  #
  # ANGEPASST in Phase 5: Dazu kommt die Gruppe "Regionalliga". Geprueft
  # wird hier weiterhin nur die Aussage dieser Phase -- es gibt eine Gruppe
  # "Herren" mit drei und eine Gruppe "Frauen" mit zwei Ligen.
  #
  # ANGEPASST mit Issue #178: Hier stand, Herren und Frauen seien die ersten
  # BEIDEN Gruppen. Das war eine Aussage ueber die Reihenfolge, die dieser
  # Test gar nicht treffen wollte -- seit #178 steht "Regionalliga"
  # zwischen ihnen. Geprueft wird jetzt die Zugehoerigkeit, nicht die
  # Nachbarschaft; die Reihenfolge pinnt test-phase5-regionalligen.R.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  je_gruppe <- vapply(gruppen, function(g) g$group, character(1))
  expect_true(all(c("Herren", "Frauen") %in% je_gruppe))
  expect_length(gruppen[[which(je_gruppe == "Herren")]]$items, 3)
  expect_length(gruppen[[which(je_gruppe == "Frauen")]]$items, 2)
})

test_that("das Navigations-HTML traegt Gruppenlabels und alle Ligen", {
  gen <- source_generator()
  html <- gen$.nav_html("index")

  expect_match(html, "Herren")
  expect_match(html, "Frauen")
  expect_match(html, "frauen-bundesliga\\.html")
  expect_match(html, "methodik\\.html")
  # Die aktuelle Seite bleibt markiert.
  expect_match(html, "nav-current")
})

# --- 4. Ende-zu-Ende ---------------------------------------------------------

test_that("generate_static_site rendert sechs Seiten", {
  # Fuenf Ligen plus Methodik.
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-08-01 12:00", tz = "Europe/Berlin"),
    ergebnisse = list(
      bundesliga = mk_ergebnis(18),
      zweite_bundesliga = mk_ergebnis(18),
      dritte_liga = mk_ergebnis(20),
      dritte_liga_aufstieg = mk_ergebnis(20),
      frauen_bundesliga = mk_ergebnis(14),
      zweite_frauen_bundesliga = mk_ergebnis(14),
      zweite_frauen_bundesliga_aufstieg = mk_ergebnis(14)
    )
  )

  expect_length(paths, 6)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html",
              "frauen-bundesliga.html", "2-frauen-bundesliga.html",
              "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
})

# --- aus test-n-ligen-entflechtung.R ---
# --- generate_static_site: Liste statt vier Argumente -----------------------

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

test_that("eine fehlende Liga wird uebersprungen und benannt", {
  # Ursprünglich verlangte dieser Test einen Abbruch. Mit Phase 5a wurde das
  # zum Zielkonflikt: scripts/preview_site.R lädt eine Fixture, die nur die
  # drei Altligen kennt, und muss trotzdem eine Vorschau erzeugen.
  #
  # Entschieden (Christoph): überspringen, aber laut. Fällt im Betrieb die
  # Simulation einer Liga aus, ist eine Seite ohne sie besser als gar keine
  # Seite -- der stille Fehler, den der Test verhindern soll, bleibt aber
  # ausgeschlossen, weil die übersprungene Liga in der Meldung steht.
  gen <- source_generator()
  out <- withr::local_tempdir()

  msgs <- capture_messages(
    paths <- gen$generate_static_site(
      output_dir = out,
      ergebnisse = list(bundesliga = make_ergebnis(18),
                        zweite_bundesliga = make_ergebnis(18))
    )
  )

  expect_match(paste(msgs, collapse = " "), "dritte_liga")
  # Die vorhandenen Ligen werden gerendert.
  expect_true(file.exists(file.path(out, "index.html")))
  expect_false(file.exists(file.path(out, "3-liga.html")))
})

# --- aus test-phase5-regionalligen.R ---
# Gleichverteilte Prognose: jeder Platz traegt 1/n. Damit sind die
# erwarteten Prozentwerte der Panels exakt bekannt.

# Die fuenf RL in Registry-Reihenfolge. Sie ist Vertrag (Fetch-Reihenfolge
# und Navigation), deshalb hier einmal ausgeschrieben.
RL_SCHLUESSEL <- c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest",
                   "rl_bayern")
RL_SLUGS <- c("rl-nord", "rl-nordost", "rl-west", "rl-suedwest", "rl-bayern")

# Slug der Seite "Aufstieg in die 3. Liga". Steht hier und nicht erst bei
# den Aufstiegstests: testthat wertet Top-Level-Code sequenziell aus, und
# die Navigations- und Seitenzahl-Tests weiter oben brauchen den Wert
# bereits.
AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

# Die Staffeln mit Direktaufstieg 2026/27 (Par. 55b DFB-SpO Nr. 2 plus der
# Rotationsplatz, den 2026/27 Nordost traegt).
RL_DIREKTAUFSTIEG <- c("rl_nordost", "rl_west", "rl_suedwest")
# Nord und Bayern spielen stattdessen zwei Aufstiegsspiele gegeneinander.
RL_AUFSTIEGSSPIELE <- c("rl_nord", "rl_bayern")

# --- 2a. Oben: Direktaufstieg vs. Aufstiegsspiele ---------------------------

test_that("Nordost, West und SuedWest zeigen oben eine Aufstiegsspalte", {
  # Direktaufsteiger: P(Aufstieg) = P(Meister), beide Groessen fallen
  # zusammen. Eine Spalte genuegt, und sie ist eine echte Platzgruppe
  # (Platz 1). Geprueft wird der WERT der gerenderten Tabelle: Bei 18
  # gleichverteilten Teams traegt Platz 1 genau 1/18 = 6 %.
  gen <- source_generator()
  views <- gen$league_views()

  for (key in RL_DIREKTAUFSTIEG) {
    v <- views[[key]]
    expect_identical(v$top$labels, "Aufstieg", info = key)
    # Direktaufstieg ist eine Platzgruppe, keine berechnete Spalte.
    expect_false(any(isTRUE(v$top$computed)), info = key)

    html <- gen$render_panel_table(mk_ergebnis(18), v$top)
    expect_match(html, "<td>6</td>", info = key)
    # Waere die Gruppe versehentlich 1:2, stuenden hier 11 %.
    expect_no_match(html, "<td>11</td>", info = key)
  }
})

# ===========================================================================
# 3. Navigation: zweistufig, drei Gruppen, Methodik separat
# ===========================================================================

test_that(".nav_groups ordnet die Gruppen nach NAV_GRUPPEN_REIHENFOLGE", {
  # ANGEPASST (Issue #178): Die Reihenfolge war bis hierher ein Nebenprodukt
  # der Registry-Reihenfolge -- die Regionalligen standen als dritte Gruppe
  # UNTER den Frauen-Ligen und lasen sich dadurch, als stuenden sie quer zu
  # den beiden Geschlechter-Gruppen. Tatsaechlich sind es Herren-Ligen
  # derselben Wechselgemeinschaft (ADR 0004).
  #
  # Die Anzeigereihenfolge ist jetzt eigene Angabe im Renderer und NICHT
  # mehr die Registry-Reihenfolge: Die Registry bestimmt weiterhin die
  # Abrufreihenfolge (league_ids()), und die beiden duerfen sich
  # unabhaengig voneinander bewegen.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  expect_identical(vapply(gruppen, function(g) g$group, character(1)),
                   c("Herren", "Regionalliga", "Frauen"))
  expect_length(gruppen[[1]]$items, 3)
  # Fuenf Staffeln plus die Seite "Aufstieg in die 3. Liga", die der
  # Nutzer bewusst unter "Regionalliga" haengt statt in eine eigene Gruppe.
  expect_length(gruppen[[2]]$items, 6)
  expect_length(gruppen[[3]]$items, 2)
})

test_that("eine unbekannte nav_group faellt ans Ende, statt zu verschwinden", {
  # Die Sortierung darf nicht stillschweigend filtern: Traegt eine kuenftige
  # Liga eine Gruppe, die NAV_GRUPPEN_REIHENFOLGE nicht kennt, muss sie
  # sichtbar bleiben -- hinten, aber da. Ein Renderer, der sie weglaesst,
  # verlaere eine ganze Liga aus der Navigation, ohne dass etwas fehlschlaegt.
  gen <- source_generator()

  expect_identical(
    gen$.nav_gruppen_sortiert(c("Frauen", "Uebersee", "Herren")),
    c("Herren", "Frauen", "Uebersee")
  )
})

test_that("jede Liga steht in genau der Gruppe ihrer Registry", {
  # Gruppenzugehoerigkeit, nicht nur Vorhandensein der Links: Ein Test, der
  # nur prueft, dass "rl-nord.html" irgendwo im HTML steht, besteht auch,
  # wenn die Liga unter "Frauen" haengt.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  slugs_je_gruppe <- lapply(gruppen, function(g) {
    vapply(g$items, function(i) i$slug, character(1))
  })
  names(slugs_je_gruppe) <- vapply(gruppen, function(g) g$group, character(1))

  expect_identical(slugs_je_gruppe$Herren,
                   c("index", "2-bundesliga", "3-liga"))
  expect_identical(slugs_je_gruppe$Frauen,
                   c("frauen-bundesliga", "2-frauen-bundesliga"))
  expect_identical(slugs_je_gruppe$Regionalliga,
                   c(RL_SLUGS, AUFSTIEGSSEITE_SLUG))
})

test_that("das Navigations-HTML ordnet die RL-Links der Regionalliga-Zeile zu", {
  # Geprueft wird die gerenderte STRUKTUR: Die fuenf RL-Links muessen in
  # DERSELBEN nav-row stehen wie das Gruppenlabel "Regionalliga" -- und
  # keiner davon in der Herren- oder Frauen-Zeile.
  gen <- source_generator()
  html <- gen$.nav_html("index")

  zeilen <- regmatches(
    html,
    gregexpr('<div class="nav-row">.*?</div>', html)
  )[[1]]

  gruppe_von <- function(zeile) {
    sub('.*<span class="nav-group">(.*?)</span>.*', "\\1", zeile)
  }
  labels <- vapply(zeilen, gruppe_von, character(1), USE.NAMES = FALSE)

  # Drei Ligagruppen plus die label-lose Methodik-Zeile. Die Regionalligen
  # stehen seit Issue #178 zwischen Herren und Frauen; Methodik bleibt die
  # LETZTE Zeile -- sie wird in .nav_html() hinter den Gruppenzeilen
  # angehaengt und von der Gruppensortierung gar nicht erfasst.
  expect_identical(labels, c("Herren", "Regionalliga", "Frauen", ""))

  # Die fuenf Staffeln UND die Aufstiegsseite -- sie haengt bewusst hier
  # und nicht in einer eigenen Gruppe.
  rl_zeile <- zeilen[labels == "Regionalliga"]
  for (slug in c(RL_SLUGS, AUFSTIEGSSEITE_SLUG)) {
    expect_match(rl_zeile, paste0('href="', slug, '.html"'), fixed = TRUE,
                 info = slug)
  }

  # Kein RL-Link verirrt sich in eine andere Zeile.
  for (andere in zeilen[labels != "Regionalliga"]) {
    for (slug in c(RL_SLUGS, AUFSTIEGSSEITE_SLUG)) {
      expect_no_match(andere, paste0('href="', slug, '.html"'), fixed = TRUE,
                      info = slug)
    }
  }
})

test_that("Methodik bleibt eine eigene, gruppenlose Zeile", {
  gen <- source_generator()
  html <- gen$.nav_html("methodik")

  zeilen <- regmatches(
    html,
    gregexpr('<div class="nav-row">.*?</div>', html)
  )[[1]]
  methodik_zeile <- zeilen[grepl("methodik.html", zeilen, fixed = TRUE)]

  expect_length(methodik_zeile, 1)
  expect_match(methodik_zeile, '<span class="nav-group"></span>', fixed = TRUE)
  expect_match(methodik_zeile, 'aria-current="page"', fixed = TRUE)
})

# ===========================================================================
# 4. Seiten: zehn Liga-Seiten plus Methodik
# ===========================================================================

# Vollstaendige Ergebnisliste fuer alle zehn Ligen inklusive der
# Sonderlaeufe (Aufstiegstabellen ohne Zweitvertretungen) und der
# berechneten RL-Spalten.
alle_ergebnisse <- function() {
  ergebnisse <- list(
    bundesliga = mk_ergebnis(18),
    zweite_bundesliga = mk_ergebnis(18),
    dritte_liga = mk_ergebnis(20),
    dritte_liga_aufstieg = mk_ergebnis(20),
    frauen_bundesliga = mk_ergebnis(14),
    zweite_frauen_bundesliga = mk_ergebnis(14),
    zweite_frauen_bundesliga_aufstieg = mk_ergebnis(14)
  )

  teams <- paste0("T", seq_len(18))
  for (key in RL_SCHLUESSEL) {
    ergebnisse[[key]] <- mk_ergebnis(18)
    # Die berechnete Abstiegsspalte: ein data.frame in genau der Form, die
    # rl_abstiegsprognose() liefert.
    ergebnisse[[paste0(key, "_abstieg")]] <-
      if (identical(key, "rl_bayern")) {
        data.frame(Relegation = rep(2 / 18, 18), Abstieg = rep(2 / 18, 18),
                   row.names = teams)
      } else {
        data.frame(Abstieg = rep(3 / 18, 18), row.names = teams)
      }
  }
  # Nord und Bayern: berechnete Aufstiegsspalte aus den Aufstiegsspielen.
  # Die Spalte heisst wie bei rl_aufstiegsprognose() "Aufstieg"; sie steht
  # als EXTRA-Wert rechts neben der Meisterspalte.
  for (key in RL_AUFSTIEGSSPIELE) {
    ergebnisse[[paste0(key, "_aufstieg")]] <-
      data.frame(Aufstieg = rep(0.5 / 18, 18), row.names = teams)
  }
  ergebnisse
}

test_that("generate_static_site schreibt zehn Liga-Seiten und die Methodik", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  paths <- gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  # Zehn Liga-Seiten, die Aufstiegsseite und Methodik.
  expect_length(paths, 12)
  for (f in c("index.html", "2-bundesliga.html", "3-liga.html",
              "frauen-bundesliga.html", "2-frauen-bundesliga.html",
              paste0(RL_SLUGS, ".html"),
              paste0(AUFSTIEGSSEITE_SLUG, ".html"), "methodik.html")) {
    expect_true(file.exists(file.path(out, f)), info = f)
  }
})

test_that("jede Regionalliga-Seite traegt ihren eigenen Titel", {
  # Zehn Seiten aus einer Schleife: Ein vertauschter Index faellt sonst
  # nicht auf, weil alle Seiten gleich aussehen.
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  erwartet <- c("rl-nord" = "Nord", "rl-nordost" = "Nordost",
                "rl-west" = "West", "rl-suedwest" = "SüdWest",
                "rl-bayern" = "Bayern")
  for (slug in names(erwartet)) {
    html <- paste(readLines(file.path(out, paste0(slug, ".html")),
                            warn = FALSE), collapse = "\n")
    expect_match(html,
                 paste0("<title>30 Punkte · ", erwartet[[slug]], "</title>"),
                 fixed = TRUE, info = slug)
    expect_match(html, 'aria-current="page"', fixed = TRUE, info = slug)
  }
})

test_that("die Bayern-Seite zeigt Relegation und Abstieg als zwei Spalten", {
  # Ende zu Ende: Die zwei Groessen duerfen nicht zu einer Zahl
  # verschmelzen. Gemessen an Werten, die sich unterscheiden -- waeren sie
  # gleich, bewiese die Tabelle nichts.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_bayern_abstieg <- data.frame(
    Relegation = rep(0.11, 18),
    Abstieg = rep(0.22, 18),
    row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-bayern.html"), warn = FALSE),
                collapse = "\n")

  expect_match(html, "Relegation", fixed = TRUE)
  expect_match(html, "<td>11</td><td>22</td>", fixed = TRUE)
  # Nicht zu 33 % addiert.
  expect_no_match(html, "<td>33</td>", fixed = TRUE)
})

test_that("die Nord-Seite zeigt oben Meister und Aufstieg nebeneinander", {
  # Ende zu Ende fuer das GEMISCHTE Panel: Die Meisterspalte kommt als
  # Platzsumme aus der Prognosematrix (1/18 = 6 %), die Aufstiegsspalte
  # unveraendert aus dem berechneten Objekt. Die Zahlen sind bewusst
  # verschieden, sonst bewiese die Tabelle nichts.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_nord_aufstieg <- data.frame(
    Aufstieg = rep(0.37, 18), row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-nord.html"), warn = FALSE),
                collapse = "\n")

  expect_match(html, "Meister", fixed = TRUE)
  # 6 % Meister, 37 % Aufstieg -- in dieser Reihenfolge, in einer Zeile.
  expect_match(html, "<td>6</td><td>37</td>", fixed = TRUE)
})

test_that("die berechnete Abstiegsspalte landet unveraendert in der Tabelle", {
  # Der schaerfste Test des `computed`-Pfades: Der Wert darf NICHT ueber
  # Platzspalten summiert werden. Bei einer gleichverteilten Prognose ueber
  # 18 Plaetze waere jede Platzsumme ein Vielfaches von 1/18 (6, 11, 17 %)
  # -- 41 % kann nur durchgereicht sein.
  gen <- source_generator()
  out <- withr::local_tempdir()

  ergebnisse <- alle_ergebnisse()
  ergebnisse$rl_nord_abstieg <- data.frame(
    Abstieg = rep(0.41, 18), row.names = paste0("T", seq_len(18))
  )

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = ergebnisse
  )

  html <- paste(readLines(file.path(out, "rl-nord.html"), warn = FALSE),
                collapse = "\n")
  expect_match(html, "<td>41</td>", fixed = TRUE)
})

# --- Die Seite existiert und haengt unter "Regionalliga" --------------------

test_that("die Aufstiegsseite steht in der Regionalliga-Gruppe der Navigation", {
  # Entscheidung des Nutzers: keine eigene Gruppe. Geprueft wird die
  # ZUGEHOERIGKEIT, nicht nur das Vorhandensein des Links -- ein Test auf
  # "rl-aufstieg.html steht irgendwo im HTML" bestuende auch, wenn die
  # Seite unter "Frauen" haengt.
  gen <- source_generator()
  gruppen <- gen$.nav_groups()

  namen <- vapply(gruppen, function(g) g$group, character(1))
  expect_true("Regionalliga" %in% namen)

  rl_gruppe <- gruppen[[which(namen == "Regionalliga")]]
  slugs <- vapply(rl_gruppe$items, function(i) i$slug, character(1))

  expect_true(AUFSTIEGSSEITE_SLUG %in% slugs)
  # Fuenf Staffeln plus die Aufstiegsseite, und die Seite steht hinter den
  # Staffeln -- sie fasst sie zusammen, sie leitet sie nicht ein.
  expect_identical(slugs, c(RL_SLUGS, AUFSTIEGSSEITE_SLUG))
})

test_that("die Aufstiegsseite wird mitgerendert und traegt ihren Titel", {
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  pfad <- file.path(out, paste0(AUFSTIEGSSEITE_SLUG, ".html"))
  expect_true(file.exists(pfad))

  html <- paste(readLines(pfad, warn = FALSE), collapse = "\n")
  expect_match(html, "Aufstieg in die 3. Liga", fixed = TRUE)
  expect_match(html, 'aria-current="page"', fixed = TRUE)
})

test_that("die Siegquote bleibt leer, wo es keine Meisterchance gibt", {
  # FESTGELEGT: leer, nicht 0 und nicht NaN. Eine 0 waere eine Aussage
  # ueber die Spielstaerke, die aus den Daten nicht folgt -- das Team
  # erreicht das Aufstiegsspiel ja gar nicht. NaN waere ein sichtbarer
  # Rechenfehler auf einer veroeffentlichten Seite.
  gen <- source_generator()

  # 0/0 muss zur leeren Zelle werden, jeder definierte Wert bleibt.
  expect_identical(gen$.siegquote(0, 0), "")
  expect_identical(gen$.siegquote(0.2, 0.4), gen$prozent(0.5))

  # Auch der Grenzfall "Aufstieg > 0, Meister = 0" darf nicht durchrutschen
  # -- er ist rechnerisch unmoeglich und deshalb ein Fehler in den Daten,
  # keine Unendlichkeit auf der Seite.
  expect_identical(gen$.siegquote(0.1, 0), "")
})

test_that("die gerenderte Seite laesst die Zelle ohne Meisterchance leer", {
  # Ende zu Ende: Weder "0" noch "NaN" noch "Inf" darf im HTML stehen.
  gen <- source_generator()
  out <- withr::local_tempdir()

  gen$generate_static_site(
    output_dir = out,
    now = as.POSIXct("2026-09-07 12:00", tz = "Europe/Berlin"),
    ergebnisse = alle_ergebnisse()
  )

  html <- paste(readLines(file.path(out, paste0(AUFSTIEGSSEITE_SLUG, ".html")),
                          warn = FALSE), collapse = "\n")

  expect_no_match(html, "NaN", fixed = TRUE)
  expect_no_match(html, "Inf", fixed = TRUE)
  # Eine leere Zelle, nicht eine mit Inhalt.
  expect_match(html, "<td></td>", fixed = TRUE)
})
