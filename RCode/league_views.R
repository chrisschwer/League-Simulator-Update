# Per-league view configuration for the static site.
#
# Transcribed from the Shiny server logic in ShinyApp/app.R. Two leagues are
# deliberately asymmetric: 3. Liga and 2. Frauen-Bundesliga build their
# promotion table from a separate simulation run (second teams carry a -50
# penalty and are thus out of the race), while relegation table and heatmap
# use the regular forecast.
#
# Panel-Grenzen duerfen NEGATIV sein; sie zaehlen dann von unten (-1 = letzter
# Platz) und werden zur Renderzeit gegen die tatsaechliche Ligagroesse
# aufgeloest. Noetig fuer Ligen mit schwankender Teamzahl -- die
# Frauen-Bundesliga ist 2025 von 12 auf 14 gewachsen.
#
# Die europaeischen Plaetze stehen bewusst hier und nicht in der Registry:
# Sie folgen dem UEFA-Koeffizienten und aendern sich unabhaengig von Auf- und
# Abstieg.
#
# ---------------------------------------------------------------------------
# `computed`: Panels, die KEINE Platzgruppe sind (Phase 5, Regionalligen)
# ---------------------------------------------------------------------------
#
# Bis zu den Regionalligen war jedes Panel eine Summe von Platzspalten: "die
# letzten beiden", "Platz 1". Das setzt voraus, dass feststeht, WELCHE Plaetze
# gemeint sind. Fuer die Regionalligen steht das nicht fest:
#
#   Abstieg   Nord, Nordost und SuedWest bekommen je Drittliga-Absteiger einen
#             Abstiegsplatz mehr; wie viele es werden, weiss erst die
#             Simulation der 3. Liga (RCode/rl_abstiegskopplung.R). West und
#             Bayern sind zwar konstant, aber West muesste "die letzten vier"
#             bei schwankender Ligagroesse als NEGATIVE Grenze schreiben --
#             genau die Stelle, an der dieses Projekt schon zweimal falsch
#             gerechnet hat -- und Bayern weist unten ZWEI Groessen aus.
#   Aufstieg  Nord und Bayern haben 2026/27 keinen Direktplatz. Ihre
#             Aufstiegswahrscheinlichkeit ist eine Doppelsumme ueber beide
#             Staffeln (RCode/rl_aufstieg.R) und strikt kleiner als P(Meister).
#
# Beides kommt deshalb als FERTIGE Spalte herein statt als Platzband. Das Feld
# `computed` sagt das ausdruecklich -- ein Panel ohne `groups` waere sonst nur
# ein Fehlen, das der Renderer interpretieren muesste:
#
#   computed = TRUE          ganzes Panel berechnet; dann darf weder `groups`
#                            noch `filter_cols` dastehen, und `source` zeigt
#                            auf das fertige Objekt (Spalten = `labels`).
#   computed = c(FALSE,TRUE) gemischtes Panel: die erste Spalte ist eine echte
#                            Platzgruppe aus `source`/`groups`, die zweite
#                            kommt aus `computed_source`. Ein Eintrag je Label.
#
# Die Reihenfolge der Eintraege in `computed` ist die der `labels`; `groups`
# traegt nur die Spalten, fuer die `computed` FALSE ist.

league_views <- function() {
  views <- list(
    bundesliga = list(
      slug = "index",
      nav_label = "Bundesliga",
      plot_title = "Saisonprognose Bundesliga",
      plot_source = "Ergebnis",
      teams = 18L,
      top = list(
        source = "Ergebnis",
        filter_cols = 1:6,
        labels = c("Meister", "Champions League", "Europa League",
                   "Conference League Quali"),
        groups = cbind(c(1, 1), c(2, 4), c(5, 5), c(6, 6))
      ),
      bottom = list(
        source = "Ergebnis",
        filter_cols = 16:18,
        labels = c("Relegation", "Abstieg"),
        groups = cbind(c(16, 16), c(17, 18))
      )
    ),
    zweite_bundesliga = list(
      slug = "2-bundesliga",
      nav_label = "2. Bundesliga",
      plot_title = "Saisonprognose 2. Bundesliga",
      plot_source = "Ergebnis2",
      teams = 18L,
      top = list(
        source = "Ergebnis2",
        filter_cols = 1:3,
        labels = c("Aufstieg", "Relegation Bundesliga"),
        groups = cbind(c(1, 2), c(3, 3))
      ),
      bottom = list(
        source = "Ergebnis2",
        filter_cols = 16:18,
        labels = c("Relegation 3. Liga", "Abstieg"),
        groups = cbind(c(16, 16), c(17, 18))
      )
    ),
    dritte_liga = list(
      slug = "3-liga",
      nav_label = "3. Liga",
      plot_title = "Saisonprognose 3. Liga",
      plot_source = "Ergebnis3",
      teams = 20L,
      top = list(
        source = "Ergebnis3_Aufstieg",
        filter_cols = 1:4,
        labels = c("Aufstieg", "Relegation", "DFB-Pokal"),
        groups = cbind(c(1, 2), c(3, 3), c(4, 4))
      ),
      bottom = list(
        source = "Ergebnis3",
        filter_cols = 17:20,
        labels = "Abstieg",
        groups = cbind(c(17, 20))
      )
    ),
    frauen_bundesliga = list(
      slug = "frauen-bundesliga",
      nav_label = "Bundesliga",
      plot_title = "Saisonprognose Frauen-Bundesliga",
      plot_source = "Ergebnis_frauen_bundesliga",
      teams = 14L,
      # Oberste Liga ihrer Wechselgemeinschaft: kein Aufstieg, dafuer
      # europaeische Plaetze. Der Meister erreicht direkt die Ligaphase der
      # Champions League, Vizemeister und Dritter die Qualifikation.
      top = list(
        source = "Ergebnis_frauen_bundesliga",
        filter_cols = 1:3,
        labels = c("Meister", "Champions League Quali"),
        groups = cbind(c(1, 1), c(2, 3))
      ),
      # Negative Grenzen: die letzten zwei, unabhaengig von der Ligagroesse.
      # Die Liga ist 2025 von 12 auf 14 Teams gewachsen.
      bottom = list(
        source = "Ergebnis_frauen_bundesliga",
        filter_cols = c(-2, -1),
        labels = "Abstieg",
        groups = cbind(c(-2, -1))
      )
    ),
    zweite_frauen_bundesliga = list(
      slug = "2-frauen-bundesliga",
      nav_label = "2. Bundesliga",
      plot_title = "Saisonprognose 2. Frauen-Bundesliga",
      plot_source = "Ergebnis_zweite_frauen_bundesliga",
      teams = 14L,
      # Dieselbe Asymmetrie wie in der 3. Liga: Zweitvertretungen duerfen
      # nicht aufsteigen, die Aufstiegstabelle kommt deshalb aus dem
      # Sonderlauf mit -50-Malus -- Heatmap und Abstieg aus der regulaeren
      # Prognose.
      top = list(
        source = "Ergebnis_zweite_frauen_bundesliga_aufstieg",
        filter_cols = 1:2,
        labels = "Aufstieg",
        groups = cbind(c(1, 2))
      ),
      # "Die letzten drei Mannschaften steigen ab" -- in die
      # Frauen-Regionalligen, die wir nicht fuehren.
      bottom = list(
        source = "Ergebnis_zweite_frauen_bundesliga",
        filter_cols = c(-3, -2, -1),
        labels = "Abstieg",
        groups = cbind(c(-3, -1))
      )
    ),

    # --- Regionalligen ------------------------------------------------------
    # Reihenfolge wie in der Registry: Nord, Nordost, West, SuedWest, Bayern.
    #
    # Alle fuenf lesen ihr unteres Panel aus einem eigenen Objekt
    # (Ergebnis_<schluessel>_abstieg, die Ausgabe von rl_abstiegsprognose()).
    # Die drei Direktaufsteiger 2026/27 lesen ihr oberes Panel dagegen als
    # gewoehnliche Platzgruppe -- dort ist P(Aufstieg) = P(Meister), und eine
    # berechnete Spalte waere derselbe Wert auf einem laengeren Weg.
    #
    # Die Meisterspalte kommt aus derselben Prognosematrix wie die Heatmap,
    # nicht aus einem Sonderlauf: Die Aufstiegsseite rechnet die
    # Zweitvertretungen heraus (rl_aufstiegsprognose() bekommt die
    # Aufstiegsvariante), die LIGA-Seite zeigt dagegen die Meisterchance so,
    # wie sie sportlich zustande kommt. Ein Sonderlauf hier haette auf der
    # Ligaseite eine Meisterchance von 0 fuer ein Team gezeigt, das sehr wohl
    # Meister werden kann -- nur eben nicht aufsteigen darf.
    rl_nord = list(
      slug = "rl-nord",
      nav_label = "Nord",
      plot_title = "Saisonprognose Regionalliga Nord",
      plot_source = "Ergebnis_rl_nord",
      teams = 18L,
      # Kein Direktplatz 2026/27: Meister zu werden reicht nicht, es folgen
      # zwei Aufstiegsspiele. Beide Groessen stehen deshalb nebeneinander --
      # eine einzige Spalte "Aufstieg" ueber P(Platz 1) waere die Behauptung
      # "Meister = Aufsteiger" und damit falsch.
      top = list(
        source = "Ergebnis_rl_nord",
        computed = c(FALSE, TRUE),
        computed_source = "Ergebnis_rl_nord_aufstieg",
        filter_cols = 1L,
        labels = c("Meister", "Aufstieg"),
        groups = cbind(c(1, 1))
      ),
      bottom = list(
        source = "Ergebnis_rl_nord_abstieg",
        computed = TRUE,
        labels = "Abstieg"
      )
    ),
    rl_nordost = list(
      slug = "rl-nordost",
      nav_label = "Nordost",
      plot_title = "Saisonprognose Regionalliga Nordost",
      plot_source = "Ergebnis_rl_nordost",
      teams = 18L,
      top = list(
        source = "Ergebnis_rl_nordost",
        filter_cols = 1L,
        labels = "Aufstieg",
        groups = cbind(c(1, 1))
      ),
      bottom = list(
        source = "Ergebnis_rl_nordost_abstieg",
        computed = TRUE,
        labels = "Abstieg"
      )
    ),
    rl_west = list(
      slug = "rl-west",
      nav_label = "West",
      plot_title = "Saisonprognose Regionalliga West",
      plot_source = "Ergebnis_rl_west",
      teams = 18L,
      top = list(
        source = "Ergebnis_rl_west",
        filter_cols = 1L,
        labels = "Aufstieg",
        groups = cbind(c(1, 1))
      ),
      bottom = list(
        source = "Ergebnis_rl_west_abstieg",
        computed = TRUE,
        labels = "Abstieg"
      )
    ),
    rl_suedwest = list(
      slug = "rl-suedwest",
      nav_label = "SüdWest",
      plot_title = "Saisonprognose Regionalliga SüdWest",
      plot_source = "Ergebnis_rl_suedwest",
      teams = 18L,
      top = list(
        source = "Ergebnis_rl_suedwest",
        filter_cols = 1L,
        labels = "Aufstieg",
        groups = cbind(c(1, 1))
      ),
      bottom = list(
        source = "Ergebnis_rl_suedwest_abstieg",
        computed = TRUE,
        labels = "Abstieg"
      )
    ),
    rl_bayern = list(
      slug = "rl-bayern",
      nav_label = "Bayern",
      plot_title = "Saisonprognose Regionalliga Bayern",
      plot_source = "Ergebnis_rl_bayern",
      # 2026/27 mit 19 Vereinen; die Zahl ist Anzeigehinweis, gerechnet wird
      # gegen die tatsaechliche Spaltenzahl der Prognosematrix.
      teams = 19L,
      top = list(
        source = "Ergebnis_rl_bayern",
        computed = c(FALSE, TRUE),
        computed_source = "Ergebnis_rl_bayern_aufstieg",
        filter_cols = 1L,
        labels = c("Meister", "Aufstieg"),
        groups = cbind(c(1, 1))
      ),
      # Zwei Groessen, die NICHT verrechnet werden: die zwei Letzten steigen
      # direkt ab, die zwei davor gehen in die Relegation gegen zwei
      # Bayernligisten. Die Relegation bleibt bewusst unaufgeloest -- wir
      # simulieren die Bayernligen nicht, jede Gewinnquote waere erfunden.
      bottom = list(
        source = "Ergebnis_rl_bayern_abstieg",
        computed = TRUE,
        labels = c("Relegation", "Abstieg")
      )
    )
  )

  # Die Aufstiegsseite ist KEINE Liga: kein api-football-Wettbewerb, keine
  # Heatmap, kein Registry-Eintrag. Sie fasst die fuenf Staffeln zu der einen
  # Frage zusammen, die ueber ihre Grenzen hinweg gestellt wird -- wer steigt
  # in die 3. Liga auf.
  #
  # Deshalb steht sie NEBEN der Ligaliste, nicht darin: names(league_views())
  # ist an mehreren Stellen die Ligamenge (sie wird gegen names(
  # league_registry()) geprueft, der Loop und der Renderer iterieren
  # darueber). Ein elftes Element haette dort ueberall eine Liga vorgetaeuscht,
  # die es nicht gibt.
  #
  # Ueber `[[` bleibt sie trotzdem unter ihrem Slug erreichbar, damit der
  # Generator sie wie jede andere Ansicht nachschlagen kann.
  structure(
    views,
    class = "league_views",
    zusatzseiten = list(`rl-aufstieg` = aufstiegsseite_view())
  )
}

#' Nachschlagen einer Ansicht ueber ihren Schluessel oder Slug.
#'
#' Faellt auf die Zusatzseiten zurueck, wenn der Name keine Liga ist. Alles
#' andere -- Laenge, names(), Iteration, einfache Klammer -- verhaelt sich
#' unveraendert wie bei der Liste, die es vorher war.
`[[.league_views` <- function(x, i, ...) {
  ligen <- unclass(x)
  if (is.character(i) && length(i) == 1L && !(i %in% names(ligen))) {
    zusatz <- attr(x, "zusatzseiten")
    if (!is.null(zusatz) && i %in% names(zusatz)) {
      return(zusatz[[i]])
    }
  }
  ligen[[i]]
}

#' `$` folgt demselben Weg wie `[[`, damit views$`rl-aufstieg` nicht anders
#' antwortet als views[["rl-aufstieg"]].
`$.league_views` <- function(x, name) {
  x[[name]]
}

#' Die Seite "Aufstieg in die 3. Liga".
#'
#' Variante 2 der Entwurfsvarianten (Entscheidung 2026-09-07): Randsummen je
#' Team statt der vollen 18x19-Paarungsmatrix. Die Matrix haette 342 Zellen,
#' fast alle nahe null -- sie zeigt viel und sagt wenig. Die Randsummen sind
#' dieselbe Information, ueber den Gegner ausintegriert.
#'
#' Vier Spalten: Team, P(Meister), P(Aufstieg), Siegquote. Die Siegquote ist
#' der Quotient P(Aufstieg)/P(Meister) -- die ueber den Gegner ausintegrierte
#' Zweikampfquote. Fuer die Direktaufsteiger ist sie definitionsgemaess 1.
#'
#' `staffeln` steht hier und nicht im Renderer: WELCHE Staffel die
#' Aufstiegsspiele bestreitet, entscheidet aufstiegsmodus() je Saison. Die
#' Seite kennt nur die fuenf Staffeln, nicht die Paarung.
aufstiegsseite_view <- function() {
  list(
    slug = "rl-aufstieg",
    nav_label = "Aufstieg",
    nav_group = "Regionalliga",
    plot_title = "Aufstieg in die 3. Liga",
    columns = c("Meister", "Aufstieg", "Siegquote"),
    staffeln = c("Nord", "Nordost", "West", "SuedWest", "Bayern")
  )
}
