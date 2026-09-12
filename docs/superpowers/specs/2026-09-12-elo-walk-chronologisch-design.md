# ELO-Walk chronologisch, und nur noch einer

> Design aus der Brainstorming-Session vom 12.09.2026. Deckt Issue #146 ab
> und löst den Heimvorteil-Widerspruch, der seit September 2026 als Notiz in
> `docs/plans/2026-09-05-heimvorteil-kalibrierung.md` liegt.

## Context

Zwei Befunde, die das Bild gegenüber dem Issue-Text verschieben.

**Der R-Walk sortiert bereits chronologisch.** `elo_aggregation.R:96` macht
`order(matches$fixture_date)`. Nur der Rust-Walk verarbeitet die Spiele in
Listenreihenfolge — bei Nachholspielen weicht das vom Kalender ab. Ein
verlegtes Spiel des 5. Spieltags, ausgetragen zwischen dem 13. und 14.,
fließt so ein, als wäre es am 5. Spieltag gespielt worden; die Runden 6–13
werden mit leicht falschen ELO-Ständen fortgeschrieben.

**`calculate_final_elos()` ist kein toter Code.** Er läuft im Saisonwechsel
(`season_processor.R:140`) und erzeugt die Start-ELOs der neuen Saison — mit
`home_advantage <- 100`, während jede Prognose mit 40 rechnet.

Der Heimvorteil-Plan vom 05.09.2026 hält dazu fest, dass die beiden Werte
**nicht vergleichbar** sind: Sie wirken über verschiedene Formeln.

| Wirkungspfad | Formel | heute | kalibriert |
|---|---|---|---|
| Tormodell (Rust) | `λ = ±(Δ+HA)·slope + intercept` | 40 | 40 |
| ELO-Erwartung (R) | `1/(1+10^(−HA/400))` | **100** | 25,8 |

Daraus folgt die tragende Einsicht dieses Entwurfs: **„Alles rechnet mit 40"
ist gar nicht herstellbar, solange der zweite Pfad existiert.** Eine 25,8
einzusetzen hieße, die zweite Physik zu konservieren — mit einem Wert, den
niemand mit dem der Prognose in Beziehung setzen kann.

Die einzige Variante, die *einen* Heimvorteil herstellt, ist die Löschung.

---

## Teil 1 — Chronologische Sortierung, R-seitig

**Entscheidung: R sortiert, Rust bleibt unverändert.** Kein neues
Payload-Feld, keine Schnittstellenänderung, kein Rust-Release. Die
Anstoßzeit liegt in R ohnehin vor.

Sortiert wird nach Anstoßzeit, bei Gleichstand nach der bestehenden
`OriginalOrder` (der API-Reihenfolge). Bei identischer Anstoßzeit spielen
verschiedene Teams — für das ELO-Ergebnis ist die Reihenfolge dort
gleichgültig, sie muss nur **deterministisch** sein.

**Betroffen sind beide Pfade:**

- `transform_data()` (`transform_data.R`) baut den Spielplan für `/simulate`.
  `fixtures_flat` trägt die Anstoßzeit bereits (aus `unnest(cols = "fixture")`),
  sie wird nur nicht mitgenommen.
- `extract_fixture_details()` (`league_details.R`) baut den Payload für
  `/league-details`. Dort wird zwar nach `kickoff` sortiert — aber nur für
  die **Anzeige** (Zeilen 193/226/234), nicht für den Payload.

### Die Stelle, an der es still schiefgehen kann

`transform_data()` hängt ein Attribut `elo_neutral` an, das **zeilengleich**
mit dem Data-Frame reist (`transform_data.R:298`, Issue #157: gewertete
Spiele zählen für die Tabelle, sollen die Stärkeschätzung aber nicht
bewegen). `rust_integration.R:237` liest es und reicht es an die Engine.

Wer die Zeilen umsortiert, ohne den Vektor mitzusortieren, lässt den
ELO-Walk die **falschen** Spiele überspringen — ohne Fehlermeldung.

**Lösung (Entscheidung Christoph):** Ein Helfer fügt `elo_neutral` als
Spalte an, sortiert, und trennt danach wieder in Data-Frame und Attribut.
Innerhalb des Helfers gibt es nur *ein* Objekt; das Vergessen ist
konstruktiv ausgeschlossen, nicht bloß durch einen Test abgesichert.

Nach außen bleibt die Spaltenstruktur Vertrag (`numberTeams = ncol - 4`) —
der Helfer arbeitet rein intern.

---

## Teil 2 — Ein Walk statt zweier

**Entfällt:** `calculate_final_elos()`, `update_elos_for_match()`,
`calculate_elo_update()` (`elo_aggregation.R`). Mit ihnen verschwindet der
100er-Heimvorteil ersatzlos.

**Bleibt:**

- `get_initial_elo_for_new_team()` — anderer Aufrufer
  (`interactive_prompts.R:40`).
- `get_league_matches()` und `fetch_league_results()` — beide werden
  weiterhin gebraucht: `fetch_league_results()` von `fixture_cache.R:52`,
  `get_league_matches()` von `calculate_liga3_relegation_baseline()`.

**Zwei Aufrufer, nicht einer.** Neben `season_processor.R:140` ruft auch
`calculate_liga3_relegation_baseline()` (`elo_aggregation.R:325`) die
Funktion — sie mittelt die End-ELOs der Drittliga-Absteiger zur
Basis-ELO für Aufsteiger. Beide Aufrufer müssen auf den Rust-Walk
umgestellt werden; der zweite ist leicht zu übersehen, weil er in derselben
Datei steht wie die zu löschende Funktion.

**Ersatz:** Der Saisonwechsel holt die End-ELOs über `/league-details`. Die
Machbarkeit ist geprüft:

- `parse_league_details_response()` liefert `current_elos` — genau das, was
  `calculate_final_elos()` produziert.
- `extract_fixture_details()` baut seine Eingabe aus denselben rohen
  Fixtures, die `fetch_league_results()` heute holt.
- Der Endpunkt ist deterministisch und nicht an den laufenden Betrieb
  gebunden (ADR 0002).

Damit erfüllt der Saisonwechsel endlich, was ADR 0002 verlangt: keine
Modelllogik in R.

---

## Testplan

**Teil 1:**

- Ein Nachholspiel, das in der Listenreihenfolge vor seinem Kalenderplatz
  steht, wird chronologisch einsortiert — geprüft an der Zeilenfolge des
  erzeugten Spielplans.
- Bei identischer Anstoßzeit entscheidet `OriginalOrder`; zwei Läufe über
  dieselbe Eingabe liefern dieselbe Reihenfolge.
- **Die Kopplung:** Ein AWD-Spiel, das durch die Sortierung an eine andere
  Position wandert, muss im `elo_neutral`-Vektor mitgewandert sein. Das ist
  der Test, der den stillen Fehler fängt.
- Die Spaltenstruktur nach außen ist unverändert (`ncol - 4`).
- Ohne Nachholspiele ändert sich die Reihenfolge nicht — die bestehenden
  Prognosen dürfen sich nicht ohne Grund bewegen.

**Teil 2:**

- Der Saisonwechsel liefert dieselben End-ELOs wie zuvor, sofern
  chronologisch sortiert wird und derselbe Heimvorteil gilt. Ein
  Abgleich gegen `/league-details` an einer echten Saison.
- `calculate_elo_update()` existiert nicht mehr — ein Test, der die
  Abwesenheit festhält, verhindert die stille Rückkehr.
- Der Snapshot-Test des Saisonwechsels muss neu aufgezeichnet werden: Die
  Start-ELOs ändern sich, weil der Heimvorteil von 100 auf die
  Tormodell-Physik wechselt.

---

## Reihenfolge und Risiko

**Teil 1 zuerst, Teil 2 danach** — in getrennten PRs.

Teil 1 ändert die laufende Prognose (kleiner Effekt: K = 20, wenige
Nachholspiele), Teil 2 ändert nur den Juli-Lauf. Zusammen in einem PR wäre
eine Regression nicht mehr eindeutig zuzuordnen; das ist der Grund, warum
#146 zweimal zurückgestellt wurde.

**Abnahme von Teil 1:** ein echter Scheduler-Zyklus, plus Abgleich der
Prognosen vorher/nachher. Erwartet wird eine kleine, erklärbare Änderung —
keine Änderung wäre ein Hinweis darauf, dass die Sortierung nicht greift.
