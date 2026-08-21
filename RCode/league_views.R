# Per-league view configuration for the static site.
#
# Transcribed from the Shiny server logic in ShinyApp/app.R. The leagues are
# deliberately asymmetric: 3. Liga's promotion table is built from
# Ergebnis3_Aufstieg, while its relegation table and heatmap use Ergebnis3.

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
    )
  )
}
