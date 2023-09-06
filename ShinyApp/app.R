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


load ("data/Ergebnis.Rds")
updatetime <- as.POSIXlt(file.mtime("data/Ergebnis.Rds"))

display_result <- function (result, colour = "grey", 
                            low = "white", high = "steelblue",
                            Titel = "Endplatzierung",
                            labeling = FALSE, Teams = 18)
  
  # Displays results from SimWrapper in a heatmap
  # result : results to display
  # colour : background colour for tiles
  # low : colour for lower end of scale
  # high : colour for higher end of scale
  # Titel : text of the title line of the chart
  # labeling : boolean, if true the tiles of the heatmap
  #            are labeled with the values in percent
  
{
  
  if (labeling) 
  {
    result <- round(result*100,0)
  }
  
  result.m <- melt (result)
  plot <- ggplot (result.m) + 
    aes (Var1, Var2) + 
    geom_tile(aes (fill=value), 
              colour = colour) + 
    scale_fill_gradient (low = low, high = high,
                         name = "p") +
    labs (x = "Verein", y = "Platz") +
    ggtitle (Titel) +
    theme_grey()
  plot <- plot + 
    theme (axis.text.x = element_text (size = rel (0.8), angle = 330,
                                       hjust = 0, colour = "grey50"))
  plot <- plot +
    theme (axis.ticks = element_line (linetype = 0)) +
    scale_y_reverse(breaks = 1:Teams)
  
  if (labeling) 
  {
    plot <- plot + geom_text (aes (label = value))
  }
  
  
  return (plot)  
}

prozent <- function (x) {
  if (!is.numeric(x)) {return (x)}
  if ((x >= .01) && (x <= .99)) {
    return (round (100 * x, digits = 0))
  } else if (x == 1) {
    return (intToUtf8(0x2713)) # Tick mark instead of 100 percent
  } else if (x == 0) {
    return (0)
  } else if (x > 0.99) {
    return (">99")
  } else if (x < 0.01) {
    return ("<1")
  }
}

groupResultsDF <- function (results,
                            labels = c("Meister", "Champions League", "Europa League",
                                       "Conference League Quali", "Mittelfeld", "Relegation", "Abstieg"),
                            groups = cbind(c(1,1), c(2,4), c(5,5),
                                           c(6,6), c(7,15), c(16,16), c(17,18))) {
  
  # groups results into a data frame of labeled groups
  # results : data frame with n probabilities for n teams
  # labels : vector of strings, labels for the groups
  # groups : 2xn matrix of integers, lower and upper bounds for groups
  
  outputDF <- data.frame (matrix(ncol=length(labels), nrow=dim(results)[1]))
  colnames (outputDF) <- labels
  rownames (outputDF) <- rownames (results)
  
  for (i in 1:length(labels)) {
    lower <- groups [1,i]
    upper <- groups [2,i]
    if (lower == upper) {
      newcol <- results[,lower]
    } else {
      range <- c(lower:upper)
      newcol <- rowSums(results[, range])
    }
    outputDF[,i] <- newcol
    
  }
  
  return (outputDF)
}

# Define UI for application that draws a histogram
ui <- shinyUI(fluidPage(
   
   # Application title
   titlePanel("Fußball-Prognosen von 30Punkte"),
   
   # Sidebar with a slider input for number of bins 
   verticalLayout(
     mainPanel(
       selectInput (inputId = "Liga", choices = c ("Bundesliga", "2. Bundesliga", "Dritte Liga"),
                    label = "Welche Liga soll dargestellt werden?", selected = "Bundesliga"),
       plotOutput(outputId = "Plot"),
       tableOutput(outputId = "Oben"),
       tableOutput(outputId = "Unten"),
       helpText("Alle Prognosen als Wahrscheinlichkeiten in Prozent angegeben. Nähere Infos unter ",
                a ("30punkte.wordpress.com", href = "http://30punkte.wordpress.com", target = "blank_"),
                paste("Letztes Update: ", 
                      format(updatetime, "%d.%m.%Y %H:%M %Z", tz="Europe/Berlin"),
                      sep="")
       )
       
     )
   )
))

# Define server logic required to draw a histogram
server <- shinyServer(function(input, output) {
    
    output$Oben <- renderTable({
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
      apply (data.frame(Abstieg = rowSums(Ergebnis3[rowSums(Ergebnis3[,17:20])>=0.01,17:20])),
             c (1,2), prozent)
    }
  }, digits = 0, rownames = TRUE)

  output$Plot <- renderPlot({
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

