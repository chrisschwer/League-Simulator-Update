# Dynamische Aufstiegssperre der Regionalliga-Reserven (#322).
#
# Eine Reserve darf nicht in die 3. Liga aufsteigen, wenn ihre Erstmannschaft
# nach der Saison dort spielt (Par. 55b Nr. 3.1 DFB-SpO, ADR 0008). Spielt die
# Erstmannschaft heute in der 2. Bundesliga, entscheidet erst der Abstieg
# (direkt oder ueber die Relegation), ob die Reserve gesperrt ist. Diese Datei
# rechnet das exakt:
#
#   P(Aufstieg) = SUMME_S  P(S) * M_S
#
# S ist die MENGE der gesperrten Reserven, P(S) ihre gemeinsame Verteilung,
# M_S das Ergebnis der Staffel unter der Maske "S ist gesperrt". Exakt, weil
# 2. Bundesliga, 3. Liga und die Staffeln kein Spiel teilen (ADR 0009): Die
# Staffel wird einmal simuliert, die Engine wertet dieselbe Abschlusstabelle
# unter allen 2^k Masken aus, und R mischt mit den Gewichten.
#
# GEMEINSAM statt je Team: Hoechstens zwei Teams steigen direkt ab, die
# Reserven zweier Zweitligisten sind also negativ gekoppelt -- und Nord und
# Bayern teilen sich dieselbe 2. Bundesliga. Die Gewichte kommen deshalb aus
# den gemeinsamen Klassenvektoren der Engine (tracked_class_patterns), nicht
# aus Randverteilungen.
#
# Die Relegation des Sechzehnten loest R auf, nicht die Engine: Sie haengt am
# Dritten der 3. Liga, den die 2.-Bundesliga-Simulation nicht kennt.

#' Die Reserven mit Erstmannschaft in der 2. Bundesliga.
#'
#' @param teams TeamList mit TeamID, ShortText, League, Erstvertretung_TeamID.
#' @param zweitliga_id Liga-ID der 2. Bundesliga ("79").
#' @return data.frame mit reserve (Kurzname), liga (Liga der Reserve) und
#'   erst (Kurzname der Erstmannschaft), eine Zeile je Reserve. Leer, wenn die
#'   Spalten fehlen oder keine Reserve eine Zweitliga-Erstmannschaft hat.
erstvertretungen_zweite_liga <- function(teams, zweitliga_id = "79") {
  leer <- data.frame(reserve = character(0), liga = character(0),
                     erst = character(0), stringsAsFactors = FALSE)
  if (is.null(teams$Erstvertretung_TeamID) || is.null(teams$League)) {
    return(leer)
  }
  id <- trimws(as.character(teams$Erstvertretung_TeamID))
  id[is.na(id)] <- ""
  ziel <- match(id, as.character(teams$TeamID))
  hat <- which(id != "" & !is.na(ziel))
  hat <- hat[as.character(teams$League[ziel[hat]]) == as.character(zweitliga_id)]
  if (length(hat) == 0L) {
    return(leer)
  }
  data.frame(
    reserve = as.character(teams$ShortText[hat]),
    liga = as.character(teams$League[hat]),
    erst = as.character(teams$ShortText[ziel[hat]]),
    stringsAsFactors = FALSE
  )
}

#' Die sperrbaren Reserven einer Staffel, in Spielplan-Reihenfolge.
#'
#' Kuerzel sind nur je Liga eindeutig; deshalb wird auf die Liga der Staffel
#' gefiltert, bevor ein Kurzname gesucht wird.
#'
#' @param zuordnung Ergebnis von erstvertretungen_zweite_liga().
#' @param kurznamen Kurznamen der Teams des Spielplans.
#' @param liga Liga-ID der Staffel.
#' @return data.frame wie `zuordnung`, nur die Reserven dieser Staffel.
sperrbare_reserven <- function(zuordnung, kurznamen, liga) {
  zeilen <- zuordnung[zuordnung$liga == as.character(liga) &
                        zuordnung$reserve %in% kurznamen, , drop = FALSE]
  zeilen[order(match(zeilen$reserve, kurznamen)), , drop = FALSE]
}

#' Alle 2^k Berechtigungsmasken einer Staffel.
#'
#' Maske j (0-basiert) sperrt die Reserven, deren Bit in j gesetzt ist (die
#' erste Reserve ist das niedrigste Bit). Maske 0 ist "niemand gesperrt".
#' Auf der Basis des Aufstiegsverzichts: Wer verzichtet, ist in jeder Maske
#' nicht berechtigt.
#'
#' @param basis Logischer Vektor je Team des Spielplans (berechtigt ohne
#'   dynamische Sperre).
#' @param kurznamen Kurznamen in Spielplan-Reihenfolge.
#' @param reserven Kurznamen der sperrbaren Reserven.
#' @return Liste der 2^k Logikvektoren.
sperr_masken <- function(basis, kurznamen, reserven) {
  k <- length(reserven)
  lapply(seq_len(2L^k) - 1L, function(j) {
    gesperrt <- reserven[bitwAnd(j, 2L^(seq_len(k) - 1L)) > 0L]
    basis & !(kurznamen %in% gesperrt)
  })
}

#' Gemeinsame Verteilung der abgestiegenen Erstmannschaften.
#'
#' Aus den Klassenvektoren der Engine (0 = sonst, 1 = direkter Abstieg,
#' 2 = Relegationsplatz). Wer auf dem Relegationsplatz steht, steigt mit
#' P(Niederlage) ab; die Duelle verschiedener Spiele sind unabhaengig, und es
#' gibt nur einen Relegationsplatz.
#'
#' @param muster list(classes = Matrix Muster x Teams, counts = Haeufigkeit).
#' @param p_niederlage Benannter Vektor: P(verliert die Relegation | steht auf
#'   dem Relegationsplatz) je Team der 2. Bundesliga.
#' @return list(teams, abstieg = logische Matrix Ausgang x Teams, gewicht =
#'   Wahrscheinlichkeit je Ausgang; Summe 1).
sperrverteilung <- function(muster, p_niederlage) {
  klassen <- muster$classes
  teams <- colnames(klassen)
  gesamt <- sum(muster$counts)

  # Zustand in einer eigenen Umgebung, nicht per <<- im umgebenden Frame.
  zustand <- new.env()
  zustand$ausgaenge <- list()
  zustand$gewichte <- numeric(0)
  merke <- function(abgestiegen, w) {
    if (w <= 0) {
      return(invisible(NULL))
    }
    schluessel <- paste(as.integer(abgestiegen), collapse = "")
    if (is.null(zustand$ausgaenge[[schluessel]])) {
      zustand$ausgaenge[[schluessel]] <- abgestiegen
      zustand$gewichte[schluessel] <- 0
    }
    zustand$gewichte[schluessel] <- zustand$gewichte[schluessel] + w
  }

  for (i in seq_len(nrow(klassen))) {
    w <- muster$counts[[i]] / gesamt
    direkt <- klassen[i, ] == 1L
    relegation <- which(klassen[i, ] == 2L)
    if (length(relegation) == 0L) {
      merke(direkt, w)
    } else if (length(relegation) == 1L) {
      p <- p_niederlage[[teams[[relegation]]]]
      if (is.null(p) || is.na(p) || p < 0 || p > 1) {
        stop(sprintf(
          "sperrverteilung: keine gueltige P(Niederlage) fuer %s", teams[[relegation]]
        ), call. = FALSE)
      }
      verliert <- direkt
      verliert[relegation] <- TRUE
      merke(verliert, w * p)
      merke(direkt, w * (1 - p))
    } else {
      stop("sperrverteilung: mehr als ein Relegationsplatz wird nicht unterstuetzt",
           call. = FALSE)
    }
  }

  abstieg <- do.call(rbind, unname(zustand$ausgaenge))
  colnames(abstieg) <- teams
  list(teams = teams, abstieg = abstieg, gewicht = unname(zustand$gewichte))
}

# Maskenindex (0-basiert) je Ausgang fuer die Reserven einer Staffel.
.sperr_index <- function(verteilung, erst) {
  if (length(erst) == 0L) {
    return(rep(0L, nrow(verteilung$abstieg)))
  }
  fehlend <- setdiff(erst, verteilung$teams)
  if (length(fehlend)) {
    stop(sprintf("Sperrverteilung kennt die Erstmannschaft nicht: %s",
                 paste(fehlend, collapse = ", ")), call. = FALSE)
  }
  bits <- verteilung$abstieg[, erst, drop = FALSE]
  as.integer(bits %*% 2^(seq_along(erst) - 1L))
}

#' Gewichte der 2^k Masken einer Staffel (Randverteilung von P(S)).
#'
#' @param erst Kurznamen der Erstmannschaften in der Reihenfolge der Reserven
#'   der Staffel (wie in sperr_masken()).
#' @return Vektor der Laenge 2^k, Summe 1.
sperr_gewichte <- function(verteilung, erst) {
  idx <- .sperr_index(verteilung, erst)
  w <- numeric(2L^length(erst))
  for (i in seq_along(idx)) {
    w[idx[[i]] + 1L] <- w[idx[[i]] + 1L] + verteilung$gewicht[[i]]
  }
  w
}

#' Gemeinsame Gewichte der Masken zweier Staffeln (Nord und Bayern teilen
#' sich dieselbe 2. Bundesliga).
#'
#' @return Matrix 2^kx x 2^ky, Summe 1; die Zeilensummen sind
#'   sperr_gewichte(verteilung, erst_x).
sperr_gewichte_paar <- function(verteilung, erst_x, erst_y) {
  ix <- .sperr_index(verteilung, erst_x)
  iy <- .sperr_index(verteilung, erst_y)
  w <- matrix(0, 2L^length(erst_x), 2L^length(erst_y))
  for (i in seq_along(ix)) {
    w[ix[[i]] + 1L, iy[[i]] + 1L] <- w[ix[[i]] + 1L, iy[[i]] + 1L] +
      verteilung$gewicht[[i]]
  }
  w
}

#' P(gesperrt) je Reserve.
sperr_risiko <- function(verteilung, reserven, erst) {
  p <- vapply(erst, function(e) {
    sum(verteilung$gewicht[verteilung$abstieg[, e]])
  }, numeric(1))
  stats::setNames(p, reserven)
}

#' Die Prognose einer Staffel mit der Sperre eingemischt.
#'
#' Die Staffel liefert `eligible_rank_probabilities` als Liste der 2^k Masken.
#' Hier wird mit den Gewichten gemischt; das Ergebnis traegt eine EINZIGE
#' Matrix an derselben Stelle, so dass erster_berechtigter() und
#' nicht_berechtigt() (rl_aufstieg.R) unveraendert weiterrechnen. Die
#' Matrix des Hauptlaufs (Heatmap, Meister) bleibt unberuehrt.
#'
#' Zusaetzlich bleiben als Attribute, was die gemeinsame Doppelsumme der
#' Aufstiegsspiele braucht: `erster_je_maske` (Teams x 2^k, P(Rang 1 | Maske))
#' und `sperr_gewichte`.
#'
#' @param prognose Prognosematrix mit Attribut eligible_rank_probabilities
#'   (Liste von 2^k Matrizen) -- sonst unveraendert zurueck.
#' @param gewichte Vektor der Laenge 2^k.
#' @param risiko Optional: benannter Vektor P(gesperrt) je Reserve.
mit_sperrmischung <- function(prognose, gewichte, risiko = NULL) {
  rang <- attr(prognose, "eligible_rank_probabilities")
  if (is.null(rang) || length(rang) != length(gewichte)) {
    return(prognose)
  }
  namen <- rownames(as.matrix(prognose))
  je_maske <- lapply(rang, function(m) as.matrix(m)[namen, , drop = FALSE])
  gemischt <- Reduce(`+`, Map(function(m, w) m * w, je_maske, gewichte))

  attr(prognose, "erster_je_maske") <- vapply(
    je_maske, function(m) m[, 1L], numeric(length(namen))
  )
  rownames(attr(prognose, "erster_je_maske")) <- namen
  attr(prognose, "sperr_gewichte") <- gewichte
  attr(prognose, "sperr_risiko") <- risiko
  attr(prognose, "eligible_rank_probabilities") <- list(gemischt)
  prognose
}
