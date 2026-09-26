# Byteidentische Helfer fuer generierte HTML-Seiten, bisher kopiert in
# test-generate_static_site.R, test-generate_static_site-tooltip.R,
# test-render_sections-ausblick.R, test-render_sections-rueckblick.R und
# test-render_sections-tabelle.R (#211, Stufe 2, T7).

read_html <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

# Wie read_html(), aber mit encoding = "UTF-8": markiert die Zeilen als UTF-8,
# statt die Kodierung der Sitzung anzunehmen. In einer UTF-8-Sitzung gleich,
# sonst nicht -- deshalb nicht mit read_html() zusammengelegt. Bisher kopiert
# in test-scripts-preview_site.R und test-update_all_leagues_loop-verdrahtung.R
# (#211, Stufe 3.6).
html_lesen <- function(pfad) {
  paste(readLines(pfad, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# Build a data environment with the same object names and shapes as the
# production ShinyApp/data/Ergebnis.Rds.
make_data_env <- function() {
  env <- new.env()
  mk <- function(n, teams) {
    m <- matrix(1 / n, nrow = teams, ncol = n,
                dimnames = list(paste0("T", seq_len(teams)), as.character(seq_len(n))))
    as.table(m)
  }
  env$Ergebnis <- mk(18, 18)
  env$Ergebnis2 <- mk(18, 18)
  env$Ergebnis3 <- mk(20, 20)
  env$Ergebnis3_Aufstieg <- mk(20, 20)
  env
}
