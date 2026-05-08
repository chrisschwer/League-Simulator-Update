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

/// Send `req` through the router and return (status, parsed JSON body).
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
        serde_json::from_slice(&bytes).expect("response body should be valid JSON")
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
