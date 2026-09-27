# Faehrt die R-Testsuite in der CI und macht Skip-Gruende sichtbar (Stufe 4.1,
# #212 Punkt 7). Vorher druckte die CI (.github/workflows/ci.yml) nur
# FAIL/WARN/SKIP/PASS -- ein Rust-abhaengiger Test, der sich trotz laufendem
# Server uebersprang, blieb unsichtbar (Issue #202 wiederholt sich lautlos).
#
# Mit RUST_SKIPS_VERBOTEN=1 (nur in der CI gesetzt) bricht das Skript ab,
# sobald ein Skip-Grund auf Rust verweist. Aufruf: Rscript scripts/ci/testthat_ci.R
# (aus dem Repo-Root, mit gestartetem Rust-Server fuer den CI-Fall).

# Liefert die Teilmenge von `meldungen`, die auf Rust verweisen -- deckt alle
# heute vorkommenden Rust-Skip-Texte ab (Rust-Server nicht erreichbar,
# RUST_API_URL ist leer gesetzt, Rust binary not found, Rust server failed to
# come up).
rust_skips <- function(meldungen) {
  meldungen[grepl("rust", meldungen, ignore.case = TRUE)]
}

# Liest die Skip-Gruende aus einem testthat_results-Objekt (Rueckgabe von
# test_dir()/test_file()): ein data.frame test/meldung, eine Zeile je
# Erwartung der Klasse expectation_skip, in Laufreihenfolge. Ohne Skips:
# 0 Zeilen.
skip_meldungen <- function(res) {
  test <- character(0)
  meldung <- character(0)
  for (block in res) {
    for (e in block$results) {
      if (inherits(e, "expectation_skip")) {
        test <- c(test, block$test)
        meldung <- c(meldung, conditionMessage(e))
      }
    }
  }
  data.frame(test = test, meldung = meldung, stringsAsFactors = FALSE)
}

# Die bisherige CI-Zeile FAIL/WARN/SKIP/PASS, aus df <- as.data.frame(res).
zusammenfassung <- function(df) {
  sprintf("FAIL=%d WARN=%d SKIP=%d PASS=%d",
          sum(df$failed > 0), sum(df$warning), sum(df$skipped), sum(df$nb))
}

main <- function() {
  # Test-only Pakete nachinstallieren, wie zuvor im Inline-Rscript der CI.
  lib <- Sys.getenv("R_LIBS_CI", "/tmp/Rlib")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))
  pkgs <- readLines("test_packagelist.txt")
  pkgs <- pkgs[!grepl("^#|^[[:space:]]*$", pkgs)]
  pkgs <- trimws(pkgs)
  installiert <- rownames(installed.packages())
  fehlend <- setdiff(pkgs, installiert)
  if (length(fehlend) > 0) {
    install.packages(fehlend, repos = "https://cloud.r-project.org")
  }

  options(testthat.progress.max_fails = Inf)
  res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE, reporter = "summary")
  df <- as.data.frame(res)

  summary_pfad <- Sys.getenv("TESTTHAT_SUMMARY", "/out/testthat-summary.txt")
  dir.create(dirname(summary_pfad), recursive = TRUE, showWarnings = FALSE)
  writeLines(capture.output(print(df)), summary_pfad)

  meldungen <- skip_meldungen(res)
  cat("\n--- skips ---\n")
  if (nrow(meldungen) == 0) {
    cat("keine\n")
  } else {
    cat(sprintf("%s | %s", meldungen$test, meldungen$meldung), sep = "\n")
    cat("\n")
  }

  cat("\n--- summary ---\n")
  cat(zusammenfassung(df), "\n")

  if (any(df$failed > 0)) quit(status = 1)

  if (Sys.getenv("RUST_SKIPS_VERBOTEN") == "1") {
    rust <- rust_skips(meldungen$meldung)
    if (length(rust) > 0) {
      cat(sprintf("❌ %d Tests haben sich wegen Rust uebersprungen, obwohl der Server laufen soll:\n",
                  length(rust)))
      cat(rust, sep = "\n")
      cat("\n")
      quit(status = 1)
    }
  }
}

# Laeuft NUR bei direktem Rscript-Aufruf -- der Test laedt dieses Skript mit
# source(local = TRUE) und darf dabei keinesfalls test_dir() starten (Muster
# wie scripts/dev/zuordnung_tests.R).
if (sys.nframe() == 0L) main()
