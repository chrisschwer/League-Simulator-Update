// REST API module for R/Shiny integration
// Provides high-performance simulation endpoints

pub mod handlers;

#[cfg(test)]
mod tests;

use axum::{
    extract::DefaultBodyLimit,
    routing::{get, post},
    Router,
};

pub fn create_router() -> Router {
    Router::new()
        .route("/health", get(handlers::health_check))
        .route("/simulate", post(handlers::simulate_league))
        .route("/simulate/batch", post(handlers::simulate_batch))
        // Payloads are ~306 fixture rows (<100 KB); 2 MB is generous headroom.
        .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
}
