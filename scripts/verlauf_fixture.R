#!/usr/bin/env Rscript

# Synthetische league_data fuer die Sichtpruefung der ELO-Verlaufsseiten
# (Issue #184). Drei Staende, reproduzierbar (fester Seed):
#   bundesliga         18 Vereine nach 3 Spielen (Saisonauftakt)
#   zweite_bundesliga  18 Vereine nach 20 Spielen ueber die Winterpause
#   dritte_liga        20 Vereine nach 15 Spielen, mit Nachholspiel und einem
#                      am gruenen Tisch gewerteten Spiel
# Die ELO-Spalten kommen aus dem echten /league-details: Der Rust-Server muss
# laufen (RUST_API_URL, Default http://localhost:8080).
#
# Usage: Rscript scripts/verlauf_fixture.R <ziel.rds>
# Danach: Rscript scripts/preview_site.R <Ergebnis.Rds> <out> <ziel.rds>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Aufruf: Rscript scripts/verlauf_fixture.R <ziel.rds>")
}
ziel <- args[[1]]

# Pfad wie in preview_site.R: R kodiert Leerzeichen im --file=-Argument als "~+~".
file_arg <- sub("^--file=", "",
                grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
file_arg <- gsub("~+~", " ", file_arg, fixed = TRUE)
script_dir <- dirname(file_arg)
rcode_dir <- if (length(script_dir) == 1 && nzchar(script_dir)) {
  file.path(dirname(script_dir), "RCode")
} else {
  file.path("RCode")
}
source(file.path(rcode_dir, "league_details.R"))

basis <- Sys.getenv("RUST_API_URL", "http://localhost:8080")
erreichbar <- tryCatch(
  httr::status_code(httr::GET(paste0(basis, "/health"), httr::timeout(5))) == 200,
  error = function(e) FALSE
)
if (!erreichbar) {
  stop(sprintf("verlauf_fixture: Rust-Server unter %s nicht erreichbar -- erst starten", basis))
}

set.seed(184)

# Doppelrunde nach der Kreismethode (gerade Vereinszahl).
spielplan <- function(ids) {
  n <- length(ids)
  rot <- ids
  hin <- vector("list", n - 1)
  for (r in seq_len(n - 1)) {
    paare <- cbind(rot[seq_len(n / 2)], rev(rot)[seq_len(n / 2)])
    if (r %% 2 == 0) paare <- paare[, 2:1, drop = FALSE]
    hin[[r]] <- paare
    rot <- c(rot[1], rot[n], rot[2:(n - 1)])
  }
  c(hin, lapply(hin, function(p) p[, 2:1, drop = FALSE]))
}

# Rundentermine (Sekunden seit Epoche): samstags 13:30 UTC ab `start`,
# woechentlich; ab Runde `pause_ab` weiter ab `nach_pause`.
termine <- function(n_runden, start, pause_ab = Inf, nach_pause = NULL) {
  sek <- function(tag) as.numeric(as.POSIXct(paste(tag, "13:30:00"), tz = "UTC"))
  vapply(seq_len(n_runden), function(r) {
    if (r >= pause_ab) {
      sek(nach_pause) + (r - pause_ab) * 7 * 86400
    } else {
      sek(start) + (r - 1) * 7 * 86400
    }
  }, numeric(1))
}

iso <- function(sekunden) {
  format(as.POSIXct(sekunden, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%S+00:00", tz = "UTC")
}

liga <- function(praefix, n, gespielt, start, id_basis, pause_ab = Inf,
                 nach_pause = NULL, nachhol = FALSE, gewertet = FALSE) {
  ids <- id_basis + seq_len(n)
  kuerzel <- sprintf("%s%02d", praefix, seq_len(n))
  teams <- data.frame(TeamID = ids, ShortText = kuerzel, Promotion = 0,
                      InitialELO = round(stats::rnorm(n, 1450, 90), 1),
                      stringsAsFactors = FALSE)
  runden <- spielplan(ids)
  zeit <- termine(length(runden), start, pause_ab, nach_pause)

  zeilen <- list()
  for (r in seq_along(runden)) {
    for (k in seq_len(nrow(runden[[r]]))) {
      gesp <- r <= gespielt
      zeilen[[length(zeilen) + 1L]] <- data.frame(
        id = length(zeilen) + 1L, sek = zeit[r] + (k %% 3) * 7200, runde = r,
        status = if (gesp) "FT" else "NS",
        home = runden[[r]][k, 1], away = runden[[r]][k, 2],
        gh = if (gesp) stats::rpois(1, 1.6) else NA_real_,
        ga = if (gesp) stats::rpois(1, 1.2) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  df <- do.call(rbind, zeilen)

  if (nachhol) {
    # Ein Spiel aus Runde gespielt-3, nachgeholt am Dienstag nach der letzten
    # gespielten Runde -- also nach dem Beginn spaeterer Spieltage.
    i <- which(df$runde == gespielt - 3)[1]
    df$sek[i] <- zeit[gespielt] + 3 * 86400
  }
  if (gewertet) {
    i <- which(df$runde == 2)[1]
    df$status[i] <- "AWD"
    df$gh[i] <- 3
    df$ga[i] <- 0
  }

  name <- function(id) paste("Verein", kuerzel[match(id, ids)])
  fixtures <- data.frame(row.names = seq_len(nrow(df)))
  fixtures$fixture <- data.frame(id = df$id, date = iso(df$sek))
  fixtures$fixture$status <- data.frame(short = df$status)
  fixtures$league <- data.frame(round = paste("Regular Season -", df$runde))
  fixtures$teams <- data.frame(row.names = seq_len(nrow(df)))
  fixtures$teams$home <- data.frame(id = df$home, name = name(df$home))
  fixtures$teams$away <- data.frame(id = df$away, name = name(df$away))
  fixtures$goals <- data.frame(home = df$gh, away = df$ga)

  entry <- build_league_page_data(fixtures, teams)
  if (is.null(entry)) {
    stop("verlauf_fixture: build_league_page_data lieferte NULL fuer ", praefix)
  }
  entry
}

league_data <- list(
  bundesliga = liga("BL", 18, gespielt = 3, start = "2026-08-22", id_basis = 91000),
  zweite_bundesliga = liga("ZB", 18, gespielt = 20, start = "2026-08-01", id_basis = 92000,
                           pause_ab = 18, nach_pause = "2027-01-23"),
  dritte_liga = liga("DL", 20, gespielt = 15, start = "2026-07-25", id_basis = 93000,
                     nachhol = TRUE, gewertet = TRUE)
)
saveRDS(league_data, ziel)
cat(ziel, "\n", sep = "")
