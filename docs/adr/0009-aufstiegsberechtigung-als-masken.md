---
status: accepted
date: 2026-10-31
---
# Die Aufstiegsberechtigung wird als Maske im selben Lauf ausgewertet

Wer aufsteigen darf, ist nicht dasselbe wie wer oben steht. Eine **Zweitvertretung** ist gesperrt, wenn ihre Erstmannschaft in der 3. Liga spielt (§ 55b Nr. 3.1 DFB-SpO), ein Verein kann auf den Aufstieg **verzichten**. Der Aufstieg geht dann an den bestplatzierten *berechtigten* Verein — und das ist in der Prognosematrix nicht abzulesen, die nur „Platz je Team" kennt.

## Entscheidung

Die Engine nimmt im Request eine Liste von **Masken** entgegen (`eligibility_masks`, je Maske ein bool je Team). Zu jeder Maske zählt sie auf **derselben Abschlusstabelle** jeder Iteration, auf welchem Rang *unter den Berechtigten* jedes berechtigte Team steht, und liefert `eligible_rank_probabilities[maske][team][rang]` (Teams in der Reihenfolge der Prognosematrix, Gesperrte tragen null). Ohne das Feld ändert sich nichts.

Das löst den bisherigen zweiten Simulationslauf mit −50 Punkten ab (3. Liga, 2. Frauen-Bundesliga). Ein Vergleichstest (`test-rust_integration-masken.R`) zeigt, dass beide Wege dieselbe Verteilung liefern (Monte-Carlo-Toleranz; eine Handprobe mit 40.000 Iterationen ergab höchstens 0,004 Abweichung) — und ein Rust-Test mit festen Seeds zeigt exakte Gleichheit, weil die Punkte der Gesperrten den Spielverlauf nicht beeinflussen. Das Ergebnis ist sogar *exakter*, weil es keine zwei unabhängigen Zufallsläufe mehr gibt: „Meister" und „Aufstieg" stammen aus denselben Iterationen.

## Warum nicht anders

- **Gemeinsame Simulation aller Ligen, je Iteration konkret ausgelesen.** Verworfen: 2. Bundesliga, 3. Liga und die Regionalligen teilen kein einziges Spiel. Ihre Ergebnisse sind unabhängig, also gilt exakt `P(Aufstieg) = Σ_S P(S) · M_S` mit den Gewichten `P(S)` der Sperr-Kombinationen. Eine gemeinsame Simulation wäre langsamer und nicht genauer. Sie bleibt als langsamer Referenztest für Schritt 3 vorgesehen (#322).
- **Ein Lauf je Sperr-Kombination.** Verworfen: bis zu 2^k Läufe je Staffel mit je 10.000 Iterationen, und die Zufallsunschärfe zwischen den Läufen käme zurück. Die Masken laufen auf *einer* Tabelle.
- **Malus-Lauf behalten.** Verworfen: Der Malus ändert die Tabelle, die Maske nicht. Der Rang der Berechtigten ist nur dann in beiden Fällen gleich, wenn die Gesperrten mit −50 Punkten hinter allen Berechtigten landen. Das ist bei 38 Spielen nicht garantiert: Eine starke Reserve mit 70 Punkten stünde trotz Abzug noch vor einem schwachen Berechtigten mit 20 und nähme ihm im Malus-Lauf den Rang. Die Maske kennt diesen Randfall nicht, sie ist also nicht nur schneller, sondern in ihm auch richtiger. (Der exakte Rust-Test oben nutzt deshalb eine Liga, in der −50 sicher das Tabellenende bedeutet.)

## Folgen

- `Ergebnis3_Aufstieg` und `Ergebnis_zweite_frauen_bundesliga_aufstieg` sind jetzt der Rang unter den Berechtigten, mit Nullzeilen für Gesperrte (vorher: Gesperrte am Tabellenende).
- Die Maske kommt aus der TeamList: `Promotion < 0` (nur 3. Liga und 2. FBL) und die optionale Spalte `Aufstiegsverzicht` (`berechtigung_aus_teamlist()`). Der Saisonwechsel schreibt die Spalte nicht fort, ein Verzicht gilt also nur für die Saison, für die er eingetragen wurde.
- Die Regionalligen nutzen die Maske seit #320 für den Aufstiegsverzicht (`mit_sperre = FALSE`: dort wirkt nur die Spalte `Aufstiegsverzicht`, nicht `Promotion`); eine Maske wird nur gesendet, wenn jemand verzichtet. In Direktstaffeln ist `P(Aufstieg) = P(erster Berechtigter)`, in den Aufstiegsspielen `P(erster Berechtigter) · P(Sieg)`; die Siegquote rechnet auf `P(erster Berechtigter)`, nicht auf `P(Meister)`. Die Aufstiegsseite kennzeichnet Verzichtende als „verzichtet“. Die dynamische Sperre aus dem Abstieg der Zweitligisten (#322) rechnet danach mit mehreren Masken je Staffel und den Gewichten `P(S)`.

## Nachtrag: gemeinsame Klassenzählung für die dynamische Sperre (#322, Schritt 3a)

Für die Aufstiegssperre aus dem Abstieg der Zweitligisten braucht R die **gemeinsame** Verteilung, in welcher Tabellenklasse die verfolgten Erstmannschaften der 2. Bundesliga enden. Die Prognosematrix liefert nur Randverteilungen, und die Teams sind negativ korreliert, weil nur wenige Plätze absteigen. Die Engine nimmt deshalb optional `tracked_teams` (0-basierte Indizes), `tracked_direct_places` und `tracked_playoff_places` entgegen und liefert `tracked_class_patterns`: je Klassenvektor (0 = sonst, 1 = direkter Abstieg, 2 = Relegationsplatz, in der Reihenfolge der Anfrage) die Häufigkeit über alle Iterationen. Es sind nur wenige Dutzend Muster, weil höchstens `tracked_direct_places` Teams direkt absteigen. Die Relegation selbst löst R auf (sie hängt an der 3. Liga, die die Engine nicht kennt). Ohne die Felder ändert sich nichts, und die Prognosematrix bleibt bitgleich.
