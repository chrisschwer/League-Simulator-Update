# ConfigMap YAML Generator for League Simulator Team Data
# Converts TeamList CSV files to Kubernetes ConfigMap YAML format

library(yaml)

#' Generate ConfigMap YAML from TeamList CSV file
#'
#' @param csv_file Path to TeamList CSV file
#' @param season Season year (e.g., "2025")
#' @param version ConfigMap version (default: "1.0.0")
#' @param namespace Kubernetes namespace (default: "league-simulator")
#' @param output_dir Directory to save YAML file (default: "k8s/configmaps")
#' @return Path to generated YAML file
generate_configmap_yaml <- function(csv_file, season, version = "1.0.0", 
                                   namespace = "league-simulator", 
                                   output_dir = "k8s/configmaps") {
  
  # Validate inputs
  if (!file.exists(csv_file)) {
    stop("CSV file not found: ", csv_file)
  }
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Read CSV data
  cat("Reading CSV file:", csv_file, "\n")
  team_data <- read.csv(csv_file, sep = ";", stringsAsFactors = FALSE, encoding = "UTF-8")
  
  # Validate CSV structure
  required_cols <- c("TeamID", "ShortText", "Promotion", "InitialELO")
  missing_cols <- setdiff(required_cols, names(team_data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Generate CSV content with proper formatting
  csv_content <- paste(
    paste(names(team_data), collapse = ";"),
    paste(apply(team_data, 1, function(row) paste(row, collapse = ";")), collapse = "\n"),
    sep = "\n"
  )
  
  # Escape special characters for YAML
  csv_content <- gsub("\\\\", "\\\\\\\\", csv_content)
  csv_content <- gsub("\"", "\\\"", csv_content)
  
  # Indent CSV content for YAML
  csv_lines <- strsplit(csv_content, "\n")[[1]]
  indented_csv <- paste0("    ", csv_lines, collapse = "\n")
  
  # Generate ConfigMap metadata
  configmap_name <- paste0("team-data-", season)
  csv_filename <- paste0("TeamList_", season, ".csv")
  
  # Create ConfigMap structure
  configmap <- list(
    apiVersion = "v1",
    kind = "ConfigMap",
    metadata = list(
      name = configmap_name,
      namespace = namespace,
      labels = list(
        app = "league-simulator",
        component = "team-data",
        season = season,
        version = version
      ),
      annotations = list(
        "generated-by" = "configmap-generator.R",
        "generated-at" = as.character(Sys.time()),
        "team-count" = as.character(nrow(team_data)),
        "source-file" = basename(csv_file)
      )
    ),
    data = structure(list(indented_csv), names = csv_filename)
  )
  
  # Generate YAML content manually for better control over formatting
  yaml_content <- paste0(
    "apiVersion: v1\n",
    "kind: ConfigMap\n",
    "metadata:\n",
    "  name: ", configmap_name, "\n",
    "  namespace: ", namespace, "\n",
    "  labels:\n",
    "    app: league-simulator\n",
    "    component: team-data\n",
    "    season: \"", season, "\"\n",
    "    version: \"", version, "\"\n",
    "  annotations:\n",
    "    generated-by: \"configmap-generator.R\"\n",
    "    generated-at: \"", Sys.time(), "\"\n",
    "    team-count: \"", nrow(team_data), "\"\n",
    "    source-file: \"", basename(csv_file), "\"\n",
    "data:\n",
    "  ", csv_filename, ": |\n",
    indented_csv, "\n"
  )
  
  # Write YAML file
  output_file <- file.path(output_dir, paste0(configmap_name, ".yaml"))
  writeLines(yaml_content, output_file, useBytes = TRUE)
  
  cat("Generated ConfigMap YAML:", output_file, "\n")
  cat("Team count:", nrow(team_data), "\n")
  cat("ConfigMap size:", nchar(yaml_content), "bytes\n")
  
  return(output_file)
}

#' Generate ConfigMaps for all available seasons
#'
#' @param rcode_dir Directory containing TeamList CSV files (default: "RCode")
#' @param output_dir Directory to save YAML files (default: "k8s/configmaps")
#' @param version ConfigMap version (default: "1.0.0")
#' @return Vector of generated YAML file paths
generate_all_configmaps <- function(rcode_dir = "RCode", output_dir = "k8s/configmaps", version = "1.0.0") {
  
  # Find all TeamList CSV files
  csv_files <- list.files(rcode_dir, pattern = "^TeamList_[0-9]{4}\\.csv$", full.names = TRUE)
  
  if (length(csv_files) == 0) {
    stop("No TeamList CSV files found in ", rcode_dir)
  }
  
  cat("Found", length(csv_files), "TeamList files:\n")
  print(basename(csv_files))
  
  # Generate ConfigMap for each season
  yaml_files <- character(0)
  
  for (csv_file in csv_files) {
    # Extract season from filename
    season <- sub(".*TeamList_([0-9]{4})\\.csv", "\\1", basename(csv_file))
    
    tryCatch({
      yaml_file <- generate_configmap_yaml(csv_file, season, version, output_dir = output_dir)
      yaml_files <- c(yaml_files, yaml_file)
    }, error = function(e) {
      cat("Error generating ConfigMap for", csv_file, ":", e$message, "\n")
    })
  }
  
  cat("\nGenerated", length(yaml_files), "ConfigMap YAML files\n")
  return(yaml_files)
}

#' Validate generated ConfigMap YAML file
#'
#' @param yaml_file Path to YAML file to validate
#' @return TRUE if valid, stops with error if invalid
validate_configmap_yaml <- function(yaml_file) {
  
  if (!file.exists(yaml_file)) {
    stop("YAML file not found: ", yaml_file)
  }
  
  # Read and parse YAML
  tryCatch({
    yaml_content <- yaml::read_yaml(yaml_file)
  }, error = function(e) {
    stop("Invalid YAML format in ", yaml_file, ": ", e$message)
  })
  
  # Validate ConfigMap structure
  if (yaml_content$apiVersion != "v1") {
    stop("Invalid apiVersion in ", yaml_file)
  }
  
  if (yaml_content$kind != "ConfigMap") {
    stop("Invalid kind in ", yaml_file)
  }
  
  if (is.null(yaml_content$metadata$name)) {
    stop("Missing metadata.name in ", yaml_file)
  }
  
  if (is.null(yaml_content$data)) {
    stop("Missing data section in ", yaml_file)
  }
  
  # Validate CSV data within ConfigMap
  csv_keys <- names(yaml_content$data)
  if (length(csv_keys) != 1) {
    stop("ConfigMap should contain exactly one CSV file, found: ", length(csv_keys))
  }
  
  csv_key <- csv_keys[1]
  if (!grepl("^TeamList_[0-9]{4}\\.csv$", csv_key)) {
    stop("Invalid CSV filename in ConfigMap: ", csv_key)
  }
  
  cat("✓ ConfigMap YAML validation passed:", yaml_file, "\n")
  return(TRUE)
}

#' Main function to generate and validate all ConfigMaps
#'
#' @param validate Whether to validate generated YAML files (default: TRUE)
main <- function(validate = TRUE) {
  cat("=== ConfigMap Generator for League Simulator ===\n\n")
  
  # Generate all ConfigMaps
  yaml_files <- generate_all_configmaps()
  
  # Validate generated files
  if (validate) {
    cat("\nValidating generated ConfigMap YAML files...\n")
    for (yaml_file in yaml_files) {
      validate_configmap_yaml(yaml_file)
    }
  }
  
  cat("\n=== ConfigMap generation completed successfully ===\n")
  cat("Generated files:\n")
  for (yaml_file in yaml_files) {
    cat(" -", yaml_file, "\n")
  }
  
  cat("\nTo deploy ConfigMaps to cluster:\n")
  cat("kubectl apply -f k8s/configmaps/\n")
  
  return(yaml_files)
}

# Run main function if script is executed directly
if (!interactive()) {
  main()
}