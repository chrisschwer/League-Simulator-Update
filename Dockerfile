# Integrated League Simulator with Rust Engine
# Stage 1: Rust binary | Stage 2: R library (binary packages) | Stage 3: slim runtime

# R-Pakete kommen als Linux-Binaerpakete aus einem festen Snapshot des Posit
# Package Manager (P3M), nicht als Quellpakete von cloud.r-project.org.
# - Binaer: Ein Kaltbau (z. B. nach neuem Digest von rocker/r-ver, 17.10.2026)
#   kompiliert nichts und dauert Sekunden statt vieler Minuten.
# - Fester Snapshot: gleiche Paketversionen bei jedem Bau, auch ohne Cache.
#   Der erste Snapshot (12.10.2026) lieferte fuer alle Laufzeitpakete exakt
#   die Versionen des Images 8c1f35d (letzter gruener main-Build am
#   13.10.2026). Angehoben wird per PR: monatlich automatisch durch
#   .github/workflows/p3m-snapshot.yml, dessen CI ohne Cache baut.
#   Das Datum nur in der ARG-Zeile unten pflegen, der Workflow ersetzt dort.
# URL-Form /cran/__linux__/<ubuntu-codename>/<datum>: rocker/r-ver:4.6.1 ist
# Ubuntu 24.04 "noble". Binaerpakete liefert P3M nur bei passendem
# HTTPUserAgent; den setzt rocker in Rprofile.site, der Bau prueft das.
ARG P3M_SNAPSHOT=2026-10-12

# ---- Stage 1: Build Rust binary ----
FROM rust:1.99-alpine AS rust-builder

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

# ---- Stage 2: Build R library (binary packages from P3M) ----
FROM rocker/r-ver:4.6.1 AS r-builder

# Keine -dev-Bibliotheken und kein build-essential mehr: Aus P3M kommen
# Binaerpakete, kompiliert wird nichts. Faellt ein Paket doch auf eine
# Quellversion zurueck und braucht Systemheader, scheitert der Bau laut
# (Pruefung unten) statt still.
ARG P3M_SNAPSHOT
ENV CRAN=https://p3m.dev/cran/__linux__/noble/${P3M_SNAPSHOT}
RUN grep -q HTTPUserAgent /usr/local/lib/R/etc/Rprofile.site \
    && echo "options(repos = c(CRAN = '${CRAN}'))" >> /usr/local/lib/R/etc/Rprofile.site

# packagelist.txt mit den Standard-Abhaengigkeiten (Depends, Imports,
# LinkingTo), ohne Suggests. Test-Pakete installiert die CI zur Testzeit aus
# test_packagelist.txt (scripts/ci/testthat_ci.R), nicht das Produktionsimage.
COPY packagelist.txt /tmp/
RUN R --slave --no-restore -e " \
    stopifnot(identical(getOption('repos')[['CRAN']], Sys.getenv('CRAN'))); \
    pkgs <- readLines('/tmp/packagelist.txt'); \
    pkgs <- trimws(pkgs[!grepl('^#|^[[:space:]]*$', pkgs)]); \
    install.packages(pkgs, Ncpus = parallel::detectCores()); \
    ok <- vapply(pkgs, requireNamespace, logical(1), quietly = TRUE); \
    if (!all(ok)) stop('Pakete nicht installierbar: ', paste(pkgs[!ok], collapse = ', '))"

# ---- Stage 3: Runtime (no compilers, non-root) ----
FROM rocker/r-ver:4.6.1

# Derselbe P3M-Snapshot wie im Build-Stage, damit Nachinstallationen im Image
# (Test-Pakete der CI, scripts/ci/testthat_ci.R) dieselben Binaerpakete ziehen.
ARG P3M_SNAPSHOT
ENV CRAN=https://p3m.dev/cran/__linux__/noble/${P3M_SNAPSHOT}
RUN grep -q HTTPUserAgent /usr/local/lib/R/etc/Rprofile.site \
    && echo "options(repos = c(CRAN = '${CRAN}'))" >> /usr/local/lib/R/etc/Rprofile.site

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
# ShinyApp/public is the static-site output and is mounted as a named volume in
# production. Create it here, before chown, so Docker seeds a fresh volume with
# appuser ownership instead of root.
RUN mkdir -p /app/RCode /app/ShinyApp/data /app/ShinyApp/public
RUN touch /app/.here

COPY RCode/ ./RCode/
COPY docker-start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Run as non-root; scheduler writes ShinyApp/data and ShinyApp/public
RUN useradd --system --create-home --uid 1001 appuser \
    && chown -R appuser:appuser /app
USER appuser

ENV RUST_API_URL=http://localhost:8080
ENV SEASON=2026

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/start.sh"]
