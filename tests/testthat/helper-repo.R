# Byteidentischer Helfer, bisher kopiert in test-rust_integration.R,
# test-update_all_leagues_loop.R, test-update_all_leagues_loop-gating.R,
# test-update_all_leagues_loop-rust.R, test-update_all_leagues_loop-sicherheitsnetz.R
# und test-update_all_leagues_loop-verdrahtung.R (#211, Stufe 2, T7).

# Source the production loop fresh so the test sees the current state of the code.
# The loop's source() calls inside its body assume cwd = repo root; we set it explicitly.
with_repo_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(old, "..", ".."))   # tests/testthat -> repo root
  force(expr)
}
