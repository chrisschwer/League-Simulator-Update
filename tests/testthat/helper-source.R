# Laedt eine oder mehrere RCode-Einheiten in eine Umgebung und gibt sie zurueck.
# source() statt sys.source(), weil generate_static_site.R sein eigenes
# Verzeichnis ueber das ofile-Muster findet.
source_module <- function(..., envir = new.env()) {
  for (einheit in c(...)) {
    source(test_path("..", "..", "RCode", paste0(einheit, ".R")), local = envir)
  }
  envir
}

# Holt eine Funktion aus einer per source_module() geladenen Umgebung und
# meldet klar, wenn sie fehlt -- statt des kryptischen "attempt to apply
# non-function" bei env$name(). Welche Einheit sie liefern soll, steht im
# source_module()-Aufruf des Tests.
fn <- function(env, name) {
  if (!exists(name, envir = env, inherits = FALSE)) {
    stop(sprintf(
      "Funktion '%s' nicht gefunden -- erwartet in einer der per source_module() geladenen RCode-Einheiten",
      name
    ), call. = FALSE)
  }
  get(name, envir = env, inherits = FALSE)
}
