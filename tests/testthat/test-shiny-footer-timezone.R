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
