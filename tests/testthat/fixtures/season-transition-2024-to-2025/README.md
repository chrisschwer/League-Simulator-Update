# Season-transition cassette fixtures (2024 → 2025)

Captured api-football response set + expected CSV snapshot for the
end-to-end test at `tests/testthat/test-season-transition-csv-snapshot.R`.

## Files

- `api-football-v1.p.rapidapi.com/<path>.json` — `httptest` cassettes; each
  represents one HTTP GET the season-transition script issues.
- `localhost-8080/league-details-*-POST.json` — the Rust engine's
  `/league-details` responses. Since issue #146 part 2 the season transition
  gets its end-of-season ELOs from the engine instead of computing them in R,
  so these carry the ELO physics the snapshot depends on. They were recorded
  against a **real** running server; the test itself needs none.
- `TeamList_2025.csv.snapshot` — expected byte-exact output of the script.
- `_record.R` — the recording harness. Not picked up by testthat.

## Re-recording

Required when:
- the api-football response shape changes
- `scripts/season_transition.R` issues new HTTP calls
- the expected CSV output legitimately changes (e.g., new league rules)
- the `/league-details` payload or the model constants change — the cassette
  key is a hash of the request body, so any payload change makes `httptest`
  report a missing cassette

**Two hosts, two sources.** `_record.R` replays nothing: it hits the real
api-football API and needs `RAPIDAPI_KEY`. The `/league-details` cassettes
additionally need a **running Rust server** on port 8080
(`cargo build --release && PORT=8080 ./target/release/league-simulator-rust --api`).
Recording only the engine half — keeping the existing api-football cassettes
and paying no API quota — is possible: drive `calculate_final_elos()` with a
`fixtures_fn` that reads the existing cassettes, wrapped in
`httptest::capture_requests()`. That is how the current set was produced.

Procedure:

```bash
export RAPIDAPI_KEY=your_key_here
Rscript tests/testthat/fixtures/season-transition-2024-to-2025/_record.R

# Minify the captured cassettes so the diff stays small. jq -c is
# semantics-preserving — httptest reads minified JSON identically.
for f in tests/testthat/fixtures/season-transition-2024-to-2025/**/*.json; do
  jq -c . "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

Then inspect the captured files (`grep -rni rapidapi .` should return nothing
about the actual key value) and `git add` the changes. Re-run
`Rscript -e 'testthat::test_file("tests/testthat/test-season-transition-csv-snapshot.R")'`
to confirm the byte-identical CSV assertion still holds against the new
recording.
