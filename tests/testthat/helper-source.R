# Laedt eine oder mehrere RCode-Einheiten in eine Umgebung und gibt sie zurueck.
# source() statt sys.source(), weil generate_static_site.R sein eigenes
# Verzeichnis ueber das ofile-Muster findet.
source_module <- function(..., envir = new.env()) {
  for (einheit in c(...)) {
    source(test_path("..", "..", "RCode", paste0(einheit, ".R")), local = envir)
  }
  envir
}
