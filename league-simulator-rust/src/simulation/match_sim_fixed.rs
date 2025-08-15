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
pub fn simulate_match_random<R: rand::Rng>(
    elo_home: f64,
    elo_away: f64,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    rng: &mut R,
) -> EloResult {
    let random_home = rng.gen::<f64>();
    let random_away = rng.gen::<f64>();
    
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

/// Calculate the quantile of a Poisson distribution
/// This matches R's qpois function behavior EXACTLY
fn poisson_quantile(p: f64, lambda: f64) -> f64 {
    // For now, use the statrs implementation with the fix
    poisson_quantile_statrs_fixed(p, lambda)
}

// FIXED implementation to match R's qpois exactly
pub fn poisson_quantile_statrs_fixed(p: f64, lambda: f64) -> f64 {
    use statrs::distribution::{DiscreteCDF, Poisson as StatrsPoisson};
    
    if p <= 0.0 {
        return 0.0;
    }
    if p >= 1.0 {
        return f64::INFINITY;
    }
    
    let poisson = StatrsPoisson::new(lambda).unwrap();
    
    // Binary search for the quantile
    // R's qpois returns the smallest integer x such that P(X <= x) >= p
    let mut low = 0;
    let mut high = (lambda * 3.0 + 20.0) as u64;  // Upper bound estimate
    
    while low < high {
        let mid = (low + high) / 2;
        let cdf = poisson.cdf(mid);
        
        // CRITICAL FIX: Use < instead of <=
        // R's qpois returns smallest x where P(X <= x) >= p
        // So we want: if P(X <= mid) < p, then search higher
        if cdf < p {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    
    low as f64
}

// Alternative implementation using direct calculation for small lambda
// This can be more accurate for very small lambda values
pub fn poisson_quantile_direct(p: f64, lambda: f64) -> f64 {
    if p <= 0.0 {
        return 0.0;
    }
    if p >= 1.0 {
        return f64::INFINITY;
    }
    
    // For small lambda, use direct calculation
    if lambda < 10.0 {
        let mut cumulative = 0.0;
        let mut k = 0;
        
        // Calculate P(X = k) iteratively
        let mut prob = (-lambda).exp();  // P(X = 0)
        cumulative = prob;
        
        while cumulative < p && k < 100 {
            k += 1;
            prob *= lambda / (k as f64);
            cumulative += prob;
        }
        
        k as f64
    } else {
        // For larger lambda, use the binary search method
        poisson_quantile_statrs_fixed(p, lambda)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_poisson_quantile_matches_r() {
        // Test cases from R's qpois function
        // Lambda = 1.3218390805, various p values
        let lambda = 1.3218390805;
        
        // These expected values come from R
        let test_cases = vec![
            (0.1, 0.0),
            (0.2, 0.0),
            (0.3, 1.0),
            (0.4, 1.0),
            (0.5, 1.0),
            (0.6, 1.0),
            (0.7, 2.0),
            (0.8, 2.0),
            (0.9, 3.0),
        ];
        
        for (p, expected) in test_cases {
            let result = poisson_quantile_statrs_fixed(p, lambda);
            assert_eq!(
                result, expected,
                "qpois({}, {}) should be {}, got {}",
                p, lambda, expected, result
            );
        }
    }
    
    #[test]
    fn test_boundary_cases() {
        // Test at exact CDF boundaries
        let lambda = 1.5;
        
        // P(X <= 1) = 0.557825 for Poisson(1.5)
        // So qpois(0.557825) should be 1, qpois(0.557826) should be 2
        let p_boundary = 0.557825;
        
        assert_eq!(poisson_quantile_statrs_fixed(p_boundary, lambda), 1.0);
        assert_eq!(poisson_quantile_statrs_fixed(p_boundary + 0.0001, lambda), 2.0);
    }
}