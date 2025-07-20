# Setup test environment for the worktree
# This installs both production and test packages

# First, install production packages
prod_packages <- readLines("packagelist.txt")
prod_packages <- prod_packages[prod_packages != "" & !grepl("^#", prod_packages)]

cat("Installing production packages...\n")
for (pkg in prod_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Installing", pkg, "...\n")
    install.packages(pkg, repos = "https://cran.r-project.org")
  } else {
    cat(pkg, "already installed\n")
  }
}

# Then install test packages
test_packages <- readLines("test_packagelist.txt")
test_packages <- test_packages[test_packages != "" & !grepl("^#", test_packages)]

cat("\nInstalling test packages...\n")
for (pkg in test_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Installing", pkg, "...\n")
    install.packages(pkg, repos = "https://cran.r-project.org")
  } else {
    cat(pkg, "already installed\n")
  }
}

cat("\nAll packages installed successfully!\n")