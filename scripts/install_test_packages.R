#!/usr/bin/env Rscript

# Install Test Packages Script
# This script installs both production and test dependencies for local development
# For production Docker images, only use packagelist.txt

cat("Installing League Simulator dependencies for development...\n")

# Function to read and clean package list
read_package_list <- function(file_path) {
  if (!file.exists(file_path)) {
    stop(paste("Package list file not found:", file_path))
  }
  
  packages <- readLines(file_path)
  # Remove comments and empty lines
  packages <- packages[!grepl("^#", packages) & nchar(trimws(packages)) > 0]
  packages <- trimws(packages)
  return(packages)
}

# Function to install packages if not already installed
install_if_missing <- function(packages, description) {
  cat(paste("\nChecking", description, "...\n"))
  
  installed_packages <- installed.packages()[, "Package"]
  missing_packages <- packages[!packages %in% installed_packages]
  
  if (length(missing_packages) > 0) {
    cat(paste("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n"))
    install.packages(missing_packages, repos = "https://cloud.r-project.org")
  } else {
    cat("All packages already installed.\n")
  }
}

# Main installation process
tryCatch({
  # Install production dependencies
  prod_packages <- read_package_list("packagelist.txt")
  install_if_missing(prod_packages, "production dependencies")
  
  # Install test dependencies
  test_packages <- read_package_list("test_packagelist.txt")
  install_if_missing(test_packages, "test dependencies")
  
  cat("\n✅ All dependencies successfully installed!\n")
  
  # Verify Rcpp compilation works
  cat("\nVerifying Rcpp compilation...\n")
  library(Rcpp)
  sourceCpp("RCode/SpielNichtSimulieren.cpp")
  cat("✅ Rcpp compilation successful!\n")
  
}, error = function(e) {
  cat("\n❌ Error during installation:\n")
  cat(paste(e$message, "\n"))
  quit(status = 1)
})

cat("\nDevelopment environment setup complete!\n")
cat("You can now run tests with: testthat::test_local()\n")