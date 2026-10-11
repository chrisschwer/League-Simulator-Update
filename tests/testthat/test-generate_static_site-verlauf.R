# Verlaufsseiten im Generator (Issue #184): Seite je Liga mit league_data,
# Link auf der Ligaseite, Ruecklink, kontextabhaengige Navigation, Tabelle
# aus R, Daten als eingebettetes JSON. Spec:
# docs/superpowers/specs/2026-10-10-elo-verlauf-design.md, Abschnitt 1.

gsv_gen <- source_module("generate_static_site")

gsv_seite <- function(dir, slug) html_lesen(file.path(dir, paste0(slug, ".html")))

gsv_nav <- function(html) sub("(?s).*?(<nav.*?</nav>).*", "\\1", html, perl = TRUE)

gsv_json <- function(html) {
  roh <- sub('(?s).*<script type="application/json" id="verlauf-daten">(.*?)</script>.*',
             "\\1", html, perl = TRUE)
  jsonlite::fromJSON(roh, simplifyVector = FALSE)
}

gsv_zwei_ligen <- function(...) {
  list(bundesliga = verlauf_beispiel(...), zweite_bundesliga = verlauf_beispiel())
}

test_that("mit league_data entsteht je Liga eine Verlaufsseite unter ihrem verlauf_slug", {
  dir <- verlauf_site(gsv_zwei_ligen())
  expect_true(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_true(file.exists(file.path(dir, "2-bundesliga-verlauf.html")))
  expect_false(file.exists(file.path(dir, "3-liga-verlauf.html")))
  expect_true(file.exists(file.path(dir, "assets", "verlauf.js")))
})

test_that("ohne league_data entsteht keine Verlaufsseite und kein Link", {
  dir <- verlauf_site(NULL)
  expect_length(list.files(dir, pattern = "-verlauf\\.html$"), 0)
  expect_false(grepl("ELO-Verlauf der Saison ansehen", gsv_seite(dir, "index"), fixed = TRUE))
})

test_that("ein league_entry ohne matches erzeugt keine Verlaufsseite und keine Warnung", {
  ld <- list(bundesliga = list(tabelle = verlauf_beispiel()$tabelle))
  # envir ausdruecklich: innerhalb von expect_*() waere parent.frame() eine
  # Auswertungsumgebung, mit der das Temp-Verzeichnis zu frueh verschwaende.
  ziel <- environment()
  expect_no_warning(dir <- verlauf_site(ld, envir = ziel))
  expect_false(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_false(grepl("bundesliga-verlauf.html", gsv_seite(dir, "index"), fixed = TRUE))
})

test_that("die Ligaseite verlinkt ihre Verlaufsseite im Tabellenabschnitt", {
  dir <- verlauf_site(gsv_zwei_ligen())
  html <- gsv_seite(dir, "index")
  link <- '<a href="bundesliga-verlauf.html">ELO-Verlauf der Saison ansehen →</a>'
  expect_match(html, link, fixed = TRUE)
  expect_gt(regexpr(link, html, fixed = TRUE), regexpr('<section id="tabelle">', html, fixed = TRUE))
  expect_match(gsv_seite(dir, "2-bundesliga"), '<a href="2-bundesliga-verlauf.html">', fixed = TRUE)
  expect_false(grepl("-verlauf.html", gsv_seite(dir, "3-liga"), fixed = TRUE))
})

test_that("die Verlaufsseite verlinkt zurueck auf die Prognose ihrer Liga", {
  dir <- verlauf_site(gsv_zwei_ligen())
  expect_match(gsv_seite(dir, "bundesliga-verlauf"), '<a href="index.html">← Prognose Bundesliga</a>', fixed = TRUE)
  expect_match(gsv_seite(dir, "2-bundesliga-verlauf"), '<a href="2-bundesliga.html">← Prognose 2. Bundesliga</a>',
               fixed = TRUE)
})

test_that("auf der Verlaufsseite fuehren die Ligalinks zu den Verlaufsseiten, sonst zur Ligaseite", {
  dir <- verlauf_site(gsv_zwei_ligen())
  nav <- gsv_nav(gsv_seite(dir, "bundesliga-verlauf"))
  expect_match(nav, '<a class="nav-current" aria-current="page" href="bundesliga-verlauf.html">Bundesliga</a>',
               fixed = TRUE)
  expect_match(nav, '<a href="2-bundesliga-verlauf.html">2. Bundesliga</a>', fixed = TRUE)
  expect_match(nav, '<a href="3-liga.html">3. Liga</a>', fixed = TRUE)
  expect_match(nav, '<a href="rl-aufstieg.html">', fixed = TRUE)
  expect_match(nav, '<a href="methodik.html">Methodik</a>', fixed = TRUE)
})

test_that("die Navigation der Ligaseiten bleibt unveraendert", {
  dir <- verlauf_site(gsv_zwei_ligen())
  nav <- gsv_nav(gsv_seite(dir, "index"))
  expect_match(nav, '<a class="nav-current" aria-current="page" href="index.html">Bundesliga</a>', fixed = TRUE)
  expect_match(nav, '<a href="2-bundesliga.html">2. Bundesliga</a>', fixed = TRUE)
  expect_false(grepl("-verlauf.html", nav, fixed = TRUE))
})

test_that("Titel und Ueberschrift nennen Liga und Saison", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, "<title>30 Punkte · ELO-Verlauf Bundesliga</title>", fixed = TRUE)
  expect_match(html, "<h2>ELO-Verlauf Bundesliga 2026/27</h2>", fixed = TRUE)
})

test_that("die Daten stehen als JSON vor dem Zeichenskript, in Tabellenreihenfolge", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  d <- gsv_json(html)
  expect_identical(d$liga, "Bundesliga")
  expect_identical(d$saison, "2026/27")
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(vapply(d$teams, function(t) t$id, numeric(1)), c(101, 104, 102, 103))
  expect_gt(regexpr('<script src="assets/verlauf.js"></script>', html, fixed = TRUE),
            regexpr('id="verlauf-daten"', html, fixed = TRUE))
})

test_that("die Tabelle rendert R: Startwert, heute, Veraenderung", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, '<table class="verlauf-tab" id="verlauf-tab">', fixed = TRUE)
  expect_match(html, paste0('<tr data-i="0"><th scope="row">Team 101</th><td class="num">1600,0</td>',
                            '<td class="num">1570,0</td><td class="num dneg">−30,0</td></tr>'), fixed = TRUE)
  expect_match(html, paste0('<tr data-i="1"><th scope="row">Team 104</th><td class="num">1450,0</td>',
                            '<td class="num">1492,0</td><td class="num dpos">+42,0</td></tr>'), fixed = TRUE)
})

test_that("Sonderzeichen im Vereinsnamen zerbrechen weder JSON noch Tabelle", {
  boese <- 'A&B "</script><b>x'
  ld <- list(bundesliga = verlauf_beispiel(namen = c(`101` = boese)))
  html <- gsv_seite(verlauf_site(ld), "bundesliga-verlauf")
  expect_false(grepl("</script><b>x", html, fixed = TRUE))
  expect_identical(gsv_json(html)$teams[[1]]$name, boese)
  expect_match(html, '<th scope="row">A&amp;B "&lt;/script&gt;&lt;b&gt;x</th>', fixed = TRUE)
  skripte <- regmatches(html, gregexpr("<script", html, fixed = TRUE))[[1]]
  enden <- regmatches(html, gregexpr("</script>", html, fixed = TRUE))[[1]]
  expect_identical(length(enden), length(skripte))
})

test_that("scheitert die Aufbereitung einer Liga, fehlen nur ihre Seite und ihr Link", {
  e <- verlauf_beispiel()
  e$tabelle$elo[e$tabelle$team_id == 104] <- 1500
  ziel <- environment()
  expect_warning(dir <- verlauf_site(list(bundesliga = e, zweite_bundesliga = verlauf_beispiel()), envir = ziel),
                 "ELO-Verlauf von Team 104")
  expect_false(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_false(grepl("bundesliga-verlauf.html", gsv_seite(dir, "index"), fixed = TRUE))
  expect_true(file.exists(file.path(dir, "2-bundesliga-verlauf.html")))
  expect_match(gsv_nav(gsv_seite(dir, "2-bundesliga-verlauf")), '<a href="index.html">Bundesliga</a>', fixed = TRUE)
})

test_that("vor dem ersten Spiel steht ein Hinweis statt des Diagramms, die Tabelle bleibt", {
  html <- gsv_seite(verlauf_site(list(bundesliga = verlauf_beispiel(leer = TRUE))), "bundesliga-verlauf")
  expect_match(html, '<p class="sectionlead" id="verlauf-leer">Die Saison hat noch nicht begonnen.</p>',
               fixed = TRUE)
  expect_false(grepl('id="verlauf-box"', html, fixed = TRUE))
  expect_match(html, '<table class="verlauf-tab" id="verlauf-tab">', fixed = TRUE)
})

test_that("Diagrammabschnitt: Umschalter, Diagrammflaeche, noscript-Hinweis", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, '<button type="button" data-mode="spiel" aria-pressed="true">', fixed = TRUE)
  expect_match(html, '<button type="button" data-mode="datum" aria-pressed="false">', fixed = TRUE)
  expect_match(html, 'id="verlauf-box"', fixed = TRUE)
  expect_match(html, 'id="verlauf-tip"', fixed = TRUE)
  expect_match(html, "<noscript>", fixed = TRUE)
})

test_that("der Hinweis nennt keine Modellkonstanten, sondern verlinkt die Methodik", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  hinweis <- sub('(?s).*<p class="hinweis">(.*?)</p>.*', "\\1", html, perl = TRUE)
  expect_match(hinweis, '<a href="methodik.html">Methodik</a>', fixed = TRUE)
  expect_false(grepl("Heimvorteil|k-Faktor|Tormodell", html))
})
