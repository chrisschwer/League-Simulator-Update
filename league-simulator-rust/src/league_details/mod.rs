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

use crate::models::Season;

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

/// Exact 1/X/2 probabilities and scoreline grid from the Poisson goal model.
pub fn match_probabilities(
    _elo_home: f64,
    _elo_away: f64,
    _home_advantage: f64,
    _tore_slope: f64,
    _tore_intercept: f64,
    _max_goals: usize,
) -> MatchProbabilities {
    todo!("phase 2: implement after test review")
}

/// Deterministic ELO walk + per-match details for a whole season schedule.
pub fn compute_league_details(
    _season: &Season,
    _mod_factor: f64,
    _home_advantage: f64,
    _tore_slope: f64,
    _tore_intercept: f64,
    _max_goals: usize,
) -> LeagueDetails {
    todo!("phase 2: implement after test review")
}

#[cfg(test)]
mod tests;
