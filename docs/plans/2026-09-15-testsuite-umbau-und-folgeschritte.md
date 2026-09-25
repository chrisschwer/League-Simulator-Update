# Testsuite-Umbau (#211) und Folgeschritte — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die 67 testthat-Dateien (777 `test_that`-Blöcke, Stand 25.09.2026), heute überwiegend nach PRs, Phasen und Anlässen benannt, in die Struktur `test-<einheit>[-<thema>].R` überführen — **ohne** dabei eine einzige Erwartung zu ändern —, danach Redundanzen mit Christophs Freigabe abbauen (#211) und erst dann die Abdeckungslücken schließen (#212).

**Architecture:** Drei strikt getrennte Stufen. Stufe 1 legt die Zielstruktur fest (maschinell hergeleitete Zuordnung Testblock → Einheit, von Christoph freigegeben, in Doku und Memory). Stufe 2 verschiebt Testblöcke 1:1, baut einen Wächtertest, der die Namensregel künftig erzwingt, und beweist per Vorher/Nachher-Abgleich der Einzelergebnisse, dass nichts anders läuft. Stufe 3 ist Review: je Doppel-Cluster ein kleiner PR, der nennt, welche Erwartung bleibt und welche fällt. Erst danach #212.

**Tech Stack:** R 4.6 / testthat 3 (`ListReporter` für den Ergebnisabgleich), `withr`, `git mv`; Rust-Tests (`cargo test`, 76 Tests) unberührt.

**Spec:** Issue #211 (Struktur, Doppel-Cluster, Unabhängigkeitsrisiken; Kommentar vom 24.09. zum Generator-Split), Issue #212 (Lücken, hohle Tests), Review-Bericht `~/.claude/plans/jolly-munching-token.md` (N8, N9), Christophs Vorgabe vom 15.09.2026: zweistufig — erst Struktur, dann 1:1 verschieben, dann grün beweisen, erst dann Redundanz-Review. Überarbeitet am 25.09.2026 nach einem unabhängigen Gutachten (Fable): Namensregel mit optionalem Thema-Segment, Wächtertest, Zieltabelle auf den Stand 25.09., robusteres Beweisverfahren, geänderte Reihenfolge.

## Global Constraints

- Ab Testfreigabe keine Teständerung ohne Rückfrage (Christophs Regel). In Stufe 2 heißt das: **kein `expect_*` wird geändert, entfernt oder ergänzt**; erlaubt sind nur Verschieben, Umbenennen der Datei, das Zusammenführen byteidentischer Helfer-Definitionen und das **Nachführen von Stringliteralen, die eine umbenannte Testdatei benennen** (heute: `test-ein-elo-walk.R:694` liest `test-rust-required.R`, `:719` den Snapshot-Runner). Jede solche Nachführung steht einzeln im PR-Text.
- Neu hinzukommen darf in Stufe 2 genau ein Test: der Struktur-Wächter (Task 5). Er prüft Dateinamen, keine Produktivlogik.
- Bestehende Zusicherung bleibt beweisbar: Vorher/Nachher-Abgleich der Einzeltests (Name, Anzahl Erwartungen, Ergebnis) als **Multimenge** muss identisch sein; Abweichungen sind ein Stopp, kein Fix.
- Sprache in Repo-Dateien: Deutsch (Commits, Kommentare, Doku), wie im Repo üblich.
- Jeder Commit endet mit der Co-Authored-By-Zeile des ausführenden Modells und `Claude-Session: <URL der Sitzung>`.
- Die CI läuft nur `tests/testthat` (nicht rekursiv, `ci.yml:184`) und `cargo test`; alles, was hier gebaut wird, muss dort grün sein (`RAPIDAPI_KEY=dummy` lokal; ~20 Skips ohne Rust-Server/Fixture-Cache sind normal).

## Die Zielregel (wird in Task 2 wörtlich nach `tests/testthat/README.md` übernommen)

> **Der Dateiname sagt, welche Einheit geprüft wird — nie, welche Änderung den Test veranlasst hat.**
>
> `test-<einheit>.R` oder `test-<einheit>-<thema>.R`
> - `<einheit>` ist exakt der Dateistamm einer Datei in `RCode/` (`league_details`, `updateScheduler`) — oder eines der festen Präfixe `scripts` (dann folgt der Stamm einer Datei unter `scripts/`: `test-scripts-preview_site.R`) oder `waechter` (Meta-Tests, die Quelltext als Text lesen). Einheitsnamen enthalten keinen Bindestrich; alles bis zum ersten Bindestrich nach `test-` ist daher die Einheit.
> - `<thema>` ist optional und benennt eine Funktion oder ein Verhalten der Einheit (`-gating`, `-rueckblick`, `-verdrahtung`); nie Issue, PR, Phase oder Reparatur (`phase5`, `haertung`, `move`, `fix`, Nummern). Ein Thema lohnt sich, wenn die Datei sonst deutlich über ~1.000 Zeilen wüchse oder die Tests eigene Helfer/Fakes brauchen.
> - Zuordnung im Zweifel: die Einheit, deren Funktion der Test aufruft und deren Ergebnis er prüft; rufen mehrere, die äußerste (der Aufrufer). Gestubbte oder nur gesourcte Mitspieler zählen nicht.
> - Jede Testdatei sourct ihre Einheit selbst. Gemeinsame Helfer heißen `helper-<zweck>.R` (testthat lädt sie automatisch); keine Helferdefinition in zwei Dateien. Unterordner (`fixtures/`, `helpers/`) enthalten nur Daten und explizit gesourcte Runner, nie Tests — testthat liest sie nicht.
> - Wird eine `RCode/`-Datei geteilt, umbenannt oder gelöscht, ziehen ihre Testdateien im selben PR mit (`git mv`); `test-waechter-teststruktur.R` schlägt sonst fehl.
> - Neue Testarten bekommen ein festes Präfix, das in `test-waechter-teststruktur.R` in die geschlossene Liste aufgenommen wird (absehbar: `js` für Client-JS, #212).
> - Ausführen einer Einheit mit allen Themen: `testthat::test_dir("tests/testthat", filter = "^league_details")`.

**Warum diese Form (verworfene Alternativen):** Sortierung nach Feature/Anlass ist der Ist-Zustand und hat die 15 Doppel-Cluster erzeugt. Unterordner je Ebene (unit/integration/render) liest `test_dir()` nicht rekursiv — genau so sind früher Dateien unsichtbar geworden. Ebenen-Präfixe (`test-unit-…`) klassifizieren doppelt und lassen im Zweifel zwei richtige Namen zu. Strikt „eine Datei je Einheit" ergäbe Dateien von ~4.000 (Loop), ~3.100 (Generator) und ~1.800 Zeilen (Details) und zwänge gleichnamige, aber verschiedene Helfer (`fake_fixtures` in 4, `read_html` in 5 Varianten) in eine Datei.

---

## Phase 0 — Vor dem Umbau

| Schritt | Was | Stand / Wer |
|---|---|---|
| 0.1 | #222 mergen, #216 schließen | ✓ erledigt |
| 0.2 | Deploy auf Eddie | ✓ erledigt (Pin `9c71147`) |
| 0.3 | Rest von #209 (Sourcing-Block-Kopien, Registry-Literale, Batch-Endpunkt) | **entkoppelt:** eigener PR, jederzeit; keine Voraussetzung für Stufe 2. Läuft er zuerst, entfallen Sourcing-Zeilen in Testköpfen — dann Vorher-Aufnahme (Task 4) erst danach. |
| 0.4 | `RCode/generate_static_site.R` teilen: Seitengerüst, Aufstiegsseite, `generate_static_site()` bleiben; ab Zeile 1113 (`.komma` … Sektionsrenderer Ligatabelle, Zonen, Rückblick, Live, Ausblick) nach `RCode/render_sections.R`. Reine Verschiebung, Sourcing in den Aufrufern und den ~zehn Testdateien, die den Generator laden, nachziehen. Vier-Argument-Pfad **nicht** anfassen (Redundanz-Review). Eigener PR unter #211. **Vor Stufe 1 Task 1**, weil die Zuordnung sonst gegen die alte Einheit rechnet. | Sonnet-Agent |
| 0.5 | Unabhängigkeit herstellen (vorgezogen aus der alten Stufe 3.6): in den 13 Dateien, die Arbeitsverzeichnis, Umgebung oder Optionen ohne Rückbau ändern (u. a. `test-season-transition-regression.R` 4×, `test-rust-required.R` 6×), `setwd` → `withr::local_dir`, `Sys.setenv` → `withr::local_envvar`, `options` → `withr::local_options`, `sample()` ohne Seed → `withr::local_seed`. **Kein `expect_*` ändert sich.** Grund: testthat läuft alphabetisch, das Umbenennen ändert die Reihenfolge; leckender Zustand ließe Stufe 2 an Altlasten stoppen statt an Verschiebefehlern. Nachweis wie Task 6 (Multimenge vor/nach). | Sonnet-Agent |
| 0.6 | Altlasten außerhalb von `tests/testthat/`: `tests/issue-31-test-specifications.md` löschen (Spezifikation eines erledigten Issues); prüfen, ob `tests/TeamList_2024.csv` noch gelesen wird (sonst löschen). **Nicht im Repo, nur lokal** (per `.gitignore:30/:56` ausgeschlossen): `tests/rust/` (Rust-vs-C++-Vergleichsskripte, laufen nicht mehr, weil die C++-Engine seit #102 fehlt) und `tests/test_poisson_fix.R` — Christoph löscht sie in seinem Checkout selbst oder gibt es frei. | Claude |

Reihenfolge: 0.4 und 0.5 nacheinander (beide fassen Testköpfe an), 0.6 beliebig. Stufe 1 startet nach 0.4, Stufe 2 nach 0.5.

---

## Stufe 1 (#211a) — Zielstruktur festlegen

### Task 1: Zuordnung Testblock → Einheit maschinell herleiten

**Files:**
- Create: `scripts/dev/test_zuordnung.R` (Werkzeug, nicht Produktivpfad; dokumentiert in Task 2)
- Create: `docs/plans/2026-09-15-testsuite-zuordnung.csv` (Ergebnis, wird in Task 2 zur Tabelle)

**Interfaces:**
- Produces: CSV mit den Spalten `datei_alt, einheit_source, test_that_titel, zeile_von, zeile_bis, funktionen, einheit_vorschlag, ziel_final, bemerkung`. `einheit_source` ist die Einheit, die der Dateikopf per `source()` lädt (bei 60 von 67 Dateien genau eine — der stärkere Beleg); `einheit_vorschlag` die Stimme aus den gerufenen Funktionen. Weichen beide ab, steht das in `bemerkung`. `ziel_final` ist die von Christoph bestätigte Zieldatei ohne `test-` und `.R` (also `<einheit>` oder `<einheit>-<thema>`). Task 3 liest genau diese Spalten.

- [ ] **Step 1: Regeln der Zuordnung als Test festhalten**

`tests/testthat/test-scripts-test_zuordnung.R` (heißt schon nach der Zielregel):

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

test_that("Grep-Tests auf Quelltext werden als waechter erkannt", {
  z <- source_zuordnung()
  body <- 'quelle <- readLines("../../RCode/league_registry.R"); expect_false(any(grepl("40", quelle)))'
  expect_identical(z$einheit_fuer_block(body, list()), "waechter")
})

test_that("die per source() geladene Einheit wird aus dem Dateikopf gelesen", {
  z <- source_zuordnung()
  kopf <- c('source(test_path("..", "..", "RCode", "league_details.R"))',
            'source("../../RCode/render_helpers.R")')
  expect_identical(z$gesourcte_einheiten(kopf), c("league_details", "render_helpers"))
})
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scripts-test_zuordnung.R")'`
Expected: FAIL, `scripts/dev/test_zuordnung.R` existiert nicht.

- [ ] **Step 3: Werkzeug schreiben**

`scripts/dev/test_zuordnung.R`:

```r
# Ordnet jeden test_that()-Block einer RCode-Einheit zu -- maschinell, als
# Vorschlag. Die Entscheidung trifft Christoph in der CSV (Spalte ziel_final).

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

gesourcte_einheiten <- function(zeilen) {
  treffer <- regmatches(zeilen, regexpr("RCode[\"/, ]+\"?[A-Za-z_]+\\.R", zeilen))
  unique(sub("\\.R$", "", sub(".*[\"/ ]", "", treffer)))
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
    return("waechter")
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
    src <- paste(gesourcte_einheiten(readLines(d, warn = FALSE)), collapse = " ")
    for (b in testbloecke(d)) {
      fns <- gerufene_funktionen(b$body, index)
      vorschlag <- einheit_fuer_block(b$body, index)
      zeilen[[length(zeilen) + 1]] <- data.frame(
        datei_alt = basename(d), einheit_source = src, test_that_titel = b$titel,
        zeile_von = b$von, zeile_bis = b$bis,
        funktionen = paste(unique(fns), collapse = " "),
        einheit_vorschlag = vorschlag,
        ziel_final = "",
        bemerkung = if (!is.na(vorschlag) && nzchar(src) && !grepl(vorschlag, src, fixed = TRUE))
          "source und Funktionsstimme weichen ab" else "",
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

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scripts-test_zuordnung.R")'`
Expected: 5 PASS.

- [ ] **Step 5: Zuordnung erzeugen und Trefferquote prüfen**

Run: `Rscript scripts/dev/test_zuordnung.R && Rscript -e 'z <- read.csv("docs/plans/2026-09-15-testsuite-zuordnung.csv"); cat(nrow(z), "Bloecke,", sum(is.na(z$einheit_vorschlag) | z$einheit_vorschlag == ""), "ohne Vorschlag,", sum(nzchar(z$bemerkung)), "Abweichungen source/Stimme\n"); print(sort(table(z$einheit_vorschlag), decreasing = TRUE))'`
Expected: ≈ 780 Blöcke (777 + 5 neue); ohne Vorschlag < 10 %. Blöcke ohne Vorschlag und alle Abweichungen von Hand nach der Zweifelsregel entscheiden (`ziel_final`, `bemerkung` = Grund).

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/test_zuordnung.R tests/testthat/test-scripts-test_zuordnung.R docs/plans/2026-09-15-testsuite-zuordnung.csv
git commit -m "chore(#211): Zuordnung Testblock -> RCode-Einheit maschinell herleiten"
```

### Task 2: Zielstruktur dokumentieren und freigeben lassen

**Files:**
- Create: `tests/testthat/README.md` (die Struktur, neben den Tests — dort sucht man sie)
- Modify: `CONTEXT.md` (ein Verweis unter Decisions)
- Modify: `docs/README.md` oder `docs/user-guide/README.md` (Eintrag für `scripts/dev/test_zuordnung.R` und `scripts/dev/test_ergebnisse.R`)
- Memory: `project_testsuite_struktur.md` (Kurzfassung + Link auf README)

**Interfaces:**
- Produces: die Tabelle „Zieldatei ← Quelldateien" in `tests/testthat/README.md`; Task 3 arbeitet ausschließlich nach dieser Tabelle und der CSV aus Task 1.

- [ ] **Step 1: README schreiben**

Inhalt: die Zielregel oben (wörtlich), dann die Helferliste, dann die Tabelle. Die Tabelle ist ein Vorschlag auf dem Stand 25.09.2026 (nach 0.4-Split); Task 2 Step 2 gleicht sie gegen die CSV ab, Christoph bestätigt.

**Helfer** (Bestand bleibt, neu nur durch Verschieben byteidentischer Kopien):

| Datei | Inhalt |
|---|---|
| `helper-test-setup.R` | Bestand (globale Sourcing-Wand `source_rcode_modules`; wird in Stufe 4 auf „Fehler statt `message()`" umgestellt) |
| `helper-fixtures.R` | Bestand (`create_test_season`, …) |
| `helper-league-details.R` | Bestand (`fd_row`, `make_details`, `make_test_teams`) |
| `helper-uhr.R` | Bestand (`runden_uhr`) |
| `helper-source.R` | neu: `source_generator` u. ä., sofern byteidentisch |
| `helper-html.R` | neu: `make_data_env`, `read_html`, sofern byteidentisch |
| `helper-repo.R` | neu: `with_repo_root`, sofern byteidentisch |
| `helper-rust.R` | neu: Fake-Rust-Server, sofern mehr als eine Datei ihn nutzt |
| `helpers/season-transition-snapshot-runner.R` | Bestand, explizit gesourcter Runner (kein Test) |

**Zieltabelle:**

| Zieldatei | nimmt auf |
|---|---|
| test-transform_data.R | test-transform_data, test-rundenfilter-schutznetz (Transform-Hälfte), test-elo-walk-reihenfolge (Transform-Hälfte), test-gewertete-spiele (Zeilen 200–238) |
| test-transform_data-kuerzel.R | test-kuerzel-vertrag, test-teamlist-eindeutigkeit (bilden Cluster 1 — liegen damit für Stufe 3.1 nebeneinander) |
| test-round_filter.R | test-rundenfilter-schutznetz (Filter-Hälfte) |
| test-league_details.R | test-fixture-details, test-fixture-details-produktionsform, test-spieltag-logik, test-gewertete-spiele (Fensterung/Tabelle), test-elo-walk-reihenfolge (Details-Hälfte), test-tbd-termin (Details-Hälfte, ruft `extract_fixture_details`) |
| test-league_details-client.R | test-league-details-client, test-league-details-client-haertung |
| test-league_details-tabelle.R | test-ligatabelle |
| test-league_details-seitendaten.R | test-league-page-data, test-league-page-data-rueckblick, test-league-page-data-ausblick |
| test-rust_integration.R | test-home-advantage-single-source, test-tormodell-rust-durchreichung, test-rust-required (Server-Start), test-league-registry Block ~Zeile 371 |
| test-league_registry.R | test-league-registry, test-frauen-ligen-aktivierung §1–2, test-phase5-regionalligen §1, test-n-ligen-entflechtung §1, test-rl-aufstieg (Registry-Slots), test-rl-zonen-verdrahtung (Regeltext) |
| test-league_views.R | test-league-views, test-frauen-ligen-live §1–2, test-phase5-regionalligen §2 |
| test-generate_static_site.R | test-generate-static-site, test-live-na-guard, test-phase5-regionalligen §3–4, test-frauen-ligen-live §3, test-n-ligen-entflechtung §2 |
| test-render_sections-tabelle.R | test-ligatabelle-sektion |
| test-render_sections-zonen.R | test-rl-zonenlinien, test-rl-zonen-verdrahtung (Render-Hälfte) |
| test-render_sections-rueckblick.R | test-rueckblick-sektion |
| test-render_sections-ausblick.R | test-ausblick-sektion, test-tbd-termin (Ausblick-Hälfte) |
| test-render_sections-farbskala.R | test-score-matrix-farbskala |
| test-render_sections-tooltip.R | test-kuerzel-tooltip (Generator-Blöcke; Blöcke, die nur `league_details` prüfen, laut CSV nach test-league_details.R; ob Tooltip-Renderer nach dem Split in `render_sections` oder im Seitengerüst liegen, entscheidet die CSV) |
| test-render_helpers.R | test-render-helpers-move |
| test-update_all_leagues_loop.R | test-update-loop-league-data, test-n-ligen-entflechtung §3, test-rust-required (Loop-Teil) |
| test-update_all_leagues_loop-gating.R | test-update-loop-gating (1.750 Z., mockery-Stubs) |
| test-update_all_leagues_loop-sicherheitsnetz.R | test-sicherheitsnetz-zeit |
| test-update_all_leagues_loop-verdrahtung.R | test-rl-verdrahtung (Loop-Verdrahtung mit Fake-Rust-Server) |
| test-rl_verdrahtung.R | test-rl-verdrahtung (Teil, der `RCode/rl_verdrahtung.R` direkt prüft) |
| test-updateScheduler.R | test-frauen-ligen-aktivierung §Zeitfenster |
| test-checkAPILimits.R | test-check-api-limits, test-frauen-ligen-aktivierung Block ~Zeile 151 |
| test-rate_limit_takt.R | test-rate-limit-takt |
| test-retrieveResults.R | test-retrieveResults |
| test-retrieveResults-rate-limit-header.R | test-rate-limit-header |
| test-api_service.R | test-team-short-name (`get_team_short_name` liegt in `api_service.R`) |
| test-rl_abstiegskopplung.R | test-rl-abstiegskopplung, test-rl-nord-aufstiegskopplung |
| test-rl_aufstieg.R | test-rl-aufstieg (Rechenteil), test-phase5-regionalligen §4a |
| test-aufstiegsspiele.R | test-aufstiegsspiele |
| test-staffel_zuordnung.R | test-staffel-zuordnung |
| test-elo_aggregation.R | test-ein-elo-walk (ohne Meta-Tests) |
| test-elo_calibration.R | test-elo-calibration |
| test-fixture_cache.R | test-fixture-cache |
| test-season_processor.R | test-season-processor, test-season-transition-validators, test-saisonwechsel-schutzgrenzen, test-team-count-validation |
| test-season_processor-regression.R | test-season-transition-regression (700 Z., eigenes Fixture-Gerüst) |
| test-csv_generation.R | test-saisonwechsel-format, test-saisonwechsel-entwurf |
| test-season_validation.R | test-season-validation |
| test-interactive_prompts.R | test-interactive-prompts |
| test-team_history_resolver.R | test-team-history-resolver |
| test-team_record_builder.R | test-team-record-builder |
| test-scripts-season_transition.R | test-season-transition-csv-snapshot, test-season-transition-cleanup-wrapper |
| test-scripts-preview_site.R | test-preview-site |
| test-scripts-test_zuordnung.R | (neu aus Task 1) |
| test-scripts-test_ergebnisse.R | (neu aus Task 4, falls das Werkzeug Tests bekommt) |
| test-waechter-modellkonstanten.R | test-modellkonstanten-nur-in-rust, test-frauen-ligen-aktivierung Block ~Zeile 84 |
| test-waechter-elo-walk.R | test-ein-elo-walk Meta-Blöcke (~Zeilen 694, 719) |
| test-waechter-teststruktur.R | (neu aus Task 5) |

**Einheiten ohne Testdatei nach dem Umbau** (gehören zu #212, nicht hierher): `input_handler`, `team_data_carryover`, `Tabelle`.

- [ ] **Step 2: Tabelle gegen die CSV abgleichen**

Run: `Rscript -e 'z <- read.csv("docs/plans/2026-09-15-testsuite-zuordnung.csv"); t <- table(z$datei_alt, z$einheit_vorschlag); print(t[, colSums(t) > 0])'`
Jede Quelldatei, deren Blöcke sich auf mehrere Einheiten verteilen, in der README als „(Hälfte)" führen und in der CSV je Block `ziel_final` setzen. Zusätzlich: für jede Zusammenführung prüfen, ob gleichnamige Helfer **nicht** byteidentisch sind (`grep -n "^<name> <- function"` + Vergleich). Kollidieren sie, bekommt die kleinere Quelle ein eigenes Thema statt Umbenennung — die Tabelle wird entsprechend angepasst.

- [ ] **Step 3: CONTEXT.md, Doku-Index, Memory**

CONTEXT.md unter Decisions: `- Testsuite: test-<einheit>[-<thema>].R je RCode-Einheit, erzwungen durch test-waechter-teststruktur.R; siehe tests/testthat/README.md (Entscheidung 2026-09-25, #211).`
Memory `project_testsuite_struktur.md`: Regel + Helferliste + Link; `MEMORY.md`-Zeile.

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

### Task 3: Umgebung festschreiben

Vorher- und Nachher-Aufnahme müssen unter **derselben** Umgebung laufen, sonst wandern Skips und der Vergleich misst die Umgebung statt des Umbaus.

- [ ] **Step 1:** Umgebung wählen und im PR-Text protokollieren: Rust-Server an (`league-simulator-rust --api`, Health auf `:8080`) **oder** aus — empfohlen **an**, damit die 11 Dateien, die sich ohne Server überspringen, mitgeprüft werden; `data/fixture_cache/` vorhanden ja/nein (2 Dateien hängen daran); `RAPIDAPI_KEY=dummy`; Paketversionen von `testthat`, `mockery`, `withr`, `sys` (`Rscript -e 'sessionInfo()'` in den PR).

### Task 4: Vorher-Aufnahme der Einzelergebnisse

**Files:**
- Create: `scripts/dev/test_ergebnisse.R`
- Create (gitignored, lokal): `tests/testthat/_baseline/vorher.csv`

**Interfaces:**
- Produces: CSV `test, expectations, failed, skipped, error` je `test_that`-Block, **ohne** Dateiname (der ändert sich). Task 6 vergleicht Vorher gegen Nachher als Multimenge.

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
df <- df[do.call(order, df), ]
utils::write.csv(df, ziel, row.names = FALSE)
cat(nrow(df), "Bloecke,", sum(df$expectations), "Erwartungen,",
    sum(df$failed), "Fehlschlaege,", sum(df$skipped), "Skips\n")
```

- [ ] **Step 2: Vorher-Aufnahme auf dem Stand von `main` nach Phase 0**

Run: `Rscript scripts/dev/test_ergebnisse.R tests/testthat/_baseline/vorher.csv`
Expected: 0 Fehlschläge; Zahl der Blöcke und Erwartungen in den PR-Text.

- [ ] **Step 3: `_baseline/` in `.gitignore`, Commit des Werkzeugs**

```bash
echo "tests/testthat/_baseline/" >> .gitignore
git add scripts/dev/test_ergebnisse.R .gitignore
git commit -m "chore(#211): Einzelergebnisse der Testsuite als Vergleichsbasis aufnehmen"
```

### Task 5: Struktur-Wächter

**Files:**
- Create: `tests/testthat/test-waechter-teststruktur.R`

Der Wächter wird **zuerst** geschrieben und läuft am Anfang rot (heute passen 49 Dateinamen nicht). Er ist das Abnahmekriterium von Task 6 und hält die Regel danach dauerhaft.

- [ ] **Step 1: Wächter schreiben**

```r
# Erzwingt die Namensregel aus tests/testthat/README.md:
# test-<einheit>[-<thema>].R, <einheit> = Stamm einer RCode-Datei oder festes Praefix.

repo <- function(...) test_path("..", "..", ...)
praefixe <- c("scripts", "waechter")
einheiten <- sub("\\.R$", "", list.files(repo("RCode"), pattern = "\\.R$"))
skripte <- sub("\\.R$", "", basename(list.files(repo("scripts"), pattern = "\\.R$", recursive = TRUE)))
testdateien <- list.files(test_path(), pattern = "^test-.*\\.R$")
stamm <- sub("^test-", "", sub("\\.R$", "", testdateien))
einheit_von <- sub("-.*$", "", stamm)

test_that("jede Testdatei beginnt mit einer RCode-Einheit oder einem festen Praefix", {
  falsch <- testdateien[!einheit_von %in% c(einheiten, praefixe)]
  expect_identical(falsch, character(0))
})

test_that("test-scripts-* nennt ein existierendes Skript", {
  s <- stamm[einheit_von == "scripts"]
  skript <- sub("^scripts-", "", s)
  expect_identical(s[!skript %in% skripte], character(0))
})

test_that("kein Dateiname nennt Anlass, Phase oder Issue", {
  # ganze Segmente, damit test-fixture_cache.R nicht als "fix" gilt
  verboten <- "(^|-)(fix|move|haertung|issue)(-|$)|phase[0-9]|[0-9]{3}"
  expect_identical(testdateien[grepl(verboten, stamm)], character(0))
})

test_that("jede Einheiten-Testdatei sourct ihre Einheit", {
  pruefen <- testdateien[einheit_von %in% einheiten]
  ohne <- pruefen[!vapply(seq_along(pruefen), function(i) {
    e <- einheit_von[testdateien == pruefen[i]]
    any(grepl(paste0("\\b", e, "\\.R\\b|source_module\\(\"", e, "\""),
              readLines(test_path(pruefen[i]), warn = FALSE), perl = TRUE))
  }, logical(1))]
  expect_identical(ohne, character(0))
})

test_that("kein Top-Level-Name ist in einer Testdatei doppelt definiert", {
  doppelt <- unlist(lapply(c(testdateien, list.files(test_path(), pattern = "^helper-.*\\.R$")), function(d) {
    ausdruecke <- parse(test_path(d))
    namen <- unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
    if (any(duplicated(namen))) paste0(d, ": ", unique(namen[duplicated(namen)]))
  }))
  expect_identical(doppelt, NULL)
})

test_that("keine Helferdefinition steht in zwei helper-Dateien", {
  helfer <- list.files(test_path(), pattern = "^helper-.*\\.R$")
  namen <- unlist(lapply(helfer, function(d) {
    ausdruecke <- parse(test_path(d))
    unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
  }))
  expect_identical(unique(namen[duplicated(namen)]), character(0))
})
```

- [ ] **Step 2: Laufen lassen, muss rot sein** (erwartet: Liste der heutigen Fehlbenennungen). Commit mit dem Wächter zusammen mit dem ersten Verschiebe-Commit, damit `main` nie rot ist — oder im Branch rot lassen, bis Task 6 fertig ist; gemergt wird nur grün.

### Task 6: Dateien verschieben — je Zieldatei ein Commit

**Files:**
- Modify/Rename: alle `tests/testthat/test-*.R` gemäß README-Tabelle
- Create: `helper-source.R`, `helper-html.R`, `helper-repo.R`, `helper-rust.R` (nur **Verschieben** byteidentischer Helfer-Definitionen; Funktionskörper unverändert)

**Regeln für jeden Commit:**
1. Ganze Datei → `git mv` (Historie bleibt). Aufgeteilte Datei → die größere Hälfte per `git mv`, die kleinere Hälfte **wortgleich** an das Ende der Zieldatei anhängen.
2. „1:1" gilt für Blöcke, **nicht** für Dateiköpfe: `library(...)`, `source(...)` und Top-Level-Konstanten (z. B. `namen` in `test-kuerzel-tooltip.R:18`) werden beim Zusammenführen geteilter Zustand. Jeder Kopf wird mitgenommen; Namenskollisionen fängt der Wächter (doppelte Top-Level-Namen). Kollidieren nicht-identische Helfer oder Konstanten, wird **nicht** umbenannt, sondern die Quelle bekommt ein eigenes Thema (Rückfrage an Christoph, Tabelle nachführen).
3. Helfer, die byteidentisch in mehreren Zieldateien stehen (`source_generator`, `make_data_env`, …), wandern in die passende `helper-*.R`. Keine Vereinheitlichung nicht-identischer Varianten in dieser Stufe.
4. Kein `expect_*`, kein `test_that`-Titel, kein Stub, kein Fixture wird angefasst. Ausnahmen: ein `context()` (veraltet) darf entfallen; Stringliterale, die eine umbenannte Testdatei benennen, werden nachgeführt und im PR-Text einzeln gelistet. Kommentare, die alte Testdateinamen nennen (~52), werden mitgeführt, wo sie im selben Commit ohnehin berührt werden; sonst bleiben sie für Stufe 3.
5. Nach jedem Commit **Einzellauf und Gesamtlauf**: `Rscript -e 'testthat::test_file("tests/testthat/test-<ziel>.R")'` und `Rscript scripts/dev/test_ergebnisse.R /tmp/zwischen.csv` → 0 Fehlschläge. (Der Einzellauf fängt fehlendes Sourcing, der Gesamtlauf Reihenfolgeeffekte.)

- [ ] **Step 1–N: Reihenfolge der Commits** (klein → groß, damit Fehler früh auffallen)

1. Reine Umbenennungen ganzer Dateien (ein Commit je 5–8 Dateien, Liste aus der README-Tabelle: alle Zeilen mit genau einer Quelle ohne „Hälfte").
2. Zusammenführungen ganzer Dateien, je Zieldatei ein Commit (alle Zeilen mit mehreren Quellen ohne „Hälfte").
3. Aufteilungen, je Quelldatei ein Commit, CSV-Zeilen als Schnittvorlage: gewertete-spiele, rundenfilter-schutznetz, elo-walk-reihenfolge, rl-zonen-verdrahtung, rl-verdrahtung, tbd-termin, kuerzel-tooltip, frauen-ligen-aktivierung, frauen-ligen-live, n-ligen-entflechtung, phase5-regionalligen, rust-required, ein-elo-walk (Meta-Blöcke → waechter-elo-walk).
4. Helfer-Dateien (ein Commit): byteidentische Kopien nach `helper-*.R`.

- [ ] **Step N+1: Wächter grün**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-waechter-teststruktur.R")'`
Expected: alle Blöcke PASS.

### Task 7: Nachher-Aufnahme und Beweis der Gleichheit

- [ ] **Step 1: Nachher-Aufnahme** (gleiche Umgebung wie Task 3)

Run: `Rscript scripts/dev/test_ergebnisse.R tests/testthat/_baseline/nachher.csv`

- [ ] **Step 2: Vergleich als Multimenge**

Titel sind nicht eindeutig (heute schon doppelt: „Bayern summiert exakt auf zwei Absteiger…" und „Nord und Bayern stellen zusammen genau einen Aufsteiger" in `test-phase5-regionalligen.R` und `test-rl-verdrahtung.R`). Deshalb kein Schlüssel-Merge, sondern Vergleich der sortierten Zeilen:

```r
# Rscript -e '<dieser Block>'
v <- read.csv("tests/testthat/_baseline/vorher.csv", stringsAsFactors = FALSE)
n <- read.csv("tests/testthat/_baseline/nachher.csv", stringsAsFactors = FALSE)
# einzige zulaessige Zusatzzeilen: die Bloecke des Waechters aus Task 5
ex <- parse("tests/testthat/test-waechter-teststruktur.R")
waechter <- unlist(lapply(ex, function(e) if (is.call(e) && identical(e[[1]], as.name("test_that"))) e[[2]]))
stopifnot(!any(waechter %in% v$test))
n <- n[!n$test %in% waechter, ]
zeilen <- function(d) sort(do.call(paste, c(d, sep = "\r")))   # Multimenge: sortierte Zeilen
nur_vorher <- setdiff(zeilen(v), zeilen(n)); nur_nachher <- setdiff(zeilen(n), zeilen(v))
print(nur_vorher); print(nur_nachher)
stopifnot(identical(zeilen(v), zeilen(n)))
cat("identisch:", nrow(v), "Bloecke,", sum(v$expectations), "Erwartungen\n")
```

Expected: `identisch: <N> Bloecke, <E> Erwartungen`, dieselben Zahlen wie Task 4 Step 2. **Jede Abweichung ist ein Stopp**: zurück zum Commit, der sie verursacht (`git bisect` über die Commits von Task 6 mit dem Vergleich als Test), Ursache benennen, nicht anpassen.

- [ ] **Step 3: Doppelte Titel notieren**

Run: `Rscript -e 'n <- read.csv("tests/testthat/_baseline/nachher.csv"); print(unique(n$test[duplicated(n$test)]))'`
Doppelte Titel sind zulässig, aber die ersten Kandidaten für Stufe 3 — in die CSV-Spalte `bemerkung`.

- [ ] **Step 4: CI**

Push, PR (Draft → nach grüner CI ready). PR-Text: Umgebung (Task 3), Zahlen aus Task 4 und Task 7, Liste der Umbenennungen, der nachgeführten Stringliterale, der Helfer-Verschiebungen, der Kandidaten für Stufe 3.

- [ ] **Step 5: Merge durch Christoph, Memory aktualisieren**

---

## Stufe 3 (#211c) — Redundanz-Review, je Cluster ein PR

Erst jetzt werden Erwartungen angefasst — und nur mit Christophs Wort je PR. Reihenfolge nach Nutzen; die Cluster-Nummern verweisen auf Issue #211.

| PR | Cluster (aus #211) | Was bleibt | Was fällt (Vorschlag) |
|---|---|---|---|
| 3.1 | Kürzel-Vertrag (Cluster 1) — beide Quellen liegen in `test-transform_data-kuerzel.R` | die Fassung aus kuerzel-vertrag (vollständiger) | die Doppelungen aus teamlist-eindeutigkeit für „gleiche Liga bricht ab", „Nord/Nordost/Bayern", „TeamID doppelt", „VFB/FCH/RWE" |
| 3.2 | home_advantage/Tormodell nicht gesendet (Cluster 2) | je ein Test für `/simulate` und `/league-details` in test-rust_integration | Wiederholungen in league_registry und league_details |
| 3.3 | `validate_team_count`-Grenze (Cluster 3) | ein Test mit der aktuellen Grenze (Christoph nennt sie) | die zwei anderen Werte |
| 3.4 | `league_views()`-Form (Cluster 6) + Seitenzahl (Cluster 7) | ein Test gegen die Registry | vier Wiederholungen mit hart kodierten Listen |
| 3.5 | Spieltag-Fensterung (Cluster 12) + Reihenfolge (Cluster 5) | spieltag-logik-Fassung | Join-Level-Wiederholungen |
| 3.6 | Helfer vereinheitlichen: nicht-identische Varianten (`fake_fixtures` 4×, `with_repo_root` 3×, `read_html` 5×) zusammenführen, wo sie dasselbe tun; ein zentrales `skip_if_no_rust()` in `helper-rust.R` statt vier Skip-Varianten | — | — (keine Erwartung fällt; Skip-Bedingungen werden gleich, das wird per Multimenge belegt) |
| 3.7 | Vier-Argument-Pfad von `generate_static_site()` (`test-n-ligen-entflechtung.R:129,154`, `test-generate-static-site.R:392` — nach Stufe 2 in den neuen Dateien) | — | die drei Kompatibilitätstests samt Pfad, wenn Christoph zustimmt |
| 3.8 | Rest (Cluster 4, 8–11, 13–15) | je Cluster die vollständigere Fassung | die andere |

Je PR: Tabelle „Test X fällt, weil Test Y dieselbe Erwartung hält (Datei:Zeile)". Vorher/Nachher-Multimenge wie in Task 7, diesmal mit **erwarteter** Abnahme, die im PR-Text steht.

---

## Stufe 4 (#212) — Lücken schließen und hohle Tests ersetzen

Nach Stufe 3, in der neuen Struktur, je Punkt ein kleiner TDD-PR:

1. `test-updateScheduler.R`: die drei Zweige von `calculate_loops()` mit gestubbtem `Sys.time`/`Sys.sleep` (reine Rechenfunktion herauslösen: Jetzt-Zeit → Loops, Startwartezeit, Dauer) — die Berlin-Zeit-Frage gleich mit.
2. `.record_rate_limit_headers()`: prüfen, ob `test-retrieveResults-rate-limit-header.R` (aus #222) das schon abdeckt; nur Lücken schließen.
3. Client-JS (Stale-Banner, Sortierung): Entscheidung Christoph — V8-Test oder JS in `site_assets/` auslagern und mit Node prüfen. Das Präfix (`js`) kommt in die Liste des Wächters.
4. Methodik-, Fallback-Seite, Asset-Kopie: je eine Erwartung an die Ausgabe.
5. Hohle Tests ersetzen: `test-rust-required` (nur `exists()`), `test-interactive-prompts` (zwei unbedingte `skip()`), `test-league-page-data` (`is.function`), `test-season-validation` (acht Warnungen); `helper-test-setup.R`: `tryCatch` beim Sourcen → Fehler statt `message()` (die Sourcing-Wand maskiert heute jede vergessene `source()`).
6. Einheiten ohne Tests: `Tabelle` (seit #218 nur indirekt über den ELO-Walk), `input_handler`, `team_data_carryover` — je entscheiden: testen oder löschen, falls tot (#209).
7. Stille Skips sichtbar machen: die CI schlägt fehl, wenn Rust-abhängige Tests trotz gestartetem Server skippen (Zählung der Skips mit Grund „Rust" im Summary).

---

## Selbstprüfung gegen die Vorgabe

- Zweistufig (Struktur → 1:1 → grün → Review): Stufe 1 = Struktur mit Freigabe-Haltepunkt; Stufe 2 = 1:1 mit Beweis; Stufe 3 = Review. ✓
- Struktur in Memory und Projektdoku: Task 2 (README, CONTEXT.md, Memory). ✓
- Offen für Veränderung: Thema-Segment statt Monsterdateien, Zweifelsregel, geschlossene Präfixliste, Split/Umbenennung zieht Tests per Wächter mit. ✓
- Danach #212: Stufe 4. ✓
- Offen für Christoph: (a) Zieltabelle freigeben (Task 2 Step 4); (b) Umgebung der Beweisläufe — Rust-Server an (Empfehlung) oder aus; (c) Reihenfolge Stufe 3.1–3.8; (d) Client-JS-Testweg in Stufe 4; (e) lokale Altlasten `tests/rust/`, `tests/test_poisson_fix.R` selbst löschen oder freigeben.
