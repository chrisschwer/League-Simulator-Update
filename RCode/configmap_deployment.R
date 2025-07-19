# ConfigMap Deployment Functions
# Handles deployment and management of team data ConfigMaps in Kubernetes

#' Deploy ConfigMap to Kubernetes cluster
#'
#' @param yaml_file Path to ConfigMap YAML file
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @param dry_run If TRUE, show what would be done without applying (default: FALSE)
#' @return TRUE if successful, FALSE otherwise
deploy_configmap_to_cluster <- function(yaml_file, namespace = "league-simulator", dry_run = FALSE) {
  
  if (!file.exists(yaml_file)) {
    stop("ConfigMap YAML file not found: ", yaml_file)
  }
  
  # Check if kubectl is available
  if (Sys.which("kubectl") == "") {
    stop("kubectl command not found. Please install kubectl and ensure it's in your PATH.")
  }
  
  cat("Deploying ConfigMap to cluster...\n")
  cat("File:", yaml_file, "\n")
  cat("Namespace:", namespace, "\n")
  
  if (dry_run) {
    cat("DRY RUN: Would execute the following command:\n")
    cmd <- paste("kubectl apply -f", shQuote(yaml_file), "-n", namespace)
    cat(cmd, "\n")
    return(TRUE)
  }
  
  # Apply ConfigMap to cluster
  tryCatch({
    cmd <- paste("kubectl apply -f", shQuote(yaml_file), "-n", namespace)
    result <- system(cmd, intern = TRUE)
    
    if (length(result) > 0 && any(grepl("configured|created", result))) {
      cat("✓ ConfigMap deployed successfully\n")
      cat("Result:", paste(result, collapse = "\n"), "\n")
      return(TRUE)
    } else {
      cat("❌ ConfigMap deployment failed\n")
      cat("Output:", paste(result, collapse = "\n"), "\n")
      return(FALSE)
    }
    
  }, error = function(e) {
    cat("❌ Error deploying ConfigMap:", e$message, "\n")
    return(FALSE)
  })
}

#' Verify ConfigMap deployment status
#'
#' @param configmap_name Name of the ConfigMap
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @return List with status information
verify_configmap_deployment <- function(configmap_name, namespace = "league-simulator") {
  
  if (Sys.which("kubectl") == "") {
    stop("kubectl command not found")
  }
  
  tryCatch({
    # Check if ConfigMap exists
    cmd <- paste("kubectl get configmap", configmap_name, "-n", namespace, "--no-headers")
    result <- system(cmd, intern = TRUE, ignore.stderr = TRUE)
    
    if (length(result) == 0) {
      return(list(
        exists = FALSE,
        message = paste("ConfigMap", configmap_name, "not found in namespace", namespace)
      ))
    }
    
    # Get ConfigMap details
    cmd <- paste("kubectl get configmap", configmap_name, "-n", namespace, "-o json")
    json_result <- system(cmd, intern = TRUE)
    
    if (length(json_result) > 0) {
      # Parse basic information (simple parsing without jsonlite dependency)
      configmap_info <- paste(json_result, collapse = "")
      
      # Extract creation timestamp (basic regex)
      creation_match <- regexpr('"creationTimestamp":"[^"]*"', configmap_info)
      creation_time <- if (creation_match > 0) {
        substr(configmap_info, creation_match + 20, creation_match + attr(creation_match, "match.length") - 2)
      } else {
        "unknown"
      }
      
      return(list(
        exists = TRUE,
        name = configmap_name,
        namespace = namespace,
        creation_time = creation_time,
        message = "ConfigMap verified successfully"
      ))
    }
    
    return(list(
      exists = FALSE,
      message = "Could not retrieve ConfigMap details"
    ))
    
  }, error = function(e) {
    return(list(
      exists = FALSE,
      error = e$message,
      message = paste("Error verifying ConfigMap:", e$message)
    ))
  })
}

#' Trigger rolling restart of deployments using the ConfigMap
#'
#' @param season Season year to determine which deployments to restart
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @param dry_run If TRUE, show what would be done without restarting (default: FALSE)
#' @return TRUE if all restarts successful, FALSE otherwise
trigger_pod_restart <- function(season = NULL, namespace = "league-simulator", dry_run = FALSE) {
  
  if (Sys.which("kubectl") == "") {
    stop("kubectl command not found")
  }
  
  # Define deployments that use team data
  deployments <- c(
    "league-updater-bl",
    "league-updater-bl2", 
    "league-updater-liga3",
    "shiny-updater"
  )
  
  cat("Triggering rolling restart of deployments...\n")
  if (!is.null(season)) {
    cat("Season:", season, "\n")
  }
  cat("Namespace:", namespace, "\n")
  cat("Deployments:", paste(deployments, collapse = ", "), "\n\n")
  
  if (dry_run) {
    cat("DRY RUN: Would restart the following deployments:\n")
    for (deployment in deployments) {
      cat(" -", deployment, "\n")
    }
    return(TRUE)
  }
  
  success_count <- 0
  failed_deployments <- character(0)
  
  for (deployment in deployments) {
    cat("Restarting", deployment, "...")
    
    tryCatch({
      # Check if deployment exists first
      check_cmd <- paste("kubectl get deployment", deployment, "-n", namespace, "--no-headers")
      check_result <- system(check_cmd, intern = TRUE, ignore.stderr = TRUE)
      
      if (length(check_result) == 0) {
        cat(" ⚠️  Not found, skipping\n")
        next
      }
      
      # Trigger rolling restart
      restart_cmd <- paste("kubectl rollout restart deployment", deployment, "-n", namespace)
      restart_result <- system(restart_cmd, intern = TRUE)
      
      if (length(restart_result) > 0 && any(grepl("restarted", restart_result))) {
        cat(" ✓\n")
        success_count <- success_count + 1
      } else {
        cat(" ❌\n")
        failed_deployments <- c(failed_deployments, deployment)
      }
      
    }, error = function(e) {
      cat(" ❌ Error:", e$message, "\n")
      failed_deployments <- c(failed_deployments, deployment)
    })
  }
  
  cat("\n=== Restart Summary ===\n")
  cat("Successful restarts:", success_count, "\n")
  cat("Failed restarts:", length(failed_deployments), "\n")
  
  if (length(failed_deployments) > 0) {
    cat("Failed deployments:", paste(failed_deployments, collapse = ", "), "\n")
  }
  
  # Wait for rollouts to complete if any were successful
  if (success_count > 0) {
    cat("\nWaiting for rollouts to complete...\n")
    
    for (deployment in deployments) {
      if (!deployment %in% failed_deployments) {
        cat("Checking rollout status for", deployment, "...")
        
        tryCatch({
          status_cmd <- paste("kubectl rollout status deployment", deployment, "-n", namespace, "--timeout=300s")
          status_result <- system(status_cmd, intern = TRUE, ignore.stderr = TRUE)
          
          if (length(status_result) > 0 && any(grepl("successfully rolled out", status_result))) {
            cat(" ✓\n")
          } else {
            cat(" ⚠️  Timeout or error\n")
          }
          
        }, error = function(e) {
          cat(" ❌ Error checking status\n")
        })
      }
    }
  }
  
  return(length(failed_deployments) == 0)
}

#' Deploy ConfigMap and restart pods in one operation
#'
#' @param yaml_file Path to ConfigMap YAML file
#' @param season Season year for the ConfigMap
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @param skip_restart If TRUE, don't restart pods (default: FALSE)
#' @param dry_run If TRUE, show what would be done without making changes (default: FALSE)
#' @return TRUE if successful, FALSE otherwise
deploy_configmap_and_restart <- function(yaml_file, season, namespace = "league-simulator", 
                                        skip_restart = FALSE, dry_run = FALSE) {
  
  cat("=== ConfigMap Deployment and Restart ===\n")
  cat("YAML file:", yaml_file, "\n")
  cat("Season:", season, "\n")
  cat("Namespace:", namespace, "\n")
  cat("Skip restart:", skip_restart, "\n")
  cat("Dry run:", dry_run, "\n\n")
  
  # Step 1: Deploy ConfigMap
  cat("Step 1: Deploying ConfigMap...\n")
  if (!deploy_configmap_to_cluster(yaml_file, namespace, dry_run)) {
    cat("❌ ConfigMap deployment failed\n")
    return(FALSE)
  }
  
  if (dry_run) {
    cat("DRY RUN: ConfigMap deployment would succeed\n")
  }
  
  # Step 2: Verify deployment
  if (!dry_run) {
    cat("\nStep 2: Verifying ConfigMap deployment...\n")
    configmap_name <- paste0("team-data-", season)
    verification <- verify_configmap_deployment(configmap_name, namespace)
    
    if (!verification$exists) {
      cat("❌ ConfigMap verification failed:", verification$message, "\n")
      return(FALSE)
    }
    
    cat("✓ ConfigMap verified:", verification$message, "\n")
  }
  
  # Step 3: Restart pods (if requested)
  if (!skip_restart) {
    cat("\nStep 3: Restarting deployments...\n")
    if (!trigger_pod_restart(season, namespace, dry_run)) {
      cat("⚠️  Some pod restarts failed, but ConfigMap was deployed successfully\n")
      return(FALSE)
    }
  } else {
    cat("\nStep 3: Skipping pod restart (skip_restart = TRUE)\n")
  }
  
  cat("\n🎉 ConfigMap deployment completed successfully!\n")
  return(TRUE)
}

#' Get status of all team data ConfigMaps
#'
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @return Data frame with ConfigMap status information
get_configmap_status <- function(namespace = "league-simulator") {
  
  if (Sys.which("kubectl") == "") {
    stop("kubectl command not found")
  }
  
  tryCatch({
    # Get all ConfigMaps with team-data prefix
    cmd <- paste("kubectl get configmaps -n", namespace, "--no-headers | grep team-data-")
    result <- system(cmd, intern = TRUE, ignore.stderr = TRUE)
    
    if (length(result) == 0) {
      cat("No team data ConfigMaps found in namespace", namespace, "\n")
      return(data.frame(
        name = character(0),
        season = character(0),
        age = character(0),
        status = character(0)
      ))
    }
    
    # Parse results
    configmaps <- data.frame(
      name = character(length(result)),
      season = character(length(result)),
      age = character(length(result)),
      status = character(length(result)),
      stringsAsFactors = FALSE
    )
    
    for (i in seq_along(result)) {
      parts <- strsplit(result[i], "\\s+")[[1]]
      if (length(parts) >= 3) {
        configmaps$name[i] <- parts[1]
        configmaps$age[i] <- parts[3]
        
        # Extract season from name
        season_match <- regexpr("team-data-([0-9]{4})", parts[1])
        if (season_match > 0) {
          season_start <- season_match + 10
          configmaps$season[i] <- substr(parts[1], season_start, season_start + 3)
        }
        
        configmaps$status[i] <- "Active"
      }
    }
    
    return(configmaps)
    
  }, error = function(e) {
    cat("Error getting ConfigMap status:", e$message, "\n")
    return(data.frame(
      name = character(0),
      season = character(0), 
      age = character(0),
      status = character(0)
    ))
  })
}