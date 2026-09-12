# Der Kuerzel-Vertrag als EINE Pruefung (Issues #195, #197, ADR 0007).
#
# Bis hierher gab es ihn dreimal, in drei Fassungen:
#
#   load_team_list()            je Liga + Ausnahme 83/84/85   -- die richtige
#   merge_league_files()        global, benennt still um      -- die gefaehrliche
#   validate_csv_data()         global, lehnt ab              -- die widerspruechliche
#
# Der Saisonwechsel setzt damit einen Vertrag durch, den der Loader seit
# PR #183 nicht mehr kennt. TeamList_2026 traegt rund vierzig absichtlich
# gleiche Kuerzel ueber Ligagrenzen (FCH, VFB, RWE, alle angeglichenen
# Frauen-Kuerzel); merge_league_files() wuerde sie beim naechsten Lauf zu
# "FC1", "VF1" umbenennen und Erfolg melden.
#
# Diese Datei beschreibt die gemeinsame Pruefung, auf die beide Seiten
# umgestellt werden. Sie bekommt einen fertigen data.frame statt eines
# Dateipfads -- nur so kann der Saisonwechsel sie auf seiner
# Zwischenrepraesentation aufrufen, bevor etwas geschrieben ist.

library(testthat)

lade_pruefung <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  env
}

mk_teams <- function(...) {
  zeilen <- list(...)
  data.frame(
    TeamID = vapply(zeilen, function(z) z[[1]], numeric(1)),
    ShortText = vapply(zeilen, function(z) z[[2]], character(1)),
    League = vapply(zeilen, function(z) z[[3]], character(1)),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------

test_that("pruefe_kuerzel_vertrag meldet nichts, wenn der Vertrag eingehalten ist", {
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "FCB", "78"),
    list(2, "BVB", "78"),
    list(3, "FCB", "82")   # Frauenteam desselben Vereins -- gewollt
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel in DERSELBEN Liga sind ein Verstoss", {
  # Der einzige Fall, der echten Schaden anrichtet: ShortText wird in
  # transform_data() zum Spaltennamen, eine Dopplung vertauscht Teams
  # stillschweigend.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "FCB", "78"),
    list(2, "FCB", "78")
  ))

  expect_length(verstoesse, 1L)
  expect_match(verstoesse[[1]], "FCB", fixed = TRUE)
  expect_match(verstoesse[[1]], "78", fixed = TRUE)
})

test_that("gleiche Kuerzel zwischen Maenner- und Frauenliga sind KEIN Verstoss", {
  # Ausdrueckliche Absicht (ADR 0007, CONTEXT.md): Derselbe Verein traegt
  # dasselbe Kuerzel, einschliesslich der "2"-Variante. In TeamList_2026
  # betrifft das ueber zwanzig Vereine.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "SGE", "78"),
    list(2, "SGE", "82"),
    list(3, "SGE2", "80"),
    list(4, "SGE2", "1034")
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel verschiedener Vereine in verschiedenen Ligen sind KEIN Verstoss", {
  # Die drei echten Faelle aus TeamList_2026, Entscheidung aus PR #186:
  # Wo ein Kuerzel fuer einen Verein eingefuehrt ist, bekommt er es.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "VFB", "78"),   # Stuttgart
    list(2, "VFB", "84"),   # Luebeck
    list(3, "FCH", "79"),   # Heidenheim
    list(4, "FCH", "80"),   # Hansa Rostock
    list(5, "RWE", "80"),   # Essen
    list(6, "RWE", "85")    # Erfurt
  ))

  expect_length(verstoesse, 0L)
})

test_that("gleiche Kuerzel zwischen Nord, Nordost und Bayern sind ein Verstoss", {
  # Lesbarkeitsregel: Zwei dieser drei Staffeln stehen jaehrlich gemeinsam
  # auf der Aufstiegsseite; dort waeren gleiche Kuerzel nicht zu
  # unterscheiden. Welche zwei es trifft, beschliesst das DFB-Praesidium
  # jaehrlich -- alle drei frei zu halten ist die einzige Fassung, die nicht
  # jedes Jahr nachgezogen werden muss.
  env <- lade_pruefung()

  for (paar in list(c("84", "83"), c("84", "85"), c("85", "83"))) {
    verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
      list(1, "SVA", paar[[1]]),
      list(2, "SVA", paar[[2]])
    ))
    expect_length(verstoesse, 1L)
    expect_match(verstoesse[[1]], "SVA", fixed = TRUE, info = paste(paar, collapse = "/"))
  }

  # Gegenprobe: West und SuedWest spielen die Aufstiegsspiele nie.
  expect_length(
    env$pruefe_kuerzel_vertrag(mk_teams(list(1, "SVA", "86"), list(2, "SVA", "87"))),
    0L
  )
})

test_that("doppelte TeamIDs sind ein Verstoss", {
  # Sie vervielfachen beim merge() die Spielzeilen -- ebenso still.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(7, "AAA", "78"),
    list(7, "BBB", "79")
  ))

  expect_length(verstoesse, 1L)
  expect_match(verstoesse[[1]], "7", fixed = TRUE)
})

test_that("ohne League-Spalte gilt die ganze Liste als eine Gruppe", {
  # TeamLists bis Saison 2025 kennen die Spalte nicht. Dort ist jede
  # Dopplung ein Verstoss -- mangels Information, ob sie erlaubt waere.
  env <- lade_pruefung()
  ohne <- data.frame(TeamID = c(1, 2), ShortText = c("FCB", "FCB"),
                     stringsAsFactors = FALSE)

  expect_length(env$pruefe_kuerzel_vertrag(ohne), 1L)
})

test_that("die Pruefung meldet ALLE Verstoesse, nicht nur den ersten", {
  # Sie speist den Konfliktbericht des Saisonwechsels (ADR 0007). Wer nach
  # jedem Fund abbricht, zwingt zu so vielen Laeufen, wie es Konflikte gibt.
  env <- lade_pruefung()

  verstoesse <- env$pruefe_kuerzel_vertrag(mk_teams(
    list(1, "AAA", "78"),
    list(2, "AAA", "78"),
    list(3, "BBB", "79"),
    list(4, "BBB", "79")
  ))

  expect_length(verstoesse, 2L)
})

# --- load_team_list() benutzt dieselbe Pruefung ----------------------------

test_that("load_team_list bricht weiterhin ab und nennt den Verstoss", {
  # Der Loader bleibt scharf: Was er heute ablehnt, lehnt er weiter ab --
  # nur eben ueber die gemeinsame Pruefung statt einer eigenen Kopie.
  env <- lade_pruefung()
  pfad <- withr::local_tempfile(fileext = ".csv")
  writeLines(c(
    "TeamID;ShortText;Promotion;InitialELO;League;Region;Name",
    "1;FCB;0;1500;78;;Team Eins",
    "2;FCB;0;1500;78;;Team Zwei"
  ), pfad)

  expect_error(env$load_team_list(pfad), "FCB")
})

test_that("die Fehlermeldung der 83/84/85-Regel nennt den richtigen Grund", {
  # KORRIGIERT (Issue #197): Hier stand, die Doppelsumme ordne ueber Namen
  # zu und ein doppeltes Kuerzel vertausche Teams. Das trifft nicht zu --
  # die beiden Staffeln liegen auf getrennten Achsen der p_sieg-Matrix.
  # Der Grund ist Lesbarkeit auf der gemeinsamen Aufstiegsseite.
  env <- lade_pruefung()
  pfad <- withr::local_tempfile(fileext = ".csv")
  writeLines(c(
    "TeamID;ShortText;Promotion;InitialELO;League;Region;Name",
    "1;SVA;0;1000;84;Nord;Team Eins",
    "2;SVA;0;1000;83;Bayern;Team Zwei"
  ), pfad)

  expect_error(env$load_team_list(pfad), "Aufstiegsseite")
  expect_error(env$load_team_list(pfad), "SVA")
})
