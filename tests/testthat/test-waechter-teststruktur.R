# Erzwingt die Namensregel aus tests/testthat/README.md:
# test-<einheit>[-<thema>].R, <einheit> = Stamm einer RCode-Datei oder festes Praefix.
# Ausnahme: eine Einheit gilt auch als gesourct, wenn die Datei eine Einheit nennt,
# die sie per source() mitlaedt (README, Abschnitt "Regel").

repo <- function(...) test_path("..", "..", ...)
praefixe <- c("scripts", "waechter")
einheiten <- sub("\\.R$", "", list.files(repo("RCode"), pattern = "\\.R$"))
skripte <- sub("\\.R$", "", basename(list.files(repo("scripts"), pattern = "\\.R$", recursive = TRUE)))
testdateien <- list.files(test_path(), pattern = "^test-.*\\.R$")
stamm <- sub("^test-", "", sub("\\.R$", "", testdateien))
einheit_von <- sub("-.*$", "", stamm)

test_that("jede Testdatei beginnt mit einer RCode-Einheit oder einem festen Praefix", {
  falsch <- testdateien[!einheit_von %in% c(einheiten, praefixe)]
  expect_identical(falsch, character(0))
})

test_that("test-scripts-* nennt ein existierendes Skript", {
  s <- stamm[einheit_von == "scripts"]
  skript <- sub("-.*$", "", sub("^scripts-", "", s))   # Thema abschneiden
  expect_identical(s[!skript %in% skripte], character(0))
})

test_that("kein Dateiname nennt Anlass, Phase oder Issue", {
  # ganze Segmente, damit test-fixture_cache.R nicht als "fix" gilt; keine
  # Ziffernregel -- sie traefe legitime Themen wie -liga1034, Issue-Nummern
  # faengt schon das Wort "issue"
  verboten <- "(^|-)(fix|move|haertung|issue|pr[0-9]+|phase[0-9]+)(-|$)"
  expect_identical(testdateien[grepl(verboten, stamm)], character(0))
})

test_that("jede Einheiten-Testdatei sourct ihre Einheit oder einen ihrer Lader", {
  # Lader-Karte: Einheit -> Menge der Einheiten, die ihre Datei per source()
  # direkt mitlaedt (Literal "<y>.R" in einer Zeile mit source(, Kommentare
  # vorher abgeschnitten).
  direkt_geladen <- function(e) {
    code <- sub("#.*$", "", readLines(repo("RCode", paste0(e, ".R")), warn = FALSE, encoding = "UTF-8"))
    zeilen <- code[grepl("source\\(", code)]
    # Literal "<y>.R" auch pfadqualifiziert erkennen (z.B. "RCode/rust_integration.R"):
    # Anfuehrungszeichen ODER Schraegstrich unmittelbar vor dem Namen.
    einheiten[vapply(einheiten, function(y) any(grepl(paste0("[/\"]", y, "\\.R\""), zeilen)), logical(1))]
  }
  direkt <- setNames(lapply(einheiten, direkt_geladen), einheiten)

  # lader_von(e): alle Einheiten, die e direkt oder ueber Zwischenstufen laden
  # (Rueckwaertssuche in der Lader-Karte, transitive Huelle).
  lader_von <- function(e) {
    besucht <- character(0)
    grenze <- e
    repeat {
      neu <- einheiten[vapply(einheiten, function(u) !u %in% besucht && any(grenze %in% direkt[[u]]), logical(1))]
      if (length(neu) == 0) break
      besucht <- union(besucht, neu)
      grenze <- neu
    }
    besucht
  }

  pruefen <- testdateien[einheit_von %in% einheiten]
  ohne <- pruefen[!vapply(seq_along(pruefen), function(i) {
    e <- einheit_von[testdateien == pruefen[i]]
    code <- sub("#.*$", "", readLines(test_path(pruefen[i]), warn = FALSE, encoding = "UTF-8"))
    kandidaten <- c(e, lader_von(e))
    any(vapply(kandidaten, function(k) {
      any(grepl(paste0("\\b", k, "\\.R\\b|source_module\\([^)]*\"", k, "\""), code, perl = TRUE))
    }, logical(1)))
  }, logical(1))]
  expect_identical(ohne, character(0))
})

test_that("kein Top-Level-Name ist in einer Testdatei doppelt definiert", {
  doppelt <- unlist(lapply(c(testdateien, list.files(test_path(), pattern = "^helper-.*\\.R$")), function(d) {
    ausdruecke <- parse(test_path(d), encoding = "UTF-8")
    namen <- unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
    if (any(duplicated(namen))) paste0(d, ": ", unique(namen[duplicated(namen)]))
  }))
  expect_identical(doppelt, NULL)
})

test_that("keine Helferdefinition steht in zwei helper-Dateien", {
  helfer <- list.files(test_path(), pattern = "^helper-.*\\.R$")
  namen <- unlist(lapply(helfer, function(d) {
    ausdruecke <- parse(test_path(d), encoding = "UTF-8")
    unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
  }))
  expect_identical(unique(namen[duplicated(namen)]), character(0))
})
