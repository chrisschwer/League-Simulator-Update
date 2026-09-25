# Sektionsrenderer der statischen Seite: Ligatabelle mit Zonen, Rueckblick,
# Live und Ausblick. Bis #211 (Testsuite-Umbau, Phase 0.4) standen sie in
# generate_static_site.R; der Generator sourct diese Datei und setzt aus den
# Sektionen die Seiten zusammen. Unveraendert verschoben.
#
# Allein ladbar: braucht nur render_helpers.R (prozent(), .heat_style(),
# .tooltip_html(), .ergebnis_objektname()) und league_registry.R.

suppressPackageStartupMessages({
  library(htmltools)
})

# Nachbardateien relativ zu dieser Datei finden -- gleiches Muster wie in
# generate_static_site.R: source() legt `ofile` in seinem Frame ab.
.rs_dir <- local({
  d <- NULL
  for (f in rev(sys.frames())) {
    if (!is.null(f$ofile)) {
      d <- dirname(f$ofile)
      break
    }
  }
  if (is.null(d) || is.na(d) || !nzchar(d)) "RCode" else d
})

source(file.path(.rs_dir, "render_helpers.R"), local = TRUE)
source(file.path(.rs_dir, "league_registry.R"), local = TRUE)

# --- Phase 4a: Ligatabelle ---------------------------------------------------

# Deutsche Dezimalformatierung: Punkt -> Komma.
.komma <- function(x, digits) {
  sub(".", ",", formatC(x, digits = digits, format = "f", big.mark = ""),
     fixed = TRUE)
}

# Vorzeichenbehaftete Zahl mit U+2212 als Minus (statt Bindestrich) und
# "±0" bei exakt Null. digits = Nachkommastellen (0 für Tordifferenz,
# 1 für Delta-ELO). Das Vorzeichen wird vom GERUNDETEN Wert abgeleitet,
# nicht vom Rohwert: sonst zeigt z.B. -0.04 bei einer Nachkommastelle ein
# "−0,0" statt des korrekten "±0,0", weil der Rohwert negativ ist, der
# angezeigte gerundete Wert aber Null.
.vorzeichen <- function(x, digits) {
  gerundet <- round(x, digits)
  formatted <- .komma(abs(gerundet), digits)
  ifelse(gerundet > 0, paste0("+", formatted),
        ifelse(gerundet < 0, paste0("−", formatted),
              paste0("±", formatted)))
}

# ---------------------------------------------------------------------------
# Auf- und Abstiegszonen an der Ligatabelle (Issue #185)
#
# Eine duenne farbige Linie links an der Zeile sagt, was dieser PLATZ am
# Saisonende bedeutet: rot Abstieg, gelb Relegation (nur Bayern), gruen
# Aufstieg. Die Deckkraft folgt der Wahrscheinlichkeit -- bei drei der fuenf
# Staffeln haengt die Absteigerzahl an der 3. Liga, derselbe Platz kann dort
# je nach deren Ausgang Abstiegsplatz sein oder nicht.
#
# NICHT in der Heatmap: Deren Zellfarbe ist mit der Wahrscheinlichkeit belegt
# (.heat_style). Ein zweiter Verlauf im selben Kanal waere mehrdeutig.
#
# Mindestdeckkraft: Jedes P > 0 bleibt sichtbar. Ohne Untergrenze saehe
# "kann noch passieren" aus wie "ausgeschlossen" -- und genau diese
# Unterscheidung ist der Zweck der Abstufung. Angewandt wird sie im
# Stylesheet (max(.15, var(--zone-p))), damit --zone-p die Wahrscheinlichkeit
# selbst bleibt und nicht eine daraus gerechnete Groesse.
.ZONE_MIN_DECKKRAFT <- 0.15

# Die Zone eines Platzes: Rot vor Gelb vor Gruen. Der Vorrang ist in der
# Praxis nie noetig -- bei 18 bis 19 Vereinen liegen Platz 1 und die
# Abstiegsplaetze weit auseinander. Er steht hier, damit die Funktion auch
# fuer eine kuenftig kleinere Liga eine definierte Antwort gibt, statt zwei
# Linien uebereinanderzulegen.
.zone_von_platz <- function(zonen, platz) {
  kandidaten <- list(
    list(name = "abstieg", p = zonen$abstieg[platz]),
    list(name = "relegation", p = if (is.null(zonen$relegation)) 0 else zonen$relegation[platz]),
    list(name = "aufstieg", p = zonen$aufstieg[platz])
  )
  for (k in kandidaten) {
    if (length(k$p) == 1L && !is.na(k$p) && k$p > 0) {
      return(list(name = k$name, p = k$p))
    }
  }
  NULL
}

# Die Zonen-Attribute einer Tabellenzeile. Leerer String, wo keine Zone ist:
# So bleibt das HTML ohne Zonen zeichengleich zu vorher.
.zone_attrs <- function(zonen, platz) {
  if (is.null(zonen)) {
    return("")
  }
  zone <- .zone_von_platz(zonen, platz)
  if (is.null(zone)) {
    return("")
  }
  # --zone-p traegt die WAHRSCHEINLICHKEIT selbst, nicht eine daraus
  # gerechnete Deckkraft. Zwei Gruende: Die Zahl bleibt im HTML lesbar und
  # mit der Fussnote vergleichbar, und die Untergrenze ist eine Frage der
  # Darstellung -- sie gehoert ins Stylesheet, das sie per max() anwendet,
  # nicht in den Renderer.
  sprintf(' data-zone="%s" style="--zone-p:%s"',
          zone$name, format(round(zone$p, 4), trim = TRUE, scientific = FALSE))
}

#' Ligatabelle, optional mit Auf-/Abstiegszonen.
#'
#' @param tabelle Der angereicherte data.frame aus build_league_page_data().
#' @param zonen NULL oder eine Liste mit den Vektoren `abstieg`, `aufstieg`
#'   (je Platz) und optional `relegation` (nur Bayern). Ohne zonen rendert
#'   die Funktion zeichengleich wie vor Issue #185 -- die fuenf Nicht-RL-
#'   Ligen rufen sie weiterhin ohne auf.
render_liga_tabelle <- function(tabelle, zonen = NULL) {
  header <- paste0(
    "<thead><tr>\n",
    "<th scope=\"col\"><button data-key=\"platz\" data-dir=\"asc\" ",
    "aria-sort=\"ascending\">Platz</button></th>\n",
    "<th scope=\"col\">Team</th>",
    "<th scope=\"col\" class=\"num opt\">Sp.</th>",
    "<th scope=\"col\" class=\"num opt\">Tordiff.</th>\n",
    "<th scope=\"col\"><button data-key=\"pkt\" data-dir=\"desc\">Punkte</button></th>\n",
    "<th scope=\"col\"><button data-key=\"elo\" data-dir=\"desc\">ELO</button></th>\n",
    "<th scope=\"col\" class=\"num\">&Delta; ELO</th>\n",
    "</tr></thead>"
  )

  rows <- vapply(seq_len(nrow(tabelle)), function(i) {
    row <- tabelle[i, ]
    paste0(
      "<tr data-platz=\"", row$platz, "\" data-pkt=\"", row$punkte,
      "\" data-elo=\"", row$elo, "\"", .zone_attrs(zonen, row$platz), ">",
      "<td class=\"num\">", row$platz, "</td>",
      "<th scope=\"row\">", .tooltip_html(row$name, row$kuerzel), "</th>",
      "<td class=\"num opt\">", row$spiele, "</td>",
      "<td class=\"num opt\">", .vorzeichen(row$tordifferenz, 0), "</td>",
      "<td class=\"num\">", row$punkte, "</td>",
      "<td class=\"num\">", .komma(row$elo, 1), "</td>",
      "<td class=\"num\">", .vorzeichen(row$delta_elo, 1), "</td>",
      "</tr>"
    )
  }, character(1))

  # data-zonen haelt fest, dass die aktuelle Sortierung die Zonen TRAEGT.
  # Sie gehoeren zum Tabellenplatz, nicht zum Team: Nach ELO sortiert
  # stuende sonst neben dem ELO-Schlechtesten ein rotes "steigt sicher ab",
  # obwohl er tabellarisch Achter ist. Das Sortierskript entfernt das
  # Attribut bei jeder anderen Spalte, das CSS blendet die Linien dann aus.
  #
  # Auch bei "Punkte", obwohl die Reihenfolge dort meist stimmt: Bei
  # Punktgleichheit entscheidet die Tordifferenz, und dann saesse die Linie
  # unbemerkt auf dem falschen Team. Eine Regel ohne Ausnahme ist hier
  # sicherer als eine mit einer seltenen.
  zonen_state <- if (is.null(zonen)) "" else " data-zonen=\"platz\""

  paste0(
    "<table class=\"liga\" id=\"ligatabelle\"", zonen_state, ">\n",
    header, "<tbody>", paste0(rows, collapse = ""), "</tbody></table>"
  )
}

#' Das Kleingedruckte unter der RL-Ligatabelle (Issue #185).
#'
#' Die Linien zeigen, WELCHER Platz betroffen ist; hier steht, WARUM die
#' Zahl schwankt und wie hoch sie je Platz ist. Bewusst klein und unter der
#' Tabelle: Wer es genau wissen will, findet es; alle anderen lesen die
#' Farbe.
#'
#' @param zonen Liste wie in render_liga_tabelle().
#' @param regel Ein Satz zur Abstiegsregel der Staffel.
#' @return HTML-Absatz.
#' Die Auf-/Abstiegszonen einer Liga, aus den Ergebnisobjekten des Zyklus.
#'
#' Das fehlende Glied zwischen Rechnung und Anzeige (Issue #185): Die
#' Bausteine liegen vor -- die Platzvektoren als Attribute an der
#' Abstiegsprognose, das zonen-Argument am Tabellenrenderer -- aber niemand
#' hat sie verbunden.
#'
#' DREI QUELLEN, und gruen ist der unangenehme Fall: Nordost, West und
#' SuedWest stellen je einen DIREKTEN Aufsteiger (promotion_slots = 1), dort
#' ist Platz 1 sicher und die Zahl kommt aus der Registry. Nord und Bayern
#' haben promotion_slots = 0 und kommen nur ueber das Aufstiegsspiel hoch;
#' dort traegt Platz 1 die Gewinnquote aus Ergebnis_<key>_aufstieg. Eine
#' Verwechslung hiesse, einen sicheren Aufstieg zu behaupten, den es nicht
#' gibt.
#'
#' @param view_key Schluessel der Liga, wie in league_registry().
#' @param data_env Umgebung mit den Ergebnisobjekten des Zyklus.
#' @return Liste (abstieg, relegation, aufstieg) oder NULL -- NULL heisst:
#'   Tabelle ohne Zonen, also zeichengleich wie vor Issue #185.
rl_zonen <- function(view_key, data_env) {
  eintrag <- league_registry()[[view_key]]
  if (is.null(eintrag) || !identical(eintrag$nav_group, "Regionalliga")) {
    return(NULL)
  }

  hole <- function(name) {
    if (exists(name, envir = data_env, inherits = FALSE)) {
      get(name, envir = data_env, inherits = FALSE)
    } else {
      NULL
    }
  }

  # Das Abstiegsobjekt ist die tragende Quelle: Ohne es gibt es GAR KEINE
  # Zonen. Der Loop laesst die RL-Spalten aus, wenn Voraussetzungen fehlen
  # (etwa ohne Zaehlung der 3. Liga) -- eine Liga ohne Linien ist besser als
  # eine mit Linien, die nur die halbe Wahrheit tragen.
  abstiegsobjekt <- hole(.ergebnis_objektname(paste0(view_key, "_abstieg")))
  if (is.null(abstiegsobjekt)) {
    return(NULL)
  }
  platz_abstieg <- attr(abstiegsobjekt, "platz_abstieg")
  if (is.null(platz_abstieg)) {
    return(NULL)
  }
  teams <- length(platz_abstieg)

  aufstieg <- numeric(teams)
  if (isTRUE(eintrag$promotion_slots >= 1L)) {
    # Direkter Aufstiegsplatz: keine Wahrscheinlichkeit im Spiel.
    aufstieg[seq_len(min(eintrag$promotion_slots, teams))] <- 1
  } else {
    # Nur ueber das Aufstiegsspiel. Fehlt die Spalte, bleibt Gruen leer --
    # die Abstiegslinien sind davon unberuehrt und bleiben vollstaendig.
    aufstiegsspalte <- hole(.ergebnis_objektname(paste0(view_key, "_aufstieg")))
    if (!is.null(aufstiegsspalte) && !is.null(aufstiegsspalte$Aufstieg)) {
      aufstieg[1] <- sum(aufstiegsspalte$Aufstieg)
    }
  }

  list(
    abstieg = platz_abstieg,
    # NULL statt Nullvektor: "gibt es nicht" und "moeglich, gerade null" sind
    # verschiedene Aussagen -- nur Bayern hat eine Abstiegsrelegation.
    relegation = attr(abstiegsobjekt, "platz_relegation"),
    aufstieg = aufstieg
  )
}

#' Ein Prozentwert fuer die Fussnote, in der Schreibweise der Seite.
#'
#' prozent() ersetzt 100 % durch ein Haekchen (render_helpers.R:37) -- so
#' halten es Heatmap und Panels. Ein "%" dahinter waere dann falsch: Das
#' Haekchen IST die Aussage, keine Zahl. Gefunden bei der QA am gerenderten
#' HTML, wo "Platz 18: \u2713 %" stand.
.zone_prozent <- function(p) {
  wert <- prozent(p)
  if (identical(as.character(wert), intToUtf8(0x2713))) {
    as.character(wert)
  } else {
    paste0(wert, "\u00a0%")
  }
}

#' Verteilung der Absteigerzahl, aus dem Platzvektor zurueckgewonnen.
#'
#' Bei Nord, Nordost und SuedWest steht nicht fest, wie viele Vereine
#' absteigen -- die Zahl haengt an der 3. Liga. Die Fussnote soll das nennen,
#' bevor sie die Platz-Wahrscheinlichkeiten zeigt.
#'
#' Dafuer braucht es weder eine neue Rechnung noch die Zaehlmatrix der
#' 3. Liga (die lebt nur im Loop und erreicht den Generator gar nicht):
#' `platz_gewichte()` IST die Ueberlebensfunktion P(Zahl der Absteiger >= j),
#' von hinten gelesen. Sie faellt monoton von 1 auf 0; ihre Differenzen sind
#' P(genau j). Linien und Fussnote haben damit eine einzige Quelle und
#' koennen nicht auseinanderlaufen.
#'
#' Nebeneffekt: Liefert eine Regel fuer zwei verschiedene Drittliga-Faelle
#' dieselbe Absteigerzahl (Nordost bei einem und bei zwei Absteigern), faellt
#' das hier zusammen -- gerechnet wird ueber die Zahl, nicht ueber den
#' Zwischenschritt.
#'
#' @param platz_abstieg Vektor je Platz, monoton fallend.
#' @return Benannter Vektor: Namen = Zahl der Absteiger, Werte = P. Nur
#'   Eintraege mit P > 0.
absteigerzahl_verteilung <- function(platz_abstieg) {
  n <- length(platz_abstieg)
  # P(>= j) ist der Wert am j-letzten Platz; P(genau j) die Differenz zum
  # naechsten. Der letzte Schritt hat keinen Nachfolger -> 0.
  zahlen <- integer(0)
  p <- numeric(0)
  for (j in seq_len(n)) {
    oben <- platz_abstieg[[n - j + 1]]
    unten <- if (n - j >= 1) platz_abstieg[[n - j]] else 0
    diff <- oben - unten
    if (diff > 1e-9) {
      zahlen <- c(zahlen, j)
      p <- c(p, diff)
    }
  }
  stats::setNames(p, as.character(zahlen))
}

render_zonen_fussnote <- function(zonen, regel) {
  # Nur Plaetze MIT Risiko. Alle 18 aufzuzaehlen hiesse, 16-mal "0 %" zu
  # schreiben -- das verdeckt die drei Zahlen, auf die es ankommt.
  eintrag <- function(vektor, klasse, wort) {
    if (is.null(vektor)) {
      return(character(0))
    }
    plaetze <- which(vektor > 0)
    if (length(plaetze) == 0) {
      return(character(0))
    }
    teile <- vapply(plaetze, function(p) {
      sprintf("Platz %d: %s", p, .zone_prozent(vektor[[p]]))
    }, character(1))
    paste0(
      "<span class=\"zone-key ", klasse, "\"></span>", wort, " \u2014 ",
      paste(teile, collapse = ", "), "."
    )
  }

  # Wie viele steigen ueberhaupt ab? Steht die Zahl fest, entfaellt der Satz:
  # "4 Absteiger mit 100 %" saehe aus, als gaebe es eine Unsicherheit.
  verteilung <- absteigerzahl_verteilung(zonen$abstieg)
  verteilungssatz <- if (length(verteilung) > 1L) {
    teile <- vapply(names(verteilung), function(z) {
      sprintf("%s mit %s", z, .zone_prozent(verteilung[[z]]))
    }, character(1))
    paste0("Zahl der Absteiger: ", paste(teile, collapse = ", "), ".")
  } else {
    character(0)
  }

  saetze <- c(
    eintrag(zonen$aufstieg, "aufstieg", "Aufstieg"),
    eintrag(zonen$relegation, "relegation", "Relegation"),
    eintrag(zonen$abstieg, "abstieg", "Abstieg")
  )

  paste0(
    "<p class=\"zonen-fussnote\">",
    htmltools::htmlEscape(regel), " ",
    # Die Verteilung steht VOR der Platzliste: erst warum die Zahl
    # schwankt, dann was daraus je Platz folgt.
    if (length(verteilungssatz) > 0) paste0(verteilungssatz, " ") else "",
    paste(saetze, collapse = " "),
    "</p>"
  )
}

.LIGA_SORT_SCRIPT <- paste0(
  "<script>\n(function(){\n",
  "  var table=document.getElementById('ligatabelle');\n",
  "  if(!table)return;\n",
  "  var tbody=table.tBodies[0];\n",
  "  table.querySelectorAll('th button[data-key]').forEach(function(btn){\n",
  "    btn.addEventListener('click',function(){\n",
  "      var key=btn.dataset.key, dir=btn.dataset.dir;\n",
  # Zonen gehoeren zum Tabellenplatz: bei jeder anderen Sortierung weg.
  "      if(table.hasAttribute('data-zonen')||key==='platz'){\n",
  "        if(key==='platz'){table.setAttribute('data-zonen','platz');}\n",
  "        else{table.removeAttribute('data-zonen');}\n",
  "      }\n",
  "      table.querySelectorAll('th button').forEach(function(b){b.removeAttribute('aria-sort')});\n",
  "      btn.setAttribute('aria-sort',dir==='asc'?'ascending':'descending');\n",
  "      var rows=Array.prototype.slice.call(tbody.rows);\n",
  "      rows.sort(function(a,b){\n",
  "        var va=parseFloat(a.dataset[key]),vb=parseFloat(b.dataset[key]);\n",
  "        return dir==='asc'?va-vb:vb-va;\n",
  "      });\n",
  "      rows.forEach(function(r){tbody.appendChild(r)});\n",
  "    });\n",
  "  });\n",
  "})();\n</script>"
)

# --- Phase 4b: Rückblick- und Live-Sektion --------------------------------

.WOCHENTAGE_KURZ <- c("So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa.")

# Anstoßzeit (UTC, wie aus league_details.R) als Berliner Zeit formatiert:
# "Wd. T.M., HH:MM<NNBSP>Uhr" — Tag/Monat ohne führende Null. Bei offener
# Anstoßzeit (TBD, Issue #230) "Wd. T.M., Zeit offen": Die API-Uhrzeit ist
# dann nur ein Platzhalter.
.mwhen <- function(kickoff, zeit_offen = FALSE) {
  lt <- as.POSIXlt(kickoff, tz = "Europe/Berlin")
  wd <- .WOCHENTAGE_KURZ[lt$wday + 1]
  tag <- as.integer(format(lt, "%d"))
  monat <- as.integer(format(lt, "%m"))
  if (isTRUE(zeit_offen)) {
    return(paste0(wd, " ", tag, ".", monat, ".,", " Zeit offen"))
  }
  zeit <- format(lt, "%H:%M")
  paste0(wd, " ", tag, ".", monat, ".,", " ", zeit, " Uhr")
}

# 1/X/2-Balken: Segmente Heim/Remis/Gast aus den ex-ante-Wahrscheinlichkeiten;
# Remis wird als Rest (100 - Heim - Gast) berechnet, nicht separat gerundet,
# damit die drei Werte immer exakt 100 ergeben (Mock-up-Regel). Segmente
# unter 8 % verlieren ihr Zahlen-Label (bleiben aber als Farbfläche sichtbar).
.oddsbar <- function(p_home, p_draw, p_away) {
  h <- round(100 * p_home)
  a <- round(100 * p_away)
  x <- 100 - h - a

  seg <- function(cls, wert) {
    nolabel <- if (wert < 8) " nolabel" else ""
    paste0("<span class=\"", cls, nolabel, "\" style=\"flex-basis:", wert, "%\">",
          "<i>", wert, "</i></span>")
  }

  aria <- paste0("Sieg Heim ", h, " %, Remis ", x, " %, Sieg Gast ", a, " %")

  paste0(
    "<div class=\"oddsbar\" role=\"img\" aria-label=\"",
    htmltools::htmlEscape(aria), "\">",
    seg("oh", h), seg("ox", x), seg("oa", a),
    "</div>"
  )
}

# ELO-Anpassung als Heim/Gast-Paar; bei NA (Nachholspiele, die noch nicht
# gespielt sind, tauchen hier nicht auf, aber die dritte Rückblick-Zeile im
# Mock-up hat absichtlich NA) auf beiden Seiten ein Halbgeviertstrich, nie
# "NA" im Markup.
.melo <- function(delta_home) {
  if (is.na(delta_home)) {
    return("– / –")
  }
  heim <- .vorzeichen(delta_home, 1)
  gast <- .vorzeichen(-delta_home, 1)
  paste0(heim, " / ", gast)
}

# Überschrift der Rückblick-Sektion: "N. Spieltag" bei einer Runde,
# "N./M. Spieltag" bei mehreren (Rundennummern mit "/" verbunden, ein
# gemeinsamer Punkt am Ende — z.B. "1./2. Spieltag").
.spieltag_ueberschrift <- function(runden) {
  paste0(paste(runden, collapse = "./"), ". Spieltag")
}

# Paarung "Heim – Gast" mit htmltools-Escaping und dem Halbgeviertstrich
# als eigenem Span (fuer CSS-Faerbung). Gemeinsam fuer Rueckblick-, Live- und
# (4c) Ausblick-Zeilen, die alle dieselbe Paarungsdarstellung brauchen.
.match_pair <- function(home_name, away_name) {
  paste0(
    htmltools::htmlEscape(home_name),
    "<span class=\"dash\"> – </span>",
    htmltools::htmlEscape(away_name)
  )
}

# Ergebnis "H:A" (Rueckblick/Live; fuer Live ist es der laufende Zwischenstand).
# NA-Guard (4b-Review-Uebertrag): fehlende Tore -> "–:–" (Halbgeviertstriche),
# nie "NA:NA" im Markup. Betrifft z.B. Live-Zeilen, deren Tore noch nicht
# uebermittelt wurden.
.match_ergebnis <- function(goals_home, goals_away) {
  if (is.na(goals_home) || is.na(goals_away)) {
    return("–:–")
  }
  paste0(goals_home, ":", goals_away)
}

.match_zeile <- function(row) {
  nachhol <- if (isTRUE(row$nachholspiel)) {
    paste0("<span class=\"nachhol\">Nachholspiel, ", row$round, ". Spieltag</span>")
  } else {
    ""
  }

  # Am grünen Tisch gewertete Spiele als solche ausweisen: Das Ergebnis zählt
  # für die Tabelle, wurde aber nicht erspielt -- und die ELO-Spalte bleibt
  # deshalb leer (Issue #157). Ohne Hinweis sähe das wie ein Datenfehler aus.
  wertung <- if (!is.null(row$status) && row$status %in% c("AWD", "WO")) {
    "<span class=\"nachhol\">Wertung</span>"
  } else {
    ""
  }

  paste0(
    "<div class=\"match\">\n",
    "<div class=\"mwhen\">", .mwhen(row$kickoff), "</div>\n",
    "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
    .oddsbar(row$p_home_win, row$p_draw, row$p_away_win), "\n",
    "<div class=\"mres\">", .match_ergebnis(row$goals_home, row$goals_away), "</div>\n",
    "<div class=\"melo\" title=\"ELO-Anpassung Heim / Gast\">",
    .melo(row$elo_delta_home), "</div>\n",
    nachhol,
    wertung,
    "</div>\n"
  )
}

# Rückblick-Sektion: gefensterte, gejointe Spielliste + Spieltagsnummern
# für die Überschrift ("N. Spieltag" bzw. "N./M. Spieltag").
render_rueckblick <- function(rueckblick, runden) {
  zeilen <- vapply(seq_len(nrow(rueckblick)), function(i) {
    .match_zeile(rueckblick[i, ])
  }, character(1))

  paste0(
    "<section id=\"rueckblick\">\n",
    "<p class=\"eyebrow\">Rückblick</p>\n",
    "<h2>", .spieltag_ueberschrift(runden), "</h2>\n",
    "<p class=\"oddslegend\">Balken: Wahrscheinlichkeit vor dem Spiel in Prozent ",
    "—<span class=\"chip h\"></span><b>Sieg Heim</b>",
    "<span class=\"chip x\"></span><b>Remis</b>",
    "<span class=\"chip a\"></span><b>Sieg Gast</b> · rechts: Ergebnis und ",
    "ELO-Anpassung Heim / Gast</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}

# Live-Sektion: Zwischenstände ohne Prognose (Planergänzung 8a);
# leeres Fenster -> "".
render_live <- function(live) {
  if (nrow(live) == 0) {
    return("")
  }

  zeilen <- vapply(seq_len(nrow(live)), function(i) {
    row <- live[i, ]
    paste0(
      "<div class=\"match live\">\n",
      "<div class=\"mwhen\">", .mwhen(row$kickoff), "</div>\n",
      "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
      "<div class=\"mres\">", .match_ergebnis(row$goals_home, row$goals_away), "</div>\n",
      "</div>\n"
    )
  }, character(1))

  paste0(
    "<section id=\"live\">\n",
    "<p class=\"eyebrow\">Live</p>\n",
    "<h2>Laufende Spiele</h2>\n",
    "<p class=\"sectionlead\">Prognosen werden während des Spiels nicht ",
    "aktualisiert.</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}

# --- Phase 4c: Ausblick-Sektion --------------------------------------------

# Deutsche Ein-Nachkommastellen-Prozentzelle für die Ergebnis-Matrix; Werte
# unter 0,1 % (0.001) bleiben leer statt auf "0,0" zu runden.
.score_zelle_text <- function(p) {
  if (p < 0.001) {
    ""
  } else {
    .komma(100 * p, 1)
  }
}

# Eine Ergebnis-Matrix (score_matrix, quadratisch: 0..(n-2) Tore, letzte
# Zeile/Spalte = Restmasse "n-1+") als <table class="score">. Färbung wie im
# Mock-up über .heat_style((p / Zellenmaximum) * 0.75) — die Spitzenzelle
# bekommt so t = 0.75 statt volle Tinte. Anteil wird auf 1 geclamped
# (Rundungsdrift/entartete Matrizen), sonst würde .heat_style() bei > 1
# negative RGB-Kanäle erzeugen (ungültiges CSS, Zelle rendert weiß auf weiß).
.render_score_matrix <- function(m) {
  n <- nrow(m)
  achse <- c(as.character(seq_len(n - 1) - 1), paste0(n - 1, "+"))
  zellenmax <- max(m)

  header <- paste0(
    "<thead><tr><th class=\"corner\"><span>Heim&nbsp;&#8595;&nbsp;&middot;&nbsp;Gast&nbsp;&#8594;</span></th>",
    paste0("<th>", achse, "</th>", collapse = ""),
    "</tr></thead>"
  )

  rows <- vapply(seq_len(n), function(i) {
    cells <- paste0(vapply(seq_len(n), function(j) {
      p <- m[i, j]
      anteil <- if (is.finite(zellenmax) && zellenmax > 0) (p / zellenmax) * 0.75 else 0
      anteil <- min(1, anteil)
      paste0("<td style=\"", .heat_style(anteil), "\">",
             .score_zelle_text(p), "</td>")
    }, character(1)), collapse = "")
    paste0("<tr><th scope=\"row\">", achse[i], "</th>", cells, "</tr>")
  }, character(1))

  paste0(
    "<table class=\"score\" aria-label=\"Wahrscheinlichkeit je Ergebnis in Prozent\">\n",
    header, "\n<tbody>", paste0(rows, collapse = ""), "</tbody></table>"
  )
}

.ausblick_zeile <- function(row) {
  nachhol <- if (isTRUE(row$nachholspiel)) {
    paste0("<span class=\"nachhol\">Nachholspiel, ", row$round, ". Spieltag</span>")
  } else {
    ""
  }

  paste0(
    "<div class=\"match outlook\">\n",
    "<div class=\"mwhen\">", .mwhen(row$kickoff, row$zeit_offen), "</div>\n",
    "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
    .oddsbar(row$p_home_win, row$p_draw, row$p_away_win), "\n",
    "<details class=\"mscore\"><summary>Ergebnis-Matrix</summary>",
    .render_score_matrix(row$score_matrix[[1]]), "</details>\n",
    nachhol,
    "</div>\n"
  )
}

# Ausblick-Sektion: kommende Spiele mit 1/X/2-Balken und aufklappbarer
# Ergebnis-Matrix (Score-Matrix aus der Endpoint-Antwort).
render_ausblick <- function(ausblick, runde) {
  zeilen <- vapply(seq_len(nrow(ausblick)), function(i) {
    .ausblick_zeile(ausblick[i, ])
  }, character(1))

  paste0(
    "<section id=\"ausblick\">\n",
    "<p class=\"eyebrow\">Ausblick</p>\n",
    "<h2>", .spieltag_ueberschrift(runde), "</h2>\n",
    "<p class=\"sectionlead\">Die Wahrscheinlichkeiten für die kommenden ",
    "Spiele, gerechnet mit den ELO-Werten von heute. Die Ergebnis-Matrix ",
    "zeigt je Paarung die Wahrscheinlichkeit jedes Endstands.</p>\n",
    "<p class=\"oddslegend\">Balken: <span class=\"chip h\"></span><b>Sieg Heim</b>",
    "<span class=\"chip x\"></span><b>Remis</b>",
    "<span class=\"chip a\"></span><b>Sieg Gast</b> — Angaben in Prozent</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}

# Kuerzel-Tooltips zum Antippen. `title` zeigt den Namen nur bei Mausberuehrung;
# Touch-Geraete haben kein Hover. Ein Tipp (oder Enter/Fokus per Tastatur) auf
# ein abbr.kz blendet den Namen als kleines Label darunter ein, ein Tipp
# daneben, Escape oder Scrollen blendet es aus. Das Label haengt am <body> und
# wird fix positioniert, weil Heatmap und Panels in Scroll-Containern stehen,
# die ein absolut positioniertes Kind abschneiden wuerden.
.KUERZEL_SCRIPT <- paste0(
  "<script>\n(function(){\n",
  "  var tip=null, akt=null;\n",
  "  function zu(){if(tip){tip.hidden=true;}akt=null;}\n",
  "  function auf(el){\n",
  "    if(!tip){tip=document.createElement('div');tip.className='kz-tip';",
  "tip.setAttribute('role','tooltip');document.body.appendChild(tip);}\n",
  "    tip.textContent=el.getAttribute('title');tip.hidden=false;akt=el;\n",
  "    var r=el.getBoundingClientRect();\n",
  "    var x=Math.min(r.left,window.innerWidth-tip.offsetWidth-8);\n",
  "    tip.style.left=Math.max(8,x)+'px';tip.style.top=(r.bottom+4)+'px';\n",
  "  }\n",
  "  document.addEventListener('click',function(e){\n",
  "    var el=e.target.closest?e.target.closest('abbr.kz'):null;\n",
  "    if(el&&el!==akt){auf(el);}else{zu();}\n",
  "  });\n",
  "  document.addEventListener('keydown',function(e){\n",
  "    if(e.key==='Escape'){zu();}\n",
  "    else if(e.key==='Enter'&&e.target.matches&&e.target.matches('abbr.kz')){auf(e.target);}\n",
  "  });\n",
  "  window.addEventListener('scroll',zu,true);\n",
  "  window.addEventListener('resize',zu);\n",
  "})();\n</script>"
)
