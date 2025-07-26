# renv Documentation

## Overview
renv is an R package that helps create reproducible environments by managing project-specific package libraries. It ensures that your R projects remain isolated, portable, and reproducible across different machines and over time.

## Core Concepts

### Project Library
- Each project gets its own private package library
- Packages installed in one project don't affect others
- Located in `renv/library/R-{version}/{platform}`

### Lockfile (renv.lock)
- JSON file recording exact package versions
- Includes package sources (CRAN, GitHub, etc.)
- Enables exact reproduction of environment

### Cache
- Global package cache prevents redundant downloads
- Packages are linked, not copied, saving disk space
- Located in `~/.local/share/renv` (Linux/Mac) or `%LOCALAPPDATA%/renv` (Windows)

## Basic Workflow

### 1. Initialize Project
```r
# Start using renv in a project
renv::init()

# What happens:
# - Creates renv/ directory
# - Creates .Rprofile to activate renv
# - Generates renv.lock from current packages
# - Installs packages into project library
```

### 2. Install Packages
```r
# Install from CRAN
install.packages("dplyr")
renv::install("dplyr")  # Alternative

# Install specific version
renv::install("dplyr@1.0.0")

# Install from GitHub
renv::install("tidyverse/dplyr")

# Install from Bioconductor
renv::install("bioc::BiocGenerics")

# Install local package
renv::install("path/to/package")
```

### 3. Snapshot State
```r
# Save current package state to lockfile
renv::snapshot()

# Preview what would be snapshotted
renv::snapshot(preview = TRUE)

# Snapshot specific packages only
renv::snapshot(packages = c("dplyr", "ggplot2"))
```

### 4. Restore Environment
```r
# Restore packages from lockfile
renv::restore()

# Preview what would be restored
renv::restore(preview = TRUE)

# Restore specific packages
renv::restore(packages = "dplyr")
```

## Common Commands

### Status and Diagnostics
```r
# Check project status
renv::status()

# View project settings
renv::settings()

# Check for package issues
renv::diagnostics()

# View dependency tree
renv::dependencies()
```

### Package Management
```r
# Update packages
renv::update()           # Update all
renv::update("dplyr")    # Update specific

# Remove packages
renv::remove("unused-package")

# Clean unused packages
renv::clean()

# Rebuild packages
renv::rebuild("package-name")
```

### Project Migration
```r
# Migrate from packrat
renv::migrate()

# Deactivate renv (keep files)
renv::deactivate()

# Completely remove renv
renv::deactivate(clean = TRUE)
```

## renv.lock Format

### Basic Structure
```json
{
  "R": {
    "Version": "4.3.1",
    "Repositories": [
      {
        "Name": "CRAN",
        "URL": "https://cran.rstudio.com"
      }
    ]
  },
  "Packages": {
    "dplyr": {
      "Package": "dplyr",
      "Version": "1.1.2",
      "Source": "Repository",
      "Repository": "CRAN"
    },
    "ggplot2": {
      "Package": "ggplot2",
      "Version": "3.4.2",
      "Source": "Repository",
      "Repository": "CRAN",
      "Requirements": [
        "R",
        "cli",
        "glue",
        "grid"
      ]
    }
  }
}
```

### GitHub Packages
```json
{
  "Package": "devtools",
  "Version": "2.4.5.9000",
  "Source": "GitHub",
  "RemoteType": "github",
  "RemoteHost": "api.github.com",
  "RemoteUsername": "r-lib",
  "RemoteRepo": "devtools",
  "RemoteRef": "HEAD",
  "RemoteSha": "abc123..."
}
```

## Configuration

### Project Settings (.Rprofile)
```r
# Automatically created by renv::init()
source("renv/activate.R")

# Custom settings
options(
  renv.settings.snapshot.type = "explicit",
  renv.settings.vcs.ignore = TRUE
)
```

### Global Settings
```r
# Set global cache location
Sys.setenv(RENV_PATHS_CACHE = "/path/to/cache")

# Disable cache
options(renv.config.cache.enabled = FALSE)

# Use alternative CRAN mirror
options(repos = c(CRAN = "https://cran.r-project.org"))
```

### Ignored Files (.renvignore)
```
# Ignore specific files
temp/
*.log
data/*.csv

# Ignore by pattern
*_cache/
*_files/
```

## Docker Integration

### Basic Dockerfile
```dockerfile
FROM rocker/r-ver:4.3.1
WORKDIR /app

# Install renv
RUN R -e "install.packages('renv')"

# Copy renv files
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R

# Restore packages
RUN R -e "renv::restore()"

# Copy application
COPY . .

CMD ["R"]
```

### Optimized Dockerfile
```dockerfile
# Use cache mount for faster builds
FROM rocker/r-ver:4.3.1
WORKDIR /app

# Install renv
RUN R -e "install.packages('renv')"

# Copy lockfile first
COPY renv.lock .

# Restore with cache mount
RUN --mount=type=cache,target=/root/.local/share/renv \
    R -e "renv::restore()"

# Copy rest of application
COPY . .
```

### Docker Compose
```yaml
version: '3.8'
services:
  r-app:
    build: .
    volumes:
      - renv-cache:/root/.local/share/renv
    environment:
      - RENV_PATHS_CACHE=/root/.local/share/renv

volumes:
  renv-cache:
```

## Best Practices

### 1. Version Control
```bash
# Always commit these files
git add renv.lock
git add .Rprofile
git add renv/activate.R

# Ignore library and cache
echo "renv/library/" >> .gitignore
echo "renv/local/" >> .gitignore
echo "renv/staging/" >> .gitignore
```

### 2. Collaboration Workflow
```r
# When starting work
git pull
renv::restore()

# Before committing
renv::snapshot()
git add renv.lock
git commit -m "Update dependencies"
```

### 3. Continuous Integration
```yaml
# GitHub Actions example
- name: Setup R
  uses: r-lib/actions/setup-r@v2
  
- name: Cache renv packages
  uses: actions/cache@v3
  with:
    path: ~/.local/share/renv
    key: ${{ runner.os }}-renv-${{ hashFiles('**/renv.lock') }}
    
- name: Restore packages
  run: |
    R -e "install.packages('renv')"
    R -e "renv::restore()"
```

### 4. Production Deployment
```r
# Use explicit snapshots in production
options(renv.settings.snapshot.type = "explicit")

# Only snapshot direct dependencies
renv::snapshot(type = "explicit")
```

## Troubleshooting

### Common Issues

#### 1. Package Installation Fails
```r
# Check for missing system dependencies
renv::diagnostics()

# Try alternative installation method
renv::install("package", type = "source")

# Use binary packages
options(pkgType = "binary")
renv::install("package")
```

#### 2. Cache Issues
```r
# Repair cache
renv::repair()

# Clear cache for specific package
renv::purge("package-name")

# Rehash cache
renv::rehash()
```

#### 3. Lockfile Conflicts
```r
# Check differences
renv::status()

# Force restore from lockfile
renv::restore(clean = TRUE)

# Update lockfile to match library
renv::snapshot(force = TRUE)
```

#### 4. Permission Problems
```bash
# Fix cache permissions
chmod -R u+rwX ~/.local/share/renv

# Use project-local cache
export RENV_PATHS_CACHE=./renv/cache
```

### Debug Commands
```r
# Verbose output
options(renv.verbose = TRUE)

# Check package sources
renv::diagnostics(package = "problematic-package")

# View effective repositories
getOption("repos")

# Check renv version
packageVersion("renv")
```

## Advanced Features

### Custom Repositories
```r
# Add custom repository
options(repos = c(
  CRAN = "https://cran.r-project.org",
  CUSTOM = "https://my-repo.example.com"
))

# Use specific repository for package
renv::install("package", repos = "https://custom-repo.com")
```

### Python Integration
```r
# Use Python with reticulate
renv::use_python()

# Specify Python version
renv::use_python(python = "/usr/bin/python3")
```

### Dependency Discovery
```r
# Find all dependencies in project
deps <- renv::dependencies()

# Custom dependency discovery
renv::dependencies(
  root = "scripts/",
  progress = FALSE
)
```

### Project Templates
```r
# Create template for new projects
renv::scaffold(
  project = "new-project",
  settings = list(
    snapshot.type = "explicit",
    vcs.ignore = TRUE
  )
)
```

## Performance Tips

### 1. Use Binary Packages
```r
# Prefer binaries when available
options(pkgType = "both")
```

### 2. Parallel Installation
```r
# Enable parallel downloads
options(Ncpus = 4)
```

### 3. Local Package Sources
```r
# Use local CRAN mirror
options(repos = c(CRAN = "file:///path/to/local/cran"))
```

### 4. Minimal Snapshots
```r
# Only snapshot explicitly installed packages
renv::settings$snapshot.type("explicit")
```