# Relaunch fussball.csdatascience.de → „30 Punkte“

## Context

Seit dem Umzug auf Selbst-Hosting (ADR 0001, Caddy + Volume `fussball-site`) gibt es keine Plattform-Grenzen mehr: Die Seite kann mehr Inhalt tragen und besser aussehen. Ziel ist ein Major Relaunch in drei Dimensionen: (1) Design aus dem Schwerdtfeger-Design-Vokabular, angepasst auf den Zweck (nüchtern, Weißflächen, responsive, für zahlengetriebene Fußballinteressierte), (2) neue Inhalte (Rückblick, Ausblick, Ligatabelle mit ELO), (3) eine Methodik-Seite auf Basis des 30-Punkte-Blogartikels von 2015.

**Kernbefund der Exploration:** Es wird heute nichts historisiert — muss es aber auch nicht. Saisonstart-ELO (TeamList-CSV) + Ergebnisse in Spielreihenfolge ergeben deterministisch die ELO-Kette; das Poisson-Tormodell liefert 1/X/2 und die komplette Score-Matrix analytisch in geschlossener Form. Alle neuen Inhalte sind zur Renderzeit berechenbar, ohne Monte Carlo, ohne Persistenz.

## Getroffene Entscheidungen (Grill-Session 2026-08-28)

1. **Identität:** Die Seite heißt „30 Punkte“. Design aus dem Schwerdtfeger-Vokabular (Source Serif 4, Weiß `#FFFFFF`, Ink `#15130F`, rote Haarlinie `#B0261E` einmal pro Fläche, Radii ≤ 2 px, keine Schatten, korrekte deutsche Typografie). Elemente des alten Blog-Templates werden **nicht** übernommen (war ein Fremd-Template).
2. **Struktur:** Drei lange Liga-Seiten (`index.html`, `2-bundesliga.html`, `3-liga.html`) + eine Methodik-Seite (`methodik.html`). Keine Startseite, keine Spiel-Detailseiten.
3. **Sektionen je Liga-Seite:** Prognose-Heatmap → Ligatabelle mit ELO → Rückblick → Ausblick (Reihenfolge im Mock-up finalisieren).
4. **Heatmap:** HTML-Tabelle (Zellen mit Hintergrundfarbe nach Wahrscheinlichkeit, Zahlen als Text, tabular numerals) statt ggplot-PNG. Die PNG-Pipeline entfällt ersatzlos.
5. **Ligatabelle:** kombinierte Liga-/ELO-Tabelle. Spalten: Platz · Team · Spiele · Tordifferenz · Punkte · ELO · Δ ELO (seit Saisonbeginn). Default nach Platz sortiert; per Klick sortierbar nach Punkten und ELO (absteigend). Vanilla-Inline-JS, progressive enhancement (ohne JS: nach Platz).
6. **Rückblick:** alle Spiele, die seit Beginn des zuletzt abgeschlossenen Spieltags beendet wurden — d. h. der letzte abgeschlossene Spieltag, die bereits gespielten Spiele des laufenden Spieltags und frisch gespielte Nachholspiele älterer Spieltage (mit Kennzeichnung „Nachholspiel, N. Spieltag“). Pro Spiel: ex-ante 1/X/2, tatsächliches Ergebnis, ELO-Anpassung beider Teams.
7. **Spieltag-Definition (statusbasiert):** Ein Spieltag ist **abgeschlossen**, wenn jedes seiner Spiele beendet oder verschoben (api-football-Status PST/CANC/TBD) ist. Er ist **laufend**, wenn mindestens ein Spiel beendet/live ist und mindestens ein nicht-verschobenes Spiel aussteht. Verschobene Spiele halten einen Spieltag nicht offen.
8. **Ausblick:** spiegelbildlich — offene, nicht verschobene Spiele des laufenden Spieltags bzw. der komplette nächste Spieltag, plus früher angesetzte Nachholspiele. Pro Spiel: Termin, 1/X/2, aufklappbare Score-Matrix (`<details>`, Heimtore × Auswärtstore).
8a. **Laufende Spiele (Planergänzung 2026-08-28):** werden berichtet (Zwischenstand), aber ohne Prognose — mit dem Hinweis, dass Prognosen während des Spiels nicht aktualisiert werden. Eigene Fensterfunktion `live_matches()`; Rückblick/Ausblick schließen Live-Spiele aus.
9. **Berechnung:** neuer deterministischer **Rust-Endpoint** (eine Quelle für Modellkonstanten; R bleibt Renderer). Keine Persistenz. Bewusst offen: Prognose-*Verläufe* (z. B. P(Meister) über die Zeit) wären nicht rekonstruierbar; falls je gewünscht, ab dann Snapshots schreiben.
10. **Methodik-Seite:** 2015er Artikel „Was die Prognosen mit Schach zu tun haben“ als Gerüst, redaktionell aktualisiert und erweitert (Heimvorteil +65, Poisson-Tormodell, Zweitvertretungs-Regel, Aktualisierungsrhythmus), in der 30-Punkte-Stimme (`brand/voice-reference.md`). Christoph redigiert vor Veröffentlichung.
11. **Fonts:** selbst gehostete woff2 (Source Serif 4, ggf. Inter Tight/JetBrains Mono) in `assets/` — kein Google-Fonts-CDN (DSGVO), Seiten bleiben selbstenthaltend.
12. **Mock-ups:** klickbares HTML-Artifact mit echten Daten (Fixture `ShinyApp/data/Ergebnis.Rds` + reale Fixtures), Iteration bis Freigabe, erst dann Übersetzung in R-Templates.
13. **Shiny-Preview:** `ShinyApp/app.R` und Shiny-Abhängigkeit werden ausgebaut; lokale Vorschau = Generator laufen lassen + HTML öffnen (kleines Script `scripts/preview_site.R`).
14. **Erhalten bleibt:** der clientseitige Stale-Banner (24 h), die Selbstenthaltenheit der Seiten, das Deployment-Modell (Volume + Caddy, pull-based CI-Image) — daran ändert der Relaunch nichts.

## Phasen

### Phase 1 — Design festklopfen (Mock-up + Texte)

- HTML-Mock-up einer Liga-Seite (Bundesliga) als privates Artifact: alle Ziel-Sektionen mit echten Daten, Desktop + Mobil. Design-Grundlage: `~/.claude/skills/schwerdtfeger-design/` (README.md, `colors_and_type.css`); Heatmap-Farbskala im Mock-up klären (im System gibt es kein Stahlblau; Kandidat: Ink-Abstufung; Rot bleibt der einen Haarlinie vorbehalten).
- Mock-up der Methodik-Seite inkl. Textentwurf (Basis: Blogartikel, ~280 Wörter Kern, erweitert). Christoph redigiert.
- Iteration bis Freigabe.
- Doku-Grundstein (erster Commit): CONTEXT.md-Glossar ergänzen und ADR 0002 anlegen (Entwürfe unten).

### Phase 2 — Datenfundament (Rust + R, ohne sichtbare Änderung)

**Rust (`league-simulator-rust/`):**
- Neuer Endpoint, z. B. `POST /league-details`: nimmt dieselbe Eingabe wie `/simulate` (Spielplan + Initial-ELO), macht den deterministischen ELO-Walk (Logik existiert in `simulate_season_in_place`, `src/simulation/season.rs`) und liefert pro Spiel: ex-ante-ELO beider Teams, λ-Paar, P(1/X/2), Score-Matrix (0–7 je Seite + Restmasse), für gespielte Spiele die ELO-Anpassung; zusätzlich je Team die aktuelle ELO. Konstanten aus `src/simulation/match_sim.rs` (`tore_slope`, `tore_intercept`, Heimvorteil +65 aus `src/elo/mod.rs`) wiederverwenden — nichts duplizieren.
- Tests: Golden-Tests gegen von Hand gerechnete Beispiele; Eigenschaft „Zeilensumme Score-Matrix ≈ 1“.

**R:**
- `RCode/transform_data.R`: Spieltermin (`fixture$date`), Spieltag (`league$round`) und Status (`fixture$status$short`) durchreichen statt verwerfen (neue Spalten oder separates Fixtures-Objekt).
- Neues Modul `RCode/league_details.R` (o. ä.): Spieltag-Klassifikation (abgeschlossen/laufend nach Def. 7), Rückblick-/Ausblick-Fensterung, Ligatabellen-Berechnung (Punkte, Tordifferenz, Spiele aus Ergebnissen), Client für den neuen Endpoint (Muster: `RCode/rust_integration.R`).
- Signatur-Erweiterung am Aufrufort `RCode/update_all_leagues_loop.R:160–166`: Fixtures/TeamList zusätzlich zu den vier Ergebnis-Objekten übergeben.
- Tests für Spieltag-Logik (Szenarien: Freitagsspiel gespielt; Nachholspiel am Dienstag; verschobenes Spiel).

### Phase 3 — Design-Umsetzung (erster sichtbarer Rollout)

- `RCode/generate_static_site.R` + `RCode/league_views.R` umbauen: neues Layout/CSS nach freigegebenem Mock-up, HTML-Heatmap (ersetzt `display_result`-PNG), Masthead „30 Punkte“, Methodik-Seite, Fonts + Favicon + Meta/OG-Tags in `assets/`, responsive (Tabellen in `overflow-x`-Containern). Stale-Banner-Mechanik übernehmen.
- Wiederverwenden: `groupResultsDF()`, `prozent()` aus `RCode/render_helpers.R`; `.stale_script`-Muster.
- Ausbau: ggplot/reshape2-Heatmap-Pfad, `ShinyApp/app.R`, Shiny aus `packagelist.txt` (prüfen, ob andernorts genutzt); `scripts/preview_site.R` als Ersatz. `CLAUDE.md`-Quick-Commands anpassen.
- Kann vor oder zusammen mit Phase 4 deployt werden — die Seite ist auch ohne die neuen Sektionen vollständig (dann Heatmap + Prognose-Panels + Methodik im neuen Design).

### Phase 4 — Neue Inhalte sukzessive

- 4a: Ligatabelle mit ELO/Δ ELO + Sortier-JS.
- 4b: Rückblick (ex-ante 1/X/2, Ergebnis, ELO-Anpassung).
- 4c: Ausblick (Termine, 1/X/2, `<details>`-Score-Matrizen).
- Jeder Schritt einzeln deploybar (CI-Image, Host-Pull nach pinned SHA).

### Nebenarbeiten (in Phase 2/3 miterledigen)

- `docs/architecture/data-flow.md:139–170` beschreibt eine `Ergebnis.Rds`-Struktur, die es nicht gibt — korrigieren.
- `docs/deployment/static-site.md` und Architektur-Doku an neue Seitenstruktur anpassen; `docs/architecture/overview.md` erwähnt noch ShinyApps-Deployment.
- Hinweis: `Ergebnis.Rds` ist ein `save()`-Image (mit `load()` lesen, nicht `readRDS()`).

## Doku-Entwürfe (in Phase 1 committen)

**CONTEXT.md-Glossar, neue Begriffe:**
- **Ligatabelle** — die aus den Ergebnissen berechnete aktuelle Tabelle einer Liga inkl. ELO und Δ ELO seit Saisonbeginn; default nach Platz, clientseitig sortierbar.
- **Abgeschlossener Spieltag** — Spieltag, dessen Spiele sämtlich beendet oder verschoben (PST/CANC/TBD) sind.
- **Laufender Spieltag** — Spieltag mit mindestens einem beendeten/laufenden und mindestens einem offenen, nicht verschobenen Spiel.
- **Rückblick** — Sektion je Liga-Seite: alle seit Beginn des zuletzt abgeschlossenen Spieltags beendeten Spiele (inkl. gekennzeichneter Nachholspiele) mit ex-ante 1/X/2, Ergebnis, ELO-Anpassung.
- **Ausblick** — Sektion je Liga-Seite: offene Spiele des laufenden bzw. der nächste Spieltag, plus früher angesetzte Nachholspiele; je Spiel Termin, 1/X/2, Score-Matrix.
- **Score-Matrix** — analytisch (Poisson) berechnete Wahrscheinlichkeitsmatrix Heimtore × Auswärtstore eines Spiels.
- **Methodik-Seite** — vierte statische Seite mit den Erläuterungen des Prognosemodells.
- Eintrag **Statische Seite** aktualisieren (vier Seiten, keine PNG-Heatmaps mehr).

**ADR 0002 — „Spieldetails werden deterministisch zur Renderzeit berechnet, nicht persistiert“:** Kontext (keine Historie vorhanden; ELO-Kette und Poisson-Modell deterministisch aus TeamList + Ergebnissen), Entscheidung (Rust-Endpoint, R als Renderer, keine Snapshots), Konsequenz (Prognose-Verläufe über die Zeit nicht rekonstruierbar; Snapshot-Schreiben erst bei konkretem Bedarf), Verworfen (R-Duplikat der Modelllogik: Drift; Persistenzschicht: Infrastruktur ohne aktuellen Nutzen).

## Verifikation

- **Phase 2:** `cargo test` im Rust-Crate; `testthat::test_file()` für Spieltag-Logik und Tabellenberechnung; Endpoint manuell gegen bekannten Spielplan prüfen (ELO-Summe konstant, Wahrscheinlichkeiten summieren zu 1).
- **Phase 3/4:** Generator lokal gegen echte Saison-Fixtures laufen lassen (`scripts/preview_site.R`), Seiten im Browser prüfen (Desktop + Mobil-Viewport, mit/ohne JS, Stale-Banner durch Uhr-Manipulation); bestehende `tests/testthat/`-Suite für `generate_static_site` aktualisieren und grün halten; ein voller Scheduler-Durchlauf im Docker-Compose-Stack vor dem Host-Pull.
- **Rollout je Phase:** CI-Image bauen lassen, auf dem Host per pinned SHA ziehen, einen Spieltag beobachten (bewährtes Muster aus dem Hosting-Umzug).
