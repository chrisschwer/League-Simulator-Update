library(testthat)
source("../../RCode/rl_sperre.R")

# Die Algebra der dynamischen Aufstiegssperre (#322): gemeinsame Verteilung
# der gesperrten Reserven und ihre Mischung. Alles exakt, ohne Monte Carlo --
# die Eingaben sind kleine, von Hand gewaehlte Verteilungen, und die Erwartung
# kommt aus einer Aufzaehlung aller "Welten" (Muster x Relegationsausgang),
# nicht aus derselben Formel.

# Drei Zweitligisten A, B, C; Muster: Klassenvektoren der Engine.
toy_muster <- function() {
  klassen <- rbind(
    c(A = 1L, B = 1L, C = 0L),  # A und B direkt ab
    c(A = 1L, B = 0L, C = 2L),  # A direkt, C in der Relegation
    c(A = 0L, B = 2L, C = 1L),  # C direkt, B in der Relegation
    c(A = 0L, B = 0L, C = 0L)   # keiner der drei
  )
  list(classes = klassen, counts = c(30, 20, 10, 40))
}
toy_pniederlage <- c(A = 0.5, B = 0.25, C = 0.8)

# Aufzaehlung aller Welten: Gewicht und Menge der Abgestiegenen.
toy_welten <- function() {
  m <- toy_muster()
  welten <- list()
  for (i in seq_len(nrow(m$classes))) {
    w <- m$counts[[i]] / sum(m$counts)
    direkt <- names(which(m$classes[i, ] == 1L))
    rel <- names(which(m$classes[i, ] == 2L))
    if (length(rel) == 0L) {
      welten[[length(welten) + 1L]] <- list(w = w, ab = direkt)
    } else {
      p <- toy_pniederlage[[rel]]
      welten[[length(welten) + 1L]] <- list(w = w * p, ab = c(direkt, rel))
      welten[[length(welten) + 1L]] <- list(w = w * (1 - p), ab = direkt)
    }
  }
  welten
}

test_that("die Erstvertretungen der 2. Liga kommen aus der TeamList, je Liga eindeutig", {
  tl <- data.frame(
    TeamID = c(1, 2, 3, 4, 5),
    ShortText = c("AAA", "AAA2", "BBB", "FCH", "FCH2"),
    League = c(79, 84, 80, 79, 85),
    Erstvertretung_TeamID = c(NA, 1, NA, NA, 4),
    stringsAsFactors = FALSE
  )
  z <- erstvertretungen_zweite_liga(tl)
  expect_identical(z$reserve, c("AAA2", "FCH2"))
  expect_identical(z$erst, c("AAA", "FCH"))
  expect_identical(z$liga, c("84", "85"))

  # Nur Reserven der Staffel, in Spielplan-Reihenfolge.
  s <- sperrbare_reserven(z, c("X", "FCH2", "AAA2"), "85")
  expect_identical(s$reserve, "FCH2")
  expect_identical(nrow(sperrbare_reserven(z, c("AAA2"), "85")), 0L)
})

test_that("ohne die Spalten gibt es keine Zuordnung", {
  tl <- data.frame(TeamID = 1, ShortText = "A", League = 79)
  expect_identical(nrow(erstvertretungen_zweite_liga(tl)), 0L)
})

test_that("sperr_masken zaehlt alle Teilmengen und haelt den Verzicht in jeder Maske", {
  kurz <- c("T1", "R1", "R2", "T2")
  basis <- c(TRUE, TRUE, TRUE, FALSE)   # T2 verzichtet
  m <- sperr_masken(basis, kurz, c("R1", "R2"))
  expect_length(m, 4L)
  expect_identical(m[[1]], c(TRUE, TRUE, TRUE, FALSE))      # niemand gesperrt
  expect_identical(m[[2]], c(TRUE, FALSE, TRUE, FALSE))     # R1
  expect_identical(m[[3]], c(TRUE, TRUE, FALSE, FALSE))     # R2
  expect_identical(m[[4]], c(TRUE, FALSE, FALSE, FALSE))    # beide
  # Ohne sperrbare Reserve genau eine Maske: die Basis.
  expect_identical(sperr_masken(basis, kurz, character(0)), list(basis))
})

test_that("die Verteilung stimmt mit der Aufzaehlung aller Welten ueberein", {
  v <- sperrverteilung(toy_muster(), toy_pniederlage)
  expect_equal(sum(v$gewicht), 1, tolerance = 1e-12)

  erwartet <- list()
  for (w in toy_welten()) {
    key <- paste(sort(w$ab), collapse = "|")
    erwartet[[key]] <- (if (is.null(erwartet[[key]])) 0 else erwartet[[key]]) + w$w
  }
  ist <- list()
  for (i in seq_len(nrow(v$abstieg))) {
    key <- paste(sort(v$teams[v$abstieg[i, ]]), collapse = "|")
    ist[[key]] <- v$gewicht[[i]]
  }
  expect_setequal(names(ist), names(erwartet))
  for (k in names(erwartet)) expect_equal(ist[[k]], erwartet[[k]], tolerance = 1e-12, info = k)
})

test_that("Staffel-Gewichte sind die Randverteilung, das Paar ist gemeinsam", {
  v <- sperrverteilung(toy_muster(), toy_pniederlage)
  # Staffel X hat die Reserven von A und B (Bits 1, 2), Staffel Y die von C.
  gx <- sperr_gewichte(v, c("A", "B"))
  gy <- sperr_gewichte(v, "C")
  expect_equal(sum(gx), 1); expect_equal(sum(gy), 1)

  # Gegen die Aufzaehlung: Maskenindex = A + 2*B.
  soll <- numeric(4)
  for (w in toy_welten()) {
    j <- as.integer("A" %in% w$ab) + 2L * as.integer("B" %in% w$ab)
    soll[j + 1L] <- soll[j + 1L] + w$w
  }
  expect_equal(gx, soll, tolerance = 1e-12)

  paar <- sperr_gewichte_paar(v, c("A", "B"), "C")
  expect_equal(dim(paar), c(4L, 2L))
  expect_equal(rowSums(paar), gx, tolerance = 1e-12)
  expect_equal(colSums(paar), gy, tolerance = 1e-12)
  # Gekoppelt, nicht unabhaengig: A und C steigen nie beide direkt ab UND
  # bleiben beide sicher in demselben Verhaeltnis wie ihre Randverteilungen.
  expect_false(isTRUE(all.equal(paar, outer(gx, gy), tolerance = 1e-9)))
})

test_that("das Sperrrisiko je Reserve ist P(Erstmannschaft steigt ab)", {
  v <- sperrverteilung(toy_muster(), toy_pniederlage)
  r <- sperr_risiko(v, c("RA", "RC"), c("A", "C"))
  soll_a <- sum(vapply(toy_welten(), function(w) if ("A" %in% w$ab) w$w else 0, numeric(1)))
  soll_c <- sum(vapply(toy_welten(), function(w) if ("C" %in% w$ab) w$w else 0, numeric(1)))
  expect_equal(unname(r), c(soll_a, soll_c), tolerance = 1e-12)
  expect_identical(names(r), c("RA", "RC"))
})

test_that("die Mischung gewichtet die Masken-Ergebnisse und liefert eine einzige Matrix", {
  prog <- matrix(c(0.6, 0.4, 0.4, 0.6), 2, byrow = TRUE,
                 dimnames = list(c("R1", "T"), c("1", "2")))
  m0 <- matrix(c(0.6, 0.4, 0.4, 0.6), 2, byrow = TRUE, dimnames = dimnames(prog))
  m1 <- matrix(c(0, 0, 1, 1), 2, byrow = TRUE, dimnames = dimnames(prog))  # R1 gesperrt
  attr(prog, "eligible_rank_probabilities") <- list(m0, m1)

  mix <- mit_sperrmischung(prog, c(0.75, 0.25), risiko = c(R1 = 0.25))
  rang <- attr(mix, "eligible_rank_probabilities")
  expect_length(rang, 1L)
  expect_equal(rang[[1]], 0.75 * m0 + 0.25 * m1)
  expect_equal(attr(mix, "erster_je_maske")[, 1], c(R1 = 0.6, T = 0.4))
  expect_equal(attr(mix, "erster_je_maske")[, 2], c(R1 = 0, T = 1))
  expect_equal(attr(mix, "sperr_gewichte"), c(0.75, 0.25))
  # Die Matrix des Hauptlaufs bleibt unberuehrt.
  expect_equal(unclass(mix)[, ], unclass(prog)[, ], ignore_attr = TRUE)
})

test_that("ohne passende Masken kommt die Prognose unveraendert zurueck", {
  prog <- matrix(1, 1, 1, dimnames = list("A", "1"))
  expect_identical(mit_sperrmischung(prog, c(1)), prog)
  attr(prog, "eligible_rank_probabilities") <- list(prog)
  expect_identical(mit_sperrmischung(prog, c(0.5, 0.5)), prog)
})

# --- Gemeinsame Doppelsumme der Aufstiegsspiele ----------------------------

sperre_modul <- function() {
  source_module("staffel_zuordnung", "rl_abstiegskopplung", "rl_aufstieg")
}

test_that("die gemeinsame Doppelsumme ist mit unabhaengigen Gewichten die alte Doppelsumme", {
  m <- sperre_modul()
  ex <- matrix(c(0.6, 0.3, 0.1, 0.5, 0.2, 0.3), 2, byrow = TRUE,
               dimnames = list(c("X1", "X2"), NULL))
  ey <- matrix(c(0.7, 0.2, 0.1, 0.4, 0.1, 0.5, 0.3, 0.2), 2, byrow = TRUE,
               dimnames = list(c("Y1", "Y2"), NULL))
  ex <- ex[, 1:2]; ey <- ey[, 1:2]
  wx <- c(0.75, 0.25); wy <- c(0.6, 0.4)
  ps <- matrix(c(0.7, 0.4, 0.55, 0.2), 2, byrow = TRUE,
               dimnames = list(c("X1", "X2"), c("Y1", "Y2")))

  gemeinsam <- m$aufstiegswahrscheinlichkeit_gemeinsam(ex, ey, outer(wx, wy), ps)
  alt <- m$aufstiegswahrscheinlichkeit(
    stats::setNames(as.vector(ex %*% wx), rownames(ex)),
    stats::setNames(as.vector(ey %*% wy), rownames(ey)), ps
  )
  expect_equal(gemeinsam, alt, tolerance = 1e-12)
})

test_that("gekoppelte Sperren: die gemeinsame Doppelsumme folgt der Aufzaehlung der Welten", {
  m <- sperre_modul()
  ex <- matrix(c(0.6, 0.4, 0.9, 0.1), 2, byrow = TRUE, dimnames = list(c("X1", "X2"), NULL))
  ey <- matrix(c(0.5, 0.5, 0.2, 0.8), 2, byrow = TRUE, dimnames = list(c("Y1", "Y2"), NULL))
  # Spalten = Masken (0 = keiner gesperrt, 1 = gesperrt); stark gekoppelt:
  w <- matrix(c(0.5, 0.0, 0.0, 0.5), 2, byrow = TRUE)
  ps <- matrix(c(0.7, 0.4, 0.55, 0.2), 2, byrow = TRUE,
               dimnames = list(c("X1", "X2"), c("Y1", "Y2")))

  ist <- m$aufstiegswahrscheinlichkeit_gemeinsam(ex, ey, w, ps)
  soll <- c(X1 = 0, X2 = 0)
  for (jx in 1:2) for (jy in 1:2) for (x in c("X1", "X2")) {
    soll[[x]] <- soll[[x]] + w[jx, jy] * ex[x, jx] *
      sum(ey[, jy] * ps[x, ])
  }
  expect_equal(ist, soll, tolerance = 1e-12)

  # Unabhaengig gerechnet kaeme etwas anderes heraus: Die Kopplung zaehlt.
  unabh <- m$aufstiegswahrscheinlichkeit_gemeinsam(ex, ey, outer(rowSums(w), colSums(w)), ps)
  expect_false(isTRUE(all.equal(ist, unabh, tolerance = 1e-6)))
})

test_that("rl_aufstiegsprognose rechnet die Aufstiegsspiele mit Sperrgewichten gemeinsam", {
  m <- sperre_modul()
  mk <- function(erste_spalte_je_maske, namen) {
    p <- matrix(c(0.6, 0.4, 0.4, 0.6), 2, byrow = TRUE, dimnames = list(namen, c("1", "2")))
    attr(p, "erster_je_maske") <- structure(erste_spalte_je_maske, dimnames = list(namen, NULL))
    attr(p, "eligible_rank_probabilities") <- list(p)
    p
  }
  nord <- mk(matrix(c(0.6, 0.4, 0.9, 0.1), 2, byrow = TRUE), c("N1", "N2"))
  bayern <- mk(matrix(c(0.5, 0.5, 0.2, 0.8), 2, byrow = TRUE), c("B1", "B2"))
  # Nord in STAFFELN vor Bayern: Zeilen = Nord, Spalten = Bayern.
  ps <- matrix(c(0.7, 0.4, 0.55, 0.2), 2, byrow = TRUE,
               dimnames = list(c("N1", "N2"), c("B1", "B2")))
  w <- matrix(c(0.5, 0, 0, 0.5), 2, byrow = TRUE)

  # 2026/27 haben Nord und Bayern die Aufstiegsspiele nur bei anderer Rotation;
  # die Rotation wird hier explizit gesetzt.
  rot <- c("2026" = "Nordost")
  gem <- m$rl_aufstiegsprognose("Nord", list(Nord = nord, Bayern = bayern), 2026,
                                p_sieg = ps, rotation = rot, sperrgewichte = w)
  soll <- m$aufstiegswahrscheinlichkeit_gemeinsam(
    attr(nord, "erster_je_maske"), attr(bayern, "erster_je_maske"), w, ps)
  expect_equal(gem$Aufstieg, unname(soll), tolerance = 1e-12)
  # Ohne Sperrgewichte: die alte Doppelsumme ueber die Randverteilungen.
  ohne <- m$rl_aufstiegsprognose("Nord", list(Nord = nord, Bayern = bayern), 2026,
                                 p_sieg = ps, rotation = rot)
  expect_false(isTRUE(all.equal(gem$Aufstieg, ohne$Aufstieg, tolerance = 1e-6)))
})

# --- Sicher gesperrt ist nicht "verzichtet" -------------------------------------

test_that("eine sicher gesperrte Reserve gilt nach der Mischung nicht als Verzichtende", {
  m <- sperre_modul()
  prog <- matrix(c(0.6, 0.4, 0.4, 0.6, 0.0, 0.0), 3, byrow = TRUE,
                 dimnames = list(c("RES", "T", "V"), c("1", "2")))
  m0 <- matrix(c(0.6, 0.4, 0.4, 0.6, 0, 0), 3, byrow = TRUE, dimnames = dimnames(prog))  # V verzichtet
  m1 <- matrix(c(0, 0, 1, 0.5, 0, 0), 3, byrow = TRUE, dimnames = dimnames(prog))       # RES gesperrt

  # P(gesperrt) = 1: RES traegt in der Mischung ueberall null ...
  mix <- mit_sperrmischung({ attr(prog, "eligible_rank_probabilities") <- list(m0, m1); prog },
                             c(0, 1))
  expect_true(all(attr(mix, "eligible_rank_probabilities")[[1]]["RES", ] == 0))
  # ... ist aber kein Verzichtender; nur V ist es.
  expect_identical(m$nicht_berechtigt(mix), "V")

  # Bei 0,99 dasselbe Bild.
  mix99 <- mit_sperrmischung({ attr(prog, "eligible_rank_probabilities") <- list(m0, m1); prog },
                               c(0.01, 0.99))
  expect_identical(m$nicht_berechtigt(mix99), "V")
})

test_that("eine veraltete Relegationsquote 0 bricht ab statt die Reserve fuer sicher zu halten", {
  expect_error(sperrverteilung(toy_muster(), c(A = 0.5, B = 0, C = 0.8)),
               "veraltete Relegationsquote")
})
