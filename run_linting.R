# Run linting checks
library(lintr)

# Lint all implemented modules
lint_files <- list.files('RCode', pattern = '(season_|api_|interactive_|input_|csv_|file_|league_|error_|logging|team_config_loader)\\.R$', full.names = TRUE)
lint_files <- c(lint_files, 'scripts/season_transition.R')

total_issues <- 0
files_checked <- 0

for (file in lint_files) {
  if (file.exists(file)) {
    cat('Linting:', basename(file), '\n')
    
    lint_results <- lint(file)
    
    if (length(lint_results) > 0) {
      cat('  Issues found:', length(lint_results), '\n')
      total_issues <- total_issues + length(lint_results)
    } else {
      cat('  ✅ No issues\n')
    }
    
    files_checked <- files_checked + 1
  }
}

cat('\n=== Linting Results ===\n')
cat('Files checked:', files_checked, '\n')
cat('Total issues:', total_issues, '\n')

if (total_issues == 0) {
  cat('✅ All linting checks passed!\n')
} else {
  cat('⚠️ Some linting issues found\n')
}