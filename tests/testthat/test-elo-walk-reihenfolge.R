# Issue #146, Teil 1: Der ELO-Walk muss die Spiele in der Reihenfolge sehen,
# in der sie STATTGEFUNDEN haben -- nicht in der, in der api-football sie
# ausliefert.
#
# WARUM DAS UEBERHAUPT EIN PROBLEM IST: Der Rust-Walk verarbeitet den
# Spielplan in Listenreihenfolge. Solange die API nach Spieltag sortiert
# liefert, faellt das nicht auf. Bei einem NACHHOLSPIEL faellt es auf: Ein
# verlegtes Spiel des 5. Spieltags, tatsaechlich ausgetragen zwischen dem
# 13. und dem 14., wandert in der Liste an den Platz des 5. Spieltags. Der
# Walk verrechnet es dort -- mit ELO-Staenden, die zum Zeitpunkt des Spiels
# noch gar nicht galten -- und schreibt die Runden 6 bis 13 anschliessend mit
# leicht falschen Werten fort.
#
# Der R-Walk (elo_aggregation.R:96) sortiert laengst chronologisch. Nur die
# beiden Payload-Bauer tun es nicht. Entscheidung aus dem Design vom
# 12.09.2026: R sortiert, Rust bleibt unveraendert -- kein neues Payload-Feld,
# keine Schnittstellenaenderung. Die Anstosszeit liegt R ohnehin vor.
#
# SORTIERSCHLUESSEL: Anstosszeit aufsteigend, bei Gleichstand die bestehende
# OriginalOrder (die API-Reihenfolge). Bei identischer Anstosszeit spielen
# verschiedene Teams; fuers ELO-Ergebnis ist die Reihenfolge dort gleichgueltig
# -- sie muss nur DETERMINISTISCH sein, damit sich Prognosen nicht zwischen
# zwei Laeufen ueber dieselbe Eingabe bewegen.
#
# DIE STELLE, AN DER ES STILL SCHIEFGEHT -- und der eigentliche Grund fuer
# diese Datei:
#
# transform_data() haengt an den zurueckgegebenen data.frame ein Attribut
# `elo_neutral` (transform_data.R:298). Dieser logische Vektor reist
# ZEILENGLEICH mit; rust_integration.R:237 liest ihn und reicht ihn an die
# Engine (Issue #157: am gruenen Tisch gewertete Spiele -- AWD, WO -- zaehlen
# fuer die Endtabelle, duerfen die Staerkeschaetzung aber nicht bewegen).
#
# Das Attribut ist an nichts gekoppelt ausser an die Zeilenposition. Wer die
# Zeilen umsortiert und den Vektor stehen laesst, laesst den ELO-Walk die
# FALSCHEN Spiele ueberspringen: ein regulaer gespieltes Spiel faellt aus der
# Staerkeschaetzung, ein gewertetes geht hinein. Ohne Fehlermeldung, ohne
# Warnung, ohne dass irgendeine Spaltenpruefung anschlaegt. Der Test
# "elo_neutral wandert mit" unten ist die einzige Stelle, die das faengt.

library(testthat)

source("../../RCode/transform_data.R")
source("../../RCode/league_details.R")

# --- Fixture-Bau --------------------------------------------------------------
#
# Bewusst im GENESTETEN Format (List-Columns einzeiliger data.frames), weil
# beide Produktivfunktionen dieses Format ausdruecklich unterstuetzen und die
# bestehenden Tests es durchgaengig benutzen (siehe helper-fixtures.R:
# create_test_fixtures_api). Kein neues Fixture-Muster erfinden.
#
# Gegenueber create_test_fixtures_api() kommen zwei Felder dazu, die es dort
# nicht braucht, hier aber den ganzen Testgegenstand ausmachen: `date` (der
# Sortierschluessel) und `league$round` (damit der Rundenfilter greift und
# extract_fixture_details() die Runde ableiten kann).

# Ein Spiel als Liste der vier List-Column-Bausteine.
ewr_spiel <- function(fixture_id, datum, status, heim_id, gast_id,
                      tore_heim = NA_real_, tore_gast = NA_real_,
                      runde = 1L) {
  list(
    teams = data.frame(
      home = I(list(data.frame(id = heim_id, name = paste("Team", heim_id)))),
      away = I(list(data.frame(id = gast_id, name = paste("Team", gast_id))))
    ),
    goals = data.frame(home = tore_heim, away = tore_gast),
    fixture = data.frame(
      id = fixture_id,
      date = datum,
      status = I(list(data.frame(short = status)))
    ),
    league = data.frame(round = paste("Regular Season -", runde))
  )
}

# Aus mehreren ewr_spiel()-Ergebnissen den fixtures-Tibble bauen, wie ihn
# retrieveResults() liefert.
ewr_fixtures <- function(...) {
  spiele <- list(...)
  tibble::tibble(
    teams   = lapply(spiele, `[[`, "teams"),
    goals   = lapply(spiele, `[[`, "goals"),
    fixture = lapply(spiele, `[[`, "fixture"),
    league  = lapply(spiele, `[[`, "league")
  )
}

# Vier Teams, Kurznamen wie in helper-fixtures.R.
ewr_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("TEA", "TEB", "TEC", "TED"),
    InitialELO = c(1500, 1450, 1550, 1400),
    stringsAsFactors = FALSE
  )
}

# Paarung je Zeile als "HEIM-GAST" -- kompakter zu lesen als zwei Vektoren,
# und die Reihenfolge ist genau das, was diese Tests pruefen.
ewr_paarungen <- function(df) paste(df$TeamHeim, df$TeamGast, sep = "-")


# --- transform_data(): chronologische Sortierung ------------------------------

test_that("transform_data sortiert ein Nachholspiel chronologisch ein", {
  # Der Kernfall des Issues. Drei Spiele, von der API in SPIELTAG-Reihenfolge
  # geliefert:
  #   Position 1: Runde 1, gespielt am 10.08.  (regulaer)
  #   Position 2: Runde 2, NACHGEHOLT am 30.09. -- verlegt, spaeter als alles
  #   Position 3: Runde 3, gespielt am 24.08.  (regulaer)
  #
  # In Listenreihenfolge sieht der Walk das Nachholspiel VOR dem Spiel vom
  # 24.08. und schreibt dessen Ergebnis mit ELO-Staenden fort, die es am
  # 30.09. laengst nicht mehr gab. Chronologisch gehoert es ans Ende.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis), c("TEA-TEB", "TEA-TEC", "TEC-TED"))
  # Und die Tore muessen mit ihrer Zeile gewandert sein, nicht nur die Namen.
  expect_equal(ergebnis$ToreHeim, c(2, 1, 0))
  expect_equal(ergebnis$ToreGast, c(1, 1, 3))
})

test_that("transform_data laesst die Reihenfolge ohne Nachholspiele unveraendert", {
  # Das Gegenstueck, und betrieblich das Wichtigere: Der Normalfall ist eine
  # Liga OHNE verlegte Spiele. Dort darf sich nichts bewegen -- eine
  # Prognose, die sich ohne sachlichen Grund aendert, waere eine Regression,
  # auch wenn niemand sie als Fehler meldet.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T15:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-08-10T18:30:00+00:00", "FT", 103, 104, 1, 1, runde = 1),
    ewr_spiel(1003, "2026-08-17T15:30:00+00:00", "FT", 101, 103, 0, 2, runde = 2),
    ewr_spiel(1004, "2026-08-17T18:30:00+00:00", "NS", 102, 104, runde = 2)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis),
               c("TEA-TEB", "TEC-TED", "TEA-TEC", "TEB-TED"))
})

test_that("transform_data entscheidet bei gleicher Anstosszeit nach OriginalOrder", {
  # Vier Spiele, alle am selben Samstag um 15:30 -- der Regelfall eines
  # Bundesliga-Spieltags. Die Anstosszeit kann hier nichts entscheiden; die
  # API-Reihenfolge muss die Sortierung ueberleben.
  #
  # WARUM DAS GENUEGT: Bei identischer Anstosszeit spielen vier verschiedene
  # Paarungen, acht verschiedene Teams. Kein ELO-Wert, den das eine Spiel
  # veraendert, geht in ein anderes ein -- die Reihenfolge ist fuers Ergebnis
  # gleichgueltig. Gefordert ist allein Determinismus.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T15:30:00+00:00", "FT", 103, 102, 1, 0, runde = 1),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT", 101, 104, 2, 2, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "FT", 102, 104, 0, 1, runde = 2),
    ewr_spiel(1004, "2026-08-10T15:30:00+00:00", "FT", 101, 103, 3, 1, runde = 2)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis),
               c("TEC-TEB", "TEA-TED", "TEB-TED", "TEA-TEC"))
})

test_that("transform_data ist deterministisch: zwei Laeufe, dieselbe Reihenfolge", {
  # Mischform aus verschiedenen und gleichen Anstosszeiten. Ein
  # Sortierverfahren, das bei Gleichstand nicht stabil ist (oder das
  # Tiebreak vergisst), liefert hier nicht zwingend beim zweiten Lauf
  # dasselbe -- und die Prognose flackerte dann zwischen zwei
  # Scheduler-Zyklen ohne neue Daten.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "FT", 103, 102, 1, 1, runde = 3),
    ewr_spiel(1004, "2026-08-24T15:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )
  teams <- ewr_teams()

  lauf_a <- transform_data(fixtures, teams)
  lauf_b <- transform_data(fixtures, teams)

  expect_equal(ewr_paarungen(lauf_a), ewr_paarungen(lauf_b))
  expect_equal(attr(lauf_a, "elo_neutral"), attr(lauf_b, "elo_neutral"))
  # Und die Sortierung muss auch tatsaechlich gegriffen haben: Das
  # Nachholspiel von Position 1 gehoert ans Ende.
  expect_equal(ewr_paarungen(lauf_a),
               c("TEA-TEB", "TEC-TEB", "TEA-TEC", "TEC-TED"))
})


# --- Rueckwaertskompatibilitaet: Fixtures ohne Anstosszeit --------------------
#
# Die geteilte Fixture create_test_fixtures_api() (helper-fixtures.R:64) traegt
# KEIN date-Feld; ihre fixture-Spalte enthaelt nur id und status. Nach dem
# unnest() existiert die Spalte `fixture_date` schlicht nicht -- geprueft, nicht
# vermutet.
#
# Das ist kein Randfall, sondern die Eingabe fast aller bestehenden
# transform_data-Tests, darunter "transform_data preserves fixture order"
# (test-transform_data.R:239), der die Eingabereihenfolge ausdruecklich pinnt.
#
# Eine Sortierung, die die Spalte blind anspricht (etwa arrange(fixture_date)),
# stuerzt hier mit einem "object not found" ab -- sie wuerde die Reihenfolge
# nicht einmal falsch herstellen, sondern gar keine. Die Implementierung muss
# das Fehlen der Anstosszeit also aktiv behandeln und in diesem Fall auf die
# Eingabereihenfolge zurueckfallen.
#
# Fachlich ist dieser Rueckfall genau richtig: Ohne Anstosszeit ist die
# API-Reihenfolge die beste verfuegbare Naeherung an die Chronologie -- und
# sie ist das Verhalten von heute.

test_that("transform_data haelt ohne Anstosszeiten die Eingabereihenfolge", {
  # Exakt die geteilte Fixture, die auch die Bestandstests benutzen -- kein
  # nachgebautes Aequivalent, damit dieser Test mit ihnen zusammen bricht
  # oder zusammen haelt.
  fixtures <- create_test_fixtures_api()
  teams <- create_test_teams_api()

  ergebnis <- transform_data(fixtures, teams)

  # Dieselbe Zusicherung wie "transform_data preserves fixture order"
  # (test-transform_data.R:239), hier als ausdruecklicher Schutz der
  # Sortier-Aenderung.
  expect_equal(ewr_paarungen(ergebnis), c("TEA-TEB", "TEC-TED", "TEA-TEC"))

  # Und die uebrigen Vertraege gelten unveraendert weiter.
  expect_equal(ergebnis$ToreHeim, c(2, 1, NA))
  expect_equal(ergebnis$ToreGast, c(1, 1, NA))
  expect_equal(ncol(ergebnis) - 4, nrow(teams))
  expect_equal(attr(ergebnis, "elo_neutral"), c(FALSE, FALSE, FALSE))
})

test_that("transform_data sortiert bei teilweise fehlenden Anstosszeiten stabil", {
  # Zweite Gestalt desselben Problems: Die Spalte EXISTIERT, traegt aber bei
  # einzelnen Spielen NA. Das ist der realistischere Produktionsfall -- ein
  # neu angesetztes Spiel ohne Termin steht im Feed neben terminierten.
  #
  # Anders als beim voelligen Fehlen der Spalte laeuft hier kein Absturz,
  # sondern eine stille Fehlsortierung: order() schiebt NA per Voreinstellung
  # ans ENDE, sortiert die uebrigen Zeilen aber um. Der Test fordert nur,
  # dass ueberhaupt eine deterministische, vollstaendige Reihenfolge
  # herauskommt und das Attribut zeilengleich bleibt -- welche Position die
  # terminlosen Spiele bekommen, legt die Implementierung fest.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, NA_character_,                "NS",  101, 102, runde = 4),
    ewr_spiel(1002, "2026-09-20T15:30:00+00:00",  "FT",  103, 104, 2, 0, runde = 3),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00",  "AWD", 101, 103, 3, 0, runde = 1)
  )
  teams <- ewr_teams()

  lauf_a <- transform_data(fixtures, teams)
  lauf_b <- transform_data(fixtures, teams)

  # Kein Spiel darf verschwinden oder doppelt auftauchen.
  expect_equal(nrow(lauf_a), 3)
  expect_setequal(ewr_paarungen(lauf_a), c("TEA-TEB", "TEC-TED", "TEA-TEC"))

  # Deterministisch ueber zwei Laeufe.
  expect_equal(ewr_paarungen(lauf_a), ewr_paarungen(lauf_b))

  # Und die Kopplung haelt auch hier: Das gewertete Spiel ist TEA-TEC, wo
  # immer die Implementierung es einsortiert.
  neutral <- attr(lauf_a, "elo_neutral")
  expect_length(neutral, 3)
  expect_equal(sum(neutral), 1)
  expect_equal(ewr_paarungen(lauf_a)[neutral], "TEA-TEC")

  # Die beiden terminierten Spiele muessen untereinander chronologisch
  # stehen -- das ist der Teil, den die Sortierung auch bei Luecken leisten
  # muss.
  paarungen <- ewr_paarungen(lauf_a)
  expect_lt(match("TEA-TEC", paarungen), match("TEC-TED", paarungen))
})


# --- Die Kopplung: elo_neutral muss mitwandern --------------------------------

test_that("transform_data laesst elo_neutral mit seiner Zeile wandern", {
  # DER TEST, DER DEN STILLEN FEHLER FAENGT.
  #
  # Aufbau, bewusst so konstruiert, dass eine vergessene Mitsortierung
  # zwingend rot wird -- und nicht zufaellig durchrutscht:
  #
  #   Position 1 (API): 05.09., FT   -- regulaer gespielt
  #   Position 2 (API): 20.08., AWD  -- am gruenen Tisch gewertet, NACHHOLFALL
  #                                     in der Zeit: es liegt VOR Position 1
  #   Position 3 (API): 06.09., FT   -- regulaer gespielt
  #
  # Vor der Sortierung ist elo_neutral == c(FALSE, TRUE, FALSE).
  # Nach chronologischer Sortierung steht das AWD-Spiel an Position 1, also
  # muss elo_neutral == c(TRUE, FALSE, FALSE) sein.
  #
  # Wer nur die Zeilen sortiert und den Vektor stehen laesst, behaelt
  # c(FALSE, TRUE, FALSE) -- und markiert damit das regulaer gespielte Spiel
  # TEA-TEB (05.09.) als ELO-neutral, waehrend das gewertete TEC-TED in die
  # Staerkeschaetzung einginge. Genau verkehrt herum. Der Vektor hat hier
  # auch nicht zufaellig dieselbe Gestalt vor und nach der Sortierung: Die
  # TRUE-Position aendert sich nachweislich von 2 auf 1.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-05T18:30:00+00:00", "FT",  101, 102, 2, 1, runde = 3),
    ewr_spiel(1002, "2026-08-20T18:30:00+00:00", "AWD", 103, 104, 3, 0, runde = 1),
    ewr_spiel(1003, "2026-09-06T18:30:00+00:00", "FT",  101, 103, 0, 3, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())
  neutral <- attr(ergebnis, "elo_neutral")

  # Erst die Zeilenfolge festnageln -- sonst waere unklar, worauf sich der
  # Vektor bezieht.
  expect_equal(ewr_paarungen(ergebnis), c("TEC-TED", "TEA-TEB", "TEA-TEC"))

  # Das Attribut muss ueberhaupt noch da sein. Ein Helfer, der elo_neutral
  # als Spalte anfuegt und sortiert, kann es beim Zurueckbauen verlieren;
  # rust_integration.R:237 faellt dann still auf "kein Spiel ist neutral"
  # zurueck.
  expect_false(is.null(neutral))
  expect_type(neutral, "logical")
  expect_length(neutral, nrow(ergebnis))

  # Und der Kern: Die Markierung sitzt auf dem gewerteten Spiel, dort wo es
  # nach der Sortierung steht.
  expect_equal(neutral, c(TRUE, FALSE, FALSE))
  expect_equal(ewr_paarungen(ergebnis)[neutral], "TEC-TED")
})

test_that("transform_data markiert bei mehreren gewerteten Spielen jedes an seinem Platz", {
  # Zwei gewertete Spiele, die durch die Sortierung in VERSCHIEDENE
  # Richtungen wandern -- eines nach vorn, eines nach hinten. Ein Helfer, der
  # den Vektor zwar mitnimmt, aber mit einer falschen Permutation (etwa der
  # umgekehrten), kaeme hier nicht durch.
  #
  #   API-Position 1: 15.09. WO   -> chronologisch Platz 4
  #   API-Position 2: 12.08. FT
  #   API-Position 3: 01.08. AWD  -> chronologisch Platz 1
  #   API-Position 4: 20.08. FT
  #
  # vorher:  c(TRUE, FALSE, TRUE, FALSE)
  # nachher: c(TRUE, FALSE, FALSE, TRUE)
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-15T18:30:00+00:00", "WO",  101, 102, 0, 3, runde = 5),
    ewr_spiel(1002, "2026-08-12T18:30:00+00:00", "FT",  103, 104, 1, 1, runde = 2),
    ewr_spiel(1003, "2026-08-01T18:30:00+00:00", "AWD", 102, 103, 3, 0, runde = 1),
    ewr_spiel(1004, "2026-08-20T18:30:00+00:00", "FT",  104, 101, 2, 2, runde = 3)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())
  neutral <- attr(ergebnis, "elo_neutral")

  expect_equal(ewr_paarungen(ergebnis),
               c("TEB-TEC", "TEC-TED", "TED-TEA", "TEA-TEB"))
  expect_equal(neutral, c(TRUE, FALSE, FALSE, TRUE))
})

test_that("transform_data haelt elo_neutral auch bei gleicher Anstosszeit zeilengleich", {
  # Der Tiebreak-Pfad muss den Vektor genauso mitnehmen wie der
  # Zeitvergleich. Zwei Spiele am selben Termin, das zweite davon gewertet;
  # zusaetzlich ein spaeteres Spiel, das die Sortierung tatsaechlich arbeiten
  # laesst (sonst waere die Eingabe schon sortiert und der Test blind).
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-29T15:30:00+00:00", "FT",  101, 102, 1, 0, runde = 4),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT",  103, 104, 2, 2, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "AWD", 101, 103, 3, 0, runde = 1)
  )

  ergebnis <- transform_data(fixtures, ewr_teams())

  expect_equal(ewr_paarungen(ergebnis), c("TEC-TED", "TEA-TEC", "TEA-TEB"))
  expect_equal(attr(ergebnis, "elo_neutral"), c(FALSE, TRUE, FALSE))
})


# --- Der Vertrag nach aussen --------------------------------------------------

test_that("transform_data behaelt die Spaltenstruktur: numberTeams = ncol - 4", {
  # Die Sortierung ist eine INTERNE Angelegenheit. Der Helfer, der
  # elo_neutral als Spalte anfuegt, muss sie hinterher restlos wieder
  # entfernen -- eine uebrig gebliebene Hilfsspalte (elo_neutral, kickoff,
  # OriginalOrder) verschoebe die Team-Spalten und damit numberTeams.
  #
  # rust_integration.R leitet die Teamzahl genau so ab: ab Spalte 5 stehen
  # die Teams, also ncol - 4. Eine zusaetzliche Spalte erzeugte ein
  # Phantom-Team im Payload.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-30T18:30:00+00:00", "FT",  101, 102, 2, 1, runde = 2),
    ewr_spiel(1002, "2026-08-10T18:30:00+00:00", "AWD", 103, 104, 3, 0, runde = 1),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT",  101, 103, 1, 1, runde = 3)
  )
  teams <- ewr_teams()

  ergebnis <- transform_data(fixtures, teams)

  expect_equal(names(ergebnis)[1:4],
               c("TeamHeim", "TeamGast", "ToreHeim", "ToreGast"))
  expect_equal(ncol(ergebnis) - 4, nrow(teams))
  expect_equal(sort(names(ergebnis)[5:ncol(ergebnis)]), sort(teams$ShortText))

  # Keine Hilfsspalte darf ueberleben.
  expect_false(any(c("elo_neutral", "OriginalOrder", "kickoff",
                     "fixture_date") %in% names(ergebnis)))

  # Die ELO-Werte stehen weiterhin nur in der ERSTEN Zeile je Teamspalte --
  # das ist der Vertrag, den rust_integration.R als elo_values ausliest.
  # Diese Schleife laeuft ueber Zeilenpositionen; wird nach ihr sortiert,
  # wandert der Wert aus Zeile 1 weg und der Vertrag ist gebrochen.
  for (spalte in teams$ShortText) {
    werte <- ergebnis[[spalte]]
    expect_false(is.na(werte[1]))
    expect_true(all(is.na(werte[-1])))
  }
})


# --- extract_fixture_details(): der Payload-Pfad ------------------------------
#
# Zweiter betroffener Pfad. Hier ist die Lage tueckischer als bei
# transform_data(): league_details.R sortiert durchaus nach kickoff -- aber
# nur in rueckblick_matches(), ausblick_matches() und live_matches(), also
# fuer die ANZEIGE. build_league_details_payload() bekommt das ungefilterte,
# unsortierte `details` und baut daraus den schedule, den der ELO-Walk von
# /league-details abarbeitet. Die Anzeige ist chronologisch, der Walk ist es
# nicht.

test_that("extract_fixture_details liefert die Spiele chronologisch", {
  # Dieselbe Nachholspiel-Konstellation wie oben, jetzt auf dem
  # league-details-Pfad.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )

  details <- extract_fixture_details(fixtures)

  expect_equal(details$fixture_id, c(1001, 1003, 1002))
  expect_false(is.unsorted(details$kickoff))
  # Runde und Tore muessen mit ihrer Zeile gewandert sein.
  expect_equal(details$round, c(1L, 3L, 2L))
  expect_equal(details$goals_home, c(2, 1, 0))
})

test_that("extract_fixture_details entscheidet bei gleicher Anstosszeit nach Eingabereihenfolge", {
  # Tiebreak wie bei transform_data(): dieselbe Anstosszeit, die
  # API-Reihenfolge bleibt. Das spaetere Spiel an Position 1 sorgt dafuer,
  # dass die Sortierung ueberhaupt etwas zu tun hat.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-09-12T18:30:00+00:00", "NS", 101, 104, runde = 3),
    ewr_spiel(1002, "2026-08-10T15:30:00+00:00", "FT", 103, 102, 1, 0, runde = 1),
    ewr_spiel(1003, "2026-08-10T15:30:00+00:00", "FT", 101, 102, 2, 2, runde = 1)
  )

  details <- extract_fixture_details(fixtures)

  expect_equal(details$fixture_id, c(1002, 1003, 1001))
})

test_that("der an Rust gehende league-details-Payload ist chronologisch", {
  # Die eigentliche Zusicherung: nicht die Anzeige, sondern der schedule,
  # den build_league_details_payload() an /league-details schickt.
  #
  # Gepruefte Konstellation: Das Spiel an API-Position 2 (30.09.) ist das
  # letzte im Kalender und muss im schedule hinten stehen. Die Eintraege sind
  # list(heim_idx, gast_idx, tore_h, tore_g) mit 1-basierten Indizes in
  # teams$TeamID.
  fixtures <- ewr_fixtures(
    ewr_spiel(1001, "2026-08-10T18:30:00+00:00", "FT", 101, 102, 2, 1, runde = 1),
    ewr_spiel(1002, "2026-09-30T18:30:00+00:00", "FT", 103, 104, 0, 3, runde = 2),
    ewr_spiel(1003, "2026-08-24T18:30:00+00:00", "FT", 101, 103, 1, 1, runde = 3)
  )
  teams <- ewr_teams()

  details <- extract_fixture_details(fixtures)
  payload <- build_league_details_payload(details, teams)

  heim_idx <- vapply(payload$schedule, function(e) e[[1]], numeric(1))
  gast_idx <- vapply(payload$schedule, function(e) e[[2]], numeric(1))

  # 101->1, 102->2, 103->3, 104->4
  expect_equal(heim_idx, c(1, 1, 3))
  expect_equal(gast_idx, c(2, 3, 4))

  # Die Tore muessen ebenfalls zeilengleich mitgewandert sein -- sonst
  # rechnete der Walk das richtige Spiel mit dem falschen Ergebnis.
  tore_heim <- vapply(payload$schedule, function(e) e[[3]], numeric(1))
  tore_gast <- vapply(payload$schedule, function(e) e[[4]], numeric(1))
  expect_equal(tore_heim, c(2, 1, 0))
  expect_equal(tore_gast, c(1, 1, 3))
})
