use axum::{
    http::StatusCode,
    Json,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
pub struct HealthResponse {
    status: String,
    version: String,
}

pub async fn health_check() -> impl IntoResponse {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

#[derive(Deserialize)]
pub struct SimulateRequest {
    // To be implemented with actual request structure
}

#[derive(Serialize)]
pub struct SimulateResponse {
    // To be implemented with actual response structure
}

pub async fn simulate_league(
    Json(_payload): Json<SimulateRequest>,
) -> Result<Json<SimulateResponse>, StatusCode> {
    // To be implemented
    Err(StatusCode::NOT_IMPLEMENTED)
}