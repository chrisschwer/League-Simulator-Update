# Integrated League Simulator with Rust Engine
# Stage 1: Rust binary | Stage 2: R build (compilers) | Stage 3: slim runtime

# ---- Stage 1: Build Rust binary ----
FROM rust:1.97-alpine AS rust-builder

RUN apk add --no-cache musl-dev

WORKDIR /build

# Dependency layer: build with a dummy main so crate compilation is cached
# and re-runs only when Cargo.toml/Cargo.lock change, not on every code edit.
COPY league-simulator-rust/Cargo.toml league-simulator-rust/Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs \
    && cargo build --release \
    && rm -rf src target/release/league-simulator-rust* target/release/deps/league_simulator_rust*

COPY league-simulator-rust/src/ ./src/
COPY league-simulator-rust/test_data/ ./test_data/
RUN cargo build --release && strip target/release/league-simulator-rust

# ---- Stage 2: Build R library (needs compilers for source packages) ----
FROM rocker/r-ver:4.6.1 AS r-builder

RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    tzdata \
    build-essential \
    cmake \
    libuv1-dev \
    libfontconfig1-dev \
    libcairo2-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install critical R packages first (core dependencies)
RUN R --slave --no-restore -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    core_pkgs <- c('httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr'); \
    for (pkg in core_pkgs) { \
        if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
            install.packages(pkg, dependencies=TRUE); \
            if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
                stop(paste('Failed to install core package:', pkg)); \
            } \
        } \
    }"

# Install Shiny ecosystem packages with retries
RUN R --slave --no-restore -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    shiny_pkgs <- c('htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect'); \
    for (pkg in shiny_pkgs) { \
        cat('Installing Shiny package:', pkg, '\n'); \
        if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
            install.packages(pkg, dependencies=TRUE, type='source'); \
            if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
                cat('WARNING: Failed to install', pkg, '- will try binary\n'); \
                install.packages(pkg, dependencies=TRUE, type='binary'); \
                if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
                    stop(paste('Failed to install Shiny package:', pkg)); \
                } \
            } \
        } \
    }"

# Install remaining packages from packagelist.txt
COPY packagelist.txt /tmp/
RUN R --slave --no-restore -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    pkgs <- readLines('/tmp/packagelist.txt'); \
    pkgs <- pkgs[!grepl('^#|^[[:space:]]*$', pkgs)]; \
    already_installed <- c('httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr', 'htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect'); \
    remaining_pkgs <- pkgs[!pkgs %in% already_installed]; \
    for (pkg in remaining_pkgs) { \
        if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
            cat('Installing remaining package:', pkg, '\n'); \
            install.packages(pkg, dependencies=TRUE); \
            if (!require(pkg, character.only=TRUE, quietly=TRUE)) { \
                cat('WARNING: Failed to install', pkg, '\n'); \
            } \
        } \
    }"

# ---- Stage 3: Runtime (no compilers, non-root) ----
FROM rocker/r-ver:4.6.1

# Runtime (non -dev) libraries for the compiled R packages + curl for healthchecks.
# rocker/r-ver:4.6.1 is Ubuntu 24.04 (Noble); several libs use the 64-bit-time_t
# ("t64") package names introduced in Noble, verified via:
#   docker run --rm rocker/r-ver:4.6.1 bash -c "apt-get update -qq && apt-cache policy <pkg>"
RUN apt-get update && apt-get install -y \
    libcurl4t64 \
    libssl3t64 \
    libxml2 \
    curl \
    tzdata \
    libuv1t64 \
    libfontconfig1 \
    libcairo2 \
    libfreetype6 \
    libpng16-16t64 \
    libtiff6 \
    libjpeg-turbo8 \
    && rm -rf /var/lib/apt/lists/*

# Compiled R packages from the build stage
COPY --from=r-builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Rust binary
COPY --from=rust-builder /build/target/release/league-simulator-rust /usr/local/bin/league-simulator-rust

WORKDIR /app
RUN mkdir -p /app/RCode /app/ShinyApp/data
RUN touch /app/.here

COPY RCode/ ./RCode/
COPY ShinyApp/ ./ShinyApp/
COPY docker-start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Run as non-root; scheduler writes ShinyApp/data and rsconnect config in $HOME
RUN useradd --system --create-home --uid 1001 appuser \
    && chown -R appuser:appuser /app
USER appuser

ENV RUST_API_URL=http://localhost:8080
ENV SEASON=2025

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/start.sh"]
