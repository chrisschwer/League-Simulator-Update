//! Golden tests for the deterministic league-details computation.
//!
//! Expected values were computed independently (Python, double precision)
//! from the model formulas in `simulation/match_sim.rs` and `elo/mod.rs`:
//! lambda_home = max(delta * TORE_SLOPE + TORE_INTERCEPT, 0.001) with
//! delta = elo_home + home_advantage - elo_away, goals ~ independent Poisson,
//! ELO shift = (result - elo_prob) * sqrt(max(|goal_diff|, 1)) * mod_factor.

use super::*;
use crate::models::{Match, Season};
use approx::assert_relative_eq;

const TORE_SLOPE: f64 = 0.0017854953143549;
const TORE_INTERCEPT: f64 = 1.3218390804597700;
const HOME_ADVANTAGE: f64 = 40.0;
const MOD_FACTOR: f64 = 20.0;
const MAX_GOALS: usize = 6;

fn probs(elo_home: f64, elo_away: f64) -> MatchProbabilities {
    match_probabilities(
        elo_home,
        elo_away,
        HOME_ADVANTAGE,
        TORE_SLOPE,
        TORE_INTERCEPT,
        MAX_GOALS,
    )
}

// ---------------------------------------------------------------- 1/X/2 ----

#[test]
fn equal_elos_give_home_edge_from_home_advantage() {
    let p = probs(1500.0, 1500.0);
    assert_relative_eq!(p.lambda_home, 1.393258893034, epsilon = 1e-9);
    assert_relative_eq!(p.lambda_away, 1.250419267886, epsilon = 1e-9);
    assert_relative_eq!(p.p_home_win, 0.402904706240, epsilon = 1e-9);
    assert_relative_eq!(p.p_draw, 0.260577313073, epsilon = 1e-9);
    assert_relative_eq!(p.p_away_win, 0.336517980687, epsilon = 1e-9);
}

#[test]
fn stronger_home_team_shifts_probabilities() {
    let p = probs(1800.0, 1500.0);
    assert_relative_eq!(p.lambda_home, 1.928907487340, epsilon = 1e-9);
    assert_relative_eq!(p.lambda_away, 0.714770673579, epsilon = 1e-9);
    assert_relative_eq!(p.p_home_win, 0.661246199792, epsilon = 1e-9);
    assert_relative_eq!(p.p_draw, 0.208561263894, epsilon = 1e-9);
    assert_relative_eq!(p.p_away_win, 0.130192536314, epsilon = 1e-9);
}

#[test]
fn outcome_probabilities_sum_to_one() {
    for (eh, ea) in [(1500.0, 1500.0), (2057.0, 1481.0), (1481.0, 2057.0)] {
        let p = probs(eh, ea);
        assert_relative_eq!(p.p_home_win + p.p_draw + p.p_away_win, 1.0, epsilon = 1e-9);
    }
}

#[test]
fn extreme_elo_gap_keeps_lambda_positive() {
    // -delta * slope + intercept would go negative around delta ~ +740;
    // the model clamps each lambda at 0.001.
    let p = probs(3000.0, 1000.0);
    assert!(p.lambda_away >= 0.001);
    assert!(p.lambda_home > p.lambda_away);
    assert_relative_eq!(p.p_home_win + p.p_draw + p.p_away_win, 1.0, epsilon = 1e-9);
}

// --------------------------------------------------------- score matrix ----

#[test]
fn score_matrix_has_tail_dimensions_and_sums_to_one() {
    let p = probs(1500.0, 1500.0);
    assert_eq!(p.score_matrix.len(), MAX_GOALS + 1);
    for row in &p.score_matrix {
        assert_eq!(row.len(), MAX_GOALS + 1);
    }
    let total: f64 = p.score_matrix.iter().flatten().sum();
    assert_relative_eq!(total, 1.0, epsilon = 1e-9);
}

#[test]
fn score_matrix_matches_poisson_cells() {
    let p = probs(1500.0, 1500.0);
    // P(0:0) and P(1:1) are plain Poisson products.
    assert_relative_eq!(p.score_matrix[0][0], 0.071099273451, epsilon = 1e-9);
    assert_relative_eq!(p.score_matrix[1][1], 0.123866151328, epsilon = 1e-9);
    // The corner cell accumulates the whole "6+ : 6+" tail.
    assert_relative_eq!(p.score_matrix[6][6], 5.757783778873e-06, epsilon = 1e-12);

    let q = probs(1800.0, 1500.0);
    assert_relative_eq!(q.score_matrix[2][0], 0.132268967937, epsilon = 1e-9);
}

#[test]
fn score_matrix_is_consistent_with_outcome_probabilities() {
    // Summing the grid by region must reproduce 1/X/2 up to the tail cells,
    // whose diagonal mass is not separable; allow a tolerance of the corner
    // cell's size.
    let p = probs(1500.0, 1500.0);
    let mut ph = 0.0;
    let mut pd = 0.0;
    let mut pa = 0.0;
    for (h, row) in p.score_matrix.iter().enumerate() {
        for (a, v) in row.iter().enumerate() {
            if h > a {
                ph += v;
            } else if h == a {
                pd += v;
            } else {
                pa += v;
            }
        }
    }
    let tol = p.score_matrix[MAX_GOALS][MAX_GOALS] + 1e-9;
    assert_relative_eq!(ph, p.p_home_win, epsilon = tol);
    assert_relative_eq!(pd, p.p_draw, epsilon = tol);
    assert_relative_eq!(pa, p.p_away_win, epsilon = tol);
}

// ------------------------------------------------------------- ELO walk ----

/// 4 teams at ELO 1500; match order: 1v2 finished 2:1, 3v4 finished 0:0,
/// 2v3 still open. Expected values from the independent computation:
/// mod(2:1) = 8.853767324754, mod(0:0) = -1.146232675246.
fn walked_season() -> Season {
    Season {
        matches: vec![
            Match {
                team_home: 0,
                team_away: 1,
                goals_home: Some(2),
                goals_away: Some(1),
            },
            Match {
                team_home: 2,
                team_away: 3,
                goals_home: Some(0),
                goals_away: Some(0),
            },
            Match {
                team_home: 1,
                team_away: 2,
                goals_home: None,
                goals_away: None,
            },
        ],
        team_elos: vec![1500.0, 1500.0, 1500.0, 1500.0],
        number_teams: 4,
    }
}

fn walked_details() -> LeagueDetails {
    compute_league_details(
        &walked_season(),
        MOD_FACTOR,
        HOME_ADVANTAGE,
        TORE_SLOPE,
        TORE_INTERCEPT,
        MAX_GOALS,
    )
}

#[test]
fn played_matches_record_pre_elos_and_deltas_in_order() {
    let d = walked_details();
    assert_eq!(d.matches.len(), 3);

    let m1 = &d.matches[0];
    assert!(m1.played);
    assert_eq!((m1.team_home, m1.team_away), (0, 1));
    assert_relative_eq!(m1.elo_home_pre, 1500.0, epsilon = 1e-9);
    assert_relative_eq!(m1.elo_away_pre, 1500.0, epsilon = 1e-9);
    assert_relative_eq!(m1.elo_delta_home.unwrap(), 8.853767324754, epsilon = 1e-9);

    let m2 = &d.matches[1];
    assert!(m2.played);
    assert_relative_eq!(m2.elo_delta_home.unwrap(), -1.146232675246, epsilon = 1e-9);
}

#[test]
fn current_elos_reflect_all_played_matches() {
    let d = walked_details();
    let expected = [
        1508.853767324754,
        1491.146232675246,
        1498.853767324754,
        1501.146232675246,
    ];
    assert_eq!(d.current_elos.len(), 4);
    for (got, want) in d.current_elos.iter().zip(expected) {
        assert_relative_eq!(*got, want, epsilon = 1e-9);
    }
}

#[test]
fn elo_is_conserved_by_the_walk() {
    let d = walked_details();
    let total: f64 = d.current_elos.iter().sum();
    assert_relative_eq!(total, 4.0 * 1500.0, epsilon = 1e-9);
}

#[test]
fn unplayed_match_uses_final_elos_not_list_position() {
    // Match 3 (team2 home vs team3) must be priced off the ELO state after
    // ALL played matches — "ELO von heute" — even though later Nachholspiel
    // entries could sit anywhere in the list.
    let d = walked_details();
    let m3 = &d.matches[2];
    assert!(!m3.played);
    assert!(m3.elo_delta_home.is_none());
    assert!(m3.goals_home.is_none());
    assert_relative_eq!(m3.elo_home_pre, 1491.146232675246, epsilon = 1e-9);
    assert_relative_eq!(m3.elo_away_pre, 1498.853767324754, epsilon = 1e-9);
    assert_relative_eq!(m3.probabilities.lambda_home, 1.379497126032, epsilon = 1e-9);
    assert_relative_eq!(m3.probabilities.p_home_win, 0.39638004759, epsilon = 1e-9);
    assert_relative_eq!(m3.probabilities.p_draw, 0.260850730011, epsilon = 1e-9);
    assert_relative_eq!(m3.probabilities.p_away_win, 0.34276922240, epsilon = 1e-9);
}

#[test]
fn played_match_probabilities_are_ex_ante() {
    // The first played match must be priced off its pre-match ELO state
    // (here: the untouched season start), not the post-match state.
    let d = walked_details();
    let m1 = &d.matches[0];
    assert_relative_eq!(m1.probabilities.p_home_win, 0.402904706240, epsilon = 1e-9);
    assert_relative_eq!(m1.probabilities.p_draw, 0.260577313073, epsilon = 1e-9);
}

#[test]
fn live_scores_do_not_count_as_played() {
    // The R side sends goals only for finished matches (FT/AET/PEN); a live
    // match arrives with goals_home/away = None. A half-set pair (data
    // glitch) must also not shift ELO.
    let season = Season {
        matches: vec![Match {
            team_home: 0,
            team_away: 1,
            goals_home: Some(1),
            goals_away: None,
        }],
        team_elos: vec![1500.0, 1500.0],
        number_teams: 2,
    };
    let d = compute_league_details(
        &season,
        MOD_FACTOR,
        HOME_ADVANTAGE,
        TORE_SLOPE,
        TORE_INTERCEPT,
        MAX_GOALS,
    );
    assert!(!d.matches[0].played);
    assert_relative_eq!(d.current_elos[0], 1500.0, epsilon = 1e-9);
}
