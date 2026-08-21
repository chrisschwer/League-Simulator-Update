# Rendering primitives shared by the Shiny app (ShinyApp/app.R) and the static
# site generator (RCode/generate_static_site.R).
#
# Requires: ggplot2, reshape2 (melt).

suppressPackageStartupMessages({
  library(ggplot2)
  library(reshape2)
})

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
