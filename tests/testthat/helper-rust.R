# Helfer fuer Tests, die den echten Rust-Server brauchen.
#
# Zwei Wege:
# - skip_if_no_rust(env): der Test nutzt einen Server, der schon laeuft
#   (RUST_API_URL, Default localhost:8080), und wird sonst uebersprungen.
# - start_rust_server()/stop_rust_server(): der Test startet sein eigenes
#   Binary auf einem freien Port; rust_binary() skippt, wenn keins da ist.

# Ueberspringt den Test, wenn kein Rust-Server erreichbar ist, und gibt `env`
# zurueck. `env` ist eine per source_module() geladene Umgebung, die
# rust_integration.R enthaelt. Die Pruefreihenfolge ist fest: erst
# RUST_API_URL, dann die Verbindung. Weil R Argumente erst bei Gebrauch
# auswertet, laeuft ein direkt uebergebenes source_module(...) erst nach der
# ersten Pruefung:
#   env <- skip_if_no_rust(source_module(..., "rust_integration"))
skip_if_no_rust <- function(env) {
  skip_if_not(nzchar(Sys.getenv("RUST_API_URL", "http://localhost:8080")),
              "RUST_API_URL ist leer gesetzt")
  skip_if_not(env$connect_rust_simulator(), "Rust-Server nicht erreichbar")
  invisible(env)
}

# Sucht das Rust-Binary an BEIDEN Orten, an denen es real liegt (Issue #146,
# Teil 2).
#
# Bis hierher kannte die Funktion nur den Entwicklerpfad. In der CI laeuft die
# R-Suite aber IM PRODUKTIONSIMAGE (.github/workflows/ci.yml, Job
# "image-build-and-test"), und dort installiert das Dockerfile:116 das Binary
# nach /usr/local/bin/. Das target/release/-Verzeichnis existiert in diesem
# Image gar nicht -- der Rust-Build passiert in einer verworfenen Build-Stage.
#
# Folge: Die Datei, die dies nutzt, hat in der CI noch nie etwas geprueft. Sie
# uebersprang sich still, und zwar mit einer Begruendung ("run `cargo build
# --release`"), die im Image niemand befolgen kann.
rust_binary <- function() {
  kandidaten <- c(
    file.path("..", "..", "league-simulator-rust", "target", "release", "league-simulator-rust"),
    "/usr/local/bin/league-simulator-rust"
  )
  for (bin in kandidaten) {
    if (file.exists(bin)) {
      return(normalizePath(bin))
    }
  }
  skip(sprintf("Rust binary not found in any of: %s; run `cargo build --release` in league-simulator-rust/",
               paste(kandidaten, collapse = ", ")))
}

# Startet das Binary im Hintergrund auf `port` und wartet bis zu 10 s auf
# /health. Jede Testdatei, die das nutzt, nimmt einen eigenen Port, damit
# parallele Laeufe sich nicht stoeren. Der Aufrufer prueft handle$ok selbst
# und skippt dann -- erst nachdem er stop_rust_server() per on.exit()
# registriert hat, sonst bliebe der Prozess stehen.
start_rust_server <- function(port = 18080L) {
  bin <- rust_binary()
  log <- tempfile(fileext = ".log")
  # Pass PORT via the parent environment (sys::exec_background inherits env from
  # the caller and has no env= parameter as of sys 3.4.3).
  old_port <- Sys.getenv("PORT", unset = NA)
  Sys.setenv(PORT = as.character(port))
  pid <- sys::exec_background(bin, args = "--api", std_out = log, std_err = log)
  if (is.na(old_port)) Sys.unsetenv("PORT") else Sys.setenv(PORT = old_port)
  # Save the prior RUST_API_URL so stop_rust_server can restore it.
  prior_rust_api_url <- Sys.getenv("RUST_API_URL", unset = NA)
  Sys.setenv(RUST_API_URL = sprintf("http://localhost:%d", port))
  # Wait up to 10 s for the server to become healthy.
  ok <- FALSE
  for (i in 1:50) {
    Sys.sleep(0.2)
    res <- tryCatch(httr::GET(paste0(Sys.getenv("RUST_API_URL"), "/health"),
                              httr::timeout(0.5)),
                    error = function(e) NULL)
    if (!is.null(res) && httr::status_code(res) == 200) { ok <- TRUE; break }
  }
  list(pid = pid, log = log, ok = ok, port = port,
       prior_rust_api_url = prior_rust_api_url)
}

stop_rust_server <- function(handle) {
  if (!is.null(handle$pid)) {
    try(tools::pskill(handle$pid), silent = TRUE)
  }
  if (!is.null(handle$prior_rust_api_url)) {
    if (is.na(handle$prior_rust_api_url)) {
      Sys.unsetenv("RUST_API_URL")
    } else {
      Sys.setenv(RUST_API_URL = handle$prior_rust_api_url)
    }
  }
}
