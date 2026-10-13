# Handbuch League Simulator

LaTeX-Quelle des Handbuchs zu Methodik, Website und Technik.

## Bauen

```bash
cd docs/handbuch
latexmk league-simulator-handbuch.tex   # schreibt build/league-simulator-handbuch.pdf
```

Benötigt TeX Live mit LuaLaTeX und den Schriften Source Serif Pro, Inter,
Source Code Pro und STIX Two Math, die in TeX Live enthalten sind.

## Aufbau

- `league-simulator-handbuch.tex` enthält Präambel und Titelseite und bindet die Kapitel ein.
- `kapitel/00–06` ist Teil I, die Methodik mit allen Formeln, so wie der Code sie rechnet.
- `kapitel/07–10` ist Teil II, die Website mit Seiten, Elementen und Gestaltung.
- `kapitel/11–14` ist Teil III, die Technik mit Architektur, Scheduler, Rust-Server und Betrieb.
- `kapitel/15-anhang.tex` enthält Formelübersicht, Ligen, Begriffe und Quelldateien.
- `bilder/` enthält Screenshots der Live-Seite. Fehlt ein Bild, setzt `\screenshot` einen Platzhalter.

## Pflege

Formeln und Konstanten sind mit `Datei:Zeile` auf den Stand auf der Titelseite
belegt. Ändert sich das Modell im Rust-Server (`league-simulator-rust/src/`),
müssen Teil I und die Formelübersicht im Anhang mitgezogen werden.
