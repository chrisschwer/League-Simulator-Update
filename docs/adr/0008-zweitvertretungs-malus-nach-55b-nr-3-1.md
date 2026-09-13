---
status: accepted
date: 2026-09-12
---
# Der Zweitvertretungs-Malus folgt § 55b Nr. 3.1, nicht einer Ligapauschale

Zweitvertretungen dürfen nicht in die 3. Liga aufsteigen. Das Modell bildet das
als −50-Punkte-Malus in einem zweiten Simulationslauf ab, dessen Ergebnis die
Aufstiegstabelle speist. Die Frage ist, **wer** den Malus bekommt — und darauf
geben Code und Norm bisher verschiedene Antworten.

## Die Norm knüpft an die erste Mannschaft, nicht an die Reserve

Die amtliche Recherche ([`docs/abstieg_aufstieg_RL_2026_2027.md`](../abstieg_aufstieg_RL_2026_2027.md))
hält fest, dass die Rechtsgrundlage **nicht** § 55b Nr. 1 ist — der stellt
Zweitvertretungen gerade *gleich*. Maßgeblich ist § 55b Nr. 3.1:

> Das Aufstiegsrecht entfällt für einen Verein, der „bereits mit einer
> Mannschaft am Spielbetrieb der 3. Liga des kommenden Spieljahrs teil[nimmt]";
> die nächstplatzierte Mannschaft rückt nach.

Die Sperre ist damit keine Eigenschaft der Zweitvertretung, sondern eine des
**Vereins**: Sie greift, weil dessen erste Mannschaft schon in der 3. Liga
steht. Das ist ein anderer Satz als „Reserveteams dürfen nie aufsteigen", und
der Unterschied ist nicht akademisch.

## Die Regel

| Liga | Malus | Warum |
|---|---|---|
| 3. Liga (80) | pauschal | Wer dort steht, käme sonst in die 2. Bundesliga |
| 2. Frauen-Bundesliga (1034) | pauschal | dieselbe Lage eine Ebene höher |
| Regionalligen (83–87) | **nur**, wenn die Erstvertretung in der 3. Liga spielt | genau der Fall des § 55b Nr. 3.1 |

Entschieden, Umsetzung in #206 — die Drei-Fälle-Regel steht heute noch nicht
im Code (siehe „Was heute falsch ist" unten).

Heute betroffen: acht Teams behalten den Malus, **24 verlieren ihn**. Derzeit
hat keine aktive Regionalliga-Zweitvertretung ihre Erstvertretung in der
3. Liga — Bayern II, Dortmund II, Schalke II und die übrigen spielen höher.

Das ist eine sichtbare Änderung: Diese 24 erscheinen künftig in der
Aufstiegstabelle ihrer Staffel und können deren Aufstiegschance besetzen. Das
ist gewollt — sie **dürfen** heute aufsteigen, und die Seite soll zeigen, was
gilt, nicht was meistens gilt.

Die Regel ist zugleich selbstheilend: Fällt ein Bundesligist bis in die 3. Liga
durch, greift die Sperre für seine Regionalliga-Reserve von selbst, sobald die
Ligazuordnung fortgeschrieben ist.

## Was heute falsch ist — an beiden Enden

`get_promotion_value_interactive()` fragt `if (league != "80") return(0)` und ist
damit **zu eng**: Die 2. Frauen-Bundesliga fehlt, obwohl die Registry sie als
aufstiegsbeschränkt führt und der Loop dort einen zweiten Lauf rechnet.

`csv_generation.R` läuft anschließend über **alle** Zeilen und setzt −50, wann
immer die Heuristik auf dem Kurznamen anschlägt — ligaunabhängig. Das ist **zu
weit**, und schlimmer: Es überschreibt eine gepflegte Spalte nachträglich. Der
Carryover übernimmt `promotion_value` brav aus der Vorsaison, danach kassiert die
Heuristik die Entscheidung wieder ein. Für die TeamList als Stammdatenblatt
([ADR 0007](0007-teamlist-ist-gepflegtes-stammdatenblatt.md)) ist das
unhaltbar.

Künftig gilt die Regel an **einer** Stelle: Der Carryover gewinnt für
Bestandsteams, die Heuristik entscheidet nur noch über Neuzugänge — und was sie
dabei geraten hat, steht im Konfliktbericht.

## Warum ein eigener ADR

Die Entscheidung widerspricht der heutigen Begründung in
`RCode/league_registry.R`, wo alle fünf Regionalligen `restrictions` tragen mit
dem Hinweis, auch aus der Regionalliga dürften Zweitvertretungen nicht
aufsteigen. Das bleibt richtig — aber eben nur unter der Bedingung des
§ 55b Nr. 3.1, und die stand dort nicht.

Ohne diesen Text wäre die Änderung für einen späteren Leser nicht
nachvollziehbar: Er fände 24 Teams ohne Malus, eine Registry, die
Aufstiegsbeschränkungen behauptet, und keinen Grund für den Unterschied.
