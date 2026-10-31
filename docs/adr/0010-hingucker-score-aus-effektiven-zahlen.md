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

`Hingucker-Wert = D_Spiel × D_Heim × D_Gast`. Das Fenster sind die Berliner Kalendertage heute bis heute + 6; nur offene Spiele (`NS`) zählen.

Saisonausgänge sind die Zonen, die `league_views()` für die Panels der Seite führt (Meister, CL, EL, …, Relegation, Abstieg), dazu „Mittelfeld" als Rest. Wo Zonen aus verschiedenen Läufen stammen (3. Liga) oder sich überlappen (Regionalliga: Aufstieg ⊂ Meister, dort „Aufstiegsspiele" als Differenz), wird so zerlegt, dass die Ausgänge disjunkt sind und sich auf 1 summieren. Berechnete Zusatzspalten (`computed_optional`, etwa „Abstieg gesamt") zählen nicht mit.

## Warum so einfach

- **Offenheit, nicht Betroffenheit.** `D_Team` sagt, wie verteilt die Saison eines Teams noch ist — nicht, wie stark gerade dieses Spiel sie verschiebt. Ein breiter Mittelfeldklub bekommt einen hohen Wert, auch wenn ein Sieg wenig ändert. Ein Maß der *Verschiebung* (Verteilung nach Sieg vs. nach Niederlage) bräuchte bedingte Simulationen vom Rust-Server und bleibt eine mögliche Erweiterung.
- **Keine Normierung je Liga — zunächst.** Das Maximum von `D_Team` hängt an der Zahl der Zonen (Bundesliga sieben, Regionalliga drei bis vier). Ob etwa der Keller der Regionalliga Bayern ein Spiel Letzter gegen Vorletzter der Regionalliga Nordost schlägt, ist eine Frage an echte Wochen, nicht an die Theorie. Der Generator schreibt dafür je Zyklus eine Logzeile mit dem besten Wert je Liga (`hingucker_logzeile()`). Eine Normierung (etwa `D / Zonenzahl`) wird nachgetragen, falls das Log eine systematische Schlagseite zeigt.

## Folgen

- Die Seite wird in jedem Zyklus geschrieben, auch ohne `league_data` oder ohne Spiele im Fenster (Leermeldung): Die Navigation verlinkt sie immer.
- `hingucker_kandidaten()` liefert alle Spiele im Fenster; die Auswahl der fünf trifft erst der Renderer.
- Die Seitenzahl steigt von 22 auf 23.
