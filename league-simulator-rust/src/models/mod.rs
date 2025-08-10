use serde::{Deserialize, Serialize};

/// Result of an ELO calculation after a match
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EloResult {
    pub new_elo_home: f64,
    pub new_elo_away: f64,
    pub goals_home: i32,
    pub goals_away: i32,
    pub win_probability_home: f64,
}

/// Parameters for ELO calculation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EloParams {
    pub elo_home: f64,
    pub elo_away: f64,
    pub goals_home: i32,
    pub goals_away: i32,
    pub mod_factor: f64,
    pub home_advantage: f64,
}

/// Match result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Match {
    pub team_home: usize,
    pub team_away: usize,
    pub goals_home: Option<i32>,
    pub goals_away: Option<i32>,
}

/// Season schedule with matches
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Season {
    pub matches: Vec<Match>,
    pub team_elos: Vec<f64>,
    pub number_teams: usize,
}

/// League table entry for a team
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamStanding {
    pub team_id: usize,
    pub played: i32,
    pub won: i32,
    pub drawn: i32,
    pub lost: i32,
    pub goals_for: i32,
    pub goals_against: i32,
    pub goal_difference: i32,
    pub points: i32,
    pub position: usize,
}

/// Complete league table
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LeagueTable {
    pub standings: Vec<TeamStanding>,
}

/// Simulation parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationParams {
    pub mod_factor: f64,
    pub home_advantage: f64,
    pub iterations: usize,
    pub tore_slope: f64,
    pub tore_intercept: f64,
}

impl Default for SimulationParams {
    fn default() -> Self {
        Self {
            mod_factor: 20.0,
            home_advantage: 65.0,
            iterations: 10000,
            tore_slope: 0.0017854953143549,
            tore_intercept: 1.3218390804597700,
        }
    }
}

/// Result of Monte Carlo simulation - probability distribution of final positions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    /// Probability matrix: rows are teams, columns are positions
    /// probability[team_id][position] = probability of team finishing in that position
    pub probability_matrix: Vec<Vec<f64>>,
    pub team_names: Vec<String>,
}