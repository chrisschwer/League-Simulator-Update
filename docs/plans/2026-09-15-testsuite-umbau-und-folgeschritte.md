# Testsuite-Umbau (#211) und Folgeschritte — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die 63 testthat-Dateien, die nach PRs und Phasen benannt sind, in eine Struktur „eine Datei je `RCode/`-Einheit" überführen — **ohne** dabei eine einzige Erwartung zu ändern —, danach Redundanzen mit Christophs Freigabe abbauen (#211) und erst dann die Abdeckungslücken schließen (#212).

**Architecture:** Drei strikt getrennte Stufen. Stufe 1 legt die Zielstruktur fest (maschinell hergeleitete Zuordnung Testblock → Einheit, von Christoph freigegeben, in Doku und Memory). Stufe 2 verschiebt Testblöcke 1:1 und beweist per Vorher/Nachher-Abgleich der Einzelergebnisse, dass nichts anders läuft. Stufe 3 ist Review: je Doppel-Cluster ein kleiner PR, der nennt, welche Erwartung bleibt und welche fällt. Erst danach #212.

**Tech Stack:** R 4.6 / testthat 3 (`ListReporter` für den Ergebnisabgleich), `withr`, `git mv`; Rust-Tests unberührt.

**Spec:** Issue #211 (Struktur, Doppel-Cluster, Unabhängigkeitsrisiken), Issue #212 (Lücken, hohle Tests), Review-Bericht `~/.claude/plans/jolly-munching-token.md` (N8, N9), Christophs Vorgabe vom 15.09.2026: zweistufig — erst Struktur, dann 1:1 verschieben, dann grün beweisen, erst dann Redundanz-Review.

## Global Constraints

- Ab Testfreigabe keine Teständerung ohne Rückfrage (Christophs Regel). In Stufe 2 heißt das: **kein `expect_*` wird geändert, entfernt oder ergänzt**; erlaubt sind nur Verschieben, Umbenennen der Datei und das Zusammenführen identischer Helfer-Definitionen, die in derselben Datei doppelt landen würden.
- Bestehende Zusicherung bleibt beweisbar: Vorher/Nachher-Abgleich der Einzeltests (Name, Anzahl Erwartungen, Ergebnis) muss identisch sein; Abweichungen sind ein Stopp, kein Fix.
- Sprache in Repo-Dateien: Deutsch (Commits, Kommentare, Doku), wie im Repo üblich.
- Jeder Commit endet mit `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` und `Claude-Session: <URL der Sitzung>`.
- Die CI läuft nur `tests/testthat` und `cargo test`; alles, was hier gebaut wird, muss dort grün sein (`RAPIDAPI_KEY=dummy` lokal; ~20 Skips ohne Rust-Server/Fixture-Cache sind normal).

---

## Phase 0 — Vor dem Umbau (kleine, unabhängige Schritte)

Diese Punkte laufen **vor** Stufe 2, weil sie Tests berühren würden, die der Umbau verschiebt.

| Schritt | Was | Wer / Modell |
|---|---|---|
| 0.1 | #222 mergen (Christoph). Danach #216 schließen, Branch `fix/204-fehlpfad-wartet` löschen. | Christoph / Claude |
| 0.2 | Deploy auf Eddie nach dem Deploy-Skill, sobald das Image zum `main`-Kopf auf Docker Hub liegt (Monitor läuft). | Sonnet-Agent |
| 0.3 | Rest von #209: die zwölf Kopien des „Nachbardatei finden"-Blocks entfernen, Sourcing in die zwei Einstiegspunkte (`updateScheduler.R`, `scripts/season_transition.R`), Registry-Literale (`csv_generation.R`, `transform_data.R:32/:132`, `elo_calibration.R:289-296`, `season_validation.R:31`, `elo_aggregation.R:534-543`) durch Registry-Lookups ersetzen, Batch-Endpunkt + `simulate_leagues_batch_rust` löschen. Eigener PR, schließt #209. | Sonnet-Agent |
| 0.4 | R-Teile von #214: Malus-Lauf nur für Staffeln, deren `top$source` ihn liest; `generate_static_site.R` in Seitengerüst + `render_sections.R` teilen; Vier-Argument-Signatur zurückbauen, `preview_site.R` auf die `ergebnisse`-Liste. Eigener PR, schließt #214. **Wichtig:** der Split bestimmt die Zieldatei-Namen der Sektions-Tests (Task 1 unten rechnet damit). | Sonnet-Agent |

Reihenfolge: 0.1 → 0.2 parallel zu 0.3; 0.4 nach 0.3 (beide berühren den Loop). Stufe 1 kann parallel zu 0.3/0.4 laufen, Stufe 2 erst danach.

---

## Stufe 1 (#211a) — Zielstruktur festlegen

### Task 1: Zuordnung Testblock → Einheit maschinell herleiten

**Files:**
- Create: `scripts/dev/test_zuordnung.R` (Werkzeug, nicht Produktivpfad; nach `docs/user-guide/` Konvention dokumentiert in Task 2)
- Create: `docs/plans/2026-09-15-testsuite-zuordnung.csv` (Ergebnis, wird in Task 2 zur Tabelle)

**Interfaces:**
- Produces: CSV mit den Spalten `datei_alt, test_that_titel, zeile_von, zeile_bis, funktionen, einheit_vorschlag, einheit_final, bemerkung`. Task 3 liest genau diese Spalten; `einheit_final` ist die von Christoph bestätigte Zieldatei ohne `test-`-Präfix und ohne `.R`.

- [ ] **Step 1: Regeln der Zuordnung als Test festhalten**

`tests/testthat/test-dev-test-zuordnung.R` (wird in Stufe 2 nach `test-scripts-dev.R` verschoben):

```r
source_zuordnung <- function() {
  source(file.path("..", "..", "scripts", "dev", "test_zuordnung.R"), local = TRUE)
  environment()
}

test_that("ein Block, der nur Funktionen einer Einheit ruft, landet dort", {
  z <- source_zuordnung()
  index <- list(load_team_list = "transform_data", pruefe_kuerzel_vertrag = "transform_data")
  expect_identical(z$einheit_fuer(c("load_team_list", "pruefe_kuerzel_vertrag"), index),
                   "transform_data")
})

test_that("ein Block, der Funktionen mehrerer Einheiten ruft, bekommt die am haeufigsten gerufene", {
  z <- source_zuordnung()
  index <- list(build_league_table = "league_details",
                render_league_page = "generate_static_site",
                league_views = "league_views")
  expect_identical(z$einheit_fuer(c("build_league_table", "build_league_table", "league_views"), index),
                   "league_details")
})

test_that("ein Block ohne bekannte Funktion bekommt NA, keinen Rateversuch", {
  z <- source_zuordnung()
  expect_true(is.na(z$einheit_fuer(character(0), list())))
})

test_that("Grep-Tests auf Quelltext werden als architektur-waechter erkannt", {
  z <- source_zuordnung()
  body <- 'quelle <- readLines("../../RCode/league_registry.R"); expect_false(any(grepl("40", quelle)))'
  expect_identical(z$einheit_fuer_block(body, list()), "architektur-waechter")
})
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-dev-test-zuordnung.R")'`
Expected: FAIL, `scripts/dev/test_zuordnung.R` existiert nicht.

- [ ] **Step 3: Werkzeug schreiben**

`scripts/dev/test_zuordnung.R`:

```r
# Ordnet jeden test_that()-Block einer RCode-Einheit zu -- maschinell, als
# Vorschlag. Die Entscheidung trifft Christoph in der CSV (Spalte einheit_final).

funktionsindex <- function(rcode_dir = "RCode") {
  dateien <- list.files(rcode_dir, pattern = "\\.R$", full.names = TRUE)
  index <- list()
  for (f in dateien) {
    einheit <- sub("\\.R$", "", basename(f))
    zeilen <- readLines(f, warn = FALSE)
    treffer <- regmatches(zeilen, regexpr("^\\s*([.A-Za-z_][.A-Za-z0-9_]*)\\s*<-\\s*function", zeilen))
    namen <- sub("\\s*<-.*$", "", trimws(treffer))
    for (n in namen) index[[n]] <- einheit
  }
  index
}

gerufene_funktionen <- function(body, index) {
  kandidaten <- regmatches(body, gregexpr("[.A-Za-z_][.A-Za-z0-9_]*(?=\\()", body, perl = TRUE))[[1]]
  kandidaten[kandidaten %in% names(index)]
}

einheit_fuer <- function(funktionen, index) {
  if (length(funktionen) == 0) return(NA_character_)
  einheiten <- vapply(funktionen, function(f) index[[f]], character(1))
  names(sort(table(einheiten), decreasing = TRUE))[1]
}

einheit_fuer_block <- function(body, index) {
  if (grepl('readLines\\(.*RCode/', body) || grepl('readLines\\(.*tests/testthat/', body)) {
    return("architektur-waechter")
  }
  einheit_fuer(gerufene_funktionen(body, index), index)
}

testbloecke <- function(datei) {
  ausdruecke <- parse(datei, keep.source = TRUE)
  quelle <- attr(ausdruecke, "srcref")
  bloecke <- list()
  for (i in seq_along(ausdruecke)) {
    e <- ausdruecke[[i]]
    if (is.call(e) && identical(e[[1]], as.name("test_that"))) {
      sr <- quelle[[i]]
      bloecke[[length(bloecke) + 1]] <- list(
        titel = as.character(e[[2]]),
        von = sr[1], bis = sr[3],
        body = paste(as.character(sr), collapse = "\n")
      )
    }
  }
  bloecke
}

zuordnung_schreiben <- function(ziel = "docs/plans/2026-09-15-testsuite-zuordnung.csv") {
  index <- funktionsindex()
  dateien <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = TRUE)
  zeilen <- list()
  for (d in dateien) {
    for (b in testbloecke(d)) {
      fns <- gerufene_funktionen(b$body, index)
      zeilen[[length(zeilen) + 1]] <- data.frame(
        datei_alt = basename(d), test_that_titel = b$titel,
        zeile_von = b$von, zeile_bis = b$bis,
        funktionen = paste(unique(fns), collapse = " "),
        einheit_vorschlag = einheit_fuer_block(b$body, index),
        einheit_final = "", bemerkung = "",
        stringsAsFactors = FALSE
      )
    }
  }
  tabelle <- do.call(rbind, zeilen)
  utils::write.csv(tabelle, ziel, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(tabelle)
}

if (sys.nframe() == 0) zuordnung_schreiben()
```

- [ ] **Step 4: Test laufen lassen, muss bestehen**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-dev-test-zuordnung.R")'`
Expected: 4 PASS.

- [ ] **Step 5: Zuordnung erzeugen und Trefferquote prüfen**

Run: `Rscript scripts/dev/test_zuordnung.R && Rscript -e 'z <- read.csv("docs/plans/2026-09-15-testsuite-zuordnung.csv"); cat(nrow(z), "Bloecke,", sum(is.na(z$einheit_vorschlag) | z$einheit_vorschlag == ""), "ohne Vorschlag\n"); print(sort(table(z$einheit_vorschlag), decreasing = TRUE))'`
Expected: > 600 Blöcke; ohne Vorschlag < 10 % (Blöcke, die nur Helfer der Testdatei rufen). Diese von Hand zuordnen (Spalte `einheit_final`, `bemerkung` = Grund).

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/test_zuordnung.R tests/testthat/test-dev-test-zuordnung.R docs/plans/2026-09-15-testsuite-zuordnung.csv
git commit -m "chore(#211): Zuordnung Testblock -> RCode-Einheit maschinell herleiten"
```

### Task 2: Zielstruktur dokumentieren und freigeben lassen

**Files:**
- Create: `tests/testthat/README.md` (die Struktur, neben den Tests — dort sucht man sie)
- Modify: `CONTEXT.md` (ein Verweis unter „Conventions"/Decisions)
- Modify: `docs/user-guide/README.md` oder `docs/README.md` (Eintrag für `scripts/dev/test_zuordnung.R`)
- Memory: `project_testsuite_struktur.md` (Kurzfassung + Link auf README)

**Interfaces:**
- Produces: die Tabelle „Zieldatei ← Quelldateien" in `tests/testthat/README.md`; Task 3 arbeitet ausschließlich nach dieser Tabelle und der CSV aus Task 1.

- [ ] **Step 1: README schreiben**

Inhalt (Vorschlag, in Task 2 gegen die CSV abgeglichen und von Christoph bestätigt):

```markdown
# Struktur der Testsuite

Regel: **eine Testdatei je Einheit in `RCode/`**, benannt `test-<einheit>.R`
mit exakt dem Dateinamen der Einheit (`test-league_details.R` für
`RCode/league_details.R`). Tests für `scripts/` heißen `test-scripts-<name>.R`.
Meta-Tests, die Quelltext per grep prüfen, liegen in
`test-architektur-waechter.R`. Dateinamen nach Issues, PRs oder Phasen
(`-haertung`, `phase5`, `-move`) sind nicht erlaubt: Ein Test gehört zu der
Einheit, die er prüft, nicht zu der Änderung, die ihn veranlasst hat.

Gemeinsame Helfer stehen in `helper-*.R` (testthat lädt sie automatisch):
`helper-source.R` (`source_module("league_details")`), `helper-html.R`
(`read_html`, `make_data_env`), `helper-repo.R` (`with_repo_root`),
`helper-fixtures.R` (Spielpläne, TeamLists, `fake_fixtures`),
`helper-rust.R` (Fake-Rust-Server aus test-rl-verdrahtung, `start_rust_server`).

| Zieldatei | nimmt auf (Stand 15.09.2026) |
|---|---|
| test-transform_data.R | test-transform_data, test-teamlist-eindeutigkeit, test-kuerzel-vertrag, test-rundenfilter-schutznetz (Transform-Hälfte), test-elo-walk-reihenfolge (Transform-Hälfte), test-gewertete-spiele (Zeilen 200–238) |
| test-round_filter.R | test-rundenfilter-schutznetz (Filter-Hälfte) |
| test-league_details.R | test-fixture-details, test-fixture-details-produktionsform, test-spieltag-logik, test-gewertete-spiele (Fensterung/Tabelle), test-ligatabelle, test-league-details-client, test-league-details-client-haertung, test-league-page-data, -rueckblick, -ausblick, test-elo-walk-reihenfolge (Details-Hälfte) |
| test-rust_integration.R | test-home-advantage-single-source, test-tormodell-rust-durchreichung, test-rust-required (Server-Start), test-league-registry Zeile ~371 |
| test-league_registry.R | test-league-registry, test-frauen-ligen-aktivierung §1–2, test-phase5-regionalligen §1, test-n-ligen-entflechtung §1, test-rl-aufstieg (Registry-Slots), test-rl-zonen-verdrahtung (Regeltext) |
| test-league_views.R | test-league-views, test-frauen-ligen-live §1–2, test-phase5-regionalligen §2 |
| test-generate_static_site.R | test-generate-static-site, test-live-na-guard, test-rl-zonenlinien, test-rl-zonen-verdrahtung (Render-Hälfte), test-phase5-regionalligen §3–4, test-frauen-ligen-live §3, test-n-ligen-entflechtung §2 |
| test-render_sections.R (nach #214-Split; sonst Teil von generate_static_site) | test-ligatabelle-sektion, test-rueckblick-sektion, test-ausblick-sektion, test-score-matrix-farbskala |
| test-render_helpers.R | test-render-helpers-move |
| test-update_all_leagues_loop.R | test-update-loop-gating, test-update-loop-league-data, test-n-ligen-entflechtung §3, test-rl-verdrahtung (Loop-Verdrahtung), test-rust-required (Loop-Teil) |
| test-updateScheduler.R | test-frauen-ligen-aktivierung §Zeitfenster |
| test-checkAPILimits.R | test-check-api-limits, test-frauen-ligen-aktivierung Zeile ~151 |
| test-retrieveResults.R | test-retrieveResults |
| test-rl_abstiegskopplung.R | test-rl-abstiegskopplung, test-rl-nord-aufstiegskopplung |
| test-rl_aufstieg.R | test-rl-aufstieg (Rechenteil), test-phase5-regionalligen §4a |
| test-rl_verdrahtung.R | test-rl-verdrahtung (Verdrahtungsteil) |
| test-aufstiegsspiele.R | test-aufstiegsspiele |
| test-staffel_zuordnung.R | test-staffel-zuordnung |
| test-elo_aggregation.R | test-ein-elo-walk (ohne Meta-Tests) |
| test-elo_calibration.R | test-elo-calibration |
| test-fixture_cache.R | test-fixture-cache |
| test-season_processor.R | test-season-processor, test-season-transition-validators, test-season-transition-regression, test-saisonwechsel-schutzgrenzen, test-team-count-validation |
| test-csv_generation.R | test-saisonwechsel-format, test-saisonwechsel-entwurf |
| test-season_validation.R | test-season-validation |
| test-interactive_prompts.R | test-interactive-prompts, test-team-short-name (falls `get_team_short_name` dort liegt) |
| test-team_data_carryover.R / test-team_history_resolver.R / test-team_record_builder.R | gleichnamige Dateien |
| test-scripts-season_transition.R | test-season-transition-csv-snapshot, test-season-transition-cleanup-wrapper |
| test-scripts-preview_site.R | test-preview-site |
| test-scripts-dev.R | test-dev-test-zuordnung |
| test-architektur-waechter.R | test-modellkonstanten-nur-in-rust, test-ein-elo-walk Zeilen ~681/~704, test-frauen-ligen-aktivierung Zeile ~84 |
```

- [ ] **Step 2: Tabelle gegen die CSV abgleichen**

Run: `Rscript -e 'z <- read.csv("docs/plans/2026-09-15-testsuite-zuordnung.csv"); print(table(z$datei_alt, z$einheit_vorschlag)[, colSums(table(z$datei_alt, z$einheit_vorschlag)) > 0])'`
Jede Quelldatei, deren Blöcke sich auf mehrere Einheiten verteilen, in der README als „(Hälfte)" führen und in der CSV je Block `einheit_final` setzen.

- [ ] **Step 3: CONTEXT.md, Doku-Index, Memory**

CONTEXT.md unter „Decisions": `- Testsuite: eine Datei je RCode-Einheit, siehe tests/testthat/README.md (Entscheidung 2026-09-15, #211).`
Memory `project_testsuite_struktur.md`: Regel + Helfer-Liste + Link; `MEMORY.md`-Zeile.

- [ ] **Step 4: Freigabe einholen (Haltepunkt)**

PR (Draft) nur mit README, CONTEXT-Zeile, CSV und Werkzeug. **Christoph bestätigt die Tabelle**; erst danach Stufe 2. Änderungswünsche nur in README + CSV.

- [ ] **Step 5: Commit + PR**

```bash
git add tests/testthat/README.md CONTEXT.md docs/README.md
git commit -m "docs(#211): Zielstruktur der Testsuite festlegen"
gh pr create --draft --title "Testsuite: Zielstruktur (#211, Stufe 1)" --body-file <body>
```

---

## Stufe 2 (#211b) — Tests 1:1 verschieben und Gleichheit beweisen

### Task 3: Vorher-Aufnahme der Einzelergebnisse

**Files:**
- Create: `scripts/dev/test_ergebnisse.R`
- Create (gitignored, lokal): `tests/testthat/_baseline/vorher.csv`

**Interfaces:**
- Produces: CSV `test, expectations, failed, skipped, error` je `test_that`-Block, **ohne** Dateiname (der ändert sich). Task 5 vergleicht Vorher gegen Nachher auf Gleichheit der Mengen.

- [ ] **Step 1: Werkzeug schreiben**

```r
# scripts/dev/test_ergebnisse.R -- Einzelergebnisse je test_that()-Block als CSV.
# Aufruf: Rscript scripts/dev/test_ergebnisse.R <ziel.csv>
args <- commandArgs(trailingOnly = TRUE)
ziel <- if (length(args) >= 1) args[1] else "tests/testthat/_baseline/ergebnisse.csv"
dir.create(dirname(ziel), showWarnings = FALSE, recursive = TRUE)
Sys.setenv(RAPIDAPI_KEY = Sys.getenv("RAPIDAPI_KEY", "dummy"))
res <- testthat::test_dir("tests/testthat", reporter = "silent", stop_on_failure = FALSE)
df <- as.data.frame(res)
df <- df[, c("test", "nb", "failed", "skipped", "error")]
names(df) <- c("test", "expectations", "failed", "skipped", "error")
df <- df[order(df$test), ]
utils::write.csv(df, ziel, row.names = FALSE)
cat(nrow(df), "Bloecke,", sum(df$expectations), "Erwartungen,",
    sum(df$failed), "Fehlschlaege,", sum(df$skipped), "Skips\n")
```

- [ ] **Step 2: Vorher-Aufnahme auf dem Stand von `main` nach Phase 0**

Run: `Rscript scripts/dev/test_ergebnisse.R tests/testthat/_baseline/vorher.csv`
Expected: 0 Fehlschläge; Zahl der Blöcke und Erwartungen notieren (in den PR-Text).

- [ ] **Step 3: `_baseline/` in `.gitignore`, Commit des Werkzeugs**

```bash
echo "tests/testthat/_baseline/" >> .gitignore
git add scripts/dev/test_ergebnisse.R .gitignore
git commit -m "chore(#211): Einzelergebnisse der Testsuite als Vergleichsbasis aufnehmen"
```

### Task 4: Dateien verschieben — je Zieldatei ein Commit

**Files:**
- Modify/Rename: alle `tests/testthat/test-*.R` gemäß README-Tabelle
- Create: `helper-source.R`, `helper-html.R`, `helper-repo.R`, `helper-rust.R` (nur **Verschieben** identischer Helfer-Definitionen; Funktionskörper unverändert)

**Regeln für jeden Commit:**
1. Ganze Datei → `git mv` (Umbenennen), damit die Historie erhalten bleibt. Aufgeteilte Datei → die größere Hälfte per `git mv`, die kleinere Hälfte ausschneiden und **wortgleich** an das Ende der Zieldatei anhängen.
2. Helfer, die in der Zieldatei doppelt vorkämen (`source_generator`, `with_repo_root`, `read_html`, `make_data_env`, `fake_fixtures`, `fn`, `mk_ergebnis`, …): eine Kopie in die passende `helper-*.R`, **nur wenn die Kopien byteidentisch sind**; sonst umbenennen (`source_generator_phase5`) und in `bemerkung` der CSV notieren. Keine Vereinheitlichung in dieser Stufe.
3. Kein `expect_*`, kein `test_that`-Titel, kein Stub, kein Fixture wird angefasst. Ein `context()` (veraltet) darf entfallen, weil testthat 3 ihn ignoriert.
4. Nach jedem Commit: `Rscript -e 'testthat::test_file("tests/testthat/test-<ziel>.R")'` → 0 Fehlschläge.

- [ ] **Step 1–N: Reihenfolge der Commits** (klein → groß, damit Fehler früh auffallen)

1. Einzeldateien-Umbenennungen (`test-check-api-limits` → `test-checkAPILimits`, `test-elo-calibration` → `test-elo_calibration`, `test-fixture-cache` → `test-fixture_cache`, `test-staffel-zuordnung` → `test-staffel_zuordnung`, `test-season-validation` → `test-season_validation`, `test-team-history-resolver`, `test-team-record-builder`, `test-interactive-prompts`, `test-render-helpers-move` → `test-render_helpers`, `test-preview-site` → `test-scripts-preview_site`, `test-season-processor` → `test-season_processor`, `test-league-registry` → `test-league_registry`, `test-league-views` → `test-league_views`, `test-generate-static-site` → `test-generate_static_site`, `test-update-loop-gating` → `test-update_all_leagues_loop`, `test-rl-abstiegskopplung` → `test-rl_abstiegskopplung`, `test-rl-aufstieg` → `test-rl_aufstieg`, `test-rl-verdrahtung` → `test-rl_verdrahtung`, `test-ein-elo-walk` → `test-elo_aggregation`).
2. Zusammenführungen ganzer Dateien (je Zieldatei ein Commit): transform_data ← teamlist-eindeutigkeit + kuerzel-vertrag; league_details ← fixture-details + -produktionsform + spieltag-logik + ligatabelle + league-details-client + -haertung + league-page-data + -rueckblick + -ausblick; rust_integration ← home-advantage-single-source + tormodell-rust-durchreichung; update_all_leagues_loop ← update-loop-league-data; rl_abstiegskopplung ← rl-nord-aufstiegskopplung; season_processor ← season-transition-validators + -regression + saisonwechsel-schutzgrenzen + team-count-validation; csv_generation ← saisonwechsel-format + saisonwechsel-entwurf; scripts-season_transition ← season-transition-csv-snapshot + -cleanup-wrapper; render_sections (oder generate_static_site) ← ligatabelle-sektion + rueckblick-sektion + ausblick-sektion + score-matrix-farbskala; generate_static_site ← live-na-guard + rl-zonenlinien; architektur-waechter ← modellkonstanten-nur-in-rust.
3. Aufteilungen (je Quelldatei ein Commit, CSV-Zeilen als Schnittvorlage): gewertete-spiele, rundenfilter-schutznetz, elo-walk-reihenfolge, rl-zonen-verdrahtung, frauen-ligen-aktivierung, frauen-ligen-live, n-ligen-entflechtung, phase5-regionalligen, rust-required, ein-elo-walk (Meta-Tests → architektur-waechter).
4. Helfer-Dateien (ein Commit): byteidentische Kopien nach `helper-*.R`.

- [ ] **Step N+1: Vollständigkeit prüfen**

Run: `ls tests/testthat/test-*.R | sed 's|tests/testthat/test-||; s|\.R$||' | sort > /tmp/ist.txt; (ls RCode/*.R | sed 's|RCode/||; s|\.R$||'; echo scripts-season_transition; echo scripts-preview_site; echo scripts-dev; echo architektur-waechter) | sort > /tmp/soll.txt; comm -23 /tmp/ist.txt /tmp/soll.txt`
Expected: leer (keine Testdatei ohne Einheit). `comm -13` listet Einheiten ohne Tests — die gehören zu #212, nicht hierher.

### Task 5: Nachher-Aufnahme und Beweis der Gleichheit

- [ ] **Step 1: Nachher-Aufnahme**

Run: `Rscript scripts/dev/test_ergebnisse.R tests/testthat/_baseline/nachher.csv`

- [ ] **Step 2: Vergleich**

```r
# Rscript -e '<dieser Block>'
v <- read.csv("tests/testthat/_baseline/vorher.csv"); n <- read.csv("tests/testthat/_baseline/nachher.csv")
stopifnot(identical(sort(v$test), sort(n$test)))          # gleiche Blöcke
m <- merge(v, n, by = "test", suffixes = c("_v", "_n"))
diff <- m[m$expectations_v != m$expectations_n | m$failed_v != m$failed_n |
          m$skipped_v != m$skipped_n | m$error_v != m$error_n, ]
print(diff); stopifnot(nrow(diff) == 0)
cat("identisch:", nrow(m), "Bloecke,", sum(m$expectations_n), "Erwartungen\n")
```

Expected: `identisch: <N> Bloecke, <E> Erwartungen`, dieselben Zahlen wie in Task 3 Step 2. **Jede Abweichung ist ein Stopp**: zurück zum Commit, der sie verursacht (`git bisect` über die Commits von Task 4 mit dem Vergleichsskript als Test), Ursache benennen, nicht anpassen.

- [ ] **Step 3: Doppelte Titel prüfen**

Run: `Rscript -e 'n <- read.csv("tests/testthat/_baseline/nachher.csv"); print(n$test[duplicated(n$test)])'`
Expected: leer. (Gleiche `test_that`-Titel aus zwei Quelldateien in einer Zieldatei sind zulässig, aber sie sind die ersten Kandidaten für Stufe 3 — in die CSV-Spalte `bemerkung` eintragen.)

- [ ] **Step 4: CI**

Push, PR (Draft → nach grüner CI ready). PR-Text: Zahlen aus Task 3 und Task 5, Liste der Umbenennungen, Liste der Helfer-Verschiebungen, Liste der Kandidaten für Stufe 3.

- [ ] **Step 5: Merge durch Christoph, Memory aktualisieren**

---

## Stufe 3 (#211c) — Redundanz-Review, je Cluster ein PR

Erst jetzt werden Erwartungen angefasst — und nur mit Christophs Wort je PR. Reihenfolge nach Nutzen; die Cluster-Nummern verweisen auf Issue #211.

| PR | Cluster (aus #211) | Was bleibt | Was fällt (Vorschlag) |
|---|---|---|---|
| 3.1 | Kürzel-Vertrag (Cluster 1) | die Fassung aus kuerzel-vertrag (vollständiger) | die Doppelungen aus teamlist-eindeutigkeit für „gleiche Liga bricht ab", „Nord/Nordost/Bayern", „TeamID doppelt", „VFB/FCH/RWE" |
| 3.2 | home_advantage/Tormodell nicht gesendet (Cluster 2) | je ein Test für `/simulate` und `/league-details` in test-rust_integration | Wiederholungen in league_registry und league_details |
| 3.3 | `validate_team_count`-Grenze (Cluster 3) | ein Test mit der aktuellen Grenze (Christoph nennt sie) | die zwei anderen Werte |
| 3.4 | `league_views()`-Form (Cluster 6) + Seitenzahl (Cluster 7) | ein Test gegen die Registry | vier Wiederholungen mit hart kodierten Listen |
| 3.5 | Spieltag-Fensterung (Cluster 12) + Reihenfolge (Cluster 5) | spieltag-logik-Fassung | Join-Level-Wiederholungen |
| 3.6 | Unabhängigkeit: `setwd` → `withr::local_dir`, `options` → `withr::local_options`, `Sys.setenv` → `withr::local_envvar`, `sample()` → `set.seed`, produktive TeamList → Fixture | — | — (keine Erwartung fällt; Regression-Datei bekommt `on.exit`) |
| 3.7 | Rest (Cluster 4, 8–11, 13–15) | je Cluster die vollständigere Fassung | die andere |

Je PR: Tabelle „Test X fällt, weil Test Y dieselbe Erwartung hält (Datei:Zeile)". Vorher/Nachher-Zahlen wie in Task 5, diesmal mit **erwarteter** Abnahme der Erwartungen, die im PR-Text steht.

---

## Stufe 4 (#212) — Lücken schließen und hohle Tests ersetzen

Nach Stufe 3, in der neuen Struktur, je Punkt ein kleiner TDD-PR:

1. `test-updateScheduler.R`: die drei Zweige von `calculate_loops()` mit gestubbtem `Sys.time`/`Sys.sleep` (reine Rechenfunktion herauslösen: Jetzt-Zeit → Loops, Startwartezeit, Dauer) — die Berlin-Zeit-Frage gleich mit.
2. `test-retrieveResults.R`: `.record_rate_limit_headers()` mit und ohne Header (falls #222 das nicht schon abdeckt — prüfen).
3. Client-JS (Stale-Banner, Sortierung): Entscheidung Christoph — V8-Test oder JS in `site_assets/` auslagern und mit Node prüfen.
4. Methodik-, Fallback-Seite, Asset-Kopie: je eine Erwartung an die Ausgabe.
5. Hohle Tests ersetzen: `test-rust-required` (nur `exists()`), `test-interactive-prompts` (zwei unbedingte `skip()`), `test-league-page-data` (`is.function`), `test-season-validation` (acht Warnungen); `helper-test-setup.R`: `tryCatch` beim Sourcen → Fehler statt `message()`.
6. `Tabelle()` bekommt eigene Tests (seit #218 nur indirekt über den ELO-Walk).

---

## Selbstprüfung gegen die Vorgabe

- Zweistufig (Struktur → 1:1 → grün → Review): Stufe 1 = Struktur mit Freigabe-Haltepunkt; Stufe 2 = 1:1 mit Beweis; Stufe 3 = Review. ✓
- Struktur in Memory und Projektdoku: Task 2 (README, CONTEXT.md, Memory). ✓
- Danach #212: Stufe 4. ✓
- Offen für Christoph: (a) Split `render_sections.R` (#214, Phase 0.4) **vor** Stufe 2 oder danach — bestimmt einen Zieldateinamen; (b) Reihenfolge Stufe 3.1–3.7; (c) Client-JS-Testweg in Stufe 4.
