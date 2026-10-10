# ELO-Verlauf je Liga (Issue #184). Die Spec liegt unter
# docs/superpowers/specs/ (elo-verlauf-design, 2026-10-10), Abschnitt 2.
#
# Rein: liest nur den league_entry, den build_league_page_data() je Liga baut,
# und formt daraus die Daten der Verlaufsseite. Nichts wird gespeichert --
# /league-details geht in jedem Zyklus die ganze Saison durch und liefert je
# Spiel den ELO-Stand davor und die Verschiebung. Damit ist der Verlauf aus
# dem aktuellen Spielplan vollstaendig rekonstruierbar.

# Nachbardateien relativ zu dieser Datei finden -- Muster wie in
# generate_static_site.R.
.ev_dir <- local({
  d <- NULL
  for (f in rev(sys.frames())) {
    if (!is.null(f$ofile)) {
      d <- dirname(f$ofile)
      break
    }
  }
  if (is.null(d) || is.na(d) || !nzchar(d)) "RCode" else d
})

if (!exists("nachholspiel_markierung", mode = "function") || !exists("STATUS_ERGEBNIS")) {
  source(file.path(.ev_dir, "league_details.R"), local = TRUE)
}

.ev_berliner_tag <- function(x) format(x, "%Y-%m-%d", tz = "Europe/Berlin")

# Saisonangabe aus der fruehesten Anstosszeit: Jahr J -> "J/J+1" zweistellig.
# Bewusst nicht aus SEASON: so stimmt sie auch in der Vorschau mit alter
# Fixture.
elo_verlauf_saison <- function(kickoff) {
  k <- kickoff[!is.na(kickoff)]
  if (length(k) == 0) {
    return("")
  }
  jahr <- as.integer(format(min(k), "%Y", tz = "Europe/Berlin"))
  sprintf("%d/%02d", jahr, (jahr + 1L) %% 100L)
}

elo_verlauf_daten <- function(league_entry) {
  m <- league_entry$matches
  tab <- league_entry$tabelle
  teams <- league_entry$teams

  nachhol <- nachholspiel_markierung(m)
  gespielt <- !is.na(m$played) & m$played
  # Abgesagte Spiele (CANC) werden nie nachgeholt; ohne Ausnahme hielte ein
  # einziges die Saison fuer immer offen.
  saison_laeuft <- any(!(m$status %in% c(STATUS_ERGEBNIS, "CANC")))

  name_von <- stats::setNames(as.character(tab$name), as.character(tab$team_id))
  kuerzel_von <- stats::setNames(as.character(tab$kuerzel), as.character(tab$team_id))
  start_von <- stats::setNames(teams$InitialELO, as.character(teams$TeamID))

  verein <- function(id) {
    sid <- as.character(id)
    start <- unname(start_von[[sid]])
    punkte <- list(list(n = 0L, nach = start))
    zeilen <- which(gespielt & (m$home_id == id | m$away_id == id))
    for (k in seq_along(zeilen)) {
      i <- zeilen[k]
      heim <- m$home_id[i] == id
      gegner <- as.character(if (heim) m$away_id[i] else m$home_id[i])
      vor <- if (heim) m$elo_home_pre[i] else m$elo_away_pre[i]
      delta <- if (heim) m$elo_delta_home[i] else -m$elo_delta_home[i]
      punkte[[k + 1L]] <- list(
        n = k,
        datum = .ev_berliner_tag(m$kickoff[i]),
        runde = as.integer(m$round[i]),
        nachhol = nachhol[i],
        gegner = unname(kuerzel_von[[gegner]]),
        gegner_name = unname(name_von[[gegner]]),
        heim = heim,
        tore_heim = m$goals_home[i],
        tore_gast = m$goals_away[i],
        vor = vor,
        nach = vor + delta,
        delta = delta,
        p_sieg = if (heim) m$p_home_win[i] else m$p_away_win[i],
        p_remis = m$p_draw[i]
      )
    }

    aktuell <- tab$elo[tab$team_id == id]
    ende <- punkte[[length(punkte)]]$nach
    if (abs(ende - aktuell) > 1e-6) {
      stop(sprintf("ELO-Verlauf von %s endet bei %.3f, die Tabelle sagt %.3f",
                   name_von[[sid]], ende, aktuell), call. = FALSE)
    }

    list(id = id, kuerzel = unname(kuerzel_von[[sid]]), name = unname(name_von[[sid]]),
         start = start, aktuell = aktuell, punkte = punkte)
  }

  vereine <- lapply(tab$team_id, verein)
  reihenfolge <- order(-vapply(vereine, function(v) v$aktuell, numeric(1)),
                       vapply(vereine, function(v) v$name, character(1)))
  vereine <- vereine[reihenfolge]

  spiele_max <- max(vapply(vereine, function(v) length(v$punkte) - 1L, integer(1)))
  tage <- .ev_berliner_tag(m$kickoff[gespielt])
  datum_ende <- if (length(tage) == 0) {
    NA_character_
  } else {
    format(as.Date(max(tage)) + if (saison_laeuft) 7L else 0L)
  }

  list(
    saison = elo_verlauf_saison(m$kickoff),
    saison_laeuft = saison_laeuft,
    achse_spiele_max = spiele_max + as.integer(saison_laeuft),
    achse_datum_ende = datum_ende,
    teams = vereine
  )
}
