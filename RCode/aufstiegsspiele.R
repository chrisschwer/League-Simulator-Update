# Die zwei Aufstiegsspiele Nord gegen Bayern: Stochastik auf gegebenen
# Tor-Raten.
#
# ARCHITEKTURGRENZE (ADR 0002, ADR 0004): Die Grenze liegt bei lambda.
# Alles von ELO zu lambda ist Modell und lebt AUSSCHLIESSLICH im
# Rust-Server; diese Datei kennt weder eine Tormodell-Konstante noch die
# Formel ELO -> lambda. Sie bekommt fertige Tor-Raten und macht daraus
# Kombinatorik: Poisson je Team, Faltung zur Tordifferenz eines Spiels,
# Faltung ueber zwei Spiele, Verlaengerung, Muenzwurf.
#
# Warum diese Trennung: Der Nachtrag zu ADR 0002 haelt fest, dass eine
# zweite Kopie des Heimvorteils in R jahrelang unbemerkt jeden Rust-Default
# ueberschrieb. Eine ELO->lambda-Formel hier waere genau so eine zweite
# Quelle. Der Client, der die Raten holt, steht in RCode/rust_integration.R.
#
# MODUS (docs/abstieg_aufstieg_RL_2026_2027.md, Abschnitt 1; Par. 55b Nr. 2
# DFB-SpO): Hin- und Rueckspiel mit getauschtem Heimrecht, gewertet wird die
# Gesamttordifferenz. Bei Gleichstand 30 Minuten Verlaengerung OHNE
# Heimvorteil (das Heimrecht wird ausgelost, es ist nicht ermittelbar, wer
# sie zu Hause bestreitet), danach Elfmeterschiessen 50:50.
#
# Zwei bewusste Auslassungen, beide dokumentiert:
#   - AUSWAERTSTORREGEL: nicht modelliert, weil in der DFB-Aufstiegs-
#     relegation abgeschafft.
#   - Verlaengerungen sind empirisch torarmer als ein Drittel eines Spiels.
#     Hier gilt reine Spielzeit-Proportionalitaet (lambda / 3), bewusst
#     keine Verhaltensannahme.

#' Verteilung der Tordifferenz eines Spiels.
#'
#' Beide Teams treffen unabhaengig Poisson-verteilt; die Differenz ist die
#' Faltung. Abgeschnitten wird bei max_tore je Team, OHNE Renormierung: Der
#' fehlende Rest ist genau der Poisson-Schwanz beider Seiten und bei
#' realistischen Raten (< 2) kleiner als 1e-9. Renormieren wuerde diesen
#' Rest still auf die dargestellten Ergebnisse verteilen und damit einen
#' echten Modellierungsfehler (zu kleines max_tore) unsichtbar machen.
#'
#' @param lambda_a Tor-Rate von A, nicht-negativ.
#' @param lambda_b Tor-Rate von B, nicht-negativ.
#' @param max_tore Groesste beruecksichtigte Torzahl je Team.
#' @return Benannter numerischer Vektor der Laenge 2 * max_tore + 1 mit
#'   names = as.character(-max_tore:max_tore); v[["d"]] = P(Tore A - Tore B = d).
tordifferenz_verteilung <- function(lambda_a, lambda_b, max_tore = 15) {
  pruefe_rate(lambda_a, "lambda_a", "tordifferenz_verteilung", laenge = 1L)
  pruefe_rate(lambda_b, "lambda_b", "tordifferenz_verteilung", laenge = 1L)
  max_tore <- pruefe_max_tore(max_tore, "tordifferenz_verteilung")

  tore <- 0:max_tore
  p_a <- stats::dpois(tore, lambda_a)
  p_b <- stats::dpois(tore, lambda_b)

  # p_a[i + 1] * p_b[j + 1] = P(A = i, B = j) -- genau die score_matrix, die
  # /match-preview liefert. Die Differenzverteilung ist die Summe ueber die
  # Antidiagonalen i - j = d. Statt die ganze Matrix zu bilden und zu
  # maskieren, wird je d direkt das passende Indexpaar summiert.
  d <- -max_tore:max_tore
  v <- vapply(d, function(dd) {
    # i laeuft ueber die Tore von A, j = i - dd ueber die von B; beide
    # muessen in 0..max_tore liegen.
    i <- max(0L, dd):min(max_tore, max_tore + dd)
    sum(p_a[i + 1L] * p_b[i - dd + 1L])
  }, numeric(1))
  names(v) <- as.character(d)
  v
}

#' Tor-Rate der Verlaengerung aus der 90-Minuten-Rate.
#'
#' Reine Spielzeit-Proportionalitaet: 30 von 90 Minuten, also ein Drittel.
#' Vektorisiert; Namen bleiben erhalten.
#'
#' @param lambda_90 Numerischer (ggf. benannter) Vektor der 90-Minuten-Raten.
#' @return Derselbe Vektor durch 3.
verlaengerung_lambda <- function(lambda_90) {
  pruefe_rate(lambda_90, "lambda_90", "verlaengerung_lambda", laenge = NULL)
  lambda_90 / 3
}

#' Wahrscheinlichkeit, dass A sich ueber zwei Aufstiegsspiele durchsetzt.
#'
#' @param hin c(a, b): Tor-Raten von A und B im Hinspiel (A hat Heimrecht).
#' @param rueck c(a, b): dito im Rueckspiel (B hat Heimrecht).
#' @param neutral c(a, b): dito ohne Heimvorteil. Daraus folgt die
#'   Verlaengerungs-Rate neutral / 3.
#' @param max_tore Groesste beruecksichtigte Torzahl je Team und Spiel.
#' @return Eine Zahl in [0, 1]: P(A setzt sich durch).
zweikampf_quote <- function(hin, rueck, neutral, max_tore = 15) {
  pruefe_rate(hin, "hin", "zweikampf_quote")
  pruefe_rate(rueck, "rueck", "zweikampf_quote")
  pruefe_rate(neutral, "neutral", "zweikampf_quote")
  max_tore <- pruefe_max_tore(max_tore, "zweikampf_quote")

  # Die Gesamtdifferenz ueber beide Spiele ist die Faltung der beiden
  # Einzelspiel-Differenzen. Gezaehlt wird allein sie -- keine
  # Auswaertstorregel.
  d1 <- tordifferenz_verteilung(hin[[1]], hin[[2]], max_tore = max_tore)
  d2 <- tordifferenz_verteilung(rueck[[1]], rueck[[2]], max_tore = max_tore)

  gesamt <- faltung(d1, d2, max_tore)

  # -max_tore:-1 waere hier ein AUSSCHLUSS-Index, wenn man ihn auf den
  # Vektor anwendet -- deshalb konsequent ueber die Namen zugreifen.
  d <- -(2 * max_tore):(2 * max_tore)
  p_a_vorn <- sum(gesamt[d > 0])
  p_gleich <- sum(gesamt[d == 0])

  # Gleichstand -> Verlaengerung mit den NEUTRALEN Raten (das Heimrecht der
  # Verlaengerung ist ausgelost, nicht ermittelbar), 30 Minuten.
  ev <- verlaengerung_lambda(c(neutral[[1]], neutral[[2]]))
  d_ev <- tordifferenz_verteilung(ev[[1]], ev[[2]], max_tore = max_tore)
  e <- -max_tore:max_tore
  p_a_ev <- sum(d_ev[e > 0])
  p_gleich_ev <- sum(d_ev[e == 0])

  # Danach immer noch gleich -> Elfmeterschiessen, 50:50.
  p_a_vorn + p_gleich * (p_a_ev + 0.5 * p_gleich_ev)
}

#' Matrix der Zweikampfquoten aus dem paarungen-data.frame.
#'
#' @param paarungen data.frame mit den Spalten a, b (Teamnamen) und hin_a,
#'   hin_b, rueck_a, rueck_b, neutral_a, neutral_b (Tor-Raten), eine Zeile
#'   je Paar -- so, wie zweikampf_paarungen_rust() es liefert.
#' @param max_tore Wird an zweikampf_quote() durchgereicht.
#' @return Matrix mit dimnames list(unique(a), unique(b)) und
#'   M[a, b] = P(a setzt sich gegen b durch).
p_sieg_matrix <- function(paarungen, max_tore = 15) {
  if (!is.data.frame(paarungen)) {
    stop(sprintf(
      "p_sieg_matrix: paarungen muss ein data.frame sein, ist aber '%s'.",
      paste(class(paarungen), collapse = "/")
    ), call. = FALSE)
  }

  noetig <- c("a", "b", "hin_a", "hin_b", "rueck_a", "rueck_b",
              "neutral_a", "neutral_b")
  fehlend <- setdiff(noetig, names(paarungen))
  if (length(fehlend)) {
    stop(sprintf(
      paste0(
        "p_sieg_matrix: in paarungen fehlen die Spalten: %s. Vorhanden ",
        "sind: %s."
      ),
      paste(fehlend, collapse = ", "),
      if (length(names(paarungen))) paste(names(paarungen), collapse = ", ")
      else "keine"
    ), call. = FALSE)
  }

  if (nrow(paarungen) == 0L) {
    stop(
      paste0(
        "p_sieg_matrix: paarungen ist leer. Ohne eine einzige Paarung gibt ",
        "es keine Zweikampfquote -- eine leere Matrix waere eine stille ",
        "Antwort auf eine falsche Frage."
      ),
      call. = FALSE
    )
  }

  a_namen <- unique(as.character(paarungen$a))
  b_namen <- unique(as.character(paarungen$b))

  M <- matrix(NA_real_, nrow = length(a_namen), ncol = length(b_namen),
              dimnames = list(a_namen, b_namen))

  for (i in seq_len(nrow(paarungen))) {
    z <- paarungen[i, ]
    M[as.character(z$a), as.character(z$b)] <- zweikampf_quote(
      c(z$hin_a, z$hin_b),
      c(z$rueck_a, z$rueck_b),
      c(z$neutral_a, z$neutral_b),
      max_tore = max_tore
    )
  }

  # Eine fehlende Paarung darf nicht als NA stehen bleiben: Sie liefe in die
  # Doppelsumme und ergaebe dort ein NA, das erst in der fertigen Prognose
  # auffiele -- oder gar nicht.
  if (anyNA(M)) {
    luecken <- which(is.na(M), arr.ind = TRUE)
    stop(sprintf(
      paste0(
        "p_sieg_matrix: fuer diese Paarung(en) liefert paarungen keine ",
        "Raten: %s."
      ),
      paste(sprintf("%s gegen %s",
                    a_namen[luecken[, 1]], b_namen[luecken[, 2]]),
            collapse = ", ")
    ), call. = FALSE)
  }

  M
}

# --- Hilfsfunktionen -------------------------------------------------------

#' Faltung zweier Differenzverteilungen ueber -max_tore:max_tore.
#'
#' P(D1 + D2 = d) = SUMME_i P(D1 = i) * P(D2 = d - i).
faltung <- function(d1, d2, max_tore) {
  x <- unname(d1)
  y <- unname(d2)
  n <- 2L * max_tore + 1L

  # Positionen 1..n stehen fuer die Differenzen -max_tore..max_tore. Die
  # Summe zweier Differenzen an den Positionen p und q liegt an Position
  # p + q - 1 der Ergebnisreihe (Laenge 2n - 1).
  d <- -(2L * max_tore):(2L * max_tore)
  out <- vapply(seq_len(2L * n - 1L), function(k) {
    p <- max(1L, k - n + 1L):min(n, k)
    sum(x[p] * y[k - p + 1L])
  }, numeric(1))
  names(out) <- as.character(d)
  out
}

#' Pruefung einer Tor-Raten-Angabe.
#'
#' Fehlerstil wie RCode/staffel_zuordnung.R: kein stiller Ersatzwert, der
#' beanstandete Wert steht in der Meldung.
#'
#' @param laenge Erwartete Laenge; NULL laesst jede Laenge >= 1 zu.
pruefe_rate <- function(x, name, aufrufer, laenge = 2L) {
  if (is.null(x)) {
    stop(sprintf(
      "%s: %s fehlt (NULL). Ohne Tor-Raten gibt es keine Quote.",
      aufrufer, name
    ), call. = FALSE)
  }
  if (!is.numeric(x)) {
    stop(sprintf(
      "%s: %s muss numerisch sein, ist aber '%s'.",
      aufrufer, name, paste(class(x), collapse = "/")
    ), call. = FALSE)
  }
  if (is.null(laenge)) {
    if (length(x) < 1L) {
      stop(sprintf("%s: %s ist leer.", aufrufer, name), call. = FALSE)
    }
  } else if (length(x) != laenge) {
    stop(sprintf(
      "%s: %s muss Laenge %d haben (c(a, b)), hat aber Laenge %d.",
      aufrufer, name, laenge, length(x)
    ), call. = FALSE)
  }
  if (anyNA(x)) {
    stop(sprintf(
      paste0(
        "%s: %s enthaelt NA. Eine fehlende Tor-Rate wird nicht stillschweigend ",
        "durch einen Ersatzwert gedeckt."
      ),
      aufrufer, name
    ), call. = FALSE)
  }
  if (any(x < 0)) {
    stop(sprintf(
      "%s: %s enthaelt negative Tor-Raten: %s. Eine Poisson-Rate ist nie negativ.",
      aufrufer, name, paste(format(x[x < 0]), collapse = ", ")
    ), call. = FALSE)
  }
  invisible(x)
}

#' Pruefung von max_tore.
pruefe_max_tore <- function(max_tore, aufrufer) {
  if (!is.numeric(max_tore) || length(max_tore) != 1L || is.na(max_tore) ||
        max_tore < 1 || max_tore != as.integer(max_tore)) {
    stop(sprintf(
      paste0(
        "%s: max_tore muss eine ganze Zahl >= 1 sein, ist aber: %s."
      ),
      aufrufer, paste(format(max_tore), collapse = ", ")
    ), call. = FALSE)
  }
  as.integer(max_tore)
}
