# Helper for deployment vs development test separation

# Function to skip tests that aren't part of deployment
skip_if_not_deployment_test <- function() {
  if (Sys.getenv("CI_ENVIRONMENT") == "true" && 
      Sys.getenv("RUN_FULL_TEST_SUITE") != "true") {
    skip("Skipping non-deployment test in CI")
  }
}

# Function to identify deployment-critical tests
is_deployment_test <- function() {
  # This is set by CI to only run deployment tests
  Sys.getenv("CI_ENVIRONMENT") != "true" || 
  Sys.getenv("RUN_DEPLOYMENT_TESTS_ONLY") == "true"
}

# List of test files that should run in CI/CD
# These are the components that actually get deployed
DEPLOYMENT_TEST_FILES <- c(
  "test-prozent.R",
  "test-simulationsCPP.R", 
  "test-SpielCPP.R",
  "test-Tabelle.R",
  "test-api/test-api-errors.R",
  "test-transform_data.R",
  "test-shiny/",  # All Shiny tests
  "test-schedulers/"  # Scheduler tests
)

# List of test files to SKIP in CI/CD
# These are maintenance/utility scripts not deployed
SKIP_IN_CI <- c(
  "test-season-transition",
  "test-season-processor",
  "test-season-validation", 
  "test-interactive-prompts",
  "test-input-handler",
  "test-csv-generation",
  "test-team-count-validation",
  "test-multi-season-integration",
  "test-cli-arguments",
  "test-configmap"  # ConfigMaps are generated locally, not in k8s
)

# Function to check if current test should run
should_run_test <- function(test_file) {
  if (Sys.getenv("CI_ENVIRONMENT") != "true") {
    return(TRUE)  # Always run all tests locally
  }
  
  # Check if this test file should be skipped in CI
  for (pattern in SKIP_IN_CI) {
    if (grepl(pattern, test_file)) {
      return(FALSE)
    }
  }
  
  return(TRUE)
}