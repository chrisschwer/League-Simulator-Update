# Static Site

After each simulation cycle the scheduler renders four pages into
`STATIC_SITE_DIR` (default `ShinyApp/public`, `/app/ShinyApp/public` in the
container). A plain web server serves that directory — there is no Shiny
runtime, no `rsconnect`, and no deployment credentials.

This replaced the shinyapps.io deployment in August 2026. Background:
[ADR 0001](../adr/0001-statische-seiten-statt-gehostetem-shiny.md) and the
[design](../superpowers/specs/2026-07-26-static-site-generation-design.md).

## Output

```
ShinyApp/public/
├── index.html          # Bundesliga
├── 2-bundesliga.html
├── 3-liga.html
├── methodik.html       # Methodik, content from RCode/site_assets/methodik_content.html
└── assets/
    ├── site.css
    ├── favicon.svg
    └── fonts/*.woff2
```

There are no PNGs — the probability heatmap is an HTML table with a
per-cell background colour, generated inline by
[`RCode/generate_static_site.R`](../../RCode/generate_static_site.R).

Total size is a few hundred KB. Writes are idempotent, so regenerating every
2 minutes during a matchday costs nothing.

The pages are self-contained. The "stale" banner (data older than 24 h) is
decided **in the browser**: each page embeds its generation time in
`<time id="generated" datetime="…">` and a few lines of inline JS reveal the
hidden banner. A page that is no longer re-rendered therefore still warns
its readers.

## Serving it (production: named volume + Caddy)

The scheduler and the web server share a Docker **named volume**. The
reference `docker-compose.yml` in this repo mounts it at the output directory:

```yaml
    volumes:
      - fussball-site:/app/ShinyApp/public
volumes:
  fussball-site:
    external: true
```

Create the volume once on the host. The image already contains
`/app/ShinyApp/public` owned by `appuser` (uid 1001), so Docker seeds a fresh
volume with the right ownership; the `chown` is a belt-and-braces step for
volumes created by other means:

```bash
docker volume create fussball-site
docker run --rm -v fussball-site:/v alpine chown 1001:1001 /v
```

Mount the same volume read-only into the Caddy container and serve it:

```yaml
# web server compose file
services:
  caddy:
    volumes:
      - fussball-site:/srv/fussball:ro
volumes:
  fussball-site:
    external: true
```

```caddyfile
fussball.example.org {
    root * /srv/fussball
    file_server
    encode zstd gzip
    header /assets/* Cache-Control "public, max-age=300"
    header *.html Cache-Control "no-cache"
}
```

Restart Caddy after adding the volume (`docker compose up -d caddy`) and
validate with `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile`.
Until the first render, copy a placeholder `index.html` into the volume so the
address never answers 404.

## Deployment host layout

```
/opt/<host>/fussball/
├── compose.yml   # copy of this repo's docker-compose.yml, image pinned to :<sha>
└── .env          # RAPIDAPI_KEY=…, SEASON=2026   (chmod 600)
```

Images are built by CI on every push to `main` and pushed as
`chrisschwer/league-simulator:latest` and `:<sha>`. On the host only **pull**;
pin `image:` to the `<sha>` tag and update deliberately (no `latest`, no
auto-updater).

```bash
cd /opt/<host>/fussball
docker compose pull && docker compose up -d
docker compose logs -f scheduler
```

## Verifying

```bash
docker compose ps                                   # fussball-scheduler healthy
docker run --rm -v fussball-site:/v alpine ls -la /v  # 4 HTML + assets/, owner 1001
curl -sI https://fussball.example.org/              # 200, Cache-Control: no-cache
curl -s  https://fussball.example.org/ | grep -c Saisonprognose
```

Check the logs for the first loop at 14:45 **MESZ/MEZ** — `TZ=Europe/Berlin`
is load-bearing for the scheduler's wall-clock window.

## Generating manually

```bash
Rscript -e '
  source("RCode/generate_static_site.R")
  e <- new.env(); load("ShinyApp/data/Ergebnis.Rds", envir = e)
  generate_static_site(e$Ergebnis, e$Ergebnis2, e$Ergebnis3, e$Ergebnis3_Aufstieg)
'
```

Inside the container: `docker compose exec scheduler Rscript -e '…'` with the
same snippet.

## Rollback

There is no code-level rollback to shinyapps.io — the deploy path was removed
(ADR 0001). During a migration, keep the previous container running on the
old host until the new one has served a full matchday; that container is the
rollback.

## Local preview

There is no Shiny app to preview against — `ShinyApp/app.R` and the Shiny
dependency were removed with the relaunch. To preview the generated site
locally, render it with [`scripts/preview_site.R`](../../scripts/preview_site.R)
and open the printed path in a browser:

```bash
Rscript scripts/preview_site.R
```

By default it reads `ShinyApp/data/Ergebnis.Rds` and renders into a fresh
`tempdir()`; pass an alternate `Ergebnis.Rds` path and/or output directory as
arguments.
