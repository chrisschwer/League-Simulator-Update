# Rocker Project Documentation

## Overview
The Rocker Project provides Docker images for the R environment, offering various pre-configured stacks for different use cases. This document covers the available images, best practices, and optimization techniques for R containerization.

## Rocker Image Stacks

### Versioned Stack (Recommended for Production)

#### r-ver
Base R installation with specific version:
```dockerfile
FROM rocker/r-ver:4.3.1
# Provides R with a fixed version, based on Ubuntu LTS
```

#### rstudio
RStudio Server on top of r-ver:
```dockerfile
FROM rocker/rstudio:4.3.1
# Includes RStudio Server
# Access via http://localhost:8787
```

#### tidyverse
Tidyverse packages pre-installed:
```dockerfile
FROM rocker/tidyverse:4.3.1
# Includes rstudio + tidyverse ecosystem
```

#### verse
LaTeX and publishing tools:
```dockerfile
FROM rocker/verse:4.3.1
# Includes tidyverse + LaTeX (for PDF generation)
```

#### geospatial
Spatial analysis packages:
```dockerfile
FROM rocker/geospatial:4.3.1
# Includes verse + spatial libraries (sf, rgdal, etc.)
```

### Base Stack (Latest R versions)

#### r-base
Official R base image:
```dockerfile
FROM r-base:latest
# Debian-based, always latest R version
# Good for testing, not for production
```

## Running Rocker Containers

### Basic R Console
```bash
docker run --rm -it rocker/r-ver:4.3.1

# With volume mount
docker run --rm -it -v $(pwd):/home/rstudio rocker/r-ver:4.3.1
```

### RStudio Server
```bash
# Basic RStudio
docker run --rm -p 8787:8787 \
  -e PASSWORD=yourpassword \
  rocker/rstudio:4.3.1

# With custom user and volume
docker run --rm -p 8787:8787 \
  -e USER=myuser \
  -e PASSWORD=mypassword \
  -e USERID=1000 \
  -e GROUPID=1000 \
  -v $(pwd):/home/myuser \
  rocker/rstudio:4.3.1
```

### Shiny Server
```bash
docker run --rm -p 3838:3838 \
  -v $(pwd)/app:/srv/shiny-server/ \
  rocker/shiny:4.3.1
```

## Best Practices for R Containerization

### 1. Package Installation

#### System Dependencies First
```dockerfile
FROM rocker/r-ver:4.3.1

# Install system libraries required by R packages
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    && rm -rf /var/lib/apt/lists/*
```

#### R Package Installation
```dockerfile
# Install from CRAN
RUN R -e "install.packages(c('dplyr', 'ggplot2'), repos='https://cran.r-project.org')"

# Install specific versions
RUN R -e "install.packages('remotes')" && \
    R -e "remotes::install_version('dplyr', version='1.1.0')"

# Install from GitHub
RUN R -e "remotes::install_github('tidyverse/dplyr')"
```

### 2. Optimizing Build Time

#### Multi-Stage Builds
```dockerfile
# Build stage - install all packages
FROM rocker/r-ver:4.3.1 AS builder
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev
RUN R -e "install.packages(c('shiny', 'dplyr'), repos='https://cran.r-project.org')"

# Runtime stage - copy installed packages
FROM rocker/r-ver:4.3.1
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
```

#### Parallel Installation
```dockerfile
# Use multiple CPU cores
RUN R -e "install.packages(c('dplyr', 'ggplot2'), Ncpus=4)"
```

### 3. Managing Dependencies

#### Using renv (Recommended)
```dockerfile
FROM rocker/r-ver:4.3.1
WORKDIR /project

# Install renv
RUN R -e "install.packages('renv')"

# Copy renv files
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R

# Restore packages
RUN R -e "renv::restore()"

# Copy project files
COPY . .
```

#### Using packrat
```dockerfile
# Copy packrat files first
COPY packrat/packrat.lock packrat/
RUN R -e "packrat::restore()"
```

### 4. Shiny App Deployment

```dockerfile
FROM rocker/shiny:4.3.1

# Install required packages
RUN R -e "install.packages(c('shinydashboard', 'DT'), repos='https://cran.r-project.org')"

# Copy app files
COPY app.R /srv/shiny-server/
COPY data/ /srv/shiny-server/data/

# Set permissions
RUN chown -R shiny:shiny /srv/shiny-server

# Expose port
EXPOSE 3838

# Run app
CMD ["/usr/bin/shiny-server"]
```

### 5. RStudio Customization

```dockerfile
FROM rocker/rstudio:4.3.1

# Install additional packages
RUN R -e "install.packages(c('devtools', 'roxygen2'))"

# Custom RStudio settings
COPY rstudio-prefs.json /home/rstudio/.config/rstudio/

# Add custom scripts
COPY scripts/ /home/rstudio/scripts/
RUN chown -R rstudio:rstudio /home/rstudio/
```

## Common Patterns

### Data Science Workflow
```dockerfile
FROM rocker/tidyverse:4.3.1

# Install ML packages
RUN R -e "install.packages(c('caret', 'randomForest', 'xgboost'))"

# Install Python integration
RUN apt-get update && apt-get install -y python3-pip
RUN R -e "install.packages('reticulate')"

WORKDIR /analysis
CMD ["R"]
```

### Production Shiny App
```dockerfile
FROM rocker/r-ver:4.3.1

# Install Shiny and dependencies
RUN R -e "install.packages('shiny')"
RUN R -e "install.packages('shinydashboard')"

# Create app directory
RUN mkdir /srv/shiny-app
COPY app.R /srv/shiny-app/

# Create non-root user
RUN useradd -m shinyuser
USER shinyuser

# Run Shiny app
EXPOSE 3838
CMD ["R", "-e", "shiny::runApp('/srv/shiny-app', host='0.0.0.0', port=3838)"]
```

### R Package Development
```dockerfile
FROM rocker/rstudio:4.3.1

# Install development tools
RUN R -e "install.packages(c('devtools', 'testthat', 'covr', 'pkgdown'))"

# Install documentation tools
RUN apt-get update && apt-get install -y \
    pandoc \
    texlive-latex-base \
    texlive-fonts-recommended

# Configure Git
RUN git config --global user.email "developer@example.com"
RUN git config --global user.name "Developer"

WORKDIR /home/rstudio
```

## Performance Optimization

### 1. Use Minimal Base Images
```dockerfile
# Instead of rocker/verse (large)
FROM rocker/r-ver:4.3.1  # Smaller base
```

### 2. Binary Package Installation
```dockerfile
# Use pre-compiled binaries when available
RUN R -e "options(repos = c(RSPM = 'https://packagemanager.rstudio.com/all/latest'))"
RUN R -e "install.packages('dplyr')"  # Will use binary if available
```

### 3. Cache R Library
```dockerfile
# Separate package installation for better caching
COPY DESCRIPTION .
RUN R -e "remotes::install_deps()"
COPY . .
```

## Troubleshooting

### Common Issues

1. **Package Installation Fails**
   - Check system dependencies
   - Use `apt-get update` before installing
   - Check package documentation for requirements

2. **RStudio Connection Issues**
   - Ensure PASSWORD is set
   - Check port mapping (-p 8787:8787)
   - Verify firewall settings

3. **Permission Problems**
   - Use correct user/group IDs
   - Set proper file ownership
   - Consider running as non-root

### Debug Commands
```bash
# Check R version
docker run rocker/r-ver:4.3.1 R --version

# List installed packages
docker run rocker/r-ver:4.3.1 R -e "installed.packages()[,'Package']"

# Test package loading
docker run rocker/r-ver:4.3.1 R -e "library(dplyr)"
```

## Version Management

### Pinning R Version
```dockerfile
# Always use specific versions in production
FROM rocker/r-ver:4.3.1  # Good
# FROM rocker/r-ver:latest  # Avoid
```

### Reproducible Environments
```dockerfile
# Record package versions
RUN R -e "writeLines(capture.output(sessionInfo()), 'sessionInfo.txt')"

# Or use renv for full reproducibility
RUN R -e "renv::snapshot()"
```

## Integration Tips

### With CI/CD
```yaml
# GitHub Actions example
- name: Build R container
  run: docker build -t myapp:latest .
  
- name: Run R tests
  run: docker run myapp:latest R CMD check .
```

### With Docker Compose
```yaml
version: '3.8'
services:
  rstudio:
    image: rocker/rstudio:4.3.1
    ports:
      - "8787:8787"
    environment:
      PASSWORD: ${RSTUDIO_PASSWORD}
    volumes:
      - ./project:/home/rstudio/project
      
  shiny:
    build: .
    ports:
      - "3838:3838"
    depends_on:
      - postgres
```