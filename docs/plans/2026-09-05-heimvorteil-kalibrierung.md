# Heimvorteil neu kalibrieren: 65 → 40 ELO

> Eigenständiger Kurzplan, unabhängig vom Ligen-Ausbau
> (`docs/plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md`). Soll zeitnah raus.

## Context

Der Heimvorteil des Modells steht auf 65 ELO-Punkten. Die Messung an den Saisons 2024+2025
zeigt, dass das zu hoch ist: Der Simulator überzeichnet damit den Heimvorteil systematisch.

Warum jetzt: Zu Saisonbeginn hat jedes Team etwa gleich viele Heim- und Auswärtsspiele
absolviert, der Fehler hebt sich in der Tabelle weitgehend auf. Die Verzerrung wächst erst
im Saisonverlauf, wenn sich die Heim-/Auswärtsverteilung zwischen den Teams auseinander
entwickelt. Je früher die Korrektur greift, desto kleiner ihr Effekt auf die veröffentlichten
Zahlen — und desto weniger Prognosen beruhen auf dem falschen Wert.

## Der richtige Wert hängt vom Wirkungspfad ab

Zwei verschiedene Stellen im System nutzen „Heimvorteil", auf **verschiedenen Skalen**. Sie
brauchen daher verschiedene Werte — das ist kein Fehler, sondern ergibt sich aus der Physik:

| Wirkungspfad | Wo | Formel | Heute | Kalibriert |
|---|---|---|---|---|
| **Tormodell** | Rust: Simulation + Spieldetails | `λ = ±(Δ+HA)·tore_slope + intercept` | 65 | **40** |
| **ELO-Erwartung** | R: Saisonwechsel (`calculate_elo_update`) | `1/(1+10^(−HA/400))` | 100 | 25,8 |

Die Kalibrierung, jeweils gegen die gemessenen Bundesliga-Anteile (Heim 41,2 %, Remis 25,0 %,
Auswärts 33,8 %):

- **Tormodell:** Ligaweit über eine realistische ELO-Verteilung (N(1500, 141)) integriert
  liefert HA=40 die Anteile 41,0 / 24,4 / 34,7 — nahe an der Messung. HA=65 ergibt 43,0 %
  Heimsiege (zu hoch), HA=25 nur 39,8 % (zu niedrig).
- **ELO-Erwartung:** Der beobachtete Heim-Score-Anteil (Sieg + ½·Remis) ist 0,5370. HA=25,8
  trifft ihn fast exakt; die heutigen 100 implizieren 0,6401 — ein massiv überzeichneter
  Heimvorteil.

> Dass beide Werte in derselben Größenordnung liegen, ist ein Zufall der Skalen, keine
> Notwendigkeit. Sie dürfen nicht gleichgesetzt werden.

**Frühere Angabe korrigiert:** Der in der Ligen-Ausbau-Analyse genannte Wert „~25 ELO für alle
Ligen" stammte aus der Umkehrung der ELO-Erwartungsformel. Für das *Tormodell* — den Pfad, der
Prognose und Anzeige bestimmt — ist er zu niedrig; dort sind es 40. Für den Saisonwechsel
bleibt 25 richtig.

## Umfang dieses Plans

**Enthalten:** Das Tormodell, also Simulation und Spieldetails — 65 → 40.

**Nicht enthalten:** `calculate_elo_update()` (Saisonwechsel, heute 100). Läuft nur einmal
jährlich im Juli, ist nicht zeitkritisch und braucht eine eigene Begründung. Wird als Notiz
festgehalten (siehe unten).

## Architektur: Rust bleibt die einzige Quelle

[ADR 0002](../../docs/adr/0002-spieldetails-deterministisch-zur-renderzeit.md) legt fest, dass
die Modellkonstanten „weiterhin nur in Rust" existieren und R reiner Renderer bleibt.

Faktisch ist das heute **nicht** erfüllt: Die 65 steht an vier Stellen in R
(`rust_integration.R:56`, `:143`, `:248`, `league_details.R:256`) und wird von beiden
Produktivpfaden **immer** mitgesendet — Rusts `unwrap_or(65.0)` greift nie. Dass Heatmap und
1/X/2-Werte heute übereinstimmen, liegt allein daran, dass die Defaults zufällig gleich sind.
Genau diese stille Kopplung kann auseinanderlaufen.

**Entscheidung:** Der Wert wird *nicht* als Konfiguration durch R gereicht. Stattdessen hört R
auf, ihn zu senden; Rust setzt ihn allein. Damit ist ein Auseinanderlaufen strukturell
unmöglich — es gibt nur noch einen Wert —, und ADR 0002 wird erstmals tatsächlich erfüllt statt
nur behauptet.

Das ist die kleinere Änderung *und* die robustere: Eine durchgereichte Konfiguration hätte zwei
Payload-Builder, zwei Defaults und einen ADR-Widerspruch zu pflegen.

## Änderungen

### Rust — der neue Wert

- `league-simulator-rust/src/models/mod.rs:84` — `home_advantage: 65.0` → `40.0`
- `league-simulator-rust/src/api/handlers.rs:157` — `unwrap_or(65.0)` → `unwrap_or(40.0)` (`/simulate`)
- `league-simulator-rust/src/api/handlers.rs:370` — `unwrap_or(65.0)` → `unwrap_or(40.0)` (`/league-details`)
- Doc-Kommentare `handlers.rs:91` und `:279` mitziehen

**Beide Handler zwingend gemeinsam.** Änderte man nur `/simulate`, nutzten Heatmap
(Monte Carlo) und Score-Matrix/1-X-2 (`/league-details`) verschiedene Heimvorteile — sichtbar
widersprüchlich auf derselben Seite.

### R — aufhören zu senden

- `RCode/rust_integration.R:81` — `home_advantage` aus dem Payload entfernen; Parameter und
  Default in `simulate_league_rust()` (`:56`) und `leagueSimulatorRust()` (`:143`) entfallen
- `RCode/league_details.R:286` — dito im Payload; Parameter-Default `:256` entfällt
- `RCode/rust_integration.R:248` — `simulate_leagues_batch_rust()` (nicht im Produktivpfad,
  der Konsistenz halber mitziehen)

Der Payload bleibt gültig: Beide Rust-Request-Structs führen `home_advantage` als
`Option<f64>`; ein fehlendes Feld ist bereits heute erlaubt.

### Methodik-Seite

`RCode/site_assets/methodik_content.html` — redaktioneller Inhalt, bewusst ohne R-Code:

- „Zuschlag von 65 ELO-Punkten" → 40, und der Halbsatz „so viel ist der eigene Platz im
  langjährigen Mittel wert" wird um die Herkunft ergänzt: geeicht an den beobachteten
  Heim-/Auswärtsanteilen.
- Das durchgerechnete Beispiel Bayern (2057) – Stuttgart (1805) neu:
  **1,8 / 0,8 Tore → 62 % / 22 % / 16 %** (heute: 1,9 / 0,8 → 64 % / 22 % / 14 %).
  Der Satz „Liefe dieser Abend siebenmal, gewönne Stuttgart einmal" passt mit 16 % weiterhin
  (1/6 statt 1/7 — Formulierung auf „sechsmal" anpassen).
- **Zusätzlich als Änderung ausweisen**: ein kurzer Hinweis, dass der Heimvorteil im September
  2026 nachkalibriert wurde — für Leser, die ältere Prognosen kennen.

### Doku

- `docs/RUST_API_REFERENCE.md` — Default-Angabe 65 → 40
- ADR-Ergänzung *oder* kurzer Zusatz in ADR 0002, dass die Konstante ausschließlich in Rust
  liegt und R sie nicht mehr sendet (macht die bestehende Entscheidung erst wahr)
- `CONTEXT.md` — falls der Heimvorteil dort als Begriff geführt werden soll

## Vorher-Nachher-Beleg (vor dem Merge)

Beide Varianten einmal gegen die aktuellen Spieldaten rechnen und dokumentieren, wie stark
sich die veröffentlichten Zahlen verschieben — je Liga Meister-, Aufstiegs- und
Abstiegswahrscheinlichkeiten. Erwartete Größenordnung nach der Modellrechnung: rund
3 Prozentpunkte bei Einzelspielprognosen (Bayern-Sieg 64 % → 62 %), ligaweit 0,14 Tore/Spiel,
die von der Heim- auf die Auswärtsseite wandern.

Das ist die Grundlage, um die Änderung gegenüber Lesern zu vertreten — und der Test, ob sich
etwas Unerwartetes verschiebt.

## Notiz für später (nicht Teil dieses Plans)

`calculate_elo_update()` (`RCode/elo_aggregation.R:239-267`) rechnet den Saisonwechsel mit
HA=100 und ist ein Teilduplikat der Rust-ELO-Logik — ADR 0002 nennt es selbst als Drift-Risiko.
Zwei Dinge stehen dort offen:

1. **Der Wert**: 100 ist deutlich zu hoch; an der ELO-Erwartungsformel geeicht wären es ~25.
2. **Der Wirkungspfad**: Sinnvoller wäre, die Funktion überhaupt auf die Tor-Logik umzustellen
   (bzw. den Rust-Walk zu nutzen, wie es der Kalibrierungsteil des Ligen-Ausbau-Plans vorsieht),
   statt eine zweite Formel mit eigener Skala zu pflegen. Dann entfiele die Frage nach dem
   „richtigen" zweiten Wert von selbst.

Zeitlich unkritisch: wirkt erst beim nächsten Saisonwechsel im Juli.

## Verifikation

- `cargo test` in `league-simulator-rust/`. Drei verschiedene Fälle, vorab geprüft:
  - `elo/tests.rs` und `simulation/tests.rs` übergeben `home_advantage` explizit
    (u. a. `65.0` als Literal) → unberührt, bleiben grün.
  - `monte_carlo/tests.rs` baut die Parameter mit `..Default::default()` → hängt **direkt**
    am geänderten Default. Erwartungswerte prüfen und ggf. nachziehen.
  - `league_details/tests.rs:15` hält eine **eigene** Konstante `HOME_ADVANTAGE = 65.0` mit
    hartkodierten Erwartungswerten (z. B. `p_away_win = 0.316490886592`). Der Test bleibt
    dadurch grün, dokumentiert aber einen Wert, den die Produktion nicht mehr verwendet —
    also auf 40 mitziehen und die Erwartungswerte neu berechnen, sonst verrottet der Test
    stillschweigend.
  - `api/tests.rs` prüft Request-Validierung, nicht den Zahlenwert → unberührt.
- `source("tests/testthat.R")` — `test-league-details-client.R:50` pinnt heute
  `expect_equal(payload$home_advantage, 65)`. Der Test **bricht bewusst** und wird zur
  Gegenprobe umgebaut: Das Feld darf im Payload **nicht mehr vorkommen**. Das ist die Stelle,
  an der die Entscheidung „Rust ist alleinige Quelle" testbar festgehalten wird.
- `Rscript scripts/preview_site.R` — Methodik-Seite und Beispielwerte im Browser prüfen.
- Vorher-Nachher-Vergleich wie oben, als Beleg im PR.
