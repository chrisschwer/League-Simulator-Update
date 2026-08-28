//! Deterministic per-match details for the static site (ADR 0002).
//!
//! No Monte Carlo here: the ELO walk over played matches and the closed-form
//! Poisson scoreline grid are exact. `/simulate` stays untouched; this module
//! feeds the new `/league-details` endpoint.
//!
//! Semantics (pinned by `tests.rs`):
//! - A match is *played* iff both goals are present.
//! - Played matches are walked in list order; each records the ELO state just
//!   before it (`elo_home_pre`/`elo_away_pre`) and its ELO shift
//!   (`elo_delta_home`, with the away shift being its negative).
//! - Unplayed matches carry probabilities computed from the *final* ELO state
//!   after all played matches ("ELO von heute"), not from their list position.
//! - `score_matrix` is a (max_goals+1)² grid; the last row/column accumulate
//!   the tail mass (e.g. "6+" goals).

use crate::elo::calculate_elo_change;
use crate::models::{EloParams, Season};

/// Accumulation bound for the Poisson sums. Production lambdas stay below ~5,
/// where the tail beyond 30 goals is far under 1e-12.
const POISSON_ACCUMULATION_MAX: usize = 30;

/// Closed-form outcome probabilities for a single match.
#[derive(Debug, Clone)]
pub struct MatchProbabilities {
    pub lambda_home: f64,
    pub lambda_away: f64,
    pub p_home_win: f64,
    pub p_draw: f64,
    pub p_away_win: f64,
    /// (max_goals+1) x (max_goals+1); last row/column hold the tail mass.
    pub score_matrix: Vec<Vec<f64>>,
}

/// One schedule entry, enriched with ELO state and probabilities.
#[derive(Debug, Clone)]
pub struct MatchDetail {
    /// Position in the request schedule (0-based).
    pub index: usize,
    /// 0-based team indices, as in `crate::models::Match`.
    pub team_home: usize,
    pub team_away: usize,
    pub played: bool,
    pub goals_home: Option<i32>,
    pub goals_away: Option<i32>,
    pub elo_home_pre: f64,
    pub elo_away_pre: f64,
    /// ELO shift of the home team for played matches (away = negative of it).
    pub elo_delta_home: Option<f64>,
    pub probabilities: MatchProbabilities,
}

#[derive(Debug, Clone)]
pub struct LeagueDetails {
    pub matches: Vec<MatchDetail>,
    /// ELO per team after all played matches, in request team order.
    pub current_elos: Vec<f64>,
}

/// Poisson pmf for k = 0..=POISSON_ACCUMULATION_MAX, computed iteratively.
fn poisson_pmf(lambda: f64) -> Vec<f64> {
    let mut pmf = Vec::with_capacity(POISSON_ACCUMULATION_MAX + 1);
    let mut p = (-lambda).exp();
    pmf.push(p);
    for k in 1..=POISSON_ACCUMULATION_MAX {
        p *= lambda / k as f64;
        pmf.push(p);
    }
    pmf
}

/// Exact 1/X/2 probabilities and scoreline grid from the Poisson goal model.
pub fn match_probabilities(
    elo_home: f64,
    elo_away: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    max_goals: usize,
) -> MatchProbabilities {
    // Same goal model as simulate_match (simulation/match_sim.rs).
    let elo_delta = elo_home + home_advantage - elo_away;
    let lambda_home = (elo_delta * tore_slope + tore_intercept).max(0.001);
    let lambda_away = ((-elo_delta) * tore_slope + tore_intercept).max(0.001);

    let pmf_home = poisson_pmf(lambda_home);
    let pmf_away = poisson_pmf(lambda_away);

    let mut p_home_win = 0.0;
    let mut p_draw = 0.0;
    let mut p_away_win = 0.0;
    let mut score_matrix = vec![vec![0.0; max_goals + 1]; max_goals + 1];

    for (h, ph) in pmf_home.iter().enumerate() {
        for (a, pa) in pmf_away.iter().enumerate() {
            let p = ph * pa;
            match h.cmp(&a) {
                std::cmp::Ordering::Greater => p_home_win += p,
                std::cmp::Ordering::Equal => p_draw += p,
                std::cmp::Ordering::Less => p_away_win += p,
            }
            score_matrix[h.min(max_goals)][a.min(max_goals)] += p;
        }
    }

    MatchProbabilities {
        lambda_home,
        lambda_away,
        p_home_win,
        p_draw,
        p_away_win,
        score_matrix,
    }
}

/// Deterministic ELO walk + per-match details for a whole season schedule.
pub fn compute_league_details(
    season: &Season,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    max_goals: usize,
) -> LeagueDetails {
    let mut elos = season.team_elos.clone();

    // Pass 1: walk the played matches in list order, recording each match's
    // pre-match ELO state and the home team's shift.
    let mut walk: Vec<Option<(f64, f64, f64)>> = Vec::with_capacity(season.matches.len());
    for m in &season.matches {
        match (m.goals_home, m.goals_away) {
            (Some(goals_home), Some(goals_away)) => {
                let pre_home = elos[m.team_home];
                let pre_away = elos[m.team_away];
                let result = calculate_elo_change(&EloParams {
                    elo_home: pre_home,
                    elo_away: pre_away,
                    goals_home,
                    goals_away,
                    mod_factor,
                    home_advantage,
                });
                elos[m.team_home] = result.new_elo_home;
                elos[m.team_away] = result.new_elo_away;
                walk.push(Some((pre_home, pre_away, result.new_elo_home - pre_home)));
            }
            _ => walk.push(None),
        }
    }

    // Pass 2: unplayed matches are priced off the final ELO state ("ELO von
    // heute"), not off their list position.
    let matches = season
        .matches
        .iter()
        .zip(walk)
        .enumerate()
        .map(|(index, (m, walked))| {
            let played = walked.is_some();
            let (elo_home_pre, elo_away_pre, elo_delta_home) = match walked {
                Some((pre_home, pre_away, delta)) => (pre_home, pre_away, Some(delta)),
                None => (elos[m.team_home], elos[m.team_away], None),
            };
            MatchDetail {
                index,
                team_home: m.team_home,
                team_away: m.team_away,
                played,
                goals_home: if played { m.goals_home } else { None },
                goals_away: if played { m.goals_away } else { None },
                elo_home_pre,
                elo_away_pre,
                elo_delta_home,
                probabilities: match_probabilities(
                    elo_home_pre,
                    elo_away_pre,
                    home_advantage,
                    tore_slope,
                    tore_intercept,
                    max_goals,
                ),
            }
        })
        .collect();

    LeagueDetails {
        matches,
        current_elos: elos,
    }
}

#[cfg(test)]
mod tests;
