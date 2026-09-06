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

league_views <- function() {
  list(
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
    )
  )
}
