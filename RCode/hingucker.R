# Hingucker der Woche: welche Spiele der naechsten sieben Tage lohnen den Blick?
#
# Ein Spiel ist interessant, wenn es knapp ist UND wenn es fuer beide Teams um
# etwas geht. Beides misst derselbe Index, der Inverse Simpson-Index: Eins
# durch die Summe der quadrierten Wahrscheinlichkeiten. Er ist die "effektive
# Zahl" gleich wahrscheinlicher Ausgaenge, also D = 1, wenn ein Ausgang sicher
# ist, und D = k, wenn k Ausgaenge gleich wahrscheinlich sind.
#
#   D_Spiel   aus (Sieg Heim, Remis, Sieg Gast)            1 .. 3
#   D_Team    aus den Ausgaengen der Saison (Meister, CL,   1 .. k
#             EL, ..., Mittelfeld, Relegation, Abstieg)
#
# Der Hingucker-Wert ist das Produkt aus D_Spiel, D_Heim und D_Gast.
#
# Das Produkt ist bewusst einfach. D_Team misst, wie OFFEN die Saison eines
# Teams noch ist -- nicht, ob gerade dieses Spiel etwas daran aendert. Und das
# Maximum von D_Team haengt an der Zahl der Ausgaenge einer Liga (Bundesliga:
# sieben, Regionalliga: drei). Ob das eine Normierung braucht, zeigt erst der
# Blick auf echte Wochen; hingucker_logzeile() schreibt ihn je Zyklus ins Log.
#
# Diese Einheit rechnet nur. Das Markup steht in render_sections.R
# (render_hingucker), die Seite in generate_static_site.R.

.hg_dir <- local({
  d <- NULL
  for (f in rev(sys.frames())) {
    if (!is.null(f$ofile)) {
      d <- dirname(f$ofile)
      break
    }
  }
  if (is.null(d) || is.na(d) || !nzchar(d)) "RCode" else d
})

source(file.path(.hg_dir, "render_helpers.R"), local = TRUE)
source(file.path(.hg_dir, "league_registry.R"), local = TRUE)

# Kalendertage ab und inklusive heute (Berliner Zeit): heute bis heute + 6.
HINGUCKER_TAGE <- 7L
HINGUCKER_ANZAHL <- 5L

# Nullen und Rundungsreste tragen zur Summe nichts bei; p muss nicht auf 1
# normiert hereinkommen.
inverse_simpson <- function(p) {
  p <- p[is.finite(p) & p > 0]
  gesamt <- sum(p)
  if (length(p) == 0L || gesamt <= 0) {
    return(NA_real_)
  }
  1 / sum((p / gesamt)^2)
}

.hg_berliner_tag <- function(x) {
  as.Date(format(x, "%Y-%m-%d", tz = "Europe/Berlin"))
}

.hg_hole <- function(name, data_env) {
  if (!is.null(name) && exists(name, envir = data_env, inherits = FALSE)) {
    get(name, envir = data_env, inherits = FALSE)
  } else {
    NULL
  }
}

# Die Ausgangsspalten EINES Panels (`top` oder `bottom` aus league_views()) als
# benannte Liste Label -> benannter Vektor Kuerzel -> Wahrscheinlichkeit.
#
# Platzgruppen werden aus der Prognosematrix summiert (negative Grenzen zaehlen
# von unten, wie in .resolve_bounds()), berechnete Spalten (Regionalligen)
# unveraendert uebernommen. `computed_optional`-Spalten sind ZUSAETZLICHE
# Zahlen ("Abstieg gesamt" neben "Abstieg"), keine eigenen Ausgaenge: Sie
# zaehlten dieselbe Masse doppelt und bleiben draussen.
.hg_panel_spalten <- function(panel, data_env) {
  # Direktstaffel mit Aufstiegsverzicht (#320): Existiert das Objekt der
  # Aufstiegsspalte, ersetzt es die Platzgruppe -- wie in render_league_page().
  # Gezaehlt wird dann der erste Berechtigte, nicht Platz 1; ein verzichtender
  # Meister traegt keine Aufstiegswahrscheinlichkeit.
  if (!is.null(panel$aufstieg_source) &&
        !is.null(.hg_hole(panel$aufstieg_source, data_env))) {
    panel <- list(source = panel$aufstieg_source, computed = TRUE,
                  labels = panel$labels)
  }
  computed <- if (is.null(panel$computed)) {
    rep(FALSE, length(panel$labels))
  } else {
    rep_len(as.logical(panel$computed), length(panel$labels))
  }
  if (isTRUE(panel$computed_optional)) {
    # Optional sind nur die berechneten Spalten; die Platzgruppen bleiben.
    behalten <- !computed
    panel$labels <- panel$labels[behalten]
    computed <- computed[behalten]
  }

  spalten <- list()

  if (!all(computed)) {
    obj <- .hg_hole(panel$source, data_env)
    if (is.null(obj)) {
      return(NULL)
    }
    m <- as.matrix(unclass(obj))
    n <- ncol(m)
    grenzen <- panel$groups
    grenzen <- ifelse(grenzen < 0, n + 1 + grenzen, grenzen)
    labels <- panel$labels[!computed]
    for (i in seq_along(labels)) {
      spalten[[labels[i]]] <- rowSums(m[, grenzen[1, i]:grenzen[2, i], drop = FALSE])
    }
  }

  if (any(computed)) {
    quelle <- if (all(computed)) panel$source else panel$computed_source
    obj <- .hg_hole(quelle, data_env)
    if (is.null(obj)) {
      return(NULL)
    }
    df <- as.data.frame(obj)
    for (label in panel$labels[computed]) {
      if (label %in% colnames(df)) {
        spalten[[label]] <- stats::setNames(df[[label]], rownames(df))
      }
    }
  }

  spalten
}

# Die Saisonausgaenge einer Liga als Matrix Teams x Ausgaenge, Zeilensumme 1.
#
# Die Ausgaenge sind die Zonen aus league_views() -- dieselben, die Panels und
# Tabelle zeigen --, der Rest ist "Mittelfeld".
#
# Regionalliga Nord und Bayern: Der Meister (bei Verzicht: der erste
# Berechtigte) spielt Aufstiegsspiele, nur der Sieger steigt auf. Damit sich
# Aufstieg und Aufstiegsspiele nicht ueberlappen, steht dort neben "Aufstieg"
# der Ausgang "Aufstiegsspiele verloren" (P(spielt) minus P(Aufstieg)). Wer
# verzichtet, spielt nicht: P(spielt) ist null, der Ausgang entfaellt.
#
# 3. Liga und 2. Frauen-Bundesliga: Das obere Panel ist der Rang unter den
# Berechtigten (Ergebnis3_Aufstieg, ADR 0009; gesperrte Zweitvertretungen
# tragen null), das untere der Tabellenplatz. Beide stammen aus demselben Lauf.
# Der Rang unter den Berechtigten ist hoechstens der Tabellenplatz, die Zonen
# ueberlappen also nicht und die Zeilensumme ist hoechstens 1. Die Normierung
# unten faengt nur Rundung und entartete Eingaben ab.
#
# NULL, wenn eine tragende Quelle fehlt: Eine Liga ohne Ausgaenge wird nicht
# bewertet, statt mit halben Zonen falsch zu rangieren.
liga_ausgaenge <- function(view, data_env) {
  basis <- .hg_hole(view$plot_source, data_env)
  if (is.null(basis)) {
    return(NULL)
  }
  teams <- rownames(basis)

  oben <- .hg_panel_spalten(view$top, data_env)
  unten <- .hg_panel_spalten(view$bottom, data_env)
  if (is.null(oben) || is.null(unten)) {
    return(NULL)
  }

  if (all(c("Meister", "Aufstieg") %in% names(oben))) {
    meister <- oben[["Meister"]]
    aufstieg <- oben[["Aufstieg"]][names(meister)]
    aufstieg[is.na(aufstieg)] <- 0
    # Wer die Aufstiegsspiele bestreitet: der erste Berechtigte (Attribut des
    # Aufstiegsobjekts); ohne das Attribut verzichtet niemand, dann der Meister.
    erster <- attr(.hg_hole(view$top$computed_source, data_env), "p_erster_berechtigter")
    spielt <- if (is.null(erster)) meister else unname(erster[names(meister)])
    spielt[is.na(spielt)] <- 0
    oben[["Meister"]] <- NULL
    # pmax() verwirft die Namen; die Zuordnung unten laeuft ueber sie.
    oben[["Aufstiegsspiele verloren"]] <-
      stats::setNames(pmax(0, spielt - aufstieg), names(meister))
  }

  je_team <- function(spalte) {
    wert <- unname(spalte[teams])
    wert[is.na(wert)] <- 0
    wert
  }
  m <- vapply(c(oben, unten), je_team, numeric(length(teams)))
  m <- matrix(m, nrow = length(teams), dimnames = list(teams, names(c(oben, unten))))

  summe <- rowSums(m)
  m <- m / pmax(1, summe)
  mittelfeld <- pmax(0, 1 - rowSums(m))

  cbind(m[, names(oben), drop = FALSE],
        Mittelfeld = mittelfeld,
        m[, names(unten), drop = FALSE])
}

# Alle offenen Spiele der naechsten `tage` Kalendertage -- heute eingeschlossen
# -- ueber alle Ligen, mit den drei Indizes und dem Score, absteigend nach Score.
# Die Auswahl der besten fuenf ist Sache des Aufrufers: Die Diagnose braucht die
# ganze Liste.
#
# `views`: league_views() (nur die gerenderten Ligen), `data_env`: die
# Ergebnisobjekte des Zyklus, `league_data`: build_league_page_data() je Liga.
#
# Gespielt wird nur, was "NS" ist (offen). Ein heute schon angepfiffenes oder
# beendetes Spiel faellt ueber den Status heraus, auch wenn sein Anstoss heute
# liegt; ein Spiel mit offener Anstosszeit (`zeit_offen`) bleibt drin.
hingucker_kandidaten <- function(views, data_env, league_data, now = Sys.time(),
                                 tage = HINGUCKER_TAGE) {
  heute <- .hg_berliner_tag(now)
  letzter <- heute + tage - 1L

  # Eine Liga mit kaputten Daten faellt allein aus; die uebrigen bleiben im
  # Rennen. Ein Fehler in der Auswahl soll keine ganze Seite kosten.
  je_liga <- lapply(names(views), function(key) {
    tryCatch(
      .hg_liga_kandidaten(key, views[[key]], league_data[[key]], data_env, heute, letzter),
      error = function(e) {
        warning(sprintf("hingucker_kandidaten: Liga %s uebersprungen: %s",
                        key, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
  })

  alle <- do.call(rbind, Filter(Negate(is.null), je_liga))
  if (is.null(alle)) {
    return(NULL)
  }
  alle <- alle[order(-alle$score, as.numeric(alle$kickoff)), , drop = FALSE]
  rownames(alle) <- NULL
  alle
}

# Die Kandidaten EINER Liga; NULL, wenn sie keine hat. Liest `matches` so, wie
# build_league_page_data() es im Betrieb liefert (siehe test-hingucker.R,
# "Betriebsdaten"): alle Spiele der Liga mit den Endpunktspalten.
.hg_liga_kandidaten <- function(key, view, eintrag, data_env, heute, letzter) {
  spalten <- c("fixture_id", "round", "kickoff", "status", "zeit_offen",
               "nachholspiel", "home_name", "away_name", "p_home_win",
               "p_draw", "p_away_win", "score_matrix")

  if (is.null(eintrag) || is.null(eintrag$matches) || nrow(eintrag$matches) == 0L) {
    return(NULL)
  }
  ausgaenge <- liga_ausgaenge(view, data_env)
  if (is.null(ausgaenge)) {
    return(NULL)
  }

  m <- eintrag$matches
  tag <- .hg_berliner_tag(m$kickoff)
  im_fenster <- m$status == "NS" & !is.na(tag) & tag >= heute & tag <= letzter
  if (!any(im_fenster)) {
    return(NULL)
  }
  m <- m[im_fenster, , drop = FALSE]

  kuerzel <- stats::setNames(as.character(eintrag$teams$ShortText),
                             as.character(eintrag$teams$TeamID))
  heim <- unname(kuerzel[as.character(m$home_id)])
  gast <- unname(kuerzel[as.character(m$away_id)])
  bekannt <- heim %in% rownames(ausgaenge) & gast %in% rownames(ausgaenge)
  if (!any(bekannt)) {
    return(NULL)
  }
  m <- m[bekannt, , drop = FALSE]
  heim <- heim[bekannt]
  gast <- gast[bekannt]

  platz <- stats::setNames(eintrag$tabelle$platz, as.character(eintrag$tabelle$kuerzel))

  d_spiel <- mapply(function(h, x, a) inverse_simpson(c(h, x, a)),
                    m$p_home_win, m$p_draw, m$p_away_win)
  d_heim <- vapply(heim, function(k) inverse_simpson(ausgaenge[k, ]), numeric(1))
  d_gast <- vapply(gast, function(k) inverse_simpson(ausgaenge[k, ]), numeric(1))

  out <- m[, spalten, drop = FALSE]
  out$liga <- key
  # display_name, nicht nav_label: "Bundesliga" gibt es bei Herren und Frauen.
  out$liga_label <- league_registry()[[key]]$display_name
  out$heim_kuerzel <- heim
  out$gast_kuerzel <- gast
  out$platz_heim <- unname(platz[heim])
  out$platz_gast <- unname(platz[gast])
  out$d_spiel <- unname(d_spiel)
  out$d_heim <- unname(d_heim)
  out$d_gast <- unname(d_gast)
  out$score <- out$d_spiel * out$d_heim * out$d_gast
  out$ausgaenge_heim <- lapply(heim, function(k) ausgaenge[k, ])
  out$ausgaenge_gast <- lapply(gast, function(k) ausgaenge[k, ])
  out
}

# Der Untertitel nennt das Fenster: "31.10. – 6.11.".
hingucker_fenster_text <- function(now = Sys.time(), tage = HINGUCKER_TAGE) {
  heute <- .hg_berliner_tag(now)
  tag <- function(d) {
    paste0(as.integer(format(d, "%d")), ".", as.integer(format(d, "%m")), ".")
  }
  paste0(tag(heute), " – ", tag(heute + tage - 1L))
}

# Eine Logzeile je Zyklus: Zahl der Spiele im Fenster und der beste Score je
# Liga. Damit laesst sich ueber Wochen im Container-Log beobachten, ob einzelne
# Ligen wegen ihrer Zonenzahl systematisch vorn oder hinten landen -- ohne dass
# league_data dafuer auf die Platte muss.
hingucker_logzeile <- function(kandidaten) {
  if (is.null(kandidaten) || nrow(kandidaten) == 0L) {
    return("hingucker: keine Spiele im Fenster")
  }
  bester <- tapply(kandidaten$score, kandidaten$liga_label, max)
  bester <- sort(bester, decreasing = TRUE)
  paste0("hingucker: ", nrow(kandidaten), " Spiele im Fenster, bester Score je Liga: ",
         paste0(names(bester), " ", formatC(bester, digits = 1, format = "f"),
                collapse = " | "))
}
