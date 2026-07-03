use crate::models::{Season, SimulationParams, SimulationResult};
use crate::simulation::{calculate_table, simulate_season_in_place};
use rand::{rngs::StdRng, RngExt, SeedableRng};
use rayon::prelude::*;

/// Run Monte Carlo simulations in parallel to get probability distribution.
/// Matches the logic in simulationsCPP.R and leagueSimulatorCPP.R.
///
/// Each iteration draws a fresh per-iteration seed from the OS entropy pool,
/// so two consecutive calls with the same `params` produce slightly different
/// probability matrices. This matches the R/C++ behavior the scheduler relies
/// on. For deterministic output (tests), use [`run_monte_carlo_simulation_seeded`].
pub fn run_monte_carlo_simulation(
    season: &Season,
    params: &SimulationParams,
    team_names: Vec<String>,
) -> SimulationResult {
    let mut rng = rand::rng();
    let seeds: Vec<u64> = (0..params.iterations).map(|_| rng.random()).collect();
    run_monte_carlo_simulation_with_seeds(season, params, team_names, &seeds)
}

/// Deterministic variant of [`run_monte_carlo_simulation`].
///
/// Derives one sub-seed per iteration from `master_seed`, so two calls with
/// the same `master_seed` and `params` produce identical probability matrices.
/// Used by tests to verify the seed plumbing — production callers should use
/// [`run_monte_carlo_simulation`] (non-deterministic, matches R/C++ behavior).
///
/// Note: bit-exact equality across calls is *not* a stable contract under
/// refactoring of how `simulate_season_in_place` consumes RNG values. The
/// guarantee this function gives is "the seed is consumed and influences the
/// result" — see the dedicated test in `tests.rs`.
pub fn run_monte_carlo_simulation_seeded(
    season: &Season,
    params: &SimulationParams,
    team_names: Vec<String>,
    master_seed: u64,
) -> SimulationResult {
    let mut master = StdRng::seed_from_u64(master_seed);
    let seeds: Vec<u64> = (0..params.iterations).map(|_| master.random()).collect();
    run_monte_carlo_simulation_with_seeds(season, params, team_names, &seeds)
}

/// Shared implementation: takes a pre-built per-iteration seed slice so the
/// caller controls the determinism policy. Iteration order under Rayon does
/// not affect the result because aggregation is via integer counts (commutative).
fn run_monte_carlo_simulation_with_seeds(
    season: &Season,
    params: &SimulationParams,
    team_names: Vec<String>,
    seeds: &[u64],
) -> SimulationResult {
    assert_eq!(
        seeds.len(),
        params.iterations,
        "must provide one seed per iteration"
    );

    let n_teams = season.number_teams;

    // Per-thread fold state: reusable simulation buffers + local counts.
    // No locks; rayon reduces the per-thread counts at the end (addition is
    // commutative, so scheduling order cannot affect the result).
    struct IterState {
        matches: Vec<crate::models::Match>,
        elos: Vec<f64>,
        counts: Vec<Vec<usize>>,
    }

    let position_counts: Vec<Vec<usize>> = seeds
        .par_iter()
        .fold(
            || IterState {
                matches: Vec::with_capacity(season.matches.len()),
                elos: Vec::with_capacity(n_teams),
                counts: vec![vec![0usize; n_teams]; n_teams],
            },
            |mut state, &seed| {
                let mut rng = StdRng::seed_from_u64(seed);

                state.matches.clear();
                state.matches.extend_from_slice(&season.matches);
                state.elos.clear();
                state.elos.extend_from_slice(&season.team_elos);

                simulate_season_in_place(
                    &mut state.matches,
                    &mut state.elos,
                    params.mod_factor,
                    params.home_advantage,
                    params.tore_slope,
                    params.tore_intercept,
                    &mut rng,
                );

                let table = calculate_table(
                    &state.matches,
                    n_teams,
                    params.adj_points.as_deref(),
                    params.adj_goals.as_deref(),
                    params.adj_goals_against.as_deref(),
                    params.adj_goal_diff.as_deref(),
                );

                for standing in &table.standings {
                    state.counts[standing.team_id][standing.position - 1] += 1;
                }
                state
            },
        )
        .map(|state| state.counts)
        .reduce(
            || vec![vec![0usize; n_teams]; n_teams],
            |mut a, b| {
                for (row_a, row_b) in a.iter_mut().zip(b) {
                    for (cell_a, cell_b) in row_a.iter_mut().zip(row_b) {
                        *cell_a += cell_b;
                    }
                }
                a
            },
        );

    // Convert counts to probabilities
    let mut probability_matrix = vec![vec![0.0; n_teams]; n_teams];

    for (team_id, counts) in position_counts.iter().enumerate() {
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

#[cfg(test)]
mod tests;
