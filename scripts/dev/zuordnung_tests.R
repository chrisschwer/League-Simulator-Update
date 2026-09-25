# Ordnet jeden test_that()-Block einer RCode-Einheit zu -- maschinell, als
# Vorschlag. Die Entscheidung trifft Christoph in der CSV (Spalte ziel_final).

funktionsindex <- function(rcode_dir = "RCode") {
  dateien <- list.files(rcode_dir, pattern = "\\.R$", full.names = TRUE)
  index <- list()
  for (f in dateien) {
    einheit <- sub("\\.R$", "", basename(f))
    zeilen <- readLines(f, warn = FALSE)
    treffer <- regmatches(zeilen, regexpr("^\\s*([.A-Za-z_][.A-Za-z0-9_]*)\\s*<-\\s*function", zeilen))
    namen <- sub("\\s*<-.*$", "", trimws(treffer))
    for (n in namen) index[[n]] <- einheit
  }
  index
}

# Alle Stringliterale "<name>.R" ausserhalb von Kommentaren, deren <name> ein
# RCode-Stamm ist -- deckt test_path(..., "x.R"), "../../RCode/x.R", rcode("x.R")
# und Dateilisten in for-Schleifen ab.
gesourcte_einheiten <- function(zeilen, einheiten) {
  code <- sub("#.*$", "", zeilen)
  treffer <- unlist(regmatches(code, gregexpr("[A-Za-z_]+\\.R\"", code)))
  namen <- unique(sub("\\.R\"$", "", treffer))
  namen[namen %in% einheiten]
}

# Direkte Aufrufe name(...) und indirekte ueber Stringliterale -- viele Tests
# rufen fn(env, "abstiegswahrscheinlichkeit")(...) oder get("name", env).
# stub(f, "g", ...) (mockery): g ist ein gestubbter Mitspieler und zaehlt
# nach der Zweifelsregel nicht; f ist die Funktion unter Test und zaehlt,
# obwohl sie ohne Klammer dasteht. env$f wird zu f.
STUB_MUSTER <- "stub\\(\\s*(?:[.A-Za-z_][.A-Za-z0-9_]*\\$)?([.A-Za-z_][.A-Za-z0-9_]*)\\s*,\\s*\"[^\"]*\""

gerufene_funktionen <- function(body, index) {
  stubs <- regmatches(body, gregexpr(STUB_MUSTER, body, perl = TRUE))[[1]]
  unter_test <- sub(STUB_MUSTER, "\\1", stubs, perl = TRUE)
  body <- gsub(STUB_MUSTER, "", body, perl = TRUE)
  direkt <- regmatches(body, gregexpr("[.A-Za-z_][.A-Za-z0-9_]*(?=\\()", body, perl = TRUE))[[1]]
  literal <- gsub("\"", "", regmatches(body, gregexpr("\"[.A-Za-z_][.A-Za-z0-9_]*\"", body))[[1]])
  kandidaten <- c(unter_test, direkt, literal)
  kandidaten[kandidaten %in% names(index)]
}

einheit_fuer <- function(funktionen, index) {
  if (length(funktionen) == 0) return(NA_character_)
  einheiten <- vapply(funktionen, function(f) index[[f]], character(1))
  names(sort(table(einheiten), decreasing = TRUE))[1]
}

einheit_fuer_block <- function(body, index) {
  if (grepl('readLines\\(.*RCode/', body) || grepl('readLines\\(.*tests/testthat/', body)) {
    return("waechter")
  }
  einheit_fuer(gerufene_funktionen(body, index), index)
}

testbloecke <- function(datei) {
  ausdruecke <- parse(datei, keep.source = TRUE, encoding = "UTF-8")
  quelle <- attr(ausdruecke, "srcref")
  bloecke <- list()
  for (i in seq_along(ausdruecke)) {
    e <- ausdruecke[[i]]
    if (is.call(e) && identical(e[[1]], as.name("test_that"))) {
      sr <- quelle[[i]]
      bloecke[[length(bloecke) + 1]] <- list(
        titel = as.character(e[[2]]),
        von = sr[1], bis = sr[3],
        body = paste(as.character(sr), collapse = "\n")
      )
    }
  }
  bloecke
}

zuordnung_schreiben <- function(ziel = "docs/plans/2026-09-15-testsuite-zuordnung.csv") {
  index <- funktionsindex()
  einheiten <- sub("\\.R$", "", list.files("RCode", pattern = "\\.R$"))
  dateien <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = TRUE)
  zeilen <- list()
  for (d in dateien) {
    src <- paste(gesourcte_einheiten(readLines(d, warn = FALSE, encoding = "UTF-8"), einheiten),
                 collapse = " ")
    for (b in testbloecke(d)) {
      fns <- gerufene_funktionen(b$body, index)
      vorschlag <- einheit_fuer_block(b$body, index)
      # ohne Funktionsstimme: die einzige gesourcte Einheit der Datei, falls eindeutig
      if (is.na(vorschlag) && nzchar(src) && !grepl(" ", src)) vorschlag <- src
      zeilen[[length(zeilen) + 1]] <- data.frame(
        datei_alt = basename(d), einheit_source = src, test_that_titel = b$titel,
        zeile_von = b$von, zeile_bis = b$bis,
        funktionen = paste(unique(fns), collapse = " "),
        einheit_vorschlag = vorschlag,
        ziel_final = "",
        bemerkung = if (!is.na(vorschlag) && nzchar(src) && !grepl(vorschlag, src, fixed = TRUE))
          "source und Funktionsstimme weichen ab" else "",
        stringsAsFactors = FALSE
      )
    }
  }
  tabelle <- do.call(rbind, zeilen)
  utils::write.csv(tabelle, ziel, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(tabelle)
}

if (sys.nframe() == 0) zuordnung_schreiben()
