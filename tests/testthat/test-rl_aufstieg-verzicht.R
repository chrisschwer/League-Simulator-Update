library(testthat)

# Aufstiegsverzicht (#320, ADR 0009): Hat eine Staffel Teams ohne
# Aufstiegsberechtigung, traegt die Prognose das Attribut
# `eligible_rank_probabilities` (Rang unter den Berechtigten). Aufstieg ist dann
# P(erster Berechtigter) statt P(Meister) -- ein verzichtender Meister vererbt
# seinen Platz.

verzicht_module <- function() source_module("staffel_zuordnung", "rl_abstiegskopplung", "rl_aufstieg", "rl_verdrahtung")

# Prognose mit Rang-Attribut: `rang1` ist P(erster Berechtigter) je Team, die
# uebrigen Raenge sind fuer diese Tests unerheblich.
mit_rang <- function(prognose, rang1) {
  m <- matrix(0, nrow = length(rang1), ncol = ncol(prognose),
              dimnames = list(names(rang1), colnames(prognose)))
  m[, 1] <- rang1
  attr(prognose, "eligible_rank_probabilities") <- list(m)
  prognose
}

test_that("Direktstaffel: der Aufstieg des verzichtenden Meisters geht an den naechsten Berechtigten", {
  env <- verzicht_module()
  # West: G ist wahrscheinlicher Meister, verzichtet aber.
  west <- mit_rang(prognose_aus_meister(c(G = 0.55, H = 0.45)), c(G = 0, H = 1))
  erg <- fn(env, "rl_aufstiegsprognose")("West", list(West = west), season = 2026)

  expect_equal(erg$Aufstieg, c(0, 1))
  expect_identical(rownames(erg), c("G", "H"))
  expect_identical(attr(erg, "verzichtet"), "G")
  # Die Meisterchance der Tabelle bleibt unberuehrt.
  expect_equal(unname(fn(env, "meisterwahrscheinlichkeit")(west)), c(0.55, 0.45))
})

test_that("ohne Verzicht bleibt P(Aufstieg) = P(Meister), Attribut leer", {
  env <- verzicht_module()
  erg <- fn(env, "rl_aufstiegsprognose")("West", prognosen_2026(), season = 2026)
  expect_equal(erg$Aufstieg, c(0.55, 0.45))
  expect_identical(attr(erg, "verzichtet"), character(0))
})

test_that("Aufstiegsspiele: der erste Berechtigte tritt an, die Siegquote bleibt ein Anteil", {
  env <- verzicht_module()
  prognosen <- prognosen_2026()
  # Nord: A (P(Meister) 0,6) verzichtet, B ist sicher der erste Berechtigte.
  prognosen$Nord <- mit_rang(prognosen$Nord, c(A = 0, B = 1))
  nord <- fn(env, "rl_aufstiegsprognose")("Nord", prognosen, season = 2026,
                                          p_sieg = sieg_nord_gegen_bayern)
  bayern <- fn(env, "rl_aufstiegsprognose")("Bayern", prognosen, season = 2026,
                                            p_sieg = sieg_nord_gegen_bayern)

  # B steigt auf, wenn er die Spiele gewinnt: 0,7 * 0,3 + 0,3 * 0,6 = 0,39.
  expect_equal(nord["B", "Aufstieg"], 0.39)
  expect_equal(nord["A", "Aufstieg"], 0)
  # Bayern: C 0,7 * (1 - 0,3) = 0,49; D 0,3 * (1 - 0,6) = 0,12.
  expect_equal(bayern["C", "Aufstieg"], 0.49)
  expect_equal(bayern["D", "Aufstieg"], 0.12)
  # Genau einer steigt auf.
  expect_equal(sum(nord$Aufstieg) + sum(bayern$Aufstieg), 1)

  # Nenner der Siegquote: P(erster Berechtigter), nicht P(Meister).
  expect_equal(attr(nord, "p_erster_berechtigter")[["B"]], 1)
  expect_identical(attr(nord, "verzichtet"), "A")
})

test_that("erster_berechtigter ordnet ueber Teamnamen zu, nicht ueber die Position", {
  env <- verzicht_module()
  prognose <- prognose_aus_meister(c(G = 0.55, H = 0.45))
  # Das Rang-Objekt steht in umgekehrter Reihenfolge.
  prognose <- mit_rang(prognose, c(H = 0.7, G = 0.3))
  expect_equal(fn(env, "erster_berechtigter")(prognose), c(G = 0.3, H = 0.7))
})

test_that("rl_direktaufstiegsspalten liefert nur Direktstaffeln mit Verzicht", {
  env <- verzicht_module()
  prognosen <- prognosen_2026()
  # Ohne Verzicht in irgendeiner Staffel: nichts.
  expect_length(fn(env, "rl_direktaufstiegsspalten")(prognosen, 2026), 0L)

  prognosen$West <- mit_rang(prognosen$West, c(G = 0, H = 1))
  # Nord verzichtet auch -- aber Nord ist 2026 keine Direktstaffel.
  prognosen$Nord <- mit_rang(prognosen$Nord, c(A = 0, B = 1))
  spalten <- fn(env, "rl_direktaufstiegsspalten")(prognosen, 2026)
  expect_named(spalten, "West")
})
