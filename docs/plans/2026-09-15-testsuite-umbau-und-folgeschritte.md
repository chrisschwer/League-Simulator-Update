# Testsuite-Umbau (#211) und Folgeschritte — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die 67 testthat-Dateien (777 `test_that`-Blöcke, Stand 25.09.2026), heute überwiegend nach PRs, Phasen und Anlässen benannt, in die Struktur `test-<einheit>[-<thema>].R` überführen — **ohne** dabei eine einzige Erwartung zu ändern —, danach Redundanzen mit Christophs Freigabe abbauen (#211) und erst dann die Abdeckungslücken schließen (#212).

**Architecture:** Drei strikt getrennte Stufen. Stufe 1 legt die Zielstruktur fest (maschinell hergeleitete Zuordnung Testblock → Einheit, von Christoph freigegeben, in Doku und Memory). Stufe 2 verschiebt Testblöcke 1:1, baut einen Wächtertest, der die Namensregel künftig erzwingt, und beweist per Vorher/Nachher-Abgleich der Einzelergebnisse, dass nichts anders läuft. Stufe 3 ist Review: je Doppel-Cluster ein kleiner PR, der nennt, welche Erwartung bleibt und welche fällt. Erst danach #212.

**Tech Stack:** R 4.6 / testthat 3 (`ListReporter` für den Ergebnisabgleich), `withr`, `git mv`; Rust-Tests (`cargo test`, 76 Tests) unberührt.

**Spec:** Issue #211 (Struktur, Doppel-Cluster, Unabhängigkeitsrisiken; Kommentar vom 24.09. zum Generator-Split), Issue #212 (Lücken, hohle Tests), Review-Bericht `~/.claude/plans/jolly-munching-token.md` (N8, N9), Christophs Vorgabe vom 15.09.2026: zweistufig — erst Struktur, dann 1:1 verschieben, dann grün beweisen, erst dann Redundanz-Review. Überarbeitet am 25.09.2026 nach einem unabhängigen Gutachten (Fable): Namensregel mit optionalem Thema-Segment, Wächtertest, Zieltabelle auf den Stand 25.09., robusteres Beweisverfahren, geänderte Reihenfolge. Zweitgutachten am selben Tag eingearbeitet: Werkzeugnamen an `.gitignore` vorbei, `source_module()` als einziger Sourcing-Helfer, sauberer Schnitt für `render_sections.R`, Vergleichswerkzeug vor Phase 0, Kollisionen schon in der Tabelle aufgelöst.

## Global Constraints

- Ab Testfreigabe keine Teständerung ohne Rückfrage (Christophs Regel). In Stufe 2 heißt das: **kein `expect_*` wird geändert, entfernt oder ergänzt**; erlaubt sind nur Verschieben, Umbenennen der Datei, das Zusammenführen byteidentischer Helfer-Definitionen, das **Ersetzen reiner Sourcing-Helfer durch `source_module(...)`** (Task 6 Regel 3) und das **Nachführen von Pfad-Stringliteralen**, die eine umbenannte Testdatei oder eine geteilte `RCode/`-Datei benennen (heute: `test-ein-elo-walk.R:694` liest `test-rust-required.R`, `:719` den Snapshot-Runner; nach 0.4 muss `test-phase5-regionalligen.R:1642` zusätzlich `render_sections.R` lesen). Jede solche Änderung steht einzeln im PR-Text.
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
> - Jede Testdatei sourct ihre Einheit selbst, mit `source_module("<einheit>", ...)` aus `helper-source.R` (mehrere Einheiten erlaubt; die eigene muss dabei sein). Eigene `source_xyz()`-Helfer nur, wenn sie mehr tun als sourcen. Gemeinsame Helfer heißen `helper-<zweck>.R` (testthat lädt sie automatisch); keine Helferdefinition in zwei Dateien. Unterordner (`fixtures/`, `helpers/`) enthalten nur Daten und explizit gesourcte Runner, nie Tests — testthat liest sie nicht.
> - Wird eine `RCode/`-Datei geteilt, umbenannt oder gelöscht, ziehen ihre Testdateien im selben PR mit (`git mv`); `test-waechter-teststruktur.R` schlägt sonst fehl.
> - Neue Testarten laufen, wo möglich, als R-Test unter der Einheit, die den Gegenstand erzeugt (Client-JS: `test-render_sections-js.R`, #212). Nur was sich keiner Einheit zuordnen lässt, bekommt ein festes Präfix, das in `test-waechter-teststruktur.R` in die geschlossene Liste aufgenommen wird.
> - Ausführen einer Einheit mit allen Themen: `testthat::test_dir("tests/testthat", filter = "^league_details")`.

**Warum diese Form (verworfene Alternativen):** Sortierung nach Feature/Anlass ist der Ist-Zustand und hat die 15 Doppel-Cluster erzeugt. Unterordner je Ebene (unit/integration/render) liest `test_dir()` nicht rekursiv — genau so sind früher Dateien unsichtbar geworden. Ebenen-Präfixe (`test-unit-…`) klassifizieren doppelt und lassen im Zweifel zwei richtige Namen zu. Strikt „eine Datei je Einheit" ergäbe Dateien von ~4.000 (Loop), ~3.100 (Generator) und ~1.800 Zeilen (Details) und zwänge gleichnamige, aber verschiedene Helfer (`fake_fixtures` in 4, `read_html` in 5 Varianten) in eine Datei.

---

## Phase 0 — Vor dem Umbau

| Schritt | Was | Stand / Wer |
|---|---|---|
| 0.0 | Vergleichswerkzeug vorziehen: Task 4 Step 1 + Step 3 (`scripts/dev/ergebnisse_tests.R`, `_baseline/` in `.gitignore`). Grund: 0.4 und 0.5 ändern Testköpfe bzw. Testcode und brauchen denselben Multimengen-Nachweis wie Stufe 2. Jeder Phase-0-PR nimmt vorher/nachher auf (gleiche Umgebung, Task 3) und stellt den Vergleich (Task 7 Step 2) in den PR-Text. | Claude |
| 0.1 | Befund aus der ersten Messung (0.0) beheben: #233 hat zwei Tests in `test-rl-verdrahtung.R` gebrochen (`tabellenzeile()` suchte den nackten Namen, seither steht er in `<abbr class="kz">`); in der CI unsichtbar, weil die Tests den gitignorten `data/fixture_cache/` lasen und skippten. Testhilfe repariert (keine Erwartung geändert) und die 34 RL-Spielpläne 2019–2025 als eingefrorene Kopie nach `tests/testthat/fixtures/fixture_cache/`. | ✓ PR #237 |
| (erledigt) | #222 gemergt, #216 geschlossen; Deploy auf Eddie (Pin `9c71147`) | ✓ |
| 0.3 | Rest von #209 (Sourcing-Block-Kopien, Registry-Literale, Batch-Endpunkt) | **entkoppelt:** eigener PR, keine Voraussetzung für Stufe 2. Er ändert Kopfzeilen von Testdateien, darum: (a) **nie zwischen Vorher- und Nachher-Aufnahme** von Stufe 2 mergen — sonst Vorher-Aufnahme wiederholen, `git bisect` würde auf #209 zeigen; (b) landet er nach Task 1, Task 1 erneut laufen lassen und `ziel_final` über (`datei_alt`, `test_that_titel`, Vorkommen) aus der alten CSV übernehmen. |
| 0.4 | `RCode/generate_static_site.R` teilen. Der Schnitt bei Zeile 1113 ist **nicht** sauber: `.heat_style` (Z. 180), `.tooltip_html` (Z. 204) und `.ergebnis_objektname` (Z. 903) werden auf beiden Seiten gerufen. Deshalb: (1) diese drei nach `RCode/render_helpers.R` (die Einheit für gemeinsame Render-Helfer, wird von `generate_static_site.R` schon gesourct); (2) ab Zeile 1113 (`.komma` … Sektionsrenderer Ligatabelle, Zonen, Rückblick, Live, Ausblick) nach `RCode/render_sections.R`, das `render_helpers.R` selbst sourct (gleiches `ofile`-Muster wie `generate_static_site.R:13-28`) und damit **allein ladbar** ist; (3) `generate_static_site.R` sourct `render_sections.R`. Aufrufer, die nur den Generator laden (`update_all_leagues_loop.R:128`, `scripts/preview_site.R:45`), bleiben unverändert, weil der Generator die Sektionen mitlädt — prüfen. Der Meta-Block `test-phase5-regionalligen.R:1642` liest den Generator als Text und muss danach auch `render_sections.R` lesen (Pfadliste wächst, Erwartung bleibt). Vier-Argument-Pfad **nicht** anfassen (Redundanz-Review). Eigener PR unter #211, Nachweis per Multimenge (0.0). | Sonnet-Agent |
| 0.5 | Unabhängigkeit herstellen (vorgezogen aus der alten Stufe 3.6): in den 13 Dateien, die Arbeitsverzeichnis, Umgebung oder Optionen ohne Rückbau ändern (u. a. `test-season-transition-regression.R` 4×, `test-rust-required.R` 6×), `setwd` → `withr::local_dir`, `Sys.setenv` → `withr::local_envvar`, `options` → `withr::local_options`, `sample()` ohne Seed → `withr::local_seed` (`sample()` in Tests ohne Seed ist heute gar nicht zu reproduzieren, deshalb ist der Seed eine Unabhängigkeits-, keine Erwartungsänderung). **Kein `expect_*` ändert sich.** Grund: testthat läuft alphabetisch, das Umbenennen ändert die Reihenfolge; leckender Zustand ließe Stufe 2 an Altlasten stoppen statt an Verschiebefehlern. Nachweis per Multimenge (0.0). | Sonnet-Agent |
| 0.6 | Altlasten außerhalb von `tests/testthat/`: `tests/issue-31-test-specifications.md` und `tests/TeamList_2024.csv` löschen (die Spezifikation gehört zu einem erledigten Issue; die CSV liest kein Test — alle Treffer meinen `RCode/…` oder Temp-Kopien). **Nicht im Repo, nur lokal** (per `.gitignore:30/:56` ausgeschlossen): `tests/rust/` (Rust-vs-C++-Vergleichsskripte, laufen nicht mehr, weil die C++-Engine seit #102 fehlt) und `tests/test_poisson_fix.R` — ✓ am 25.09. im lokalen Checkout gelöscht (Christophs Freigabe). | Claude |

Reihenfolge: **0.0 → 0.4 → 0.5 → Stufe 1 → Stufe 2.** 0.5 steht vor Stufe 1, weil die CSV aus Task 1 Zeilennummern als Schnittvorlage trägt und 0.5 Zeilen verschiebt. 0.6 beliebig, 0.3 nach den Regeln in seiner Zeile.

---

## Stufe 1 (#211a) — Zielstruktur festlegen

### Task 1: Zuordnung Testblock → Einheit maschinell herleiten

**Files:**
- Create: `scripts/dev/zuordnung_tests.R` (Werkzeug, nicht Produktivpfad; dokumentiert in Task 2)
- Create: `docs/plans/2026-09-15-testsuite-zuordnung.csv` (Ergebnis, wird in Task 2 zur Tabelle)

**Interfaces:**
- Produces: CSV mit den Spalten `datei_alt, einheit_source, test_that_titel, zeile_von, zeile_bis, funktionen, einheit_vorschlag, ziel_final, bemerkung`. `einheit_source` ist die Einheit, die der Dateikopf per `source()` lädt (bei 60 von 67 Dateien genau eine — der stärkere Beleg); `einheit_vorschlag` die Stimme aus den gerufenen Funktionen. Weichen beide ab, steht das in `bemerkung`. `ziel_final` ist die von Christoph bestätigte Zieldatei ohne `test-` und `.R` (also `<einheit>` oder `<einheit>-<thema>`). Task 3 liest genau diese Spalten.

- [ ] **Step 1: Regeln der Zuordnung als Test festhalten**

`tests/testthat/test-scripts-zuordnung_tests.R` (heißt schon nach der Zielregel):

```r
source_zuordnung <- function() {
  source(file.path("..", "..", "scripts", "dev", "zuordnung_tests.R"), local = TRUE)
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

test_that("indirekte Aufrufe ueber Stringliterale zaehlen als Aufruf", {
  z <- source_zuordnung()
  index <- list(abstiegswahrscheinlichkeit = "rl_abstiegskopplung")
  body <- 'p <- fn(env, "abstiegswahrscheinlichkeit")(prognose, gewichte)'
  expect_identical(z$einheit_fuer_block(body, index), "rl_abstiegskopplung")
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

test_that("die geladenen Einheiten werden aus allen Pfadformen gelesen", {
  z <- source_zuordnung()
  kopf <- c('source(test_path("..", "..", "RCode", "league_details.R"))',
            'source("../../RCode/render_helpers.R")',
            'source(rcode("rl_aufstieg.R"), local = env)',
            'for (datei in c("rl_abstiegskopplung.R", "staffel_zuordnung.R")) source(rcode(datei))')
  expect_identical(z$gesourcte_einheiten(kopf, c("league_details", "render_helpers", "rl_aufstieg",
                                                 "rl_abstiegskopplung", "staffel_zuordnung")),
                   c("league_details", "render_helpers", "rl_aufstieg",
                     "rl_abstiegskopplung", "staffel_zuordnung"))
})

test_that("Kommentare und unbekannte Dateinamen zaehlen nicht als geladene Einheit", {
  z <- source_zuordnung()
  kopf <- c('# frueher: source("../../RCode/rust_integration.R")',
            'pfad <- "fixtures/TeamList_minimal.R"')
  expect_identical(z$gesourcte_einheiten(kopf, c("rust_integration")), character(0))
})
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scripts-zuordnung_tests.R")'`
Expected: FAIL, `scripts/dev/zuordnung_tests.R` existiert nicht.

- [ ] **Step 3: Werkzeug schreiben**

`scripts/dev/zuordnung_tests.R`:

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

# Alle Stringliterale "<name>.R" ausserhalb von Kommentaren, deren <name> ein
# RCode-Stamm ist -- deckt test_path(..., "x.R"), "../../RCode/x.R", rcode("x.R")
# und Dateilisten in for-Schleifen ab.
gesourcte_einheiten <- function(zeilen, einheiten) {
  code <- sub("#.*$", "", zeilen)
  treffer <- unlist(regmatches(code, gregexpr("[A-Za-z_]+\\.R\"", code)))
  namen <- unique(sub("\\.R\"$", "", treffer))
  namen[namen %in% einheiten]
}

# Direkte Aufrufe name(...) und indirekte ueber Stringliterale -- viele Tests
# rufen fn(env, "abstiegswahrscheinlichkeit")(...) oder get("name", env).
gerufene_funktionen <- function(body, index) {
  direkt <- regmatches(body, gregexpr("[.A-Za-z_][.A-Za-z0-9_]*(?=\\()", body, perl = TRUE))[[1]]
  literal <- gsub("\"", "", regmatches(body, gregexpr("\"[.A-Za-z_][.A-Za-z0-9_]*\"", body))[[1]])
  kandidaten <- c(direkt, literal)
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
  ausdruecke <- parse(datei, keep.source = TRUE, encoding = "UTF-8")
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
  einheiten <- sub("\\.R$", "", list.files("RCode", pattern = "\\.R$"))
  dateien <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = TRUE)
  zeilen <- list()
  for (d in dateien) {
    src <- paste(gesourcte_einheiten(readLines(d, warn = FALSE, encoding = "UTF-8"), einheiten),
                 collapse = " ")
    for (b in testbloecke(d)) {
      fns <- gerufene_funktionen(b$body, index)
      vorschlag <- einheit_fuer_block(b$body, index)
      # ohne Funktionsstimme: die einzige gesourcte Einheit der Datei, falls eindeutig
      if (is.na(vorschlag) && nzchar(src) && !grepl(" ", src)) vorschlag <- src
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

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-scripts-zuordnung_tests.R")'`
Expected: 7 PASS.

- [ ] **Step 5: Zuordnung erzeugen und Trefferquote prüfen**

Run: `Rscript scripts/dev/zuordnung_tests.R && Rscript -e 'z <- read.csv("docs/plans/2026-09-15-testsuite-zuordnung.csv"); cat(nrow(z), "Bloecke,", sum(is.na(z$einheit_vorschlag) | z$einheit_vorschlag == ""), "ohne Vorschlag,", sum(nzchar(z$bemerkung)), "Abweichungen source/Stimme\n"); print(sort(table(z$einheit_vorschlag), decreasing = TRUE))'`
Expected: ≈ 784 Blöcke (777 + 7 neue); ohne Vorschlag < 10 %. Blöcke ohne Vorschlag und alle Abweichungen von Hand nach der Zweifelsregel entscheiden (`ziel_final`, `bemerkung` = Grund).

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/zuordnung_tests.R tests/testthat/test-scripts-zuordnung_tests.R docs/plans/2026-09-15-testsuite-zuordnung.csv
git commit -m "chore(#211): Zuordnung Testblock -> RCode-Einheit maschinell herleiten"
```

### Task 2: Zielstruktur dokumentieren und freigeben lassen

**Files:**
- Create: `tests/testthat/README.md` (die Struktur, neben den Tests — dort sucht man sie)
- Modify: `CONTEXT.md` (ein Verweis unter Decisions)
- Modify: `docs/README.md` oder `docs/user-guide/README.md` (Eintrag für `scripts/dev/zuordnung_tests.R` und `scripts/dev/ergebnisse_tests.R`)
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
| `helper-source.R` | neu: `source_module(...)` (Task 6 Regel 3) — ersetzt `source_generator`, `source_registry`, `source_views`, `source_round_filter`, `source_aufstieg` u. ä., soweit sie nur `RCode/`-Dateien laden. Helfer, die mehr tun (z. B. `source_scheduler`, wertet bis `main()` aus), bleiben in ihrer Datei |
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
| test-league_details.R | test-fixture-details, test-fixture-details-produktionsform, test-spieltag-logik, test-ligatabelle (61 Z., kein eigenes Thema), test-gewertete-spiele (Fensterung/Tabelle), test-elo-walk-reihenfolge (Details-Hälfte), test-tbd-termin (Details-Hälfte, ruft `extract_fixture_details`) |
| test-league_details-client.R | test-league-details-client, test-league-details-client-haertung |
| test-league_details-seitendaten.R | test-league-page-data, test-league-page-data-rueckblick, test-league-page-data-ausblick |
| test-rust_integration.R | test-home-advantage-single-source, test-tormodell-rust-durchreichung, test-league-registry Block ~Zeile 371 |
| test-rust_integration-server.R | test-rust-required (Server-Start) — eigenes Thema, weil `start_rust_server` und `with_repo_root` dort anders definiert sind als in den übrigen Quellen |
| test-league_registry.R | test-league-registry, test-frauen-ligen-aktivierung §1–2, test-phase5-regionalligen §1, test-n-ligen-entflechtung §1, test-rl-aufstieg (Registry-Slots), test-rl-zonen-verdrahtung (Regeltext) |
| test-league_views.R | test-league-views, test-frauen-ligen-live §1–2, test-phase5-regionalligen §2 |
| test-generate_static_site.R | test-generate-static-site, test-live-na-guard, test-phase5-regionalligen §3–4 (ohne Meta-Block :1642), test-frauen-ligen-live §3, test-n-ligen-entflechtung §2 |
| test-render_sections-tabelle.R | test-ligatabelle-sektion |
| test-render_sections-zonen.R | test-rl-zonenlinien, test-rl-zonen-verdrahtung (Render-Hälfte) |
| test-render_sections-rueckblick.R | test-rueckblick-sektion |
| test-render_sections-ausblick.R | test-ausblick-sektion, test-tbd-termin (Ausblick-Hälfte) |
| test-render_sections-farbskala.R | test-score-matrix-farbskala |
| test-render_sections-tooltip.R | test-kuerzel-tooltip (Generator-Blöcke ohne den `site.css`-Block :182; Blöcke, die nur `league_details` prüfen, laut CSV nach test-league_details.R; ob Tooltip-Renderer nach dem Split in `render_sections` oder im Seitengerüst liegen, entscheidet die CSV) |
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
| test-rl_abstiegskopplung.R | test-rl-abstiegskopplung |
| test-rl_abstiegskopplung-nord.R | test-rl-nord-aufstiegskopplung — eigenes Thema, weil `K_DRITTE_LIGA` anders definiert ist als in test-rl-abstiegskopplung |
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
| test-scripts-zuordnung_tests.R | (neu aus Task 1) |
| test-waechter-quelltext.R | Blöcke, die Produktivquelltext oder Assets als Text lesen: test-modellkonstanten-nur-in-rust, test-frauen-ligen-aktivierung Block ~Zeile 84 (Fenstergrenzen in `updateScheduler.R`), test-phase5-regionalligen Block :1642 (Staffelnamen im Generator), test-kuerzel-tooltip Block :182 (`site.css`) |
| test-waechter-ci-pfade.R | test-ein-elo-walk Meta-Blöcke (~Zeilen 694, 719: CI-Pfad `test-rust-required.R`, Snapshot-Runner) |
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

> **Stand 25.09.2026:** Die Zieltabelle in diesem Plan hat Christoph freigegeben. Offen bleibt nur die Einzelzuordnung der Blöcke ohne Vorschlag (~8 %) und der Abweichungen source/Stimme in der CSV; sie folgt der Zweifelsregel und der freigegebenen Tabelle und braucht nur dann eine Rückfrage, wenn ein Block in keine Tabellenzeile passt.

- [ ] **Step 5: Commit + PR**

```bash
git add tests/testthat/README.md CONTEXT.md docs/README.md
git commit -m "docs(#211): Zielstruktur der Testsuite festlegen"
gh pr create --draft --title "Testsuite: Zielstruktur (#211, Stufe 1)" --body-file <body>
```

---

## Stufe 2 (#211b) — Tests 1:1 verschieben und Gleichheit beweisen

### Task 3: Umgebung festschreiben

Christophs Entscheidung (25.09.): **jede Aufnahme läuft zweimal — mit und ohne Rust-Server —, und beide Läufe müssen exakt das für ihre Umgebung erwartete Verhalten zeigen.** Vorher und Nachher werden je Umgebung verglichen (mit↔mit, ohne↔ohne), nie über Kreuz.

- [ ] **Step 1: Umgebungen festschreiben.** Im PR-Text protokollieren:
  - *mit*: `league-simulator-rust --api` läuft, Health auf `:8080` grün (so wie die CI, `ci.yml` ~Z. 150–165), **und** das Binary liegt unter `league-simulator-rust/target/release/` (zwei Tests — `test-rust-required.R`, `test-tormodell-rust-durchreichung.R` — starten ihren eigenen Server von dort oder `/usr/local/bin`); das Binary aus dem aktuellen Quellstand bauen;
  - *ohne*: kein Prozess auf `:8080` (`curl -sf localhost:8080/health` schlägt fehl), `RUST_API_URL` ungesetzt, **kein** Binary an den beiden Pfaden;
  - in beiden gleich: keine lokalen, gitignorten Daten im Arbeitsverzeichnis — so wie die CI (nach 0.1 liest kein Test mehr `data/fixture_cache/`; `ShinyApp/data/Ergebnis.Rds` fehlt dann, zwei Blöcke skippen in beiden Umgebungen), `RAPIDAPI_KEY=dummy`, Paketversionen von `testthat`, `mockery`, `withr`, `sys` (`sessionInfo()` in den PR).
  - *Referenz* (gemessen 25.09. nach 0.1, PR #237): ohne Rust 777 Blöcke, 3232 Erwartungen, 0 Fehlschläge, 10 Skips (4× Server, 2× Binary, 2× `interactive-prompts` unbedingt, 2× `Ergebnis.Rds`); mit Rust 3311 Erwartungen, 0 Fehlschläge, 4 Skips. Nach #242 (main `4bae96d`, 26.09.): 787 Blöcke; ohne Rust 3246 Erwartungen, 10 Skips; mit Rust 3325 Erwartungen, 4 Skips. Maßgeblich ist immer die eigene Vorher-Aufnahme, nicht diese Zahlen.

  > **Ergänzt 26.09. (Review vor Stufe 2) — beide Aufnahmen in frischen Worktrees, Binary in beiden.** Der Haupt-Checkout enthält gitignorte Daten (`data/`, `data/fixture_cache/`, `ShinyApp/data/Ergebnis.Rds`); eine Nachher-Aufnahme dort zeigt zwei Skips weniger als die CI und die Vorher-Aufnahme, und der Vergleich schlägt fehl. Deshalb: Vorher in `git worktree add --detach <pfad-vorher> origin/main`, Nachher in `git worktree add --detach <pfad-nachher> <branch-HEAD>` — nie im Haupt-Checkout. `rust_binary()` (`test-rust-required.R`, `test-tormodell-rust-durchreichung.R`) sucht das Binary **relativ zum jeweiligen Worktree** unter `league-simulator-rust/target/release/`, `/usr/local/bin` ist auf dem Entwicklerrechner leer; das Binary muss also in **beide** Worktrees kopiert werden (einmal bauen: `CARGO_TARGET_DIR` außerhalb des Repos, dann je Worktree nach `target/release/`). Das lokal vorhandene Binary vom 12.09. ist älter als zwei Rust-Commits (`d5f8f3e`, `0334d34`) — neu bauen, und derselbe Build stellt den Server auf `:8080` für die „mit"-Läufe. Beide Worktrees nach der Nachher-Aufnahme mit `git worktree remove` entfernen.
- [ ] **Step 2: Erwartetes Verhalten je Umgebung** (wird in Task 4 an der Vorher-Aufnahme geprüft und in Task 7 an der Nachher-Aufnahme):
  - *mit*: 0 Fehlschläge, 0 Fehler, **kein** Block skippt wegen Rust (Server oder Binary).
  - *ohne*: 0 Fehlschläge, 0 Fehler; Rust-abhängige Blöcke **skippen**, statt zu scheitern.
  - Die Differenzmenge „skippt ohne, läuft mit" enthält nur Blöcke aus Dateien, die den Server ansprechen (`connect_rust_simulator`, `RUST_API_URL`, `start_rust_server`, `localhost:8080`, `league-simulator-rust`) — sonst hängt ein Test unerkannt am Server.
  - Weicht die Vorher-Aufnahme davon ab (z. B. ein Test scheitert ohne Server, statt zu skippen), ist das ein Befund **vor** dem Umbau: Stopp, Christoph fragen, ob er in Phase 0 behoben oder als erwartete Ausnahme protokolliert wird. Im Umbau selbst wird nichts daran geändert.

### Task 4: Vorher-Aufnahme der Einzelergebnisse

**Files:**
- Create: `scripts/dev/ergebnisse_tests.R`
- Create (gitignored, lokal): `tests/testthat/_baseline/vorher.csv`

**Interfaces:**
- Produces: CSV `test, expectations, failed, skipped, error` je `test_that`-Block, **ohne** Dateiname (der ändert sich). Task 6 vergleicht Vorher gegen Nachher als Multimenge.

- [ ] **Step 1: Werkzeug schreiben**

```r
# scripts/dev/ergebnisse_tests.R -- Einzelergebnisse je test_that()-Block als CSV.
# Aufruf: Rscript scripts/dev/ergebnisse_tests.R <ziel.csv>
args <- commandArgs(trailingOnly = TRUE)
ziel <- if (length(args) >= 1) args[1] else "tests/testthat/_baseline/ergebnisse.csv"
dir.create(dirname(ziel), showWarnings = FALSE, recursive = TRUE)
Sys.setenv(RAPIDAPI_KEY = Sys.getenv("RAPIDAPI_KEY", "dummy"))
res <- testthat::test_dir("tests/testthat", reporter = "silent", stop_on_failure = FALSE)
df <- as.data.frame(res)
# file nur zur Diagnose (Rust-Plausibilitaet); der Vergleich ignoriert die Spalte
df <- df[, c("file", "test", "nb", "failed", "skipped", "error")]
names(df) <- c("file", "test", "expectations", "failed", "skipped", "error")
df <- df[do.call(order, df), ]
utils::write.csv(df, ziel, row.names = FALSE)
cat(nrow(df), "Bloecke,", sum(df$expectations), "Erwartungen,",
    sum(df$failed), "Fehlschlaege,", sum(df$skipped), "Skips\n")
```

- [ ] **Step 2: Vorher-Aufnahme auf dem Stand von `main` nach Phase 0**

Run (einmal je Umgebung aus Task 3):
`Rscript scripts/dev/ergebnisse_tests.R tests/testthat/_baseline/vorher-mit.csv`
`Rscript scripts/dev/ergebnisse_tests.R tests/testthat/_baseline/vorher-ohne.csv`
Expected: das Verhalten aus Task 3 Step 2, geprüft mit

```r
# Rscript -e '<dieser Block>' -- Plausibilitaet je Umgebung
b <- "tests/testthat/_baseline/"; m <- read.csv(paste0(b, "vorher-mit.csv")); o <- read.csv(paste0(b, "vorher-ohne.csv"))
stopifnot(sum(m$failed) == 0, !any(m$error), sum(o$failed) == 0, !any(o$error))
nur_ohne <- unique(o$file[o$skipped & !(paste(o$file, o$test) %in% paste(m$file, m$test)[m$skipped])])
rust <- vapply(nur_ohne, function(f) any(grepl("connect_rust_simulator|RUST_API_URL|start_rust_server|localhost:8080|league-simulator-rust|skip_if_no_rust|rust_binary",
  readLines(file.path("tests/testthat", f), warn = FALSE))), logical(1))
print(nur_ohne); stopifnot(all(rust))
```

Zahlen (Blöcke, Erwartungen, Skips je Umgebung) in den PR-Text. Seit Stufe 3.6 leben die
RUST_API_URL-/localhost:8080-Literale selbst in `helper-rust.R`, nicht mehr in den einzelnen
Testdateien — das Muster muss daher um die jetzt zentralen Helfernamen `skip_if_no_rust` und
`rust_binary` ergänzt werden, sonst greift die Grep-Prüfung an den betroffenen Dateien ins Leere.

- [ ] **Step 3: `_baseline/` in `.gitignore`, Commit des Werkzeugs**

```bash
echo "tests/testthat/_baseline/" >> .gitignore
git add scripts/dev/ergebnisse_tests.R .gitignore
git commit -m "chore(#211): Einzelergebnisse der Testsuite als Vergleichsbasis aufnehmen"
```

### Task 5: Struktur-Wächter

**Files:**
- Create: `tests/testthat/test-waechter-teststruktur.R`

Der Wächter wird **zuerst** geschrieben und läuft am Anfang rot (heute passen 49 Dateinamen nicht). Er ist das Abnahmekriterium von Task 6 und hält die Regel danach dauerhaft.

> **Entschieden 26.09. (Review vor Stufe 2):** Der vierte Block („jede Einheiten-Testdatei sourct ihre Einheit") akzeptiert eine Datei auch dann, wenn sie eine Einheit nennt, die die geprüfte Einheit per `source()` mitlädt. Grund: Die sechs `test-render_sections-*.R` laden ausnahmslos `generate_static_site.R` und brauchen dessen Funktionen (`render_league_page`, `league_views`, `render_heatmap`, `render_panel_table`); `render_sections.R` allein reicht ihnen nicht, und der Generator sourct es selbst. Umsetzung: Der Wächter liest je `RCode/`-Datei die Literale `"<x>.R"` in `source()`-Zeilen (Lader-Karte Einheit → mitgeladene Einheiten, transitiv) und prüft „nennt die Einheit oder einen ihrer Lader". Die README bekommt den Satz: „Eine Einheit gilt als gesourct, wenn die Datei sie oder eine Einheit nennt, die sie per `source()` mitlädt." Verworfen: beide Einheiten laden (Doppelladung), Umbenennung nach `generate_static_site-<thema>` (widerspricht der freigegebenen Tabelle).

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
  skript <- sub("-.*$", "", sub("^scripts-", "", s))   # Thema abschneiden
  expect_identical(s[!skript %in% skripte], character(0))
})

test_that("kein Dateiname nennt Anlass, Phase oder Issue", {
  # ganze Segmente, damit test-fixture_cache.R nicht als "fix" gilt; keine
  # Ziffernregel -- sie traefe legitime Themen wie -liga1034, Issue-Nummern
  # faengt schon das Wort "issue"
  verboten <- "(^|-)(fix|move|haertung|issue|pr[0-9]+|phase[0-9]+)(-|$)"
  expect_identical(testdateien[grepl(verboten, stamm)], character(0))
})

test_that("jede Einheiten-Testdatei sourct ihre Einheit", {
  pruefen <- testdateien[einheit_von %in% einheiten]
  ohne <- pruefen[!vapply(seq_along(pruefen), function(i) {
    e <- einheit_von[testdateien == pruefen[i]]
    code <- sub("#.*$", "", readLines(test_path(pruefen[i]), warn = FALSE, encoding = "UTF-8"))
    any(grepl(paste0("\\b", e, "\\.R\\b|source_module\\([^)]*\"", e, "\""), code, perl = TRUE))
  }, logical(1))]
  expect_identical(ohne, character(0))
})

test_that("kein Top-Level-Name ist in einer Testdatei doppelt definiert", {
  doppelt <- unlist(lapply(c(testdateien, list.files(test_path(), pattern = "^helper-.*\\.R$")), function(d) {
    ausdruecke <- parse(test_path(d), encoding = "UTF-8")
    namen <- unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
    if (any(duplicated(namen))) paste0(d, ": ", unique(namen[duplicated(namen)]))
  }))
  expect_identical(doppelt, NULL)
})

test_that("keine Helferdefinition steht in zwei helper-Dateien", {
  helfer <- list.files(test_path(), pattern = "^helper-.*\\.R$")
  namen <- unlist(lapply(helfer, function(d) {
    ausdruecke <- parse(test_path(d), encoding = "UTF-8")
    unlist(lapply(ausdruecke, function(e)
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]])))
  }))
  expect_identical(unique(namen[duplicated(namen)]), character(0))
})
```

- [ ] **Step 2: Laufen lassen, muss rot sein** (erwartet: Liste der heutigen Fehlbenennungen; die anderen fünf Blöcke sind auf dem Ist-Stand grün — am 26.09. geprüft: keine doppelten Top-Level-Namen, keine Helferdoppel). **Entschieden 26.09.:** Die rote Ausgabe wird als Nachweis in den PR-Text übernommen, der Wächter selbst aber erst als **letzter Commit von Task 6** eingecheckt (Step N+1). So hält jeder Commit im Branch Regel 5 („0 Fehlschläge") wörtlich, der `git bisect`-Test aus Task 7 bleibt ein schlichter `test_dir`, und die CI des Draft-PR ist nur rot, wenn wirklich etwas schiefging. Verworfen: Wächter ab Commit 1 rot mitführen (Regel 5 müsste zu „0 außer Wächter" werden); Wächter mit `skip()` einchecken (das Muster, das #212 Punkt 5 abschafft).

### Task 6: Dateien verschieben — je Zieldatei ein Commit

**Files:**
- Modify/Rename: alle `tests/testthat/test-*.R` gemäß README-Tabelle
- Create: `helper-source.R`, `helper-html.R`, `helper-repo.R`, `helper-rust.R` (nur **Verschieben** byteidentischer Helfer-Definitionen; Funktionskörper unverändert)

**Regeln für jeden Commit:**
1. Ganze Datei → `git mv` (Historie bleibt). Aufgeteilte Datei → die größere Hälfte per `git mv`, die kleinere Hälfte **wortgleich** an das Ende der Zieldatei anhängen.
2. „1:1" gilt für Blöcke, **nicht** für Dateiköpfe: `library(...)`, `source(...)` und Top-Level-Konstanten (z. B. `namen` in `test-kuerzel-tooltip.R:18`) werden beim Zusammenführen geteilter Zustand. Jeder Kopf wird mitgenommen; Namenskollisionen fängt der Wächter (doppelte Top-Level-Namen). Kollidieren nicht-identische Helfer oder Konstanten, wird **nicht** umbenannt, sondern die Quelle bekommt ein eigenes Thema (Rückfrage an Christoph, Tabelle nachführen).

   > **Entschieden 26.09. (Review vor Stufe 2) — Zwischen-Definitionen und mehrfach gebrauchte Helfer.** Vier geteilte Dateien haben Top-Level-Definitionen *zwischen* den Blöcken (`test-rl-verdrahtung.R` 27, `test-n-ligen-entflechtung.R` 7 inkl. globalem `source(update_all_leagues_loop.R)` Z. 192, `test-phase5-regionalligen.R` 5, `test-frauen-ligen-aktivierung.R` 1). Regel: **Jede Top-Level-Definition folgt den Blöcken, die sie unmittelbar oder über andere Definitionen benutzen**; die Zugehörigkeit wird maschinell aus den Namensverweisen bestimmt (Skript im Scratchpad, Ergebnis in den PR-Text), nicht per Augenmaß. Braucht mehr als eine Zieldatei dieselbe Definition und gibt es nur **eine Fassung** (identisch bis auf Kommentare und Leerraum — nicht „bytegleich"), wandert sie in die passende `helper-*.R`: `read_html`, `make_data_env` → `helper-html.R`; `with_repo_root` (7 Quellen, zwei unterscheiden sich nur durch einen Kommentar) → `helper-repo.R`; `mk_ergebnis` (Prognose-Attrappe, gebraucht in `test-generate_static_site.R` und `test-rl_abstiegskopplung.R`, Basis von `alle_ergebnisse`) → `helper-fixtures.R`. Gibt es mehrere Fassungen (`fake_fixtures` 4×), bleibt jede in ihrer Zieldatei bis Stufe 3.6. `helper-rust.R` entsteht in Stufe 2 nicht (kein byteidentischer Fake-Server in mehreren Zieldateien). Verworfen: Kopien in mehreren Testdateien (README-Regel „keine Helferdefinition in zwei Dateien" wäre vom ersten Tag an unwahr, der Wächter prüft sie zwischen Testdateien nicht).
3. **Sourcing:** Der erste Commit von Task 6 legt `helper-source.R` mit genau dieser Funktion an:

   ```r
   # Laedt eine oder mehrere RCode-Einheiten in eine Umgebung und gibt sie zurueck.
   # source() statt sys.source(), weil generate_static_site.R sein eigenes
   # Verzeichnis ueber das ofile-Muster findet.
   source_module <- function(..., envir = new.env()) {
     for (einheit in c(...)) {
       source(test_path("..", "..", "RCode", paste0(einheit, ".R")), local = envir)
     }
     envir
   }
   ```

   Danach werden reine Sourcing-Helfer an ihren Aufrufstellen ersetzt, z. B. `env <- source_generator()` → `env <- source_module("generate_static_site")`, `source_aufstieg()` → `source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "rl_aufstieg")`, und die Definition fällt weg. Damit lösen sich die Namenskollisionen der `source_*`-Varianten beim Zusammenführen (etwa in `test-league_registry.R`), und der Wächter findet in jeder Datei ihre Einheit. `test-season-transition-regression.R` hat heute **keinen** `source()`-Aufruf und lebt von der Sourcing-Wand in `helper-test-setup.R`; sie bekommt oben `source_module("season_processor", envir = environment())`. Andere Helfer, die byteidentisch in mehreren Zieldateien stehen (`make_data_env`, …), wandern in die passende `helper-*.R`. Keine Vereinheitlichung nicht-identischer Varianten, die mehr tun als sourcen — das ist Stufe 3.6.

   > **Entschieden 26.09. (Review vor Stufe 2):** Die flächige Ersetzung entfällt in Stufe 2. Befund: Alle Helfer-Kollisionen beim Zusammenführen sind byteidentisch (`source_generator` 12×, `source_registry` 2×, `mk_ergebnis` 2×) — bis auf `source_aufstieg`, dessen Phase-5-Fassung zusätzlich `aufstiegsspiele.R` lädt; der Wächter akzeptiert auch das Literal `<einheit>.R`, das jeder bestehende Helfer enthält. Deshalb: byteidentische Helfer werden im Zielkopf zu **einer** Definition zusammengeführt; ersetzt werden nur die 13 `source_aufstieg()`-Aufrufe aus `test-phase5-regionalligen.R`, mit `source_module("league_registry", "staffel_zuordnung", "rl_abstiegskopplung", "aufstiegsspiele", "rl_aufstieg")` — Argumentliste = exakt die Dateiliste des ersetzten Helfers, je Aufrufstelle. `helper-source.R` entsteht trotzdem (Regressionsdatei, Sektionsdateien). Die flächige Umstellung (~345 Aufrufstellen) wird ein eigener PR **direkt nach Stufe 2** mit demselben Identitätsbeweis; der README-Satz „sourct … mit `source_module()`" wird bis dahin zu „nennt ihre Einheit im Kopf" abgeschwächt.
4. Kein `expect_*`, kein `test_that`-Titel, kein Stub, kein Fixture wird angefasst. Ausnahmen: ein `context()` (veraltet) darf entfallen; die Kopfänderungen aus Regel 3; Stringliterale, die eine umbenannte Testdatei benennen, werden nachgeführt. Alle Ausnahmen stehen einzeln im PR-Text, die Multimenge (Task 7) belegt, dass sich kein Ergebnis ändert. Kommentare, die alte Testdateinamen nennen (~52), werden mitgeführt, wo sie im selben Commit ohnehin berührt werden; sonst bleiben sie für Stufe 3.
5. Nach jedem Commit **Einzellauf und Gesamtlauf**: `Rscript -e 'testthat::test_file("tests/testthat/test-<ziel>.R")'` und `Rscript scripts/dev/ergebnisse_tests.R /tmp/zwischen.csv` → 0 Fehlschläge. (Der Einzellauf fängt fehlendes Sourcing, der Gesamtlauf Reihenfolgeeffekte.)

- [ ] **Step 1–N: Reihenfolge der Commits** (klein → groß, damit Fehler früh auffallen)

1. Reine Umbenennungen ganzer Dateien (ein Commit je 5–8 Dateien, Liste aus der README-Tabelle: alle Zeilen mit genau einer Quelle ohne „Hälfte").
2. Zusammenführungen ganzer Dateien, je Zieldatei ein Commit (alle Zeilen mit mehreren Quellen ohne „Hälfte").
3. Aufteilungen, je Quelldatei ein Commit, CSV-Zeilen als Schnittvorlage: gewertete-spiele, rundenfilter-schutznetz, elo-walk-reihenfolge, rl-zonen-verdrahtung, rl-verdrahtung, tbd-termin, kuerzel-tooltip, frauen-ligen-aktivierung, frauen-ligen-live, n-ligen-entflechtung, phase5-regionalligen (Block :1642 → waechter-quelltext), rust-required (Server-Start → rust_integration-server), ein-elo-walk (Meta-Blöcke → waechter-ci-pfade). kuerzel-tooltip gibt Block :182 an waechter-quelltext ab.
4. Helfer-Dateien (ein Commit): byteidentische Kopien nach `helper-*.R`. (`helper-source.R` entsteht schon im ersten Commit, siehe Regel 3.)

- [ ] **Step N+1: Wächter einchecken, grün**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-waechter-teststruktur.R")'`, danach Einzel- und Gesamtlauf wie Regel 5.
Expected: alle Blöcke PASS; Gesamtlauf 0 Fehlschläge. Erst jetzt `git add tests/testthat/test-waechter-teststruktur.R` und Commit (Entscheidung 26.09., Task 5 Step 2). Im selben Commit: README-Sätze nachführen (Lader-Regel des Wächters; „sourct … mit `source_module()`" → „nennt ihre Einheit im Kopf", bis der Folge-PR die Umstellung bringt; Helferliste: `helper-rust.R` entfällt, `mk_ergebnis` in `helper-fixtures.R`).

### Task 7: Nachher-Aufnahme und Beweis der Gleichheit

- [ ] **Step 1: Nachher-Aufnahme** (beide Umgebungen wie Task 3)

Run: `Rscript scripts/dev/ergebnisse_tests.R tests/testthat/_baseline/nachher-mit.csv` und `… nachher-ohne.csv`; danach die Plausibilitätsprüfung aus Task 4 Step 2 auf die Nachher-Dateien.

- [ ] **Step 2: Vergleich als Multimenge**

Titel sind nicht eindeutig (heute schon doppelt: „Bayern summiert exakt auf zwei Absteiger…" und „Nord und Bayern stellen zusammen genau einen Aufsteiger" in `test-phase5-regionalligen.R` und `test-rl-verdrahtung.R`). Deshalb kein Schlüssel-Merge, sondern Vergleich der sortierten Zeilen:

```r
# Rscript -e '<dieser Block>'
# einmal mit umgebung <- "mit", einmal mit umgebung <- "ohne"
umgebung <- "mit"
spalten <- c("test", "expectations", "failed", "skipped", "error")   # ohne file: der aendert sich
v <- read.csv(sprintf("tests/testthat/_baseline/vorher-%s.csv", umgebung), stringsAsFactors = FALSE)[, spalten]
n <- read.csv(sprintf("tests/testthat/_baseline/nachher-%s.csv", umgebung), stringsAsFactors = FALSE)[, spalten]
# einzige zulaessige Zusatzzeilen: die Bloecke des Waechters aus Task 5
ex <- parse("tests/testthat/test-waechter-teststruktur.R", encoding = "UTF-8")
waechter <- unlist(lapply(ex, function(e) if (is.call(e) && identical(e[[1]], as.name("test_that"))) e[[2]]))
stopifnot(!any(waechter %in% v$test))
n <- n[!n$test %in% waechter, ]
zeilen <- function(d) sort(do.call(paste, c(d, sep = "\r")))   # Multimenge: sortierte Zeilen
# Anzeige als Multimengen-Differenz (Haeufigkeit je Zeile), nicht per setdiff
alle <- union(zeilen(v), zeilen(n))
h_v <- table(factor(zeilen(v), levels = alle)); h_n <- table(factor(zeilen(n), levels = alle))
abw <- data.frame(zeile = alle, vorher = as.integer(h_v), nachher = as.integer(h_n))
print(abw[abw$vorher != abw$nachher, ])
stopifnot(identical(zeilen(v), zeilen(n)))
cat("identisch:", nrow(v), "Bloecke,", sum(v$expectations), "Erwartungen\n")
```

Expected: `identisch: <N> Bloecke, <E> Erwartungen`, dieselben Zahlen wie Task 4 Step 2. **Jede Abweichung ist ein Stopp**: zurück zum Commit, der sie verursacht (`git bisect` über die Commits von Task 6 mit dem Vergleich als Test), Ursache benennen, nicht anpassen.

- [ ] **Step 3: Doppelte Titel notieren**

Run: `Rscript -e 'n <- read.csv("tests/testthat/_baseline/nachher-mit.csv"); print(unique(n$test[duplicated(n$test)]))'`
Doppelte Titel sind zulässig, aber die ersten Kandidaten für Stufe 3 — in die CSV-Spalte `bemerkung`.

- [ ] **Step 4: CI**

Push, PR (Draft → nach grüner CI ready). PR-Text: Umgebung (Task 3), Zahlen aus Task 4 und Task 7, Liste der Umbenennungen, der nachgeführten Stringliterale, der Helfer-Verschiebungen, der Kandidaten für Stufe 3.

- [ ] **Step 5: Merge durch Christoph, Memory aktualisieren**

---

## Stufe 3 (#211c) — Redundanz-Review, je Cluster ein PR

Erst jetzt werden Erwartungen angefasst — und nur mit Christophs Wort je PR. Reihenfolge nach Nutzen; die Cluster-Nummern verweisen auf Issue #211.

**Vorab, PR 3.0 (entschieden 26.09.):** die flächige Umstellung der reinen Sourcing-Helfer auf `source_module()` (elf Helfernamen ersetzt, 320 Aufrufstellen; zehn Definitionen entfallen vollständig, `source_zuordnung` bleibt nur in `test-scripts-zuordnung_tests.R` erhalten, weil dort ein Skript geladen wird, keine RCode-Einheit), die aus Stufe 2 herausgenommen wurde. Reines Refactoring ohne Erwartungsänderung, Nachweis per identischer Multimenge wie Task 7; danach gilt der README-Satz „sourct … mit `source_module()`" wieder wörtlich. Läuft direkt nach dem Merge von Stufe 2, vor 3.1. **Erledigt 26.09., PR #245.**

| PR | Cluster (aus #211) | Was bleibt | Was fällt (Vorschlag) |
|---|---|---|---|
| 3.1 | Kürzel-Vertrag (Cluster 1) — beide Quellen liegen in `test-transform_data-kuerzel.R` | die Fassung aus kuerzel-vertrag (vollständiger) | die Doppelungen aus teamlist-eindeutigkeit für „gleiche Liga bricht ab", „Nord/Nordost/Bayern", „TeamID doppelt", „VFB/FCH/RWE" — **Erledigt 26.09., PR #247: 7 Blöcke/18 Erwartungen (A:90, 161, 225, 245, 257, 272; B:448).** |
| 3.2 | home_advantage/Tormodell nicht gesendet (Cluster 2) | je ein Test für `/simulate` und `/league-details` in test-rust_integration | Wiederholungen in league_registry und league_details |
| 3.3 | `validate_team_count`-Grenze (Cluster 3) | ein Test mit der aktuellen Grenze (Christoph nennt sie) | die zwei anderen Werte |
| 3.4 | `league_views()`-Form (Cluster 6) + Seitenzahl (Cluster 7) | ein Test gegen die Registry | vier Wiederholungen mit hart kodierten Listen — **Erledigt 26.09., PR #248: 6 Blöcke/16 Erwartungen (V:5, 121, 180; R:182, 870; G:784).** |
| 3.5 | Spieltag-Fensterung (Cluster 12) + Reihenfolge (Cluster 5) | spieltag-logik-Fassung | Join-Level-Wiederholungen |
| 3.6 | Helfer vereinheitlichen: nicht-identische Varianten (`fake_fixtures` 4×, `with_repo_root` 3×, `read_html` 5×) zusammenführen, wo sie dasselbe tun; ein zentrales `skip_if_no_rust()` in `helper-rust.R` statt vier Skip-Varianten | — | — (keine Erwartung fällt; Skip-Bedingungen werden gleich, das wird per Multimenge belegt). **Erledigt 26.09., PR #246.** |
| 3.7 | Vier-Argument-Pfad von `generate_static_site()` (`test-n-ligen-entflechtung.R:129,154`, `test-generate-static-site.R:392` — nach Stufe 2 in den neuen Dateien) | — | die drei Kompatibilitätstests samt Pfad, wenn Christoph zustimmt |
| 3.8 | Rest (Cluster 4, 8–11, 13–15) | je Cluster die vollständigere Fassung | die andere |

Je PR: Tabelle „Test X fällt, weil Test Y dieselbe Erwartung hält (Datei:Zeile)". Vorher/Nachher-Multimenge wie in Task 7, diesmal mit **erwarteter** Abnahme, die im PR-Text steht.

---

## Stufe 4 (#212) — Lücken schließen und hohle Tests ersetzen

Nach Stufe 3, in der neuen Struktur, je Punkt ein kleiner TDD-PR:

1. `test-updateScheduler.R`: die drei Zweige von `calculate_loops()` mit gestubbtem `Sys.time`/`Sys.sleep` (reine Rechenfunktion herauslösen: Jetzt-Zeit → Loops, Startwartezeit, Dauer) — die Berlin-Zeit-Frage gleich mit.
2. `.record_rate_limit_headers()`: prüfen, ob `test-retrieveResults-rate-limit-header.R` (aus #222) das schon abdeckt; nur Lücken schließen.
3. Client-JS — **entschieden 25.09.: Node + jsdom mit Syntaxprüfung, Skripte bleiben inline.**
   - *Gegenstand:* die drei Inline-Skripte aus `generate_static_site.R` (nach 0.4 teils in `render_sections.R`): Veraltet-Hinweis (`.stale_script`, heute `:478`), Tabellensortierung (`.LIGA_SORT_SCRIPT`, `:1427`), Kürzel-Tooltip (`.KUERZEL_SCRIPT`, `:1716`).
   - *Werkzeug:* `package.json` im Repo-Root mit genau einer devDependency `jsdom` (+ `package-lock.json`); `node_modules/` in `.gitignore`. Ein kleiner Runner `tests/testthat/helpers/js-runner.mjs` (explizit aufgerufen, kein Test) lädt eine HTML-Datei in jsdom mit `runScripts: "dangerously"`, führt ein übergebenes Szenario aus und gibt das Ergebnis als JSON auf stdout aus.
   - *Tests:* R-Testdateien nach der Einheit, die das Skript ausliefert — kein neues Präfix: `test-generate_static_site-js.R` (Veraltet-Hinweis), `test-render_sections-js.R` (Sortierung, Tooltip). Jede rendert eine Seite aus der Preview-Fixture in ein `withr::local_tempdir()`, ruft den Runner per `system2("node", …)` und prüft das JSON mit `expect_*`. Ohne Node oder ohne `node_modules/jsdom` → `skip()` mit Grund „Node/jsdom fehlt" (wie die Rust-Tests).
   - *Syntaxprüfung (je Skript, zuerst):* die `<script>`-Inhalte aus der gerenderten Seite ziehen, in Temp-Dateien schreiben, `node --check` → Exit-Code 0. Fängt Escape-Fehler aus den `paste0`-Strings.
   - *Verhaltensfälle:* Veraltet-Hinweis — `Date.now` eingefroren auf `generated + Schwelle − 1 h` → `#stale` bleibt `hidden`; auf `+ Schwelle + 1 h` → sichtbar, `#stale-hours` zeigt die gerundeten Stunden; fehlendes `#generated` → kein Fehler. Sortierung — Klick auf eine Spalte ordnet die Zeilen nach `data-<key>` in der Richtung von `data-dir`, setzt `aria-sort` nur am geklickten Knopf, entfernt `data-zonen` bei fremder Sortierung und setzt es bei `platz` wieder. Tooltip — Klick auf `abbr.kz` zeigt `.kz-tip` mit dem `title`-Text, zweiter Klick, Klick daneben, Escape und Scroll schließen, Enter auf fokussiertem Kürzel öffnet. **Nicht** getestet: die Position des Tooltips (jsdom rechnet kein Layout).
   - *CI:* im R-Job vor `test_dir` ein Schritt `npm ci` (Node ist auf `ubuntu-latest` vorhanden, ggf. `actions/setup-node` für eine feste Version). In der CI darf kein JS-Test skippen — gleiche Regel wie Punkt 7 für Rust.
   - *Wächter:* keine Änderung nötig, weil die Dateien dem Schema `test-<einheit>-<thema>.R` folgen; die Präfixliste bleibt `scripts`, `waechter`.
   - *Bewusst nicht:* JS in `assets/site.js` auslagern (widerspräche den freigegebenen Tests „kein `<script src=`" in `test-generate-static-site.R:242/330`, `test-ligatabelle-sektion.R:126`; nur als eigene Entscheidung, falls das JS deutlich wächst), R-Paket V8 (kein DOM), Headless-Browser (unverhältnismäßig).
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
- Entschieden am 25.09.: Zieltabelle freigegeben; Beweisläufe mit **und** ohne Rust-Server, je mit dem erwarteten Verhalten (Task 3); lokale Altlasten gelöscht.
- Entschieden am 25.09.: Client-JS per Node + jsdom mit Syntaxprüfung, Skripte bleiben inline (Stufe 4 Punkt 3).
- Entschieden am 26.09. (Review vor Stufe 2, vier Punkte): (1) keine flächige `source_module()`-Ersetzung in Stufe 2 — nur die 13 `source_aufstieg()`-Stellen aus Phase 5, Rest als PR 3.0 (Task 6 Regel 3); (2) der Wächter akzeptiert „nennt die Einheit oder einen ihrer Lader", damit die sechs `test-render_sections-*.R` bestehen (Task 5); (3) Zwischen-Definitionen folgen ihren Blöcken, einfassige Mehrfach-Helfer nach `helper-html.R`/`helper-repo.R`/`helper-fixtures.R` (Task 6 Regel 2); (4) der Wächter wird zuerst geschrieben, zuletzt committet (Task 5 Step 2). Dazu Ergänzung ohne Entscheidung: beide Aufnahmen in frischen Worktrees mit je einem frisch gebauten Binary (Task 3).
- Geprüft am 26.09.: alle 68 Dateien laufen isoliert (je eigener R-Prozess) grün — 787 Blöcke, 0 Fehlschläge, 0 Fehler, 10 Skips ohne Rust; Voraussetzung für den Einzellauf je Commit (Task 6 Regel 5) ist damit erfüllt.
- Offen für Christoph: Reihenfolge Stufe 3.1–3.8.
