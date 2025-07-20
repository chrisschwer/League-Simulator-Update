library(testthat)
source("../../RCode/SpielCPP.R")
source("../../RCode/cpp_wrappers.R")

test_that("SpielCPP calculates ELO correctly for actual results", {
  # Test with actual match result (not simulated)
  result <- SpielCPP_wrapper(
    ELOHeim = 1500,
    ELOGast = 1500,
    ToreHeim = 2,
    ToreGast = 1,
    ZufallHeim = 0.5,  # Not used when Simulieren = FALSE
    ZufallGast = 0.5,  # Not used when Simulieren = FALSE
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Check return structure
  expect_length(result, 4)
  expect_named(result, c("ELOHeim", "ELOGast", "ToreHeim", "ToreGast"))
  
  # Home team won, so ELO should increase for home and decrease for away
  expect_true(result$ELOHeim > 1500)
  expect_true(result$ELOGast < 1500)
  
  # ELO changes should sum to zero
  elo_change_home <- result$ELOHeim - 1500
  elo_change_away <- result$ELOGast - 1500
  expect_equal(elo_change_home + elo_change_away, 0, tolerance = 0.01)
  
  # Goals should match input
  expect_equal(result$ToreHeim, 2)
  expect_equal(result$ToreGast, 1)
})

test_that("SpielCPP simulates match results correctly", {
  # Test match simulation
  set.seed(123)
  result <- SpielCPP_wrapper(
    ELOHeim = 1600,
    ELOGast = 1400,
    ToreHeim = NA,  # Will be simulated
    ToreGast = NA,  # Will be simulated
    ZufallHeim = runif(1),
    ZufallGast = runif(1),
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = TRUE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Check return structure
  expect_length(result, 4)
  expect_named(result, c("ELOHeim", "ELOGast", "ToreHeim", "ToreGast"))
  
  # Goals should be non-negative integers
  expect_true(result$ToreHeim >= 0)
  expect_true(result$ToreGast >= 0)
  expect_equal(result$ToreHeim, as.integer(result$ToreHeim))
  expect_equal(result$ToreGast, as.integer(result$ToreGast))
  
  # ELO should be updated based on simulated result
  expect_true(result$ELOHeim != 1600 || result$ELOGast != 1400)
})

test_that("SpielCPP handles draws correctly", {
  # Test draw result
  result <- SpielCPP_wrapper(
    ELOHeim = 1500,
    ELOGast = 1500,
    ToreHeim = 1,
    ToreGast = 1,
    ZufallHeim = 0.5,
    ZufallGast = 0.5,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # With equal ELO and a draw, changes should be minimal
  # Home team might gain slightly due to home advantage
  expect_true(abs(result$ELOHeim - 1500) < 10)
  expect_true(abs(result$ELOGast - 1500) < 10)
  
  # ELO changes should still sum to zero
  elo_change_home <- result$ELOHeim - 1500
  elo_change_away <- result$ELOGast - 1500
  expect_equal(elo_change_home + elo_change_away, 0, tolerance = 0.01)
})

test_that("SpielCPP handles extreme ELO differences", {
  # Strong favorite loses
  result <- SpielCPP_wrapper(
    ELOHeim = 1800,
    ELOGast = 1200,
    ToreHeim = 0,
    ToreGast = 1,
    ZufallHeim = 0.5,
    ZufallGast = 0.5,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Upset result should lead to large ELO changes
  expect_true(result$ELOHeim < 1800)  # Big decrease for favorite
  expect_true(result$ELOGast > 1200)   # Big increase for underdog
  
  # Changes should be larger than normal
  elo_change_home <- abs(result$ELOHeim - 1800)
  elo_change_away <- abs(result$ELOGast - 1200)
  expect_true(elo_change_home > 20)
  expect_true(elo_change_away > 20)
})

test_that("SpielCPP respects home advantage", {
  # Test two identical teams, one at home
  # Run multiple simulations to test statistical behavior
  set.seed(456)
  home_wins <- 0
  n_sims <- 100
  
  for (i in 1:n_sims) {
    result <- SpielCPP_wrapper(
      ELOHeim = 1500,
      ELOGast = 1500,
      ToreHeim = NA,
      ToreGast = NA,
      ZufallHeim = runif(1),
      ZufallGast = runif(1),
      ModFaktor = 40,
      Heimvorteil = 100,
      Simulieren = TRUE,
      ToreSlope = 0.7,
      ToreIntercept = 0.9
    )
    
    if (result$ToreHeim > result$ToreGast) {
      home_wins <- home_wins + 1
    }
  }
  
  # With home advantage, home team should win more often than 33%
  # (accounting for draws)
  expect_true(home_wins / n_sims > 0.35)
})

test_that("SpielCPP handles large goal differences", {
  # Test with a large win
  result <- SpielCPP_wrapper(
    ELOHeim = 1500,
    ELOGast = 1500,
    ToreHeim = 5,
    ToreGast = 0,
    ZufallHeim = 0.5,
    ZufallGast = 0.5,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Large win should result in larger ELO changes than 1-0
  result_small <- SpielCPP_wrapper(
    ELOHeim = 1500,
    ELOGast = 1500,
    ToreHeim = 1,
    ToreGast = 0,
    ZufallHeim = 0.5,
    ZufallGast = 0.5,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # ELO change should be larger for 5-0 than 1-0
  expect_true(abs(result$ELOHeim - 1500) > abs(result_small$ELOHeim - 1500))
})

test_that("SpielCPP produces consistent simulations with same random values", {
  # Same random values should produce same result
  result1 <- SpielCPP_wrapper(
    ELOHeim = 1550,
    ELOGast = 1450,
    ToreHeim = NA,
    ToreGast = NA,
    ZufallHeim = 0.7,
    ZufallGast = 0.3,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = TRUE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  result2 <- SpielCPP_wrapper(
    ELOHeim = 1550,
    ELOGast = 1450,
    ToreHeim = NA,
    ToreGast = NA,
    ZufallHeim = 0.7,
    ZufallGast = 0.3,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = TRUE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Results should be identical
  expect_equal(result1, result2)
})

test_that("SpielCPP correctly applies home advantage through SpielNichtSimulieren", {
  # Test that teams with different ELOs but same effective strength 
  # (ELO + home advantage) get the same ELO changes
  
  # All scenarios: home wins 2-1
  # Effective strength is same in all cases (home ELO + advantage = 1500)
  scenarios <- list(
    list(home = 1500, away = 1500, adv = 0,   desc = "Equal teams, no advantage"),
    list(home = 1450, away = 1500, adv = 50,  desc = "Home weaker by 50, advantage 50"),
    list(home = 1400, away = 1500, adv = 100, desc = "Home weaker by 100, advantage 100"),
    list(home = 1350, away = 1500, adv = 150, desc = "Home weaker by 150, advantage 150")
  )
  
  elo_changes <- numeric(length(scenarios))
  final_elos <- numeric(length(scenarios))
  
  for (i in seq_along(scenarios)) {
    s <- scenarios[[i]]
    result <- SpielCPP_wrapper(
      ELOHeim = s$home,
      ELOGast = s$away,
      ToreHeim = 2,
      ToreGast = 1,
      ZufallHeim = 0.5,
      ZufallGast = 0.5,
      ModFaktor = 40,
      Heimvorteil = s$adv,
      Simulieren = FALSE
    )
    
    elo_changes[i] <- result$ELOHeim - s$home
    final_elos[i] <- result$ELOHeim
    
    # Verify effective strength
    expect_equal(s$home + s$adv, 1500, 
                 info = paste(s$desc, "- effective strength should be 1500"))
  }
  
  # All scenarios should have the same ELO change
  expect_true(all(abs(elo_changes - elo_changes[1]) < 0.001),
              info = "All scenarios with same effective strength should have same ELO change")
  
  # But final ELOs should be different (decreasing with higher home advantage)
  expect_true(all(diff(final_elos) < 0),
              info = "Final ELO should decrease with higher home advantage")
  
  # Specific checks
  expect_equal(elo_changes[1], 20, tolerance = 0.1,
               info = "Equal teams winning 2-1 should gain ~20 ELO")
  expect_equal(final_elos[1], 1520, tolerance = 0.1)
  expect_equal(final_elos[2], 1470, tolerance = 0.1)
  expect_equal(final_elos[3], 1420, tolerance = 0.1)
  expect_equal(final_elos[4], 1370, tolerance = 0.1)
  
  # Test home losses with different advantages
  # Both scenarios: home loses 1-2, same effective strength (1500)
  loss_scenarios <- list(
    list(home = 1500, away = 1500, adv = 0),
    list(home = 1400, away = 1500, adv = 100)
  )
  
  loss_changes <- numeric(length(loss_scenarios))
  
  for (i in seq_along(loss_scenarios)) {
    s <- loss_scenarios[[i]]
    result <- SpielCPP_wrapper(
      ELOHeim = s$home,
      ELOGast = s$away,
      ToreHeim = 1,
      ToreGast = 2,
      ZufallHeim = 0.5,
      ZufallGast = 0.5,
      ModFaktor = 40,
      Heimvorteil = s$adv,
      Simulieren = FALSE
    )
    
    loss_changes[i] <- result$ELOHeim - s$home
  }
  
  # Both should lose the same amount
  expect_equal(loss_changes[1], loss_changes[2], tolerance = 0.001,
               info = "Teams with same effective strength should have same ELO loss")
  expect_equal(loss_changes[1], -20, tolerance = 0.1,
               info = "Equal effective teams losing 1-2 should lose ~20 ELO")
})

test_that("SpielCPP handles zero goals correctly", {
  # Test 0-0 draw
  result <- SpielCPP_wrapper(
    ELOHeim = 1500,
    ELOGast = 1500,
    ToreHeim = 0,
    ToreGast = 0,
    ZufallHeim = 0.5,
    ZufallGast = 0.5,
    ModFaktor = 40,
    Heimvorteil = 100,
    Simulieren = FALSE,
    ToreSlope = 0.7,
    ToreIntercept = 0.9
  )
  
  # Should handle 0-0 without errors
  expect_length(result, 4)
  expect_equal(result$ToreHeim, 0)
  expect_equal(result$ToreGast, 0)
  
  # ELO changes should be minimal for equal teams with 0-0
  expect_true(abs(result$ELOHeim - 1500) < 10)
  expect_true(abs(result$ELOGast - 1500) < 10)
})

test_that("SpielCPP handles different mod factors correctly", {
  # Test with different modification factors
  mod_factors <- c(20, 40, 60)
  
  for (mod in mod_factors) {
    result <- SpielCPP_wrapper(
      ELOHeim = 1500,
      ELOGast = 1400,
      ToreHeim = 2,
      ToreGast = 1,
      ZufallHeim = 0.5,
      ZufallGast = 0.5,
      ModFaktor = mod,
      Heimvorteil = 100,
      Simulieren = FALSE,
      ToreSlope = 0.7,
      ToreIntercept = 0.9
    )
    
    # Higher mod factor should lead to larger ELO changes
    elo_change <- abs(result$ELOHeim - 1500)
    
    if (mod == 20) {
      expect_true(elo_change < 30)
    } else if (mod == 60) {
      expect_true(elo_change > 10)
    }
  }
})