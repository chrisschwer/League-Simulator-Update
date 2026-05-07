# Season-transition cassette fixtures (2024 → 2025)

Captured api-football response set + expected CSV snapshot for the
end-to-end test at `tests/testthat/test-season-transition-csv-snapshot.R`.

## Files

- `<host>/<path>.json` — `httptest` cassettes; each represents one HTTP GET
  the season-transition script issues.
- `TeamList_2025.csv.snapshot` — expected byte-exact output of the script.
- `_record.R` — the recording harness. Not picked up by testthat.

## Re-recording

Required when:
- the api-football response shape changes
- `scripts/season_transition.R` issues new HTTP calls
- the expected CSV output legitimately changes (e.g., new league rules)

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
