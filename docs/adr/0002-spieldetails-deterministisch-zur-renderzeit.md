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

## Nachtrag (12. September 2026): Das Teilduplikat ist gelöscht

Der vorstehende Absatz („Bewusst nicht angefasst") ist erledigt. `calculate_elo_update()`
und `update_elos_for_match()` gibt es nicht mehr; der Saisonwechsel holt seine End-ELOs über
`POST /league-details` aus derselben Engine, die jede Prognose rechnet
([Issue #146](https://github.com/chrisschwer/League-Simulator-Update/issues/146), PR #201).

Damit ist die ursprüngliche Zusage dieses ADR — „Die Modellkonstanten existieren nur in
Rust" — erstmals wörtlich wahr. Sie war es bei der Annahme nicht (der Heimvorteil stand in
R), nach dem ersten Nachtrag nur für die beiden Prognosepfade, und erst jetzt auch für den
Saisonwechsel.

**Warum nicht einfach 40 eintragen.** Der naheliegende Weg wäre gewesen, den Wert von 100
auf den geeichten zu setzen. Er führt in die Irre: Die beiden Heimvorteile wirken über
verschiedene Formeln — Rust über das Poisson-Tormodell, die R-Funktion über die
ELO-Erwartung `1/(1+10^(−HA/400))`. An denselben beobachteten Anteilen geeicht läge der
R-Wert bei ~25,8, nicht bei 40. Eine 25,8 einzutragen hätte die zweite Physik konserviert,
mit einer Zahl, die niemand mehr mit der 40 der Prognose in Beziehung setzen kann. Die
einzige Variante, die *einen* Heimvorteil herstellt, war die Löschung.

Gegenprobe an der laufenden Engine, 3:0 bei 1500 gegen 1480: Der Saisonwechsel rechnet jetzt
+14,359 ELO — exakt der Wert für Heimvorteil 40 (mit 100 wären es 11,565 gewesen).

Ein Wachhund-Test (`tests/testthat/test-ein-elo-walk.R`) hält die Abwesenheit beider
Funktionen fest. Das ist kein Misstrauen gegen künftige Autoren, sondern folgt aus der
Natur des Fehlers: Zwei ELO-Implementierungen widersprechen sich nur in den Zahlen, nie im
Typ — ihr Auseinanderlaufen fällt im Betrieb nicht auf.
