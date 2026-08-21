#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# revert to app_normal after 2021/2022 season

library(shiny)
library(reshape2)
library(ggplot2)


source("app_helpers.R", local = TRUE)
source("../RCode/render_helpers.R", local = TRUE)

data_loaded <- load_results("data/Ergebnis.Rds", environment())
updatetime <- if (data_loaded) {
  as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "Europe/Berlin")
} else {
  NULL
}
stale_message <- if (data_loaded) {
  stale_warning_text(data_age_hours(updatetime))
} else {
  NULL
}


# Define UI for application that draws a histogram
ui <- shinyUI(fluidPage(

   # Application title
   titlePanel("Fußball-Prognosen von 30Punkte"),

   if (!data_loaded) {
     mainPanel(
       h3("Noch keine Prognosedaten verfügbar"),
       p("Die Simulationsergebnisse wurden noch nicht erzeugt oder konnten",
         "nicht geladen werden. Bitte versuchen Sie es später erneut."),
       helpText("Nähere Infos unter ",
                a("30punkte.wordpress.com",
                  href = "http://30punkte.wordpress.com", target = "blank_"))
     )
   } else {
     verticalLayout(
       mainPanel(
         if (!is.null(stale_message)) {
           div(
             style = paste(
               "background-color:#f8d7da; color:#721c24;",
               "padding:10px; border-radius:4px; margin-bottom:12px;"
             ),
             stale_message
           )
         },
         selectInput(inputId = "Liga",
                     choices = c("Bundesliga", "2. Bundesliga", "Dritte Liga"),
                     label = "Welche Liga soll dargestellt werden?",
                     selected = "Bundesliga"),
         plotOutput(outputId = "Plot"),
         tableOutput(outputId = "Oben"),
         tableOutput(outputId = "Unten"),
         helpText("Alle Prognosen als Wahrscheinlichkeiten in Prozent angegeben. Nähere Infos unter ",
                  a("30punkte.wordpress.com", href = "http://30punkte.wordpress.com", target = "blank_"),
                  paste("Letztes Update: ",
                        format(updatetime, "%d.%m.%Y %H:%M"),
                        " ",
                        # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
                        if (updatetime$isdst > 0) "MESZ" else "MEZ",
                        sep = "")
         )
       )
     )
   }
))

# Define server logic required to draw a histogram
server <- shinyServer(function(input, output) {
    
    output$Oben <- renderTable({
    req(data_loaded)
    if (input$Liga == "Bundesliga") {
      apply (groupResultsDF(Ergebnis[rowSums(Ergebnis[,1:6])>=0.01,],
                              labels = c ("Meister", "Champions League",
                                          "Europa League", "Conference League Quali"),
                              groups = cbind (c (1,1), c (2,4), c (5,5),
                                              c (6,6))),
             c (1,2), prozent)
    } else if (input$Liga == "2. Bundesliga") {
      apply (groupResultsDF (Ergebnis2[rowSums(Ergebnis2[,1:3])>=0.01,],
                               labels = c ("Aufstieg", "Relegation Bundesliga"),
                               groups = cbind (c(1,2), c(3,3))),
             c (1,2), prozent)
    } else {
      apply (groupResultsDF (Ergebnis3_Aufstieg[rowSums(Ergebnis3_Aufstieg[,1:4])>=0.01,],
                               labels = c("Aufstieg", "Relegation", "DFB-Pokal"),
                               groups = cbind (c(1,2), c(3,3), c(4,4))),
               c (1,2), prozent)
    }
  }, digits = 0, rownames = TRUE)

  output$Unten <- renderTable({
    req(data_loaded)
    if (input$Liga == "Bundesliga") {
      apply (groupResultsDF(Ergebnis[rowSums(Ergebnis[,16:18])>=0.01,],
                            labels = c ("Relegation", "Abstieg"),
                            groups = cbind (c (16, 16), c(17, 18))),
             c (1,2), prozent)
    } else if (input$Liga == "2. Bundesliga") {
      apply (groupResultsDF (Ergebnis2[rowSums(Ergebnis2[,16:18])>=0.01,],
                             labels = c ("Relegation 3. Liga", "Abstieg"),
                             groups = cbind (c(16,16), c(17,18))),
             c (1,2), prozent)
    } else {
      apply (groupResultsDF (Ergebnis3[rowSums(Ergebnis3[,17:20])>=0.01,],
                             labels = c("Abstieg"),
                             groups = cbind (c(17,20))),
             c (1,2), prozent)
    }
  }, digits = 0, rownames = TRUE)

  output$Plot <- renderPlot({
    req(data_loaded)
    if (input$Liga == "Bundesliga") {
      display_result (Ergebnis, Titel = "Saisonprognose Bundesliga")
    } else if (input$Liga == "2. Bundesliga") {
      display_result (Ergebnis2, Titel = "Saisonprognose 2. Bundesliga")
    } else {
      display_result (Ergebnis3, Titel = "Saisonprognose 3. Liga", Teams = 20)
    }
  })
  
})

# Run the application 
shinyApp(ui = ui, server = server)

