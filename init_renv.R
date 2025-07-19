# Initialize renv for the League Simulator project

# Install renv if not already installed
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

# Initialize renv
renv::init()

# Install required packages
packages_to_install <- c(
  "dplyr",
  "tidyr", 
  "ggplot2",
  "tibble",
  "magrittr",
  "httr",
  "jsonlite",
  "reshape2",
  "rsconnect",
  "shiny",
  "Rcpp",
  "digest",
  "xtable"  # Keep for backward compatibility even if unused
)

# Install packages
for (pkg in packages_to_install) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

# Create snapshot
renv::snapshot()

cat("renv initialization complete. Check renv.lock file for package versions.\n")