// REST API module for R/Shiny integration
// Provides high-performance simulation endpoints

pub mod handlers;

#[cfg(test)]
mod tests;

use axum::{
    http::Method,
    routing::{get, post},
    Router,
};
use tower_http::cors::{Any, CorsLayer};

pub fn create_router() -> Router {
    // Configure CORS for R client access
    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST])
        .allow_origin(Any)
        .allow_headers(Any);

    Router::new()
        .route("/health", get(handlers::health_check))
        .route("/simulate", post(handlers::simulate_league))
        .route("/simulate/batch", post(handlers::simulate_batch))
        .layer(cors)
}
