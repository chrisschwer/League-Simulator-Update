# Integrated League Simulator with Rust Engine
# Combines high-performance Rust simulation with R orchestration

# Stage 1: Build Rust binary
FROM rust:1.81-alpine AS rust-builder

RUN apk add --no-cache musl-dev

WORKDIR /build

# Copy Rust source
COPY league-simulator-rust/Cargo.toml .
COPY league-simulator-rust/src/ ./src/
COPY league-simulator-rust/test_data/ ./test_data/

# Build optimized binary
RUN cargo build --release
RUN strip target/release/league-simulator-rust

# Stage 2: Build complete application  
FROM rocker/r-ver:4.3.1

# Install system dependencies and curl for healthcheck
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    curl \
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
    core_pkgs <- c('Rcpp', 'httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr'); \
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
    already_installed <- c('Rcpp', 'httr', 'jsonlite', 'dplyr', 'tidyr', 'magrittr', 'htmltools', 'httpuv', 'promises', 'shiny', 'rsconnect'); \
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

# Copy Rust binary from builder
COPY --from=rust-builder /build/target/release/league-simulator-rust /usr/local/bin/league-simulator-rust

# Create application directory structure
WORKDIR /app
RUN mkdir -p /app/RCode /app/ShinyApp/data

# Copy R code and data
COPY RCode/ ./RCode/
COPY ShinyApp/ ./ShinyApp/

# Compile C++ code (fallback when Rust unavailable)
RUN cd /app/RCode && \
    R -e "Rcpp::sourceCpp('SpielNichtSimulieren.cpp')" || \
    echo "Warning: C++ compilation failed, will rely on Rust engine"

# Copy robust startup script
COPY docker-integrated-start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Environment variables
ENV RUST_API_URL=http://localhost:8080
ENV SEASON=2025

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the integrated application
CMD ["/app/start.sh"]