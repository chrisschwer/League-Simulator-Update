# Basic code quality checks for test files
files <- list.files('tests/testthat/test-helpers', pattern = '\\.R$', full.names = TRUE)
files <- c(files, 'tests/testthat/test-integration-e2e.R', 'tests/testthat/test-e2e-simulation-workflow.R')

cat('Checking', length(files), 'test files for code quality...\n\n')

issues <- 0
for (f in files) {
  if (!file.exists(f)) {
    cat('File not found:', f, '\n')
    next
  }
  
  lines <- readLines(f)
  cat('Checking:', basename(f), '\n')
  
  # Check for very long lines
  long_lines <- which(nchar(lines) > 100)
  if (length(long_lines) > 0) {
    cat('  - Lines exceeding 100 characters:', paste(long_lines, collapse=', '), '\n')
    issues <- issues + length(long_lines)
  }
  
  # Check for trailing whitespace
  trailing_ws <- which(grepl('\\s+$', lines))
  if (length(trailing_ws) > 0) {
    cat('  - Lines with trailing whitespace:', paste(trailing_ws, collapse=', '), '\n')
    issues <- issues + length(trailing_ws)
  }
  
  # Check for tabs (should use spaces)
  tabs <- which(grepl('\t', lines))
  if (length(tabs) > 0) {
    cat('  - Lines with tabs:', paste(tabs, collapse=', '), '\n')
    issues <- issues + length(tabs)
  }
  
  # Check for proper function documentation
  functions <- grep('^[a-zA-Z_][a-zA-Z0-9_]* <- function\\(', lines)
  documented <- 0
  for (fn_line in functions) {
    if (fn_line > 1 && grepl("^#'", lines[fn_line - 1])) {
      documented <- documented + 1
    }
  }
  if (length(functions) > 0) {
    cat('  - Functions found:', length(functions), ', Documented:', documented, '\n')
  }
  
  if (length(long_lines) == 0 && length(trailing_ws) == 0 && length(tabs) == 0) {
    cat('  ✓ No style issues found\n')
  }
  cat('\n')
}

cat('Total style issues found:', issues, '\n')
if (issues == 0) {
  cat('✓ All files pass basic code quality checks\n')
} else {
  cat('⚠ Some files have style issues that should be addressed\n')
}