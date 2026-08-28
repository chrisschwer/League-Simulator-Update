---
status: accepted
date: 2026-08-28
---
# Spieldetails werden deterministisch zur Renderzeit berechnet, nicht persistiert

Der Relaunch der statischen Seite ergänzt je Liga einen Rückblick (ex-ante-1/X/2, Ergebnis, ELO-Anpassung), einen Ausblick (1/X/2, Score-Matrix) und eine Ligatabelle mit ELO und Δ ELO seit Saisonbeginn. Nichts davon liegt heute gespeichert vor: Der Scheduler überschreibt bei jedem Lauf dieselben Seiten, und die ELO-Kette wird in Rust bei jeder Simulation von Saisonbeginn an neu durchgerechnet und verworfen.

Gespeichert werden muss aber auch nichts. Start-ELO (TeamList) plus Spielergebnisse in Spielreihenfolge ergeben deterministisch die ELO vor jedem Spiel; das Poisson-Tormodell liefert daraus 1/X/2 und die vollständige Score-Matrix analytisch in geschlossener Form — ohne Monte Carlo. Entschieden: Ein neuer deterministischer Endpoint im vorhandenen Rust-Server macht diesen ELO-Walk und liefert die Spieldetails; R bleibt reiner Renderer. Die Modellkonstanten (Tor-Formel, Heimvorteil, ELO-Update) existieren damit weiterhin nur in Rust. Es entsteht keine Persistenzschicht: keine Snapshots, keine Datenbank, keine Archivdateien.

Bewusst in Kauf genommen: Prognose-*Verläufe* — etwa die Meisterwahrscheinlichkeit über die Saison — sind so nicht rekonstruierbar, weil Monte-Carlo-Ergebnisse nicht deterministisch aus den Eingaben folgen. Sollte ein solches Feature je gewollt sein, beginnt die Aufzeichnung mit seiner Einführung; rückwirkend gibt es sie nicht.

Verworfen: Nachbau der Modelllogik in R (`calculate_elo_update` existiert als Teilduplikat — jede weitere Kopie erhöht das Drift-Risiko zwischen Anzeige und Simulation); Persistenzschicht im Scheduler (Infrastruktur und Betriebsaufwand für Daten, die sich jederzeit exakt nachrechnen lassen).
