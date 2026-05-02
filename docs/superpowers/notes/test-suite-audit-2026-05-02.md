# Test suite audit verdict table — 2026-05-02

Temporary working document for PR-B (issue #76 prerequisite). Deleted in
the final commit of PR-B; captured in the merged PR description for the
historical record.

## Verdicts

| Path | Verdict | Justification |
|---|---|---|
| tests/testthat/test-rust-required.R | keep-firm | Production loop ↔ Rust contract (#83) |
| tests/testthat/test-prozent.R | keep-firm | RCode/prozent.R math |
| tests/testthat/test-Tabelle.R | keep-firm | Table/standings logic (both workflows) |
| tests/testthat/test-SpielNichtSimulieren.R | keep-firm | Only test exercising RCode/SpielNichtSimulieren.cpp directly |
| tests/testthat/test-season-processor.R | keep-firm | Season-transition: per-season processing |
| tests/testthat/test-season-validation.R | keep-firm | Season-transition: input validation |
| tests/testthat/test-season-transition-regression.R | keep-firm | Season-transition: end-to-end CSV contract |
| tests/testthat/test-team-count-validation.R | keep-firm | Season-transition: team-count rules |
| tests/testthat/test-interactive-prompts.R | keep-firm | Season-transition: input handling |
| tests/testthat/test-transform_data.R | keep-firm | Season-transition: data transformation |
| tests/testthat/test-SpielCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-simulationsCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-SaisonSimulierenCPP.R | keep-pending-cpp-audit | Resolved in Task 7 |
| tests/testthat/test-deployment.R | delete | All concerns covered by keep-firm tests (C++ compilation by test-SpielNichtSimulieren.R, simulation math by CPP tests, function existence by dedicated tests); API connectivity test is a live network test guarded by API key skip with no unique coverage |
| tests/testthat/helper-deployment.R | delete | Co-deleted with test-deployment.R; defines CI filter helpers referencing k8s configmap and deleted test files that no kept test imports |
| tests/testthat/test-simple-integration.R | delete | References update_all_leagues_loop_simple (deleted in PR #80) and simulationsCPP_wrapper from cpp_wrappers.R; all tested code paths (SaisonSimulierenCPP, Tabelle, simulationsCPP) are covered by keep-pending-cpp-audit files |
| tests/testthat/test-integration-e2e.R | delete | Tests SaisonSimulierenCPP, simulationsCPP_wrapper, and SpielNichtSimulieren — all covered by keep-pending-cpp-audit files; ELO consistency test (block 3) duplicates test-SpielNichtSimulieren.R |
| tests/testthat/test-e2e-simulation-workflow.R | delete | Explicitly mocks leagueSimulatorCPP (deleted) with a hand-rolled probability matrix; comment "In real test, this would call leagueSimulatorCPP" confirms no real production code path is exercised |
| tests/testthat/test-elo-basic.R | delete | All five test_that blocks call SpielNichtSimulieren or SpielCPP for the same ELO update and match simulation properties already covered by test-SpielNichtSimulieren.R (keep-firm) |
| tests/testthat/test-edge-cases/test-extreme-scenarios.R | delete | Test asserts ncol(result) == numberTeams (line 69) but simulationsCPP returns a 6-column Tabelle matrix stacked over iterations; column-index access at lines 113/133 also assumes wrong shape — broken by construction. Coverage redundant with keep-pending-cpp-audit files. |
| tests/testthat/test-api/test-api-errors.R | delete | All test_that blocks define and test locally-scoped mock functions (mock_retrieve_with_retry, handle_api_error, parse_api_response, etc.); no RCode/api_service.R or RCode/api_helpers.R code is sourced or called, so no production code path is protected |
| tests/testthat/test-helpers/api-mock-fixtures.R | delete | Only referenced by test-e2e-simulation-workflow.R (delete) and test-integration-e2e.R (delete); no kept-firm test imports it |
| tests/testthat/test-helpers/elo-mock-generator.R | delete | Only referenced by test-e2e-simulation-workflow.R (delete) and test-integration-e2e.R (delete); no kept-firm test imports it |
| tests/testthat/test-helpers/season-transition-mocks.R | delete | Not referenced by any kept-firm test (grep confirms zero references from keep-firm set); only plausible consumers are the deleted integration tests |
| tests/testthat/helper-fixtures.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/helper-performance-baseline.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/helper-test-setup.R | (decided in Phase 4) | Dependency-driven |
| tests/testthat/fixtures/api-responses/* | (decided per-fixture in Task 17) | Keep iff a kept test references it |
| tests/testthat/fixtures/rust-required/* | keep | Referenced by test-rust-required.R |
| tests/testthat/fixtures/test-data/* | (decided per-fixture in Task 17) | Keep iff a kept test references it |

## Audit method

For each file audited, this worker opened the file, read its `test_that()` blocks,
and wrote the verdict + a one-sentence justification. The justification names
either (a) the deleted code path the test references, (b) the kept test
that already covers the same concern, or (c) the surviving code path that the
test protects (in which case it's a port candidate, not a delete).

Key evidence used per verdict:

- **test-deployment.R**: Five test_that blocks; each concern (C++ compilation,
  API connectivity with skip_if no key, function existence, scheduler loading,
  basic simulation) is either covered by a keep-firm or CPP-audit test, or is
  a live-network test that belongs to deployment verification not unit testing.

- **helper-deployment.R**: Defines `skip_if_not_deployment_test`, `is_deployment_test`,
  and `SKIP_IN_CI` list including "test-configmap" — a k8s artifact. Only consumer
  is test-deployment.R (deleted).

- **test-simple-integration.R**: Sources `../../RCode/cpp_wrappers.R` and calls
  `simulationsCPP_wrapper` (a wrapper from that file); the "Basic season transition
  works" block is a pure data-frame exercise with no RCode import, duplicating
  nothing kept-firm. `update_all_leagues_loop_simple.R` is confirmed deleted.

- **test-integration-e2e.R**: Three blocks. Block 3 (ELO calculations) is an
  exact duplicate concern of test-SpielNichtSimulieren.R. Blocks 1 and 2 call
  SaisonSimulierenCPP/simulationsCPP_wrapper, covered by keep-pending-cpp-audit.

- **test-e2e-simulation-workflow.R**: Explicit comment "In real test, this would
  call leagueSimulatorCPP" at line 49; the test constructs probability matrix
  from a `dnorm` distribution — no simulation engine is invoked.

- **test-elo-basic.R**: Five blocks; all call `SpielNichtSimulieren` or `SpielCPP`
  for home-win ELO change, win-rate, home advantage rate, draw vs. win magnitude,
  goal-diff magnitude — same properties tested in test-SpielNichtSimulieren.R.

- **test-edge-cases/test-extreme-scenarios.R**: `simulationsCPP` called as
  `simulationsCPP(season=, ELOValue=, numberTeams=, numberGames=, iterations=)` —
  this signature does not match the real `simulationsCPP` function which takes
  `Saison`, `TeamList`, `n`, etc. Tests would fail at runtime regardless.

- **test-api/test-api-errors.R**: Confirmed by reading: all error-handling logic
  is defined inline in the test file itself; `RCode/api_service.R` and
  `RCode/api_helpers.R` are never sourced. Tests validate mock behavior, not
  production behavior.

- **test-helpers/api-mock-fixtures.R, elo-mock-generator.R**: `grep -rln` confirms
  only test-e2e-simulation-workflow.R and test-integration-e2e.R reference them.

- **test-helpers/season-transition-mocks.R**: `grep -rln` confirms zero references
  from any kept-firm test file.

## Per-test port notes

No port verdicts issued. All audited files are `delete`. No individual test_that
block from any audited file exercises a unique production code path not already
covered by the keep-firm or keep-pending-cpp-audit set.
