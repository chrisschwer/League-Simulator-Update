use crate::models::{Season, SimulationParams, SimulationResult};
use crate::simulation::process_season;
use rayon::prelude::*;
use rand::{SeedableRng, rngs::StdRng};
use std::sync::Mutex;

/// Run Monte Carlo simulations in parallel to get probability distribution
/// Matches the logic in simulationsCPP.R and leagueSimulatorCPP.R
pub fn run_monte_carlo_simulation(
    season: &Season,
    params: &SimulationParams,
    team_names: Vec<String>,
) -> SimulationResult {
    // Initialize probability matrix (teams x positions)
    let n_teams = season.number_teams;
    let position_counts: Vec<Mutex<Vec<usize>>> = (0..n_teams)
        .map(|_| Mutex::new(vec![0; n_teams]))
        .collect();
    
    // Run simulations in parallel
    (0..params.iterations).into_par_iter().for_each(|iteration| {
        // Create RNG with unique seed for each iteration
        let mut rng = StdRng::seed_from_u64(iteration as u64);
        
        // Simulate season
        let (table, _) = process_season(
            season,
            params.mod_factor,
            params.home_advantage,
            params.tore_slope,
            params.tore_intercept,
            None, None, None, None,  // No adjustments for now
            &mut rng,
        );
        
        // Record final positions
        for standing in &table.standings {
            let team_id = standing.team_id;
            let position = standing.position - 1;  // Convert to 0-indexed
            
            let mut counts = position_counts[team_id].lock().unwrap();
            counts[position] += 1;
        }
    });
    
    // Convert counts to probabilities
    let mut probability_matrix = vec![vec![0.0; n_teams]; n_teams];
    
    for (team_id, counts_mutex) in position_counts.iter().enumerate() {
        let counts = counts_mutex.lock().unwrap();
        for (position, &count) in counts.iter().enumerate() {
            probability_matrix[team_id][position] = count as f64 / params.iterations as f64;
        }
    }
    
    // Sort teams by average position (best teams first)
    let mut team_rankings: Vec<(usize, f64)> = (0..n_teams)
        .map(|team_id| {
            let avg_position: f64 = probability_matrix[team_id]
                .iter()
                .enumerate()
                .map(|(pos, &prob)| (pos + 1) as f64 * prob)
                .sum();
            (team_id, avg_position)
        })
        .collect();
    
    team_rankings.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
    
    // Reorder probability matrix by ranking
    let mut sorted_matrix = vec![vec![0.0; n_teams]; n_teams];
    let mut sorted_names = vec![String::new(); n_teams];
    
    for (new_idx, &(team_id, _)) in team_rankings.iter().enumerate() {
        sorted_matrix[new_idx] = probability_matrix[team_id].clone();
        sorted_names[new_idx] = if team_id < team_names.len() {
            team_names[team_id].clone()
        } else {
            format!("Team {}", team_id + 1)
        };
    }
    
    SimulationResult {
        probability_matrix: sorted_matrix,
        team_names: sorted_names,
    }
}

/// Run Monte Carlo with adjustments (e.g., for Liga 3 second teams)
pub fn run_monte_carlo_with_adjustments(
    season: &Season,
    params: &SimulationParams,
    team_names: Vec<String>,
    adj_points: Option<Vec<i32>>,
    adj_goals: Option<Vec<i32>>,
    adj_goals_against: Option<Vec<i32>>,
    adj_goal_diff: Option<Vec<i32>>,
) -> SimulationResult {
    let n_teams = season.number_teams;
    let position_counts: Vec<Mutex<Vec<usize>>> = (0..n_teams)
        .map(|_| Mutex::new(vec![0; n_teams]))
        .collect();
    
    // Convert Option<Vec> to Option<&[i32]> for the adjustments
    let adj_points_ref = adj_points.as_deref();
    let adj_goals_ref = adj_goals.as_deref();
    let adj_goals_against_ref = adj_goals_against.as_deref();
    let adj_goal_diff_ref = adj_goal_diff.as_deref();
    
    (0..params.iterations).into_par_iter().for_each(|iteration| {
        let mut rng = StdRng::seed_from_u64(iteration as u64);
        
        let (table, _) = process_season(
            season,
            params.mod_factor,
            params.home_advantage,
            params.tore_slope,
            params.tore_intercept,
            adj_points_ref,
            adj_goals_ref,
            adj_goals_against_ref,
            adj_goal_diff_ref,
            &mut rng,
        );
        
        for standing in &table.standings {
            let team_id = standing.team_id;
            let position = standing.position - 1;
            
            let mut counts = position_counts[team_id].lock().unwrap();
            counts[position] += 1;
        }
    });
    
    // Convert to probabilities and sort as before
    let mut probability_matrix = vec![vec![0.0; n_teams]; n_teams];
    
    for (team_id, counts_mutex) in position_counts.iter().enumerate() {
        let counts = counts_mutex.lock().unwrap();
        for (position, &count) in counts.iter().enumerate() {
            probability_matrix[team_id][position] = count as f64 / params.iterations as f64;
        }
    }
    
    let mut team_rankings: Vec<(usize, f64)> = (0..n_teams)
        .map(|team_id| {
            let avg_position: f64 = probability_matrix[team_id]
                .iter()
                .enumerate()
                .map(|(pos, &prob)| (pos + 1) as f64 * prob)
                .sum();
            (team_id, avg_position)
        })
        .collect();
    
    team_rankings.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
    
    let mut sorted_matrix = vec![vec![0.0; n_teams]; n_teams];
    let mut sorted_names = vec![String::new(); n_teams];
    
    for (new_idx, &(team_id, _)) in team_rankings.iter().enumerate() {
        sorted_matrix[new_idx] = probability_matrix[team_id].clone();
        sorted_names[new_idx] = if team_id < team_names.len() {
            team_names[team_id].clone()
        } else {
            format!("Team {}", team_id + 1)
        };
    }
    
    SimulationResult {
        probability_matrix: sorted_matrix,
        team_names: sorted_names,
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
pub use tests::*;