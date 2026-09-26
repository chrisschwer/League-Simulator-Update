# Phase 5, letzter Schritt: Der Update-Loop verdrahtet die Regionalligen.
#
# Registry, Views und Generator kennen die fuenf Staffeln bereits. Was fehlt,
# ist die Kette im Loop, die aus der Simulation der 3. Liga die Objekte
# macht, die die RL-Seiten lesen:
#
#   Ergebnis_rl_<staffel>            regulaere Prognosematrix   (gibt es)
#   Ergebnis_rl_<staffel>_abstieg    rl_abstiegsprognose()      (FEHLT)
#   Ergebnis_rl_<staffel>_aufstieg   rl_aufstiegsprognose()     (FEHLT, Nord + Bayern)
#
# Voraussetzung: Die 3. Liga muss `group_of_team` und `relegation_places`
# SENDEN, sonst zaehlt die Engine keine Absteiger je Staffel aus, und die
# Regionalligen koennen ihre Abstiegszahlen nicht mischen.
#
# Diese Datei ist test-first geschrieben: Sie MUSS rot sein, solange der Loop
# die Objekte nicht baut.
#
# ===========================================================================
# WARUM HIER EIN FAKE-RUST-SERVER STEHT UND KEIN mockery-Stub AUF DER ENGINE
# ===========================================================================
#
# mockery::stub() bindet an den FUNKTIONS-Scope von update_all_leagues_loop().
# Lagert die Verdrahtung den Simulationsaufruf in eine Hilfsfunktion aus
# (oder ruft fuer die 3. Liga simulate_league_rust() direkt), greift ein Stub
# auf leagueSimulatorRust() nicht mehr -- und der Test wuerde still an der
# falschen Stelle messen. Das hat in diesem Projekt schon Tests brechen
# lassen.
#
# Deshalb wird hier eine Ebene tiefer angesetzt: httr::POST(),
# httr::status_code() und httr::content() werden fuer die Dauer des Laufs
# ueber testthat::local_mocked_bindings(.package = "httr") durch einen
# Fake-Server ersetzt. Das faengt beide Aufrufformen -- das nackte POST()
# aus rust_integration.R wie das qualifizierte httr::POST() aus
# league_details.R -- und uebersteht das library(httr), das der Loop beim
# Sourcen ausfuehrt (empirisch geprueft). Der Fake beantwortet /simulate,
# /match-preview und /league-details und PROTOKOLLIERT JEDEN PAYLOAD. So
# wird geprueft, was wirklich ueber die Leitung geht, unabhaengig davon,
# welche R-Funktion es abschickt.
#
# Die uebrigen Mitspieler (retrieveResults, transform_data, ...) bleiben wie
# in test-update-loop-gating.R mockery-Stubs: Der Loop haelt diese Aufrufe
# ausdruecklich INLINE (Kommentar dort), das ist Vertrag.
#
# ===========================================================================
# WAS DER FAKE-SERVER LIEFERT -- und warum genau das
# ===========================================================================
#
#   /simulate       Eine doppelt-stochastische, NICHT gleichverteilte Matrix
#                   (jede Zeile und jede Spalte summiert auf 1). Der
#                   Malus-Lauf (adj_points < 0) bekommt ANDERE Zahlen als der
#                   regulaere, und ein zweiter regulaerer Lauf derselben Liga
#                   wieder andere. Nur so laesst sich sehen, WELCHE Matrix
#                   eine Rechnung benutzt hat.
#
#                   Ist group_of_team gesetzt, kommt relegation_group_counts
#                   mit -- fuer den Malus-Lauf eine ANDERE Zaehlung als fuer
#                   den regulaeren. Die Absteiger der 3. Liga sind die des
#                   regulaeren Laufs; wer den Malus-Lauf zaehlt, rechnet mit
#                   Zweitvertretungen, die per -50 sicher absteigen.
#
#   /match-preview  Tor-Raten als Funktion der ELO-Differenz. Konstante Raten
#                   ergaeben ueber Hin- und Rueckspiel exakt 0,5 -- und dann
#                   waere eine erfundene 50:50-Quote vom Modell nicht zu
#                   unterscheiden.
#
#   /league-details Die aktuelle ELO nach den gespielten Partien. Keine
#                   echte ELO-Physik, sondern eine deterministische
#                   Verschiebung je entschiedenem Spiel (+-12 Punkte) --
#                   genug, um zu sehen, OB der Loop die aktuelle ELO holt
#                   und nicht die Start-ELO nimmt. Der Fake liest die Spiele
#                   aus dem Request, die Sollwerte rechnen dieselbe
#                   Verschiebung aus dem Spielplan; beide muessen sich also
#                   auf dieselben Partien beziehen.
#
# Der Loop laeuft mit n = 10 Iterationen; die Zaehlmatrizen sind auf diese
# Zeilensumme gebaut (absteiger_verteilung() prueft sie).
#
# ===========================================================================
# DREI ENTSCHEIDUNGEN DES NUTZERS (2026-09-08), DIE DIESE TESTS FESTHALTEN
# ===========================================================================
#
# (1) Nord koppelt seine Absteigerzahl zusaetzlich an den EIGENEN
#     Meisteraufstieg (Phase 6, Nachtrag: p_meister_aufstieg). Der Loop hat
#     die Zahl: P(Nord-Meister steigt auf) = Summe der Aufstiegsspalte.
#     Die Tests erwarten p = sum(Ergebnis_rl_nord_aufstieg$Aufstieg), nicht
#     den Default 0 -- sichtbar in der Invariante
#     "Summe P(Abstieg) = 3 + E[k] - p".
#
# (2) Die Aufstiegsspiele rechnen mit der AKTUELLEN ELO nach den gespielten
#     Partien (POST /league-details, Feld current_elos), NICHT mit der
#     Start-ELO aus TeamList oder Spielplan. Begruendung: Aufstiegsspiel und
#     Prognose muessen denselben ELO-Stand sehen; ein Team, das sich ueber
#     die Saison verbessert hat, ist auch im Playoff staerker. Das kostet je
#     Playoff-Staffel einen zusaetzlichen Aufruf. Ein Test belegt, dass die
#     Start-ELO ein ANDERES Ergebnis liefern wuerde.
#
# (3) Fehlt eine Voraussetzung (keine Stammregion, unbekannte Saison, keine
#     Zaehlung), degradiert der Loop STILL: keine RL-Spalte, keine Meldung,
#     kein Abbruch; der Generator ueberspringt die RL-Seiten.
#
# Punkt 6 der Vorgabe (3. Liga nicht simuliert, RL aber schon) zerfaellt in
# ZWEI Faelle, s. die Tests im Abschnitt "Fehlerfall".
#
# FALLE FUER JEDEN, DER `ergebnisse` LIEST: `ergebnisse$rl_nord_aufstieg`
# trifft per partiellem `$`-Matching auf `rl_nord_aufstiegstabelle` (die
# Platzmatrix des Malus-Laufs), solange das eigentliche Objekt fehlt -- und
# liefert dann lautlos eine 18x18-Matrix statt NULL. Deshalb greift diese
# Datei ausschliesslich mit `[[` auf die Ergebnisliste zu. Das gilt ebenso
# fuer den Loop selbst, wenn er die Aufstiegsspalte fuer Nords
# p_meister_aufstieg nachschlaegt.

library(testthat)
library(mockery)

# --- rl_group_of_team: der Produktivpfad, ungefiltert ----------------------
#
# Diese Funktion hatte keinen Test. Das ist der zweite Grund, warum die
# Kuerzel-Kollision (s. test-staffel-zuordnung.R) unbemerkt blieb: Getestet
# war nur group_of_team() -- und zwar stets mit einer schon auf eine Liga
# gefilterten TeamList. Der Loop uebergibt aber die GANZE TeamList, und
# genau dort entstand der Fehler.
#
# Die Tests fahren deshalb bewusst so auf, wie update_all_leagues_loop.R es
# tut: ungefiltert, mit der echten Kollision im Datensatz.

test_that("rl_group_of_team filtert die TeamList selbst auf die Liga", {
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  source(test_path("..", "..", "RCode", "rl_verdrahtung.R"), local = env)

  # Spielplan-Attrappe: vier Spielspalten, dann je Team eine ELO-Spalte.
  # Die Spaltennamen ab 5 sind die Kurznamen in Spielplan-Reihenfolge.
  spielplan <- data.frame(
    1L, 2L, NA_integer_, NA_integer_,
    FCH = 0, AAA = 0,
    check.names = FALSE
  )
  names(spielplan)[1:4] <- c("heim", "gast", "th", "ta")

  # "FCH" zweimal: Liga 79 (SuedWest) zuerst, Liga 80 (Nordost) danach --
  # so wie in TeamList_2026 (Heidenheim vor Hansa Rostock).
  teams <- data.frame(
    ShortText = c("FCH", "AAA", "FCH"),
    League    = c(79L, 80L, 80L),
    Region    = c("SuedWest", "Nord", "Nordost"),
    stringsAsFactors = FALSE
  )

  idx <- env$rl_group_of_team(spielplan, teams, liga = "80")

  # FCH muss Nordost (1) sein, nicht SuedWest (3).
  expect_equal(idx, c(1L, 0L))
})

test_that("rl_group_of_team loest FCH in der echten TeamList auf Nordost auf", {
  # Der Regressionstest am echten Datensatz: Hansa Rostock ist der EINZIGE
  # Nordost-Drittligist. Faellt er aus, steht die Nordost-Zeile der
  # Auszaehlung auf P(0 Absteiger) = 1, und der Regionalliga Nordost fehlt
  # die Abstiegszone auf Platz 17.
  env <- new.env()
  source(test_path("..", "..", "RCode", "league_registry.R"), local = env)
  source(test_path("..", "..", "RCode", "staffel_zuordnung.R"), local = env)
  source(test_path("..", "..", "RCode", "rl_verdrahtung.R"), local = env)

  tl <- read.csv2(test_path("..", "..", "RCode", "TeamList_2026.csv"),
                  stringsAsFactors = FALSE)
  liga3 <- tl[tl$League == 80, ]

  spielplan <- as.data.frame(c(
    list(heim = 1L, gast = 2L, th = NA_integer_, ta = NA_integer_),
    stats::setNames(as.list(rep(0, nrow(liga3))), liga3$ShortText)
  ), check.names = FALSE)

  # Ungefiltert uebergeben -- genau wie der Loop es tut.
  idx <- env$rl_group_of_team(spielplan, tl, liga = "80")

  expect_false(is.null(idx))
  nordost <- env$staffel_index("Nordost")
  expect_equal(idx[match("FCH", liga3$ShortText)], nordost)
  # Und die Staffel darf ueberhaupt vorkommen.
  expect_true(nordost %in% idx)
})
