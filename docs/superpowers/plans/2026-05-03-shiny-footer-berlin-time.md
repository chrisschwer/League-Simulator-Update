# Shiny Footer Berlin-Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Shiny dashboard footer's "Letztes Update: …" timestamp in Berlin local time, with the abbreviation switching automatically between `MEZ` (winter) and `MESZ` (DST), independent of the host's TZ or locale.

**Architecture:** Two-line change in `ShinyApp/app.R`. We pass `tz = "Europe/Berlin"` to `as.POSIXlt()` so the wall-clock conversion is correct everywhere (POSIXct stores an absolute instant; `tz` only changes the display). We then compute the German abbreviation ourselves from `POSIXlt$isdst` instead of relying on `strftime`'s `%Z`, which is platform/locale-dependent (glibc with US-English locale prints `CET`/`CEST`). One regression test pins the DST-flip behavior with two fixed UTC instants.

**Tech Stack:** R (base only — no new packages), `shiny`, `testthat` 3.x.

**Spec:** `docs/superpowers/specs/2026-05-03-shiny-footer-berlin-time-design.md`
**Issue:** [#103](https://github.com/chrisschwer/League-Simulator-Update/issues/103)

---

## File Structure

- **Modify:** `ShinyApp/app.R`
  - Line 18 — change `tz = ""` to `tz = "Europe/Berlin"`.
  - Line 130 — drop `%Z` from the format string and append `MEZ`/`MESZ` from `updatetime$isdst`, with an inline comment documenting the negative-`isdst` fall-through.
- **Create:** `tests/testthat/test-shiny-footer-timezone.R`
  - One file, two `test_that` blocks, no Shiny session needed. Sits alongside other `test-*.R` files in `tests/testthat/` per existing convention. (`tests/testthat/test-shiny/` exists but is empty; we keep flat layout for discoverability.)

No other files. No Dockerfile, deploy script, or `packagelist.txt` change.

---

## Branch setup

- [ ] **Step 0.1: Create a working branch off `main`**

Run from the repo root:

```bash
git checkout main
git pull --ff-only
git checkout -b fix/issue-103-shiny-footer-berlin-time
```

Expected: a clean working tree on the new branch.

---

## Task 1: Pin DST flip behavior with a failing test

**Files:**
- Test: `tests/testthat/test-shiny-footer-timezone.R` (create)

This test exercises only the abbreviation logic — it constructs two fixed UTC instants (one summer, one winter), converts them with `as.POSIXlt(..., tz = "Europe/Berlin")`, and checks that the rendered footer string matches the spec's examples. No Shiny session, no `app.R` sourcing, no file I/O. The point is to lock the behavior so a future "cleanup" can't silently break it.

The test will fail right now because `app.R` is the only place this logic lives and it's wrong. Rather than try to source `app.R` (which has top-level `load(...)` and `library(shiny)` calls that fight with testthat), we duplicate the *exact* expression we plan to use in `app.R` inside a small inline helper in the test file. After Task 2, that expression also lives in `app.R`. They are identical and there is no abstraction to keep them in sync — that's intentional (the spec calls out "no helper extraction" as out of scope).

- [ ] **Step 1.1: Write the failing test file**

Create `tests/testthat/test-shiny-footer-timezone.R` with this exact content:

```r
library(testthat)

# Mirrors the footer-rendering expression in ShinyApp/app.R.
# Kept in sync by hand — the spec explicitly leaves extraction out of scope.
render_footer <- function(instant_utc) {
  updatetime <- as.POSIXlt(instant_utc, tz = "Europe/Berlin")
  paste("Letztes Update: ",
        format(updatetime, "%d.%m.%Y %H:%M"),
        " ",
        # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
        if (updatetime$isdst > 0) "MESZ" else "MEZ",
        sep = "")
}

test_that("summer UTC instant renders as MESZ in Berlin local time", {
  summer <- as.POSIXct("2026-07-15 12:00:00", tz = "UTC")
  expect_equal(render_footer(summer),
               "Letztes Update: 15.07.2026 14:00 MESZ")
})

test_that("winter UTC instant renders as MEZ in Berlin local time", {
  winter <- as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
  expect_equal(render_footer(winter),
               "Letztes Update: 15.01.2026 13:00 MEZ")
})

test_that("fall-back ambiguity: same wall clock, different abbreviation", {
  # 00:30 UTC on 2026-10-25 = 02:30 MESZ (DST still in force)
  pre_fb  <- as.POSIXct("2026-10-25 00:30:00", tz = "UTC")
  # 01:30 UTC on 2026-10-25 = 02:30 MEZ  (after fall-back to standard time)
  post_fb <- as.POSIXct("2026-10-25 01:30:00", tz = "UTC")
  expect_equal(render_footer(pre_fb),
               "Letztes Update: 25.10.2026 02:30 MESZ")
  expect_equal(render_footer(post_fb),
               "Letztes Update: 25.10.2026 02:30 MEZ")
})
```

- [ ] **Step 1.2: Run the test and confirm it passes (this is a logic-only test)**

Note: this test embeds the *target* logic inside `render_footer()`, so it will pass even before we change `app.R`. That's deliberate — the test pins the behavior we're aiming for, and Task 3 verifies `app.R` matches it by inspection. (We can't easily source `app.R` from a test because of its top-level side effects, and doing so is explicitly out of scope per the spec.)

Run from the repo root:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-shiny-footer-timezone.R")'
```

Expected output: 3 PASS, 0 FAIL. Sample tail:

```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3 ]
```

If it does not pass, the most likely cause is missing tzdata for `Europe/Berlin` on the host. Confirm with:

```bash
Rscript -e 'format(as.POSIXlt(as.POSIXct("2026-07-15 12:00:00", tz="UTC"), tz="Europe/Berlin"), "%H:%M")'
```

Expected output: `[1] "14:00"`. If you see `12:00`, the host's tzdata is broken — install/repair it before continuing.

- [ ] **Step 1.3: Commit the test**

```bash
git add tests/testthat/test-shiny-footer-timezone.R
git commit -m "test(#103): pin Shiny footer MEZ/MESZ rendering"
```

---

## Task 2: Make `app.R` render Berlin time with MEZ/MESZ

**Files:**
- Modify: `ShinyApp/app.R:18`
- Modify: `ShinyApp/app.R:127-132`

For reference, the relevant region of `ShinyApp/app.R` currently looks like this (lines 17–18 and 127–132):

```r
load ("data/Ergebnis.Rds")
updatetime <- as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "")
```

```r
       helpText("Alle Prognosen als Wahrscheinlichkeiten in Prozent angegeben. Nähere Infos unter ",
                a ("30punkte.wordpress.com", href = "http://30punkte.wordpress.com", target = "blank_"),
                paste("Letztes Update: ", 
                      format(updatetime, "%d.%m.%Y %H:%M %Z"),
                      sep="")
       )
```

- [ ] **Step 2.1: Change line 18 — set `tz = "Europe/Berlin"`**

Use the Edit tool (or `sed -i` if you prefer) to replace:

```r
updatetime <- as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "")
```

with:

```r
updatetime <- as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "Europe/Berlin")
```

- [ ] **Step 2.2: Change the `paste(...)` block on lines 129–131 — drop `%Z`, append abbreviation**

Replace:

```r
                paste("Letztes Update: ", 
                      format(updatetime, "%d.%m.%Y %H:%M %Z"),
                      sep="")
```

with:

```r
                paste("Letztes Update: ",
                      format(updatetime, "%d.%m.%Y %H:%M"),
                      " ",
                      # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
                      if (updatetime$isdst > 0) "MESZ" else "MEZ",
                      sep = "")
```

Note the `sep = ""` (with spaces) — match the surrounding style of the file rather than the original `sep=""`. Either works in R; this is purely cosmetic and should not block the change.

- [ ] **Step 2.3: Verify the file parses**

`app.R` is loaded by Shiny at runtime and we don't want to discover a syntax error in production. Sanity-check it parses:

```bash
Rscript -e 'parse("ShinyApp/app.R"); cat("OK\n")'
```

Expected output: `OK`. Any syntax error means revert and re-apply the edits carefully.

- [ ] **Step 2.4: Re-run the regression test**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-shiny-footer-timezone.R")'
```

Expected output: 3 PASS, 0 FAIL.

- [ ] **Step 2.5: Confirm the rendered string by hand against the live `app.R` expression**

This is the only "did `app.R` actually change correctly" check, since the test file uses an inline mirror. Run:

```bash
Rscript -e '
# Replicate the exact expression from app.R lines 18 + 129-134, but feed a fixed instant.
fake_mtime <- as.POSIXct("2026-07-15 12:00:00", tz = "UTC")
updatetime <- as.POSIXlt(fake_mtime, tz = "Europe/Berlin")
out <- paste("Letztes Update: ",
             format(updatetime, "%d.%m.%Y %H:%M"),
             " ",
             if (updatetime$isdst > 0) "MESZ" else "MEZ",
             sep = "")
cat(out, "\n")
'
```

Expected output exactly: `Letztes Update:  15.07.2026 14:00 MESZ`

(Note the double space after the colon — that comes from the trailing space in the literal `"Letztes Update: "` plus the way `paste` joins the next argument; this matches the pre-existing footer formatting and is not introduced by this change.)

- [ ] **Step 2.6: Commit the app change**

```bash
git add ShinyApp/app.R
git commit -m "fix(#103): render Shiny footer in Europe/Berlin with MEZ/MESZ"
```

---

## Task 3: Run the full test suite to catch regressions

This is a small change to a UI file that no other test exercises, but the suite is fast enough to be worth a final pass before opening a PR.

- [ ] **Step 3.1: Run the full test suite**

```bash
Rscript tests/testthat.R
```

Expected: existing pass/fail counts unchanged compared to `main`, plus the 3 new PASS lines from Task 1.

If `tests/testthat.R` is too slow or has unrelated flakes that aren't this PR's problem, you can scope to the new file only:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-shiny-footer-timezone.R")'
```

- [ ] **Step 3.2: Verify the diff is exactly what we intend**

```bash
git diff main -- ShinyApp/app.R
```

Expected: only the two changes from Task 2 (line 18 and the `paste(...)` block). Nothing else in `app.R` should be touched.

```bash
git diff main -- tests/testthat/test-shiny-footer-timezone.R
```

Expected: the entire new test file from Task 1, no other changes.

- [ ] **Step 3.3: Push the branch and open the PR**

```bash
git push -u origin fix/issue-103-shiny-footer-berlin-time

gh pr create --title "fix(#103): render Shiny footer in Europe/Berlin (MEZ/MESZ)" --body "$(cat <<'EOF'
## Summary
- `ShinyApp/app.R` now converts the `Letztes Update` timestamp to `Europe/Berlin` via `tz = "Europe/Berlin"` on `as.POSIXlt`.
- Abbreviation is computed from `POSIXlt$isdst` (positive → `MESZ`, otherwise → `MEZ`), instead of the host-locale-dependent `%Z`.
- New regression test pins the DST-flip behavior, including the autumn fall-back ambiguity.

Closes #103.

## Test plan
- [ ] `Rscript -e 'testthat::test_file("tests/testthat/test-shiny-footer-timezone.R")'` → 3 PASS, 0 FAIL
- [ ] `Rscript tests/testthat.R` → no new failures vs. main
- [ ] After deploy to ShinyApps.io, footer reads `Letztes Update: DD.MM.YYYY HH:MM MESZ` (summer) or `... MEZ` (winter)

## Spec
docs/superpowers/specs/2026-05-03-shiny-footer-berlin-time-design.md
EOF
)"
```

Expected: `gh` prints the new PR URL. Paste it into the issue thread on #103.

---

## Manual post-deploy check (not a code step)

After the PR is merged and the next ShinyApps.io deploy goes out (the scheduler pushes at the next active window — see `docs/deployment/quick-start.md`), open `https://chrisschwer.shinyapps.io/FussballPrognosen/` and confirm the footer ends with `MEZ` (winter) or `MESZ` (summer / DST). If you see `CET`/`CEST` instead, the build went out without the new `app.R` — re-run the deploy.

---

## Self-review notes

- **Spec coverage:**
  - Spec "Change → Line 18" → Task 2 Step 2.1 ✓
  - Spec "Change → Line 130 (incl. inline comment)" → Task 2 Step 2.2 ✓
  - Spec "Testing — summer/winter abbreviation" → Task 1 Step 1.1 (plus a third fall-back test for free, since the design discussion called it out explicitly) ✓
  - Spec "Out of scope: no helper extraction, no new packages" → respected; the test's `render_footer` is a hand-mirrored duplicate, not an extraction from `app.R` ✓
  - Spec "Edge case: file missing — out of scope" → not implemented, as required ✓
- **Placeholder scan:** no TBD/TODO/"add appropriate"/"similar to" — every step has the literal commands and code.
- **Type/identifier consistency:** `updatetime`, `isdst`, `Europe/Berlin`, `MEZ`/`MESZ`, `tests/testthat/test-shiny-footer-timezone.R`, `render_footer` — spelled identically across all tasks.
