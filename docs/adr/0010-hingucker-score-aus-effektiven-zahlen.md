---
status: accepted
date: 2026-10-31
---
# Der Hingucker-Wert ist das Produkt dreier effektiver Zahlen

Die Seite „Hingucker der Woche" wählt aus den Spielen der nächsten sieben Tage die fünf aus, die den Blick am meisten lohnen: knappe Spiele, bei denen es für beide Teams noch um etwas geht. Dafür braucht es *ein* Maß, das über Ligen mit verschieden vielen Zonen hinweg rangiert.

## Entscheidung

Beide Eigenschaften misst derselbe Index, der Inverse Simpson-Index `D = 1 / Σ pᵢ²`, die **effektive Zahl** gleich wahrscheinlicher Ausgänge:

- `D_Spiel` aus (Sieg Heim, Remis, Sieg Gast), Wertebereich 1 bis 3.
- `D_Team` aus den **Saisonausgängen** des Teams, Wertebereich 1 bis zur Zahl der Zonen der Liga.

`Hingucker-Wert = D_Spiel × D_Heim × D_Gast`. Das Fenster sind die Berliner Kalendertage heute bis heute + 6; offene Spiele (`NS`) im Fenster zählen, dazu laufende Spiele (Status live ohne `SUSP`/`INT`, Anstoß höchstens vier Stunden her) unabhängig vom Fenster — sie tragen das Label „Läuft gerade“, damit das spannendste Spiel nicht verpasst wird, nur weil es schon angepfiffen ist. Der Spielstand fließt nicht ein; die Prognose gilt wie vor Anpfiff, und die Seite sagt das beim Spiel.

Saisonausgänge sind die Zonen, die `league_views()` für die Panels der Seite führt (Meister, CL, EL, …, Relegation, Abstieg), dazu „Mittelfeld“ als Rest. Sie müssen disjunkt sein und sich auf 1 summieren:

- **3. Liga, 2. Frauen-Bundesliga:** Das obere Panel ist der Rang unter den Berechtigten (`Ergebnis3_Aufstieg`, [ADR 0009](0009-aufstiegsberechtigung-als-masken.md); gesperrte Zweitvertretungen tragen null), das untere der Tabellenplatz. Beide stammen aus demselben Lauf, und der Rang unter den Berechtigten ist höchstens der Tabellenplatz. Die Zonen überlappen also nicht; eine Normierung auf Zeilensumme 1 fängt nur Rundung und entartete Eingaben ab.
- **Regionalliga Nord und Bayern:** Die Saison des ersten Berechtigten entscheidet sich daran, dass er die Aufstiegsspiele bestreitet; ob er sie gewinnt, entscheidet sich danach. Der Ausgang heißt deshalb „Aufstiegsspiele“ (`p_erster_berechtigter`, ohne Verzicht der Meister) und ersetzt „Meister“ und „Aufstieg“; wer verzichtet, spielt nicht und trägt null. Keine zweite Zone „verloren“.
- **Regionalliga Nordost, West, SüdWest:** Der erste Ausgang ist der erste Berechtigte, nicht der Meister. Gibt es einen Aufstiegsverzicht, ist „Aufstieg“ P(erster Berechtigter) aus `aufstieg_source` statt P(Platz 1), wie auf der Ligaseite.
- **Zusatzzahlen** (`computed_optional`, etwa „Abstieg gesamt“) zählen nicht mit.

## Warum so einfach

- **Offenheit, nicht Betroffenheit.** `D_Team` sagt, wie verteilt die Saison eines Teams noch ist — nicht, wie stark gerade dieses Spiel sie verschiebt. Ein breiter Mittelfeldklub bekommt einen hohen Wert, auch wenn ein Sieg wenig ändert. Ein Maß der *Verschiebung* (Verteilung nach Sieg vs. nach Niederlage) bräuchte bedingte Simulationen vom Rust-Server und bleibt eine mögliche Erweiterung.
- **Keine Normierung je Liga — zunächst.** Das Maximum von `D_Team` hängt an der Zahl der Zonen (Bundesliga sieben, Regionalliga drei bis vier). Ob etwa der Keller der Regionalliga Bayern ein Spiel Letzter gegen Vorletzter der Regionalliga Nordost schlägt, ist eine Frage an echte Wochen, nicht an die Theorie. Der Generator schreibt dafür je Zyklus eine Logzeile mit dem besten Wert je Liga (`hingucker_logzeile()`). Eine Normierung (etwa `D / Zonenzahl`) wird nachgetragen, falls das Log eine systematische Schlagseite zeigt.

## Folgen

- Die Seite wird in jedem Zyklus geschrieben, auch ohne `league_data` oder ohne Spiele im Fenster (Leermeldung): Die Navigation verlinkt sie immer.
- `hingucker_kandidaten()` liefert alle Spiele im Fenster; die Auswahl der fünf trifft erst der Renderer.
- Die Seitenzahl steigt von 22 auf 23.

## Nachtrag 2026-11-08: Normierung auf den Liga-Median

Das Log zeigte, was der Abschnitt „Keine Normierung je Liga – zunächst" vermutet hatte: Die Bundesliga mit sieben Zonen gewinnt fast jede Woche, die Frauen-Ligen (vier bzw. drei Zonen, früh entschiedene Saisons) und die Regionalligen kommen kaum vor. Eine Woche ohne ein einziges Frauenspiel auf der Seite war der Anlass.

**Entscheidung.** `D_Team` wird durch den Median `M` von `D_Team` über *alle* Teams der Liga geteilt (nicht nur über die Teams mit Spiel im Fenster):

`Hingucker-Wert = D_Spiel × (D_Heim / M) × (D_Gast / M) = D_Spiel × D_Heim × D_Gast / M²`

`D_Team` fragt jetzt: Wie offen ist die Saison dieses Teams im Vergleich zum typischen Team seiner Liga? Die Interessantesten *jeder* Liga werden gefiltert; dass klar entschiedene Ligen dabei seltener vorn liegen, bleibt, weil ihre wenigen offenen Teams weit über dem Median liegen müssen. `D_Spiel` (1 bis 3) liegt in jeder Liga auf derselben Skala und bleibt unnormiert. Das Log nennt `M` je Liga.

**Verglichen** (stilisierte Simulation: zehn Ligen mit den Zonen aus `league_views()`, 400 Spielwochen, Anteil an den fünf Plätzen). Keine Betriebsdaten; die Frauen-Anteile hängen an der angenommenen Ungleichheit der Teams.

| Variante | Bundesliga | Frauen-Ligen | Regionalligen | ≥ 1 Frauenspiel |
|---|---|---|---|---|
| ungleichmäßig (bisher) | 58 % | 3 % | 6 % | 13 % |
| `/ D_ref²` (Inverser Simpson der Zonenbreiten) | 2 % | 3 % | 67 % | 15 % |
| Zonenbreite als Gewicht der Wahrscheinlichkeiten (`p / w`) | 57 % | 0 % | 0 % | 0 % |
| Median der Spiel-Scores je Liga | 18 % | 16 % | 44 % | 59 % |
| **Median von `D_Team` je Liga (gewählt)** | 11 % | 9 % | 53 % | 39 % |

Kandidatenanteile: Bundesliga 10 %, Frauen-Ligen 16 %, Regionalligen 52 %.

**Verworfen.**
- *Referenz aus den Zonenbreiten* (`D_ref`): Die Regionalligen mit ihrem kleinen `D_ref` (≈ 1,7) übernehmen die Seite.
- *Wahrscheinlichkeiten durch die Zonenbreite teilen*: schmale Zonen (Meister) übertönen das Mittelfeld, ein 50/50-Meisterschaftsrennen wirkt fast entschieden; die Bundesliga mit ihren vielen schmalen Zonen gewinnt noch deutlicher.
- *Median der Spiel-Scores*: gleicht am stärksten aus, entkoppelt aber vom absoluten Niveau — jede Liga stellt jede Woche ihre Besten, auch wenn alle Spiele unbedeutend sind.

**Folgen.**
- `hingucker_kandidaten()` liefert zusätzlich `d_median`; `d_heim`/`d_gast` bleiben die Rohwerte und werden mit dem Median auf der Seite gezeigt.
- Die Rechnung steht in der Aufklappzeile je Spiel und im Einleitungstext der Seite.
- Offen: Die Simulation ersetzt keine echte Wochen. Die Logzeile (`Median D_Team: …`) zeigt über einige Zyklen, ob die Frauen-Ligen und Regionalligen angemessen vorkommen.

## Nachtrag 2026-11-09: Aufstiegsspiele als eine Zone

Vorher standen in Nord und Bayern „Aufstieg“ und „Aufstiegsspiele verloren“ als zwei Ausgänge nebeneinander. Das teilte die Zone der Spitzenteams in zwei Hälften und senkte `D_Team` künstlich: Oldenburg (Nord) hatte etwa 17 % Aufstieg und 13 % verloren statt 30 % Teilnahme. Entscheidend für ein Spiel zweier Spitzenteams ist, ob beide in der Zone der Teilnehmer landen. Jetzt ist es eine Zone: Teilnahme an den Aufstiegsspielen.
