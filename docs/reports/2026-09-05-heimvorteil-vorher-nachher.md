# Heimvorteil 65 -> 40: Wirkung auf die veröffentlichten Prognosen

Erhoben am 2026-09-05 gegen die Spieldaten der laufenden Saison 2026/27
(Bundesliga 10, 2. Bundesliga 29, 3. Liga 31 beendete Spiele).
Je Variante 30.000 Simulationen auf identischen Eingabedaten.

```
Vorher-Nachher: Heimvorteil 65 -> 40 ELO
30.000 Simulationen je Variante, gleiche Spieldaten (Saison 2026, Stand heute)

--- Bundesliga (18 Teams) ---
Team     Meister 65  Meister 40      Δ    Abstieg 65 Abstieg 40      Δ
FCB           82.3%       82.0%   -0.4          0.0%       0.0%   +0.0
BVB            9.3%        9.3%   +0.1          0.1%       0.1%   -0.0
RBL            2.6%        2.9%   +0.2          0.6%       0.6%   -0.0
STU            2.2%        2.2%   -0.0          0.7%       0.6%   -0.1
B04            2.1%        2.2%   +0.1          0.8%       0.7%   -0.1
SCF            0.5%        0.5%   -0.0          3.9%       3.6%   -0.3
  ...
S04            0.0%        0.0%   -0.0         61.3%      62.0%   +0.7
SCP            0.0%        0.0%   +0.0         48.5%      48.0%   -0.5
ELV            0.0%        0.0%   +0.0         36.7%      36.6%   -0.2
KOE            0.0%        0.0%   -0.0         28.9%      28.8%   -0.1
  max |Δ| Meister: 0.4 pp | max |Δ| Abstieg: 0.7 pp

--- 2. Bundesliga (18 Teams) ---
Team     Meister 65  Meister 40      Δ    Abstieg 65 Abstieg 40      Δ
WOB           62.3%       61.3%   -1.0          0.2%       0.2%   +0.0
HDH           28.7%       28.2%   -0.6          1.6%       1.7%   +0.1
BSC           26.9%       26.3%   -0.6          1.9%       1.8%   -0.1
FCN           21.3%       21.7%   +0.4          2.5%       2.5%   +0.0
H96           10.4%       10.5%   +0.1          6.5%       6.6%   +0.1
FCK           10.1%       10.2%   +0.2          7.3%       7.3%   +0.1
  ...
FCE            0.4%        0.5%   +0.1         51.1%      50.8%   -0.3
OSN            1.1%        1.2%   +0.2         34.4%      34.8%   +0.5
EBS            1.4%        1.6%   +0.2         30.5%      30.9%   +0.3
SGF            1.9%        1.9%   +0.1         27.5%      27.6%   +0.1
  max |Δ| Meister: 1.0 pp | max |Δ| Abstieg: 0.7 pp

--- 3. Liga (20 Teams) ---
Team    Aufstieg 65 Aufstieg 40      Δ    Abstieg 65 Abstieg 40      Δ
ROS           39.0%       38.5%   -0.5          0.4%       0.3%   -0.0
MSV           32.2%       32.4%   +0.2          0.5%       0.6%   +0.1
F95           27.7%       27.6%   -0.1          0.9%       0.8%   -0.1
AAC           23.8%       24.2%   +0.4          0.8%       1.0%   +0.1
PMS           18.8%       18.7%   -0.1          1.5%       1.6%   +0.0
RWE           13.5%       13.4%   -0.1          2.8%       2.6%   -0.1
  ...
ST2            0.0%        0.0%   +0.0        100.0%     100.0%   +0.0
HO2            0.0%        0.0%   +0.0        100.0%      99.9%   -0.0
SG             0.3%        0.4%   +0.1         39.1%      38.2%   -0.9
HAV            0.5%        0.7%   +0.1         32.7%      31.9%   -0.8
  max |Δ| Aufstieg: 0.5 pp | max |Δ| Abstieg: 0.9 pp

```

## Einordnung

Die Saisonprognosen verschieben sich durchweg um **weniger als 1 Prozentpunkt**
(Maximum: 1,0 pp bei der Meisterwahrscheinlichkeit des VfL Wolfsburg in der
2. Bundesliga). Der Grund ist der frühe Saisonzeitpunkt: Jedes Team hat bisher
etwa gleich viele Heim- und Auswärtsspiele bestritten, sodass sich ein zu hoch
angesetzter Heimvorteil in der Tabelle weitgehend heraushebt. Die Verzerrung
wächst erst im Saisonverlauf — deshalb ist jetzt der günstigste Zeitpunkt für
die Korrektur.

Deutlicher wirkt die Änderung auf **Einzelspielprognosen**, wo der Heimvorteil
unmittelbar eingeht und sich nicht über 34 Spieltage ausmittelt. Beispiel aus
der Methodik-Seite (Bayern 2057 gegen Stuttgart 1805):

| | Torerwartung | Sieg Heim | Remis | Sieg Auswärts |
|---|---|---|---|---|
| HA = 65 | 1,9 : 0,8 | 64 % | 21 % | 14 % |
| HA = 40 | 1,8 : 0,8 | 62 % | 22 % | 16 % |

Ligaweit wandern rund 0,14 Tore pro Spiel von der Heim- auf die Auswärtsseite.
