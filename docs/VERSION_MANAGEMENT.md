# Version Management Strategy

This document describes the hybrid version management approach used in the League Simulator project.

## Overview

We use a hybrid approach that balances reproducibility with security:
- **R packages**: Version-pinned using renv for reproducibility
- **System packages**: Allowed to update for security patches
- **Base images**: Pinned to specific R versions with regular review

## Components

### 1. R Package Management (renv)

We use [renv](https://rstudio.github.io/renv/) to manage R package versions:

```r
# Initialize renv (first time only)
renv::init()

# Install/update packages
install.packages("newpackage")

# Create/update lockfile
renv::snapshot()

# Restore packages from lockfile
renv::restore()
```

The `renv.lock` file contains exact versions of all R packages and is tracked in git.

### 2. Docker Base Images

We pin to specific R versions but allow system updates:

```dockerfile
# Pin R version
FROM rocker/r-ver:4.3.1

# Allow security updates
RUN apt-get update && apt-get upgrade -y
```

### 3. Package Lists

- `packagelist.txt`: Lists required packages (used during Docker build if no renv.lock)
- `renv.lock`: Contains exact versions (preferred for production)

## Update Process

### Monthly Security Review
1. Check for security advisories
2. Review Dependabot alerts
3. Update critical packages immediately

### Quarterly Feature Updates
1. Run `renv::update()` to check for updates
2. Review changelog for breaking changes
3. Test in staging environment
4. Update `renv.lock` via PR

### Annual Major Updates
1. Review R version updates
2. Update base Docker images
3. Full regression testing

## Implementation Steps

### Setting Up renv (First Time)

```bash
# Run the initialization script
Rscript init_renv.R

# Or manually:
R
> renv::init()
> renv::snapshot()
```

### Building Docker Images

With renv.lock:
```dockerfile
COPY renv.lock renv.lock
RUN R -e "renv::restore()"
```

Without renv.lock (fallback):
```dockerfile
COPY packagelist.txt .
RUN Rscript -e "install.packages(readLines('packagelist.txt'))"
```

### Updating Packages

```bash
# Update all packages
R
> renv::update()
> renv::snapshot()

# Update specific package
R
> renv::update("httr")
> renv::snapshot()

# View differences
> renv::diff()
```

## CI/CD Integration

### GitHub Actions
- Dependabot monitors Docker base images
- Custom action for R package update notifications
- Automated testing on package updates

### Testing Strategy
1. Unit tests run on every PR
2. Integration tests for package updates
3. Staging deployment before production

## Rollback Procedures

### Quick Rollback
```bash
# Revert to previous renv.lock
git checkout HEAD~1 -- renv.lock
Rscript -e "renv::restore()"
```

### Docker Rollback
```bash
# Use previous image tag
docker pull myregistry/league-simulator:previous-tag
```

## Best Practices

1. **Never skip renv::snapshot()** after installing packages
2. **Test package updates** in isolated environment first
3. **Document breaking changes** in commit messages
4. **Keep renv itself updated** quarterly
5. **Monitor security advisories** for critical packages

## Troubleshooting

### Package Installation Fails
```r
# Clear renv cache
renv::clean()

# Reinstall from scratch
renv::restore(rebuild = TRUE)
```

### Version Conflicts
```r
# Check package dependencies
renv::diagnostics()

# Force specific version
renv::install("package@1.2.3")
```

### Docker Build Issues
```bash
# Build without cache
docker build --no-cache -t test .

# Check package availability
docker run --rm test R -e "library(package)"
```

## Security Considerations

1. **System packages**: Always run `apt-get upgrade` in Dockerfile
2. **R packages**: Monitor for CVEs in critical packages (httr, jsonlite)
3. **Base images**: Update within 30 days of security patches
4. **Secrets**: Never commit API keys or credentials

## Future Considerations

- Automated R package security scanning
- Integration with vulnerability databases
- Automated update PRs for non-breaking changes
- Package license compliance checking