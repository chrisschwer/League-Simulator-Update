# Empirie-Report: zehn Ligen, Saisons 2024 + 2025

Erhoben am 2026-09-05 mit `scripts/analyze_league_empirics.R`
(beendete Hauptrundenspiele, Relegations- und Playoff-Partien ausgeschlossen).

Dieser Report macht die Zahlen des Ligen-Ausbauplans erstmals reproduzierbar —
sie waren bis dahin ad hoc erhoben, ohne Skript und ohne Datenbasis im Repo.

## Messung

| Liga | Spiele | Tore/Spiel | Heim% | Remis% | Ausw% | impl. HA |
|---|---:|---:|---:|---:|---:|---:|
| Bundesliga | 612 | 3,18 | 41,2 | **25,0** | 33,8 | 26 |
| 2. Bundesliga | 612 | 2,98 | 43,3 | **26,1** | 30,6 | 45 |
| 3. Liga | 760 | 3,06 | 45,7 | 24,3 | 30,0 | 55 |
| Frauen-Bundesliga | 314 | 3,31 | 45,5 | **15,9** | 38,5 | 24 |
| 2. Frauen-Bundesliga | 365 | 3,30 | 42,7 | **17,5** | 39,7 | 10 |
| RL Bayern | 611 | 3,02 | 40,6 | 25,4 | 34,0 | 23 |
| RL Nord | 612 | 3,41 | 42,2 | 22,4 | 35,5 | 23 |
| RL Nordost | 612 | 2,89 | 43,6 | 24,7 | 31,7 | 42 |
| RL SüdWest | 612 | 3,24 | 42,3 | 22,5 | 35,1 | 25 |
| RL West | 598 | 3,11 | 38,6 | 25,3 | 36,1 | 9 |

`impl. HA` ist der Heimvorteil auf der **ELO-Erwartungsskala** (Umkehrung des
Heim-Score-Anteils). Er ist *nicht* mit dem Heimvorteil des Tormodells (40)
vergleichbar — andere Skala, anderer Wirkungspfad.

## Der Ausbauplan wird bestätigt

Alle fünf im Plan gemessenen Ligen stimmen exakt überein (Spielzahl,
Tore/Spiel und Remisquote auf die angegebene Stelle). Die ad-hoc-Erhebung
war korrekt.

## Nötige ELO-Streuung je Liga

Bei festem `tore_intercept` = 1,32184 und Heimvorteil 40 liegt die
**Poisson-Obergrenze der Remisquote bei 26,14 %** — gleich starke Teams,
kein Heimvorteil. Jede ELO-Streuung senkt die Quote von dort aus; nach oben
ist nichts erreichbar. Daraus ergibt sich je Liga die Streuung, die zur
beobachteten Remisquote passt:

| Liga | Remis% | nötige SD |
|---|---:|---:|
| Frauen-Bundesliga | 15,9 | **458** |
| 2. Frauen-Bundesliga | 17,5 | **384** |
| RL Nord | 22,4 | 207 |
| RL SüdWest | 22,5 | 203 |
| 3. Liga | 24,3 | 132 |
| RL Nordost | 24,7 | 112 |
| Bundesliga | 25,0 | 99 |
| RL West | 25,3 | 81 |
| RL Bayern | 25,4 | 75 |
| 2. Bundesliga | 26,1 | *nicht erreichbar* |

Zum Vergleich: Die tatsächliche Streuung der Bundesliga liegt bei SD ≈ 145
(gemessen aus `TeamList_2026.csv`), die der 2. Bundesliga bei ≈ 59.

## Zwei Befunde

**1. Der Frauen-Befund des Ausbauplans trägt.** Die beiden Frauen-Ligen
brauchen mit 384–458 etwa das Dreifache der Bundesliga-Streuung. Das ist
plausibel für Ligen mit sehr grossen Qualitätsunterschieden und bestätigt
die Ausgangsvermutung: Ursache der niedrigen Remisquote ist die
ELO-Spreizung, nicht das Torniveau.

**2. Die 2. Bundesliga ist mit diesem Modell nicht darstellbar.** Ihre
Remisquote von 26,1 % liegt praktisch auf der Obergrenze von 26,14 %; sie
wäre nur mit einer Streuung nahe null erreichbar, während die Liga real
SD ≈ 59 hat. Das ist keine Frage der Kalibrierung, sondern die strukturelle
Grenze des unabhängigen Poisson-Modells: Reale Spielstände sind korreliert,
das Modell nimmt Unabhängigkeit an.

Betroffen ist damit eine **Altliga**, nicht eine der neuen — der Befund
ändert nichts an diesem Vorhaben, gehört aber zum Projekt „Prognosequalität"
(Sommer 2027), zusammen mit dem zu niedrigen Torniveau
(Intercept 1,32184 impliziert 2,64 Tore/Spiel gegen gemessene 3,18 in der BL)
und der Frage nach einem korrelierten Tormodell (z. B. Dixon-Coles).

## Nachtrag: Die Streuung ist kein freier Parameter

Der ursprüngliche Plan sah vor, die ELO-Streuung gegen die beobachtete
Remisquote zu eichen. Das ist nicht möglich — die Streuung ist ein
**Gleichgewicht des ELO-Walks**, kein einstellbarer Wert.

Gegenprobe an RL Nord (Saison 2025), Start mit künstlich aufgeprägter
Streuung:

| Start-SD | nach einer Saison |
|---:|---:|
| 0 | 100 |
| 100 | 94 |
| 200 | 99 |
| 300 | 125 |
| 400 | 181 |

Es gibt einen starken Attraktor bei SD ≈ 95–100. Grosse Streuungen werden
aktiv abgebaut, weil ELO selbstkorrigierend ist: Ein Team, das 400 Punkte
über dem Feld steht, *soll* gewinnen — Siege bringen ihm fast nichts,
Niederlagen kosten viel. Der k-Faktor 20 begrenzt bei ~34 Spielen pro
Saison, wie weit sich Bewertungen trennen können. Auch sieben Saisons
Historie ändern daran nichts (RL Nord schwankt zwischen SD 76 und 111).

Die Frauen-Bundesliga verhält sich anders und bestätigt die Ausgangs-
vermutung: Ihre Streuung wächst über zehn Saisons von 113 auf ~240 und
bleibt dort. Die Liga ist also tatsächlich ungleicher als die Männerligen —
sie erreicht nur nicht die 458, die das Poisson-Modell für 15,9 % Remis
bräuchte.

Daraus folgt für die Kalibrierung:

| Liga | SD (Walk) | Remis Modell | Remis real | Lücke |
|---|---:|---:|---:|---:|
| Frauen-BL | 257 | 21,2 % | 15,9 % | +5,3 pp |
| RL Nord | 129 | 24,5 % | 22,4 % | +2,1 pp |
| Bundesliga | 145 | 24,2 % | 25,0 % | −0,8 pp |

**Entschieden: Die Lücke bleibt stehen und wird dokumentiert.** Ein
nachträgliches Strecken der Frauen-ELOs auf SD 458 würde die Remisquote
treffen, aber die Werte hätten dann nicht mehr die Bedeutung, die der Walk
ihnen gibt — und der Auf-/Abstieg zwischen den beiden Frauen-Ligen würde
verzerrt. Die eigentliche Ursache liegt im Tormodell, nicht in der
Kalibrierung.

## Reproduktion

```bash
Rscript scripts/analyze_league_empirics.R --seasons 2024,2025
```

Fixtures werden unter `data/fixture_cache/` zwischengespeichert
(gitignored); `--refresh` erzwingt einen Neuabruf.
