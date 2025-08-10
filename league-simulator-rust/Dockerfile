# Multi-stage build for minimal production image
FROM rust:1.81-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev

WORKDIR /build

# Copy source files
COPY Cargo.toml .
COPY src/ ./src/

# Build release binary with optimizations (native architecture)
RUN cargo build --release
RUN strip target/release/league-simulator-rust

# Final minimal image
FROM alpine:3.19

# Install only runtime dependencies (if any needed)
RUN apk add --no-cache libgcc

# Copy binary from builder
COPY --from=builder /build/target/release/league-simulator-rust /usr/local/bin/league-simulator

# Create non-root user
RUN adduser -D -u 1000 simulator
USER simulator

# Expose REST API port
EXPOSE 8080

# Run the simulator
ENTRYPOINT ["/usr/local/bin/league-simulator"]