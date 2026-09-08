# Verdrahtung der Regionalligen im Update-Loop.
#
# Die Rechenmodule stehen laengst (rl_abstiegskopplung.R, rl_aufstieg.R,
# aufstiegsspiele.R). Hier steht nur die Kette dazwischen: welche Matrix,
# welche Zaehlung und welche ELO in welche Funktion gehen.
#
# EINE ENTWURFSENTSCHEIDUNG BESTIMMT DIESE DATEI: Jede Voraussetzung kann
# fehlen, und dann wird still uebersprungen. Der Loop laeuft in Tests und im
# Betrieb mit Saisons ohne belegte Aufstiegsrotation, mit TeamLists ohne
# Spalte Region, mit Prognosematrizen ohne Zeilennamen und mit Ligen, deren
# Teams gar nicht in der TeamList stehen. Nichts davon darf den Zyklus
# abbrechen -- eine Seite ohne RL-Panel ist besser als keine Seite. Die
# strengen Pruefungen der Rechenmodule bleiben trotzdem in Kraft: Sie fangen
# den Fall, dass die Voraussetzungen DA sind und trotzdem nicht passen.
#
# Deshalb wird hier `tryCatch(..., error = ...)` benutzt, wo sonst in diesem
# Projekt eine Meldung stuende. Es ist keine Schlamperei, sondern die
# Entscheidung 3 der Vorgabe: Der Generator ueberspringt die RL-Seiten
# ohnehin, sobald ihre Objekte fehlen -- das ist das dokumentierte Verhalten
# und die sichtbare Folge.

# Setzt die Registry, die Views, die Staffel-Zuordnung und die drei
# Rechenmodule voraus; der Loop sourct sie vor dem ersten Aufruf.

#' Staffel-Zuordnung der 3. Liga in SPIELPLAN-Reihenfolge.
#'
#' Die Engine ordnet ueber die Position zu -- `group_of_team[i]` gehoert zum
#' i-ten Team des Spielplans, nicht zur i-ten Zeile der TeamList. Beide
#' Reihenfolgen unterscheiden sich in der Regel, und eine Verwechslung
#' zaehlte die Absteiger der falschen Staffel zu, ohne dass etwas
#' fehlschlaegt.
#'
#' @param spielplan Der Simulations-Data-Frame: vier Spielspalten, dann je
#'   Team eine ELO-Spalte. Ihre Namen sind die Kurznamen in Spielplan-
#'   Reihenfolge.
#' @param teams TeamList mit den Spalten ShortText und Region.
#' @return Integer-Vektor je Team, oder NULL, wenn die Zuordnung nicht
#'   herzustellen ist (keine Spalte Region, Team ausserhalb der TeamList,
#'   unbekannte Region). NULL heisst: nichts senden.
rl_group_of_team <- function(spielplan, teams) {
  if (is.null(teams$Region)) {
    return(NULL)
  }

  kurznamen <- names(spielplan)[5:ncol(spielplan)]

  # Ein Team ohne Stammregion liefert NA. simulate_league_rust() laesst die
  # Felder dann von sich aus weg -- eine halbe Zuordnung waere schlimmer als
  # keine.
  tryCatch(group_of_team(kurznamen, teams), error = function(e) NULL)
}

#' Abstiegsplaetze der 3. Liga, wie die Engine sie auszaehlen soll.
#'
#' Aus der Registry statt als Literal: Die Zahl steht dort schon
#' (relegation_slots), und zwei Quellen liefen frueher oder spaeter
#' auseinander.
rl_relegation_places <- function(id = "80") {
  eintrag <- league_by_id(id)
  if (is.null(eintrag) || is.null(eintrag$relegation_slots)) {
    return(NULL)
  }
  as.integer(eintrag$relegation_slots)
}

#' Aktuelle ELO einer Liga nach den gespielten Partien.
#'
#' WARUM NICHT DIE START-ELO: Aufstiegsspiel und Prognose muessen denselben
#' ELO-Stand sehen. Ein Team, das sich ueber die Saison verbessert hat, ist
#' auch im Playoff staerker; mit der Start-ELO aus der TeamList stuende auf
#' der Aufstiegsseite die Staerke vom Saisonbeginn.
#'
#' Die Quelle ist derselbe Spielplan, der in die Simulation geht, und
#' derselbe Endpunkt wie in der Kalibrierung (elo_calibration.R,
#' calibration_walk()). Beides zusammen heisst: Der ELO-Walk laeuft an genau
#' einer Stelle, im Rust-Server (ADR 0002).
#'
#' @param spielplan Simulations-Data-Frame wie bei rl_group_of_team().
#' @param tormodell Liste aus goal_model_args() -- leer, wo die Defaults des
#'   Servers gelten.
#' @return Benannter numerischer Vektor Kurzname -> ELO, oder NULL.
rl_aktuelle_elo <- function(spielplan, tormodell = list(),
                            base_url = Sys.getenv("RUST_API_URL",
                                                  "http://localhost:8080")) {
  kurznamen <- names(spielplan)[5:ncol(spielplan)]
  start_elo <- as.numeric(spielplan[1, 5:ncol(spielplan)])

  # Die Engine indiziert 1-basiert ueber die Position in team_names; Tore
  # eines noch nicht gespielten Spiels sind NULL, nicht NA.
  idx <- function(namen) match(as.character(namen), kurznamen)
  heim <- idx(spielplan$TeamHeim)
  gast <- idx(spielplan$TeamGast)
  if (anyNA(heim) || anyNA(gast)) {
    return(NULL)
  }

  schedule <- lapply(seq_len(nrow(spielplan)), function(i) {
    tore_h <- spielplan$ToreHeim[[i]]
    tore_g <- spielplan$ToreGast[[i]]
    if (is.na(tore_h) || is.na(tore_g)) {
      list(heim[[i]], gast[[i]], NULL, NULL)
    } else {
      list(heim[[i]], gast[[i]], as.integer(tore_h), as.integer(tore_g))
    }
  })

  payload <- c(
    list(
      schedule = schedule,
      elo_values = start_elo,
      # team_names ist nicht Zierde: Ohne sie waere die Antwort der Engine
      # nicht den Teams zuzuordnen, und die Zuordnung ueber die Position
      # allein ist genau die Verwechslung, die dieses Projekt schon
      # zweimal gemacht hat.
      team_names = kurznamen,
      mod_factor = 20
    ),
    tormodell
  )

  antwort <- tryCatch(
    fetch_league_details(payload, base_url = base_url),
    error = function(e) NULL
  )
  if (is.null(antwort)) {
    return(NULL)
  }

  geparst <- tryCatch(parse_league_details_response(antwort),
                      error = function(e) NULL)
  if (is.null(geparst) || is.null(geparst$current_elos)) {
    return(NULL)
  }

  namen <- if (is.null(geparst$team_names)) kurznamen else as.character(geparst$team_names)
  elo <- as.numeric(geparst$current_elos)
  if (length(elo) != length(namen)) {
    return(NULL)
  }
  stats::setNames(elo, namen)
}

#' Die Aufstiegsspalten der beiden Playoff-Staffeln.
#'
#' Beide entstehen zusammen: Die Doppelsumme ueber die Aufstiegstabellen
#' braucht BEIDE Staffeln, also auch dann, wenn nur eine neu simuliert
#' wurde. Die Zweikampfquoten kommen aus /match-preview ueber die AKTUELLE
#' ELO -- ein Aufruf von /league-details je Staffel.
#'
#' @param prognosen Benannte Liste Staffel -> Aufstiegstabelle (der Lauf mit
#'   -50-Malus, in dem Zweitvertretungen aus dem Rennen sind).
#' @param elos Benannte Liste Staffel -> aktueller ELO-Vektor.
#' @param saison Startjahr der Saison.
#' @param tormodell Abweichendes Tormodell (ADR 0004). Leer fuer die
#'   Regionalligen: Sie tauschen Teams mit der 3. Liga und gehoeren damit zur
#'   Wechselgemeinschaft Herren, deren Werte der Rust-Server haelt. Der
#'   Parameter steht trotzdem hier, weil das Aufstiegsspiel zwischen zwei
#'   Staffeln DERSELBEN Gemeinschaft stattfindet -- welche das ist, sagt die
#'   Registry, nicht diese Funktion.
#' @return Benannte Liste Staffel -> data.frame(Aufstieg), oder eine leere
#'   Liste, wenn die Rechnung nicht moeglich ist.
rl_aufstiegsspalten <- function(prognosen, elos, saison,
                                tormodell = list()) {
  modus <- tryCatch(aufstiegsmodus(saison), error = function(e) NULL)
  if (is.null(modus) || length(modus$playoff) != 2L) {
    return(list())
  }

  # p_sieg ist in STAFFELN-Reihenfolge orientiert: Zeilen = die fruehere
  # Staffel. zweikampf_paarungen_rust() gibt a = Heimrecht im Hinspiel, und
  # rl_aufstiegsprognose() dreht selbst, wenn die gefragte Staffel die
  # spaetere ist -- also muss a hier die fruehere sein.
  reihenfolge <- modus$playoff[order(match(modus$playoff, STAFFELN))]
  frueher <- reihenfolge[[1]]
  spaeter <- reihenfolge[[2]]

  if (any(vapply(reihenfolge, function(s) is.null(prognosen[[s]]), logical(1))) ||
        any(vapply(reihenfolge, function(s) is.null(elos[[s]]), logical(1)))) {
    return(list())
  }

  paarungen <- tryCatch(
    zweikampf_paarungen_rust(elos[[frueher]], elos[[spaeter]],
                             tore_slope = tormodell$tore_slope,
                             tore_intercept = tormodell$tore_intercept),
    error = function(e) NULL
  )
  if (is.null(paarungen)) {
    return(list())
  }

  spalten <- list()
  for (staffel in reihenfolge) {
    spalte <- tryCatch(
      rl_aufstiegsprognose(staffel, prognosen, season = saison,
                           paarungen = paarungen),
      error = function(e) NULL
    )
    if (!is.null(spalte)) {
      spalten[[staffel]] <- spalte
    }
  }
  spalten
}
