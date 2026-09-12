# Der Saisonwechsel muss das Siebenspalten-Format tragen (Issue #195, ADR 0007).
#
# Heute schreibt er vier Spalten. Die produktive TeamList_2026 hat sieben:
#
#   TeamID;ShortText;Promotion;InitialELO;League;Region;Name
#
# Ein Lauf 2026 -> 2027 verloere League, Region und Name -- und mit Region
# die gesamte Abstiegskopplung der Regionalligen (ADR 0006), weil
# rl_group_of_team() ohne sie NULL liefert und der Loop die RL-Spalten
# stillschweigend ueberspringt. Im --non-interactive-Modus ohne Rueckfrage.
#
# Der Verlust passiert an ZWEI Stellen, die gemeinsam zu aendern sind:
#   generate_league_csv()  schreibt die Zusatzspalten gar nicht erst
#   format_team_data()     schneidet sie am Ende wieder weg
#
# Woher die drei Werte kommen (Entscheidung Christoph):
#   League  aus der Liga-ID, die beim Schreiben der Ligadatei bekannt ist
#   Name    aus dem Team-Record, der ihn laengst fuehrt
#   Region  aus der Vorsaison -- und LEER, wo sie ihn nicht kennt. Der Lauf
#           erfindet keine Stammregion; betroffene Teams nennt der Bericht.

library(testthat)

lade_csv_generation <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  env
}

SPALTEN <- c("TeamID", "ShortText", "Promotion", "InitialELO",
             "League", "Region", "Name")

mk_daten <- function(n = 2L, league = "78", region = "", promotion = 0) {
  data.frame(
    TeamID = seq_len(n),
    ShortText = sprintf("T%02d", seq_len(n)),
    Promotion = promotion,
    InitialELO = 1500,
    League = league,
    Region = region,
    Name = sprintf("Verein %d", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------

test_that("format_team_data behaelt League, Region und Name", {
  env <- lade_csv_generation()

  ergebnis <- env$format_team_data(mk_daten())

  expect_named(ergebnis, SPALTEN)
  expect_identical(ergebnis$League, c("78", "78"))
  expect_identical(ergebnis$Name, c("Verein 1", "Verein 2"))
})

test_that("format_team_data kommt ohne die Zusatzspalten aus", {
  # TeamLists bis Saison 2025 kennen sie nicht. Der Saisonwechsel muss auch
  # dann laufen -- der Snapshot-Test faehrt genau diesen Fall (2024 -> 2025).
  env <- lade_csv_generation()
  alt <- mk_daten()[, c("TeamID", "ShortText", "Promotion", "InitialELO")]

  ergebnis <- env$format_team_data(alt)

  expect_true(all(c("TeamID", "ShortText", "Promotion", "InitialELO") %in% names(ergebnis)))
  expect_equal(nrow(ergebnis), 2L)
})

test_that("eine leere Region ist zulaessig, keine erfundene", {
  # Region kommt nur aus der Vorsaison. Kennt die sie nicht, bleibt sie leer
  # -- und das Team steht im Konfliktbericht. Eine aus der Liga-ID geratene
  # Stammregion waere schlimmer als eine fehlende: Sie saehe richtig aus.
  env <- lade_csv_generation()

  ergebnis <- env$format_team_data(mk_daten(region = ""))

  expect_identical(ergebnis$Region, c("", ""))
})

# --- Die Formatregel -------------------------------------------------------

test_that("validate_csv_data akzeptiert vierstellige Kurznamen", {
  # Die Regel ^[A-Z0-9]{2,3}$ lehnt SCPM, VFBO, WACA und HO2A ab. Heute
  # schuetzt dieser LAUTE Fehler zufaellig vor der STILLEN Umbenennung in
  # merge_league_files() -- wer nur das Format lockert, oeffnet sie. Beides
  # gehoert deshalb in denselben Schritt (Issue #195, Punkt 3).
  env <- lade_csv_generation()
  daten <- mk_daten(4L)
  daten$ShortText <- c("SCPM", "VFBO", "WACA", "HO2A")

  expect_true(env$validate_csv_data(daten)$valid)
})

test_that("validate_csv_data lehnt ungueltige R-Namen weiter ab", {
  # ShortText wird zum Spaltennamen; ein Ziffernanfang wird von R still zu
  # X186 umbenannt oder scheitert -- je nach check.names (Issue #181).
  env <- lade_csv_generation()
  daten <- mk_daten(1L)
  daten$ShortText <- "186"

  expect_false(env$validate_csv_data(daten)$valid)
})

test_that("validate_csv_data pruefT Kuerzel je Liga, nicht global", {
  # Dieselbe Regel wie load_team_list(): Ueber Ligagrenzen ist Gleichheit
  # erlaubt. Heute lehnt validate_csv_data() sie global ab -- und widerspricht
  # damit der Datei, die es schreiben soll.
  env <- lade_csv_generation()
  daten <- mk_daten(2L)
  daten$ShortText <- c("FCH", "FCH")
  daten$League <- c("79", "80")

  expect_true(env$validate_csv_data(daten)$valid)

  # Innerhalb einer Liga bleibt es scharf.
  daten$League <- c("79", "79")
  expect_false(env$validate_csv_data(daten)$valid)
})

# --- Der Zweitvertretungs-Malus (ADR 0008) ---------------------------------

test_that("apply_promotion_penalties ueberschreibt die gepflegte Spalte nicht mehr", {
  # Der Carryover uebernimmt promotion_value aus der Vorsaison
  # (team_record_builder.R:37) -- und apply_promotion_penalties kassierte die
  # Entscheidung danach wieder ein, ligaunabhaengig und anhand des
  # KURZNAMENS. Fuer die TeamList als gepflegtes Stammdatenblatt (ADR 0007)
  # ist das unhaltbar.
  env <- lade_csv_generation()
  daten <- mk_daten(2L, league = "87", promotion = 0)
  daten$ShortText <- c("BVB2", "S042")   # Zweitvertretungen in der RL West

  ergebnis <- env$apply_promotion_penalties(daten)

  # Regionalliga: kein Malus, solange die Erstvertretung nicht in Liga 80
  # spielt (Par. 55b Nr. 3.1). Beide Erstvertretungen spielen hoeher.
  expect_identical(ergebnis$Promotion, c(0, 0))
})

test_that("in der 3. Liga und der 2. Frauen-Bundesliga gilt der Malus pauschal", {
  # Wer dort steht, kaeme sonst eine Ebene hoeher -- die Sperre greift
  # unabhaengig davon, wo die Erstvertretung spielt.
  env <- lade_csv_generation()

  for (liga in c("80", "1034")) {
    daten <- mk_daten(1L, league = liga, promotion = 0)
    daten$ShortText <- "VFB2"
    expect_identical(env$apply_promotion_penalties(daten)$Promotion, -50,
                     info = liga)
  }
})

test_that("eine Erstvertretung mit Ziffernkuerzel bekommt keinen Malus", {
  # M05 (Mainz), S04 (Schalke), B04 (Leverkusen), H96 (Hannover) sind
  # Erstvertretungen. Die alte Heuristik brauchte dafuer eine handgepflegte
  # Ausnahmeliste (^M02$, ^S02$, ...); aus der Liga plus dem Suffix "2"
  # ergibt es sich von selbst.
  env <- lade_csv_generation()
  daten <- mk_daten(4L, league = "78", promotion = 0)
  daten$ShortText <- c("M05", "S04", "B04", "H96")

  expect_true(all(env$apply_promotion_penalties(daten)$Promotion == 0))
})
