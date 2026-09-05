---
status: accepted
date: 2026-08-28
---
# Spieldetails werden deterministisch zur Renderzeit berechnet, nicht persistiert

Der Relaunch der statischen Seite ergänzt je Liga einen Rückblick (ex-ante-1/X/2, Ergebnis, ELO-Anpassung), einen Ausblick (1/X/2, Score-Matrix) und eine Ligatabelle mit ELO und Δ ELO seit Saisonbeginn. Nichts davon liegt heute gespeichert vor: Der Scheduler überschreibt bei jedem Lauf dieselben Seiten, und die ELO-Kette wird in Rust bei jeder Simulation von Saisonbeginn an neu durchgerechnet und verworfen.

Gespeichert werden muss aber auch nichts. Start-ELO (TeamList) plus Spielergebnisse in Spielreihenfolge ergeben deterministisch die ELO vor jedem Spiel; das Poisson-Tormodell liefert daraus 1/X/2 und die vollständige Score-Matrix analytisch in geschlossener Form — ohne Monte Carlo. Entschieden: Ein neuer deterministischer Endpoint im vorhandenen Rust-Server macht diesen ELO-Walk und liefert die Spieldetails; R bleibt reiner Renderer. Die Modellkonstanten (Tor-Formel, Heimvorteil, ELO-Update) existieren damit weiterhin nur in Rust. Es entsteht keine Persistenzschicht: keine Snapshots, keine Datenbank, keine Archivdateien.

Bewusst in Kauf genommen: Prognose-*Verläufe* — etwa die Meisterwahrscheinlichkeit über die Saison — sind so nicht rekonstruierbar, weil Monte-Carlo-Ergebnisse nicht deterministisch aus den Eingaben folgen. Sollte ein solches Feature je gewollt sein, beginnt die Aufzeichnung mit seiner Einführung; rückwirkend gibt es sie nicht.

Verworfen: Nachbau der Modelllogik in R (`calculate_elo_update` existiert als Teilduplikat — jede weitere Kopie erhöht das Drift-Risiko zwischen Anzeige und Simulation); Persistenzschicht im Scheduler (Infrastruktur und Betriebsaufwand für Daten, die sich jederzeit exakt nachrechnen lassen).


## Nachtrag (September 2026): Heimvorteil neu kalibriert, R sendet ihn nicht mehr

Die Aussage „Die Modellkonstanten (Tor-Formel, Heimvorteil, ELO-Update) existieren damit weiterhin nur in Rust" traf faktisch nicht zu: Der Heimvorteil stand zusätzlich an vier Stellen in R (`rust_integration.R`, `league_details.R`) und wurde von beiden Produktivpfaden bei *jedem* Aufruf mitgesendet — der Rust-Default griff nie. Dass Heatmap und 1/X/2-Werte übereinstimmten, lag allein daran, dass die Defaults zufällig gleich waren.

Entschieden: Die R-Seite sendet `home_advantage` nicht mehr. Der Wert steht ausschließlich im Rust-Server; ein Auseinanderlaufen zwischen `/simulate` (Prognose-Heatmap) und `/league-details` (Ligatabelle, Rückblick, Ausblick) ist damit strukturell ausgeschlossen statt nur unwahrscheinlich. Die R-Parameter bleiben als optionale Übersteuerung mit Default `NULL` erhalten; zwei Tests halten fest, dass der Payload das Feld im Normalfall nicht enthält.

Zugleich wurde der Wert von 65 auf **40 ELO-Punkte** korrigiert. 65 überzeichnete den Heimvorteil: Über eine realistische ELO-Verteilung integriert liefert 40 die tatsächlich beobachteten Anteile (41,0 / 24,4 / 34,7 gegen gemessen 41,2 / 25,0 / 33,8 in den Saisons 2024+2025), 65 dagegen 43,0 % Heimsiege.

Bewusst nicht angefasst: `calculate_elo_update()` (`RCode/elo_aggregation.R`) rechnet den Saisonwechsel weiterhin mit 100. Diese Funktion nutzt die ELO-Erwartungsformel statt des Tormodells — ein anderer Wirkungspfad mit anderer Skala, auf dem der geeichte Wert bei ~25 läge. Sie ist zudem das in diesem ADR bereits benannte Teilduplikat der Rust-Logik. Richtig wäre, sie auf den Rust-Walk umzustellen, statt eine zweite Formel zu pflegen; zeitlich unkritisch, da sie nur einmal jährlich im Juli läuft.
