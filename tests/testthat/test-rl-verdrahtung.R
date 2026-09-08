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

source("../../RCode/update_all_leagues_loop.R")

with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))
  force(expr)
}

rcode <- function(datei) test_path("..", "..", "RCode", datei)

# --- Registry-abgeleitete Zahlen (wie in test-update-loop-gating.R) --------

registry_env <- function() {
  env <- new.env()
  source(rcode("league_registry.R"), local = env)
  env
}

n_ligen <- function() length(registry_env()$league_ids())

n_sims_pro_runde <- function() {
  env <- registry_env()
  ids <- env$league_ids()
  length(ids) + sum(vapply(ids, env$has_promotion_restriction, logical(1)))
}

# --- Die Ligen des Fake-Betriebs --------------------------------------------
#
# Realistische Groessen, weil generate_static_site() im Fehlerfall-Test echt
# rendert und die Views feste Platzbaender (16:18, 17:20) lesen. Bayern mit
# 19 wie 2026/27.

LIGA_GROESSE <- c(
  bundesliga = 18L, zweite_bundesliga = 18L, dritte_liga = 20L,
  frauen_bundesliga = 14L, zweite_frauen_bundesliga = 14L,
  rl_nord = 18L, rl_nordost = 18L, rl_west = 18L, rl_suedwest = 18L,
  rl_bayern = 19L
)

LIGA_PRAEFIX <- c(
  bundesliga = "BL", zweite_bundesliga = "ZB", dritte_liga = "DL",
  frauen_bundesliga = "FB", zweite_frauen_bundesliga = "ZF",
  rl_nord = "NO", rl_nordost = "NE", rl_west = "WE", rl_suedwest = "SW",
  rl_bayern = "BY"
)

# Kurznamen wie DL02, DL12: Sie enden auf "2" und sind damit fuer den Loop
# Zweitvertretungen -- jede Liga bekommt so ihren Malus-Lauf mit echten -50.
teams_von <- function(key) {
  sprintf("%s%02d", LIGA_PRAEFIX[[key]], seq_len(LIGA_GROESSE[[key]]))
}

# Je Team eine eigene ELO; Nord und Bayern liegen ~200 Punkte auseinander,
# damit die Tor-Raten der Aufstiegsspiele nicht symmetrisch sind.
elo_von <- function(key) {
  idx <- match(key, names(LIGA_GROESSE))
  teams <- teams_von(key)
  stats::setNames(1000 + 50 * idx + 4 * seq_along(teams), teams)
}

STAFFELN <- c("Nord", "Nordost", "West", "SuedWest", "Bayern")

# Stammregionen der 20 Drittligisten IN TEAMLIST-REIHENFOLGE (DL01..DL20).
# Absichtlich ungleich verteilt (West 7, SuedWest 5, Bayern 3, Nordost 3,
# Nord 2) und nicht spiegelsymmetrisch: Der Spielplan traegt die Teams in
# UMGEKEHRTER Reihenfolge, und die Zuordnung nach TeamList-Reihenfolge
# ergaebe einen anderen Vektor als die nach Spielplan-Reihenfolge.
REGION_DRITTE_LIGA <- c(
  "West", "Bayern", "Nord", "SuedWest", "Nordost",
  "West", "West", "SuedWest", "Bayern", "West",
  "Nordost", "SuedWest", "West", "Nord", "West",
  "SuedWest", "Bayern", "Nordost", "West", "SuedWest"
)

teamlist_df <- function(region_leer = character(0)) {
  reg <- registry_env()$league_registry()
  zeilen <- lapply(names(LIGA_GROESSE), function(key) {
    teams <- teams_von(key)
    idx <- match(key, names(LIGA_GROESSE))
    region <- if (identical(key, "dritte_liga")) {
      REGION_DRITTE_LIGA
    } else if (!is.null(reg[[key]]$staffel)) {
      rep(reg[[key]]$staffel, length(teams))
    } else {
      rep("", length(teams))
    }
    data.frame(
      TeamID = 1000L * idx + seq_along(teams),
      ShortText = teams,
      Promotion = 0L,
      InitialELO = unname(elo_von(key)),
      League = reg[[key]]$api_id,
      Region = region,
      Name = paste("Team", teams),
      stringsAsFactors = FALSE
    )
  })
  df <- do.call(rbind, zeilen)
  df$Region[df$ShortText %in% region_leer] <- ""
  df
}

teamlist_datei <- function(region_leer = character(0)) {
  pfad <- tempfile("TeamList_rl_", fileext = ".csv")
  utils::write.table(teamlist_df(region_leer), pfad, sep = ";",
                     quote = FALSE, row.names = FALSE)
  pfad
}

# Spielplan einer Liga, wie transform_data() ihn liefert: vier Spielspalten,
# dann je Team eine Spalte mit der ELO. Die Teamspalten stehen BEWUSST in
# umgekehrter TeamList-Reihenfolge -- die Engine ordnet ueber die Position,
# und genau diese Verwechslung soll der Test fangen.
spielplan_von <- function(key) {
  teams <- rev(teams_von(key))
  elo <- elo_von(key)[teams]
  n <- length(teams)
  paare <- matrix(teams[seq_len(2L * (n %/% 2L))], ncol = 2, byrow = TRUE)
  gespielt <- seq_len(nrow(paare)) <= nrow(paare) %/% 2L
  df <- data.frame(
    TeamHeim = paare[, 1], TeamGast = paare[, 2],
    ToreHeim = ifelse(gespielt, 2L, NA_integer_),
    ToreGast = ifelse(gespielt, 1L, NA_integer_),
    stringsAsFactors = FALSE
  )
  for (t in teams) df[[t]] <- unname(elo[[t]])
  df
}

# Rohe Fixture-Liste einer Liga, nur die Felder, die der Loop selbst liest
# (beendet-Menge, Render-Signatur). `liga` ist der Schluessel fuer den
# transform_data-Stub.
fake_fixtures <- function(key, statuses) {
  idx <- match(key, names(LIGA_GROESSE))
  n <- length(statuses)
  list(
    liga = key,
    fixture = list(
      id = 100L * idx + seq_len(n),
      date = rep("2026-09-05T14:00:00+02:00", n),
      status = list(short = statuses, elapsed = rep(NA_integer_, n))
    ),
    goals = list(home = rep(NA_integer_, n), away = rep(NA_integer_, n))
  )
}

# --- Der Fake-Rust-Server ---------------------------------------------------

N_ITER <- 10L

# Zaehlmatrizen der 3. Liga: Zeile = Staffel (STAFFELN-Reihenfolge), Spalte
# = k Absteiger (0..4), Zelle = Iterationen. Jede Zeile summiert auf N_ITER,
# die Erwartungswerte ueber alle Staffeln auf exakt 4 (die Invariante von
# absteiger_verteilung()).
COUNTS_REGULAER <- matrix(c(
  2, 5, 3, 0, 0,   # Nord      E[k] = 1.1
  4, 6, 0, 0, 0,   # Nordost   E[k] = 0.6
  5, 3, 2, 0, 0,   # West      E[k] = 0.7
  3, 4, 3, 0, 0,   # SuedWest  E[k] = 1.0
  6, 2, 2, 0, 0    # Bayern    E[k] = 0.6
), nrow = 5, byrow = TRUE, dimnames = list(STAFFELN, as.character(0:4)))

COUNTS_MALUS <- matrix(c(
  0, 4, 6, 0, 0,   # Nord      E[k] = 1.6
  8, 2, 0, 0, 0,   # Nordost   E[k] = 0.2
  6, 4, 0, 0, 0,   # West      E[k] = 0.4
  2, 3, 5, 0, 0,   # SuedWest  E[k] = 1.3
  5, 5, 0, 0, 0    # Bayern    E[k] = 0.5
), nrow = 5, byrow = TRUE, dimnames = list(STAFFELN, as.character(0:4)))

# Gewichte der Verschiebungsmatrix: [Lauf-Art][[1. oder 2. Lauf]].
GEWICHTE <- list(
  regulaer = list(c(0.5, 0.3, 0.2), c(0.4, 0.35, 0.25)),
  malus    = list(c(0.6, 0.25, 0.15), c(0.45, 0.3, 0.25))
)

# Doppelt-stochastische Matrix: Zeile i traegt gewichte[j] auf Platz
# (i + j - 1) mod n. Jede Zeile UND jede Spalte summiert auf 1, keine zwei
# Zeilen sind gleich.
verschiebungsmatrix <- function(n, gewichte) {
  m <- matrix(0, nrow = n, ncol = n)
  for (j in seq_along(gewichte)) {
    for (i in seq_len(n)) {
      spalte <- ((i + j - 2L) %% n) + 1L
      m[i, spalte] <- m[i, spalte] + gewichte[[j]]
    }
  }
  m
}

# Tor-Raten als Funktion der ELO-Differenz plus Heimvorteil. Kein Modell,
# nur eine Funktion, die Staerke sichtbar macht.
fake_lambda <- function(elo_home, elo_away) {
  d <- as.numeric(elo_home) - as.numeric(elo_away)
  c(home = max(0.2, 1.4 + 0.0015 * d + 0.1),
    away = max(0.2, 1.4 - 0.0015 * d - 0.1))
}

# Die "ELO-Physik" des Fakes: je entschiedenem Spiel wandern 12 Punkte vom
# Verlierer zum Sieger, ein Remis bewegt nichts. Dieselbe Funktion rechnet
# im Fake ueber den Request und in den Sollwerten ueber den Spielplan.
ELO_SCHRITT <- 12

elo_nach_spielen <- function(elo, heim, gast, tore_heim, tore_gast) {
  for (i in seq_along(heim)) {
    if (is.na(tore_heim[[i]]) || is.na(tore_gast[[i]])) next
    if (tore_heim[[i]] == tore_gast[[i]]) next
    sieger <- if (tore_heim[[i]] > tore_gast[[i]]) heim[[i]] else gast[[i]]
    verlierer <- if (tore_heim[[i]] > tore_gast[[i]]) gast[[i]] else heim[[i]]
    elo[[sieger]] <- elo[[sieger]] + ELO_SCHRITT
    elo[[verlierer]] <- elo[[verlierer]] - ELO_SCHRITT
  }
  elo
}

# Aktuelle ELO einer Liga, wie der Fake sie fuer diesen Spielplan liefert.
elo_aktuell_von <- function(key) {
  sp <- spielplan_von(key)
  elo_nach_spielen(elo_von(key), sp$TeamHeim, sp$TeamGast, sp$ToreHeim, sp$ToreGast)
}

# Ein Request-Body zweimal geparst: vereinfacht fuer Skalare und Vektoren,
# unvereinfacht fuer den Schedule (dessen null-Tore sonst zu NA-Matrizen
# verschmelzen).
parse_body <- function(body) {
  text <- as.character(body)
  payload <- jsonlite::fromJSON(text, simplifyVector = TRUE)
  payload$schedule_roh <- jsonlite::fromJSON(text, simplifyVector = FALSE)$schedule
  payload
}

rust_fake <- function() {
  log <- new.env()
  log$simulate <- list()
  log$preview <- list()
  log$details <- list()
  log$laeufe <- list()

  POST <- function(url, body = NULL, ...) {
    payload <- parse_body(body)

    if (grepl("/league-details$", url)) {
      log$details[[length(log$details) + 1L]] <- payload
      teams <- as.character(payload$team_names)
      if (length(teams) == 0L) {
        stop("Fake-Engine: /league-details ohne team_names -- die Antwort waere nicht zuzuordnen")
      }
      elo <- stats::setNames(as.numeric(payload$elo_values), teams)
      zeilen <- payload$schedule_roh
      idx <- function(z, k) as.integer(z[[k]])
      tore <- function(z, k) if (is.null(z[[k]])) NA_integer_ else as.integer(z[[k]])
      elo <- elo_nach_spielen(
        elo,
        heim = vapply(zeilen, function(z) teams[[idx(z, 1)]], character(1)),
        gast = vapply(zeilen, function(z) teams[[idx(z, 2)]], character(1)),
        tore_heim = vapply(zeilen, function(z) tore(z, 3), integer(1)),
        tore_gast = vapply(zeilen, function(z) tore(z, 4), integer(1))
      )
      return(list(status = 200L, parsed = list(
        matches = list(),
        current_elos = unname(elo),
        team_names = teams
      )))
    }

    if (grepl("/simulate$", url)) {
      log$simulate[[length(log$simulate) + 1L]] <- payload
      teams <- as.character(payload$team_names)
      n <- length(teams)
      malus <- !is.null(payload$adj_points) && any(payload$adj_points < 0)
      art <- if (malus) "malus" else "regulaer"

      schluessel <- paste(art, paste(sort(teams), collapse = ","))
      zaehler <- if (is.null(log$laeufe[[schluessel]])) 1L else log$laeufe[[schluessel]] + 1L
      log$laeufe[[schluessel]] <- zaehler

      m <- verschiebungsmatrix(n, GEWICHTE[[art]][[min(zaehler, 2L)]])
      antwort <- list(
        probability_matrix = lapply(seq_len(n), function(i) as.list(m[i, ])),
        team_names = as.list(teams),
        simulations_performed = payload$iterations,
        time_ms = 1L
      )
      if (!is.null(payload$group_of_team)) {
        if (!identical(as.integer(payload$iterations), N_ITER)) {
          stop(sprintf(
            "Fake-Engine: die Zaehlmatrix ist auf %d Iterationen gebaut, angefragt waren %s",
            N_ITER, payload$iterations
          ))
        }
        counts <- if (malus) COUNTS_MALUS else COUNTS_REGULAER
        antwort$relegation_group_counts <-
          lapply(seq_len(nrow(counts)), function(i) as.list(unname(counts[i, ])))
      }
      return(list(status = 200L, parsed = antwort))
    }

    if (grepl("/match-preview$", url)) {
      log$preview[[length(log$preview) + 1L]] <- payload
      l <- fake_lambda(payload$elo_home, payload$elo_away)
      return(list(status = 200L, parsed = list(
        lambda_home = l[["home"]], lambda_away = l[["away"]],
        p_home_win = 0.4, p_draw = 0.25, p_away_win = 0.35,
        score_matrix = list(list(0.25, 0.25), list(0.25, 0.25))
      )))
    }

    stop(sprintf("Fake-Engine: unerwarteter Endpunkt %s", url))
  }

  # content(): "parsed" liefert die R-Struktur (wie httr sie aus JSON baut),
  # "text" denselben Inhalt als JSON-Text -- so liest ihn league_details.R.
  content <- function(x, as = "parsed", ...) {
    if (identical(as, "parsed")) {
      x$parsed
    } else {
      as.character(jsonlite::toJSON(x$parsed, auto_unbox = TRUE, null = "null",
                                    digits = NA))
    }
  }

  list(
    POST = POST,
    status_code = function(r) r$status,
    content = content,
    log = log
  )
}

# Haengt den Fake fuer die Dauer von `expr` in den httr-Namespace ein; die
# Bindings werden beim Verlassen dieser Funktion zurueckgesetzt -- auch wenn
# `expr` abbricht.
mit_rust_fake <- function(fake, expr) {
  testthat::local_mocked_bindings(
    POST = fake$POST,
    status_code = fake$status_code,
    content = fake$content,
    .package = "httr"
  )
  force(expr)
}

# --- Ein Lauf des Loops -----------------------------------------------------
#
# Rueckgabe: alle an generate_static_site() uebergebenen `ergebnisse` (eine
# Liste je Render), die Zahl der /simulate-Aufrufe zum Zeitpunkt jedes
# Renders (sim_marken), alle Payloads, alle Meldungen, die TeamList.

lauf_ausfuehren <- function(loops = 1L, full_fetch_every = 30L,
                            teamlist = teamlist_datei(),
                            nord_ab_fetch2_beendet = FALSE) {
  # Vor dem Wechsel ins Repo-Root auswerten: Die TeamList-Datei und die
  # Registry werden ueber Pfade relativ zu tests/testthat gefunden.
  force(teamlist)
  fake <- rust_fake()
  capture <- new.env()
  capture$ergebnisse <- list()
  capture$sim_marken <- integer(0)

  reg <- registry_env()
  keys <- reg$active_league_keys()
  ids <- vapply(keys, function(k) reg$league_registry()[[k]]$api_id, character(1))
  spielplaene <- lapply(stats::setNames(keys, keys), spielplan_von)
  fetch_zaehler <- new.env()

  stub(update_all_leagues_loop, "connect_rust_simulator", function() TRUE)
  stub(update_all_leagues_loop, "retrieveResults", function(league, season) {
    key <- names(ids)[match(as.character(league), ids)]
    z <- if (is.null(fetch_zaehler[[key]])) 1L else fetch_zaehler[[key]] + 1L
    fetch_zaehler[[key]] <- z
    # Nord: ab dem zweiten Fetch ist auch das zweite Spiel beendet -- die
    # beendet-Menge aendert sich, nur Nord wird neu simuliert.
    statuses <- if (identical(key, "rl_nord") && nord_ab_fetch2_beendet && z >= 2L) {
      c("FT", "FT")
    } else {
      c("FT", "NS")
    }
    fake_fixtures(key, statuses)
  })
  stub(update_all_leagues_loop, "retrieveLiveFixtures", function(...) integer(0))
  stub(update_all_leagues_loop, "transform_data", function(fixtures, teams) {
    spielplaene[[fixtures$liga]]
  })
  stub(update_all_leagues_loop, "build_league_page_data", function(...) NULL)
  stub(update_all_leagues_loop, "generate_static_site", function(..., ergebnisse) {
    capture$ergebnisse[[length(capture$ergebnisse) + 1L]] <- ergebnisse
    capture$sim_marken <- c(capture$sim_marken, length(fake$log$simulate))
    invisible(character(0))
  })

  msgs <- capture_messages(mit_rust_fake(fake, with_repo_root({
    update_all_leagues_loop(
      duration = 0, loops = loops, initial_wait = 0, n = N_ITER,
      saison = "2026", TeamList_file = teamlist,
      static_site_dir = tempdir(), full_fetch_every = full_fetch_every
    )
  })))

  list(
    ergebnisse = capture$ergebnisse,
    sim_marken = capture$sim_marken,
    simulate = fake$log$simulate,
    preview = fake$log$preview,
    details = fake$log$details,
    msgs = msgs,
    teamlist = utils::read.csv(teamlist, sep = ";", stringsAsFactors = FALSE)
  )
}

# Der Standardlauf (ein Loop, alles simuliert) wird einmal gerechnet und von
# mehreren Tests gelesen. Kein Test veraendert ihn.
.laeufe <- new.env()

standardlauf <- function() {
  if (is.null(.laeufe$standard)) .laeufe$standard <- lauf_ausfuehren()
  .laeufe$standard
}

# Die Payloads einer Liga, getrennt nach regulaerem und Malus-Lauf.
payloads_von <- function(lauf, key, malus = FALSE) {
  teams <- teams_von(key)
  Filter(function(p) {
    ist_malus <- !is.null(p$adj_points) && any(p$adj_points < 0)
    setequal(as.character(p$team_names), teams) && identical(ist_malus, malus)
  }, lauf$simulate)
}

# --- Sollwerte: dieselben Module, ein eigener Fake ---------------------------
#
# Die Sollwerte kommen aus den Modulen selbst (rl_abstiegskopplung.R,
# rl_aufstieg.R, aufstiegsspiele.R), gefuettert mit den Zahlen, die der Fake
# dem Loop gegeben hat. Geprueft wird damit die VERDRAHTUNG -- welche
# Matrix, welche Zaehlung, welche ELO in welche Funktion geht -- nicht die
# Module, die ihre eigenen Tests haben.

modell <- function() {
  if (!is.null(.laeufe$modell)) return(.laeufe$modell)
  env <- new.env()
  for (f in c("league_registry.R", "league_views.R", "staffel_zuordnung.R",
              "rl_abstiegskopplung.R", "aufstiegsspiele.R", "rl_aufstieg.R",
              "rust_integration.R")) {
    source(rcode(f), local = env)
  }
  fake <- rust_fake()
  env$POST <- fake$POST
  env$status_code <- fake$status_code
  env$content <- fake$content
  .laeufe$modell <- env
  env
}

# Tor-Raten aller Nord-Bayern-Paarungen. Sollwert ist die AKTUELLE ELO nach
# den gespielten Partien (Entscheidung 2); `elo_quelle = elo_von` liefert die
# Gegenprobe mit der Start-ELO.
paarungen_erwartet <- function(lauf = NULL, elo_quelle = elo_aktuell_von) {
  schluessel <- paste0("paarungen_", if (identical(elo_quelle, elo_von)) "start" else "aktuell")
  if (!is.null(.laeufe[[schluessel]])) return(.laeufe[[schluessel]])
  .laeufe[[schluessel]] <- modell()$zweikampf_paarungen_rust(
    elo_quelle("rl_nord"), elo_quelle("rl_bayern")
  )
  .laeufe[[schluessel]]
}

p_meister_aufstieg_nord <- function(erg) {
  if (is.null(erg[["rl_nord_aufstieg"]])) return(NULL)
  sum(erg[["rl_nord_aufstieg"]]$Aufstieg)
}

abstieg_erwartet <- function(staffel, key, erg, counts = COUNTS_REGULAER) {
  p <- if (identical(staffel, "Nord")) p_meister_aufstieg_nord(erg) else 0
  if (is.null(p)) {
    stop("Sollwert fuer Nord braucht Ergebnis_rl_nord_aufstieg (P(Meister steigt auf)); es fehlt.")
  }
  modell()$rl_abstiegsprognose(staffel, erg[[key]], counts, p_meister_aufstieg = p)
}

aufstieg_erwartet <- function(staffel, erg, paarungen,
                              nord = erg[["rl_nord_aufstiegstabelle"]],
                              bayern = erg[["rl_bayern_aufstiegstabelle"]]) {
  modell()$rl_aufstiegsprognose(
    staffel, list(Nord = nord, Bayern = bayern),
    season = 2026, paarungen = paarungen
  )
}

# Zwei Teamtabellen (data.frame, rownames = Teams) auf Wert gleich?
# Zuordnung ueber die Zeilennamen -- die Reihenfolge ist Sache des Loops.
expect_gleich <- function(ist, soll, was, tol = 1e-9) {
  if (is.null(ist)) {
    fail(sprintf("%s fehlt in den an generate_static_site() uebergebenen Ergebnissen.", was))
    return(invisible(FALSE))
  }
  ist <- as.data.frame(ist)
  soll <- as.data.frame(soll)
  expect_true(setequal(rownames(ist), rownames(soll)),
              info = sprintf("%s: andere Teams als erwartet", was))
  expect_identical(colnames(ist), colnames(soll),
                   info = sprintf("%s: Spalten", was))
  if (!setequal(rownames(ist), rownames(soll)) ||
        !identical(colnames(ist), colnames(soll))) {
    return(invisible(FALSE))
  }
  abweichung <- max(abs(
    as.matrix(ist[rownames(soll), colnames(soll), drop = FALSE]) - as.matrix(soll)
  ))
  expect_lt(abweichung, tol,
            label = sprintf("%s: groesste Abweichung vom Sollwert", was))
  invisible(abweichung < tol)
}

groesste_abweichung <- function(a, b) {
  a <- as.data.frame(a)
  b <- as.data.frame(b)
  max(abs(as.matrix(a[rownames(b), colnames(b), drop = FALSE]) - as.matrix(b)))
}

RL_SCHLUESSEL <- c(Nord = "rl_nord", Nordost = "rl_nordost", West = "rl_west",
                   SuedWest = "rl_suedwest", Bayern = "rl_bayern")

# ===========================================================================
# 1. Die 3. Liga sendet die Staffel-Zuordnung -- in Spielplan-Reihenfolge
# ===========================================================================

test_that("die 3. Liga sendet group_of_team und relegation_places = 4", {
  lauf <- standardlauf()
  regulaer <- payloads_von(lauf, "dritte_liga", malus = FALSE)
  expect_length(regulaer, 1L)
  p <- regulaer[[1]]

  # Harness-Probe: Der Spielplan traegt die Teams in umgekehrter
  # TeamList-Reihenfolge, und genau die kommt als team_names an.
  expect_identical(as.character(p$team_names), rev(teams_von("dritte_liga")))

  expect_false(is.null(p$group_of_team),
               info = "Die 3. Liga sendet kein group_of_team -- ohne die Zuordnung zaehlt die Engine keine Absteiger je Staffel aus.")
  expect_false(is.null(p$relegation_places),
               info = "Die 3. Liga sendet kein relegation_places -- die Engine lehnt group_of_team ohne relegation_places ab.")
  expect_identical(as.integer(p$relegation_places), 4L)
  expect_length(p$group_of_team, length(p$team_names))
})

test_that("die Zuordnung folgt dem Spielplan, nicht der TeamList", {
  lauf <- standardlauf()
  p <- payloads_von(lauf, "dritte_liga", malus = FALSE)[[1]]
  m <- modell()
  tl <- lauf$teamlist

  # Sollwert je Position: die Staffel des Teams, das an dieser Position der
  # team_names steht.
  soll <- m$staffel_index(tl$Region[match(as.character(p$team_names), tl$ShortText)])

  # Die Falle, in TeamList-Reihenfolge gerechnet. Harness-Probe: Sie MUSS
  # sich vom Sollwert unterscheiden, sonst faengt der Test nichts.
  naiv <- m$staffel_index(tl$Region[tl$League == 80])
  expect_false(identical(naiv, soll))

  expect_false(is.null(p$group_of_team),
               info = "kein group_of_team im Payload der 3. Liga")
  expect_false(identical(as.integer(p$group_of_team), naiv),
               info = "group_of_team folgt der TeamList-Reihenfolge -- die Engine zaehlt damit die Absteiger der falschen Staffel zu.")
  expect_identical(as.integer(p$group_of_team), soll)

  # Dasselbe noch einmal lesbar, Team fuer Team.
  for (i in seq_along(if (is.null(p$group_of_team)) NULL else p$team_names)) {
    team <- as.character(p$team_names)[[i]]
    expect_identical(
      STAFFELN[[as.integer(p$group_of_team)[[i]] + 1L]],
      tl$Region[tl$ShortText == team],
      info = sprintf("Position %d (%s)", i, team)
    )
  }
})

test_that("nur die 3. Liga sendet eine Staffel-Zuordnung, und nie ohne relegation_places", {
  lauf <- standardlauf()
  mit_zuordnung <- Filter(function(p) !is.null(p$group_of_team), lauf$simulate)
  expect_gte(length(mit_zuordnung), 1L)
  for (p in mit_zuordnung) {
    expect_true(setequal(as.character(p$team_names), teams_von("dritte_liga")),
                info = "group_of_team ausserhalb der 3. Liga gesendet")
    expect_false(is.null(p$relegation_places))
  }
})

# ===========================================================================
# 2./3. Je Staffel Ergebnis_rl_<staffel>_abstieg aus der Zaehlung der 3. Liga
# ===========================================================================

test_that("jede Staffel bekommt ihre Abstiegsspalte aus der regulaeren Zaehlung der 3. Liga", {
  lauf <- standardlauf()
  erg <- lauf$ergebnisse[[1]]
  views <- modell()$league_views()

  # Harness-Probe: Die Zaehlung des Malus-Laufs ergaebe andere Zahlen -- der
  # Vergleich unten unterscheidet also wirklich, welche Zaehlung benutzt
  # wurde.
  expect_gt(groesste_abweichung(
    modell()$rl_abstiegsprognose("SuedWest", erg[["rl_suedwest"]], COUNTS_MALUS),
    modell()$rl_abstiegsprognose("SuedWest", erg[["rl_suedwest"]], COUNTS_REGULAER)
  ), 1e-3)

  for (staffel in names(RL_SCHLUESSEL)) {
    key <- RL_SCHLUESSEL[[staffel]]
    was <- paste0("Ergebnis_", key, "_abstieg")
    ist <- erg[[paste0(key, "_abstieg")]]
    expect_gleich(ist, abstieg_erwartet(staffel, key, erg), was)
    if (!is.null(ist)) {
      expect_identical(colnames(as.data.frame(ist)), views[[key]]$bottom$labels,
                       info = sprintf("%s: Spalten der View", was))
      expect_true(setequal(rownames(as.data.frame(ist)), teams_von(key)),
                  info = sprintf("%s: Teams der Staffel", was))
    }
  }
})

test_that("Bayern weist Relegation und Abstieg getrennt aus, die anderen nur den Abstieg", {
  erg <- standardlauf()$ergebnisse[[1]]
  bayern <- erg[["rl_bayern_abstieg"]]
  expect_false(is.null(bayern), info = "Ergebnis_rl_bayern_abstieg fehlt")
  if (!is.null(bayern)) {
    expect_identical(colnames(as.data.frame(bayern)), c("Relegation", "Abstieg"))
  }
  for (key in c("rl_nord", "rl_nordost", "rl_west", "rl_suedwest")) {
    ist <- erg[[paste0(key, "_abstieg")]]
    expect_false(is.null(ist), info = sprintf("Ergebnis_%s_abstieg fehlt", key))
    if (!is.null(ist)) expect_identical(colnames(as.data.frame(ist)), "Abstieg")
  }
})

# ===========================================================================
# 4. Nord und Bayern: die Aufstiegsspalte aus den Aufstiegsspielen
# ===========================================================================

test_that("Nord und Bayern bekommen die Aufstiegsspalte als Doppelsumme ueber die Aufstiegstabellen", {
  lauf <- standardlauf()
  erg <- lauf$ergebnisse[[1]]
  paarungen <- paarungen_erwartet(lauf)

  # Harness-Probe: Mit den REGULAEREN Prognosen (Zweitvertretungen im
  # Rennen) kaeme etwas anderes heraus -- der Vergleich sieht also, ob die
  # Aufstiegstabelle benutzt wurde.
  expect_gt(groesste_abweichung(
    aufstieg_erwartet("Nord", erg, paarungen, nord = erg[["rl_nord"]], bayern = erg[["rl_bayern"]]),
    aufstieg_erwartet("Nord", erg, paarungen)
  ), 1e-3)

  expect_gleich(erg[["rl_nord_aufstieg"]], aufstieg_erwartet("Nord", erg, paarungen),
                "Ergebnis_rl_nord_aufstieg")
  expect_gleich(erg[["rl_bayern_aufstieg"]], aufstieg_erwartet("Bayern", erg, paarungen),
                "Ergebnis_rl_bayern_aufstieg")
})

test_that("die Zweikampfquoten kommen aus /match-preview, fuer jede Paarung in beide Richtungen", {
  lauf <- standardlauf()
  # 18 x 19 Paarungen, je Hin- und Rueckspiel. Weniger heisst: eine Quote
  # wurde erfunden oder eine Paarung ausgelassen.
  expect_gte(length(lauf$preview), 2L * 18L * 19L)
})

test_that("die Aufstiegsspiele rechnen mit der aktuellen ELO aus /league-details, nicht mit der Start-ELO", {
  lauf <- standardlauf()
  erg <- lauf$ergebnisse[[1]]

  # Harness-Probe: Die gespielten Partien haben die ELO wirklich bewegt, und
  # zwar so, dass die Aufstiegsspalte mit Start-ELO eine ANDERE waere.
  # Sonst bewiese der Vergleich unten nichts.
  expect_gt(max(abs(elo_aktuell_von("rl_nord") - elo_von("rl_nord"))), 0)
  expect_gt(max(abs(elo_aktuell_von("rl_bayern") - elo_von("rl_bayern"))), 0)
  soll_aktuell <- aufstieg_erwartet("Nord", erg, paarungen_erwartet(lauf))
  soll_start <- aufstieg_erwartet("Nord", erg, paarungen_erwartet(lauf, elo_quelle = elo_von))
  expect_gt(groesste_abweichung(soll_aktuell, soll_start), 1e-6)

  # Je Playoff-Staffel ein Aufruf von /league-details mit genau ihren Teams.
  details_fuer <- function(key) {
    Filter(function(p) setequal(as.character(p$team_names), teams_von(key)), lauf$details)
  }
  expect_gte(length(details_fuer("rl_nord")), 1L,
             label = "Aufrufe von /league-details fuer die Regionalliga Nord")
  expect_gte(length(details_fuer("rl_bayern")), 1L,
             label = "Aufrufe von /league-details fuer die Regionalliga Bayern")

  # Und das Ergebnis traegt die aktuelle ELO, nicht die Start-ELO.
  expect_gleich(erg[["rl_nord_aufstieg"]], soll_aktuell, "Ergebnis_rl_nord_aufstieg")
  if (!is.null(erg[["rl_nord_aufstieg"]])) {
    expect_gt(groesste_abweichung(erg[["rl_nord_aufstieg"]], soll_start), 1e-6,
              label = "Abstand der Aufstiegsspalte zur Rechnung mit Start-ELO")
  }
})

# ===========================================================================
# 5. Die Invarianten aus Phase 6/7 gelten auch nach der Verdrahtung
# ===========================================================================

test_that("Summe P(Abstieg) je Staffel ist E[Absteigerzahl] -- Nord um p_meister_aufstieg vermindert", {
  erg <- standardlauf()$ergebnisse[[1]]
  m <- modell()
  v <- m$absteiger_verteilung(COUNTS_REGULAER)
  k <- as.integer(colnames(v))
  e_absteiger <- function(staffel) sum(v[staffel, ] * m$abstiegsplaetze(staffel, k))

  p_nord <- p_meister_aufstieg_nord(erg)
  expect_false(is.null(p_nord), info = "Ergebnis_rl_nord_aufstieg fehlt")
  if (!is.null(p_nord)) {
    expect_gt(p_nord, 0)
    expect_lt(p_nord, 1)
  }

  for (staffel in names(RL_SCHLUESSEL)) {
    ist <- erg[[paste0(RL_SCHLUESSEL[[staffel]], "_abstieg")]]
    expect_false(is.null(ist), info = sprintf("Abstiegsspalte %s fehlt", staffel))
    if (is.null(ist) || (identical(staffel, "Nord") && is.null(p_nord))) next
    soll <- e_absteiger(staffel) - if (identical(staffel, "Nord")) p_nord else 0
    expect_lt(abs(sum(as.data.frame(ist)$Abstieg) - soll), 1e-9,
              label = sprintf("%s: |Summe P(Abstieg) - E[Absteiger]|", staffel))
  }
})

test_that("Bayern summiert exakt auf zwei Absteiger und zwei Releganten", {
  ist <- standardlauf()$ergebnisse[[1]]$rl_bayern_abstieg
  expect_false(is.null(ist), info = "Ergebnis_rl_bayern_abstieg fehlt")
  if (!is.null(ist)) {
    ist <- as.data.frame(ist)
    expect_lt(abs(sum(ist$Abstieg) - 2), 1e-9)
    expect_lt(abs(sum(ist$Relegation) - 2), 1e-9)
  }
})

test_that("Nord und Bayern stellen zusammen genau einen Aufsteiger", {
  erg <- standardlauf()$ergebnisse[[1]]
  expect_false(is.null(erg[["rl_nord_aufstieg"]]), info = "Ergebnis_rl_nord_aufstieg fehlt")
  expect_false(is.null(erg[["rl_bayern_aufstieg"]]), info = "Ergebnis_rl_bayern_aufstieg fehlt")
  if (!is.null(erg[["rl_nord_aufstieg"]]) && !is.null(erg[["rl_bayern_aufstieg"]])) {
    summe <- sum(erg[["rl_nord_aufstieg"]]$Aufstieg) + sum(erg[["rl_bayern_aufstieg"]]$Aufstieg)
    expect_lt(abs(summe - 1), 1e-9)
  }
})

# --- Aufstiegs-Invarianten auf den VERDRAHTETEN Objekten -------------------
#
# test-phase5-regionalligen.R prueft dieselben Summen auf Modell-Ebene, an
# rl_aufstiegsprognose() direkt. Hier laufen sie ueber das, was der Loop in
# `ergebnisse` ablegt -- denn dort brechen sie: falsche Rotation, falsche
# ELO-Zuordnung, vertauschte Staffeln, doppelt gezaehlte Liga.
#
# QUELLE JE STAFFEL: Fuer Nord und Bayern das berechnete Objekt
# Ergebnis_rl_<staffel>_aufstieg. Fuer die drei Direktaufsteiger (2026/27:
# Nordost, West, SuedWest) legt der Loop kein eigenes Objekt ab -- die Views
# lesen dort P(Meister), und .aufstiegsdaten() im Generator setzt fuer die
# Aufstiegsseite `aufstieg <- meister` aus der REGULAEREN Prognose
# (plot_source), nicht aus der Aufstiegstabelle. Genau diese Spalte nimmt
# der Test: Spalte 1 der regulaeren Prognosematrix. Legt der Loop doch ein
# _aufstieg-Objekt ab, hat es Vorrang, weil dann die Seite es lesen wuerde.
# Beide Quellen muessen auf 1 summieren; die Wahl ist eine der Treue zur
# Seite, nicht der Zahl.

aufstieg_summe <- function(erg, key) {
  obj <- erg[[paste0(key, "_aufstieg")]]
  if (!is.null(obj)) return(sum(as.data.frame(obj)$Aufstieg))
  prognose <- erg[[key]]
  if (is.null(prognose)) return(NA_real_)
  sum(as.matrix(prognose)[, 1L])
}

test_that("Nord, Nordost und Bayern stellen zusammen genau zwei Aufsteiger", {
  # Nordost ist 2026/27 Direktaufsteiger, sein Meister steigt sicher auf:
  # Summe exakt 1. Zusammen mit dem einen Aufsteiger aus den
  # Aufstiegsspielen also exakt 2. Faengt zusaetzlich den Fall, dass die
  # Verdrahtung fuer eine Direktaufsteiger-Staffel keine oder eine falsche
  # Aufstiegsspalte erzeugt.
  erg <- standardlauf()$ergebnisse[[1]]
  summen <- vapply(c("rl_nord", "rl_nordost", "rl_bayern"),
                   function(key) aufstieg_summe(erg, key), numeric(1))
  expect_false(anyNA(summen), info = paste("fehlende Quelle:", paste(names(summen)[is.na(summen)], collapse = ", ")))
  if (!anyNA(summen)) {
    expect_lt(abs(summen[["rl_nordost"]] - 1), 1e-9)
    expect_lt(abs(sum(summen) - 2), 1e-9)
  }
})

test_that("ueber alle fuenf Staffeln steigen genau vier Teams auf (Par. 55b DFB-SpO)", {
  erg <- standardlauf()$ergebnisse[[1]]
  summen <- vapply(unname(RL_SCHLUESSEL), function(key) aufstieg_summe(erg, key), numeric(1))
  expect_false(anyNA(summen), info = paste("fehlende Quelle:", paste(names(summen)[is.na(summen)], collapse = ", ")))
  if (!anyNA(summen)) {
    # Jede der drei Direktaufsteiger-Staffeln stellt genau einen ...
    for (key in c("rl_nordost", "rl_west", "rl_suedwest")) {
      expect_lt(abs(summen[[key]] - 1), 1e-9, label = sprintf("%s: |Summe P(Aufstieg) - 1|", key))
    }
    # ... und alle fuenf zusammen genau vier.
    expect_lt(abs(sum(summen) - 4), 1e-9)
  }
})

# --- Die Asymmetrie der zweiten Kopplung: Nord ja, Bayern nein --------------
#
# Bei Nord vermindert der eigene Meisteraufstieg die Absteigerzahl: Steigt
# der Meister auf, fehlt ein Team (18 - 1 - 3 + 3 = 17), und NFV-SpO Par. 6
# Abs. 3 a.E. fuellt den Platz mit dem bestplatzierten Absteiger auf. Bei
# Bayern wirkt der Meisteraufstieg NICHT auf die Abstiegszahl: Die Staffel
# spielt 2026/27 mit 19 statt 18 Vereinen, ein Aufstieg stellt die
# Sollstaerke her, statt sie zu unterschreiten. Dieser Test haelt die
# Asymmetrie an den verdrahteten Objekten fest, damit niemand die Kopplung
# spaeter "der Symmetrie halber" auch bei Bayern einbaut.

test_that("die Meisteraufstiegs-Kopplung wirkt bei Nord und nicht bei Bayern", {
  erg <- standardlauf()$ergebnisse[[1]]
  m <- modell()
  p_nord <- p_meister_aufstieg_nord(erg)
  expect_false(is.null(p_nord), info = "Ergebnis_rl_nord_aufstieg fehlt")
  if (is.null(p_nord)) return(invisible(NULL))
  expect_gt(p_nord, 0)

  # Bayern: p = 0 und p = 1 liefern dasselbe Objekt, und das verdrahtete
  # Objekt ist mit beiden identisch -- Summe in jedem Fall exakt 2.
  bayern_p0 <- m$rl_abstiegsprognose("Bayern", erg[["rl_bayern"]], COUNTS_REGULAER, p_meister_aufstieg = 0)
  bayern_p1 <- m$rl_abstiegsprognose("Bayern", erg[["rl_bayern"]], COUNTS_REGULAER, p_meister_aufstieg = 1)
  expect_lt(groesste_abweichung(bayern_p0, bayern_p1), 1e-12)
  expect_gleich(erg[["rl_bayern_abstieg"]], bayern_p0, "Ergebnis_rl_bayern_abstieg (p = 0)")
  expect_gleich(erg[["rl_bayern_abstieg"]], bayern_p1, "Ergebnis_rl_bayern_abstieg (p = 1)")
  if (!is.null(erg[["rl_bayern_abstieg"]])) {
    expect_lt(abs(sum(as.data.frame(erg[["rl_bayern_abstieg"]])$Abstieg) - 2), 1e-9)
  }

  # Nord: ohne Kopplung (p = 0) laege die Summe um genau p_nord hoeher als
  # im verdrahteten Objekt.
  nord_p0 <- m$rl_abstiegsprognose("Nord", erg[["rl_nord"]], COUNTS_REGULAER, p_meister_aufstieg = 0)
  ist <- erg[["rl_nord_abstieg"]]
  expect_false(is.null(ist), info = "Ergebnis_rl_nord_abstieg fehlt")
  if (!is.null(ist)) {
    differenz <- sum(nord_p0$Abstieg) - sum(as.data.frame(ist)$Abstieg)
    expect_lt(abs(differenz - p_nord), 1e-9,
              label = "Nord: |Summe(p = 0) - Summe(verdrahtet) - p_meister_aufstieg|")
  }
})

# ===========================================================================
# 6. Fehlerfall: die Zaehlung der 3. Liga fehlt
# ===========================================================================
#
# Die Vorgabe nennt den Fall "3. Liga nicht simuliert, RL aber schon". Er
# zerfaellt in zwei, die sich VERSCHIEDEN verhalten muessen:
#
# (a) Die 3. Liga wurde FRUEHER simuliert und hat sich seither nicht
#     geaendert (keine neuen Spiele). Ihre Zaehlung ist dann nicht veraltet,
#     sondern gueltig -- die Absteiger der 3. Liga haengen nur von der
#     3. Liga ab. Eine neu simulierte Regionalliga MUSS mit dieser Zaehlung
#     neu gemischt werden. Die Seite zu ueberspringen waere hier falsch:
#     Die Zahlen sind nicht erfunden.
#
# (b) Es gibt KEINE Zaehlung: Die Engine hat keine geliefert, weil kein
#     group_of_team gesendet werden konnte (ein Drittligist ohne
#     Stammregion -- simulate_league_rust() laesst die Felder dann bewusst
#     weg, statt eine Staffel zu erfinden). Dann darf der Loop nicht
#     abbrechen, darf keine Abstiegsspalte aus dem Nichts bauen, und
#     generate_static_site() ueberspringt die RL-Seiten -- das dokumentierte
#     Verhalten bei fehlenden Objekten. Der Loop degradiert STILL
#     (Entscheidung 3): Eine Meldung wird weder verlangt noch verboten.

test_that("(a) eine neu simulierte Regionalliga mischt mit der gueltigen Zaehlung aus dem frueheren Lauf", {
  # Loop 1: alles. Loop 2: idle. Loop 3: Sicherheits-Fetch, nur Nords
  # beendet-Menge hat sich geaendert -> nur Nord wird neu simuliert.
  lauf <- lauf_ausfuehren(loops = 3L, full_fetch_every = 2L,
                          nord_ab_fetch2_beendet = TRUE)
  expect_length(lauf$ergebnisse, 2L)
  expect_length(lauf$sim_marken, 2L)

  # Harness-Probe: In Loop 3 liefen genau zwei Simulationen (Nord regulaer
  # und Nord Aufstiegstabelle), die 3. Liga nicht.
  expect_identical(lauf$sim_marken[[2]] - lauf$sim_marken[[1]], 2L)
  spaeter <- lauf$simulate[seq(lauf$sim_marken[[1]] + 1L, lauf$sim_marken[[2]])]
  expect_true(all(vapply(spaeter, function(p) is.null(p$group_of_team), logical(1))))

  erg1 <- lauf$ergebnisse[[1]]
  erg2 <- lauf$ergebnisse[[2]]
  paarungen <- paarungen_erwartet(lauf)

  # Harness-Probe: Nords Prognose IST eine andere als in Loop 1.
  expect_gt(groesste_abweichung(erg2[["rl_nord"]], erg1[["rl_nord"]]), 1e-3)

  # Nords Abstieg: neue Prognose, alte (gueltige) Zaehlung, neues p.
  expect_gleich(erg2[["rl_nord_abstieg"]], abstieg_erwartet("Nord", "rl_nord", erg2),
                "Ergebnis_rl_nord_abstieg (Loop 3)")

  # Bayerns Aufstieg haengt ueber die Doppelsumme an Nords Aufstiegstabelle
  # und muss deshalb MIT gerechnet worden sein -- obwohl Bayern selbst nicht
  # neu simuliert wurde.
  expect_gleich(erg2[["rl_bayern_aufstieg"]], aufstieg_erwartet("Bayern", erg2, paarungen),
                "Ergebnis_rl_bayern_aufstieg (Loop 3)")
  if (!is.null(erg1[["rl_bayern_aufstieg"]]) && !is.null(erg2[["rl_bayern_aufstieg"]])) {
    expect_gt(groesste_abweichung(erg2[["rl_bayern_aufstieg"]], erg1[["rl_bayern_aufstieg"]]), 1e-6)
  }

  # Die uebrigen Staffeln: gleiche Eingaben, gleiche Zahlen.
  for (key in c("rl_nordost", "rl_west", "rl_suedwest", "rl_bayern")) {
    expect_gleich(erg2[[paste0(key, "_abstieg")]], erg1[[paste0(key, "_abstieg")]],
                  sprintf("Ergebnis_%s_abstieg (Loop 3)", key))
  }
})

test_that("(b) ohne Zaehlung bricht der Loop nicht ab und erfindet keine Abstiegsspalte", {
  # DL07 (West) verliert seine Stammregion. group_of_team() liefert dafuer
  # NA, simulate_league_rust() laesst die Zuordnung weg, die Engine zaehlt
  # nicht.
  lauf <- NULL
  expect_no_error(
    lauf <- lauf_ausfuehren(teamlist = teamlist_datei(region_leer = "DL07"))
  )
  if (is.null(lauf)) return(invisible(NULL))

  # Der Payload traegt keine halbe Zuordnung.
  regulaer <- payloads_von(lauf, "dritte_liga", malus = FALSE)
  expect_length(regulaer, 1L)
  expect_null(regulaer[[1]]$group_of_team)
  expect_null(regulaer[[1]]$relegation_places)

  # Es wurde gerendert, mit allen regulaeren Prognosen ...
  expect_length(lauf$ergebnisse, 1L)
  erg <- lauf$ergebnisse[[1]]
  for (key in c("dritte_liga", "dritte_liga_aufstieg", unname(RL_SCHLUESSEL))) {
    expect_false(is.null(erg[[key]]), info = sprintf("%s fehlt", key))
  }
  # ... aber ohne eine einzige Abstiegsspalte der Regionalligen.
  expect_length(grep("^rl_.*_abstieg$", names(erg)), 0L)

  # Ende zu Ende: Der echte Generator ueberspringt genau die RL-Seiten.
  gen <- local({
    source(rcode("generate_static_site.R"), local = TRUE)
    environment()
  })
  out <- withr::local_tempdir()
  gen_msgs <- capture_messages(
    paths <- gen$generate_static_site(
      output_dir = out,
      now = as.POSIXct("2026-09-08 12:00", tz = "Europe/Berlin"),
      ergebnisse = erg
    )
  )
  expect_true(any(grepl("uebersprungen: .*rl_nord", gen_msgs)))
  for (slug in c("index", "2-bundesliga", "3-liga", "frauen-bundesliga",
                 "2-frauen-bundesliga", "methodik")) {
    expect_true(file.exists(file.path(out, paste0(slug, ".html"))), info = slug)
  }
  for (slug in c("rl-nord", "rl-nordost", "rl-west", "rl-suedwest", "rl-bayern",
                 "rl-aufstieg")) {
    expect_false(file.exists(file.path(out, paste0(slug, ".html"))), info = slug)
  }
})

# ===========================================================================
# 7. Das Gating bleibt: Simulationen je Runde nur durch die Ligen erklaert
# ===========================================================================

test_that("die Verdrahtung aendert die Zahl der Simulationen je Runde nicht", {
  lauf <- standardlauf()
  expect_identical(n_ligen(), 10L)
  # Eine je Liga plus der Malus-Lauf jeder Liga mit Aufstiegsbeschraenkung
  # (3. Liga, 2. Frauen-BL, fuenf RL) -- dieselbe Formel wie in
  # test-update-loop-gating.R. Die Abstiegs- und Aufstiegsspalten sind
  # Rechnungen auf vorhandenen Ergebnissen, keine weiteren Simulationen.
  expect_identical(lauf$sim_marken[[1]], n_sims_pro_runde())
  expect_length(lauf$simulate, n_sims_pro_runde())
})
