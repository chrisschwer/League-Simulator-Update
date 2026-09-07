library(testthat)

# Waechter fuer ADR 0002: Die Modellkonstanten leben im Rust-Server, nicht in R.
#
# Warum maschinell und nicht als Konvention: Der Nachtrag zu ADR 0002 haelt
# fest, dass genau diese Regel schon einmal unbemerkt gebrochen wurde -- der
# Heimvorteil stand zusaetzlich an vier Stellen in R und wurde bei JEDEM
# Aufruf mitgesendet, der Rust-Default griff nie. Dass Heatmap und
# 1/X/2-Werte trotzdem uebereinstimmten, lag allein daran, dass die beiden
# Werte zufaellig gleich waren. Ein Test wie dieser haette das sofort gezeigt.
#
# Die Gefahr ist nicht der falsche Wert, sondern der stille: Eine zweite
# Kopie faellt erst auf, wenn jemand die eine aendert und die andere nicht --
# und dann rechnen Prognose und Anzeige verschieden, ohne dass etwas
# fehlschlaegt.
#
# Erlaubt sind zwei Ausnahmen, beide bewusst und dokumentiert:
#
#   RCode/elo_calibration.R  -- Offline-Diagnostik. Der Kommentar dort sagt
#     es ausdruecklich: "Spiegel der Rust-Konstanten [...] Nur fuer die
#     Diagnostik hier -- der Produktivpfad liest sie nie von hier."
#
#   RCode/league_registry.R  -- Die Frauen-Konstanten. Sie sind KEINE Kopie
#     eines Rust-Defaults, sondern der Abweichungsfall aus ADR 0004: Rust
#     kennt nur das Herren-Tormodell, die Frauen-Werte muessen von R
#     gesendet werden. Ohne sie wuerden die Frauen-Ligen mit dem
#     Herren-Tormodell simuliert.
#
# Alles andere in RCode/ ist ein Verstoss. Wer eine weitere Ausnahme
# braucht, traegt sie hier mit Begruendung ein -- dann ist die Entscheidung
# sichtbar, statt in einer Datei zu verschwinden.

# Die Konstanten als Zeichenketten, wie sie im Code stehen wuerden. Bewusst
# nicht als Zahlen: Gesucht wird die literale Schreibweise, denn genau die
# waere eine Kopie.
MODELLKONSTANTEN <- c(
  herren_slope     = "0.0017854953143549",
  herren_intercept = "1.3218390804597700",
  frauen_slope     = "0.0024058833",
  frauen_intercept = "1.6527603153"
)

# Kuerzere Praefixe fangen auch abgeschnittene Schreibweisen (etwa
# 1.32183908 statt der vollen Stellenzahl) -- eine gerundete Kopie ist
# genauso eine Kopie, und sie waere sogar gefaehrlicher, weil sie zusaetzlich
# vom Original abweicht.
MODELLKONSTANTEN_PRAEFIX <- c("0.00178549", "1.32183908", "0.00240588", "1.65276031")

AUSNAHMEN <- c(
  "elo_calibration.R",  # Offline-Diagnostik, s. Kopfkommentar
  "league_registry.R"   # Frauen-Tormodell nach ADR 0004, s. Kopfkommentar
)

r_dateien <- function() {
  pfad <- test_path("..", "..", "RCode")
  dateien <- list.files(pfad, pattern = "\\.R$", full.names = TRUE)
  dateien[!basename(dateien) %in% AUSNAHMEN]
}

# Kommentarzeilen zaehlen nicht: Eine Konstante IM Kommentar ist eine
# Erklaerung, keine zweite Quelle. rust_integration.R nennt tore_slope
# beispielsweise im Kommentar zur jsonlite-Rundung -- das ist in Ordnung.
code_zeilen <- function(datei) {
  zeilen <- readLines(datei, warn = FALSE)
  ohne_kommentar <- sub("#.*$", "", zeilen)
  data.frame(
    nr = seq_along(zeilen),
    text = ohne_kommentar,
    stringsAsFactors = FALSE
  )
}

test_that("keine Tormodell-Konstante steht im R-Produktivpfad", {
  treffer <- character(0)

  for (datei in r_dateien()) {
    zeilen <- code_zeilen(datei)
    for (muster in c(MODELLKONSTANTEN, MODELLKONSTANTEN_PRAEFIX)) {
      gefunden <- grep(muster, zeilen$text, fixed = TRUE)
      for (i in gefunden) {
        treffer <- c(treffer, sprintf(
          "%s:%d  %s", basename(datei), zeilen$nr[i], trimws(zeilen$text[i])
        ))
      }
    }
  }

  expect_equal(
    unique(treffer), character(0),
    label = paste0(
      "Tormodell-Konstanten im R-Produktivpfad gefunden. Sie gehoeren in den ",
      "Rust-Server (ADR 0002); eine zweite Kopie laeuft frueher oder spaeter ",
      "auseinander, ohne dass etwas fehlschlaegt. Fundstellen"
    )
  )
})

test_that("der Waechter wuerde eine Kopie auch wirklich finden", {
  # Gegenprobe: Ohne sie wuesste niemand, ob der Test oben nur deshalb gruen
  # ist, weil das Suchmuster nicht greift. Genau diese Sorte falsch-gruener
  # Test hat in diesem Projekt schon zweimal einen echten Fehler verdeckt.
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(
    "lambda <- function(d) {",
    "  d * 0.0017854953143549 + 1.3218390804597700",
    "}"
  ), tmp)

  zeilen <- code_zeilen(tmp)
  gefunden <- vapply(
    MODELLKONSTANTEN,
    function(m) any(grepl(m, zeilen$text, fixed = TRUE)),
    logical(1)
  )

  expect_true(gefunden[["herren_slope"]])
  expect_true(gefunden[["herren_intercept"]])

  # Und ein Kommentar loest KEINEN Alarm aus -- sonst waere der Waechter
  # unbrauchbar, weil er jede Erklaerung im Code bestrafen wuerde.
  writeLines(c(
    "# Bei tore_slope (0.0024058833) waeren das 0,245 % Fehler.",
    "x <- 1"
  ), tmp)
  zeilen <- code_zeilen(tmp)
  expect_false(any(grepl("0.0024058833", zeilen$text, fixed = TRUE)))
})

test_that("die Ausnahmen sind noch das, wofuer sie erklaert wurden", {
  # Eine Ausnahme, die verschwindet oder ihren Zweck aendert, macht den
  # Waechter stillschweigend loechrig. Deshalb wird beides geprueft:
  # dass die Datei existiert, und dass sie die Konstanten wirklich fuehrt
  # (sonst ist der Eintrag ueberfluessig und gehoert entfernt).
  pfad <- test_path("..", "..", "RCode")

  kalibrierung <- file.path(pfad, "elo_calibration.R")
  expect_true(file.exists(kalibrierung))
  kal_text <- paste(readLines(kalibrierung, warn = FALSE), collapse = "\n")
  expect_match(kal_text, "0.0017854953143549", fixed = TRUE)
  # Der Kommentar, der die Ausnahme rechtfertigt, muss stehen bleiben.
  expect_match(kal_text, "Produktivpfad liest sie nie von hier")

  registry <- file.path(pfad, "league_registry.R")
  expect_true(file.exists(registry))
  reg_text <- paste(readLines(registry, warn = FALSE), collapse = "\n")
  expect_match(reg_text, "0.0024058833", fixed = TRUE)
})
