library(testthat)

# Aufstiegsberechtigung als Masken (ADR 0009): leagueSimulatorRust() mit
# eligibilityMasks liefert den Rang unter den Berechtigten aus demselben Lauf.
# Der Vergleichstest unten ist die Abnahme fuer das Entfernen des zweiten
# Laufs mit -50-Malus bei 3. Liga und 2. Frauen-Bundesliga: Beide Wege muessen
# dieselbe Verteilung liefern (Monte-Carlo-Toleranz).

# Vier Teams, Hin- und Rueckspiele, alle offen. Mit hoechstens 18 Punkten
# liegt ein Team mit -50 Punkten sicher am Tabellenende -- dann sind die Plaetze
# der Berechtigten im Malus-Lauf genau ihre Raenge unter den Berechtigten.
masken_spielplan <- function() {
  teams <- c("AAA", "BBB", "CCC", "DDD")
  paare <- expand.grid(heim = teams, gast = teams, stringsAsFactors = FALSE)
  paare <- paare[paare$heim != paare$gast, ]
  df <- data.frame(
    TeamHeim = match(paare$heim, teams), TeamGast = match(paare$gast, teams),
    ToreHeim = NA_integer_, ToreGast = NA_integer_
  )
  df$TeamHeim <- teams[df$TeamHeim]
  df$TeamGast <- teams[df$TeamGast]
  elo <- c(AAA = 1700, BBB = 1600, CCC = 1500, DDD = 1450)
  for (t in teams) df[[t]] <- elo[[t]]
  df
}

masken_env <- function() source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "rl_aufstieg", "aufstiegsspiele", "rust_integration")

test_that("Integration: Rang unter den Berechtigten stimmt mit dem Malus-Lauf ueberein", {
  env <- skip_if_no_rust(masken_env())
  lauf <- fn(env, "leagueSimulatorRust")
  spielplan <- masken_spielplan()
  # AAA und CCC sind gesperrt; Spielplan-Reihenfolge AAA, BBB, CCC, DDD.
  n <- 20000

  mit_maske <- lauf(spielplan, n = n, numberTeams = 4,
                    eligibilityMasks = list(c(FALSE, TRUE, FALSE, TRUE)))
  rang <- attr(mit_maske, "eligible_rank_probabilities")[[1]]

  # Der alte Weg: ein zweiter Lauf, in dem die Gesperrten -50 Punkte tragen.
  malus <- lauf(spielplan, n = n, numberTeams = 4,
                adjPoints = c(-50, 0, -50, 0))

  berechtigt <- c("BBB", "DDD")
  expect_equal(unname(rang[berechtigt, 1:2]), unname(malus[berechtigt, 1:2]),
               tolerance = 0.03)
  # Die Gesperrten haben keinen Rang unter den Berechtigten.
  expect_true(all(rang[c("AAA", "CCC"), ] == 0))
  # Rang 1 und 2 unter den Berechtigten summieren auf 1; es gibt keinen dritten.
  expect_equal(unname(colSums(rang)), c(1, 1, 0, 0), tolerance = 1e-9)
})

test_that("Integration: ohne Maske traegt das Ergebnis kein eligible_rank_probabilities", {
  env <- skip_if_no_rust(masken_env())
  erg <- fn(env, "leagueSimulatorRust")(masken_spielplan(), n = 200, numberTeams = 4)
  expect_null(attr(erg, "eligible_rank_probabilities"))
})

test_that("Integration: alle berechtigt ergibt dieselbe Verteilung wie die Tabelle", {
  env <- skip_if_no_rust(masken_env())
  erg <- fn(env, "leagueSimulatorRust")(masken_spielplan(), n = 2000, numberTeams = 4,
                                        eligibilityMasks = list(rep(TRUE, 4)))
  rang <- attr(erg, "eligible_rank_probabilities")[[1]]
  # Dieselben Iterationen, dieselbe Tabelle: exakte Gleichheit.
  expect_equal(unname(rang), unname(unclass(erg)[rownames(rang), ]), tolerance = 1e-12,
               check.attributes = FALSE)
})

test_that("Integration: verfolgte Teams liefern gemeinsame Klassenvektoren (#322)", {
  env <- skip_if_no_rust(masken_env())
  n <- 4000
  erg <- fn(env, "leagueSimulatorRust")(
    masken_spielplan(), n = n, numberTeams = 4,
    trackedTeams = c("DDD", "BBB"), trackedDirectPlaces = 2, trackedPlayoffPlaces = 1
  )
  muster <- attr(erg, "tracked_class_patterns")
  expect_false(is.null(muster))
  expect_identical(colnames(muster$classes), c("DDD", "BBB"))
  expect_equal(sum(muster$counts), n)

  # Die Randverteilung aus den Mustern ist die der Prognosematrix (Plaetze 3
  # und 4 = direkter Abstieg, Platz 2 = Relegationsplatz): dieselben Laeufe.
  direkt <- sum(muster$counts[muster$classes[, "DDD"] == 1L]) / n
  expect_equal(direkt, sum(erg["DDD", 3:4]), tolerance = 1e-12)
  rel <- sum(muster$counts[muster$classes[, "BBB"] == 2L]) / n
  expect_equal(rel, erg["BBB", 2], tolerance = 1e-12)
})

test_that("Integration: ein Kurzname ausserhalb des Spielplans bricht ab", {
  env <- skip_if_no_rust(masken_env())
  expect_error(
    fn(env, "leagueSimulatorRust")(masken_spielplan(), n = 100, numberTeams = 4,
                                    trackedTeams = "ZZZ", trackedDirectPlaces = 2),
    "nicht im Spielplan"
  )
})
