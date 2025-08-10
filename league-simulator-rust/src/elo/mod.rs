use crate::models::{EloParams, EloResult};

/// Calculate ELO changes based on match result
/// This matches the logic in SpielNichtSimulieren.cpp exactly
pub fn calculate_elo_change(params: &EloParams) -> EloResult {
    // Calculate ELO delta (inverted as in C++ code)
    let elo_delta_inv = params.elo_away - params.elo_home - params.home_advantage;
    
    // Clamp to [-400, 400] range as in C++ code
    let elo_delta_inv_clamped = elo_delta_inv.max(-400.0).min(400.0);
    
    // Calculate win probability for home team
    let elo_prob = 1.0 / (1.0 + 10_f64.powf(elo_delta_inv_clamped / 400.0));
    
    // Calculate actual result (0 = loss, 0.5 = draw, 1 = win)
    let goal_diff = params.goals_home - params.goals_away;
    let result = ((0 < goal_diff) as i32 - (goal_diff < 0) as i32 + 1) as f64 / 2.0;
    
    // Goal difference modifier (square root of absolute goal difference, minimum 1)
    let goal_mod = (goal_diff.abs().max(1) as f64).sqrt();
    
    // Calculate ELO change
    let elo_modificator = (result - elo_prob) * goal_mod * params.mod_factor;
    
    EloResult {
        new_elo_home: params.elo_home + elo_modificator,
        new_elo_away: params.elo_away - elo_modificator,
        goals_home: params.goals_home,
        goals_away: params.goals_away,
        win_probability_home: elo_prob,
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
pub use tests::*;