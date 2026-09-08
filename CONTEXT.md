# League Simulator Update

Berechnet nach jedem Spiel Wahrscheinlichkeiten für die Endplatzierung in zehn deutschen Ligen — Bundesliga, 2. Bundesliga, 3. Liga, den fünf Regionalligen sowie Frauen-Bundesliga und 2. Frauen-Bundesliga — und veröffentlicht sie als statische Seiten unter fussball.csdatascience.de (Begleiter zum Blog „30 Punkte“).

## Language

**Prognose**: Die Wahrscheinlichkeitsmatrix Team × Endplatz einer Liga nach 10 000 Monte-Carlo-Saisonsimulationen. _Avoid_: Vorhersage, Tipp
**Ergebnisse**: Der Sammelbegriff für die Prognosen aller aktiven Ligen — die benannte Liste, über die Update-Loop und Seitengenerator verbunden sind; Schlüssel sind die Registry-Schlüssel (`bundesliga`, `rl_nord`, …). _Avoid_: Ergebnis-Objekte (mehrdeutig zu den Singletons unten)
**Ergebnis / Ergebnis2 / Ergebnis3**: Die Prognose der Bundesliga / 2. Bundesliga / 3. Liga (R-Objekte, class `table`). Historische Einzelnamen aus der Drei-Ligen-Zeit; sie leben als Kompatibilitätspfad von `generate_static_site()` weiter, der Produktivpfad benutzt **Ergebnisse**.
**Ergebnis3_Aufstieg**: Die 3.-Liga-Prognose mit −50-Punkte-Malus für Zweitvertretungen; Quelle der Aufstiegstabelle, nicht der Heatmap.
**Zweitvertretung**: Reserveteam eines Profivereins (Kurzname endet auf „2“); darf nicht aufsteigen.
**TeamList**: Die Saisondatei `RCode/TeamList_<Jahr>.csv` mit Team-IDs, Kurznamen, Aufstiegs-Flag und Start-ELO.
**Kurzname** (`ShortText`): Das Kürzel eines Teams; wird in `transform_data()` zum **Spaltennamen** des Simulations-Data-Frames. Muss deshalb innerhalb einer **Wechselgemeinschaft** eindeutig sein — dort wechseln Teams die Liga. Über die Grenze hinweg ist Gleichheit erlaubt und erwünscht: Die Frauenmannschaft eines Vereins trägt dasselbe Kürzel wie die Herrenmannschaft (SGE, HSV, SCF, RBL, …), weil beide nie in derselben Simulation und nie auf derselben Seite stehen. _Avoid_: global eindeutig
**Saisonwechsel**: Einmal jährlich (Juli) auf dem Entwicklerrechner ausgeführter Vorgang, der die neue TeamList erzeugt und committet. _Avoid_: Migration
**Scheduler**: Der Dauerprozess, der täglich 11:00–23:00 (Berlin) alle zwei Minuten Ergebnisse holt, bei Bedarf simuliert und die statische Seite rendert. Der frühe Start deckt die Vormittagsspiele der 2. Frauen-Bundesliga ab (Anstoß ab 11:00).
**Live-Poll**: Die billige Einzelanfrage nach laufenden Spielen aller aktiven Ligen, die der Scheduler fast jeden Loop stellt — ein Request, unabhängig von der Ligazahl.
**Vollabruf**: Der teure Abruf aller Saisonspiele einer Liga; nur nach Spielende oder alle 30 Loops.
**Statische Seite**: Die vom Scheduler gerenderten HTML-Seiten — je Liga eine, dazu die Aufstiegsseite der Regionalligen und die Methodik-Seite (September 2026: zwölf; bis zum Relaunch 2026: drei Seiten samt PNG-Heatmaps). Die Navigation ist seit dem Ligen-Ausbau zweistufig, gruppiert nach `nav_group` der **Liga-Registry**. _Avoid_: Shiny-App, Dashboard (historisch)
**Stale-Banner**: Hinweis auf der Seite, wenn die Prognose älter als 24 Stunden ist; clientseitig ermittelt.
**Umzugsbanner**: Die letzte, inhaltslose App auf shinyapps.io mit Verweis auf die neue Adresse (September 2026).
**Ligatabelle**: Die aus den Spielergebnissen berechnete aktuelle Tabelle einer Liga samt ELO und Δ ELO seit Saisonbeginn; standardmäßig nach Platz sortiert, clientseitig auch nach Punkten oder ELO sortierbar.
**Gewertetes Spiel**: Ein am grünen Tisch entschiedenes Spiel (api-football-Status `AWD`/`WO`, etwa nach Nichtantritt). Sportrechtlich ein Ergebnis: Es zählt für **Ligatabelle** und **Prognose**-Endtabelle wie ein beendetes Spiel — bewegt aber die ELO-Wertung nicht, weil es nichts über Spielstärke aussagt ([Issue #157](https://github.com/chrisschwer/League-Simulator-Update/issues/157)). Im **Rückblick** als „Wertung" gekennzeichnet.
**Abgeschlossener Spieltag**: Spieltag, dessen Spiele sämtlich beendet oder verschoben (api-football-Status PST/CANC/TBD) sind. Verschobene Spiele halten einen Spieltag nicht offen.
**Laufender Spieltag**: Spieltag mit mindestens einem beendeten oder laufenden und mindestens einem offenen, nicht verschobenen Spiel.
**Rückblick**: Sektion je Liga-Seite mit allen seit Beginn des zuletzt abgeschlossenen Spieltags beendeten Spielen — einschließlich gekennzeichneter Nachholspiele älterer Spieltage — mit ex-ante-1/X/2, Ergebnis und ELO-Anpassung beider Teams.
**Ausblick**: Sektion je Liga-Seite mit den offenen, nicht verschobenen Spielen des laufenden bzw. des nächsten Spieltags plus früher angesetzten Nachholspielen; je Spiel Termin, 1/X/2 und Score-Matrix.
**Score-Matrix**: Die analytisch aus dem Poisson-Tormodell berechnete Wahrscheinlichkeitsmatrix Heimtore × Auswärtstore eines einzelnen Spiels; kein Monte-Carlo-Ergebnis.
**Methodik-Seite**: Die statische Seite mit den Erläuterungen des Prognosemodells (Basis: Blogartikel „Was die Prognosen mit Schach zu tun haben“, 2015, aktualisiert).
**Wechselgemeinschaft**: Die Menge von Ligen, zwischen denen Mannschaften auf- und absteigen. Innerhalb einer Wechselgemeinschaft müssen alle Ligen dasselbe **Tormodell** benutzen, weil ELO das Einzige ist, was ein Team über eine Ligagrenze mitnimmt. Es gibt zwei: Herren (78, 79, 80, 83–87) und Frauen (82, 1034). _Avoid_: Ligafamilie, Liga-Gruppe
**Tormodell**: Das Paar `tore_slope`/`tore_intercept`, das aus der ELO-Differenz die Torerwartung beider Seiten macht. Es gilt `E[Tore/Spiel] = 2 × tore_intercept`, weil die ELO-Steigungen sich aufheben. Je **Wechselgemeinschaft** ein Wert.
**Staffel**: Eine der fünf regionalen Regionalligen (Bayern, Nord, Nordost, SüdWest, West). Sie spielen nie gegeneinander; verglichen werden sie nur über ihre Aufsteiger in die 3. Liga. Die amtlichen Auf- und Abstiegsregeln jeder Staffel stehen in [docs/abstieg_aufstieg_RL_2026_2027.md](docs/abstieg_aufstieg_RL_2026_2027.md).
**Stammregion**: Die Staffel, der ein Verein dauerhaft zugeordnet ist (Spalte `Region` der **TeamList**). Über sieben Saisons hat kein Verein sie gewechselt. Sie ersetzt die ursprünglich geplante handkuratierte Vereins→Staffel-Karte; die Übersetzung in den Staffel-Index der Engine steht in `RCode/staffel_zuordnung.R`, eine unbekannte Region bricht dort ab. _Avoid_: Vereins→Staffel-Karte, club_staffel_map
**Liga-Registry**: Die eine Datenquelle für alles, was eine Liga ausmacht — API-ID, **Wechselgemeinschaft**, Slug, Navigation, Teamzahl-Spanne, Auf- und Abstiegsplätze (`RCode/league_registry.R`, [ADR 0005](docs/adr/0005-liga-konfiguration-als-daten.md)). Vorher standen die Liga-IDs als Literale an rund 60 Stellen. _Avoid_: Liga-Konfiguration, Liga-Liste
**Abstiegskopplung**: Dass die Zahl der Absteiger einer **Staffel** davon abhängt, wie viele Drittligisten nach **Stammregion** in genau diese Staffel fallen. Die Engine zählt je Iteration aus (`relegation_group_counts`), statt aus der aggregierten Prognose zu rechnen; P(Team steigt ab) ist dann die Summe über Plätze von P(Team auf Platz) · P(Platz ist Abstiegsplatz). Nur Nord, Nordost und SüdWest koppeln — West und Bayern haben eine feste Absteigerzahl ([ADR 0006](docs/adr/0006-abstiegskopplung-der-regionalligen.md)). _Avoid_: Abstiegsregel (die ist je Staffel amtlich, die Kopplung ist das Modell darüber)
**Aufstiegsrelegation**: Die zwei Aufstiegsspiele, in denen zwei Staffelmeister den vierten Aufsteiger in die 3. Liga ausspielen. West und SüdWest steigen dauerhaft direkt auf, den dritten Direktplatz rotieren Nord, Nordost und Bayern jährlich unter sich aus — nach jährlichem DFB-Präsidiumsbeschluss ohne Ordnungsgrundlage, deshalb in `AUFSTIEGSROTATION` (`RCode/rl_aufstieg.R`) je Saison hinterlegt; eine unbelegte Saison bricht ab. P(Aufstieg) ist die Doppelsumme über die Meisterpaarungen, nicht P(Meister). _Avoid_: Relegation (unqualifiziert — die Altligen und die RL Bayern haben eine nach unten)

## Relationships

- Eine **Prognose** entsteht aus Spielergebnissen + **TeamList** per Simulation.
- Der **Scheduler** erzeugt aus den **Ergebnissen** genau eine **Statische Seite** (September 2026: zwölf Unterseiten).
- **Ergebnis3_Aufstieg** speist nur die Aufstiegstabelle der 3. Liga; Heatmap und Abstiegstabelle kommen aus **Ergebnis3**.
- **Ligatabelle**, **Rückblick**, **Ausblick** und **Score-Matrix** entstehen deterministisch zur Renderzeit aus TeamList + Spielergebnissen ([ADR 0002](docs/adr/0002-spieldetails-deterministisch-zur-renderzeit.md)); nur die **Prognose** braucht die Monte-Carlo-Simulation.
- Die **Abstiegskopplung** verbindet die 3. Liga mit den fünf **Staffeln**; sie ist die einzige Stelle, an der die Prognose einer Liga in die einer anderen eingeht.
- Ein **Tormodell** gehört zu genau einer **Wechselgemeinschaft**; die Frauen-Ligen tragen seit September 2026 eigene Werte, weil sie nie Teams mit den Herren tauschen.
- Der **Rückblick** endet, wo der **Ausblick** beginnt: Die Grenze ist der Spielstatus, nicht der Spieltag — ein **laufender Spieltag** kann in beiden Sektionen zugleich vertreten sein.

## Example dialogue

> **Dev:** „Wenn der **Scheduler** nachts steht, zeigt die **Statische Seite** dann alte Zahlen?“
> **Domain expert:** „Ja, aber mit **Stale-Banner** — der Browser rechnet das selbst aus, die Seite muss dafür nicht neu gerendert werden.“

## Flagged ambiguities

- „Shiny-App“/„Dashboard“ bezeichneten bis August 2026 das Auslieferungsformat; seither ist das die **Statische Seite**. `ShinyApp/app.R` ist mit dem Relaunch entfallen; lokale Vorschau läuft über `scripts/preview_site.R`.
- „Migration“ wurde sowohl für den Saisonwechsel als auch für den Hosting-Umzug verwendet — **Saisonwechsel** ist der Begriff für Ersteres.

## Decisions

- [ADR 0001](docs/adr/0001-statische-seiten-statt-gehostetem-shiny.md) — statische Seiten statt gehostetem Shiny; shinyapps.io-Pfad entfernt.
- [ADR 0002](docs/adr/0002-spieldetails-deterministisch-zur-renderzeit.md) — Spieldetails (ELO-Verlauf, 1/X/2, Score-Matrix) werden deterministisch zur Renderzeit berechnet, nicht persistiert.
- [ADR 0003](docs/adr/0003-elo-eichung-fuer-ligen-ohne-historie.md) — Start-ELOs für Ligen ohne Historie werden offline erzeugt und über Auf-/Absteiger geankert; Frauen und Herren gelten per Konvention als gleich stark, ELO ist nur innerhalb einer **Wechselgemeinschaft** vergleichbar.
- [ADR 0004](docs/adr/0004-tormodell-je-wechselgemeinschaft.md) — das **Tormodell** gilt je **Wechselgemeinschaft**, nicht je Liga; die Frauen-Ligen tragen eigene Werte.
- [ADR 0005](docs/adr/0005-liga-konfiguration-als-daten.md) — Liga-Eigenschaften stehen als Daten in der **Liga-Registry**, nicht als Literale im Code.
- [ADR 0006](docs/adr/0006-abstiegskopplung-der-regionalligen.md) — die **Abstiegskopplung** wird je Iteration exakt ausgezählt; die fünf **Staffeln** koppeln verschieden, und die **Aufstiegsrelegation** ist saisonabhängig konfiguriert.
