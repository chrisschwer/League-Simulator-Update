# League Simulator Update

Berechnet nach jedem Spiel Wahrscheinlichkeiten für die Endplatzierung in Bundesliga, 2. Bundesliga und 3. Liga und veröffentlicht sie als statische Seiten unter fussball.csdatascience.de (Begleiter zum Blog „30 Punkte“).

## Language

**Prognose**: Die Wahrscheinlichkeitsmatrix Team × Endplatz einer Liga nach 10 000 Monte-Carlo-Saisonsimulationen. _Avoid_: Vorhersage, Tipp
**Ergebnis / Ergebnis2 / Ergebnis3**: Die Prognose der Bundesliga / 2. Bundesliga / 3. Liga (R-Objekte, class `table`).
**Ergebnis3_Aufstieg**: Die 3.-Liga-Prognose mit −50-Punkte-Malus für Zweitvertretungen; Quelle der Aufstiegstabelle, nicht der Heatmap.
**Zweitvertretung**: Reserveteam eines Profivereins (Kurzname endet auf „2“); darf nicht aufsteigen.
**TeamList**: Die Saisondatei `RCode/TeamList_<Jahr>.csv` mit Team-IDs, Kurznamen, Aufstiegs-Flag und Start-ELO.
**Saisonwechsel**: Einmal jährlich (Juli) auf dem Entwicklerrechner ausgeführter Vorgang, der die neue TeamList erzeugt und committet. _Avoid_: Migration
**Scheduler**: Der Dauerprozess, der täglich 14:45–22:45 (Berlin) alle zwei Minuten Ergebnisse holt, bei Bedarf simuliert und die statische Seite rendert.
**Live-Poll**: Die billige Einzelanfrage nach laufenden Spielen aller drei Ligen, die der Scheduler fast jeden Loop stellt.
**Vollabruf**: Der teure Abruf aller Saisonspiele einer Liga; nur nach Spielende oder alle 30 Loops.
**Statische Seite**: Die vom Scheduler gerenderten HTML-Seiten (drei Liga-Seiten und die Methodik-Seite; bis zum Relaunch 2026: drei Seiten samt PNG-Heatmaps). _Avoid_: Shiny-App, Dashboard (historisch)
**Stale-Banner**: Hinweis auf der Seite, wenn die Prognose älter als 24 Stunden ist; clientseitig ermittelt.
**Umzugsbanner**: Die letzte, inhaltslose App auf shinyapps.io mit Verweis auf die neue Adresse (September 2026).
**Ligatabelle**: Die aus den Spielergebnissen berechnete aktuelle Tabelle einer Liga samt ELO und Δ ELO seit Saisonbeginn; standardmäßig nach Platz sortiert, clientseitig auch nach Punkten oder ELO sortierbar.
**Abgeschlossener Spieltag**: Spieltag, dessen Spiele sämtlich beendet oder verschoben (api-football-Status PST/CANC/TBD) sind. Verschobene Spiele halten einen Spieltag nicht offen.
**Laufender Spieltag**: Spieltag mit mindestens einem beendeten oder laufenden und mindestens einem offenen, nicht verschobenen Spiel.
**Rückblick**: Sektion je Liga-Seite mit allen seit Beginn des zuletzt abgeschlossenen Spieltags beendeten Spielen — einschließlich gekennzeichneter Nachholspiele älterer Spieltage — mit ex-ante-1/X/2, Ergebnis und ELO-Anpassung beider Teams.
**Ausblick**: Sektion je Liga-Seite mit den offenen, nicht verschobenen Spielen des laufenden bzw. des nächsten Spieltags plus früher angesetzten Nachholspielen; je Spiel Termin, 1/X/2 und Score-Matrix.
**Score-Matrix**: Die analytisch aus dem Poisson-Tormodell berechnete Wahrscheinlichkeitsmatrix Heimtore × Auswärtstore eines einzelnen Spiels; kein Monte-Carlo-Ergebnis.
**Methodik-Seite**: Die statische Seite mit den Erläuterungen des Prognosemodells (Basis: Blogartikel „Was die Prognosen mit Schach zu tun haben“, 2015, aktualisiert).

## Relationships

- Eine **Prognose** entsteht aus Spielergebnissen + **TeamList** per Simulation.
- Der **Scheduler** erzeugt aus vier **Ergebnis**-Objekten genau eine **Statische Seite** (drei Unterseiten).
- **Ergebnis3_Aufstieg** speist nur die Aufstiegstabelle der 3. Liga; Heatmap und Abstiegstabelle kommen aus **Ergebnis3**.
- **Ligatabelle**, **Rückblick**, **Ausblick** und **Score-Matrix** entstehen deterministisch zur Renderzeit aus TeamList + Spielergebnissen ([ADR 0002](docs/adr/0002-spieldetails-deterministisch-zur-renderzeit.md)); nur die **Prognose** braucht die Monte-Carlo-Simulation.
- Der **Rückblick** endet, wo der **Ausblick** beginnt: Die Grenze ist der Spielstatus, nicht der Spieltag — ein **laufender Spieltag** kann in beiden Sektionen zugleich vertreten sein.

## Example dialogue

> **Dev:** „Wenn der **Scheduler** nachts steht, zeigt die **Statische Seite** dann alte Zahlen?“
> **Domain expert:** „Ja, aber mit **Stale-Banner** — der Browser rechnet das selbst aus, die Seite muss dafür nicht neu gerendert werden.“

## Flagged ambiguities

- „Shiny-App“/„Dashboard“ bezeichneten bis August 2026 das Auslieferungsformat; seither ist das die **Statische Seite**. `ShinyApp/app.R` existiert nur noch als lokale Vorschau.
- „Migration“ wurde sowohl für den Saisonwechsel als auch für den Hosting-Umzug verwendet — **Saisonwechsel** ist der Begriff für Ersteres.

## Decisions

- [ADR 0001](docs/adr/0001-statische-seiten-statt-gehostetem-shiny.md) — statische Seiten statt gehostetem Shiny; shinyapps.io-Pfad entfernt.
- [ADR 0002](docs/adr/0002-spieldetails-deterministisch-zur-renderzeit.md) — Spieldetails (ELO-Verlauf, 1/X/2, Score-Matrix) werden deterministisch zur Renderzeit berechnet, nicht persistiert.
