# ELO-Kalibrierung für neue Ligen

Erzeugt Start-ELO-Werte für Ligen ohne Historie (fünf Regionalligen,
Frauen-Bundesliga, 2. Frauen-Bundesliga) auf der bestehenden ELO-Skala.

## Überblick

Der Simulator kennt eine Liga nur über die ELO-Werte ihrer Teams. Für die
drei Altligen wachsen diese Werte seit Jahren aus den Ergebnissen; für neue
Ligen gibt es keinen solchen Verlauf. Dieses Skript stellt ihn her: Es
lässt alle verfügbaren historischen Spiele einmal durchlaufen und eicht
das Ergebnis so ein, dass es zu den bestehenden Ligen passt.

Der Lauf ist **einmalig**. Danach führt der reguläre Saisonwechsel
(`scripts/season_transition.R`) die Werte fort.

## Voraussetzungen

- [ ] Laufender Rust-Server (`RUST_API_URL`, Default `localhost:8080`)
- [ ] `RAPIDAPI_KEY` gesetzt — nur nötig, wenn der Fixture-Cache leer ist
- [ ] Rund 70 freie API-Requests beim ersten Lauf

Den Rust-Server starten:

```bash
cd league-simulator-rust && cargo run --release
```

> Auf macOS mit Dropbox-synchronisiertem Projektordner schlägt der Build
> fehl (`Operation not permitted`). Dann mit einem Zielverzeichnis
> ausserhalb der Synchronisation bauen:
> `CARGO_TARGET_DIR=/tmp/lsr-target cargo build --release`

## Ausführung

**Immer zuerst als Dry-Run.** Ohne `--confirm` wird nichts geschrieben:

```bash
Rscript scripts/calibrate_historical_elo.R
```

Die Ausgabe zeigt je Liga den ELO-Walk, beide Ankerungen und eine
Prüftabelle. Erst wenn die Werte plausibel aussehen:

```bash
Rscript scripts/calibrate_historical_elo.R --confirm
```

| Option | Wirkung |
|---|---|
| `--confirm` | Ergebnis tatsächlich schreiben (sonst Dry-Run) |
| `--refresh` | Fixtures neu von der API holen statt aus dem Cache |
| `--season <jahr>` | Zielsaison (Default: 2026) |
| `--out <datei>` | Ausgabedatei (Default: `RCode/TeamList_<saison>_neu.csv`) |

## Was das Skript tut

1. **Beschaffen** — alle verfügbaren Saisons je Liga
   (Regionalligen ab 2019, Frauen-BL ab 2016, 2. Frauen-BL ab 2023).
   Die Rohantworten landen unter `data/fixture_cache/` und werden nicht
   erneut geholt.
2. **ELO-Walk** — je Liga chronologisch durch alle Saisons. Gerechnet wird
   im Rust-Server (`POST /league-details`), nicht in R: So ruht die
   Kalibrierung auf derselben Physik wie jede Prognose (ADR 0002).
   Alle Teams starten auf einem gemeinsamen Wert; die Rangfolge entsteht
   allein aus den Ergebnissen.
3. **Ankerung Regionalligen → 3. Liga** — der gesamte RL-Block wird so
   verschoben, dass die Aufsteiger im Mittel dort landen, wo die Absteiger
   der 3. Liga stehen. Anschliessend werden die fünf Staffeln
   gegeneinander justiert, gemessen daran, wie stark ihre Aufsteiger
   später in der 3. Liga waren — gedämpft auf die Hälfte, weil je Staffel
   nur zwei bis sechs Aufsteiger vorliegen.
4. **Ankerung Frauen → Herren** — zuerst die 2. Frauen-BL an die
   Frauen-BL (wieder über Auf- und Absteiger), dann beide gemeinsam auf
   den Mittelwert der Herren-Bundesliga. Das ist eine **Konvention**,
   keine Messung: Beide obersten Ligen gelten als gleich stark, weil sie
   nie gegeneinander spielen und jede Abstufung unbelegbar wäre.
5. **Schreiben** — eine CSV im TeamList-Format, erweitert um `League`,
   `Region` und `Name`.

## Ergebnis prüfen

Die Prüftabelle am Ende zeigt je Liga Mittelwert, Streuung und die
Remisquote, die das Modell daraus erzeugt, gegen die tatsächlich
beobachtete.

**Erwartete Werte** (Stand September 2026):

| Liga | Mittel | SD |
|---|---:|---:|
| Frauen-Bundesliga | 1682 | 257 |
| 2. Frauen-Bundesliga | 1386 | 134 |
| 3. Liga (Anker) | 1156 | 97 |
| RL West | 995 | 132 |
| RL Nordost | 965 | 136 |
| RL SüdWest | 950 | 123 |
| RL Nord | 911 | 129 |
| RL Bayern | 898 | 132 |

Die Liga-Abstände (284 → 242 → 214) setzen die Verengung der bestehenden
Leiter fort — das ist das wichtigste Plausibilitätssignal.

**Bekannte Abweichung:** Bei den Frauen-Ligen bleibt die modellierte
Remisquote rund 5 Prozentpunkte über der beobachteten. Der ELO-Walk
erreicht nicht die Spreizung, die das unabhängige Poisson-Modell dafür
bräuchte (nötig wären SD ~458, der Walk liefert 257). Das ist eine Grenze
des Tormodells, keine fehlerhafte Kalibrierung, und wird bewusst nicht
nachjustiert — siehe
[Empirie-Report](../reports/2026-09-05-liga-empirie-zehn-ligen.md).

## Fehlerbilder

| Symptom | Ursache |
|---|---|
| `Rust-Server nicht erreichbar` | Server läuft nicht — siehe Voraussetzungen |
| `kein Spiel mit bekannten Teams uebrig` | Rundenfilter hat alles verworfen; Rundenbezeichnungen der Liga prüfen |
| `kein freies Kuerzel fuer '<Verein>'` | Über 700 Vereine mit gleichem Namensstamm — praktisch ausgeschlossen |
| `RAPIDAPI_KEY environment variable not set` | Cache leer und kein Schlüssel gesetzt |
