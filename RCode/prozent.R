#' prozent
#' 
#' formats fractions nicely, so that they round to the nearest full percentage,
#' get displayed in percent and number on the margin get marked as such.
#' 
#' @param x number to be formatted nicely
#' @export

prozent <- function (x) {
  if (!is.numeric(x)) {return (x)}
  if ((x >= .01) && (x <= .99)) {
    return (round (100 * x, digits = 0))
  } else if (x == 1) {
    return (100)
  } else if (x == 0) {
    return (0)
  } else if (x > 0.99) {
    return (">99")
  } else if (x < 0.01) {
    return ("<1")
  }
}