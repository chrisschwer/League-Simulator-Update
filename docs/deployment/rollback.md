# Rollback

Roll back to a previous version of the League Simulator.

> The League Simulator runs as a single Docker container with no database. Rollback is "stop the current container, run a previous image, restart" — no schema migrations, no blue-green, no traffic-shifting.

## Decide what to roll back

| Symptom | What to roll back |
|---|---|
| Container won't start, `curl localhost:8081/health` fails | The Docker image (Section A) |
| Container is up but produces wrong simulation results | The Docker image (Section A) |
| Container is up but the schedule or env config is wrong | `.env` and/or `docker-compose.yml` (Section B) |
| You want to compare against the pre-#78 deployment surface (multi-Dockerfile, k8s) | The git tag (Section C) |

## A. Roll back the Docker image

If you tag your images at deploy time (recommended), you have a previous tag to roll back to.

```bash
# 1. Stop the running container.
docker-compose down

# 2. Pin docker-compose.yml to the previous image tag.
#    (Edit the `image:` line under `league-simulator-integrated`.)
$EDITOR docker-compose.yml

# 3. Bring the previous version up.
docker-compose up -d

# 4. Verify.
docker-compose ps
curl http://localhost:8081/health
docker-compose logs -f league-simulator-integrated
```

If you don't tag images and just rebuild from `main`, you're rolling back code, not images — see Section C below.

## B. Roll back configuration only

```bash
# Inspect the previous .env from git history.
git log -p .env

# Restore an earlier version (or hand-edit .env to match).
git checkout HEAD~1 -- .env  # or a specific commit

# Restart with the new config — no rebuild needed.
docker-compose down
docker-compose up -d
```

## C. Roll back to a previous git tag and rebuild

This is the path when you don't have versioned Docker images and need to run the code as it was at a previous commit.

```bash
# Inspect tags.
git tag -l

# Check out the tag.
git checkout <tag-name>

# Rebuild and run.
docker-compose up -d --build

# When you're done debugging, return to main.
git checkout main
docker-compose up -d --build
```

### Reference tag

The repo has one annotated tag preserving the pre-cleanup deployment surface:

```bash
git checkout pre-deployment-cleanup-2026-05-02
```

This tag captures the multi-Dockerfile + `k8s/` tree as of 2026-05-02, before the deployment-collapse work in #78. You will *not* be able to `docker-compose up` directly from that tag (the file layout is different); use it for reference reading only.

## After rolling back

Watch the logs for one full simulation cycle:

```bash
docker-compose logs -f league-simulator-integrated
```

If the rollback was driven by a real bug, file an issue describing what you observed before and after, and consider whether the bug needs a regression test before re-deploying `main`.
