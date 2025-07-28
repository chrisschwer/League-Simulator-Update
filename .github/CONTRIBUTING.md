# Contributing to League Simulator

Thank you for your interest in contributing to the League Simulator project! This guide will help you get started with contributing code, documentation, and bug reports.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Contributions](#making-contributions)
- [Testing Guidelines](#testing-guidelines)
- [CI/CD Workflow](#cicd-workflow)
- [Pull Request Process](#pull-request-process)
- [Style Guidelines](#style-guidelines)

## Code of Conduct

By participating in this project, you agree to abide by our code of conduct: be respectful, inclusive, and professional in all interactions.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/League-Simulator-Update.git
   cd League-Simulator-Update
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/chrisschwer/League-Simulator-Update.git
   ```

## Development Setup

### Prerequisites

- R 4.3.3 or higher
- Docker and Docker Compose
- Git
- A RapidAPI key for api-football

### Local Environment

1. **Install R dependencies**:
   ```r
   # Install renv if not already installed
   install.packages("renv")
   
   # Restore project dependencies
   renv::restore()
   ```

2. **Set up environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   ```

3. **Run tests locally**:
   ```r
   source("tests/testthat.R")
   ```

## Making Contributions

### Types of Contributions

- **Bug Fixes**: Fix issues reported in GitHub Issues
- **Features**: Add new functionality (discuss in issue first)
- **Documentation**: Improve or add documentation
- **Tests**: Add missing tests or improve test coverage
- **Performance**: Optimize code for better performance

### Workflow

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/issue-NUMBER-description
   ```

2. **Make your changes**:
   - Write clean, documented code
   - Add tests for new functionality
   - Update documentation as needed

3. **Commit your changes**:
   ```bash
   git commit -m "type(#issue): description"
   ```
   
   Types: `feat`, `fix`, `docs`, `test`, `perf`, `refactor`

4. **Push to your fork**:
   ```bash
   git push origin feature/issue-NUMBER-description
   ```

5. **Create a Pull Request** on GitHub

## Testing Guidelines

### Test Organization

Tests are organized by type and located in `tests/testthat/`:

- **Unit Tests**: `test-*.R` files testing individual functions
- **Integration Tests**: `test-integration-*.R` testing component interaction
- **E2E Tests**: `test-e2e-*.R` testing complete workflows
- **Performance Tests**: `test-performance-*.R` testing speed and resources

### Writing Tests

```r
# Example test structure
test_that("function performs expected behavior", {
  # Arrange
  input <- prepare_test_data()
  
  # Act
  result <- function_under_test(input)
  
  # Assert
  expect_equal(result$value, expected_value)
  expect_true(validate_result(result))
})
```

### Test Sharding

Our CI uses test sharding for faster execution. Tests are divided into 4 shards:

1. **Core**: Basic functionality tests
2. **Integration**: Component interaction tests
3. **Performance**: Speed and resource tests
4. **E2E**: End-to-end workflow tests

When adding tests, ensure they're properly categorized for optimal sharding.

## CI/CD Workflow

### Automated Checks

All pull requests trigger automated checks:

1. **R Tests**: Full test suite across multiple R versions
2. **Container Tests**: Docker build and structure validation
3. **Linting**: Code style and quality checks
4. **Documentation**: Ensure docs are updated

### Test Execution

Our CI pipeline features:

- **Parallel Execution**: Tests run in 4 parallel shards
- **Incremental Testing**: Only affected tests run for faster feedback
- **Retry Logic**: Automatic retry for transient failures
- **Flaky Test Management**: Unstable tests are quarantined

### Performance Monitoring

- Build times are tracked and should stay under 15 minutes
- Test success rate should remain above 95%
- Resource usage is monitored to prevent waste

## Pull Request Process

### Before Submitting

1. **Run tests locally**:
   ```r
   source("tests/testthat.R")
   ```

2. **Check code style**:
   ```r
   source("run_linting.R")
   ```

3. **Update documentation** if needed

4. **Ensure CI passes** on your branch

### PR Requirements

- **Clear Title**: `type(#issue): brief description`
- **Description**: Explain what and why
- **Tests**: All new code must have tests
- **Documentation**: Update relevant docs
- **Screenshots**: For UI changes

### Review Process

1. Automated checks must pass
2. At least one maintainer review required
3. All feedback addressed
4. No merge conflicts

## Style Guidelines

### R Code Style

We follow the tidyverse style guide with some modifications:

```r
# Good
calculate_elo_rating <- function(team_a, team_b, result) {
  k_factor <- 32
  expected_a <- 1 / (1 + 10^((team_b - team_a) / 400))
  
  new_rating_a <- team_a + k_factor * (result - expected_a)
  
  return(new_rating_a)
}

# Bad
calculateEloRating<-function(teamA,teamB,result){
  k=32
  expA=1/(1+10^((teamB-teamA)/400))
  newA=teamA+k*(result-expA)
  return(newA)
}
```

### Documentation

- Use roxygen2 for function documentation
- Include examples in documentation
- Keep README.md updated
- Document breaking changes

### Commit Messages

Follow conventional commits:

```
type(#issue): subject

Longer description if needed.

Co-authored-by: Name <email>
```

## Debugging CI Failures

### Common Issues

1. **Test Timeouts**
   - Check for infinite loops
   - Reduce test data size
   - Use skip_on_cran() for slow tests

2. **Platform-Specific Failures**
   - Test on multiple platforms locally
   - Use platform-specific skips when necessary
   - Check file path separators

3. **Flaky Tests**
   - Avoid time-dependent tests
   - Mock external API calls
   - Set random seeds for reproducibility

### Getting Help

- Check existing issues for similar problems
- Ask in discussions for general questions
- Create an issue for bugs or feature requests
- Tag maintainers for urgent issues

## Resources

- [R Packages Book](https://r-pkgs.org/)
- [Tidyverse Style Guide](https://style.tidyverse.org/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)
- [Conventional Commits](https://www.conventionalcommits.org/)

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

Thank you for contributing to League Simulator! Your efforts help make this project better for everyone.