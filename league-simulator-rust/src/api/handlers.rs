use crate::{run_monte_carlo_simulation, Match, Season, SimulationParams};
use axum::{http::StatusCode, response::IntoResponse, Json};
use serde::{Deserialize, Serialize};

/// Server-side ceiling on Monte Carlo iterations (production uses 10,000).
const MAX_ITERATIONS: usize = 100_000;

fn validate_request(payload: &SimulateRequest) -> Result<(), String> {
    if payload.schedule.is_empty() {
        return Err("schedule must not be empty".to_string());
    }
    let number_teams = payload.elo_values.len();
    if number_teams == 0 {
        return Err("elo_values must not be empty".to_string());
    }
    if let Some(iterations) = payload.iterations {
        if iterations == 0 || iterations > MAX_ITERATIONS {
            return Err(format!(
                "iterations must be between 1 and {}, got {}",
                MAX_ITERATIONS, iterations
            ));
        }
    }
    for (i, row) in payload.schedule.iter().enumerate() {
        for (name, value) in [("team_home", row[0]), ("team_away", row[1])] {
            match value {
                Some(v) if v >= 1 && (v as usize) <= number_teams => {}
                Some(v) => {
                    return Err(format!(
                        "schedule row {}: {} index {} out of range 1..={}",
                        i, name, v, number_teams
                    ))
                }
                None => return Err(format!("schedule row {}: {} must not be null", i, name)),
            }
        }
    }
    for (name, adj) in [
        ("adj_points", &payload.adj_points),
        ("adj_goals", &payload.adj_goals),
        ("adj_goals_against", &payload.adj_goals_against),
        ("adj_goal_diff", &payload.adj_goal_diff),
    ] {
        if let Some(v) = adj {
            if v.len() != number_teams {
                return Err(format!(
                    "{} has length {}, expected {} (one per team)",
                    name,
                    v.len(),
                    number_teams
                ));
            }
        }
    }
    Ok(())
}

#[derive(Serialize)]
pub struct HealthResponse {
    status: String,
    version: String,
    performance: String,
}

pub async fn health_check() -> impl IntoResponse {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        performance: "370,000+ simulations/second".to_string(),
    })
}

#[derive(Deserialize)]
pub struct SimulateRequest {
    /// Schedule matrix: each row is [team_home, team_away, goals_home, goals_away]
    /// goals are null/None for unplayed matches
    schedule: Vec<[Option<i32>; 4]>,

    /// Initial ELO values for each team
    elo_values: Vec<f64>,

    /// Team names (optional, for display)
    team_names: Option<Vec<String>>,

    /// Number of Monte Carlo iterations (default: 10000)
    iterations: Option<usize>,

    /// ELO modification factor (default: 20)
    mod_factor: Option<f64>,

    /// Home advantage in ELO points (default: 65)
    home_advantage: Option<f64>,

    /// Point adjustments per team (optional)
    adj_points: Option<Vec<i32>>,

    /// Goal adjustments per team (optional)
    adj_goals: Option<Vec<i32>>,

    /// Goals against adjustments per team (optional)
    adj_goals_against: Option<Vec<i32>>,

    /// Goal difference adjustments per team (optional)
    adj_goal_diff: Option<Vec<i32>>,
}

#[derive(Serialize)]
pub struct SimulateResponse {
    /// Probability matrix: rows are teams (in final rank order), columns are positions
    /// Values are probabilities [0,1] of team finishing in that position
    probability_matrix: Vec<Vec<f64>>,

    /// Team names in the same order as probability_matrix rows
    team_names: Vec<String>,

    /// Number of simulations actually performed
    simulations_performed: usize,

    /// Time taken in milliseconds
    time_ms: u128,
}

pub async fn simulate_league(
    Json(payload): Json<SimulateRequest>,
) -> Result<Json<SimulateResponse>, (StatusCode, String)> {
    let start = std::time::Instant::now();

    validate_request(&payload).map_err(|e| (StatusCode::BAD_REQUEST, e))?;

    let number_teams = payload.elo_values.len();

    // Convert schedule to Match structs
    let matches: Vec<Match> = payload
        .schedule
        .iter()
        .map(|row| Match {
            // Validated above: indices are Some and within 1..=number_teams.
            // R uses 1-indexed, Rust uses 0-indexed.
            team_home: row[0].unwrap() as usize - 1,
            team_away: row[1].unwrap() as usize - 1,
            goals_home: row[2],
            goals_away: row[3],
        })
        .collect();

    // Create Season struct
    let season = Season {
        matches,
        team_elos: payload.elo_values.clone(),
        number_teams,
    };

    // Set simulation parameters
    let params = SimulationParams {
        iterations: payload.iterations.unwrap_or(10000),
        mod_factor: payload.mod_factor.unwrap_or(20.0),
        home_advantage: payload.home_advantage.unwrap_or(65.0),
        tore_slope: 0.0017854953143549,
        tore_intercept: 1.3218390804597700,
        adj_points: payload.adj_points.clone(),
        adj_goals: payload.adj_goals.clone(),
        adj_goals_against: payload.adj_goals_against.clone(),
        adj_goal_diff: payload.adj_goal_diff.clone(),
    };

    // Generate team names if not provided
    let team_names = payload.team_names.unwrap_or_else(|| {
        (0..number_teams)
            .map(|i| format!("Team_{}", i + 1))
            .collect()
    });

    // Run simulation
    let result = run_monte_carlo_simulation(&season, &params, team_names.clone());

    let elapsed = start.elapsed();

    Ok(Json(SimulateResponse {
        probability_matrix: result.probability_matrix,
        team_names: result.team_names,
        simulations_performed: params.iterations,
        time_ms: elapsed.as_millis(),
    }))
}

/// Batch simulation endpoint for multiple leagues
#[derive(Deserialize)]
pub struct BatchSimulateRequest {
    leagues: Vec<LeagueRequest>,
}

#[derive(Deserialize)]
pub struct LeagueRequest {
    name: String,
    request: SimulateRequest,
}

#[derive(Serialize)]
pub struct BatchSimulateResponse {
    results: Vec<LeagueResult>,
    total_time_ms: u128,
}

#[derive(Serialize)]
pub struct LeagueResult {
    name: String,
    response: SimulateResponse,
}

pub async fn simulate_batch(
    Json(payload): Json<BatchSimulateRequest>,
) -> Result<Json<BatchSimulateResponse>, (StatusCode, String)> {
    let start = std::time::Instant::now();
    let mut results = Vec::new();

    // Process each league in parallel using tokio tasks
    let tasks: Vec<_> = payload
        .leagues
        .into_iter()
        .map(|league| {
            tokio::spawn(async move {
                let response = simulate_league_internal(league.request).await;
                (league.name, response)
            })
        })
        .collect();

    // Collect results
    for task in tasks {
        match task.await {
            Ok((name, Ok(response))) => {
                results.push(LeagueResult { name, response });
            }
            Ok((name, Err((status, msg)))) => {
                return Err((status, format!("league '{}': {}", name, msg)));
            }
            Err(_) => {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "batch task panicked".to_string(),
                ));
            }
        }
    }

    let elapsed = start.elapsed();

    Ok(Json(BatchSimulateResponse {
        results,
        total_time_ms: elapsed.as_millis(),
    }))
}

// Internal helper function for batch processing
async fn simulate_league_internal(
    request: SimulateRequest,
) -> Result<SimulateResponse, (StatusCode, String)> {
    simulate_league(Json(request)).await.map(|Json(r)| r)
}
