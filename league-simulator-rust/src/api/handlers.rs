use crate::{run_monte_carlo_simulation, Match, Season, SimulationParams};
use axum::{http::StatusCode, response::IntoResponse, Json};
use serde::{Deserialize, Serialize};

/// Server-side ceiling on Monte Carlo iterations (production uses 10,000).
const MAX_ITERATIONS: usize = 100_000;

/// Liest das ELO-Neutral-Flag fuer Spiel `i`.
///
/// Fehlt der Vektor, ist kein Spiel neutral -- das ist das Verhalten vor
/// Issue #157. Die Laengengleichheit ist vorher validiert; `unwrap_or(false)`
/// ist nur die defensive Untergrenze.
fn elo_neutral_flag(flags: &Option<Vec<bool>>, i: usize) -> bool {
    flags
        .as_ref()
        .and_then(|v| v.get(i))
        .copied()
        .unwrap_or(false)
}

/// Prueft, dass `elo_neutral` genau so lang ist wie `schedule`.
///
/// Ein zu kurzer oder zu langer Vektor waere eine stille Fehlzuordnung: Ab
/// der Abweichung traegt jedes Spiel das Flag eines anderen. Das faellt
/// niemandem auf -- deshalb ein harter 400er statt einer Auffuellung.
fn validate_elo_neutral(elo_neutral: &Option<Vec<bool>>, n_matches: usize) -> Result<(), String> {
    if let Some(flags) = elo_neutral {
        if flags.len() != n_matches {
            return Err(format!(
                "elo_neutral must have one entry per schedule row: got {}, expected {}",
                flags.len(),
                n_matches
            ));
        }
    }
    Ok(())
}

fn validate_request(payload: &SimulateRequest) -> Result<(), String> {
    if payload.schedule.is_empty() {
        return Err("schedule must not be empty".to_string());
    }
    let number_teams = payload.elo_values.len();
    if number_teams == 0 {
        return Err("elo_values must not be empty".to_string());
    }
    validate_elo_neutral(&payload.elo_neutral, payload.schedule.len())?;

    // group_of_team und relegation_places gehoeren zusammen. Eines allein ist
    // mehrdeutig und vermutlich ein Fehler beim Aufrufer.
    match (&payload.group_of_team, payload.relegation_places) {
        (Some(groups), Some(places)) => {
            if groups.len() != number_teams {
                return Err(format!(
                    "group_of_team must have one entry per team: got {}, expected {}",
                    groups.len(),
                    number_teams
                ));
            }
            if places == 0 || places > number_teams {
                return Err(format!(
                    "relegation_places must be between 1 and {}, got {}",
                    number_teams, places
                ));
            }
        }
        (None, None) => {}
        (Some(_), None) => {
            return Err("group_of_team requires relegation_places".to_string());
        }
        (None, Some(_)) => {
            return Err("relegation_places requires group_of_team".to_string());
        }
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

    /// Staffel-Index je Team, parallel zu `elo_values` (0-basiert). Nur
    /// zusammen mit `relegation_places` gueltig; loest die Auszaehlung der
    /// Absteiger je Staffel aus (Antwortfeld `relegation_group_counts`).
    group_of_team: Option<Vec<usize>>,

    /// Zahl der Abstiegsplaetze am Tabellenende.
    relegation_places: Option<usize>,

    /// Je Spiel: Ergebnis zaehlt fuer die Tabelle, bewegt aber den ELO-Walk
    /// nicht. Paralleler Vektor zu `schedule` (gleiche Laenge und
    /// Reihenfolge); fehlt das Feld, verhaelt sich alles wie bisher.
    /// Gedacht fuer am gruenen Tisch gewertete Spiele (Issue #157).
    elo_neutral: Option<Vec<bool>>,

    /// Initial ELO values for each team
    elo_values: Vec<f64>,

    /// Team names (optional, for display)
    team_names: Option<Vec<String>>,

    /// Number of Monte Carlo iterations (default: 10000)
    iterations: Option<usize>,

    /// ELO modification factor (default: 20)
    mod_factor: Option<f64>,

    /// Home advantage in ELO points (default: 40)
    home_advantage: Option<f64>,

    /// Goal-model slope: goals per ELO point (default: 0.0017854953143549).
    /// Only leagues that never exchange teams may differ here -- ELO is the
    /// only thing a team carries across a league boundary, so a shared goal
    /// model is what makes an ELO value mean the same on both sides.
    tore_slope: Option<f64>,

    /// Goal-model intercept: half the expected goals per match
    /// (default: 1.3218390804597700). See `tore_slope`.
    tore_intercept: Option<f64>,

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

    /// Absteiger je Staffel: `[staffel][anzahl]` = Zahl der Iterationen, in
    /// denen genau `anzahl` Teams dieser Staffel abgestiegen sind. Fehlt,
    /// wenn keine Staffel-Zuordnung uebergeben wurde.
    #[serde(skip_serializing_if = "Option::is_none")]
    relegation_group_counts: Option<Vec<Vec<usize>>>,

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
        .enumerate()
        .map(|(i, row)| Match {
            // Validated above: indices are Some and within 1..=number_teams.
            // R uses 1-indexed, Rust uses 0-indexed.
            team_home: row[0].unwrap() as usize - 1,
            team_away: row[1].unwrap() as usize - 1,
            goals_home: row[2],
            goals_away: row[3],
            elo_neutral: elo_neutral_flag(&payload.elo_neutral, i),
        })
        .collect();

    // Create Season struct
    let season = Season {
        matches,
        team_elos: payload.elo_values.clone(),
        number_teams,
    };

    // Set simulation parameters
    // Zeilenzahl der Ergebnismatrix: hoechster vorkommender Index + 1.
    // Staffeln, die in DIESER Liga kein Team stellen, behalten ihre Zeile,
    // solange eine hoeher nummerierte besetzt ist -- eine leere Zeile
    // zwischendrin summiert sich schlicht auf null Absteiger.
    // Zur Grenze dieses Verfahrens siehe SimulationParams::group_count.
    let group_count = payload
        .group_of_team
        .as_ref()
        .map(|g| g.iter().max().map_or(0, |m| m + 1));

    let params = SimulationParams {
        group_of_team: payload.group_of_team.clone(),
        relegation_places: payload.relegation_places,
        group_count,
        iterations: payload.iterations.unwrap_or(10000),
        mod_factor: payload.mod_factor.unwrap_or(20.0),
        home_advantage: payload.home_advantage.unwrap_or(40.0),
        tore_slope: payload.tore_slope.unwrap_or(0.0017854953143549),
        tore_intercept: payload.tore_intercept.unwrap_or(1.3218390804597700),
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
        relegation_group_counts: result.relegation_group_counts.clone(),
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

/// Deterministic per-match details (ADR 0002): ELO walk over played matches,
/// closed-form Poisson probabilities and scoreline grid per match. No Monte
/// Carlo, no randomness — same input, same output.
#[derive(Deserialize)]
pub struct LeagueDetailsRequest {
    /// Schedule matrix, identical to `/simulate`: rows of
    /// [team_home, team_away, goals_home, goals_away], goals null if open.
    schedule: Vec<[Option<i32>; 4]>,

    /// Je Spiel: Ergebnis zaehlt fuer die Tabelle, bewegt aber den ELO-Walk
    /// nicht. Paralleler Vektor zu `schedule` (gleiche Laenge und
    /// Reihenfolge); fehlt das Feld, verhaelt sich alles wie bisher.
    /// Gedacht fuer am gruenen Tisch gewertete Spiele (Issue #157).
    elo_neutral: Option<Vec<bool>>,

    /// Season-start ELO per team.
    elo_values: Vec<f64>,

    /// Team names (optional, echoed back).
    team_names: Option<Vec<String>>,

    /// ELO modification factor (default: 20).
    mod_factor: Option<f64>,

    /// Home advantage in ELO points (default: 40).
    home_advantage: Option<f64>,

    /// Goal-model slope (default: 0.0017854953143549). Must match the value
    /// used by `/simulate` for the same league, otherwise the heatmap and the
    /// 1/X/2 display would silently diverge.
    tore_slope: Option<f64>,

    /// Goal-model intercept (default: 1.3218390804597700). See `tore_slope`.
    tore_intercept: Option<f64>,

    /// Scoreline grid size: the grid is (max_goals+1)² with the tail mass
    /// accumulated in the last row/column (default: 6 → 7x7, "6+").
    max_goals: Option<usize>,
}

#[derive(Serialize)]
pub struct MatchDetailResponse {
    /// Position in the request schedule (0-based).
    index: usize,
    /// 1-based team indices, mirroring the request encoding.
    team_home: usize,
    team_away: usize,
    played: bool,
    goals_home: Option<i32>,
    goals_away: Option<i32>,
    elo_home_pre: f64,
    elo_away_pre: f64,
    /// Home team's ELO shift for played matches (away = negative of it).
    elo_delta_home: Option<f64>,
    lambda_home: f64,
    lambda_away: f64,
    p_home_win: f64,
    p_draw: f64,
    p_away_win: f64,
    score_matrix: Vec<Vec<f64>>,
}

#[derive(Serialize)]
pub struct LeagueDetailsResponse {
    matches: Vec<MatchDetailResponse>,
    /// ELO per team after all played matches, in request team order.
    current_elos: Vec<f64>,
    team_names: Vec<String>,
}

fn validate_league_details_request(payload: &LeagueDetailsRequest) -> Result<(), String> {
    if payload.schedule.is_empty() {
        return Err("schedule must not be empty".to_string());
    }
    let number_teams = payload.elo_values.len();
    if number_teams == 0 {
        return Err("elo_values must not be empty".to_string());
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
    validate_elo_neutral(&payload.elo_neutral, payload.schedule.len())?;
    Ok(())
}

pub async fn league_details(
    Json(payload): Json<LeagueDetailsRequest>,
) -> Result<Json<LeagueDetailsResponse>, (StatusCode, String)> {
    validate_league_details_request(&payload).map_err(|e| (StatusCode::BAD_REQUEST, e))?;

    let number_teams = payload.elo_values.len();

    let matches: Vec<Match> = payload
        .schedule
        .iter()
        .enumerate()
        .map(|(i, row)| Match {
            // Validated above; request is 1-indexed, internals 0-indexed.
            team_home: row[0].unwrap() as usize - 1,
            team_away: row[1].unwrap() as usize - 1,
            goals_home: row[2],
            goals_away: row[3],
            elo_neutral: elo_neutral_flag(&payload.elo_neutral, i),
        })
        .collect();

    let season = Season {
        matches,
        team_elos: payload.elo_values.clone(),
        number_teams,
    };

    let details = crate::league_details::compute_league_details(
        &season,
        payload.mod_factor.unwrap_or(20.0),
        payload.home_advantage.unwrap_or(40.0),
        payload.tore_slope.unwrap_or(0.0017854953143549),
        payload.tore_intercept.unwrap_or(1.3218390804597700),
        payload.max_goals.unwrap_or(6),
    );

    let team_names = payload.team_names.unwrap_or_else(|| {
        (0..number_teams)
            .map(|i| format!("Team_{}", i + 1))
            .collect()
    });

    let matches = details
        .matches
        .into_iter()
        .map(|m| MatchDetailResponse {
            index: m.index,
            team_home: m.team_home + 1,
            team_away: m.team_away + 1,
            played: m.played,
            goals_home: m.goals_home,
            goals_away: m.goals_away,
            elo_home_pre: m.elo_home_pre,
            elo_away_pre: m.elo_away_pre,
            elo_delta_home: m.elo_delta_home,
            lambda_home: m.probabilities.lambda_home,
            lambda_away: m.probabilities.lambda_away,
            p_home_win: m.probabilities.p_home_win,
            p_draw: m.probabilities.p_draw,
            p_away_win: m.probabilities.p_away_win,
            score_matrix: m.probabilities.score_matrix,
        })
        .collect();

    Ok(Json(LeagueDetailsResponse {
        matches,
        current_elos: details.current_elos,
        team_names,
    }))
}

/// Obergrenze fuer `max_goals`. Die Antwort waechst quadratisch: 100 bedeutet
/// schon 101x101 Zellen. Alles darueber ist kein Anwendungsfall, sondern ein
/// Fehler beim Aufrufer.
const MAX_GOALS_LIMIT: usize = 100;

/// Ein einzelnes virtuelles Spiel (ADR 0002): zwei ELO-Werte rein, die
/// Tor-Raten und die Ergebnisverteilung raus.
///
/// Gedacht fuer Paarungen, die in keinem Ligaspielplan stehen -- etwa die
/// Aufstiegsspiele Nord gegen Bayern (Par. 55b DFB-SpO). R soll die Formel
/// ELO -> lambda nicht nachbauen, also liefert sie der Server.
#[derive(Deserialize)]
pub struct MatchPreviewRequest {
    /// ELO des Heimteams.
    elo_home: f64,

    /// ELO des Gastteams.
    elo_away: f64,

    /// Heimvorteil in ELO-Punkten (Default: 40). Fuer ein Spiel auf
    /// neutralem Platz 0 uebergeben.
    home_advantage: Option<f64>,

    /// Steigung des Tormodells (Default: 0.0017854953143549). Siehe
    /// `LeagueDetailsRequest::tore_slope`.
    tore_slope: Option<f64>,

    /// Achsenabschnitt des Tormodells (Default: 1.3218390804597700).
    tore_intercept: Option<f64>,

    /// Kantenlaenge des Ergebnisgitters minus eins (Default: 6 -> 7x7);
    /// letzte Zeile/Spalte tragen die Schwanzmasse.
    max_goals: Option<usize>,
}

#[derive(Serialize)]
pub struct MatchPreviewResponse {
    lambda_home: f64,
    lambda_away: f64,
    p_home_win: f64,
    p_draw: f64,
    p_away_win: f64,
    score_matrix: Vec<Vec<f64>>,
}

fn validate_match_preview_request(payload: &MatchPreviewRequest) -> Result<(), String> {
    if let Some(max_goals) = payload.max_goals {
        if max_goals == 0 || max_goals > MAX_GOALS_LIMIT {
            return Err(format!(
                "max_goals must be between 1 and {}, got {}",
                MAX_GOALS_LIMIT, max_goals
            ));
        }
    }
    Ok(())
}

pub async fn match_preview(
    Json(payload): Json<MatchPreviewRequest>,
) -> Result<Json<MatchPreviewResponse>, (StatusCode, String)> {
    validate_match_preview_request(&payload).map_err(|e| (StatusCode::BAD_REQUEST, e))?;

    // Kein zweiter Rechenweg: dieselbe Funktion, die /league-details je Spiel
    // aufruft (ADR 0002). Weichen die Defaults hier ab, antworten beide
    // Endpunkte fuer dasselbe Spiel verschieden -- deshalb stehen sie
    // wortgleich wie in `league_details`.
    let probabilities = crate::league_details::match_probabilities(
        payload.elo_home,
        payload.elo_away,
        payload.home_advantage.unwrap_or(40.0),
        payload.tore_slope.unwrap_or(0.0017854953143549),
        payload.tore_intercept.unwrap_or(1.3218390804597700),
        payload.max_goals.unwrap_or(6),
    );

    Ok(Json(MatchPreviewResponse {
        lambda_home: probabilities.lambda_home,
        lambda_away: probabilities.lambda_away,
        p_home_win: probabilities.p_home_win,
        p_draw: probabilities.p_draw,
        p_away_win: probabilities.p_away_win,
        score_matrix: probabilities.score_matrix,
    }))
}
