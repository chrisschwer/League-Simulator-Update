library(testthat)

# Phase 3 baut den Shiny-Preview aus; lokale Vorschau ist künftig
# "Generator laufen lassen, HTML öffnen" via scripts/preview_site.R.

test_that("scripts/preview_site.R existiert und ist syntaktisch valide", {
  path <- test_path("..", "..", "scripts", "preview_site.R")
  expect_true(file.exists(path))
  expect_no_error(parse(path))
})

test_that("der Shiny-Preview ist ausgebaut", {
  expect_false(file.exists(test_path("..", "..", "ShinyApp", "app.R")))
  packagelist <- readLines(test_path("..", "..", "packagelist.txt"), warn = FALSE)
  expect_false(any(trimws(packagelist) == "shiny"))
})

# --- Phase 5: das Skript kennt alle zehn Ligen ------------------------------
#
# preview_site.R reichte nur vier Objekte durch (Ergebnis, Ergebnis2,
# Ergebnis3, Ergebnis3_Aufstieg) und rief generate_static_site() mit der
# alten Signatur. Seit Phase 2 nimmt der Generator die Liste `ergebnisse`,
# seit Phase 5 gibt es zehn Ligen -- eine Vorschau der Regionalliga-Seiten
# war ueber das Skript nicht zu bekommen.
#
# OBJEKTNAMEN in der Ergebnis-Datei: Das Skript liest ein save()-Image. Die
# Objekte heissen so, wie der Generator sie in seine data_env legt
# (.ergebnis_objektname(): die vier historischen Namen, sonst
# "Ergebnis_<schluessel>"). Die Tests leiten die Namen aus genau dieser
# Funktion ab, damit Skript und Generator nicht auseinanderlaufen.
#
# Die Tests fahren das Skript wirklich als Prozess (Rscript), mit
# absoluten Pfaden -- der Repo-Pfad enthaelt ein Leerzeichen, und genau
# daran ist das Skript schon einmal gescheitert.

skript_pfad <- function() {
  normalizePath(test_path("..", "..", "scripts", "preview_site.R"), mustWork = TRUE)
}

generator_modul <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

preview_ausfuehren <- function(fixture, outdir) {
  rscript <- Sys.which("Rscript")
  skip_if(!nzchar(rscript), "Rscript nicht im PATH")
  ausgabe <- suppressWarnings(system2(
    rscript, c(shQuote(skript_pfad()), shQuote(fixture), shQuote(outdir)),
    stdout = TRUE, stderr = TRUE
  ))
  status <- attr(ausgabe, "status")
  list(status = if (is.null(status)) 0L else as.integer(status),
       ausgabe = as.character(ausgabe))
}

html_lesen <- function(pfad) {
  paste(readLines(pfad, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

mk_prognose <- function(teams) {
  n <- length(teams)
  as.table(matrix(1 / n, n, n, dimnames = list(teams, as.character(seq_len(n)))))
}

# Ein save()-Image mit den Objekten aller zehn Ligen. Jede Liga hat eigene
# Teamnamen (Praefix je Liga), damit die gerenderten Seiten unterscheidbar
# sind; Nord bekommt fuer ein Team eine markante Abstiegswahrscheinlichkeit.
fixture_zehn_ligen <- function(pfad, nord_abstieg_t1 = 0.37) {
  objektname <- generator_modul()$.ergebnis_objektname
  groesse <- c(
    bundesliga = 18L, zweite_bundesliga = 18L, dritte_liga = 20L,
    frauen_bundesliga = 14L, zweite_frauen_bundesliga = 14L,
    rl_nord = 18L, rl_nordost = 18L, rl_west = 18L, rl_suedwest = 18L,
    rl_bayern = 19L
  )
  praefix <- c(
    bundesliga = "BL", zweite_bundesliga = "ZB", dritte_liga = "DL",
    frauen_bundesliga = "FB", zweite_frauen_bundesliga = "ZF",
    rl_nord = "NORD", rl_nordost = "NOST", rl_west = "WEST",
    rl_suedwest = "SUWE", rl_bayern = "BAYE"
  )
  teams_von <- function(key) sprintf("%s%02d", praefix[[key]], seq_len(groesse[[key]]))

  env <- new.env()
  ablegen <- function(key, obj) assign(objektname(key), obj, envir = env)
  for (key in names(groesse)) ablegen(key, mk_prognose(teams_von(key)))
  ablegen("dritte_liga_aufstieg", mk_prognose(teams_von("dritte_liga")))
  ablegen("zweite_frauen_bundesliga_aufstieg", mk_prognose(teams_von("zweite_frauen_bundesliga")))
  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest", "rl_bayern")) {
    teams <- teams_von(key)
    n <- length(teams)
    ablegen(paste0(key, "_abstieg"), if (identical(key, "rl_bayern")) {
      data.frame(Relegation = rep(2 / n, n), Abstieg = rep(2 / n, n), row.names = teams)
    } else {
      data.frame(Abstieg = rep(3 / n, n), row.names = teams)
    })
  }
  for (key in c("rl_nord", "rl_bayern")) {
    teams <- teams_von(key)
    ablegen(paste0(key, "_aufstieg"),
            data.frame(Aufstieg = rep(0.5 / length(teams), length(teams)), row.names = teams))
  }
  nord_abstieg <- get(objektname("rl_nord_abstieg"), envir = env)
  nord_abstieg$Abstieg[1] <- nord_abstieg_t1
  ablegen("rl_nord_abstieg", nord_abstieg)

  save(list = ls(env), envir = env, file = pfad)
  invisible(ls(env))
}

ALLE_SEITEN <- c("index", "2-bundesliga", "3-liga", "frauen-bundesliga",
                 "2-frauen-bundesliga", "rl-nord", "rl-nordost", "rl-west",
                 "rl-suedwest", "rl-bayern", "rl-aufstieg", "methodik")
NEUE_SEITEN <- setdiff(ALLE_SEITEN, c("index", "2-bundesliga", "3-liga", "methodik"))

test_that("preview_site.R reicht die Objekte aller zehn Ligen durch -- die RL-Seiten entstehen", {
  fixture <- withr::local_tempfile(fileext = ".Rds")
  out <- withr::local_tempdir()
  objekte <- fixture_zehn_ligen(fixture)
  # Harness-Probe: Die Fixture traegt wirklich mehr als die vier alten Objekte.
  expect_true(all(c("Ergebnis", "Ergebnis3_Aufstieg", "Ergebnis_rl_nord",
                    "Ergebnis_rl_nord_abstieg", "Ergebnis_rl_nord_aufstieg") %in% objekte))

  lauf <- preview_ausfuehren(fixture, out)
  expect_identical(lauf$status, 0L, info = paste(lauf$ausgabe, collapse = "\n"))

  for (slug in ALLE_SEITEN) {
    expect_true(file.exists(file.path(out, paste0(slug, ".html"))),
                info = sprintf("%s.html fehlt -- das Skript reicht nur die vier alten Objekte durch", slug))
  }
  # Der gedruckte Pfad ist der Einstieg der Vorschau.
  expect_true(file.path(out, "index.html") %in% lauf$ausgabe)

  nord <- file.path(out, "rl-nord.html")
  if (!file.exists(nord)) return(invisible(NULL))
  html <- html_lesen(nord)
  expect_match(html, "Saisonprognose Regionalliga Nord", fixed = TRUE)
  # Die Werte der Fixture, nicht irgendeine Nord-Seite: das Team der Fixture
  # mit seiner markanten Abstiegswahrscheinlichkeit (37 %).
  expect_match(html, "<th scope=\"row\">NORD01</th>", fixed = TRUE)
  expect_match(html, "NORD01</th><td>37</td>", fixed = TRUE)
  # Und die Altliga-Seite traegt weiterhin ihre eigenen Teams.
  expect_match(html_lesen(file.path(out, "index.html")), "<th scope=\"row\">BL01</th>", fixed = TRUE)
})

test_that("eine alte Fixture mit nur vier Objekten rendert weiterhin (ShinyApp/data/Ergebnis.Rds)", {
  fixture <- test_path("..", "..", "ShinyApp", "data", "Ergebnis.Rds")
  skip_if_not(file.exists(fixture), "ShinyApp/data/Ergebnis.Rds fehlt (gitignored, nur lokal)")
  fixture <- normalizePath(fixture, mustWork = TRUE)
  # Harness-Probe: Es ist wirklich die alte Form -- genau die vier Objekte.
  alt <- new.env()
  load(fixture, envir = alt)
  expect_setequal(ls(alt), c("Ergebnis", "Ergebnis2", "Ergebnis3", "Ergebnis3_Aufstieg"))
  out <- withr::local_tempdir()

  lauf <- preview_ausfuehren(fixture, out)
  expect_identical(lauf$status, 0L, info = paste(lauf$ausgabe, collapse = "\n"))

  for (slug in c("index", "2-bundesliga", "3-liga", "methodik")) {
    expect_true(file.exists(file.path(out, paste0(slug, ".html"))), info = slug)
  }
  # Keine Seite fuer Ligen, die die Fixture nicht kennt.
  for (slug in NEUE_SEITEN) {
    expect_false(file.exists(file.path(out, paste0(slug, ".html"))), info = slug)
  }
  expect_true(file.path(out, "index.html") %in% lauf$ausgabe)
  # Die Seite zeigt die Teams der Fixture.
  html <- html_lesen(file.path(out, "index.html"))
  expect_match(html, paste0("<th scope=\"row\">", rownames(alt$Ergebnis)[1], "</th>"), fixed = TRUE)
})

test_that("eine fehlende Ergebnis-Datei bricht mit klarer Meldung ab, nicht mit einem R-Fehler", {
  fehlt <- file.path(withr::local_tempdir(), "gibt-es-nicht.Rds")
  out <- withr::local_tempdir()

  lauf <- preview_ausfuehren(fehlt, out)
  expect_false(identical(lauf$status, 0L), info = "das Skript endete trotz fehlender Datei mit Status 0")
  meldung <- paste(lauf$ausgabe, collapse = "\n")
  expect_match(meldung, "preview_site: Ergebnis-Datei nicht gefunden", fixed = TRUE)
  expect_match(meldung, "gibt-es-nicht.Rds", fixed = TRUE)
  expect_false(file.exists(file.path(out, "index.html")))
})
