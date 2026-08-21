# Connect Cloud Migration — Design

**Date:** 2026-07-26
**Status:** **SUPERSEDED** by [`2026-07-26-static-site-generation-design.md`](2026-07-26-static-site-generation-design.md) — do not implement
**Trigger:** Posit email 2026-07-26 announcing shinyapps.io consolidation into Posit Connect Cloud

> **Why superseded:** this design assumed hosted Shiny was worth keeping. It is
> not — the app serves a 5.4 KB payload with no reactivity across three fixed
> views, and the simulator already runs self-hosted in the operator's homelab,
> so serving three static pages there costs nothing. Static generation removes
> the migration, the credentials, the rate-limit risk and the 13 USD/month
> entirely. Kept for the platform research (auth mechanisms, version floors,
> plan mapping), which remains accurate.

## Problem

Posit is retiring shinyapps.io in favour of Posit Connect Cloud. The account
(`chrisschwer`, **Starter plan, 13 USD/month**) will be force-migrated on
**2027-03-31** if not migrated voluntarily. A self-serve migration tool arrives
September 2026.

The Shiny application itself is unaffected — `ShinyApp/app.R` is a standard Shiny
app and runs on Connect Cloud unchanged. The problem is exclusively in the
**unattended deployment path**.

`RCode/updateShiny.R:37` authenticates with a static token/secret pair:

```r
rsconnect::setAccountInfo(name = account_name, token = account_token, secret = account_secret)
```

`setAccountInfo()` targets shinyapps.io and does not exist for Connect Cloud.
The publicised Connect Cloud replacement, `connectCloudUser()`, performs a
**browser-based handshake** ("without worrying about API key management") and is
therefore unusable from a headless container.

### Why this breaks quietly

The failure mode is the dangerous kind. `RCode/updateScheduler.R:6,16-18`
preflights only `SHINYAPPS_IO_SECRET` at startup — never `SHINYAPPS_IO_TOKEN`.
A broken deploy credential therefore surfaces hours later, inside the matchday
loop, not at container start. Viewers keep seeing the redirected app while the
data silently goes stale.

`updateShiny.R:59` compounds this: `setwd(curr_wd)` is not wrapped in
`on.exit()`, so a failing `deployApp()` leaves the process CWD inside
`ShinyApp/`, breaking the *next* loop iteration's relative `source("RCode/...")`
paths. A deploy-time error thus escalates into a scheduler-wide failure.

## Solution

Use `rsconnect::connectCloudClientCredentials()` — an OAuth 2.0
`client_credentials` grant against a Connect Cloud **service account**,
documented explicitly "to authenticate in non-interactive contexts".

```r
rsconnect::connectCloudClientCredentials(
  clientId     = Sys.getenv("CONNECT_CLOUD_CLIENT_ID"),
  clientSecret = Sys.getenv("CONNECT_CLOUD_CLIENT_SECRET"),
  accountName  = Sys.getenv("CONNECT_CLOUD_ACCOUNT", "chrisschwer")
)
```

This is a structural 1:1 replacement for the current pattern: three environment
variables in, `deployApp()` unchanged afterwards. Credentials are issued at
<https://login.posit.cloud/identity/credentials>.

### Version constraint

| Item | Value |
|---|---|
| `connectCloudClientCredentials` introduced | rsconnect **1.10.0** |
| Locally installed at analysis time | rsconnect 1.5.0 (lacks the function) |
| CRAN latest | rsconnect 1.10.1 |
| `packagelist.txt:14` | bare `rsconnect` — **unpinned** |

The unpinned dependency means the Docker build installs whichever version CRAN
serves on build day. Pinning `rsconnect (>= 1.10.0)` is part of this migration,
not an afterthought.

### Plan mapping and cost

Starter maps to Connect Cloud **Basic**, with current pricing and authorized
user count held **until 2029**. Basic is also the tier that permits deployment
from private GitHub repositories and offers higher memory than Free. Relevant
detail: the **Free** plan deploys only from *public* GitHub repos, so the paid
plan is not merely a convenience here — it underpins the chosen approach.

## Architecture

Introduce a thin **deployment backend seam** in `RCode/updateShiny.R`, selected
by one environment variable:

```
SHINY_DEPLOY_TARGET = shinyapps | connectcloud     (default: shinyapps)
```

Two small functions behind one interface:

- `authenticate_shinyapps()` — reads `SHINYAPPS_IO_{NAME,TOKEN,SECRET}`, calls `setAccountInfo()`
- `authenticate_connectcloud()` — reads `CONNECT_CLOUD_{ACCOUNT,CLIENT_ID,CLIENT_SECRET}`, calls `connectCloudClientCredentials()`

`updateShiny()` resolves the backend, calls the matching authenticator, then
proceeds to the existing save-and-`deployApp()` logic unchanged.

**Why a seam rather than a straight replacement:** it allows both backends to be
live simultaneously, so Connect Cloud can be validated against the real
simulation pipeline while shinyapps.io continues serving production. Rollback is
an environment-variable flip, not a code revert. The seam is deliberately
minimal — two functions and a `switch()`, no plugin registry.

### Credential validation moves to startup

Extend the `updateScheduler.R` preflight to validate the credentials of the
*selected* backend — including the token, which is currently unchecked. This
converts the silent mid-loop failure into a loud startup failure.

### Correctness fixes in scope

Both are in the file being modified and are the exact failure class a migration
provokes:

1. Wrap the CWD restore in `on.exit(setwd(curr_wd), add = TRUE)` so a failed
   deploy cannot corrupt subsequent loop iterations.
2. Replace the hardcoded `directory` default (`updateShiny.R:3-7`), which points
   at a `Dropbox-CSDataScience` path that does not exist in this checkout, with
   a repo-relative default.

Explicitly **out of scope**: the redeploy-per-cycle architecture, `app.R`
changes, and the stale `tests/container-shiny.yaml` / `docs/GITHUB_ACTIONS_CONFIG.md`
cleanup beyond removing now-wrong shinyapps references.

## Open questions requiring empirical verification

Posit's documentation does not answer these; the plan resolves them by testing
rather than assuming.

1. **Deployment rate limit.** `updateScheduler.R:80` schedules a loop every 2
   minutes from 14:45–22:45 — up to ~241 full-bundle redeploys per matchday.
   No rate limit is documented anywhere for Connect Cloud. This is the largest
   residual risk. If a limit exists, the mitigation is to gate redeploys on a
   content hash of the results (skip deploy when unchanged), which is a
   worthwhile change regardless.
2. **Migration-tool behaviour for rsconnect-deployed apps.** Posit's docs
   describe GitHub-centric flows; behaviour for an app published via
   `deployApp()` bundles is unstated.
3. **`connectCloudClientCredentials` availability in practice.** It appears in
   the rsconnect reference but not in the Connect Cloud "What's New" changelog.

## Testing strategy

`tests/testthat/test-updateShiny-env.R` currently covers only missing-credential
hard-fails for shinyapps.io. Extend it to cover both backends:

- shinyapps backend: missing token / missing secret still hard-fail (regression)
- connectcloud backend: missing client id / client secret / account hard-fail
- backend selection: unknown `SHINY_DEPLOY_TARGET` fails with an actionable message
- default remains `shinyapps` when the variable is unset (no behaviour change)
- CWD is restored even when the deploy step throws (`on.exit` regression test)

All assertions fire before any network call, so no rsconnect mocking is needed —
matching the existing test's approach of passing `directory = tempdir()`.

Manual verification gate: one real Connect Cloud deploy triggered from a local R
session with `SHINY_DEPLOY_TARGET=connectcloud`, confirming the app renders and
reads its bundled `data/Ergebnis.Rds`.

## Timeline

Migration tool ships September 2026; hard deadline 2027-03-31, which falls
mid-Rückrunde. The work should land in the summer break, where a failed deploy
affects nobody. Sequence: implement the seam now → validate against Connect
Cloud when the tool ships in September → flip the default → decommission the
shinyapps path once stable.

## Rejected alternatives

**Wait for automatic migration (2027-03-31).** Zero work now, but the cutover
lands mid-season and the failure is silent (redirect works, deploys fail, data
ages). Worst combination of bad timing and low observability.

**Leave the platform** (self-hosted Shiny in the container, or static
pre-rendered output). Solves the dependency permanently but is a separate
project, and discards a plan whose price is frozen until 2029.

## References

- Announcement: <https://posit.co/blog/migrating-connect-cloud-posits-unified-publishing-solution>
- Migration guide: <https://docs.posit.co/shinyapps.io/guide/migration/>
- `connectCloudClientCredentials`: <https://rstudio.github.io/rsconnect/reference/connectCloudClientCredentials.html>
- rsconnect NEWS: <https://cran.r-project.org/web/packages/rsconnect/news/news.html>
- Connect Cloud plans: <https://docs.posit.co/connect-cloud/user/account/plans.html>
