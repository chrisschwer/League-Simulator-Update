# Einzelergebnisse je test_that()-Block als CSV -- Vergleichsbasis fuer den
# Testsuite-Umbau (#211): Vorher/Nachher-Abgleich als Multimenge, je einmal
# mit und ohne laufenden Rust-Server. Ablauf und Vergleich stehen im Plan
# docs/plans/2026-09-15-testsuite-umbau-und-folgeschritte.md (Task 3, 4, 7).
#
# Aufruf aus dem Repo-Root: Rscript scripts/dev/ergebnisse_tests.R <ziel.csv>
# Die Spalte file dient nur der Diagnose; der Vergleich ignoriert sie, weil
# sich Dateinamen im Umbau aendern.
args <- commandArgs(trailingOnly = TRUE)
ziel <- if (length(args) >= 1) args[1] else "tests/testthat/_baseline/ergebnisse.csv"
dir.create(dirname(ziel), showWarnings = FALSE, recursive = TRUE)
Sys.setenv(RAPIDAPI_KEY = Sys.getenv("RAPIDAPI_KEY", "dummy"))
res <- testthat::test_dir("tests/testthat", reporter = "silent", stop_on_failure = FALSE)
df <- as.data.frame(res)
df <- df[, c("file", "test", "nb", "failed", "skipped", "error")]
names(df) <- c("file", "test", "expectations", "failed", "skipped", "error")
df <- df[do.call(order, df), ]
utils::write.csv(df, ziel, row.names = FALSE)
cat(nrow(df), "Bloecke,", sum(df$expectations), "Erwartungen,",
    sum(df$failed), "Fehlschlaege,", sum(df$error), "Fehler,",
    sum(df$skipped), "Skips\n")
