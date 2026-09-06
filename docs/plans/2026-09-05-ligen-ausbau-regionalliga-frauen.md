# Ligen-Ausbau: Regionalligen + Frauen-Bundesligen

## Context

Das API-Budget (Pro-Plan, 7.500 Requests/Tag, real ~150–450) lässt Luft für weitere Ligen.
Die Prognose soll daher von drei auf zehn Ligen wachsen: fünf Regionalligen sowie
Frauen-Bundesliga und 2. Frauen-Bundesliga.

Der Kern des Vorhabens ist nicht die Simulation — die Rust-Engine ist bereits vollständig
ligaunabhängig (Teamzahl aus `elo_values.len()`, keine Auf-/Abstiegssemantik) — sondern:

1. **Entflechtung**: Die Liga-IDs 78/79/80 stehen als Literale in ~12 R-Dateien; Update-Loop
   und Seitengenerator sind auf genau drei Ligen verdrahtet.
2. **Initiale ELO-Bewertung**: Für die neuen Ligen gibt es keine Historie. Sie muss offline
   erzeugt und auf die bestehende ELO-Skala geeicht werden.
3. **Abstiegskopplung**: Wie viele Teams aus einer Regionalliga absteigen, hängt davon ab,
   wer aus der 3. Liga in diese Staffel fällt.

## Empirische Befunde (gemessen, Saisons 2024+2025, beendete Hauptrundenspiele)

| Liga | Spiele | Tore/Spiel | Heim | Ausw. | Heim% | Remis% | Ausw.% | Remis% lt. Poisson | impl. Heimvorteil |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Bundesliga | 612 | 3,18 | 1,71 | 1,48 | 41,2 | **25,0** | 33,8 | 23,3 | 26 ELO |
| Frauen-BL | 314 | 3,31 | 1,77 | 1,54 | 45,5 | **15,9** | 38,5 | 22,8 | 24 ELO |
| 2. Frauen-BL | 365 | 3,30 | 1,77 | 1,52 | 42,7 | **17,5** | 39,7 | 22,9 | 10 ELO |
| RL Bayern | 611 | 3,02 | 1,59 | 1,42 | 40,6 | 25,4 | 34,0 | 24,1 | 23 ELO |
| RL Nord | 612 | 3,41 | 1,80 | 1,61 | 42,2 | 22,4 | 35,5 | 22,5 | 23 ELO |

Drei Schlussfolgerungen, die den Plan prägen:

- **Das Torniveau der Frauen liegt nur +4 % über der Bundesliga** — nicht der erwartete große
  Unterschied. Die Spanne *zwischen den Regionalliga-Staffeln* (3,02 vs. 3,41 = 13 %) ist
  größer als der Unterschied Frauen/Herren. Ein abweichendes `tore_intercept` ist daher je
  **Staffel** zu begründen, nicht je Geschlecht.
- **Der Remis-Anteil ist der eigentliche Befund.** Das Poisson-Modell impliziert für beide
  ~23 %; es trifft die Herren (25,0 %) gut und überschätzt die Frauen (15,9 %) deutlich.
  Das bestätigt die Ausgangsvermutung: Ursache sind die **größeren Qualitätsunterschiede
  innerhalb der Liga**, nicht das Torniveau. Der Hebel ist die **ELO-Spreizung**, kein
  Torparameter.
- **Der implizite Heimvorteil liegt in allen Ligen bei ~23–26 ELO**, auch in der Bundesliga —
  weit unter den konfigurierten 65. Befund über den *bestehenden* Parameter; wird dokumentiert,
  hier aber nicht geändert.

## Verifizierte Rahmenbedingungen (API)

**Liga-IDs**: 82 Frauen-BL, 1034 2. Frauen-BL, 83 RL Bayern, 84 RL Nord, 85 RL Nordost,
86 RL SüdWest, 87 RL West; zusätzlich 1002 „Regionalliga – Promotion Play-offs".

> **Es sind fünf Regionalligen, nicht vier.** Der Plan geht von fünf Staffeln aus (insgesamt
> zehn Ligen).

**Historientiefe deutlich geringer als die angenommenen zehn Jahre:**

| Liga | Erste Saison | Saisons |
|---|---|---|
| Regionalligen (83–87) | 2019 | 7–8 |
| Frauen-BL (82) | 2016 | 11 |
| 2. Frauen-BL (1034) | **2023** | **4** |

Die 10-Jahres-Durchsimulation ist für die neuen Ligen nicht durchführbar; der Horizont wird
je Liga konfigurierbar und schöpft das Vorhandene aus (2020/21, 2021/22 Corona-markiert).

**Blocker — abweichende Rundenbezeichnungen**: Die Regionalligen liefern Runden als
`"Bayern - 34"`, `"Nord - 20"` statt `"Regular Season - N"` — und **inkonsistent über Saisons**
(Liga 84 mal `"Nord - N"`, mal `"North - N"`). `transform_data()` und
`extract_fixture_details()` filtern hart auf `startsWith("Regular Season")` und würden **jedes
Regionalliga-Spiel verwerfen** und eine leere Liga simulieren.

**Teamzahlen schwanken je Saison**: Frauen-BL 12 → 14, RL Bayern 18 → 20 → 19. Teamzahlen
dürfen nirgends Konstante sein; zu prüfen ist eine Spanne, keine Gleichheit.

**Zweiter Blocker — Kurznamen-Kollisionen**: `ShortText` ist dreistellig, Zweitvertretungen
werden auf zwei Zeichen + „2" gekürzt (`api_service.R:258`). Diese Kurznamen werden in
`transform_data()` zu **Spaltennamen** des Simulations-Data-Frames. Von 56 auf ~170 Teams,
davon allein in den Regionalligen rund 20 Zweitvertretungen (Bayern II, Nürnberg II,
Augsburg II, HSV II, Werder II, Dortmund II, Köln II …), sind Kollisionen **sicher**, nicht
bloß möglich — und sie werfen keinen Fehler, sondern erzeugen doppelte Spaltennamen und
damit stillschweigend vertauschte Teams. Nötig: eine globale Eindeutigkeitsprüfung beim
Laden der TeamList (heute prüft `generate_unique_short_name()` nur innerhalb einer Liga) und
eine Verbreiterung auf vier Zeichen für die neuen Ligen.

**API-Budget** (Live-Poll deckt per `retrieveLiveFixtures(league_ids=…)` weiterhin *alle*
Ligen mit einem Request ab):

| | 25 % aktive Loops | 100 % aktiv (Worst Case) |
|---|---:|---:|
| heute (3 Ligen) | 422/Tag | 964/Tag |
| künftig (10 Ligen) | 844/Tag | 2.651/Tag |

Unkritisch gegen 7.500/Tag. Einzige Stellschraube: `checkAPILimits(avg_calls_per_loop = 2)`
muss mit der Ligazahl wachsen.

## Getroffene Entscheidungen

1. Alle Ligen in einem Zug.
2. Empirie als Entscheidungsgrundlage: abweichende Parameter nur bei klarem Unterschied.
3. RL-Abstieg: manuelle, statische Zuordnung **jedes** Vereins zu „seiner" Regionalliga.
4. Kopplungsformel (unverändert übernommen): je Staffel eine Mindestzahl `c` an
   Abstiegsplätzen; die letzten `c` Plätze steigen mit Wahrscheinlichkeit 1 ab; für den
   `c+j`-letzten Platz gilt
   **P(Abstieg) = P(Platz `c+j`) · P(≥ `j` Absteiger aus der 3. Liga in diese Staffel)**.
   P(≥ j) wird **exakt ausgezählt**, nicht approximiert: siehe Abschnitt 7.
5. Aufstiegsrelegation als eigener Simulationsschritt. Verifiziert: Die RL-Relegation ist ein
   Hin-/Rückspiel zwischen zwei Staffelmeistern (Liga 1002, historische Daten vorhanden).
6. ELO-Historie: einmaliges Offline-Skript.
7. Heimvorteil-Widerspruch 100 vs. 65: **nicht** anfassen, nur dokumentieren.

## Architektur

### 1. Zentrale Liga-Registry (`RCode/league_registry.R`, neu)

Eine Datenquelle ersetzt die verstreuten Literale. R-Datei (nicht YAML) — bleibt bei den
bestehenden Konventionen, ist ohne neue Dependency testbar und kann Ausdrücke tragen:

```r
league_registry <- function() list(
  bundesliga = list(
    api_id = "78", tier = 1L, family = "herren",
    slug = "index", nav_label = "Bundesliga", nav_group = "Herren",
    round_is_regular = NULL,                # NULL = Standard-Negativliste, s. 2.
    home_advantage = 65, tore_intercept = 1.3218390804597700,  # unverändert
    teams_range = c(18L, 18L),              # Spanne, keine Gleichheit
    first_season = 2010L,
    relegates_to = "zweite_bundesliga", promotes_to = NULL
  ),
  ...
  rl_nord = list(
    api_id = "84", tier = 4L, family = "regionalliga", staffel = "Nord",
    slug = "rl-nord", nav_label = "Nord", nav_group = "Regionalliga",
    round_is_regular = NULL,                # Labels "Nord"/"North" -> Negativliste
    teams_range = c(16L, 22L),              # schwankt je Saison
    # KEIN eigener tore_intercept: Die Regionalligen tauschen Teams mit der
    # 3. Liga, gehoeren also zur Wechselgemeinschaft Herren und muessen
    # deren Tormodell benutzen (siehe Nachtrag am Ende).
    first_season = 2019L,
    seasons_excluded = c(2020L),            # nicht abgedeckt / abgebrochen
    relegation_min_slots = 2L,              # das `c` der Kopplungsformel
    ...
  )
)
```

Verbraucher (Literale entfallen): `league_views()`, `update_all_leagues_loop()`,
`retrieveLiveFixtures()`, `input_validation.R:325`, `elo_aggregation.R:66/379`,
`league_processor.R:196/252`, `api_service.R:152/221`, `checkAPILimits()`,
`scripts/season_transition/cleanup.R`.

`league_views()` wird aus der Registry abgeleitet und behält seine heutige Form
(`top`/`bottom` mit `filter_cols`/`labels`/`groups`), damit die bestehende
Panel-Renderlogik unverändert bleibt.

### 2. Rundenfilter ligaabhängig machen

`transform_data()` und `extract_fixture_details()` erhalten einen ligaabhängigen
Rundenfilter aus der Registry. Statt einer Positivliste („beginnt mit *Regular Season*")
eine **Negativliste**: Alles zählt als Hauptrunde, was keine bekannte K.-o.-/Playoff-Runde
ist (`Final`, `Relegation`, `Promotion`, `Play-offs`, …) und eine Spieltagsnummer trägt.
Genau die Positivliste ist das Problem — sie kannte `"Bayern - 34"` nicht und hätte auch
den Wechsel von `"Nord"` zu `"North"` nicht überlebt.

Entscheidend ergänzend eine **Postcondition** in beiden Funktionen: Wenn der Filter *alle*
Spiele entfernt, ist das ein Abbruch mit den beobachteten Rundenlabels in der Meldung —
nicht eine leere Liga, die klaglos simuliert wird. Diese zehn Zeilen sind der eigentliche
Schutz und gehören vor alles andere (Phase 0).

Regressionstest mit einer RL-Fixture, die sowohl `"Nord - 12"` als auch `"North - 12"`
enthält, plus ein Test, dass eine reine Playoff-Fixture sauber abbricht.

### 3. Update-Loop und Seitengenerator entflechten

`update_all_leagues_loop.R`: die drei `fixtures*`/`beendet_*`/`Ergebnis*`-Tripel werden zu
`lapply` über die Registry mit benannten Listen (`fixtures[[key]]`, `beendet[[key]]`,
`ergebnisse[[key]]`). Die Gating-Logik (Live-Poll, `pending_finished_ids`, Render-Signatur)
bleibt inhaltlich unverändert — sie ist bereits ligaunabhängig formuliert, nur über drei
Variablen statt einer Liste. `test-update-loop-gating.R` (526 Zeilen) muss grün bleiben.

`generate_static_site()`: neue Signatur
```r
generate_static_site(ergebnisse = NULL, output_dir, now, league_data = NULL,
                     Ergebnis = NULL, Ergebnis2 = NULL, Ergebnis3 = NULL,
                     Ergebnis3_Aufstieg = NULL)
```
Die alten Argumente bleiben als Kompatibilitätspfad (füllen `ergebnisse`), damit
`scripts/preview_site.R`, die Fixture `ShinyApp/data/Ergebnis.Rds` und
`test-generate-static-site.R` unverändert funktionieren. Intern wird `data_env` aus
`ergebnisse` befüllt; die namensbasierte `plot_source`-Auflösung bleibt und trägt damit
weiterhin die `Ergebnis3_Aufstieg`-Asymmetrie.

### 4. Menüführung

Zehn Ligen sprengen die flache „·"-Navigation. Zweistufig, weiterhin reines statisches HTML:

```
Herren      Bundesliga · 2. Bundesliga · 3. Liga
Frauen      Bundesliga · 2. Bundesliga
Regionalliga  Nord · Nordost · West · SüdWest · Bayern            Methodik
```

Gruppen aus `nav_group` der Registry; `.nav_items()`/`.nav_html()` in
`generate_static_site.R:37-46/150-163` erzeugen je Gruppe eine Zeile mit vorangestelltem
Label. `index.html` bleibt die Bundesliga. Das CSS (`site_assets/site.css:48-52`) nutzt
bereits `flex-wrap`; ergänzt wird eine Gruppenzeile — kein JavaScript, mobil unkritisch.

### 5. Offline-ELO-Kalibrierung (`RCode/elo_calibration.R` + `scripts/calibrate_historical_elo.R`)

Nach CLAUDE.md-Konvention: Logik in `RCode/`, Wrapper in `scripts/`, Doku in
`docs/user-guide/`, Default Dry-Run mit `--confirm` zum Schreiben.

1. **Beschaffung**: je Liga alle verfügbaren Saisons (`/fixtures?league&season`),
   Rohantworten als JSON-Cache auf Platte → wiederholbar ohne erneute API-Last.
   Größenordnung 60–80 Requests einmalig.
2. **ELO-Lauf**: alle Spiele chronologisch, Startwert einheitlich, über die verfügbaren
   Saisons; Auf-/Absteiger tragen ihren Wert mit. Genutzt wird `calculate_elo_update()`
   (`RCode/elo_aggregation.R:239`) — **Achtung:** dieselbe Funktion trägt den
   Heimvorteil 100; für die Kalibrierung wird der Wert explizit übergeben, damit die
   Eichung auf derselben Physik wie die Simulation ruht.
3. **Ankerung (i)** — Regionalliga an die 3. Liga: additive Verschiebung je Staffel, sodass
   der Mittelwert der RL-Aufsteiger dem Mittelwert der 3.-Liga-Absteiger entspricht
   (Werte über die verfügbaren Saisons gemittelt).
4. **Ankerung (ii)** — Frauen an Herren: additive Verschiebung, sodass der Mittelwert der
   Frauen-BL dem der Herren-BL entspricht (aktuell ~1682).
   **Zwei Freiheitsgrade sauber getrennt:** die *Lage* fixiert diese Ankerung; die
   *Streuung* (heute SD ~141 in der BL) ist frei und wird gegen die beobachtete Remisquote
   von 15,9 % kalibriert. Das ist die eigentliche Modellierung des Frauen-Befunds.
5. **Ergebnis**: committete Startwerte, gleiche Form wie `TeamList_<Saison>.csv`.
   Validierung: simulierte gegen beobachtete Remisquote, Heimsiegquote und Torverteilung
   je Liga.

### 6. Empirie-Report (`scripts/analyze_league_empirics.R`)

Reproduziert die Tabelle oben je Liga und Saison (Tore/Spiel, H/X/A, impliziter Heimvorteil,
beobachtete vs. Poisson-Remisquote) aus dem Fixture-Cache. Grundlage für die Entscheidung,
wo abweichende Parameter gerechtfertigt sind — und Regressionsnetz nach der Kalibrierung.

**Nötige Rust-Änderung**: `tore_slope`/`tore_intercept` sind an zwei Stellen hartkodiert
(`api/handlers.rs:158-159` für `/simulate`, `:371-372` für `/league-details`), obwohl
`SimulationParams` (`models/mod.rs:76-77`) die Felder bereits trägt. Beide werden zu
optionalen Request-Parametern mit den heutigen Werten als Default — **beide Endpunkte
gemeinsam**, sonst divergieren Heatmap und Ausblick-Score-Matrix stillschweigend.
R-seitig durchgereicht in `rust_integration.R` und `league_details.R:255`.

### 7. RL-Abstiegskopplung — exakte Auszählung je Iteration

**Die Verteilung P(k Absteiger nach RL Nord) wird in der Simulation exakt ausgezählt, nicht
aus der aggregierten Matrix rekonstruiert.**

Aus der fertigen Team×Platz-Tabelle lässt sich die Verteilung nicht mehr exakt gewinnen: Sie
enthält nur die Randverteilungen je Team. Ein Poisson-Binomial darüber würde die Teams als
unabhängig behandeln — sie sind es aber nicht, denn genau vier Teams belegen die Plätze
17–20 (stark negativ korreliert). Kontrollrechnung: ein solcher Ansatz liefert einen
Erwartungswert von 4,12 statt exakt 4,00. Der Fehler ist strukturell, nicht numerisch.

Jede der n Simulationen erzeugt aber ohnehin eine konkrete Abschlusstabelle. Es genügt, je
Iteration mitzuschreiben, wie viele der Absteiger zu welcher Staffel gehören, und am Ende
auszuzählen. Das ist exakt, inklusive aller Korrelationen.

**Engine-Erweiterung** (klein, passt in die bestehende Struktur): In
`monte_carlo/mod.rs:97` liegt die Tabelle je Iteration bereits vor; die Aggregation ist ein
sperrfreier per-thread-Fold, den rayon kommutativ reduziert. Ergänzt wird ein zweiter Zähler
neben `counts`:

- Request: optional `group_of_team: Vec<usize>` (Team → Staffel-Index) und
  `relegation_places`.
- Je Iteration: für die Teams auf den Abstiegsplätzen `group_counts[staffel][k] += 1`.
- Reduce: dieselbe kommutative Addition wie bisher.
- Response: `relegation_group_counts` — eine kleine 5×5-Matrix (Staffel × Anzahl).

Kosten: ein Inkrement je Abstiegsplatz und Iteration; die Aggregation bleibt sperrfrei. Ohne
`group_of_team` ändert sich nichts — die Altligen bleiben unberührt.

R-seitig:

```r
# P(>= j) je Staffel, direkt aus den ausgezählten Häufigkeiten
p_ge_j_aus_counts(relegation_group_counts, iterations)

# Formel oben, angewandt auf die RL-Matrix
abstiegs_prognose(rl_matrix, p_ge_j, c_min)
```

Läuft im Renderpfad nach den Simulationen, vor `generate_static_site()`. Die
Vereins→Staffel-Karte ist eine gepflegte CSV (`RCode/club_staffel_map.csv`, alle Vereine
inkl. Bundesliga); `venue.city` aus `/teams` hilft beim erstmaligen Befüllen, die Zuordnung
bleibt handkuratiert und wird beim Laden auf Vollständigkeit geprüft.

Tests: Randfälle (`c=0`, keine 3.-Liga-Absteiger in eine Staffel); Monotonie (P(Abstieg)
fällt mit besserem Platz); und als starke Invariante die **exakte** Erwartungswert-Kontrolle
— die Summe der Absteiger über alle Staffeln muss die Zahl der 3.-Liga-Absteiger *exakt*
treffen (bei Auszählung gibt es hier keine Toleranz, anders als bei der verworfenen
Näherung). Rust-seitig ein Test, dass die Zeilensummen der `relegation_group_counts` der
Iterationszahl entsprechen.

### 8. Aufstiegsrelegation

Hier genügt die aggregierte Matrix, ohne Näherung: Die Meisterschaft je Staffel ist Spalte 1
der jeweiligen Prognose, und die Meister-Ereignisse **verschiedener** Staffeln sind
tatsächlich unabhängig (disjunkte Ligen, keine gemeinsamen Spiele). Damit ist

P(X steigt auf) = P(X Meister seiner Staffel) · Σ_Y P(Y Meister seiner Staffel) · P(X gewinnt gegen Y)

eine exakte Doppelsumme über die Paarungen — kein Monte Carlo nötig. Das Hin-/Rückspiel
wird analytisch über dasselbe Poisson-/ELO-Modell gerechnet (Bausteine in
`/league-details`); über zwei Spiele mit getauschtem Heimrecht hebt sich der Heimvorteil
weitgehend auf. Ergebnis: echte Aufstiegswahrscheinlichkeit statt Meisterwahrscheinlichkeit.

Welche Staffeln direkt aufsteigen und welche in die Relegation müssen, rotiert nach
DFB-Regelung — das ist Konfiguration je Saison in der Registry, nicht ableitbar.

Da die bestehenden Relegationen (BL/2. BL/3. Liga) heute ebenfalls nur als Band
„Relegation" ausgewiesen werden, wird derselbe Mechanismus dort anschließend nutzbar —
als eigener Schritt, nicht als stille Verhaltensänderung der Altligen.

## Phasen

Die Phasen 0–3 sind bewusst **verhaltensneutrale Umbauten an den bestehenden drei Ligen**:
Wenn die erste neue Liga dazukommt, existiert und greift jeder Mechanismus bereits. Die
riskanteste Arbeit (die Daten der neuen Ligen) landet zuletzt auf geprüftem Fundament.

| # | Inhalt | Ergebnis |
|---|---|---|
| 0 | **Schutznetz, keine Verhaltensänderung**: Rundenfilter-Postcondition (Abbruch statt leerer Liga) und globale Kurznamen-Eindeutigkeit; Empirie-Skript + Fixture-Cache | beide Blocker scheitern künftig laut statt leise |
| 1 | Liga-Registry; Literale ersetzen; `round_pattern`; `checkAPILimits` skalieren | Verhalten der 3 Altligen unverändert, Tests grün |
| 2 | Update-Loop + `generate_static_site()` entflechten (kompatible Signatur) | n Ligen technisch möglich |
| 3 | Rust: `tore_slope`/`tore_intercept` als Request-Parameter (beide Endpunkte); `relegation_group_counts` als optionale Zusatzstatistik | **erledigt** (PR #172) — Tormodell je Liga steuerbar, Abstiegsverteilung exakt auszählbar |
| 4 | ELO-Kalibrierung offline; Ankerung (i)+(ii); Streuung gegen Remisquote | committete Startwerte |
| 5 | Neue Ligen in Registry + TeamList; Menü zweistufig | 10 Ligen live |
| 6 | RL-Abstiegskopplung (R-Seite) + Vereins→Staffel-Karte | echte Abstiegswahrscheinlichkeiten |
| 7 | Aufstiegsrelegation | echte Aufstiegswahrscheinlichkeiten |
| 8 | CONTEXT.md, ADR, Methodik-Seite, `docs/user-guide/` | Doku konsistent |

### Stand Phase 3 (September 2026, PR #172)

`relegation_group_counts` ist gebaut: zweiter Zähler im per-thread-Fold, über
dieselbe kommutative Addition rayon-reduziert wie `counts`. Dazu die R-seitige
Übersetzung Stammregion → Positionsindex (`RCode/staffel_zuordnung.R`) und die
letzten 41 Stammregionen in der TeamList — **alle 56 Herren-Teams tragen jetzt
eine**. Die 37 verbleibenden Lücken liegen sämtlich in den Frauen-Ligen und
sollen dort bleiben (eigene Wechselgemeinschaft, ADR 0004).

Der Rundungsweg über ein Poisson-Binomial bleibt ausgeschlossen — die Begründung
steht in §7 und jetzt auch am Feld `SimulationResult::relegation_group_counts`.

**Für Phase 6 zu beachten:** `group_count` leitet der Handler als
`max(group_of_team) + 1` ab. Stellt eine Liga kein Team der höchstnummerierten
Staffel (Bayern, Index 4), fällt deren Zeile weg und die Matrix ist kürzer als
erwartet. Heute trifft das keine der drei Herren-Ligen; der eingefrorene Test
`relegation_group_counts_respects_group_assignment` schreibt die Ableitung fest.
Wer Zeilen fest einer Staffel zuordnet, muss also die Länge prüfen statt sie
vorauszusetzen. Das Feld `group_count` existiert bereits, damit ein Aufrufer die
Zahl später explizit setzen kann, ohne die Signatur zu ändern.

**Offen, unabhängig von Phase 3:** die Validierung der Stammregionen über die
Landesverbände (Verein → Landesverband → Oberliga → Regionalliga). Sie erzeugt
die Zuordnung nicht, sondern prüft sie nach — ein eigener Lauf mit
Browser-Zugriff. Gebraucht wird sie erst für Phase 6.

## Doku-Folgearbeiten

- **CONTEXT.md**: `Ergebnis`/`Ergebnis2`/`Ergebnis3` sind als benannte Singletons definiert;
  sie brauchen einen Sammelbegriff. „Live-Poll … aller drei Ligen" und „Statische Seite
  (drei Liga-Seiten)" müssen mitwachsen. Neue Begriffe: Staffel, Vereins→Staffel-Karte,
  Abstiegskopplung, Aufstiegsrelegation.
- **Neue ADRs**: (a) Liga-Konfiguration als Daten statt Literale; (b) ELO-Eichung für Ligen
  ohne Historie (die Ankerung ist eine Modellentscheidung, die begründet gehören).
- **Methodik-Seite** (`RCode/site_assets/methodik_content.html`): nennt „65 ELO-Punkte" und
  BL-typische ELO-Spannen als allgemeingültig; muss je Liga qualifiziert werden. Ehrlich zu
  benennen ist, dass das Modell die Remisquote der Frauen-Ligen überschätzt.
- **Folge-Issue** (bewusst nicht Teil dieses Vorhabens): Heimvorteil 100 (`elo_aggregation.R:245`)
  vs. 65 (`models/mod.rs:84`) — Start-ELOs werden mit anderer Physik gerechnet als jede
  Prognose; dazu der empirische Befund ~25 ELO. Ebenfalls dort: doppelter ELO-Basiswert für
  Liga 79 (1350 in `elo_aggregation.R:391` vs. 1500 in `team_record_builder.R:12`) und die
  Zweitvertretungs-Erkennung über Kurznamen-Suffix statt `Promotion`-Spalte
  (`update_all_leagues_loop.R:186`).

## Nachtrag (September 2026): Stand nach Phase 4

Phase 4 ist umgesetzt; drei Annahmen dieses Plans haben sich dabei
geändert.

### Das Tormodell gilt je Wechselgemeinschaft, nicht je Staffel

`§1` skizzierte einen `tore_intercept` je Staffel (1,71 für Nord, 1,51 für
Bayern). Das wäre falsch: ELO ist das Einzige, was ein Team über eine
Ligagrenze mitnimmt — nur bei gleichem Tormodell bedeutet ein ELO-Wert auf
beiden Seiten dasselbe. Ein staffelweiser Intercept würde jeden Auf- und
Absteiger stillschweigend umskalieren.

Massgeblich ist die **Wechselgemeinschaft**: Herren (78, 79, 80, 83–87)
teilen ein Tormodell, die Frauen (82, 1034) haben ein eigenes, weil sie nie
Teams mit den Herren tauschen.

| Wechselgemeinschaft | `tore_slope` | `tore_intercept` |
|---|---|---|
| Herren | 0,0017854953143549 | 1,3218390804597700 |
| **Frauen** | **0,0024058833** | **1,6527603153** |

Die Frauen-Werte sind an 1917 Spielen per Maximum Likelihood geschätzt und
out-of-sample validiert (Brier −2,96 %, in jeder von fünf Testsaisons
besser). Der Heimvorteil bleibt auch dort bei 40: Er ist mit `tore_slope`
teilweise austauschbar, der gemeinsame Fit bevorzugt zwar 28, aber nicht
signifikant (LR 1,43, p 0,23). Herleitung:
[`docs/reports/2026-09-05-frauen-tormodell.md`](../reports/2026-09-05-frauen-tormodell.md).

Die in `§6` geforderte Rust-Änderung ist damit umgesetzt — beide Endpunkte
nehmen `tore_slope`/`tore_intercept` als optionale Parameter, Defaults
unverändert.

### Die ELO-Streuung ist kein freier Parameter

`§5.4` wollte die Streuung gegen die beobachtete Remisquote eichen. Sie ist
aber ein **Gleichgewicht des ELO-Walks**: Startet RL Nord mit SD 400, fällt
sie binnen einer Saison auf 181; startet sie bei 0, wächst sie auf 100. ELO
ist selbstkorrigierend, der k-Faktor 20 begrenzt die Separation.

Die Frauen-Bundesliga bestätigt die Ausgangsvermutung trotzdem — ihre
Streuung wächst über zehn Saisons auf ~257 und liegt damit deutlich über
den Männerligen. Sie erreicht nur nicht die für 15,9 % Remis nötigen 458.
Die verbleibende Lücke von 3,7 Prozentpunkten wird dokumentiert, nicht
nachjustiert: Ursache ist die Verteilungsform (Überdispersion 1,20), nicht
die Parameterlage.

### Die Vereins→Staffel-Karte kommt aus den Daten

`§7` sah eine handkuratierte CSV vor. Nicht nötig: Über sieben Saisons hat
**kein** Verein die Staffel gewechselt (163 von 163 eindeutig). Die
Zuordnung wird aus den Spielplänen abgeleitet und steht in der Spalte
`Region` der TeamList.

### Ergebnis

`RCode/TeamList_2026.csv` führt 237 Teams (vorher 56) im Format
`TeamID;ShortText;Promotion;InitialELO;League;Region;Name`. Die 56
bestehenden Einträge sind unverändert.

| Liga | Mittel | SD |
|---|---:|---:|
| Bundesliga / Frauen-BL | 1675 / 1731 | 153 / 259 |
| 2. Bundesliga | 1401 | 79 |
| 2. Frauen-BL | 1351 | 122 |
| 3. Liga | 1160 | 95 |
| RL Nordost / West / SüdWest / Nord / Bayern | 957 … 887 | ~120 |

Offen aus diesem Plan: Phasen 1–3 (Registry, Entflechtung), 5 (Menü),
6–7 (Abstiegskopplung, Aufstiegsrelegation), 8 (restliche Doku).

## Verifikation

- `source("tests/testthat.R")` — insbesondere `test-league-views.R` (pinnt heute *exakt drei*
  Ligen; wird bewusst erweitert, der generische Gruppen-Invariantentest bleibt), 
  `test-update-loop-gating.R`, `test-generate-static-site.R`, `test-transform_data.R`.
- `cargo test` im `league-simulator-rust/` für die Parametrisierung beider Endpunkte.
- `Rscript scripts/preview_site.R` — Seiten inkl. neuer Navigation lokal prüfen.
- Neuer Regressionstest: RL-Fixture mit `"Nord - N"` **und** `"North - N"` wird vollständig
  übernommen (nicht stillschweigend leer).
- Kalibrierung: simulierte vs. beobachtete Remis-/Heimsiegquote je Liga innerhalb Toleranz.
- Ein voller Scheduler-Lauf gegen die echte API mit Beobachtung der Request-Zahl gegen die
  Prognose von ~844/Tag.
