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

# --- Der Weg durch den Saisonwechsel ---------------------------------------
#
# Die beiden Tests oben pruefen format_team_data() -- das ENDE der Kette.
# Sie war schon richtig: format_team_data() reicht League, Region und Name
# durch, WENN es sie bekommt. Es bekam sie nie, weil generate_league_csv()
# nur vier Spalten schreibt (season_processor.R:302-306) und
# merge_league_files() bloss Zeilen zusammenbindet.
#
# Diese Tests fahren deshalb die Kette selbst: process_league_teams() ->
# generate_league_csv() -> die Ligadatei auf der Platte.

lade_saisonwechsel <- function() {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "transform_data.R"), local = env)
  source(test_path("..", "..", "RCode", "api_service.R"), local = env)
  source(test_path("..", "..", "RCode", "team_data_carryover.R"), local = env)
  source(test_path("..", "..", "RCode", "team_history_resolver.R"), local = env)
  source(test_path("..", "..", "RCode", "team_record_builder.R"), local = env)
  source(test_path("..", "..", "RCode", "csv_generation.R"), local = env)
  source(test_path("..", "..", "RCode", "season_processor.R"), local = env)
  env
}

# Vorsaison-TeamList im Siebenspalten-Format, wie TeamList_2026 sie hat.
vorsaison <- function() {
  data.frame(
    TeamID = c(158, 9369, 777),
    ShortText = c("F95", "FO2", "NEU"),
    Promotion = c(0, -50, 0),
    InitialELO = c(1343.5, 987.9, 1500),
    League = c("80", "87", "87"),
    Region = c("West", "West", ""),
    Name = c("Fortuna Duesseldorf", "Fortuna Duesseldorf II", "Ohne Region"),
    stringsAsFactors = FALSE
  )
}

# API-Antwort: dieselben Teams plus einen echten Neuzugang.
api_teams <- function() {
  list(
    list(id = 158, name = "Fortuna Duesseldorf", is_second_team = FALSE),
    list(id = 9369, name = "Fortuna Duesseldorf II", is_second_team = TRUE),
    list(id = 4242, name = "Aufsteiger SV", is_second_team = FALSE)
  )
}

test_that("die Ligadatei traegt sieben Spalten mit League, Region und Name", {
  env <- lade_saisonwechsel()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("RCode")

  teams <- env$process_league_teams(
    api_teams(), "87", "2027",
    final_elos = data.frame(TeamID = numeric(0), FinalELO = numeric(0)),
    liga3_baseline = 1300,
    previous_team_list = vorsaison(),
    prompt_fn = function(name, liga, belegt, baseline, retry_count = 0) {
      list(short_name = "AUF", initial_elo = 1200, promotion_value = 0)
    }
  )

  pfad <- env$generate_league_csv(teams, "87", "2027")
  geschrieben <- utils::read.csv(pfad, sep = ";", stringsAsFactors = FALSE,
                                 colClasses = "character")

  expect_named(geschrieben, SPALTEN)

  # League ist die Liga, die gerade verarbeitet wird -- sie steht beim
  # Schreiben der Ligadatei fest und kommt NICHT aus der Vorsaison. Genau
  # darin liegt der Auf- und Abstieg: F95 stand dort in Liga 80.
  expect_equal(unique(geschrieben$League), "87")

  # Region und Name aus der Vorsaison, wo sie dort bekannt sind.
  zeile <- function(id) geschrieben[geschrieben$TeamID == id, ]
  expect_equal(zeile(158)$Region, "West")
  expect_equal(zeile(158)$Name, "Fortuna Duesseldorf")
  expect_equal(zeile(9369)$Region, "West")
})

test_that("ein Neuzugang bekommt eine leere Region, keine geratene", {
  # Region laesst sich nicht herleiten -- weder API noch Team-Record fuehren
  # sie, einzige Quelle ist das Offline-Kalibrierungsskript (ADR 0003). Eine
  # aus der Liga-ID geratene Stammregion waere schlimmer als eine fehlende,
  # weil sie richtig aussaehe (Entscheidung aus PR #199).
  env <- lade_saisonwechsel()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("RCode")

  teams <- env$process_league_teams(
    api_teams(), "87", "2027",
    final_elos = data.frame(TeamID = numeric(0), FinalELO = numeric(0)),
    liga3_baseline = 1300,
    previous_team_list = vorsaison(),
    prompt_fn = function(name, liga, belegt, baseline, retry_count = 0) {
      list(short_name = "AUF", initial_elo = 1200, promotion_value = 0)
    }
  )

  pfad <- env$generate_league_csv(teams, "87", "2027")
  geschrieben <- utils::read.csv(pfad, sep = ";", stringsAsFactors = FALSE,
                                 colClasses = "character")

  neu <- geschrieben[geschrieben$TeamID == "4242", ]
  expect_equal(neu$Region, "")
  # Der Name kommt dagegen aus der API-Antwort und ist da.
  expect_equal(neu$Name, "Aufsteiger SV")
})

test_that("eine vierspaltige Vorsaison laesst Region leer, ohne zu scheitern", {
  # Der Snapshot-Lauf 2024 -> 2025 faehrt genau diesen Fall: Seine Eingabe
  # TeamList_2024.csv hat vier Spalten. League und Name entstehen trotzdem
  # (Liga-ID und API-Antwort), Region bleibt leer.
  env <- lade_saisonwechsel()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("RCode")

  alt <- vorsaison()[, c("TeamID", "ShortText", "Promotion", "InitialELO")]

  teams <- env$process_league_teams(
    api_teams(), "87", "2027",
    final_elos = data.frame(TeamID = numeric(0), FinalELO = numeric(0)),
    liga3_baseline = 1300,
    previous_team_list = alt,
    prompt_fn = function(name, liga, belegt, baseline, retry_count = 0) {
      list(short_name = "AUF", initial_elo = 1200, promotion_value = 0)
    }
  )

  pfad <- env$generate_league_csv(teams, "87", "2027")
  geschrieben <- utils::read.csv(pfad, sep = ";", stringsAsFactors = FALSE,
                                 colClasses = "character")

  expect_named(geschrieben, SPALTEN)
  expect_equal(unique(geschrieben$Region), "")
  expect_equal(unique(geschrieben$League), "87")
})

test_that("eine leere Region ueberlebt den Merge als leer, nicht als NA", {
  # Die Ligadateien gehen ueber die Platte: generate_league_csv() schreibt
  # sie, merge_league_files() liest sie zurueck. read.csv() macht aus einem
  # leeren Feld dabei ein NA -- und das landete als Zeichenkette "NA" in der
  # Region-Spalte der TeamList.
  #
  # Das ist genau der stille Schaden, den Issue #195 beschreibt, nur eine
  # Ebene tiefer: staffel_index() kennt "NA" nicht und brueche ab, waehrend
  # eine leere Region sauber dazu fuehrt, dass die Zuordnung entfaellt.
  env <- lade_saisonwechsel()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("RCode")

  teams <- list(
    list(id = 1, name = "Ohne Region", short_name = "AAA",
         initial_elo = 1500, promotion_value = 0, region = ""),
    list(id = 2, name = "Mit Region", short_name = "BBB",
         initial_elo = 1500, promotion_value = 0, region = "West")
  )
  ligadatei <- env$generate_league_csv(teams, "87", "2027")

  geschrieben <- NULL
  mockery::stub(env$merge_league_files, "generate_team_list_csv",
                function(data, season, output_dir = "RCode") {
                  geschrieben <<- data
                  file.path(dir, "TeamList_2027.csv")
                })
  env$merge_league_files(ligadatei, "2027")

  expect_false(anyNA(geschrieben$Region))
  expect_identical(geschrieben$Region[geschrieben$TeamID == 1], "")
  expect_identical(geschrieben$Region[geschrieben$TeamID == 2], "West")
})

test_that("eine durchweg leere Region wird nicht zur logical-Spalte", {
  # Der gefaehrlichere Fall, und der des Snapshot-Laufs 2024 -> 2025: Ist
  # die Spalte GANZ leer, raet read.csv() nicht "character mit Leerstrings",
  # sondern logical -- und jede Zeile wird zu NA. Beim Schreiben steht dann
  # "NA" in der Region-Spalte der TeamList.
  #
  # Das sieht aus wie eine Stammregion und ist keine: staffel_index()
  # brueche daran ab, waehrend die leere Region den vorgesehenen Weg geht
  # (rl_group_of_team() liefert NULL, die Kopplung entfaellt sichtbar).
  env <- lade_saisonwechsel()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("RCode")

  teams <- list(
    list(id = 1, name = "Ohne Region", short_name = "AAA",
         initial_elo = 1500, promotion_value = 0, region = ""),
    list(id = 2, name = "Auch ohne", short_name = "BBB",
         initial_elo = 1500, promotion_value = 0, region = "")
  )
  ligadatei <- env$generate_league_csv(teams, "87", "2027")

  geschrieben <- NULL
  mockery::stub(env$merge_league_files, "generate_team_list_csv",
                function(data, season, output_dir = "RCode") {
                  geschrieben <<- data
                  file.path(dir, "TeamList_2027.csv")
                })
  env$merge_league_files(ligadatei, "2027")

  expect_type(geschrieben$Region, "character")
  expect_identical(geschrieben$Region, c("", ""))
})
