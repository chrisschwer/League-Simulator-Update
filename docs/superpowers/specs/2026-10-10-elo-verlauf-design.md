# ELO-Verlauf je Liga (Issue #184) — Design

Stand: 2026-10-10, im Gespräch mit Christoph abgestimmt.

## Ziel

Für jede Liga eine eigene Seite, die den ELO-Verlauf aller Vereine der
laufenden Saison zeigt — die Grafik aus dem 30-Punkte-Artikel von 2016,
interaktiv: Jede Linie ein Verein, jeder Knick ein Spiel; Hover hebt einen
Verein hervor, ein Tooltip zeigt das konkrete Spiel.

Gestalterische Vorlage ist der Entwurf vom 8. September 2026 (eigenständige
HTML-Datei, 2. Bundesliga 2024/25): Umschalter „Nach Spieltag / Nach Datum“,
entzerrte Endbeschriftungen mit Führungsstrichen, Winterpause als Fläche,
Tabelle Beginn/Ende/Veränderung darunter, linkslastige Spielauswahl unter dem
Zeiger.

Nicht Ziel: frühere Saisons, Vergleich über Ligen hinweg, Änderungen am
Rust-Server oder an der Datenhaltung.

## Gestaltungsanspruch

Die Seite ist eine Mischung aus **Edward Tufte** und dem Erscheinungsbild
von *30 Punkte*. Maßstab ist der Entwurf vom 8. September, der als Referenz
unter `docs/designs/elo-verlauf-2bl-2024-25.html` im Repo liegt. Die
fertige Seite muss **mindestens so gut aussehen wie dieser Entwurf**. Wo sie
abweicht, dann nur, weil echte Saisondaten es verlangen (variable Ligagröße,
laufende Saison).

**Tufte, konkret:**

- **Daten-Tinte vor allem anderen.** Kein Rahmen um das Diagramm, keine
  Achsenlinien, kein Hintergrundraster außer wenigen waagerechten Hilfslinien
  im 50er-Schritt (`--rule-soft`, 0,5 px). Keine Schatten, keine Verläufe,
  keine Flächenfüllungen unter Linien.
- **Kontext leise, Fokus laut.** Alle Linien in Ruhe in `--rule` (1 px). Bei
  Auswahl wird genau eine Linie `--tinte` (2 px), alle anderen treten weiter
  zurück (`--rule-soft`, gedämpft). Keine bunte Farbe je Verein: 18–20
  unterscheidbare Farben gibt es nicht, und eine Farblegende wäre Chartjunk.
- **Direkt beschriften statt Legende.** Kürzel und ELO stehen an den
  Linienenden, entzerrt, mit Führungsstrich, sobald ein Etikett von seiner
  Linie weggerückt ist.
- **Ziffern:** in Diagramm, Tooltip und Tabelle tabellarisch in
  JetBrains Mono, im Fließtext Mediävalziffern (Source Serif).
- **Ruhige Hilfsflächen:** Die Winterpause ist eine `--surface-2`-Fläche mit
  kleiner Versalienzeile, kein Muster und keine Linie.
- **Erklären in Prosa, nicht in Bedienelementen.** Ein Lead-Satz sagt, wie
  das Diagramm zu lesen ist; die einzige Bedienung ist der Umschalter aus zwei
  Segmenten.

**Farben und Schrift** ausschließlich über die Tokens aus `site.css`
(`--paper`, `--surface-2`, `--ink`/`-2`/`-3`, `--rule`/`-soft`, `--tinte`
für Fokus und positives Δ, `--akzent` für negatives Δ, `--ocker` für den
Hinweisbalken; `--serif`/`--sans`/`--mono`). Keine neuen Farbwerte. Die
Hartwerte aus dem Entwurf (`#EDE9DE`, `#BDB6A8`) werden zu benannten Tokens
in `site.css`.

**Typografie und Abstände** wie im Entwurf: `eyebrow` in Versalien,
`h2` in Serif 28/24 px, Lead höchstens 64 Zeichen breit, Diagrammbeschriftung
9,5–10,5 px.

**Abnahme der Gestaltung** (Teil der Definition of Done, nicht optional):

1. Die Verlaufsseite wird mit der Fixture gerendert und **neben dem Entwurf**
   im Browser verglichen, jeweils in beiden Achsenmodi. Geprüft wird bei
   1280 px und 390 px Breite, für eine frühe Saison (3 Spiele), die
   Saisonmitte (Winterpause sichtbar) und eine Liga mit 20 Vereinen.
2. Screenshots beider Seiten gehen in den PR.
3. Christoph nimmt die Gestaltung ab. Ohne seine Abnahme wird nicht gemergt.

## Entscheidungen

| Frage | Entscheidung |
|---|---|
| Eigene Seite oder Abschnitt auf der Ligaseite? | Eigene Seite je Liga. |
| Wie findet man sie? | Link im Tabellenabschnitt der Ligaseite; Rücklink auf der Verlaufsseite. Hauptnavigation wächst nicht. |
| Navigation auf der Verlaufsseite | Ligalinks führen zur **Verlaufsseite** der anderen Liga (Rückfall: deren Ligaseite, falls sie keine hat). Aufstiegsseite und Methodik normal. |
| Welche Ligen? | Alle zehn. |
| x-Achse | Zahl der gespielten Spiele des Vereins (bzw. Datum). Reicht bis zum aktuellen Stand, solange die Saison läuft **plus ein Spiel bzw. 7 Kalendertage**; abgeschlossen ohne Überhang. |
| Umsetzung | Ansatz 1: Daten aus R als eingebettetes JSON, Zeichnung im Browser durch ein gemeinsames Skript. |

## Datenquelle

Es wird nichts zusätzlich gespeichert. `POST /league-details` geht in jedem
Zyklus die ganze Saison durch und liefert je Spiel `played`, `elo_home_pre`,
`elo_away_pre`, `elo_delta_home`, `p_home_win`, `p_draw`, `p_away_win`.
`build_league_page_data()` legt das als `league_entry$matches` neben die
Spalten aus `extract_fixture_details()` (`fixture_id`, `round`, `kickoff`,
`status`, Team-IDs und -Namen, Tore). Die Zeilenreihenfolge ist die
Walk-Reihenfolge (Anstoßzeit, siehe Spec 2026-09-12). Der Verlauf ist damit
in jedem Zyklus vollständig aus dem aktuellen Spielplan rekonstruierbar.

Am grünen Tisch gewertete Spiele sind in der Antwort `played = FALSE`
(Issue #157) und erzeugen deshalb keinen Punkt im Verlauf.

## Abschnitt 1: Seiten und Navigation

- **Dateiname:** `league_views()` bekommt je Sicht ein Feld `verlauf_slug`,
  z. B. `2-bundesliga-verlauf`; für die Bundesliga (`slug = "index"`)
  `bundesliga-verlauf`. Keine abgeleitete Namensregel an mehreren Stellen.
- **Wann gerendert:** genau dann, wenn für die Liga `league_data` vorliegt und
  `elo_verlauf_daten()` ohne Fehler durchläuft. Der Generator bestimmt diese
  Menge **vor** dem Rendern aller Seiten (`verlauf_daten` je Liga), weil sie
  zwei Dinge steuert:
  1. ob die Ligaseite den Link „ELO-Verlauf der Saison ansehen →“ trägt,
  2. wohin die Ligalinks der Navigation auf Verlaufsseiten zeigen.
- **Navigation:** `.nav_html(current_slug)` bekommt einen zweiten Parameter
  `verlauf_ziele` (benannter Vektor nav-slug → verlauf_slug, oder `NULL`).
  - `NULL` (Liga-, Aufstiegs-, Methodikseite): unverändert.
  - Auf einer Verlaufsseite: Ligalinks zeigen auf `verlauf_ziele[slug]`, wo
    vorhanden, sonst auf die Ligaseite. Aufstiegsseite und Methodik
    unverändert. Markiert (`nav-current`, `aria-current="page"`) ist die
    Liga, deren Verlauf man sieht.
- **Rücklink** oben auf der Verlaufsseite: „← Prognose <nav_label>“ zur
  Ligaseite.
- **`scripts/preview_site.R`** ohne `league_data` rendert wie heute (keine
  Verlaufsseiten, keine Links). Neues optionales drittes Argument: Pfad zu
  einem RDS mit `league_data` (benannte Liste wie im Betrieb).
- **Seitenzahl** im Betrieb: 12 → 22. Nachzuziehen: `CLAUDE.md`,
  `docs/architecture/overview.md`, `docs/deployment/static-site.md`.

**Seitenaufbau** (wie die anderen Seiten: Masthead, Stale-Banner, Fuß):

1. Rücklink.
2. Abschnitt „ELO-Verlauf“ (`eyebrow` ELO-Verlauf, `h2` „ELO-Verlauf
   <Liga> <Saison>“, Lead-Text), Umschalter, Diagrammfläche mit
   `<noscript>`-Hinweis, Hinweisabsatz mit Link auf Methodik. Der Text nennt
   **keine** Modellkonstanten als Zahl — die leben nur im Rust-Server
   (ADR 0002). Die Saisonangabe kommt aus der frühesten Anstoßzeit im
   Spielplan (Jahr J → „J/J+1“, zweistellig), nicht aus einer
   Umgebungsvariable — so stimmt sie auch in der Vorschau mit alter Fixture.
3. Abschnitt „Tabelle“: Verein, ELO Saisonbeginn, ELO heute, Veränderung;
   sortiert nach ELO heute. Von R gerendert (funktioniert ohne JS); Hover/Klick
   auf eine Zeile hebt die Linie hervor.

## Abschnitt 2: Daten (R)

Neue Datei `RCode/elo_verlauf.R`, rein (keine I/O):

```r
elo_verlauf_daten(league_entry) -> list(
  saison,             # "2026/27" aus der fruehesten Anstosszeit (Berliner Zeit)
  saison_laeuft,      # TRUE, solange ein Spiel weder ein Ergebnis (STATUS_ERGEBNIS)
                      # hat noch abgesagt (CANC) ist -- sonst hielte ein einziges
                      # abgesagtes Spiel die Saison fuer immer offen
  achse_spiele_max,   # max(n) + (saison_laeuft ? 1 : 0)
  achse_datum_ende,   # "YYYY-MM-DD": letzter Spieltag (+7 Tage, wenn saison_laeuft)
  teams = list(       # in Reihenfolge ELO heute absteigend
    list(id, kuerzel, name, start, aktuell,
         punkte = list(
           list(n = 0, nach = start),            # Startpunkt
           list(n, datum, runde, nachhol,        # je ELO-wirksamem Spiel
                gegner, gegner_name, heim,
                tore_heim, tore_gast,
                vor, nach, delta, p_sieg, p_remis),
           ...)))
)
```

- Quelle ausschließlich `league_entry$matches`, `$teams` (InitialELO,
  ShortText) und `$tabelle` (Name, aktuelles ELO).
- Je Zeile mit `played == TRUE` ein Punkt für Heim und Gast:
  Heim `vor = elo_home_pre`, `delta = elo_delta_home`, `p_sieg = p_home_win`;
  Gast `vor = elo_away_pre`, `delta = -elo_delta_home`, `p_sieg = p_away_win`;
  `nach = vor + delta`; `p_remis = p_draw`.
- `n` zählt die Punkte des Vereins ab 1 in Zeilenreihenfolge.
- `datum` ist der Berliner Kalendertag von `kickoff`.
- `nachhol` aus `nachholspiel_markierung(details)`.
- **Invariante:** Für jeden Verein ist das letzte `nach` (bzw. `start` ohne
  Spiel) gleich `tabelle$elo` bis auf 1e-6. Sonst `stop()` mit Verein und
  Differenz. Der Generator fängt das ab (`tryCatch` + `warning`): Nur diese
  Verlaufsseite und der Link dorthin entfallen, die übrige Site entsteht.
- **Keine gespielten Spiele:** `teams` mit nur dem Startpunkt,
  `achse_spiele_max = 1`, `achse_datum_ende = NA`; die Seite zeigt statt des
  Diagramms „Die Saison hat noch nicht begonnen.“

**Einbettung:** `jsonlite::toJSON(auto_unbox = TRUE, digits = 4)`, danach
`</` → `<\/` ersetzt, in
`<script type="application/json" id="verlauf-daten">`. `digits = 4` statt
voller Präzision: Die ELO-Invariante wird vor der Serialisierung in R geprüft
(Abweichung höchstens 1e-6), und die Anzeige rundet ohnehin auf eine
Nachkommastelle.

## Abschnitt 3: Darstellung (`RCode/site_assets/verlauf.js`)

- Einmal als Asset, von `.copy_assets()` nach `assets/verlauf.js` kopiert,
  von jeder Verlaufsseite per `<script src>` eingebunden. CSS des Entwurfs
  wandert nach `site.css` und nutzt die vorhandenen Farb-Tokens.
- Grundlage ist das Skript des Entwurfs; Änderungen:
  - Daten aus `#verlauf-daten` statt Konstante; Tabelle wird nicht mehr per
    JS gebaut, sondern vorhandene `<tr data-i>` werden verdrahtet.
  - **Spielmodus:** `x = n / achse_spiele_max`, Achse „Spiele“ mit Marken
    alle 5 Spiele und „Start“ bei 0.
  - **Datumsmodus:** Achse vom Tag 7 Tage vor dem ersten Spiel bis
    `achse_datum_ende`, Monatsbeschriftung; Startpunkt (`n = 0`) liegt am
    linken Rand. Winterpause nur hier und nur bei einer Lücke > 18 Tagen.
  - Endbeschriftung (Kürzel + gerundetes ELO heute) an den Linienenden,
    entzerrt, Führungsstrich bei Versatz — wie im Entwurf.
  - **Tooltip:** „Sa. 4. Okt. 2026 · 7. Spieltag“ (bei Nachholspiel
    „ · Nachholspiel“), Paarung Heim–Gast mit Ergebnis, „Das Modell gab
    <Kürzel> vorher a % Sieg, b % Remis.“, „ELO vor → nach Δ“.
  - **Touch:** Antippen einer Linie wählt den Verein und zeigt den Tooltip
    für das Spiel links vom Finger; erneutes Antippen hebt die Auswahl auf.
  - `aria-label` des SVG aus Liga und Saison; die Tabelle ist die
    zugängliche Alternative.
  - Kleine Schnittstelle `window.eloVerlauf = { modus(m), waehle(i),
    zeigeSpiel(i, n), loesche() }` — dieselben Funktionen, die die
    Ereignisse aufrufen. jsdom kennt kein Layout; die Tests steuern das
    Diagramm darüber statt über Zeigerkoordinaten.

## Tests

- `tests/testthat/test-elo_verlauf.R`:
  Heim-/Gastperspektive inkl. Vorzeichen von Δ und `p_sieg`; gewertetes Spiel
  ohne Punkt; Nachholspiel chronologisch und mit `nachhol = TRUE`; Überhang
  bei laufender, keiner bei abgeschlossener Saison (Spiele und Datum);
  Invariantenverletzung bricht ab; Fall ohne gespielte Spiele; Sortierung.
- `tests/testthat/test-generate_static_site-verlauf.R`:
  Seite nur mit `league_data`; Slugs inkl. Bundesliga; Link auf der Ligaseite
  und Rücklink; Navigation auf der Verlaufsseite zeigt auf `*-verlauf.html`,
  mit Rückfall auf die Ligaseite für eine Liga ohne Verlauf; Ligaseiten-Nav
  unverändert; JSON maskiert `</script>`; scheiternde Aufbereitung lässt nur
  diese Seite und ihren Link weg; `assets/verlauf.js` wird kopiert.
- `tests/testthat/test-verlauf-js.R` (jsdom, `helper-js.R`):
  Zahl der Linien = Zahl der Vereine; Moduswechsel zeichnet neu und setzt
  `aria-pressed`; Endbeschriftungen überlappen nicht (Abstand ≥ 12,5);
  Tooltip für einen Punkt enthält Paarung, Ergebnis, Δ; Tabellenzeile hebt
  Linie hervor; „Saison hat noch nicht begonnen“ ohne Spiele.
- Sichtprüfung: ein kleines Skript `scripts/verlauf_fixture.R` erzeugt
  reproduzierbar (fester Seed) synthetische `league_data` für drei Stände:
  18 Vereine nach 3 Spielen, 18 Vereine nach 20 Spielen über die
  Winterpause, 20 Vereine mit Nachholspiel und einem gewerteten Spiel. Die
  ELO-Werte kommen dabei aus dem echten `/league-details`, wenn der
  Rust-Server lokal läuft. Gerendert wird mit `scripts/preview_site.R`, die
  Abnahme läuft wie unter „Gestaltungsanspruch“ beschrieben.

## Betroffene Dateien

- neu: `RCode/elo_verlauf.R`, `RCode/site_assets/verlauf.js`, drei Testdateien,
  eine Fixture
- geändert: `RCode/league_views.R` (`verlauf_slug`),
  `RCode/generate_static_site.R` (Verlaufsdaten vorab, Render-Funktion,
  Nav-Parameter, Link auf Ligaseite, Asset-Kopie),
  `RCode/site_assets/site.css`, `scripts/preview_site.R`, Doku (s. o.)
- neu (Referenz/Sichtprüfung): `docs/designs/elo-verlauf-2bl-2024-25.html`,
  `scripts/verlauf_fixture.R`
