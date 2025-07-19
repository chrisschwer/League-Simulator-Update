# Core Test Infrastructure for Deployment Safety
# This file sets up the base testing framework and utilities

library(testthat)
library(httr)
library(jsonlite)

# Base configuration for deployment tests
DEPLOYMENT_CONFIG <- list(
  staging_url = Sys.getenv("STAGING_URL", "http://localhost:3838"),
  production_url = Sys.getenv("PRODUCTION_URL", "http://league-simulator.prod"),
  k8s_namespace = Sys.getenv("K8S_NAMESPACE", "production"),
  health_check_timeout = 30,
  deployment_timeout = 300
)

# Helper function to check service health
check_service_health <- function(url, timeout = 30) {
  start_time <- Sys.time()
  
  while (as.numeric(Sys.time() - start_time) < timeout) {
    tryCatch({
      response <- GET(paste0(url, "/health"), timeout(5))
      if (status_code(response) == 200) {
        return(list(
          healthy = TRUE,
          response_time = as.numeric(Sys.time() - start_time),
          details = content(response)
        ))
      }
    }, error = function(e) {
      # Continue trying
    })
    Sys.sleep(2)
  }
  
  return(list(
    healthy = FALSE,
    response_time = timeout,
    details = "Health check timed out"
  ))
}

# Helper function to verify deployment status
verify_deployment_status <- function(deployment_name, namespace = DEPLOYMENT_CONFIG$k8s_namespace) {
  cmd <- sprintf(
    "kubectl get deployment %s -n %s -o json",
    deployment_name,
    namespace
  )
  
  result <- system2("kubectl", 
                   args = c("get", "deployment", deployment_name, 
                           "-n", namespace, "-o", "json"),
                   stdout = TRUE,
                   stderr = TRUE)
  
  if (attr(result, "status") == 0) {
    deployment_info <- fromJSON(paste(result, collapse = "\n"))
    
    return(list(
      success = TRUE,
      replicas = deployment_info$status$replicas,
      ready_replicas = deployment_info$status$readyReplicas,
      updated_replicas = deployment_info$status$updatedReplicas,
      conditions = deployment_info$status$conditions
    ))
  } else {
    return(list(
      success = FALSE,
      error = paste(result, collapse = "\n")
    ))
  }
}

# Helper function to execute deployment rollback
execute_rollback <- function(deployment_name, namespace = DEPLOYMENT_CONFIG$k8s_namespace) {
  result <- system2("kubectl",
                   args = c("rollout", "undo", "deployment", deployment_name,
                           "-n", namespace),
                   stdout = TRUE,
                   stderr = TRUE)
  
  return(list(
    success = attr(result, "status") == 0,
    output = paste(result, collapse = "\n")
  ))
}

# Helper function to get current deployment version
get_deployment_version <- function(deployment_name, namespace = DEPLOYMENT_CONFIG$k8s_namespace) {
  result <- system2("kubectl",
                   args = c("get", "deployment", deployment_name,
                           "-n", namespace,
                           "-o", "jsonpath={.spec.template.spec.containers[0].image}"),
                   stdout = TRUE,
                   stderr = TRUE)
  
  if (attr(result, "status") == 0) {
    return(result[1])
  } else {
    return(NA)
  }
}

# Export functions for use in test files
test_infrastructure_exports <- list(
  config = DEPLOYMENT_CONFIG,
  check_service_health = check_service_health,
  verify_deployment_status = verify_deployment_status,
  execute_rollback = execute_rollback,
  get_deployment_version = get_deployment_version
)