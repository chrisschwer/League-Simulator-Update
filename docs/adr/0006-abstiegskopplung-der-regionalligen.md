---
status: accepted
date: 2026-09-08
---
# Die Abstiegskopplung wird exakt ausgezählt, je Staffel verschieden gerechnet und je Saison konfiguriert

Wie viele Mannschaften aus einer Regionalliga absteigen, steht vor der Saison nicht fest. Es hängt davon ab, wie viele Drittligisten in genau diese Staffel fallen — nach Stammregion des Vereins, nicht nach Tabellenplatz. Das ist die einzige Stelle im ganzen Modell, an der die Prognose einer Liga in die einer anderen eingeht, und sie zwingt zu drei Entscheidungen.

## Exakt ausgezählt, nicht aus der Prognosematrix gerechnet

Die Verteilung „wie viele Absteiger fallen nach Nord" lässt sich aus der fertigen Team×Platz-Matrix der 3. Liga nicht mehr gewinnen: Sie enthält nur die Randverteilungen je Team. Ein Poisson-Binomial darüber behandelt die Teams als unabhängig — sie sind es aber gerade nicht, denn genau vier von ihnen belegen die vier Abstiegsplätze. Die Kontrollrechnung zeigt den Fehler: Erwartungswert 4,12 statt exakt 4,00. Er ist strukturell, nicht numerisch, und wächst mit der Streuung der Prognose.

Entschieden: Die Engine zählt aus. Jede der 10.000 Iterationen erzeugt ohnehin eine konkrete Abschlusstabelle; es genügt, je Iteration mitzuschreiben, zu welcher Staffel die Absteiger gehören (`relegation_group_counts`, ein zweiter per-thread-Fold neben `counts`, von rayon über dieselbe kommutative Addition reduziert). Das ist exakt, einschließlich aller Korrelationen, und kostet ein Inkrement je Abstiegsplatz und Iteration. Ohne das optionale Feld `group_of_team` ändert sich nichts — die Ligen ohne Kopplung bleiben unberührt.

Die Invariante ist entsprechend scharf: Die Summe der Erwartungswerte über alle fünf Staffeln muss die Zahl der Drittliga-Absteiger *exakt* treffen. `absteiger_verteilung()` bricht bei jeder Abweichung ab. Bei einer Auszählung gibt es hier keine Toleranz — anders als bei der verworfenen Näherung, wo eine Toleranz nötig gewesen wäre und den Fehler versteckt hätte.

Die anschließende Multiplikation `P(Team auf Platz p) · P(Platz p ist Abstiegsplatz)` ist dagegen wieder exakt ohne Rest: 3. Liga und Regionalliga sind disjunkte Wettbewerbe ohne ein einziges gemeinsames Spiel, die beiden Ereignisse sind tatsächlich unabhängig. Genau dieser Unterschied — exakt zwischen Ligen, falsch innerhalb einer Liga — ist die Stelle, an der ein späterer Leser die Formel fälschlich verallgemeinern würde; er steht deshalb im Dateikopf von `RCode/rl_abstiegskopplung.R`.

## Fünf Staffeln, fünf Regeln

Der Ausbauplan hatte eine einheitliche Regel „Basis `c` plus Zahl der Drittliga-Absteiger" angenommen. Die amtliche Recherche ([`docs/abstieg_aufstieg_RL_2026_2027.md`](../abstieg_aufstieg_RL_2026_2027.md)) ergab, dass sie nur für drei von fünf Staffeln gilt:

| Staffel | Abstiegsplätze bei k Drittliga-Absteigern | Belegstelle |
|---|---|---|
| Nord | 3 + k, ohne Deckel | NFV-SpO § 6 Abs. 3 und 4 |
| Nordost | 1 + k, gedeckelt auf 2 | NOFV A. Nr. 5, Schema A/B |
| SüdWest | 3 + k, gedeckelt auf 5 | RLSW-SpO § 47 Nr. 1 und 2 |
| West | konstant 4 | WDFV Abstieg Nr. 1 |
| Bayern | konstant 2 | BFV A&A II. Nr. 1 |

Entschieden: fünf Fälle, ausgeschrieben, jeder mit Belegstelle im Code. West und Bayern koppeln nicht — bei West hängen die übrigen Fälle an den Oberligen und an der Lizenzierung, nicht an der 3. Liga, und der eine Fall, der sie berührt, kann 2026/27 nicht eintreten; Bayerns Zahl ist schlicht fest. Eine einheitliche Formel wäre für diese beiden nicht ungenau, sondern falsch, und zwar lautlos: Sie hätte plausible Zahlen erzeugt.

Nord trägt zusätzlich eine **zweite** Kopplung, an den *eigenen* Meisteraufstieg: Steigt der Nord-Meister auf, wird die Staffelstärke unterschritten und der dritte Absteiger bleibt drin (Basis 3 bzw. 2, gemischt über P(Meister steigt auf)). Diese Mischung ist ausdrücklich eine **Näherung** — beide Größen stammen aus derselben Nord-Simulation und sind korreliert. Vertretbar, weil dasselbe Team praktisch nie Meister- und Abstiegskandidat zugleich ist; der Unterschied zum exakten Fall oben ist aber im Code markiert, damit niemand ihn für dieselbe Art von Produkt hält.

Bayerns Abstiegsrelegation gegen zwei Bayernligisten wird **nicht aufgelöst**. Wir simulieren die Bayernligen nicht; jede Gewinnquote wäre erfunden. Relegation und direkter Abstieg stehen deshalb als zwei getrennte Spalten auf der Seite — dieselbe Darstellung, die die Altligen für ihre Relegationsplätze schon haben.

## Die Aufstiegsrotation ist Konfiguration, keine Konstante

Vier Mannschaften steigen aus den Regionalligen auf. West und SüdWest haben nach § 55b DFB-SpO einen dauerhaften Direktplatz; den dritten rotieren Nord, Nordost und Bayern jährlich unter sich aus, die beiden übrigen spielen den vierten Aufsteiger in zwei Aufstiegsspielen aus.

Wer die Rotation trägt, beschließt das DFB-Präsidium jährlich, und es steht **in keiner Ordnung**. Entschieden: Die Zuordnung ist Saison-Daten (`AUFSTIEGSROTATION` in `RCode/rl_aufstieg.R`), sie enthält nur belegte Saisons, und eine unbekannte Saison **bricht ab** mit der Aufforderung, sie zu recherchieren. Ein stilles Weiterrechnen mit dem Vorjahreswert wäre in zwei von drei Fällen falsch und würde niemandem auffallen. Die Registry führt `promotion_slots`/`playoff_slots` nur als abgeleiteten Stand mit; ein Test hält beide Stellen gegeneinander.

Dass das keine theoretische Vorsicht ist, zeigt die Quellenlage: Der Ausbauplan nannte Nord als Rotationsplatz, gestützt auf kicker und Wikipedia. Amtlich ist Nordost — die BFV-Regelung benennt Bayern–Nord als Playoff-Paarung. Beide Sekundärquellen tragen dieselbe Verschiebung um eine Saison.

Bewusst in Kauf genommen: Der Saisonwechsel bekommt damit einen Schritt mehr, der nicht automatisierbar ist. [`docs/modellannahmen-rl-kopplung.md`](../modellannahmen-rl-kopplung.md) ist dafür die Checkliste; dort stehen auch die Stellen, an denen zwischen Ordnung und Code eine Annahme liegt (der Nordost-Deckel, Bayerns Relegationsplätze bei 19 Vereinen, die Lesart des WDFV-Textes).

## Verworfen

**Poisson-Binomial über die Randverteilungen** — die naheliegende Rechnung ohne Engine-Änderung. Sie liefert einen nachweislich falschen Erwartungswert (4,12 statt 4,00), weil sie die negative Korrelation innerhalb der Liga ignoriert. Der Fehler ließe sich nicht wegtolerieren, nur verstecken.

**Eine einheitliche Kopplungsformel mit Parametern je Staffel** — sie hätte West und Bayern ein Vorzeichen aufgezwungen, das ihre Ordnungen nicht hergeben, und die Ausnahmen als Parameterwerte getarnt statt sie sichtbar zu machen.

**Die Rotation als Konstante in der Liga-Registry** (so der Ausbauplan). Sie ist keine Eigenschaft der Liga, sondern ein jährlicher Beschluss; in der Registry hätte sie ausgesehen wie die stabilen Felder daneben und wäre beim Saisonwechsel übersehen worden.

**Eine angenommene 50:50-Quote für die Aufstiegsspiele**, wenn die Zweikampfquote fehlt. `rl_aufstiegsprognose()` bricht stattdessen ab — aus demselben Grund, aus dem Bayerns Relegation nach unten nicht aufgelöst wird: Eine erfundene Zahl ist auf der Seite nicht von einer gerechneten zu unterscheiden.
