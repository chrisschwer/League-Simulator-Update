use crate::elo::calculate_elo_change;
use crate::models::{EloParams, EloResult};

/// Simulates a match between two teams based on their ELO ratings
/// Matches the logic in SpielCPP.R
pub fn simulate_match(
    elo_home: f64,
    elo_away: f64,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    random_home: f64,
    random_away: f64,
) -> EloResult {
    // Calculate ELO delta
    let elo_delta = elo_home + home_advantage - elo_away;

    // Calculate average goals for each team
    let tore_heim_durchschnitt = (elo_delta * tore_slope + tore_intercept).max(0.001);
    let tore_gast_durchschnitt = ((-elo_delta) * tore_slope + tore_intercept).max(0.001);

    // Generate goals using Poisson distribution with quantile function
    let goals_home = poisson_quantile(random_home, tore_heim_durchschnitt) as i32;
    let goals_away = poisson_quantile(random_away, tore_gast_durchschnitt) as i32;

    // Calculate ELO changes based on the result
    let params = EloParams {
        elo_home,
        elo_away,
        goals_home,
        goals_away,
        mod_factor,
        home_advantage,
    };

    calculate_elo_change(&params)
}

/// Simulates a match with actual random number generation
pub fn simulate_match_random<R: rand::Rng + rand::RngExt>(
    elo_home: f64,
    elo_away: f64,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    rng: &mut R,
) -> EloResult {
    let random_home = rng.random::<f64>();
    let random_away = rng.random::<f64>();

    simulate_match(
        elo_home,
        elo_away,
        mod_factor,
        home_advantage,
        tore_slope,
        tore_intercept,
        random_home,
        random_away,
    )
}

/// Calculate the quantile of a Poisson distribution.
/// Matches R's qpois: smallest integer k with P(X <= k) >= p.
fn poisson_quantile(p: f64, lambda: f64) -> f64 {
    // Production lambdas are ~0.6-2.5 (ELO-derived goal averages), so the
    // O(k) direct summation terminates after a handful of multiplications
    // instead of ~5 regularized-gamma CDF evaluations per draw.
    if lambda < 10.0 {
        poisson_quantile_direct(p, lambda)
    } else {
        poisson_quantile_statrs(p, lambda)
    }
}

/// Iterative CDF summation: P(X = k) = P(X = k-1) * lambda / k.
pub fn poisson_quantile_direct(p: f64, lambda: f64) -> f64 {
    if p <= 0.0 {
        return 0.0;
    }
    if p >= 1.0 {
        return f64::INFINITY;
    }
    let mut k: u64 = 0;
    let mut prob = (-lambda).exp(); // P(X = 0)
    let mut cumulative = prob;
    while cumulative < p && k < 1000 {
        k += 1;
        prob *= lambda / (k as f64);
        cumulative += prob;
    }
    k as f64
}

// Alternative implementation using statrs for better accuracy
pub fn poisson_quantile_statrs(p: f64, lambda: f64) -> f64 {
    use statrs::distribution::{DiscreteCDF, Poisson as StatrsPoisson};

    if p <= 0.0 {
        return 0.0;
    }
    if p >= 1.0 {
        return f64::INFINITY;
    }

    let poisson = StatrsPoisson::new(lambda).unwrap();

    // Binary search for the quantile
    let mut low = 0;
    let mut high = (lambda * 3.0 + 20.0) as u64; // Upper bound estimate

    while low < high {
        let mid = (low + high) / 2;
        let cdf = poisson.cdf(mid);

        if cdf < p {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    low as f64
}

#[cfg(test)]
mod poisson_tests {
    use super::*;

    #[test]
    fn direct_quantile_matches_r_qpois() {
        // Expected values computed with R: qpois(p, 1.3218390805)
        let lambda = 1.3218390805;
        let cases = [
            (0.1, 0.0),
            (0.2, 0.0),
            (0.3, 1.0),
            (0.5, 1.0),
            (0.7, 2.0),
            (0.9, 3.0),
        ];
        for (p, expected) in cases {
            assert_eq!(
                poisson_quantile_direct(p, lambda),
                expected,
                "qpois({}, {})",
                p,
                lambda
            );
        }
    }

    #[test]
    fn direct_quantile_agrees_with_binary_search() {
        for &lambda in &[0.1, 0.5, 1.0, 1.3218390805, 2.0, 5.0, 9.9] {
            let mut p = 0.001;
            while p < 0.999 {
                assert_eq!(
                    poisson_quantile_direct(p, lambda),
                    poisson_quantile_statrs(p, lambda),
                    "divergence at p={}, lambda={}",
                    p,
                    lambda
                );
                p += 0.001;
            }
        }
    }

    #[test]
    fn direct_quantile_edge_cases() {
        assert_eq!(poisson_quantile_direct(0.0, 1.5), 0.0);
        assert_eq!(poisson_quantile_direct(-0.1, 1.5), 0.0);
        assert_eq!(poisson_quantile_direct(1.0, 1.5), f64::INFINITY);
    }
}
