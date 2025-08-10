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
/// This matches R's qpois function behavior
fn poisson_quantile(p: f64, lambda: f64) -> f64 {
    // For now, use the statrs implementation
    poisson_quantile_statrs(p, lambda)
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
    let mut high = (lambda * 3.0 + 20.0) as u64;  // Upper bound estimate
    
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