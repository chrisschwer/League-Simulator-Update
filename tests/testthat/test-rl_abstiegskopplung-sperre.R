library(testthat)

# Abstiegsfolge der dynamischen Aufstiegssperre (#331): Eine gesperrte Reserve
# (Erstmannschaft steigt aus der 2. Bundesliga in die 3. Liga ab) rueckt ans
# Tabellenende und steigt ab, die uebrigen ruecken auf, die Zahl der
# Absteiger bleibt gleich. Der Platzvektor wirkt auf den Rang unter den
# Nicht-Gesperrten statt auf den Tabellenplatz.
#
# Die Sollwerte kommen aus einer AUFZAEHLUNG von Welten (Abschlusstabellen mit
# Gewicht), nicht aus derselben Formel: Fuer jede Welt wird die Tabelle von
# Hand umgebaut (Gesperrte ans Ende) und abgelesen, wer absteigt.

env <- source_module("league_registry", "staffel_zuordnung",
                     "rl_abstiegskopplung", "rl_sperre")

# Prognosematrix bzw. Rangmatrix (Teams x Plaetze) aus Welten: je Welt die
# Abschlusstabelle als Vektor der Kurznamen (Platz 1 zuerst) und ihr Gewicht.
# Mit `gesperrt` ist es der Rang unter den Nicht-Gesperrten (Gesperrte
# tragen null) -- genau was die Engine je Maske liefert.
matrix_aus_welten <- function(welten, gesperrt = character(0)) {
  teams <- welten[[1]]$tabelle
  m <- matrix(0, length(teams), length(teams),
              dimnames = list(sort(teams), as.character(seq_along(teams))))
  for (w in welten) {
    frei <- setdiff(w$tabelle, gesperrt)
    for (r in seq_along(frei)) m[frei[r], r] <- m[frei[r], r] + w$w
  }
  m
}

# Alle 2^k Rangmatrizen in der Bitordnung von sperr_masken().
rang_je_maske <- function(welten, reserven) {
  k <- length(reserven)
  lapply(seq_len(2L^k) - 1L, function(j) {
    matrix_aus_welten(welten, reserven[bitwAnd(j, 2L^(seq_len(k) - 1L)) > 0L])
  })
}

# Sollwert aus der Aufzaehlung: je Welt und je Sperr-Kombination werden die
# Gesperrten ans Ende gesetzt und die Plaetze `abstiegsplaetze` (von oben
# gezaehlt) abgelesen; Gesperrte zaehlen mit `gesperrt_wert`.
soll_aus_welten <- function(welten, reserven, gewichte_masken, plaetze,
                            gesperrt_wert = 1) {
  teams <- sort(welten[[1]]$tabelle)
  k <- length(reserven)
  p <- stats::setNames(numeric(length(teams)), teams)
  for (j in seq_len(2L^k)) {
    g <- gewichte_masken[[j]]
    gesperrt <- reserven[bitwAnd(j - 1L, 2L^(seq_len(k) - 1L)) > 0L]
    for (w in welten) {
      tabelle <- c(setdiff(w$tabelle, gesperrt), gesperrt)
      for (t in teams) {
        platz <- match(t, tabelle)
        wert <- if (t %in% gesperrt) gesperrt_wert else as.numeric(platz %in% plaetze)
        p[[t]] <- p[[t]] + g * w$w * wert
      }
    }
  }
  p
}

# Deterministische Tabelle: Team Tp steht sicher auf Platz p.
feste_tabelle <- function(n) list(list(w = 1, tabelle = sprintf("T%02d", seq_len(n))))

# Zaehlmatrix der 3. Liga, in der KEIN Drittligist in `staffel` faellt (k = 0
# sicher): Alle vier Absteiger gehen in eine andere Staffel, damit die
# Invariante der Zaehlung (Summe der Erwartungswerte = 4) haelt.
zaehlung_k0 <- function(staffel) {
  andere <- setdiff(STAFFELN_ERWARTET, staffel)[[1]]
  args <- list(c(0, 0, 0, 0, N_ITER))
  names(args) <- andere
  do.call(zaehlung, args)
}

# Zwei Welten mit sechs Teams, Reserve R mal Dritter, mal Vierter.
toy_welten <- function() {
  list(
    list(w = 0.6, tabelle = c("A", "B", "R", "C", "D", "E")),
    list(w = 0.4, tabelle = c("B", "A", "C", "R", "E", "D"))
  )
}

test_that("Maske 0 allein ist bitgleich mit der Rechnung ohne Sperre", {
  welten <- toy_welten()
  prognose <- matrix_aus_welten(welten)
  w <- c(0, 0, 0, 0, 1, 1)
  sperre <- list(rang = rang_je_maske(welten, "R"), gewichte = c(1, 0), reserven = "R")

  ohne <- env$abstiegswahrscheinlichkeit(prognose, w)
  mit <- env$abstiegswahrscheinlichkeit_mit_sperre(prognose, w, sperre)
  expect_identical(mit, ohne)

  # Auch durch die ganze Kette, fuer jede Staffel: dieselben Zahlen, nur das
  # Attribut sperr_risiko kommt hinzu.
  for (staffel in STAFFELN_ERWARTET) {
    counts <- zaehlung_k0(staffel)
    a <- env$rl_abstiegsprognose(staffel, prognose, counts)
    b <- env$rl_abstiegsprognose(staffel, prognose, counts,
                                 sperre = c(sperre, list(risiko = c(R = 0))))
    expect_identical(b$Abstieg, a$Abstieg, info = staffel)
    if (identical(staffel, "Bayern")) expect_identical(b$Relegation, a$Relegation)
    expect_identical(attr(b, "platz_abstieg"), attr(a, "platz_abstieg"), info = staffel)
    expect_identical(attr(b, "sperr_risiko"), c(R = 0))
    expect_null(attr(a, "sperr_risiko"))
  }
})

test_that("ohne sperrbare Reserve (sperre = NULL) bleibt alles wie bisher", {
  prognose <- matrix_aus_welten(toy_welten())
  a <- env$rl_abstiegsprognose("West", prognose, zaehlung_k0("West"))
  b <- env$rl_abstiegsprognose("West", prognose, zaehlung_k0("West"), sperre = NULL)
  expect_identical(a, b)
})

test_that("je Maske bleibt die Summe der Abstiegswahrscheinlichkeiten sum(w), wenn die letzten Plaetze sicher sind", {
  welten <- toy_welten()
  prognose <- matrix_aus_welten(welten)
  rang <- rang_je_maske(welten, "R")
  w <- c(0, 0, 0, 0.3, 1, 1)   # Platz 4 unsicher, 5 und 6 sicher
  nur_gesperrt <- list(rang = rang, gewichte = c(0, 1), reserven = "R")
  p <- env$abstiegswahrscheinlichkeit_mit_sperre(prognose, w, nur_gesperrt)
  expect_equal(sum(p), sum(w), tolerance = 1e-12)
  expect_equal(p[["R"]], 1)
  # Gegen die Aufzaehlung, Platz fuer Platz.
  soll <- soll_aus_welten(welten, "R", c(0, 1), plaetze = c(5, 6)) +
    0.3 * soll_aus_welten(welten, "R", c(0, 1), plaetze = 4, gesperrt_wert = 0)
  expect_equal(p, soll, tolerance = 1e-12)
})

test_that("Handbeispiel West: Reserve auf Platz 5 gesperrt -- Reserve 100 %, Viertletzter 0 %, drei Letzte 100 %", {
  welten <- feste_tabelle(18L)
  prognose <- matrix_aus_welten(welten)
  sperre <- list(rang = rang_je_maske(welten, "T05"), gewichte = c(0, 1),
                 reserven = "T05", risiko = c(T05 = 1))
  erg <- env$rl_abstiegsprognose("West", prognose, zaehlung_k0("West"), sperre = sperre)
  p <- erg$Abstieg
  names(p) <- rownames(erg)
  expect_equal(p[["T05"]], 1)
  expect_equal(p[["T15"]], 0)
  expect_equal(unname(p[c("T16", "T17", "T18")]), c(1, 1, 1))
  expect_equal(sum(p), 4)
  # Die Zonenlinie bleibt die Regel ohne Sperre: vier letzte Plaetze.
  expect_equal(attr(erg, "platz_abstieg"), c(numeric(14), 1, 1, 1, 1))
  expect_equal(attr(erg, "sperr_risiko"), c(T05 = 1))
})

test_that("Handbeispiel Bayern: Abstieg und Relegation ruecken um einen Rang, die Gesperrte hat Relegation 0", {
  welten <- feste_tabelle(19L)
  prognose <- matrix_aus_welten(welten)
  sperre <- list(rang = rang_je_maske(welten, "T05"), gewichte = c(0, 1),
                 reserven = "T05", risiko = c(T05 = 1))
  erg <- env$rl_abstiegsprognose("Bayern", prognose, zaehlung_k0("Bayern"), sperre = sperre)
  ab <- stats::setNames(erg$Abstieg, rownames(erg))
  rel <- stats::setNames(erg$Relegation, rownames(erg))
  # Ohne Sperre: Abstieg 18, 19; Relegation 16, 17. Mit T05 am Ende rueckt
  # alles ab Platz 6 um einen Rang auf.
  expect_equal(unname(ab[c("T05", "T19")]), c(1, 1))
  expect_equal(unname(ab[c("T16", "T17", "T18")]), c(0, 0, 0))
  expect_equal(unname(rel[c("T17", "T18")]), c(1, 1))
  expect_equal(unname(rel[c("T05", "T16", "T19")]), c(0, 0, 0))
  expect_equal(sum(ab), 2)
  expect_equal(sum(rel), 2)
  expect_equal(attr(erg, "platz_relegation"), c(numeric(15), 1, 1, 0, 0))
})

test_that("Nordost-Randfall: k = 0 und beide Reserven gesperrt -- beide 100 %, alle uebrigen 0 %", {
  welten <- feste_tabelle(18L)
  prognose <- matrix_aus_welten(welten)
  reserven <- c("T03", "T07")
  sperre <- list(rang = rang_je_maske(welten, reserven), gewichte = c(0, 0, 0, 1),
                 reserven = reserven, risiko = c(T03 = 1, T07 = 1))
  erg <- env$rl_abstiegsprognose("Nordost", prognose, zaehlung_k0("Nordost"), sperre = sperre)
  p <- stats::setNames(erg$Abstieg, rownames(erg))
  expect_equal(unname(p[reserven]), c(1, 1))
  expect_true(all(p[setdiff(names(p), reserven)] == 0))
  # Ein Abstiegsplatz nach Regel, zwei Absteiger durch die Sperre.
  expect_equal(sum(attr(erg, "platz_abstieg")), 1)
  expect_equal(sum(p), 2)
})

test_that("die Mischung ueber die Masken ist die gewichtete Summe der Einzelfaelle", {
  welten <- toy_welten()
  prognose <- matrix_aus_welten(welten)
  rang <- rang_je_maske(welten, "R")
  w <- c(0, 0, 0, 0, 1, 1)
  f <- function(g) {
    env$abstiegswahrscheinlichkeit_mit_sperre(
      prognose, w, list(rang = rang, gewichte = g, reserven = "R")
    )
  }
  expect_equal(f(c(0.7, 0.3)), 0.7 * f(c(1, 0)) + 0.3 * f(c(0, 1)), tolerance = 1e-12)
  expect_equal(f(c(0.7, 0.3)), soll_aus_welten(welten, "R", c(0.7, 0.3), plaetze = c(5, 6)),
               tolerance = 1e-12)
})

test_that("zwei Reserven: alle vier Masken gegen die Aufzaehlung", {
  welten <- list(
    list(w = 0.5, tabelle = c("A", "R1", "B", "R2", "C", "D")),
    list(w = 0.3, tabelle = c("R2", "A", "R1", "B", "D", "C")),
    list(w = 0.2, tabelle = c("B", "A", "C", "D", "R1", "R2"))
  )
  prognose <- matrix_aus_welten(welten)
  reserven <- c("R1", "R2")
  g <- c(0.4, 0.3, 0.2, 0.1)
  w <- c(0, 0, 0, 0, 1, 1)
  sperre <- list(rang = rang_je_maske(welten, reserven), gewichte = g, reserven = reserven)
  p <- env$abstiegswahrscheinlichkeit_mit_sperre(prognose, w, sperre)
  expect_equal(p, soll_aus_welten(welten, reserven, g, plaetze = c(5, 6)), tolerance = 1e-12)
  # Relegationsvariante: Gesperrte tragen 0.
  p0 <- env$abstiegswahrscheinlichkeit_mit_sperre(prognose, c(0, 0, 0, 1, 0, 0), sperre, gesperrt = 0)
  expect_equal(p0, soll_aus_welten(welten, reserven, g, plaetze = 4, gesperrt_wert = 0),
               tolerance = 1e-12)
})

test_that("Nord: die Kopplung an den eigenen Meisteraufstieg bleibt im Platzvektor und wirkt auf den Rang", {
  welten <- feste_tabelle(18L)
  prognose <- matrix_aus_welten(welten)
  sperre <- list(rang = rang_je_maske(welten, "T05"), gewichte = c(0, 1),
                 reserven = "T05", risiko = c(T05 = 1))
  # p = 1: Meister steigt auf, Basis 2 statt 3 -> zwei Abstiegsplaetze.
  erg <- env$rl_abstiegsprognose("Nord", prognose, zaehlung_k0("Nord"), p_meister_aufstieg = 1,
                                 sperre = sperre)
  p <- stats::setNames(erg$Abstieg, rownames(erg))
  expect_equal(unname(p[c("T05", "T18")]), c(1, 1))
  expect_equal(unname(p[c("T16", "T17")]), c(0, 0))
  expect_equal(sum(p), 2)
})

test_that("Rangmatrizen mit weniger Spalten als Plaetzen werden mit null aufgefuellt", {
  welten <- toy_welten()
  prognose <- matrix_aus_welten(welten)
  rang <- rang_je_maske(welten, "R")
  rang[[2]] <- rang[[2]][, 1:5]   # fuenf Nicht-Gesperrte, fuenf Raenge
  w <- c(0, 0, 0, 0, 1, 1)
  voll <- env$abstiegswahrscheinlichkeit_mit_sperre(
    prognose, w, list(rang = rang_je_maske(welten, "R"), gewichte = c(0.5, 0.5), reserven = "R")
  )
  kurz <- env$abstiegswahrscheinlichkeit_mit_sperre(
    prognose, w, list(rang = rang, gewichte = c(0.5, 0.5), reserven = "R")
  )
  expect_equal(kurz, voll, tolerance = 1e-12)
})

test_that("Aufruferfehler brechen ab statt still zu rechnen", {
  welten <- toy_welten()
  prognose <- matrix_aus_welten(welten)
  rang <- rang_je_maske(welten, "R")
  w <- c(0, 0, 0, 0, 1, 1)
  f <- function(sperre) env$abstiegswahrscheinlichkeit_mit_sperre(prognose, w, sperre)
  expect_error(f(list(rang = rang[1], gewichte = c(1, 0), reserven = "R")), "Masken")
  expect_error(f(list(rang = rang, gewichte = c(0.5, 0.4), reserven = "R")), "summieren")
  expect_error(f(list(rang = rang, gewichte = c(1, 0), reserven = "X")), "kennt die Reserve")
  rang_fremd <- rang
  rownames(rang_fremd[[2]])[1] <- "Z"
  expect_error(f(list(rang = rang_fremd, gewichte = c(0, 1), reserven = "R")), "kennt nicht")
})
