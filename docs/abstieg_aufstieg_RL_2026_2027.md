# Auf- und Abstieg der fünf Regionalligen — Spieljahr 2026/2027

Recherchiert am 2026-09-06 aus den amtlichen Ordnungen der Regionalligaträger
und der DFB-Spielordnung. Jede Zahl in diesem Dokument ist auf ein
Verbandsdokument zurückgeführt; die Quellen stehen am Ende, die Belegstelle
jeweils am Satz.

**Warum das Dokument existiert.** Die fünf Regionalligen sind in
`RCode/league_registry.R` als `active = FALSE` geführt — ausdrücklich, weil
die Abstiegskopplung an die 3. Liga fehlt: „ihre Absteigerzahl hängt davon ab,
wie viele Teams aus der 3. Liga in die jeweilige Staffel fallen, und ein festes
Abstiegs-Panel wäre auf der Seite sichtbar falsch."  Dieses Dokument liefert die
Regelgrundlage dafür (Phasen 6–7 in
[`docs/plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md`](plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md)).

> **Gegenstueck:** Was das Modell aus diesen Regeln uebernimmt, was es
> auslaesst und wo eine Regel mehr als eine Lesart zulaesst, steht in
> [`modellannahmen-rl-kopplung.md`](modellannahmen-rl-kopplung.md).

Die Staffelreihenfolge folgt `STAFFELN` aus `RCode/staffel_zuordnung.R`
(Nord, Nordost, West, SüdWest, Bayern) — sie ist dort Vertrag, weil der Index
die Zeilen der Ergebnismatrix bestimmt.

---

## 1. Der gemeinsame Rahmen: Aufstieg in die 3. Liga

Für alle fünf Staffeln gilt dieselbe Norm — **§ 55b DFB-Spielordnung**
(Fassung vom 28.11.2025, gültig ab 01.07.2026, S. 96 f.). Sie ist die einzige
Stelle, an der die Staffeln überhaupt miteinander verrechnet werden; die
Regionalligaträger verweisen durchweg auf sie (BFV RO § 20 Nr. 1, WDFV-Regelung
Aufstieg Nr. 1 und 3, RLSW-SpO § 49a, NFV-SpO § 6 Abs. 6 und Statut Ziff. 1.3).

> „Für den Aufstieg in die 3. Liga können sich insgesamt bis zu **vier Vereine**
> der 4. Spielklassenebene sportlich qualifizieren und aufsteigen. Zweite
> Mannschaften von Lizenzvereinen sind mit Amateurmannschaften gleich zu
> behandeln." (§ 55b Nr. 1)

> „Sportlich unmittelbar qualifiziert sind die **Meister der regionalen Ligen
> Südwest und West**. Ebenfalls unmittelbar sportlich qualifiziert ist jeweils
> **ein Meister aus den übrigen drei regionalen Ligen**, wobei jeweils im
> Wechsel eine andere der drei regionalen Ligen den dritten direkten Aufsteiger
> stellt. […] Die Meister aus den **beiden jeweils verbleibenden** regionalen
> Ligen ermitteln in **zwei Aufstiegsspielen** den vierten Aufsteiger."
> (§ 55b Nr. 2)

Die Regelung gilt **seit der Saison 2020/21**, beschlossen vom DFB-Bundestag 2019.
Den festen Status von West und SüdWest begründet der DFB damit, dass deren
Gebiete „von Ballungsräumen geprägt [sind] und gemeinsam mehr als 50 Prozent der
gemeldeten Männermannschaften in Deutschland" umfassen (DFB-FAQ, 05.06.2023).
Für die Modellierung heißt das: **West und SüdWest brauchen keine
Saison-Fallunterscheidung**, nur Nord/Nordost/Bayern rotieren.

Vier Aufstiegsplätze verteilen sich also so:

| | Staffel | Weg in die 3. Liga 2026/27 |
|---|---|---|
| 1 | **SüdWest** | Direktaufstieg (fest) |
| 2 | **West** | Direktaufstieg (fest) |
| 3 | **Nordost** | Direktaufstieg (Rotationsplatz, dieses Jahr) |
| 4 | **Nord** vs. **Bayern** | Aufstiegsspiele, Hin- und Rückspiel |

Die Zuordnung des Rotationsplatzes für 2026/27 ist **amtlich belegt** durch die
BFV-Regelung, die die Paarung ausdrücklich benennt:

> „In der Saison 2026/2027 wird der Aufsteiger in die 3. Liga in zwei
> Aufstiegsspielen (Hin- und Rückspiel) gegen den Meister der **Regionalliga
> Nord** ermittelt." (BFV, Auf- und Abstiegsregelung RL Bayern 2026/2027, I. Nr. 1)

Sind Bayern und Nord die Relegationspaarung und West/SüdWest gesetzt, bleibt für
den dritten Direktplatz nur Nordost. Wer die Reihenfolge festlegt, sagt § 55b
Nr. 2 selbst: das **DFB-Präsidium** nach Anhörung des DFB-Spielausschusses —
sie steht in keiner Liga-Ordnung, sondern wird jährlich gesetzt. Das Heimrecht
in den Aufstiegsspielen wird vor Saisonbeginn vom Spielausschuss ausgelost.

> ⚠️ **Warnung zu Sekundärquellen.** Die englische Wikipedia
> („Promotion to the 3. Liga") führt eine Rotationstabelle, die für 2026/27
> *Bayern* als Direktaufsteiger und *Nord–Nordost* als Playoff nennt. Das
> **widerspricht der amtlichen BFV-Regelung** und ist falsch (die Tabelle
> scheint um eine Saison verschoben; ihre Zeile 2025/26 entspricht dem
> tatsächlichen Vorjahr, kicker: „Nordost vs. Bayern"). Für die Modellierung
> gilt ausschließlich die amtliche Quelle.

### Nicht aufstiegsberechtigt

Zweitvertretungen dürfen nicht in die 3. Liga aufsteigen — das ist in der
Registry bereits als `restrictions` hinterlegt und gilt für die Regionalligen
gleichermaßen. Rechtsgrundlage ist nicht § 55b Nr. 1 (der Zweitvertretungen
gerade *gleichstellt*), sondern § 55b Nr. 3.1: Das Aufstiegsrecht entfällt für
einen Verein, der „bereits mit einer Mannschaft am Spielbetrieb der 3. Liga des
kommenden Spieljahrs teil[nimmt]"; die nächstplatzierte Mannschaft rückt nach.
Praktisch ist damit jede zweite Mannschaft eines Drittligisten ausgeschlossen.

---

## 2. Die fünf Staffeln im Einzelnen

### 2.1 Regionalliga Nord — 18 Mannschaften

Träger: Norddeutscher Fußball-Verband (NFV). Maßgeblich ist **§ 6 NFV-Spielordnung**
(Stand 19.03.2026) samt Anhang 1 („Regionalliga-Statut – Herren –").

| | Regelung | Beleg |
|---|---|---|
| Sollstärke | 18 Mannschaften | § 6 Abs. 2 |
| Aufstieg 3. Liga | **Aufstiegsspiele** gegen RL Bayern | § 55b; BFV I. Nr. 1 |
| Absteiger | **grundsätzlich die drei letztplatzierten** | § 6 Abs. 3 |
| Aufsteiger aus den Oberligen | grundsätzlich **drei** | § 6 Abs. 7 |

**Abstieg.** § 6 Abs. 3 setzt drei Regelabsteiger an. Die Zahl ist nach oben
gekoppelt: Sie „erhöht sich, wenn die in Absatz (2) geregelte Staffelstärke
durch den Abstieg von Regelabsteigern in diese Ligen überschritten wird"
(§ 6 Abs. 4) — also je Drittliga-Absteiger mit NFV-Zugehörigkeit einer mehr.
Umgekehrt gilt: Wird die Staffelstärke *unterschritten* (etwa durch den
Aufstieg in die 3. Liga), geht ein freier Platz zunächst an den bestplatzierten
zugelassenen Absteiger, weitere an die nächstbesten der Aufstiegsrunde
(§ 6 Abs. 3 a. E.).

Eine Besonderheit: Steigt eine Mannschaft „ohne Anrechnung auf die Zahl der
Regelabsteiger ihrer bisherigen Spielklasse" ab, erhöht sich die Absteigerzahl
zunächst *nicht*; die Rückführung auf 18 erfolgt erst im Folgejahr (§ 6 Abs. 4
Satz 2 f.). Die Kopplung wirkt also mit einem Jahr Verzögerung.

**Aufstieg in die Liga** (Gegenrichtung, für die Bilanz der Staffelstärke):
Nach § 6 Abs. 7 in der ab 2024/25 geltenden Fassung steigen drei Mannschaften auf —
die bestplatzierte Mannschaft der Oberliga Niedersachsen direkt, dazu Sieger und
Zweitplatzierter einer Aufstiegsrunde zwischen den Besten aus Bremen, Hamburg,
Schleswig-Holstein und der nächstbesten Mannschaft aus Niedersachsen. Die
Durchführungsbestimmungen zur Aufstiegsrunde 2026 beschreiben diese als
„einfache Punktrunde" der vier Beteiligten.

**Keine Relegation um den Klassenerhalt.** Die frühere Regelung (§ 6 Abs. 7 c:
Relegation zwischen dem Viertletzten der RL Nord und dem Zweiten der Oberliga
Niedersachsen) ist in der Spielordnung ausdrücklich als überholt markiert — der
Text „Ab der Spielzeit 2024/2025 regelt sich der Aufstieg wie folgt" ersetzt sie
durch die reine Aufstiegsrunde. Für 2026/27 gilt: **Abstieg rein tabellarisch.**
Nord ist damit neben Nordost die zweite Staffel ohne Abstiegsrelegation.

Zwei weitere Regeln sind für die Simulation relevant:

- **Zwangsabstieg der Zweitvertretung** (§ 6 Abs. 12): „Steigt eine Mannschaft
  in eine der Ligen des NFV ab, in der ihr Verein bereits durch eine Mannschaft
  vertreten ist, so scheidet letztere Mannschaft aus dem Spielbetrieb der
  entsprechenden Liga aus und steht als **erster Regelabsteiger** fest."
- **Tie-Break ohne direkten Vergleich** (§ 5 Abs. 4 f.): Tordifferenz, dann
  erzielte Tore, dann Entscheidungsspiel auf neutralem Platz. Das weicht von
  Bayern (RO § 19 Nr. 2: direkter Vergleich als Kriterium 2.4) ab.

> **Hinweis zu einer verbreiteten Falschangabe.** Die deutsche Wikipedia nennt
> für 2026/27 „die letzten zwei" als Regelabsteiger und begründet Erhöhungen mit
> möglichen Drittliga-Abstiegen von *TSV Havelse* und *SV Meppen*. Beide sind
> laut NFV für 2026/27 regulär **in der Regionalliga Nord zugelassen**, also
> keine potenziellen Drittliga-Absteiger; die Angabe beschreibt die Vorsaison.
> Maßgeblich ist § 6 Abs. 3 NFV-SpO mit **drei** Regelabsteigern — wortgleich in
> beiden geprüften Fassungen (Statut 20.09.2025 und Spielordnung 19.03.2026).

### 2.2 Regionalliga Nordost — 18 Mannschaften

Träger: Nordostdeutscher Fußballverband (NOFV). Maßgeblich ist die
**Auf- und Abstiegsregelung Herren 2026/2027** (Stand 22.06.2026), Abschnitt A.

| | Regelung | Beleg |
|---|---|---|
| Sollstärke | 18 Mannschaften | A. Nr. 1 |
| Aufstieg 3. Liga | **Direktaufstieg** (Rotationsplatz 2026/27) | A. Nr. 4; § 55b |
| Absteiger | **1 oder 2**, je nach Drittliga-Abstieg | A. Nr. 5 + Schema |
| Aufsteiger aus den Oberligen | **2** (Platz 1 je Staffel Nord/Süd) | B. Nr. 5 + Schema |

> „Der auf Tabellenplatz eins der Regionalliga einkommende Verein, ist zur
> Teilnahme am Spielbetrieb der 3. Liga des DFB berechtigt." (A. Nr. 4)

**Abstieg.** Die Regelung nennt keine feste Zahl, sondern macht sie ausdrücklich
abhängig „des Abstieges/der Einordnung von Mannschaften des NOFV aus der 3. Liga
in die Regionalliga und des Aufstiegs bzw. des Nichtaufstiegs einer Mannschaft
aus der Regionalliga in die 3. Liga" (A. Nr. 5). Das beigefügte Schema macht das
für 2026/27 explizit — die beiden einzigen vorgesehenen Varianten:

| | Variante A | Variante B |
|---|---:|---:|
| Mannschaften RL 2026/27 | 18 | 18 |
| − Aufsteiger 3. Liga | 1 | 1 |
| **+ Absteiger aus 3. Liga** | **0** | **1** |
| + Aufsteiger aus Oberliga | 2 | 2 |
| **− Absteiger in Oberliga** | **1** (Platz 18) | **2** (Plätze 17 und 18) |
| Mannschaften RL 2027/28 | 18 | 18 |

Nordost ist damit die Staffel mit der **schmalsten** Abstiegszone: ein Absteiger,
zwei nur dann, wenn ein NOFV-Verein aus der 3. Liga herunterkommt. Das Schema
bildet nur 0 oder 1 Drittliga-Absteiger ab; für mehr greift die
Präsidiums-Öffnungsklausel (A. Nr. 7).

Dass das Schema mit nur zwei Varianten auskommt, hat einen konkreten Grund:
**Hansa Rostock ist 2026/27 der einzige Drittligist aus dem NOFV-Gebiet**
(Sekundärquelle). Die Fallunterscheidung A/B ist damit faktisch eine einzige
binäre Variable — steigt Hansa ab, gilt B, sonst A. Auch hier gibt es **keine
Relegation um den Klassenerhalt**; die Absteiger stehen rein nach Tabellenplatz
fest. (Relegationsspiele existieren nur eine Ebene tiefer, Oberliga ↔
Landesverbände, B. Nr. 13.)

Verzichtet ein qualifizierter Verein auf die Teilnahme, wird er nach SpO § 5 (5)
in die Oberliga eingegliedert und „die Anzahl der Absteiger reduziert sich
entsprechend" (A. Nr. 6).

### 2.3 Regionalliga West — 18 Mannschaften

Träger: Westdeutscher Fußballverband (WDFV). Maßgeblich ist die
**Auf- und Abstiegsregelung der Herren-Regionalliga West im Spieljahr 2026/2027**
(§ 16 des Statuts für die Regionalliga West).

| | Regelung | Beleg |
|---|---|---|
| Sollstärke | 18 Mannschaften | Abstieg Nr. 1 |
| Aufstieg 3. Liga | **Direktaufstieg** (fest) | Aufstieg Nr. 1 |
| Absteiger | **4** bei 18 Vereinen | Abstieg Nr. 1 |
| Aufsteiger aus den Oberligen | **4** (FVM 1, FVN 1, FLVW 2) | Aufstieg RL West Nr. 1 |

> „Der Meister ist sportlich unmittelbar für die 3. Liga gemäß § 55 b Nr. 2
> SpO/DFB qualifiziert." (Aufstieg Nr. 1)

> „Am Ende der Spielrunde steigen aus der Regionalliga West bei 18 teilnehmenden
> Vereinen/Mannschaften die **vier** Vereine/Mannschaften mit der geringsten
> Punktezahl und Platzierung in die 5. Spielklassenebene […] gemäß ihrer
> Verbandszugehörigkeit ab." (Abstieg Nr. 1)

**Die Kopplung wirkt hier in der Gegenrichtung.** West nennt eine feste Zahl (vier)
und *vermindert* sie, statt sie zu erhöhen:

- „Steigen weniger als vier Vereine/Mannschaften der 5. Spielklassenebene in die
  Regionalliga West auf, so vermindert sich die Zahl der absteigenden […]
  entsprechend." (Nr. 3)
- Kommt ein Lizenzverein in die 3. Liga, steigt dessen in der RL West spielende
  zweite Mannschaft ab und rückt ans Tabellenende — „Die Anzahl der Absteiger
  verringert sich entsprechend." Ebenso bei Abstieg einer Lizenzmannschaft in
  die RL West (Nr. 4).
- Erhöht sich durch spätere Nichtlizenzierung die Zahl der Absteiger aus höheren
  Ligen, wird die Regionalliga West **aufgestockt** (Nr. 5).

Ein Abstieg aus der 3. Liga führt in West also nicht zu mehr Absteigern, sondern
verdrängt Aufsteiger bzw. wird über die Ligagröße ausgeglichen. Die vier
Absteiger verteilen sich nicht nach Quote, sondern nach der
Verbandszugehörigkeit der sportlich betroffenen Vereine.

Die vier Aufstiegsplätze sind dagegen fest kontingentiert: „bis zu vier
Vereine/Mannschaften (FVM=1; FVN=1; FLVW=2)" (Aufstieg RL West Nr. 1).
Zweite Mannschaften von Drittligisten und dritte Mannschaften von Lizenzvereinen
sind nicht teilnahmeberechtigt (Nr. 3).

### 2.4 Regionalliga SüdWest — Sollstärke 18

Träger: RLSW Regionalliga Südwest GmbH. Maßgeblich ist die
**Spielordnung RLSW** (Stand 01.08.2026), §§ 47–49a.

| | Regelung | Beleg |
|---|---|---|
| Sollstärke | 18 (Normalzahl) | § 47 Nr. 2 |
| Aufstieg 3. Liga | **Direktaufstieg** (fest) | § 49a; § 55b Nr. 2 |
| Absteiger | **mindestens 3**, + je Drittliga-Absteiger | § 47 Nr. 1 |
| Aufsteiger aus den Oberligen | **bis zu 4** | § 48 Nr. 4 |

> „Am Ende der Spielrunde steigen aus der Regionalliga Südwest **mindestens die
> drei** Mannschaften mit der geringsten Punktezahl und Platzierung in die
> nächsttiefere Spielklasse ihres Landes- bzw. Regionalverbandes ab, unabhängig
> von der Regional-/oder Landesverbands-zugehörigkeit. **Die Anzahl der Absteiger
> erhöht sich um die Anzahl an Absteigern aus der 3. Liga in die Regionalliga
> Südwest.**" (§ 47 Nr. 1)

Das ist die **direkteste Formulierung der Abstiegskopplung** in allen fünf
Ordnungen: Absteiger = 3 + (Drittliga-Absteiger nach SüdWest). Gedeckelt ist sie
durch § 47 Nr. 2: „Soweit die Normalzahl von 18 Vereinen nicht überschritten ist,
sind mehr als **fünf** Absteiger im selben Spieljahr ausgeschlossen."

Die Spielordnung enthält dazu ein vollständiges Auf- und Abstiegsschema, das die
Absteigerzahl als Funktion von Ligagröße und Drittliga-Absteigern tabelliert —
für den Simulator die brauchbarste Vorlage aller fünf Staffeln. Auszug für die
Sollstärke 18 (stets 4 Aufsteiger aus den Oberligen, 1 Aufsteiger in die 3. Liga):

| Absteiger aus 3. Liga | 4 | 3 | 2 | 1 | 0 |
|---|---:|---:|---:|---:|---:|
| **Absteiger in die Oberliga** | 5 | 5 | 5 | 4 | 3 |
| Liga im nächsten Spieljahr | 20 | 19 | 18 | 18 | 18 |

Man sieht die Deckelung wirken: Bei 3 oder 4 Drittliga-Absteigern bleibt es bei
fünf Absteigern, und die Liga wächst vorübergehend über 18 — abgebaut wird erst
in den Folgejahren „durch einen verschärften Abstieg" (§ 47 Nr. 2).

**Kein Verteilungsschlüssel auf die Oberligen.** § 47 Nr. 1 sagt ausdrücklich
„unabhängig von der Regional-/oder Landesverbands-zugehörigkeit" — es steigt rein
sportlich ab, und jeder Absteiger fällt in die Oberliga *seines* Verbandes. Wie
viele Absteiger eine einzelne Oberliga aufnimmt, ist damit nicht fixiert.

**Aufstieg in die Liga:** Je ein Meister aus dem baden-württembergischen Bereich,
dem Hessischen FV und dem FRV Südwest (§ 48 Nr. 1), dazu ein vierter Aufsteiger,
der zwischen den Tabellenzweiten dieser drei Staffeln ausgespielt wird
(§ 48 Nr. 4) — laut Verbandsseite in „einer einfachen Punkterunde ‚Jeder gegen
Jeden', wobei jeder Teilnehmer der Aufstiegsspiele ein Heim- und ein
Auswärtsspiel hat". Steigen weniger auf als vorgesehen, vermindert sich die Zahl
der Absteiger entsprechend (§ 47 Nr. 6). Nachrücken ist längstens bis zum
Tabellenvierten möglich (§ 48 Nr. 2 f.).

**Die Formel geht am Ist-Zustand auf.** Die Liga startet 2026/27 mit genau 18
Vereinen: 14 Verbleiber + SSV Ulm 1846 (Absteiger aus der 3. Liga) + 4 Aufsteiger
(VfR Aalen, 1. FC Kaiserslautern II, Eintracht Frankfurt II, VfR Mannheim). Ein
Drittliga-Absteiger bedeutet nach § 47 Nr. 1 im Vorjahr 3 + 1 = **4 Absteiger** —
und genau vier gab es (Bayern Alzenau, Schott Mainz, TSG Balingen, Bahlinger SC).
Die Regel ist damit nicht nur zitiert, sondern an einer echten Saison validiert.

### 2.5 Regionalliga Bayern — 19 Vereine (Sollzahl 18)

Träger: Bayerischer Fußball-Verband (BFV). Maßgeblich sind die
**Regionalligaordnung** (RO, Stand 01.07.2024), §§ 19–21, und die jährliche
**Auf- und Abstiegsregelung RL Bayern 2026/2027** (München, 21.07.2026).

| | Regelung | Beleg |
|---|---|---|
| Teilnehmer 2026/27 | **19 Vereine** (Sollzahl 18) | A&A-Regelung, Vorspann; RO § 1 Nr. 2 |
| Aufstieg 3. Liga | **Aufstiegsspiele** gegen RL Nord | A&A I. Nr. 1 |
| Direktabsteiger | **2** (die beiden letztplatzierten) | A&A II. Nr. 1 |
| Relegation | Plätze **17 und 18** gegen 2 Bayernligisten | A&A II. Nr. 3 |
| Aufsteiger aus den Bayernligen | 2 Relegationsteilnehmer (Nord/Süd) | A&A II. Nr. 3 |

Bayern ist die einzige Staffel, die 2026/27 **über der Sollzahl** spielt (19 statt
18) — und die einzige mit einer **Abstiegsrelegation**.

> „Aus der Regionalliga Bayern steigen in der Saison 2026/2027 grundsätzlich die
> **zwei** letztplatzierten Vereine ab." (II. Nr. 1)

> „Die **zwei** vor den bestplatzierten Festabsteiger stehenden Vereine der
> Regionalliga Bayern spielen mit dem Relegationsteilnehmer der Bayernliga Nord
> und dem Relegationsteilnehmer der Bayernliga Süd die Relegation." (II. Nr. 3)

Der Relegationsmodus hängt an der Sollzahl 18 und ist deshalb für die Modellierung
unangenehm: „Die Relegation besteht grundsätzlich aus **einer Runde**. Wird die
Sollzahl von 18 Mannschaften unterschritten bzw. mit mehr als 18 Mannschaften
überschritten, wird eine **zweite Runde** durchgeführt." (IV.)

- **1. Runde:** Zwei Spiele Bayernligist gegen Regionalligist (Auslosung); die
  beiden Sieger qualifizieren sich für die Regionalliga.
- **2. Runde, Fall 1** (Sollzahl unterschritten): bei 1 freiem Platz spielen die
  beiden Verlierer diesen aus; bei 2 freien Plätzen entfällt die Relegation und
  alle vier Teilnehmer werden eingereiht.
- **2. Runde, Fall 2** (Sollzahl überschritten): die beiden Sieger spielen den
  einzigen freien Platz aus.

Die Kopplung an die 3. Liga steht in der RO: Steigt ein Lizenzverein in die
3. Liga ab, wird dessen in der Regionalliga spielende zweite Mannschaft „nach dem
letzten Spieltag an den letzten Platz der Tabelle gesetzt und gilt als erster
Absteiger" (RO § 2 Nr. 3). Umgekehrt: „Wird nach vollzogenem Auf- und Abstieg die
Sollzahl von 18 Vereinen überschritten, so kann sich die Zahl der Absteiger im
folgenden Spieljahr entsprechend erhöhen." (A&A IV.) — genau der Fall, der in der
laufenden Saison mit 19 Vereinen vorliegt.

Ferner: Die Abstiegsrelegation wird ausgesetzt, solange ein bayerischer
Zweitliga-Lizenzverein in der Abstiegsrelegation der 2. Liga steht (RO § 2 Nr. 3
a. E.; A&A IV. Grundsatz). Die Zahl der Direktabsteiger und Releganten wird nach
RO § 21 Nr. 1 **jährlich vor Saisonbeginn** festgelegt — sie ist keine Konstante
der Ordnung.

---

## 3. Zusammenschau für die Modellierung

### 3.1 Aufstieg

| Staffel | Weg 2026/27 | Plätze |
|---|---|---:|
| Nord | Aufstiegsspiele gegen Bayern | 0 oder 1 |
| Nordost | Direktaufstieg | 1 |
| West | Direktaufstieg | 1 |
| SüdWest | Direktaufstieg | 1 |
| Bayern | Aufstiegsspiele gegen Nord | 0 oder 1 |

Für die Registry heißt das: `promotion_slots = 1` trifft nur für Nordost, West
und SüdWest zu. Nord und Bayern haben `promotion_slots = 0` und
`playoff_slots = 1` — der Meister erreicht die 3. Liga nur über zwei Spiele.

> **Abweichung zum heutigen Code.** `RCode/league_registry.R` setzt derzeit für
> **Nord, Nordost und Bayern** je `playoff_slots = 1` und für alle fünf Staffeln
> `promotion_slots = 1`. Nach § 55b und der BFV-Regelung ist für 2026/27
> Nordost ein Direktaufsteiger (kein Playoff), und Nord/Bayern haben keinen
> Direktplatz. Die Registry bildet damit eher das allgemeine Muster als die
> konkrete Saison ab — das ist beim Aktivieren der Ligen zu korrigieren.
> **Wichtig:** Die Rotation wechselt jährlich, die Zuordnung gehört also an eine
> saisonabhängige Stelle, nicht als Konstante in die Registry.

### 3.2 Abstieg — die Kopplung an die 3. Liga

Alle fünf Staffeln koppeln ihre Absteigerzahl an die Drittliga-Absteiger, aber
in zwei verschiedenen Bauarten:

**Typ „Aufstockung des Abstiegs"** (Absteiger = Basis + Drittliga-Absteiger):

| Staffel | Basis | Kopplung | Deckel |
|---|---:|---|---:|
| **SüdWest** | 3 | + 1 je Drittliga-Absteiger (§ 47 Nr. 1) | 5 |
| **Nordost** | 1 | + 1 je Drittliga-Absteiger (Schema A/B) | Schema bis 2 |
| **Nord** | 3 | + 1, sofern Staffelstärke überschritten (§ 6 Abs. 4) | — |

**Typ „Verminderung"** (feste Zahl, die sich reduziert):

| Staffel | Basis | Kopplung |
|---|---:|---|
| **West** | 4 | Drittliga-Absteiger verdrängen Aufsteiger; Absteigerzahl sinkt (Nr. 3, 4) |
| **Bayern** | 2 + Relegation | Zweitvertretung eines Absteigers gilt als erster Absteiger (RO § 2 Nr. 3) |

Für die Simulation ist der Unterschied wesentlich: Bei SüdWest, Nordost und Nord
verschiebt ein Drittliga-Absteiger die **Abstiegsgrenze nach oben** (mehr Teams
steigen ab); bei West und Bayern bleibt die Grenze, aber ein Platz ist
vorbelegt.

**Nur Bayern kennt eine Abstiegsrelegation.** In den anderen vier Staffeln steht
der Abstieg rein tabellarisch fest — bei Nord erst seit 2024/25, seit die frühere
Oberliga-Relegation gestrichen wurde:

| Staffel | Relegation um den Klassenerhalt |
|---|---|
| Nord | nein (bis 2023/24 ja, § 6 Abs. 7 c a. F.) |
| Nordost | nein |
| West | nein |
| SüdWest | nein |
| **Bayern** | **ja**, Plätze 17/18 gegen zwei Bayernligisten |

Für die Modellierung heißt das: Vier Staffeln lassen sich über einen Schwellwert
abbilden, Bayern braucht eine eigene Behandlung — und zwar eine, deren Rundenzahl
selbst vom Simulationsergebnis abhängt (siehe 2.5).

Die in
[`docs/plans/…`](plans/2026-09-05-ligen-ausbau-regionalliga-frauen.md) (§ 7)
vorgesehene Auszählung `relegation_group_counts` — je Iteration mitschreiben,
wie viele Absteiger auf welche Staffel entfallen — liefert genau die Größe, die
alle fünf Regeln als Eingang brauchen.

### 3.3 Was nicht aus den Ordnungen ableitbar ist

- **Die Rotationsreihenfolge über 2026/27 hinaus.** § 55b Nr. 2 delegiert sie an
  das DFB-Präsidium; es gibt keine in einer Ordnung niedergelegte Jahresfolge.
  Für Folgesaisons muss die Zuordnung neu recherchiert werden.
- **Die Verteilung der vier Drittliga-Absteiger auf die Staffeln.** Sie folgt der
  Stammregion der Vereine, nicht einer Quote — im Modell über die Spalte `Region`
  der TeamList (`staffel_zuordnung.R`).
- **Bayerns Relegationsmodus** hängt von der am Saisonende erreichten Teamzahl ab
  und kann vom Verbands-Spielausschuss modifiziert werden (A&A II. Nr. 4, IV.
  Sonderbestimmung).

### 3.4 Reformdebatte — derzeit ohne Beschluss

Eine Reform der Aufstiegsregelung wird seit Jahren verhandelt, ist aber
**nicht beschlossen**. Der Stand:

| Datum | Ereignis |
|---|---|
| 2019 | DFB-Bundestag beschließt, dass eine Regelung zu finden ist, die allen Meistern den Aufstieg ermöglicht |
| 25.03.2026 | AG Regionalliga-Reform legt zwei Modelle vor („Kompassmodell", „Regionenmodell"), beide mit vier Staffeln und Direktaufstieg aller Meister |
| 20.05.2026 | DFB benennt die Entscheidungsgremien (DFB-Vorstand oder außerordentlicher Bundestag) |
| **30.06.2026** | **Vereinsvotum: beide Modelle abgelehnt** — keines fand in allen Regionen eine Mehrheit |

> „Wir respektieren das Vereinsvotum im Hinblick auf die beiden von der AG
> ausgearbeiteten Modelle." — DFB-Präsident Neuendorf, 30.06.2026

Der DFB hält am Ziel fest („Das Ziel, ein Aufstiegsrecht für die Meister zu
realisieren, bleibt unabhängig vom gestrigen Votum allerdings richtig"), ein
Beschluss und ein Zieldatum existieren jedoch nicht. Parallel meldete der NFV
am 30.06.2026 „Keine bundesweite Lösung für ein gemeinsames Aufstiegsmodell".

**Für 2026/27 — und mangels Beschluss auch für 2027/28 — gilt unverändert der
oben dargestellte Modus.** Die anhaltende Debatte ist gleichwohl ein Grund, die
Aufstiegslogik konfigurierbar statt fest verdrahtet zu halten.

> Vorsicht bei der Recherche: Es kursieren Darstellungen, die „vier
> Direktaufsteiger ab 2028/29" als feststehend behaupten. Nach dem
> DFB-Statement vom 30.06.2026 ist das nicht der Fall.

---

## 4. Quellen

Alle Primärquellen wurden im Volltext ausgewertet (Abruf: 2026-09-06).

### Amtlich (Verbandsdokumente)

| # | Dokument | Stand | URL |
|---|---|---|---|
| Q1 | **DFB-Spielordnung**, § 55b „Aufstieg in die 3. Liga", S. 96 f. | 28.11.2025, gültig ab 01.07.2026 | https://assets.dfb.de/uploads/000/328/557/original_Heft_04_Spielordnung_Schiedsrichterordnung_20251128.pdf |
| Q2 | **BFV, Auf- und Abstiegsregelung der Regionalliga Bayern — Spieljahr 2026/2027** | 21.07.2026 | https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/amtliches/spielausschuss/auf--und-abstiegsregelung-regionalliga-bayern-2026_2027.pdf |
| Q3 | **BFV, Regionalligaordnung (RO)**, Anlage A — §§ 1, 2, 19, 20, 21 | 01.07.2024 | https://www.bfv.de/binaries/content/assets/inhalt/spielbetrieb-verbandsleben/ligabetrieb/zulassungsvoraussetzungen-2024_25/anlage-a_regionalligaordnung_gultig-ab-01.07.2024.pdf |
| Q4 | **NOFV, Herren-Spielklassen: Auf- und Abstiegsregelungen 2026/2027** inkl. schematischer Darstellung | 22.06.2026 | https://www.nofv-online.de/files/Inhalt/Aktuelles/2026_Q2/260626_Herren_Auf-und%20Abstiegsregelung%202026-27_final.pdf |
| Q5 | **WDFV, Auf- und Abstiegsregelung der Herren-Regionalliga West im Spieljahr 2026/2027** (§ 16 Statut RL West) | 2026 | https://wdfv.de/download/herren-regionalliga-west/herren-regionalliga-west-auf-und-abstiegsregelung-fuer-die-saison-20262027.pdf |
| Q6 | **RLSW, Spielordnung der Regionalliga Südwest**, §§ 47–49a inkl. Auf-/Abstiegsschema | 01.08.2026 | https://res.cloudinary.com/rlsw/image/upload/v1785911302/Spielordnung_RLSW_Stand_Stand_01.08.26_pxvhrg.pdf |
| Q7 | **NFV, Spielordnung**, § 6 „Staffelstärke, Auf- und Abstieg"; Anhang 1 „Regionalliga-Statut – Herren –", Ziff. 1.3 | 19.03.2026 | https://www.nordfv.de/fileadmin/Statuten/260319_Spielordnung_NFV_V2.pdf |
| Q8 | **NFV, Durchführungsbestimmungen für die Aufstiegsrunde zur Regionalliga Nord 2026/2027** | 05.05.2026 | https://www.nordfv.de/fileadmin/Spielbetrieb_Herren/260505_NordFV_Ausschreibung-Aufstiegsrunde_2025-2026_FINAL_2.pdf |
| Q9 | **DFB-FAQ „Aufstieg von Regionalliga zur 3. Liga"** — Dauerplätze West/SüdWest, Rotation, Geltung ab 2020/21 | 05.06.2023 | https://www.dfb.de/news/detail/aufstieg-von-regionalliga-zur-3-liga-fragen-und-antworten-208044 |
| Q10 | **DFB-Statement zur Regionalliga-Reform** — Vereinsvotum, Ablehnung beider Modelle | 30.06.2026 | https://www.dfb.de/news/dfb-statement-zur-regionalliga-reform |
| Q11 | DFB, „AG Regionalliga-Reform legt zwei Lösungsvorschläge vor" | 25.03.2026 | https://www.dfb.de/news/ag-regionalliga-reform-legt-zwei-loesungsvorschlaege-vor |
| Q12 | NFV, Regionalliga-Statut (ältere Fassung; § 6 zur Absteigerzahl wortgleich mit Q7 — gegengeprüft) | 20.09.2025 | https://www.nordfv.de/fileadmin/Statuten/250920_Regionalliga-Statut.pdf |
| Q13 | RLSW, Modus der Aufstiegsspiele der Oberliga-Zweiten | laufend | https://www.regionalliga-suedwest.de/Spielbetrieb/Aufstiegsspiele/ |
| Q14 | NOFV, Übersicht Auf-/Abstiegsregelungen und Durchführungsbestimmungen (Einstieg zu Q4) | laufend | https://www.nofv-online.de/index.php/durchfuehrungsbestimmungen.html |
| Q15 | RLSW, Statut-Übersicht (Einstieg zu Q6) | laufend | https://www.regionalliga-suedwest.de/Statut/ |
| Q16 | NFV, Regularien Herren-Regionalliga Nord (Einstieg zu Q7/Q8) | laufend | https://www.nordfv.de/spielbetrieb/ligen/herren-regionalliga-nord/regularien |

### Sekundärquellen (nur für Kontext, nicht für Regelaussagen)

| # | Quelle | Verwendung |
|---|---|---|
| S1 | Sportschau, „DFB bekennt sich und nennt Entscheidungsgremien zur Aufstiegsreform", 20.05.2026 — https://www.sportschau.de/regional/mdr/mdr-dfb-bekennt-sich-und-nennt-entscheidungsgremien-zur-aufstiegsreform-102.html | Abschnitt 3.4 (Reform ab frühestens 2027/28) |
| S2 | NFV-News, „Keine bundesweite Lösung für ein gemeinsames Aufstiegsmodell", 30.06.2026 — https://www.nordfv.de/spielbetrieb/ligen/herren-regionalliga-nord/news/ | Abschnitt 3.4 |
| S3 | NFV-News, „Regionalliga Nord der Herren 2026/2027" (Zulassungsentscheide, u. a. Havelse/Meppen) — https://www.nordfv.de/news/regionalliga-nord-der-herren-2026-2027-1 | Richtigstellung in 2.1 |
| S4 | diefalsche9.de, Teilnehmerlisten RL SüdWest / Nord 2026/27 | Ist-Zustand-Validierung in 2.4 (18 Vereine, Auf-/Absteiger namentlich) |
| S5 | Wikipedia (de), „Fußball-Regionalliga 2026/27" — Zuordnung Direktaufsteiger/Playoff | Gegenprobe zu Q1+Q2 in Abschnitt 1 |
| S6 | Hansa Rostock als einziger NOFV-Drittligist 2026/27 | Auslöser für Szenario A/B in 2.2 |
| S7 | Wikipedia (de), „Fußball-Regionalliga Nord 2026/27" | **Als fehlerhaft markiert** (Absteigerzahl Nord); nicht verwendet |
| S8 | Wikipedia (en), „Promotion to the 3. Liga" | **Als fehlerhaft markiert** (Rotation 2026/27); nicht verwendet |

### Nicht verwendet

Die unter `media.dfl.de` gespiegelte DFB-Spielordnung
(`https://media.dfl.de/sites/2/2018/11/DFB-Spielordnung.pdf`) enthält eine
**veraltete** Fassung des § 55b (drei Aufsteiger, alle sechs Teilnehmer in einer
Aufstiegsrunde — Stand vor 2018). Sie wurde verworfen; maßgeblich ist Q1.

---

## Verifikation

Der Kernbefund dieses Dokuments — Rotationszuordnung 2026/27 — ist durch zwei
unabhängige amtliche Quellen gestützt: § 55b DFB-SpO (Q1) legt die Struktur fest
(West/SüdWest fest, dritter Platz rotierend, zwei Verbleibende im Playoff), die
BFV-Regelung (Q2) benennt die konkrete Paarung Bayern–Nord für 2026/2027. Daraus
folgt Nordost als dritter Direktaufsteiger zwingend. Zwei Sekundärquellen, die
dem widersprechen, sind oben ausdrücklich als fehlerhaft gekennzeichnet.

Nicht abschließend belegt ist der **Präsidiumsbeschluss** selbst, der die
Rotationsreihenfolge festlegt; er ist in keiner der eingesehenen Ordnungen
veröffentlicht. Die Zuordnung 2026/27 steht dadurch nicht in Frage — sie folgt
aus Q1 und Q2 —, wohl aber die Reihenfolge künftiger Saisons.
