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

# --- aus test-frauen-ligen-aktivierung.R ---
test_that("die Fenstergrenzen stehen nur in den Konstanten", {
  # Vorher standen 14:45 und 22:45 an neun Stellen in updateScheduler.R --
  # als Zahl, in Kommentaren und in Meldungstexten. Eine Verschiebung musste
  # alle treffen; eine vergessene Stelle waere nicht aufgefallen.
  #
  # Geprueft wird die AUSSAGE, nicht eine Anzahl: Die alten Uhrzeiten kommen
  # nirgends mehr vor, und die neuen Grenzen stehen als benannte Konstanten.
  code <- readLines(test_path("..", "..", "RCode", "updateScheduler.R"))

  expect_false(any(grepl("14:45|22:45", code)))
  expect_false(any(grepl("14 \\* 60|22 \\* 60", code)))

  # Die Meldungstexte bauen die Uhrzeit aus den Konstanten, statt sie zu
  # wiederholen.
  konstanten <- grep("SCHEDULE_(START|END)_MINUTES *<-", code, value = TRUE)
  expect_length(konstanten, 2)
})

# --- aus test-kuerzel-tooltip.R ---
test_that("das Stylesheet kennt Kuerzel und Tipp-Label", {
  css <- paste(readLines(test_path("..", "..", "RCode", "site_assets", "site.css")),
               collapse = "\n")
  expect_match(css, "abbr.kz", fixed = TRUE)
  expect_match(css, ".kz-tip", fixed = TRUE)
})

# --- aus test-ein-elo-walk.R ---
# Der zweite ELO-Walk (calculate_elo_update() und Co., Issue #146 Teil 2)
# darf nicht wiederkehren.

# =============================================================================
# 4. Die Abwesenheit -- damit der zweite Walk nicht still zurueckkehrt
# =============================================================================

test_that("der zweite ELO-Walk existiert nicht mehr", {
  # DER WACHHUND. Ohne diesen Test koennte jemand calculate_elo_update()
  # spaeter "zur Sicherheit" wieder einfuehren -- etwa als vermeintlich
  # harmlosen Offline-Helfer -- und damit die zweite Physik zurueckholen, die
  # Teil 2 gerade beseitigt hat. Das faellt an keiner anderen Stelle auf:
  # Zwei ELO-Implementierungen widersprechen sich nur in den Zahlen, nie im
  # Typ.
  #
  # helper-test-setup.R sourct alle Dateien aus RCode/ in die globale
  # Umgebung, bevor irgendein Test laeuft. exists() sieht hier also genau
  # das, was das Repo definiert.
  expect_false(exists("calculate_elo_update"),
               info = "calculate_elo_update war der R-Walk mit home_advantage = 100 (Issue #146, Teil 2)")
  expect_false(exists("update_elos_for_match"),
               info = "update_elos_for_match war der Schleifenkoerper des geloeschten R-Walks")

  # UEBERNOMMEN aus test-elo-aggregation-engine-selection.R, die mit Teil 2
  # entfaellt.
  #
  # Diese Datei war der Wachhund der VORIGEN Bereinigung: Issue #102 loeschte
  # die kompilierte C++-Engine und legte elo_aggregation.R auf den reinen
  # R-Pfad fest. Sie hielt fest, dass SpielNichtSimulieren() nicht
  # zurueckkehrt -- und zugleich, dass calculate_elo_update() EXISTIERT.
  #
  # Genau dieser zweite Satz ist heute falsch: Teil 2 loescht die Funktion, die
  # #102 als tragend festgeschrieben hat. Beide Saetze in derselben Suite
  # stehen zu lassen hiesse, eine Datei zu behalten, die der anderen
  # widerspricht -- deshalb wandert der noch gueltige Teil hierher und die
  # alte Datei entfaellt (Entscheidung Christoph).
  #
  # Die Linie ist damit durchgehend: erst raus die C++-Engine, jetzt raus der
  # zweite R-Walk. Uebrig bleibt EINE Implementierung, und die steht in Rust.
  expect_false(exists("SpielNichtSimulieren"),
               info = "SpielNichtSimulieren war die C++-Engine, geloescht in Issue #102")
})

# =============================================================================
# 5. Der Heimvorteil 100 ist aus dem Repo verschwunden
# =============================================================================

test_that("kein Produktivcode setzt einen Heimvorteil von 100", {
  # DIE EIGENTLICHE ZUSICHERUNG DES GANZEN VORHABENS, als Textpruefung.
  #
  # Warum als Grep und nicht ueber einen Funktionsaufruf: Nach der Loeschung
  # gibt es keine R-Funktion mehr, die man auf ihren Heimvorteil befragen
  # koennte. Der Wert kann aber jederzeit als Literal irgendwo wieder
  # auftauchen -- in einem Skript, einem neuen Helfer, einer Kopie der alten
  # Formel. Genau das soll auffallen.
  #
  # Gesucht wird die ZUWEISUNG (`home_advantage <- 100`, `home_advantage =
  # 100`), nicht die Zahl 100 an sich. Kommentare und Dokumentation, die den
  # historischen Wert nennen, sind ausdruecklich erlaubt und sollen es
  # bleiben: Sie erklaeren, warum es ihn nicht mehr gibt.
  wurzel <- normalizePath("../..")
  dateien <- c(
    list.files(file.path(wurzel, "RCode"), pattern = "\\.R$", full.names = TRUE),
    list.files(file.path(wurzel, "scripts"), pattern = "\\.R$", full.names = TRUE)
  )

  treffer <- character(0)
  for (datei in dateien) {
    zeilen <- readLines(datei, warn = FALSE)
    # Kommentarzeilen ausklammern -- der Fund soll Code sein, nicht Prosa.
    code <- zeilen[!grepl("^\\s*#", zeilen)]
    verdacht <- grep("home_advantage\\s*(<-|=)\\s*100\\b", code, value = TRUE)
    if (length(verdacht) > 0) {
      treffer <- c(treffer, paste0(basename(datei), ": ", verdacht))
    }
  }

  expect_equal(treffer, character(0),
               info = paste("home_advantage = 100 ist die zweite ELO-Physik",
                            "(Issue #146, Teil 2). Fundstellen:",
                            paste(treffer, collapse = " | ")))
})

test_that("der einzige Heimvorteil in R ist der der Kalibrierung, und er ist 40", {
  # Positivseite derselben Zusicherung. HOME_ADVANTAGE_MODEL
  # (elo_calibration.R:23) ist der einzige Heimvorteil, der in R ueberhaupt
  # noch als Zahl steht -- und er beschreibt ausdruecklich den Rust-Default,
  # damit die Offline-Kalibrierung dieselbe Physik rechnet wie die Prognose.
  #
  # Der Test bindet die beiden aneinander: Wer den Rust-Default aendert, ohne
  # hier nachzuziehen, bekommt eine Kalibrierung, die etwas anderes misst als
  # das, was laeuft. (Der Rust-Wert steht in
  # league-simulator-rust/src/models/mod.rs und in CLAUDE.md.)
  expect_true(exists("HOME_ADVANTAGE_MODEL"))
  expect_equal(HOME_ADVANTAGE_MODEL, 40)
})

# --- aus test-phase5-regionalligen.R ---
test_that("die Aufstiegsseite verdrahtet keine Staffelnamen im Renderer", {
  # Maschineller Schutz gegen die Falle: Stuende "Bayern" oder "Nord" als
  # Playoff-Paarung im Seitengenerator, waere die Seite ab 2027/28 lautlos
  # falsch. Die Namen duerfen dort nur als Anzeigetext vorkommen, nicht als
  # Bedingung.
  #
  # Geprueft wird der Code OHNE Kommentare -- ein Staffelname im Kommentar
  # ist eine Erklaerung, keine Verdrahtung.
  # Seit #211 liegen die Sektionsrenderer in render_sections.R -- beide lesen.
  code <- unlist(lapply(c("generate_static_site.R", "render_sections.R"), function(datei)
    readLines(test_path("..", "..", "RCode", datei))))
  code <- sub("#.*$", "", code)

  for (muster in c('"Bayern"\\s*(==|%in%)', '(==|%in%)\\s*c?\\(?"Bayern"',
                   '"Nord"\\s*(==|%in%)', '(==|%in%)\\s*c?\\(?"Nord"')) {
    expect_false(any(grepl(muster, code)), info = muster)
  }
})
