#!/usr/bin/env Rscript
# Analyze test dependencies to enable selective test execution

library(tools)

# Function to parse R file and extract dependencies
extract_dependencies <- function(file_path) {
  deps <- list(
    sources = character(),
    functions = character(),
    files = character()
  )
  
  tryCatch({
    content <- readLines(file_path)
    
    # Find source() calls
    source_pattern <- "source\\([\"']([^\"']+)[\"']"
    source_matches <- gregexpr(source_pattern, content, perl = TRUE)
    for (i in seq_along(content)) {
      if (source_matches[[i]][1] != -1) {
        matches <- regmatches(content[i], source_matches[[i]])
        for (match in matches) {
          file <- sub(source_pattern, "\\1", match, perl = TRUE)
          deps$sources <- c(deps$sources, file)
        }
      }
    }
    
    # Find function calls from RCode directory
    func_pattern <- "([a-zA-Z_][a-zA-Z0-9_.]*)\\s*\\("
    for (line in content) {
      matches <- gregexpr(func_pattern, line, perl = TRUE)
      if (matches[[1]][1] != -1) {
        funcs <- regmatches(line, matches)[[1]]
        funcs <- sub("\\s*\\($", "", funcs)
        deps$functions <- unique(c(deps$functions, funcs))
      }
    }
    
    # Find file references
    file_pattern <- "[\"']([^\"']*\\.(csv|rds|txt|R))[\"']"
    for (line in content) {
      matches <- gregexpr(file_pattern, line, perl = TRUE)
      if (matches[[1]][1] != -1) {
        files <- regmatches(line, matches)[[1]]
        files <- gsub("[\"']", "", files)
        deps$files <- unique(c(deps$files, files))
      }
    }
    
  }, error = function(e) {
    warning(sprintf("Error parsing %s: %s", file_path, e$message))
  })
  
  return(deps)
}

# Function to determine which tests need to run based on changes
determine_affected_tests <- function(changed_files, test_dir = "tests/testthat") {
  affected_tests <- character()
  all_tests <- list.files(test_dir, pattern = "^test.*\\.R$", full.names = TRUE)
  
  # Build dependency map
  test_deps <- list()
  for (test in all_tests) {
    test_deps[[test]] <- extract_dependencies(test)
  }
  
  # Check which tests are affected by changes
  for (test in names(test_deps)) {
    deps <- test_deps[[test]]
    
    # Direct test file change
    if (test %in% changed_files) {
      affected_tests <- c(affected_tests, test)
      next
    }
    
    # Check if any dependency changed
    for (changed in changed_files) {
      # Source file dependency
      if (any(grepl(basename(changed), deps$sources, fixed = TRUE))) {
        affected_tests <- c(affected_tests, test)
        break
      }
      
      # Check if changed file might contain functions used by test
      if (grepl("\\.R$", changed) && changed != test) {
        changed_funcs <- extract_dependencies(changed)$functions
        if (length(intersect(deps$functions, changed_funcs)) > 0) {
          affected_tests <- c(affected_tests, test)
          break
        }
      }
      
      # Data file dependency
      if (any(grepl(basename(changed), deps$files, fixed = TRUE))) {
        affected_tests <- c(affected_tests, test)
        break
      }
    }
  }
  
  return(unique(affected_tests))
}

# Main execution
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0) {
    cat("Usage: test-dependencies.R <changed_files...>\n")
    quit(status = 1)
  }
  
  affected <- determine_affected_tests(args)
  
  if (length(affected) == 0) {
    cat("No tests affected by changes\n")
  } else {
    cat("Affected tests:\n")
    for (test in affected) {
      cat(sprintf("  %s\n", test))
    }
  }
  
  # Output for GitHub Actions
  if (nchar(Sys.getenv("GITHUB_OUTPUT")) > 0) {
    output_file <- Sys.getenv("GITHUB_OUTPUT")
    cat(sprintf("affected_tests=%s\n", paste(affected, collapse = ",")), 
        file = output_file, append = TRUE)
  }
}