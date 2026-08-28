//! HTTP-API handler tests.
//!
//! These tests exercise the `axum::Router` returned by `create_router` using
//! `tower::ServiceExt::oneshot`, so no real port is opened. They pin the
//! wire-format contract that the R-side scheduler depends on, and they
//! document the validation paths in `simulate_league` (empty schedule, empty
//! elo_values).

use crate::api::create_router;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;

/// Send `req` through the router and return (status, body).
///
/// Success responses are JSON and are parsed as such. Error responses (e.g.
/// validation failures) are plain text — `(StatusCode, String)` rejections
/// render as a text body, not JSON — so those are wrapped as a JSON string
/// instead of failing the parse.
async fn send(req: Request<Body>) -> (StatusCode, Value) {
    let response = create_router()
        .oneshot(req)
        .await
        .expect("router service should not fail");

    let status = response.status();
    let bytes = response
        .into_body()
        .collect()
        .await
        .expect("body collect")
        .to_bytes();
    let body: Value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)
            .unwrap_or_else(|_| Value::String(String::from_utf8_lossy(&bytes).into_owned()))
    };

    (status, body)
}

fn post_simulate_json(payload: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/simulate")
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap()
}

/// A minimal valid simulate request: 2 teams, 1 played match plus 1 to
/// simulate, low iteration count to keep tests fast.
fn minimal_valid_simulate_payload() -> Value {
    json!({
        "schedule": [
            [1, 2, 1, 0],          // played match
            [2, 1, null, null]     // match to simulate
        ],
        "elo_values": [1500.0, 1500.0],
        "iterations": 50
    })
}

#[tokio::test]
async fn health_returns_ok_with_status_version_and_performance_fields() {
    let req = Request::builder()
        .method("GET")
        .uri("/health")
        .body(Body::empty())
        .unwrap();

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");
    assert!(
        body["version"].is_string(),
        "version field must be present and a string, got: {body}"
    );
    assert!(
        body["performance"].is_string(),
        "performance field must be present and a string, got: {body}"
    );
}

#[tokio::test]
async fn simulate_returns_400_when_schedule_is_empty() {
    let req = post_simulate_json(json!({
        "schedule": [],
        "elo_values": [1500.0, 1500.0],
        "iterations": 10
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_returns_400_when_elo_values_is_empty() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, 1, 0]],
        "elo_values": [],
        "iterations": 10
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_happy_path_returns_probability_matrix_with_expected_shape() {
    let req = post_simulate_json(minimal_valid_simulate_payload());

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);

    let matrix = body["probability_matrix"]
        .as_array()
        .expect("probability_matrix must be a JSON array");
    assert_eq!(matrix.len(), 2, "matrix should have one row per team");
    for row in matrix {
        let cols = row.as_array().expect("each row must be an array");
        assert_eq!(
            cols.len(),
            2,
            "each row should have one column per position"
        );
        let row_sum: f64 = cols.iter().map(|v| v.as_f64().unwrap()).sum();
        assert!(
            (row_sum - 1.0).abs() < 1e-9,
            "row probabilities must sum to 1, got {row_sum}"
        );
    }

    let names = body["team_names"]
        .as_array()
        .expect("team_names must be a JSON array");
    assert_eq!(names.len(), 2);

    assert_eq!(
        body["simulations_performed"].as_u64().unwrap(),
        50,
        "simulations_performed should reflect the requested iterations"
    );
    assert!(
        body["time_ms"].is_number(),
        "time_ms must be a number, got: {body}"
    );
}

#[tokio::test]
async fn simulate_uses_caller_supplied_team_names_in_response() {
    let mut payload = minimal_valid_simulate_payload();
    payload["team_names"] = json!(["Foo FC", "Bar United"]);

    let req = post_simulate_json(payload);
    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    let names: Vec<String> = body["team_names"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    assert!(
        names.contains(&"Foo FC".to_string()),
        "response team_names must contain caller-supplied 'Foo FC', got {names:?}"
    );
    assert!(
        names.contains(&"Bar United".to_string()),
        "response team_names must contain caller-supplied 'Bar United', got {names:?}"
    );
}

#[tokio::test]
async fn simulate_defaults_iterations_to_10000_when_not_provided() {
    // Note: this is the slow test (10k iterations) — kept minimal (2 teams,
    // 2-match schedule) so it still completes well under a second on dev
    // hardware.
    let req = post_simulate_json(json!({
        "schedule": [
            [1, 2, 1, 0],
            [2, 1, null, null]
        ],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["simulations_performed"].as_u64().unwrap(),
        10_000,
        "default iterations should be 10000 when caller omits the field"
    );
}

#[tokio::test]
async fn simulate_rejects_team_index_zero() {
    // team index 0 previously underflowed to usize::MAX and aborted the process
    let req = post_simulate_json(json!({
        "schedule": [[0, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_null_team_index() {
    let req = post_simulate_json(json!({
        "schedule": [[null, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_out_of_range_team_index() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 3, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_excessive_iterations() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "iterations": 100_000_000
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_mismatched_adjustment_length() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "adj_points": [0, 0, 0]
    }));

    let (status, _body) = send(req).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ======================================================================
// POST /league-details — deterministic per-match details (ADR 0002).
//
// These tests pin the wire contract the R-side renderer will parse
// (parse_league_details_response in RCode/league_details.R). Expected
// numbers come from the same independent computation as
// league_details/tests.rs.
// ======================================================================

fn post_league_details_json(payload: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/league-details")
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap()
}

/// 4 teams at 1500; 1v2 finished 2:1, 3v4 finished 0:0, 2v3 open.
fn minimal_league_details_payload() -> Value {
    json!({
        "schedule": [
            [1, 2, 2, 1],
            [3, 4, 0, 0],
            [2, 3, null, null]
        ],
        "elo_values": [1500.0, 1500.0, 1500.0, 1500.0],
        "team_names": ["AAA", "BBB", "CCC", "DDD"]
    })
}

#[tokio::test]
async fn league_details_returns_wire_contract() {
    let (status, body) = send(post_league_details_json(minimal_league_details_payload())).await;

    assert_eq!(status, StatusCode::OK);

    // Top level: matches, current_elos, team_names.
    let matches = body["matches"].as_array().expect("matches array");
    assert_eq!(matches.len(), 3);
    assert_eq!(body["team_names"], json!(["AAA", "BBB", "CCC", "DDD"]));

    let elos = body["current_elos"].as_array().expect("current_elos array");
    assert_eq!(elos.len(), 4);
    assert!((elos[0].as_f64().unwrap() - 1508.150675388313).abs() < 1e-6);

    // Played match: 1-based team indices (like the request), flat
    // probability fields, ELO state and delta.
    let m1 = &matches[0];
    assert_eq!(m1["index"], json!(0));
    assert_eq!(m1["team_home"], json!(1));
    assert_eq!(m1["team_away"], json!(2));
    assert_eq!(m1["played"], json!(true));
    assert_eq!(m1["goals_home"], json!(2));
    assert_eq!(m1["goals_away"], json!(1));
    assert!((m1["elo_home_pre"].as_f64().unwrap() - 1500.0).abs() < 1e-9);
    assert!((m1["elo_delta_home"].as_f64().unwrap() - 8.150675388313).abs() < 1e-6);
    assert!((m1["p_home_win"].as_f64().unwrap() - 0.424217291957).abs() < 1e-6);
    assert!((m1["p_draw"].as_f64().unwrap() - 0.259291821451).abs() < 1e-6);
    assert!((m1["p_away_win"].as_f64().unwrap() - 0.316490886592).abs() < 1e-6);
    assert!(m1["lambda_home"].as_f64().is_some());
    assert!(m1["lambda_away"].as_f64().is_some());

    // Score matrix: default max_goals = 6 → 7x7, sums to ~1.
    let grid = m1["score_matrix"].as_array().expect("score_matrix");
    assert_eq!(grid.len(), 7);
    assert_eq!(grid[0].as_array().unwrap().len(), 7);
    let total: f64 = grid
        .iter()
        .flat_map(|row| row.as_array().unwrap())
        .map(|v| v.as_f64().unwrap())
        .sum();
    assert!((total - 1.0).abs() < 1e-9);

    // Unplayed match: no goals, null delta, priced off final ELOs.
    let m3 = &matches[2];
    assert_eq!(m3["played"], json!(false));
    assert!(m3["goals_home"].is_null());
    assert!(m3["elo_delta_home"].is_null());
    assert!((m3["elo_home_pre"].as_f64().unwrap() - 1491.849324611687).abs() < 1e-6);
    assert!((m3["p_home_win"].as_f64().unwrap() - 0.418825321481).abs() < 1e-6);
}

#[tokio::test]
async fn league_details_rejects_empty_schedule() {
    let (status, _body) = send(post_league_details_json(json!({
        "schedule": [],
        "elo_values": [1500.0, 1500.0]
    })))
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn league_details_rejects_out_of_range_team_index() {
    let (status, _body) = send(post_league_details_json(json!({
        "schedule": [[1, 5, null, null]],
        "elo_values": [1500.0, 1500.0]
    })))
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn league_details_respects_max_goals_parameter() {
    let mut payload = minimal_league_details_payload();
    payload["max_goals"] = json!(4);

    let (status, body) = send(post_league_details_json(payload)).await;

    assert_eq!(status, StatusCode::OK);
    let grid = body["matches"][0]["score_matrix"].as_array().unwrap();
    assert_eq!(grid.len(), 5);
}
