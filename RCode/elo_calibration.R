# Offline-ELO-Kalibrierung fuer Ligen ohne Historie (Phase 4 Ligen-Ausbau).
#
# Die sieben neuen Ligen (fuenf Regionalligen, Frauen-BL, 2. Frauen-BL) haben
# keine ELO-Historie. Diese Datei enthaelt die reinen Rechenschritte, die aus
# einem historischen Spieldatensatz Startwerte auf der bestehenden ELO-Skala
# machen.
#
# Bewusst NICHT hier: der ELO-Walk selbst. Er lebt im Rust-Server
# (POST /league-details liefert current_elos) und wird ueber
# calibration_walk() nur angestossen. ADR 0002 verwirft den Nachbau der
# Modelllogik in R ausdruecklich -- calculate_elo_update() ist bereits ein
# Teilduplikat, ein zweites kommt nicht dazu.
#
# Modellkonstanten: Der Intercept ist fuer ALLE Ligen gleich. ELO ist die
# einzige Groesse, die ein Team beim Ligawechsel mitnimmt; nur wenn Ligen,
# die Mannschaften austauschen, dasselbe Tormodell benutzen, bedeutet ein
# ELO-Wert dies- und jenseits der Ligagrenze dasselbe.

# Spiegel der Rust-Konstanten (league-simulator-rust/src/models/mod.rs:84-87).
# Nur fuer die Diagnostik hier -- der Produktivpfad liest sie nie von hier.
TORE_INTERCEPT <- 1.3218390804597700
TORE_SLOPE <- 0.0017854953143549
HOME_ADVANTAGE_MODEL <- 40

#' Verschiebt eine ELO-Verteilung additiv auf einen Zielmittelwert.
#'
#' Nutzt die ELO-Erhaltung des Walks: Weil der Mittelwert einer geschlossenen
#' Liga ueber die Saison konstant bleibt (Rust-Test
#' `elo_is_conserved_by_the_walk`), wirkt eine Verschiebung des Startniveaus
#' unveraendert bis zum Saisonende durch. Die Ankerung ist damit eine reine
#' Startwertfrage -- kein Nachjustieren, keine Iteration.
#'
#' Additiv, nicht multiplikativ: Die Abstaende zwischen den Teams sind das
#' Ergebnis des Walks und duerfen nicht angetastet werden.
#'
#' @param elos Numerischer Vektor von ELO-Werten.
#' @param target_mean Gewuenschter Mittelwert.
#' @return Verschobener Vektor, Namen bleiben erhalten.
anchor_to_mean <- function(elos, target_mean) {
  if (length(elos) == 0) {
    stop("anchor_to_mean: ELO-Vektor ist leer")
  }
  elos + (target_mean - mean(elos))
}

#' Koppelt zwei Ligen ueber das Ergebnis ihrer Relegationsspiele.
#'
#' Relegationsspiele sind die einzige direkte Evidenz dafuer, wie zwei sonst
#' getrennte Ligen zueinander stehen. Ein Delta aus wenigen Partien traegt
#' aber viel Zufall, deshalb wirkt nur ein Anteil (`share`, per Default die
#' Haelfte) -- und zwar auf ALLE Teams beider Ligen, nicht nur auf die
#' beteiligten. So wird aus einem Zwei-Team-Ergebnis ein Liga-Signal.
#'
#' Die Verschiebung ist summenerhaltend: Was Liga A gewinnt, verliert Liga B.
#' Bei ungleicher Teamzahl wird entsprechend gewichtet, damit die Kopplung
#' keine ELO aus dem Nichts erzeugt.
#'
#' @param elos_a,elos_b ELO-Vektoren der beiden Ligen.
#' @param delta Gemessener ELO-Unterschied (positiv: Liga A ist staerker).
#' @param share Anteil des Deltas, der angewandt wird.
#' @return Liste mit `league_a` und `league_b`.
apply_relegation_coupling <- function(elos_a, elos_b, delta, share = 0.5) {
  if (share < 0 || share > 1) {
    stop("apply_relegation_coupling: share muss in [0, 1] liegen")
  }

  n_a <- length(elos_a)
  n_b <- length(elos_b)
  if (n_a == 0 || n_b == 0) {
    stop("apply_relegation_coupling: beide Ligen brauchen mindestens ein Team")
  }

  # Jedes Team bewegt sich um `share` des Deltas -- bei share = 0.5 also um
  # die Haelfte, gegenlaeufig in beiden Ligen.
  shift_a <- delta * share
  shift_b <- -delta * share

  # Bei ungleicher Teamzahl waere das nicht summenerhaltend (die groessere
  # Liga truege mehr Gesamt-ELO bei). Dann wird so umgewichtet, dass die
  # Summe konstant bleibt und die kleinere Liga sich staerker bewegt.
  if (n_a != n_b) {
    total_shift <- delta * share * 2
    shift_a <- total_shift * n_b / (n_a + n_b)
    shift_b <- -total_shift * n_a / (n_a + n_b)
  }

  list(
    league_a = elos_a + shift_a,
    league_b = elos_b + shift_b
  )
}

#' Hoechste Remisquote, die das unabhaengige Poisson-Modell erzeugen kann.
#'
#' Bestfall: gleich starke Teams, kein Heimvorteil -- dann ist lambda auf
#' beiden Seiten gleich dem Intercept und P(Remis) = sum_k dpois(k)^2.
#' Jede ELO-Differenz und jeder Heimvorteil senken die Quote von dort aus.
#'
#' Praktische Bedeutung: Liegt eine beobachtete Remisquote UEBER dieser
#' Decke, ist sie mit diesem Modell grundsaetzlich nicht darstellbar -- dann
#' hilft auch keine Streuungskalibrierung.
#'
#' @param intercept tore_intercept des Modells.
#' @return Wahrscheinlichkeit als Anteil.
poisson_draw_ceiling <- function(intercept = TORE_INTERCEPT) {
  sum(dpois(0:60, intercept)^2)
}

#' Simuliert die Remisquote fuer eine gegebene ELO-Streuung.
#'
#' Physik wie Rust (`simulation/match_sim.rs:17-25`): lambda ergibt sich
#' linear aus ELO-Differenz plus Heimvorteil, Tore sind unabhaengig Poisson.
#'
#' @keywords internal
.simulate_draw_rate <- function(sd_elo, intercept = TORE_INTERCEPT,
                                home_advantage = HOME_ADVANTAGE_MODEL,
                                n = 200000, seed = 42) {
  set.seed(seed)
  # Differenz zweier unabhaengiger Teams aus derselben Verteilung.
  d <- rnorm(n, 0, sd_elo * sqrt(2))
  lambda_home <- pmax((d + home_advantage) * TORE_SLOPE + intercept, 0.001)
  lambda_away <- pmax(-(d + home_advantage) * TORE_SLOPE + intercept, 0.001)
  mean(rpois(n, lambda_home) == rpois(n, lambda_away))
}

#' Prueft die ELO-Streuung gegen die beobachtete Remisquote.
#'
#' Bewusst pruefend, nicht setzend: Die Streuung ist das ERGEBNIS des Walks,
#' kein freier Parameter. Diese Funktion sagt nur, ob der Walk die Spreizung
#' erzeugt hat, die zur beobachteten Remisquote passt -- eine stille
#' Nachjustierung waere eine Modellentscheidung, die in den Report gehoert.
#'
#' Erwartungswerte aus der Vorabrechnung (Intercept 1.32184, HA 40):
#' Frauen-BL 15.9 % Remis -> SD ~460; 2. Frauen-BL 17.5 % -> SD ~400;
#' Bundesliga 25.0 % -> SD ~100.
#'
#' @param elos ELO-Vektor der Liga (Ergebnis des Walks).
#' @param observed_draw_rate Beobachtete Remisquote als Anteil.
#' @param intercept,home_advantage Modellkonstanten.
#' @return Liste: reachable, ceiling, actual_sd, required_sd, actual_draw_rate.
check_spread <- function(elos, observed_draw_rate,
                         intercept = TORE_INTERCEPT,
                         home_advantage = HOME_ADVANTAGE_MODEL) {
  ceiling_rate <- poisson_draw_ceiling(intercept)
  actual_sd <- stats::sd(elos)

  reachable <- observed_draw_rate <= ceiling_rate

  # Noetige SD durch Suche: die Remisquote faellt monoton in der Streuung.
  required_sd <- NA_real_
  if (reachable) {
    objective <- function(s) .simulate_draw_rate(s, intercept, home_advantage) -
      observed_draw_rate
    lo <- 1
    hi <- 1200
    if (objective(hi) < 0) {
      required_sd <- tryCatch(
        stats::uniroot(objective, c(lo, hi), tol = 1)$root,
        error = function(e) NA_real_
      )
    }
  }

  list(
    reachable = reachable,
    ceiling = ceiling_rate,
    actual_sd = actual_sd,
    required_sd = required_sd,
    actual_draw_rate = .simulate_draw_rate(actual_sd, intercept, home_advantage)
  )
}

# --- Der ELO-Walk -----------------------------------------------------------
#
# Gerechnet wird er NICHT hier, sondern im Rust-Server. POST /league-details
# macht den deterministischen Walk ueber alle gespielten Partien und liefert
# current_elos je Team -- auf exakt derselben Physik wie jede Prognose.
# ADR 0002 verwirft den Nachbau der Modelllogik in R ausdruecklich.

#' Baut die Teamliste einer Spielmenge.
#'
#' Teams ohne bekannte Historie starten auf dem Familien-Mittelwert; wer einen
#' bekannten Wert mitbringt (etwa ein Absteiger aus der 3. Liga), behaelt ihn.
#'
#' @param matches data.frame mit teams_home_id/teams_away_id.
#' @param start_elo Startwert fuer Teams ohne Historie.
#' @param known_elos Benannter Vektor: Team-ID (als String) -> ELO.
#' @return data.frame mit TeamID, ShortText, InitialELO.
teams_from_matches <- function(matches, start_elo, known_elos = NULL) {
  ids <- sort(unique(c(matches$teams_home_id, matches$teams_away_id)))
  ids <- ids[!is.na(ids)]

  if (length(ids) == 0) {
    stop("teams_from_matches: keine Teams in der Spielmenge")
  }

  elos <- rep(start_elo, length(ids))
  if (!is.null(known_elos)) {
    hit <- match(as.character(ids), names(known_elos))
    elos[!is.na(hit)] <- as.numeric(known_elos[hit[!is.na(hit)]])
  }

  data.frame(
    TeamID = ids,
    # Platzhalter: Der Walk braucht Namen nur als Beschriftung, nicht als
    # Schluessel. Die echten Kurznamen entstehen erst beim Schreiben der
    # TeamList, inklusive globaler Eindeutigkeitspruefung.
    ShortText = paste0("T", ids),
    InitialELO = elos,
    stringsAsFactors = FALSE
  )
}

#' Baut den Request-Body fuer POST /league-details.
#'
#' Die Indizes im Spielplan sind 1-basiert (Rust rechnet sie selbst herunter).
#' `home_advantage` wird bewusst NICHT gesetzt: Der Wert lebt allein im
#' Rust-Server (ADR 0002), damit die Kalibrierung auf derselben Physik ruht
#' wie jede Prognose.
#'
#' @param matches data.frame mit teams_home_id/away_id und goals_home/away.
#' @param teams data.frame aus teams_from_matches().
#' @return Liste, bereit fuer jsonlite::toJSON(auto_unbox = TRUE).
build_walk_payload <- function(matches, teams, mod_factor = 20, max_goals = 6) {
  heim_idx <- match(matches$teams_home_id, teams$TeamID)
  gast_idx <- match(matches$teams_away_id, teams$TeamID)

  # Spiele mit unbekannten Teams stillschweigend zu simulieren waere der
  # Fehler, den der Rundenfilter der Regionalligen sonst erzeugt haette.
  valid <- !is.na(heim_idx) & !is.na(gast_idx)
  if (!any(valid)) {
    stop("build_walk_payload: kein Spiel mit bekannten Teams uebrig")
  }

  schedule <- lapply(which(valid), function(i) {
    tore_h <- matches$goals_home[i]
    tore_g <- matches$goals_away[i]
    if (is.na(tore_h) || is.na(tore_g)) {
      list(heim_idx[i], gast_idx[i], NULL, NULL)
    } else {
      list(heim_idx[i], gast_idx[i], tore_h, tore_g)
    }
  })

  list(
    schedule = schedule,
    elo_values = teams$InitialELO,
    team_names = teams$ShortText,
    mod_factor = mod_factor,
    max_goals = max_goals
  )
}

#' Fuehrt den ELO-Walk ueber den Rust-Server aus.
#'
#' @param matches Spielmenge (chronologisch sortiert!).
#' @param teams Teamliste aus teams_from_matches().
#' @param base_url Adresse des Rust-Servers.
#' @return Benannter Vektor: Team-ID (String) -> End-ELO.
calibration_walk <- function(matches, teams,
                             base_url = Sys.getenv("RUST_API_URL", "http://localhost:8080")) {
  payload <- build_walk_payload(matches, teams)
  json_body <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")

  response <- httr::POST(
    paste0(base_url, "/league-details"),
    body = json_body,
    httr::content_type_json(),
    httr::accept_json()
  )

  if (httr::status_code(response) != 200) {
    stop(sprintf("calibration_walk: /league-details antwortete mit %d: %s",
                 httr::status_code(response),
                 httr::content(response, "text", encoding = "UTF-8")))
  }

  parsed <- jsonlite::fromJSON(httr::content(response, "text", encoding = "UTF-8"))
  stats::setNames(parsed$current_elos, as.character(teams$TeamID))
}

# --- Orchestrierung ---------------------------------------------------------

# Die zehn Ligen und ihre Familien. Eine Familie ist eine
# Wechselgemeinschaft: Ligen, zwischen denen Teams auf- und absteigen. Nur
# innerhalb einer Familie sind ELO-Werte vergleichbar.
LEAGUE_FAMILIES <- list(
  herren = c("78", "79", "80", "83", "84", "85", "86", "87"),
  frauen = c("82", "1034")
)

REGIONALLIGEN <- c("83", "84", "85", "86", "87")

RL_LABELS <- c("83" = "Bayern", "84" = "Nord", "85" = "Nordost",
               "86" = "SuedWest", "87" = "West")

#' Laedt die Hauptrundenspiele einer Liga-Saison, chronologisch sortiert.
load_season_matches <- function(league, season, refresh = FALSE) {
  fx <- tryCatch(cached_fixtures(league, season, refresh = refresh),
                 error = function(e) NULL)
  if (is.null(fx) || !is.data.frame(fx) || nrow(fx) == 0) return(NULL)

  keep <- fx$fixture_status_short == "FT" &
    !is.na(fx$goals_home) & !is.na(fx$goals_away)
  if (!is.null(fx$round)) {
    keep <- keep & is_regular_season_round(fx$round)
  }

  m <- fx[keep, , drop = FALSE]
  if (nrow(m) == 0) return(NULL)
  m[order(m$fixture_date), , drop = FALSE]
}

#' Laeuft eine Liga ueber mehrere Saisons durch.
#'
#' Die End-ELOs einer Saison sind die Start-ELOs der naechsten; wer neu
#' dazukommt, startet auf `start_elo`. Das ist der Kern der Kalibrierung:
#' Aus einem einheitlichen Startwert entsteht ueber die Historie eine
#' Rangfolge.
#'
#' @return Benannter Vektor Team-ID -> ELO, oder NULL ohne Daten.
walk_league_history <- function(league, seasons, start_elo,
                                known_elos = NULL, refresh = FALSE,
                                base_url = Sys.getenv("RUST_API_URL", "http://localhost:8080")) {
  elos <- known_elos
  seen_any <- FALSE

  for (s in seasons) {
    m <- load_season_matches(league, s, refresh = refresh)
    if (is.null(m)) next

    teams <- teams_from_matches(m, start_elo = start_elo, known_elos = elos)
    walked <- calibration_walk(m, teams, base_url = base_url)

    # Ergebnisse in den laufenden Bestand mischen: Teams, die diese Saison
    # nicht gespielt haben, behalten ihren Wert.
    if (is.null(elos)) {
      elos <- walked
    } else {
      elos[names(walked)] <- walked
    }
    seen_any <- TRUE
  }

  if (!seen_any) NULL else elos
}

#' Ordnet jeden Regionalliga-Verein seiner Staffel zu.
#'
#' Aus den Daten abgeleitet, nicht handkuratiert: Ueber die verfuegbaren
#' Saisons hinweg hat kein Verein die Staffel gewechselt (163 von 163
#' eindeutig), die Zuordnung ist also eine Tatsache der Spielplaene.
#' Mehrdeutige Faelle -- sollte es sie kuenftig geben -- werden der Staffel
#' mit den meisten Saisons zugeschlagen.
#'
#' @return data.frame mit TeamID und Region.
derive_club_regions <- function(seasons, refresh = FALSE) {
  rows <- list()
  for (lid in REGIONALLIGEN) {
    for (s in seasons) {
      m <- load_season_matches(lid, s, refresh = refresh)
      if (is.null(m)) next
      ids <- unique(c(m$teams_home_id, m$teams_away_id))
      rows[[length(rows) + 1]] <- data.frame(
        TeamID = ids, Region = unname(RL_LABELS[lid]),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) return(data.frame(TeamID = integer(0), Region = character(0)))

  d <- do.call(rbind, rows)
  # Haeufigste Staffel je Verein.
  split_by_team <- split(d$Region, d$TeamID)
  data.frame(
    TeamID = as.integer(names(split_by_team)),
    Region = vapply(split_by_team, function(r) names(sort(table(r), decreasing = TRUE))[1], ""),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Ermittelt Auf- und Absteiger zwischen zwei Ligen-Mengen.
#'
#' Ein Aufsteiger ist ein Team, das in der Vorsaison unten und in der
#' Folgesaison oben gespielt hat -- und umgekehrt.
#'
#' @return Liste mit `promoted` und `relegated` (Team-IDs).
find_league_movers <- function(lower_ids_prev, upper_ids_prev,
                               lower_ids_now, upper_ids_now) {
  list(
    promoted = intersect(lower_ids_prev, setdiff(upper_ids_now, upper_ids_prev)),
    relegated = intersect(upper_ids_prev, setdiff(lower_ids_now, lower_ids_prev))
  )
}

#' Sammelt die aktuellsten bekannten Vereinsnamen je Team-ID.
#'
#' Der jeweils spaeteste Eintrag gewinnt -- Vereine werden umbenannt, und die
#' TeamList soll den heutigen Namen tragen.
collect_team_names <- function(leagues, seasons_by_league, refresh = FALSE) {
  rows <- list()
  for (lid in leagues) {
    for (s in seasons_by_league[[lid]]) {
      m <- load_season_matches(lid, s, refresh = refresh)
      if (is.null(m) || is.null(m$teams_home_name)) next
      rows[[length(rows) + 1]] <- data.frame(
        TeamID = c(m$teams_home_id, m$teams_away_id),
        Name = c(m$teams_home_name, m$teams_away_name),
        Season = s, stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    return(data.frame(TeamID = integer(0), Name = character(0)))
  }

  d <- do.call(rbind, rows)
  d <- d[order(d$TeamID, -d$Season), ]
  d <- d[!duplicated(d$TeamID), c("TeamID", "Name")]
  rownames(d) <- NULL
  d
}

#' Vergibt Kurznamen, die gegen einen Reservierungssatz eindeutig sind.
#'
#' Global eindeutig, obwohl produktiv nur Eindeutigkeit je Liga verlangt ist
#' (s. u.) -- dieses Offline-Skript kennt die Ligazuordnung nicht.
#'
#' Kritisch, weil ShortText in transform_data() zum SPALTENNAMEN des
#' Simulations-Data-Frames wird: Zwei Vereine mit demselben Kuerzel erzeugen
#' doppelte Spalten und damit stillschweigend vertauschte Teams. Bei ~200
#' Teams -- darunter viele Zweitvertretungen ("Bayern II", "Koeln II") --
#' sind Kollisionen sicher, nicht bloss moeglich.
#'
#' Vorhandene Kurznamen (die drei Altligen) sind gesetzt und werden nie
#' veraendert; neue Teams weichen bei Kollision auf eine vierte Stelle aus.
#'
#' @param names_df data.frame mit TeamID und Name.
#' @param reserved Bereits vergebene Kurznamen.
#' @return data.frame mit TeamID, Name, ShortText, Promotion.
# Vergibt global eindeutige Kuerzel gegen `reserved`. Produktiv ist
# Eindeutigkeit nur noch JE LIGA verlangt (load_team_list() in
# transform_data.R, Regel seit PR #183): Die Frauenmannschaft
# eines Vereins traegt bewusst dasselbe Kuerzel wie die Herrenmannschaft.
#
# Diese Funktion bleibt bei der strengeren globalen Regel. Sie laeuft nur im
# einmaligen Offline-Kalibrierungsskript (ADR 0003), nie im Produktivpfad --
# ein zu strenges Kriterium erzeugt hier hoechstens ein unnoetiges
# Ausweichkuerzel, nie einen Fehler. Wer sie erneut fuer die Frauen-Ligen
# laufen laesst, muss die 16 angeglichenen Kuerzel danach von Hand
# wiederherstellen (oder `reserved` je Wechselgemeinschaft fuellen).
assign_short_names <- function(names_df, reserved = character()) {
  used <- reserved
  short <- character(nrow(names_df))
  promo <- numeric(nrow(names_df))

  for (i in seq_len(nrow(names_df))) {
    nm <- names_df$Name[i]
    is_second <- grepl("\\bII\\b|\\bU2[13]\\b", nm)
    promo[i] <- if (is_second) -50 else 0

    base <- toupper(gsub("[^A-Za-z]", "", get_team_short_name(nm)))
    if (nchar(base) < 3) base <- toupper(substr(gsub("[^A-Za-z]", "", nm), 1, 3))
    if (is_second) base <- paste0(substr(base, 1, 2), "2")

    cand <- if (is_second) base else substr(base, 1, 3)
    if (cand %in% used || nchar(cand) < 3) {
      # Vierte Stelle nur mit Buchstaben. Eine angehaengte "2" waere
      # mehrdeutig: Sie ist im Bestand die Markierung fuer
      # Zweitvertretungen (siehe update_all_leagues_loop.R, das den
      # -50-Abzug am Suffix erkennt).
      #
      # Reicht eine Stelle nicht, wird auf zwei erweitert. Lieber ein
      # fuenfstelliges Kuerzel als ein doppeltes: ShortText wird zum
      # Spaltennamen, Duplikate vertauschen Teams stillschweigend.
      stem <- substr(cand, 1, 3)
      found <- NA_character_
      for (suffix in LETTERS) {
        alt <- paste0(stem, suffix)
        if (!(alt %in% used)) { found <- alt; break }
      }
      if (is.na(found)) {
        for (s1 in LETTERS) {
          for (s2 in LETTERS) {
            alt <- paste0(stem, s1, s2)
            if (!(alt %in% used)) { found <- alt; break }
          }
          if (!is.na(found)) break
        }
      }
      if (is.na(found)) {
        stop(sprintf("assign_short_names: kein freies Kuerzel fuer '%s'", nm))
      }
      cand <- found
    }
    used <- c(used, cand)
    short[i] <- cand
  }

  data.frame(TeamID = names_df$TeamID, Name = names_df$Name,
             ShortText = short, Promotion = promo,
             stringsAsFactors = FALSE)
}
