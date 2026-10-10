# Struktur der Testsuite

Entschieden am 25.09.2026 (#211, Plan `docs/plans/2026-09-15-testsuite-umbau-und-folgeschritte.md`).
Seit Stufe 2 erzwingt `test-waechter-teststruktur.R` die Regel.

## Regel

**Der Dateiname sagt, welche Einheit geprüft wird — nie, welche Änderung den Test veranlasst hat.**

`test-<einheit>.R` oder `test-<einheit>-<thema>.R`
- `<einheit>` ist exakt der Dateistamm einer Datei in `RCode/` (`league_details`, `updateScheduler`) — oder eines der festen Präfixe `scripts` (dann folgt der Stamm einer Datei unter `scripts/`: `test-scripts-preview_site.R`) oder `waechter` (Meta-Tests, die Quelltext als Text lesen). Einheitsnamen enthalten keinen Bindestrich; alles bis zum ersten Bindestrich nach `test-` ist daher die Einheit.
- `<thema>` ist optional und benennt eine Funktion oder ein Verhalten der Einheit (`-gating`, `-rueckblick`, `-verdrahtung`); nie Issue, PR, Phase oder Reparatur (`phase5`, `haertung`, `move`, `fix`, Nummern). Ein Thema lohnt sich, wenn die Datei sonst deutlich über ~1.000 Zeilen wüchse oder die Tests eigene Helfer/Fakes brauchen.
- Zuordnung im Zweifel: die Einheit, deren Funktion der Test aufruft und deren Ergebnis er prüft; rufen mehrere, die äußerste (der Aufrufer). Gestubbte oder nur gesourcte Mitspieler zählen nicht.
- Jede Testdatei nennt ihre Einheit im Quelltext — per `source()`-Literal `<einheit>.R` oder `source_module("<einheit>", ...)` aus `helper-source.R` (mehrere Einheiten erlaubt; die eigene muss dabei sein). Eine Einheit gilt auch als gesourct, wenn die Datei eine Einheit nennt, die sie per `source()` mitlädt (`render_sections` über `generate_static_site`). Eigene `source_xyz()`-Helfer nur, wenn sie mehr tun als sourcen. Gemeinsame Helfer heißen `helper-<zweck>.R` (testthat lädt sie automatisch); keine Helferdefinition in zwei Dateien — was mehr als eine Testdatei braucht, steht in einer `helper-*.R`; eine lokale Variante, die etwas anderes tut, bekommt einen eigenen Namen (`fake_fixtures_je_liga`, `fake_response_status`). Unterordner (`fixtures/`, `helpers/`) enthalten nur Daten und explizit gesourcte Runner, nie Tests — testthat liest sie nicht.
- Wird eine `RCode/`-Datei geteilt, umbenannt oder gelöscht, ziehen ihre Testdateien im selben PR mit (`git mv`); `test-waechter-teststruktur.R` schlägt sonst fehl.
- Kein Top-Level-Name (Zuweisung `name <- ...`) steht in zwei Testdateien — jede Testdatei läuft zwar in eigener Umgebung, aber ein doppelter Name erschwert die Suche, lässt offen, welche Definition gemeint ist, und verbirgt Helfer-Dopplungen (seit Stufe 4.7 vom Wächter geprüft; Meldung „name: datei1, datei2“).
- Kein Top-Level-Name einer Testdatei überschattet einen Namen aus einer `helper-*.R` — sonst gilt je nach Kontext die lokale oder die gemeinsame Definition (seit Stufe 4.7 vom Wächter geprüft; Meldung „name: datei“).
- Die in `helper-test-setup.R` vom globalen Laden ausgenommenen RCode-Dateien (`exclude_patterns`) sourct eine Testdatei nur mit `local = TRUE` — sonst landen sie doch in `globalenv` und sind für alle später laufenden Dateien sichtbar (seit dem Abschluss von #211 vom Wächter geprüft; Meldung „datei: pfad“).
- Neue Testarten laufen, wo möglich, als R-Test unter der Einheit, die den Gegenstand erzeugt (Client-JS: `test-render_sections-js.R`, #212). Nur was sich keiner Einheit zuordnen lässt, bekommt ein festes Präfix, das in `test-waechter-teststruktur.R` in die geschlossene Liste aufgenommen wird.
- Ausführen einer Einheit mit allen Themen: `testthat::test_dir("tests/testthat", filter = "^league_details")`.

## Helfer

| Datei | Inhalt |
|---|---|
| `helper-test-setup.R` | globales Sourcing (`source_rcode_modules`); seit Stufe 4.1 bricht ein Sourcing-Fehler die Suite mit R-Fehler ab statt als `message()` zu verschwinden |
| `helper-fixtures.R` | Test-Saisons und API-Attrappen (`create_test_season`, ..., `mk_ergebnis`, `ewr_spiel`/`ewr_fixtures`/`ewr_teams`, `RL_IDS`/`RL_SLUGS`/`AUFSTIEGSSEITE_SLUG`/`RL_DIREKTAUFSTIEG`/`RL_AUFSTIEGSSPIELE`); seit Stufe 3.6 auch `RL_SCHLUESSEL`, Regionalliga-Aufstieg-Attrappen (`prognose_aus_meister`, `meister_nord`/`meister_bayern`, `sieg_nord_gegen_bayern`, `prognosen_2026`), Abstiegskopplung-Attrappen (`STAFFELN_ERWARTET`, `N_ITER`, `K_DRITTE_LIGA`, `zaehlung`, `zaehlung_nordost89`, `prognose_zeile`) und Loop-Attrappen (`n_ligen`, `n_sims_pro_runde`, `fake_fixtures`, `fake_transformed`) |
| `helper-league-details.R` | `fd_row`, `make_details`, `make_test_teams` |
| `helper-elo-verlauf.R` | seit #184: `verlauf_teams`, `verlauf_spiel`, `verlauf_entry` (league_entry ohne Rust), `verlauf_beispiel` (vier Vereine, drei Runden, Varianten für Nachhol-, gewertete, verschobene, abgesagte Spiele), `verlauf_site` (rendert die Site in ein Temp-Verzeichnis) |
| `helper-uhr.R` | `runden_uhr` (steuerbare Uhr für Loop-Tests) |
| `helper-source.R` | seit Stufe 2: `source_module(...)`, lädt RCode-Einheiten in eine Umgebung; seit Stufe 3.6 `fn(env, name)` (holt eine Funktion daraus, klare Meldung, wenn sie fehlt) |
| `helper-html.R` | seit Stufe 2: `read_html`, `make_data_env`; seit Stufe 3.6 `html_lesen` (wie `read_html`, aber mit `encoding = "UTF-8"`) |
| `helper-rust.R` | seit Stufe 3.6: `skip_if_no_rust(env)` (skippt ohne erreichbaren Rust-Server), `rust_binary`, `start_rust_server`/`stop_rust_server` (eigenes Binary auf eigenem Port). Seit Stufe 4.1 gilt in der CI: `scripts/ci/testthat_ci.R` listet jeden Skip-Grund und bricht mit `RUST_SKIPS_VERBOTEN=1` ab, sobald ein Test trotz laufendem Rust-Server wegen Rust skippt — ein solcher Skip ist dort ein Fehler, kein grünes Ergebnis. |
| `helper-js.R` | seit Stufe 4.6: `skip_ohne_js()` (Skip-Text „Node/jsdom fehlt“), `js_szenario()`, `js_skripte_aus_html()`, `js_syntax_status()`, `js_assets_einbetten()`. Node/jsdom lokal per `npm ci`; in der CI sind sie Pflicht (`JS_SKIPS_VERBOTEN=1`), ein Skip wegen Node/jsdom ist dort ein Fehler |
| `helper-repo.R` | seit Stufe 2: `with_repo_root` |
| `helper-teamlist.R` | seit #271: `aktuelle_teamlist_pfad()` – die TeamList der aktuellen Saison (aus `SEASON`, sonst neueste `TeamList_<Jahr>.csv`) für **Datenprüfungen**; bricht ab statt zu skippen, wenn sie fehlt. Datenprüfungen tragen „Datenpruefung:“ im Titel; Einheitentests nehmen eine Fixture, nie die produktive Liste |
| `helpers/js-runner.mjs` | explizit aufgerufener Node-Runner (jsdom), kein Test |
| `helpers/season-transition-snapshot-runner.R` | explizit gesourcter Runner, kein Test |
| `fixtures/` | Testdaten, u. a. `fixtures/fixture_cache/` (eingefrorene RL-Spielpläne, siehe README dort) |

## Zieldateien

787 `test_that`-Blöcke aus 68 Quelldateien, Stand 25.09.2026, dazu 6 Wächterblöcke (793). Die Einzelzuordnung je Block steht in `docs/plans/2026-09-15-testsuite-zuordnung.csv` (Spalte `ziel_final`); „(n Bl.)" markiert Quelldateien, die aufgeteilt werden. Stufe 3 hat seither 35 Blöcke als Doppel gestrichen (PRs #247–#250, #252) sowie zwei Kompatibilitätstests des Vier-Argument-Pfads (PR #253); die CSV führt sie in `bemerkung` als „gestrichen".

| Zieldatei | Blöcke | nimmt auf |
|---|---|---|
| `test-api_service.R` | 3 | team-short-name |
| `test-aufstiegsspiele.R` | 43 | aufstiegsspiele |
| `test-checkAPILimits.R` | 11 (+1, Stufe 4.4a: `checkAPILimits meldet, ob die Planung aus einem Fallback kam`, aus `test-update_all_leagues_loop-gating.R`) | check-api-limits, frauen-ligen-aktivierung (1 Bl.) |
| `test-csv_generation.R` | 23 | saisonwechsel-entwurf, saisonwechsel-format |
| `test-elo_aggregation.R` | 12 | ein-elo-walk (12 Bl.) |
| `test-elo_calibration.R` | 30 | elo-calibration |
| `test-fixture_cache.R` | 6 (−3, Stufe 4.4a: die drei `is_regular_season_round`-Blöcke nach `test-round_filter.R`) | fixture-cache |
| `test-generate_static_site.R` | 64 | frauen-ligen-live (11 Bl.), generate-static-site, live-na-guard, n-ligen-entflechtung (5 Bl.), phase5-regionalligen (15 Bl.) |
| `test-generate_static_site-js.R` | 4 | — (neu in Stufe 4.6: Veraltet-Hinweis in Node + jsdom) |
| `test-generate_static_site-tooltip.R` | 10 | kuerzel-tooltip (10 Bl.) |
| `test-input_handler.R` | 7 | — (neu in Stufe 4.5: `input_handler.R` hatte keinen eigenen Test, nur Stubs in `test-interactive_prompts.R`) |
| `test-interactive_prompts.R` | 11 | interactive-prompts |
| `test-league_details.R` | 49 | elo-walk-reihenfolge (3 Bl.), fixture-details-produktionsform, fixture-details, gewertete-spiele (11 Bl.), kuerzel-tooltip (1 Bl.), ligatabelle, rundenfilter-schutznetz (5 Bl.), spieltag-logik, tbd-termin (6 Bl.) |
| `test-league_details-client.R` | 13 (+1, Stufe 4.4b: `fetch_league_details postet an RUST_API_URL/league-details, Default localhost:8080, Fehler nennt Status und Body`, ersetzt den Signaturblock aus `test-league_details-seitendaten.R`; der bisherige Wert 11 in dieser Zeile war veraltet, tatsächlich waren es vorher 12) | league-details-client-haertung, league-details-client |
| `test-league_details-seitendaten.R` | 13 (−1, Stufe 4.4b: Signaturblock zu `fetch_league_details` entfernt, siehe `test-league_details-client.R`) | league-page-data-ausblick, league-page-data-rueckblick, league-page-data |
| `test-league_registry.R` | 42 | frauen-ligen-aktivierung (2 Bl.), league-registry (19 Bl.), n-ligen-entflechtung (3 Bl.), phase5-regionalligen (15 Bl.), rl-zonen-verdrahtung (3 Bl.) |
| `test-league_views.R` | 20 | frauen-ligen-live (4 Bl.), league-views, phase5-regionalligen (11 Bl.) |
| `test-rate_limit_takt.R` | 28 | rate-limit-takt |
| `test-render_helpers.R` | 2 (−1, Stufe 4.4b: reine Existenzprüfung gestrichen, gedeckt durch die zwei Folgeblöcke) | render-helpers-move |
| `test-render_sections-ausblick.R` | 9 | ausblick-sektion, tbd-termin (1 Bl.) |
| `test-render_sections-farbskala.R` | 1 | score-matrix-farbskala |
| `test-render_sections-js.R` | 9 | — (neu in Stufe 4.6: Sortierung und Kürzel-Tooltip in Node + jsdom) |
| `test-render_sections-rueckblick.R` | 13 | rueckblick-sektion |
| `test-render_sections-tabelle.R` | 9 | ligatabelle-sektion |
| `test-render_sections-tooltip.R` | 2 | kuerzel-tooltip (2 Bl.) |
| `test-render_sections-zonen.R` | 20 | rl-zonen-verdrahtung (13 Bl.), rl-zonenlinien |
| `test-retrieveResults.R` | 2 | retrieveResults |
| `test-retrieveResults-rate-limit-header.R` | 5 | rate-limit-header |
| `test-rl_abstiegskopplung.R` | 50 | phase5-regionalligen (8 Bl.), rl-abstiegskopplung |
| `test-rl_abstiegskopplung-nord.R` | 19 | rl-nord-aufstiegskopplung |
| `test-rl_aufstieg.R` | 37 | phase5-regionalligen (13 Bl.), rl-aufstieg |
| `test-rl_verdrahtung.R` | 2 | rl-verdrahtung (2 Bl.) |
| `test-round_filter.R` | 8 (+3, Stufe 4.4a: `is_regular_season_round` aus `test-fixture_cache.R`) | phase5-regionalligen (5 Bl.) |
| `test-rust_integration.R` | 4 | home-advantage-single-source, league-registry (1 Bl.), tormodell-rust-durchreichung |
| `test-scripts-preview_site.R` | 6 | frauen-ligen-live (1 Bl.), preview-site |
| `test-scripts-season_transition.R` | 5 | season-transition-cleanup-wrapper, season-transition-csv-snapshot |
| `test-scripts-testthat_ci.R` | 8 (+1, Stufe 4.6: `js_skips`) | — (neu in Stufe 4.1: `scripts/ci/testthat_ci.R`) |
| `test-scripts-zuordnung_tests.R` | 8 | scripts-zuordnung_tests |
| `test-season_processor.R` | 20 (−2, Stufe 4.5: die zwei `team_data_carryover`-Bestandsbloecke nach `test-team_data_carryover.R`; +1, #267: `source_with_fallback` von dort hierher) | saisonwechsel-schutzgrenzen, season-processor, season-transition-validators, team-count-validation |
| `test-season_processor-regression.R` | 10 | season-transition-regression |
| `test-season_validation.R` | 16 | frauen-ligen-aktivierung (1 Bl.), season-validation |
| `test-staffel_zuordnung.R` | 10 | staffel-zuordnung |
| `test-Tabelle.R` | 6 | — (neu in Stufe 4.5: `Tabelle()` war nur in `test-elo_aggregation.R` gestubbt, nie selbst ausgefuehrt) |
| `test-team_data_carryover.R` | 7 (−1, #267) | season-processor (2 Bl., Stufe 4.5) |
| `test-team_history_resolver.R` | 7 | team-history-resolver |
| `test-team_record_builder.R` | 9 | team-record-builder |
| `test-transform_data.R` | 30 | elo-walk-reihenfolge (10 Bl.), gewertete-spiele (2 Bl.), rundenfilter-schutznetz (7 Bl.), transform_data |
| `test-transform_data-kuerzel.R` | 23 | kuerzel-vertrag, teamlist-eindeutigkeit |
| `test-update_all_leagues_loop.R` | 6 | n-ligen-entflechtung (4 Bl.), update-loop-league-data |
| `test-update_all_leagues_loop-gating.R` | 36 (−1, Stufe 4.4a: `checkAPILimits meldet, ob die Planung aus einem Fallback kam` nach `test-checkAPILimits.R`) | update-loop-gating |
| `test-update_all_leagues_loop-rust.R` | 2 | rust-required |
| `test-update_all_leagues_loop-sicherheitsnetz.R` | 4 | sicherheitsnetz-zeit |
| `test-update_all_leagues_loop-verdrahtung.R` | 21 | rl-verdrahtung (21 Bl.) |
| `test-updateScheduler.R` | 15 | frauen-ligen-aktivierung (4 Bl.) |
| `test-waechter-ci-pfade.R` | 2 | ein-elo-walk (2 Bl.) |
| `test-waechter-quelltext.R` | 9 | ein-elo-walk (3 Bl.), frauen-ligen-aktivierung (1 Bl.), kuerzel-tooltip (1 Bl.), modellkonstanten-nur-in-rust, phase5-regionalligen (1 Bl.) |
| `test-waechter-teststruktur.R` | 6 (seit Stufe 4.7: 8) | — (neu in Stufe 2, prüft die Namenskonvention selbst) |

## Werkzeuge

- `scripts/dev/zuordnung_tests.R` schlägt je Block eine Einheit vor (Aufrufe, `source()`-Köpfe, `stub()`-Ziele) und schreibt die CSV.
- `scripts/dev/ergebnisse_tests.R` schreibt die Einzelergebnisse je Block als CSV — Grundlage des Vorher/Nachher-Vergleichs.
- `scripts/dev/blockmenge_tests.R` vergleicht die Multimenge aller `test_that()`-Blocktexte zweier Testverzeichnisse — Nachweis für reine Refactoring-PRs (`Rscript scripts/dev/blockmenge_tests.R <dirA> <dirB>`).
