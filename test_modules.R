# Test basic R syntax of all modules
test_files <- list.files('RCode', pattern = '(season_|api_|interactive_|input_|csv_|file_|league_|error_|logging)\\.R$', full.names = TRUE)
passed <- 0
failed <- 0

for (file in test_files) {
  cat('Testing:', basename(file), '\n')
  result <- tryCatch({
    source(file)
    cat('  ✅ PASS\n')
    passed <- passed + 1
    TRUE
  }, error = function(e) {
    cat('  ❌ FAIL:', conditionMessage(e), '\n')
    failed <- failed + 1
    FALSE
  })
}

cat('\n=== Test Results ===\n')
cat('Passed:', passed, '\n')
cat('Failed:', failed, '\n')
cat('Total:', passed + failed, '\n')

if (failed == 0) {
  cat('✅ All module tests passed!\n')
} else {
  cat('❌ Some module tests failed\n')
  quit(status = 1)
}