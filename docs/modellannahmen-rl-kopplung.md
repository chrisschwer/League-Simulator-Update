# Modellannahmen der Regionalliga-Kopplung

Was das Modell aus den amtlichen Ordnungen übernimmt, was es davon
**auslässt**, und wo eine Regel mehr als eine Lesart zulässt.

Die Regeln selbst stehen in
[`abstieg_aufstieg_RL_2026_2027.md`](abstieg_aufstieg_RL_2026_2027.md) — jede
mit Belegstelle. Dieses Dokument ist die Gegenrichtung: die Liste der Stellen,
an denen zwischen Ordnung und Code eine Entscheidung liegt, die keine Ordnung
vorgibt.

**Warum getrennt.** Eine Annahme, die nur als Kommentar im Test steht, findet
niemand wieder, wenn sich die Regel ändert — und die Zahlen ändern sich
jährlich. Beim Saisonwechsel ist dieses Dokument die Checkliste.

Stand: 2026-09-07, Phase 6/7 (PR #174). Getestet in
`tests/testthat/test-rl-abstiegskopplung.R` und `test-rl-aufstieg.R`.

---

## 1. Was gerechnet wird

```
P(Team steigt ab) = Σ über Plätze  P(Team auf Platz) · P(Platz ist Abstiegsplatz)
```

Der erste Faktor ist die Prognosematrix der Regionalliga. Der zweite kommt aus
`relegation_group_counts` der 3. Liga: der exakten Auszählung, wie viele
Drittliga-Absteiger je Staffel anfallen (Phase 3, PR #172).

**Die Multiplikation ist exakt, nicht genähert.** 3. Liga und Regionalliga sind
disjunkte Wettbewerbe ohne gemeinsame Spiele — die beiden Ereignisse sind
tatsächlich unabhängig.

Das ist bemerkenswert, weil dieselbe Rechnung *innerhalb* einer Liga falsch
wäre: Dort belegen genau `relegation_places` Teams die Abstiegsplätze, die
Ereignisse sind stark negativ korreliert, und ein Poisson-Binomial über die
Randverteilungen liefert Erwartungswert 4,12 statt exakt 4,00. Genau deshalb
zählt Phase 3 aus, statt zu rechnen. Wer diese Formel später auf einen anderen
Fall überträgt, muss zuerst prüfen, ob die Unabhängigkeit dort auch gilt.

---

## 2. Die fünf Staffeln koppeln nicht gleichsinnig

`k` = Zahl der Drittliga-Absteiger, die in diese Staffel fallen (nach
Stammregion, Spalte `Region` der TeamList).

| Staffel | k = 0 | 1 | 2 | 3 | 4 | Belegstelle |
|---|--:|--:|--:|--:|--:|---|
| SüdWest | 3 | 4 | 5 | 5 | 5 | RLSW-SpO § 47 Nr. 1, Deckel Nr. 2 |
| Nordost | 1 | 2 | 2 | — | — | NOFV A. Nr. 5, Schema A/B |
| Nord | 3 | 4 | 5 | 6 | 7 | NFV-SpO § 6 Abs. 3 und 4 |
| **West** | **4** | **3** | **2** | **1** | **0** | WDFV Abstieg Nr. 1, 3, 4 |
| **Bayern** | **2** | **2** | **2** | **2** | **2** | BFV A&A II. Nr. 1 |

Zwei Staffeln brechen das Muster, und beide sind leicht zu übersehen:

**West wirkt gegenläufig.** Vier feste Absteiger, die *sinken*. Ein
Drittliga-Absteiger verdrängt einen Oberliga-Aufsteiger oder belegt einen Platz
vor — er erhöht die Zahl der sportlichen Absteiger nicht, sondern senkt sie.

**Bayern koppelt gar nicht.** Zwei Direktabsteiger, unabhängig von der 3. Liga.
Die Kopplung wirkt dort über die Ligagröße (2026/27: 19 statt 18 Vereine) und
darüber, dass die Zweitvertretung eines Absteigers ans Tabellenende gesetzt wird.

Ein einheitlicher „Basis + k"-Term — so stand es ursprünglich im Ausbauplan —
wäre für zwei von fünf Staffeln vorzeichenfalsch gewesen.

---

## 3. Bayern: zwei Größen, die nicht verrechnet werden

Nach unten weist Bayern **getrennt** aus:

- **direkter Abstieg** — die zwei Letzten
- **Relegation** — die zwei davor, gegen zwei Bayernligisten

Die Relegation wird **nicht aufgelöst**. Wir simulieren die Bayernligen nicht;
eine Gewinnquote gegen einen Bayernliga-Releganten wäre erfunden. Getrennt
ausgewiesen steht auf der Seite genau das, was das Modell weiß — und es ist
dieselbe Darstellung, die die Altligen für ihre Relegationsplätze schon haben.

**Entscheidung von Christoph, 2026-09-06:** „Für die Regionalliga Bayern gibt es
nach unten nur die Wahrscheinlichkeiten für Relegation und direkten Abstieg."

---

## 4. Aufstieg 2026/27

| Staffel | Weg | P(Aufstieg) |
|---|---|---|
| West, SüdWest | Direktaufstieg (dauerhaft) | = P(Meister) |
| Nordost | Direktaufstieg (Rotationsplatz) | = P(Meister) |
| Nord, Bayern | Aufstiegsspiele gegeneinander | Doppelsumme |

```
P(X steigt auf) = P(X Meister) · Σ_Y P(Y Meister) · P(X gewinnt gegen Y)
```

Exakt, weil Meister-Ereignisse verschiedener Staffeln unabhängig sind. 2026/27
läuft `Y` nur über die Teams der jeweils anderen Playoff-Staffel.

> **Der Ausbauplan lag hier falsch** und nannte Nord als Rotationsplatz.
> Amtlich ist das Gegenteil: Die BFV-Regelung benennt Bayern–Nord als
> Playoff-Paarung, womit Nordost zwingend der dritte Direktaufsteiger ist. Die
> damalige Prüfung stützte sich auf kicker und Wikipedia — beide tragen
> dieselbe Verschiebung um eine Saison, die Regeldoku markiert sie ausdrücklich
> als fehlerhaft.

**Die Rotation gehört nicht in die Registry.** Wer den dritten Direktplatz
bekommt, legt das DFB-Präsidium jährlich fest; es steht in keiner Ordnung
(Regeldoku 3.3). Die Zuordnung ist deshalb saisonabhängig konfigurierbar, und
eine **unbekannte Saison ist ein Fehler**, kein stilles Weiterlaufen mit dem
Vorjahreswert. Für 2027/28 muss sie neu recherchiert werden.

---

## 5. Offene Annahmen

Hier liegt zwischen Ordnung und Code eine Entscheidung. Jede ist bewusst
getroffen, keine ist durch eine Ordnung gedeckt.

### 5.1 Nordost jenseits des Schemas — *Annahme*

Das NOFV-Schema kennt nur zwei Varianten (0 oder 1 Drittliga-Absteiger), weil
**Hansa Rostock 2026/27 der einzige Drittligist aus dem NOFV-Gebiet** ist. Für
`k ≥ 2` gibt es keine Regel, nur die Präsidiums-Öffnungsklausel (A. Nr. 7).

**Angenommen:** Deckel bei 2.

*Wirkung:* Nur bei einem zweiten NOFV-Drittligisten überhaupt erreichbar. Beim
Saisonwechsel zu prüfen.

### 5.2 Nord: Kopplung an den eigenen Aufstieg — *modelliert, mit Näherung*

Nord hat 18 Teams, 3 Regelabsteiger, 3 Oberliga-Aufsteiger; die Bilanz geht auf
(18 − 3 + 3 = 18). Steigt der **Nord-Meister** in die 3. Liga auf, fehlt ein
Team (18 − 1 − 3 + 3 = 17), die Staffelstärke wird unterschritten, und nach
§ 6 Abs. 3 a. E. geht „ein freier Platz zunächst an den bestplatzierten
zugelassenen Absteiger" — der dritte Absteiger bleibt drin.

```
w[d] = P(Meister bleibt) · P(k ≥ d−2)  +  P(Meister steigt auf) · P(k ≥ d−1)
```

also `abstiegsplaetze` mit Basis 3 bzw. 2, gemischt über die binäre
Aufstiegsvariable. Die letzten beiden Plätze sind in beiden Ästen sicher.

**Das ist kein Randfall.** Nord ist 2026/27 eine der beiden Playoff-Staffeln;
die Aufstiegswahrscheinlichkeit ist entsprechend hoch und verschiebt die
Abstiegsschwelle regelmäßig.

> *Annahme — Unabhängigkeit.* Anders als bei den Drittliga-Absteigern stammen
> beide Faktoren aus **derselben** Nord-Simulation: „Team X wird Drittletzter"
> und „der Nord-Meister steigt auf" sind über dieselbe Tabelle verbunden. Das
> Produkt ist hier also eine **Näherung**, kein exaktes Ergebnis.
>
> Sie ist vertretbar, weil dasselbe Team praktisch nie Meister- *und*
> Abstiegskandidat ist und sich beide Zonen gegen Saisonende ohnehin trennen
> (Entscheidung Christoph, 2026-09-07). Wer den Unterschied zu § 1 sucht: Dort
> ist die Unabhängigkeit strukturell gegeben (disjunkte Wettbewerbe), hier ist
> sie eine begründete Vereinfachung.

`P(Meister steigt auf)` wird als fertige Zahl übergeben, nicht intern aus
`rl_aufstieg.R` geholt — das hält die Module getrennt und die Zahl im Test
setzbar.

**Weiterhin nicht modelliert:** § 6 Abs. 4 S. 2 f. — steigt eine Mannschaft
„ohne Anrechnung auf die Zahl der Regelabsteiger" ab, erhöht sich die Zahl
zunächst *nicht*; die Rückführung auf 18 erfolgt erst im Folgejahr. Die
Kopplung wirkt dann **mit einem Jahr Verzögerung**.

*Wirkung:* Das Modell ist in diesem Sonderfall eher zu pessimistisch.

### 5.3 West: `max(4 − k, 0)` ist eine Lesart — *Interpretation*

Der WDFV-Text spricht von verdrängten Oberliga-Aufsteigern und von
Zweitvertretungen, die ans Tabellenende rücken (Nr. 3, 4) — **nicht** wörtlich
von „je Drittliga-Absteiger einer weniger". Die Zusammenschau in Regeldoku 3.2
zieht diese Gleichung; der Ordnungstext selbst gibt sie nicht her.

*Wirkung:* Bei `k ≥ 4` fällt der Abstieg in West rechnerisch ganz aus. Das ist
die aggressivste Extrapolation im ganzen Modell — die Stelle, an der ich am
ehesten mit einer Korrektur rechne.

### 5.4 Bayerns Relegationsplätze bei 19 Teams — *Annahme*

Die Regeldoku nennt „Plätze 17/18", was 18 Vereine voraussetzt; der A&A-Text
sagt „die zwei vor den Festabsteigern". 2026/27 spielt Bayern mit **19**.

**Angenommen:** relativ gerechnet, also n−3 und n−2 (bei 19 Teams: 16 und 17).

**Nicht modelliert:** die Zweitvertretung eines Drittliga-Absteigers als „erster
Absteiger" (RO § 2 Nr. 3); die **Rundenzahl** der Relegation, die selbst vom
Endstand abhängt (bei 19 Teams ist die zweite Runde der Regelfall); die
Aussetzung, solange ein bayerischer Zweitligist in der Abstiegsrelegation der
2. Liga steht.

### 5.5 Fehlende Zeilen in der Zählmatrix — *Entscheidung*

Die Engine leitet `group_count` als `max(group_of_team) + 1` ab (bekannte Grenze
aus PR #172). Stellt eine Liga kein Team der höchstnummerierten Staffel, fehlt
deren Zeile.

**Entschieden:** fehlende Zeilen am Ende mit `P(0) = 1` auffüllen — fachlich
korrekt, denn ohne Teams steigt dorthin niemand ab. Mehr als fünf Zeilen ist ein
Fehler, kein stilles Abschneiden.

### 5.6 `p_sieg` ist Eingang, nicht Herleitung — *Abgrenzung*

Die Gewinnquote über zwei Aufstiegsspiele geht als Matrix **ein**; wie sie
entsteht, ist hier nicht festgelegt. Offen: Verlängerung, das vor Saisonbeginn
ausgeloste Heimrecht, ob der Heimvorteil sich über zwei Spiele wirklich aufhebt.

Angenommen ist lediglich, dass es **keinen Unentschieden-Ausgang** gibt:
Gegenrichtung = `1 − t(p_sieg)`.

### 5.7 Nicht modellierte Sonderfälle — *bewusst ausgelassen*

Alle senken die Absteigerzahl und treten selten auf:

- Verzicht eines qualifizierten Vereins (NOFV A. Nr. 6)
- Zwangsabstieg einer Zweitvertretung, wenn die erste Mannschaft in dieselbe
  Liga absteigt (NFV § 6 Abs. 12)
- nachträgliche Nichtlizenzierung, die eine Liga aufstockt (WDFV Nr. 5)
- Präsidiums-Öffnungsklauseln

---

## 6. Beim Saisonwechsel zu prüfen

Diese Werte sind **jahresabhängig** und stehen nicht in einer Ordnung, aus der
man sie einmalig ableiten könnte:

1. **Rotation** des dritten Direktplatzes (Nord / Nordost / Bayern) — jährlicher
   Präsidiumsbeschluss. Ohne Eintrag bricht die Rechnung ab; das ist Absicht.
2. **Bayerns Teilnehmerzahl** — 2026/27 sind es 19, und daran hängen sowohl der
   Relegationsmodus als auch die Zahl der Direktabsteiger (RO § 21 Nr. 1: „vor
   Saisonbeginn festgelegt").
3. **Zahl der Drittligisten je Stammregion** — sie deckelt `k` faktisch. Für
   2026/27 aus dem Spielplan (`data/fixture_cache/80_2026.json`) und der
   TeamList: Nord 2 (Havelse, SV Meppen), Nordost 1 (Hansa Rostock), Bayern 3,
   SüdWest 6, West 8. Für Nordost bestimmt das, ob Annahme 5.1 überhaupt
   relevant wird.

   > Diese Zahlen gehören an den Spielplan geprüft, nicht an Sekundärquellen.
   > Die Regeldoku hatte Havelse und Meppen zunächst als Regionalligisten
   > geführt (nach einer NFV-Meldung, die die Vorsaison beschrieb) — am
   > Spielplan der 3. Liga 2026/27 widerlegt und dort am 2026-09-07 korrigiert.
4. **Reformstand.** Das Vereinsvotum vom 30.06.2026 hat beide Modelle abgelehnt;
   für 2026/27 und mangels Beschluss auch 2027/28 gilt der heutige Modus. Es
   kursieren Darstellungen, die „vier Direktaufsteiger ab 2028/29" als
   feststehend behaupten — das ist nach dem DFB-Statement nicht der Fall.

---

## 7. Verwandte Dokumente

- [`abstieg_aufstieg_RL_2026_2027.md`](abstieg_aufstieg_RL_2026_2027.md) — die
  amtlichen Regeln mit Belegstellen und Quellenliste
- [`plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md`](plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md)
  — Ausbauplan; § 7 begründet die exakte Auszählung
- [`adr/0004-tormodell-je-wechselgemeinschaft.md`](adr/0004-tormodell-je-wechselgemeinschaft.md)
  — warum die Frauen-Ligen keine Stammregion brauchen
