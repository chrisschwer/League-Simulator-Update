# Umzugsbanner: the final, data-free app deployed to shinyapps.io once, after
# the static site at fussball.csdatascience.de has taken over. Plain notice
# plus link — no auto-redirect, no data, no computation.
#
# Deploy (one-off, from a developer machine): see README.md in this directory.

library(shiny)

NEW_URL <- "https://fussball.csdatascience.de"

ui <- fluidPage(
  tags$head(tags$title("Fußball-Prognosen von 30Punkte – umgezogen")),
  titlePanel("Fußball-Prognosen von 30Punkte"),
  mainPanel(
    h3("Die Prognosen sind umgezogen"),
    p(
      "Die Saisonprognosen für Bundesliga, 2. Bundesliga und 3. Liga finden ",
      "Sie ab sofort unter"
    ),
    p(tags$a(href = NEW_URL, NEW_URL, style = "font-size:1.3em;font-weight:bold")),
    p("Bitte aktualisieren Sie Ihr Lesezeichen. Diese Seite wird nicht mehr ",
      "aktualisiert und im Herbst 2026 abgeschaltet."),
    helpText(
      "Nähere Infos unter ",
      a("30punkte.wordpress.com", href = "http://30punkte.wordpress.com",
        target = "blank_")
    )
  )
)

server <- function(input, output) {}

shinyApp(ui = ui, server = server)
