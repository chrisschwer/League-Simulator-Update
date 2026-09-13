# Rollback

Roll back to a previous version of the League Simulator.

> The League Simulator runs as a single Docker container with no database. Rollback is "stop the current container, run a previous image, restart" — no schema migrations, no blue-green, no traffic-shifting.

## Decide what to roll back

| Symptom | What to roll back |
|---|---|
| Container won't start, health check fails | The Docker image (Section A) |
| Container is up but produces wrong simulation results | The Docker image (Section A) |
| Container is up but the schedule or env config is wrong | `docker-compose.yml` / `.env` by hand (Section B) |
| You want to read the pre-#78 deployment surface (multi-Dockerfile, k8s) for reference | The git tag (Section C, read-only) |

## A. Roll back the Docker image (primary path)

Images are built by CI on every push to `main` and published as
`chrisschwer/league-simulator:latest` and `:<sha>`. The deploy host pins
`image:` to a specific `<sha>` in its compose file (see
[Static Site](static-site.md#deployment-host-layout)) — rolling back means
pointing that pin at a previous, known-good sha and restarting.

```bash
# 1. Stop the running container.
docker-compose down

# 2. Pin docker-compose.yml to the previous image sha.
#    (Edit the `image:` line under `scheduler`.)
$EDITOR docker-compose.yml

# 3. Pull that exact tag and bring it up.
docker-compose pull
docker-compose up -d

# 4. Verify.
docker-compose ps
docker-compose logs -f scheduler
```

## B. Roll back configuration only

`.env` is gitignored and never committed, so there is no git history to
restore it from. If the schedule or env config is wrong, hand-edit
`.env` and/or `docker-compose.yml` on the host to the known-good values
(see [Deployment Overview](README.md#required-environment-variables) for
the reference table), then restart — no rebuild needed:

```bash
docker-compose down
docker-compose up -d
```

## C. Reference: the pre-cleanup deployment surface (read-only)

The repo has one annotated tag preserving the deployment surface before the
single-container collapse in #78:

```bash
git checkout pre-deployment-cleanup-2026-05-02
```

This tag captures the multi-Dockerfile + `k8s/` tree as of 2026-05-02. You
will *not* be able to `docker-compose up` from that tag — the file layout is
different, and production images now come from CI, not a local build. Use it
for reading old manifests, not for running anything.

## After rolling back

Watch the logs for one full simulation cycle:

```bash
docker-compose logs -f scheduler
```

If the rollback was driven by a real bug, file an issue describing what you observed before and after, and consider whether the bug needs a regression test before re-deploying `main`.
