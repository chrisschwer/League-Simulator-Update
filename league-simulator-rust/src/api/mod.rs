// REST API module - to be implemented
// This will provide HTTP endpoints for the R code to call

pub mod handlers;

use axum::{
    Router,
    routing::{get, post},
};

pub fn create_router() -> Router {
    Router::new()
        .route("/health", get(handlers::health_check))
        .route("/simulate", post(handlers::simulate_league))
}