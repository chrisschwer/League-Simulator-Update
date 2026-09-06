# Tormodell der Frauen-Ligen: slope und intercept neu geschätzt

Erhoben am 2026-09-05 auf 1917 Spielen beider Frauen-Ligen
(Frauen-BL 2016–2025, 2. Frauen-BL 2023–2025), gegen die in Phase 4
kalibrierten ELO-Werte.

## Warum das zulässig ist

`tore_slope` und `tore_intercept` dürfen sich nur zwischen Ligen
unterscheiden, die **keine Mannschaften austauschen**. ELO ist das
Einzige, was ein Team über eine Ligagrenze mitnimmt; nur bei gleichem
Tormodell bedeutet ein ELO-Wert auf beiden Seiten dasselbe.

Die beiden Frauen-Ligen bilden eine solche Wechselgemeinschaft: Sie
tauschen Teams untereinander aus (5 Aufsteiger, 2 Absteiger in den
betrachteten Saisons), aber nie mit den Herren. Ein eigenes Tormodell für
diese Familie ist deshalb unbedenklich — für die acht Herren-Ligen bleibt
alles unverändert.

## Ergebnis

| | slope | intercept | Tore | Remis | Heim |
|---|---:|---:|---:|---:|---:|
| beobachtet | – | – | 3,306 | 16,2 % | 45,5 % |
| heute (Herren-Parameter) | 0,0017855 | 1,3218 | 2,644 | 23,7 % | 41,2 % |
| **ML-Fit (empfohlen)** | **0,0024059** | **1,6528** | **3,306** | **19,9 %** | **43,5 %** |

Bootstrap (200 Ziehungen): slope [0,00215; 0,00251],
intercept [1,609; 1,693]. Beide Hälften des Zeitraums liefern konsistente
Werte (slope 0,00256 bzw. 0,00209).

## Der Heimvorteil bleibt bei 40

Heimvorteil und slope wirken beide im Term `(Δ + HA) · slope` und sind
teilweise austauschbar — sie dürfen daher nicht einzeln geschätzt werden.
Der gemeinsame Fit über alle drei Parameter bevorzugt HA ≈ 28
(slope 0,002247), verbessert die Likelihood aber nur um 0,72:

Likelihood-Ratio-Test: LR = 1,43, p = 0,23 — **nicht signifikant**.

Die Profil-Likelihood ist zwischen HA 25 und 50 praktisch flach; die
Daten können 28 und 40 nicht trennen. Im End-to-End-Test schneidet
HA = 40 sogar **besser** ab als HA = 28 (Brier 0,4933 vs 0,4978).
Entschieden: **HA bleibt 40**, eine Abweichung wäre nicht belegt.

## End-to-End-Test durch die Engine

1917 Spiele durch `POST /league-details`, ex-ante-Prognose gegen das
tatsächliche Ergebnis:

| Parameter | Brier | LogLoss |
|---|---:|---:|
| heute | 0,5083 | 0,8710 |
| ML-Fit, HA = 40 | **0,4933** (−2,96 %) | **0,8478** (−2,66 %) |
| ML-Fit, HA = 28 | 0,4978 (−2,08 %) | 0,8556 (−1,76 %) |

**Out-of-sample** (auf früheren Saisons geschätzt, auf der jeweils
nächsten getestet, 1257 Spiele):

| Test-Saison | Brier heute | Brier ML-Fit |
|---|---:|---:|
| 2021 | 0,4724 | 0,4500 |
| 2022 | 0,4830 | 0,4707 |
| 2023 | 0,5785 | 0,5755 |
| 2024 | 0,5543 | 0,5437 |
| 2025 | 0,5653 | 0,5605 |
| **gewichtet** | **0,5475** | **0,5390** (−1,54 %) |

Der ML-Fit ist in **jeder** Testsaison besser. Die Schätzung stabilisiert
sich mit wachsender Historie (slope 0,00362 → 0,00248).

## Was offen bleibt

Die Remisquote bleibt 3,7 Prozentpunkte zu hoch (19,9 % gegen 16,2 %).
Das ist mit diesen zwei Parametern nicht zu schließen:

- Die Remisquote exakt zu treffen erfordert slope ≈ 0,0060 — das liegt
  weit ausserhalb des Bootstrap-Intervalls und triebe die Heimsiegquote
  auf 49,1 % (beobachtet 45,5 %).
- Die Ursache ist die Verteilungsform, nicht die Parameterlage: Die
  beobachtete Tordifferenz hat eine dünnere Mitte und fettere Ränder als
  das Modell (0-Differenz 16,2 % gegen 20,4 %; ±3 Tore 7,1 % gegen
  5,3 %). Die Überdispersion der Gesamttore beträgt 1,20 — Poisson
  erwartet 1,00.

Ein korreliertes Tormodell (Dixon-Coles) setzt genau dort an und gehört
zum Projekt „Prognosequalität" (Sommer 2027).

## Reproduktion

Die Schätzung setzt die kalibrierten ELO-Werte aus
`scripts/calibrate_historical_elo.R` voraus sowie einen laufenden
Rust-Server. Der ELO-Verlauf je Spiel stammt aus dem Saisonstart-Stand
(Drift innerhalb der Saison bleibt unberücksichtigt).
