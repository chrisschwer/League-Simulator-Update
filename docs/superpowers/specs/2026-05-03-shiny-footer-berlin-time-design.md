# Shiny footer: display "Letztes Update" in Europe/Berlin (MEZ/MESZ)

**Issue:** [#103](https://github.com/chrisschwer/League-Simulator-Update/issues/103)
**Date:** 2026-05-03
**Status:** approved

## Problem

The footer of the Shiny dashboard currently reads:

> Alle Prognosen als Wahrscheinlichkeiten in Prozent angegeben. Nähere Infos unter 30punkte.wordpress.com **Letztes Update: 02.05.2026 20:25 UTC**

The timestamp is shown in UTC because:

1. `ShinyApp/app.R:18` builds `updatetime` with `tz = ""`, which uses the host's local timezone.
2. ShinyApps.io serves the app from a host whose local TZ is UTC.
3. `format(updatetime, "%d.%m.%Y %H:%M %Z")` on line 130 then prints `UTC`.

For a German-language audience the timestamp should be shown in Berlin local time, with the abbreviation switching automatically between **MEZ** (winter) and **MESZ** (summer / DST).

## Goal

Footer renders the file modification time of `ShinyApp/data/Ergebnis.Rds` as Berlin wall-clock time, suffixed with `MEZ` during standard time and `MESZ` during DST — independent of the host TZ or locale.

Examples:

| File mtime (UTC)             | Footer renders                          |
|------------------------------|-----------------------------------------|
| 2026-01-15 12:00:00          | `Letztes Update: 15.01.2026 13:00 MEZ`  |
| 2026-07-15 12:00:00          | `Letztes Update: 15.07.2026 14:00 MESZ` |
| 2026-10-25 00:30:00 (pre-FB) | `Letztes Update: 25.10.2026 02:30 MESZ` |
| 2026-10-25 01:30:00 (post-FB)| `Letztes Update: 25.10.2026 02:30 MEZ`  |

## Approach

Compute the abbreviation from the `isdst` field of the `POSIXlt` object, rather than relying on `strftime`'s `%Z` (which on a US/English-locale glibc host emits `CET`/`CEST`, not `MEZ`/`MESZ`).

Per `?DateTimeClasses` and `?as.POSIXlt`:

- `POSIXct` represents an absolute instant (seconds since 1970-01-01 UTC). `as.POSIXlt(x, tz = "Europe/Berlin")` converts the *display* to Berlin local time; the underlying instant is unchanged.
- `isdst` on a `POSIXlt` is **positive** if DST is in force, **zero** if not, **negative** if unknown.
- `%Z` is documented as platform-specific and locale-dependent ("Time zone abbreviation as a character string (empty if not available)") — unsuitable when we need a guaranteed German abbreviation.

Empirically verified on the dev host:

```
summer (2026-07-15 12:00 UTC):  isdst = 1, local = 14:00, %Z = CEST
winter (2026-01-15 12:00 UTC):  isdst = 0, local = 13:00, %Z = CET
fall-back ambiguity:            two distinct instants both render 02:30,
                                isdst flips 1 → 0 across the boundary
```

This confirms `isdst > 0 ↔ MESZ` and `isdst <= 0 ↔ MEZ` is correct, including across the fall-back ambiguity (the wall clock repeats but the underlying UTC instants differ, so `isdst` distinguishes them).

## Change

Single file: `ShinyApp/app.R`. Two lines.

**Line 18** — convert mtime to Berlin time explicitly:

```r
updatetime <- as.POSIXlt(file.mtime("data/Ergebnis.Rds"), tz = "Europe/Berlin")
```

**Line 130** — drop `%Z`, append abbreviation derived from `isdst`. Include a one-line comment documenting the negative-`isdst` fall-through, so a future reader knows it's intentional:

```r
paste("Letztes Update: ",
      format(updatetime, "%d.%m.%Y %H:%M"),
      " ",
      # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
      if (updatetime$isdst > 0) "MESZ" else "MEZ",
      sep = "")
```

No new packages. No Dockerfile or deploy-script changes. No host TZ assumptions.

## Edge cases

- **`isdst < 0` ("unknown").** Documented as "couldn't determine"; for a concrete `file.mtime` value with a named TZ it should not occur in practice. The `> 0` test routes negative values to `MEZ`, which is the safer default (at worst, one hour of label drift twice a year). Documented inline.
- **File missing.** `file.mtime` on a missing path returns `NA`; `NA > 0` is `NA` and would break the `if`. Pre-existing behavior: the app already errors at line 17 (`load("data/Ergebnis.Rds")`) before reaching this code path, so this is not a new failure mode. **Out of scope.**
- **Host TZ / locale.** Irrelevant once we pass `tz = "Europe/Berlin"` explicitly. Behavior is identical on ShinyApps.io, in Docker, and on local Mac/Linux dev.

## Testing

Add `tests/testthat/test-shiny/test-footer-timezone.R`. The abbreviation logic is the only thing worth pinning — wrap it (or test it inline) with two known UTC instants and assert the rendered abbreviation:

- Summer instant → `MESZ`
- Winter instant → `MEZ`

The test must not depend on host TZ; it constructs `POSIXct` values with `tz = "UTC"` and converts via `as.POSIXlt(..., tz = "Europe/Berlin")` exactly as the app does.

No Shiny session is required — this is plain string/date logic.

## Out of scope

- Refactoring the footer's `paste(...)` into a helper function.
- Localizing other timestamps (logs, scheduler messages) — none are user-facing.
- Adding `lubridate` or any other tz library; base R is sufficient.

## References

- Issue [#103](https://github.com/chrisschwer/League-Simulator-Update/issues/103)
- R docs: [`DateTimeClasses`](https://stat.ethz.ch/R-manual/R-devel/library/base/html/DateTimeClasses.html), [`as.POSIXlt`](https://stat.ethz.ch/R-manual/R-devel/library/base/html/as.POSIXlt.html), [`strptime`](https://stat.ethz.ch/R-manual/R-devel/library/base/html/strptime.html) (for `%Z` semantics)
