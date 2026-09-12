---
status: accepted
date: 2026-09-12
---
# Die TeamList ist ein gepflegtes Stammdatenblatt, und der Saisonwechsel läuft in zwei Phasen

Bis September 2026 galt: Der Saisonwechsel erzeugt die TeamList. So stand es im
Glossar, so ist der Code gebaut, und für 56 Teams in drei Ligen trug das. Seit
dem Ligen-Ausbau trägt es nicht mehr — und zwar nicht, weil jemand die
Entscheidung geändert hätte, sondern weil die Praxis sie stillschweigend
überholt hat.

Drei Belege aus derselben Saison:

- Die Kürzel 2026/27 stammen aus einer Handrecherche nach DFL-Konvention
  (PR #186, 101 von 175 aktiven Teams). Nicht aus `get_team_short_name()`.
- Die sieben neuen Ligen wurden von Hand eingetragen (Commit 6bcb64b), nie von
  einem Transition-Lauf.
- Der letzte tatsächliche Lauf (Juli 2026) erzeugte ein Format, das es seit
  September 2026 nicht mehr gibt: vier Spalten gegen heute sieben.

Der Saisonwechsel **kann** die produktive TeamList also gar nicht mehr
schreiben. `csv_generation.R` selektiert `TeamID, ShortText, Promotion,
InitialELO`; `League`, `Region` und `Name` fielen weg — und mit `Region` die
gesamte Abstiegskopplung der Regionalligen ([ADR 0006](0006-abstiegskopplung-der-regionalligen.md)),
weil `rl_group_of_team()` ohne sie `NULL` liefert und der Loop die RL-Spalten
stillschweigend überspringt. Im `--non-interactive`-Modus geschähe das ohne
Rückfrage: `confirm_overwrite()` gibt dort immer `TRUE` zurück.

## Die Entscheidung

**Die TeamList ist gepflegte Stammdaten.** Über Kurznamen und
Zweitvertretungs-Status entscheidet der Betreiber; der Saisonwechsel schreibt
fort und schlägt vor.

Das ist keine Kapitulation vor der Automatisierung, sondern folgt aus der Sache.
Ein Kürzel ist eine Frage der Vereinsidentität, nicht der Zeichenkette: Kickers
Offenbach heißt OFC und nicht KIC, Würzburg FWK und nicht WUE. Das lässt sich
aus dem Namen nicht ableiten — genau deshalb wurde PR #186 von Hand gemacht,
gestützt auf DFL-Codes, BR24, MDR und Vereins-Hashtags. Eine Heuristik, die das
nachbauen wollte, müsste die Recherche enthalten.

## Zwei Phasen statt eines Durchlaufs

Daraus folgt der Ablauf. **Phase 1 läuft automatisch** und leistet das, was
maschinell zu leisten ist:

1. Neuberechnung der Start-ELOs aus der Vorsaison
2. Benennung der Konflikte, die durch geänderte Ligazugehörigkeit entstehen
3. Vorschläge für Neuzugänge — Kürzel, ELO, Zweitvertretungs-Status

Sie schreibt einen **Entwurf** (`TeamList_<Jahr>_entwurf.csv`), nicht die
produktive Datei. **Phase 2 ist die Nacharbeit von Hand**; erst dadurch entsteht
`TeamList_<Jahr>.csv`.

Die Trennung ist der Punkt: Ein Entwurf kann nicht versehentlich simuliert
werden, weil der Produktivpfad ihn gar nicht liest. Die Alternative — eine
fertige Datei mit Sperrvermerk — verlässt sich darauf, dass die Sperre überall
greift, wo gelesen wird.

Der **Konfliktbericht** ist dabei kein Beiwerk, sondern das tragende Stück. Er
nennt vier Dinge:

- Kürzel, die nicht aus der Vorsaison übernommen wurden
- **Kollisionen nach Ligawechsel** — der Kernfall: Steigt ein Team auf oder ab,
  trifft sein Kürzel auf die neue Liga und kann dort belegt sein. In PR #186
  traf es Waldhof Mannheim, das `SVW` trug — den Code von Werder Bremen.
- geratenen Zweitvertretungs-Status
- die Ligazuordnung neuer Teams

Er landet als Datei neben der TeamList, nicht im Log: Der Lauf findet einmal im
Juli statt, und bis zur Nacharbeit wäre eine Terminalausgabe weggescrollt.

## Was der Lauf nicht mehr tun darf

Zwei heutige Verhaltensweisen widersprechen dem und fallen weg.

`merge_league_files()` dedupliziert die zusammengeführte Liste über **alle**
Ligen und ersetzt jedes zweite Vorkommen durch ein Kunstkürzel (`FC1`, `VF1`).
Einzige Spur ist eine `cat`-Zeile. Beim Lauf 2027 träfe das rund vierzig
absichtlich gleiche Kürzel — und der Lauf meldete Erfolg. Künftig gilt die Regel
des Loaders (eindeutig je Liga, plus die Ausnahme zwischen Nord, Nordost und
Bayern), und eine Kollision *innerhalb* einer Liga wird gemeldet, nicht
umbenannt.

Die Formatregel `^[A-Z0-9]{2,3}$` lehnt vierstellige Kürzel ab (`SCPM`, `VFBO`,
`HO2A`). Dieser laute Fehler schützt heute zufällig vor der stillen Umbenennung;
wer nur das Format lockert, öffnet sie. Beides gehört deshalb in denselben
Schritt.

## Folgen

Der Juli-Lauf braucht künftig zwingend einen Menschen. Das ist der Preis, und er
ist bewusst gewählt: Die Alternative war ein Lauf, der bei jedem Neuzugang still
etwas erfindet — und genau so sind `STUA`, `ROSA` und `WACA` entstanden, die
über ein Jahr auf der Seite standen, bis sie jemandem auffielen.

Ein echter Transition-Lauf ist erst im Juli 2027 möglich. Der Snapshot-Test
(`tests/testthat/fixtures/season-transition-2024-to-2025/`) ist bis dahin das
einzige Rückgrat; er muss auf das Siebenspalten-Format gezogen werden.
