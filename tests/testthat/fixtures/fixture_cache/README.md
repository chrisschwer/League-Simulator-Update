# Eingefrorene Spielpläne der Regionalligen (83–87, Saisons 2019–2025)

Kopie der Dateien `8[3-7]_<saison>.json` aus dem Offline-Cache `data/fixture_cache/`
(`RCode/fixture_cache.R`), Stand 25.09.2026. Alle Saisons sind abgeschlossen; die
Dateien ändern sich nicht mehr.

**Warum hier und nicht in `data/`:** `data/fixture_cache/` ist nach ADR 0002 ein
gitignorter Offline-Cache, kein Teil des Produktivpfads. Die CI bindet nur `tests/`
und `scripts/` in den Container ein. Solange die Tests den Cache lasen, skippten sie
in der CI still, und ein Bruch durch #233 blieb unbemerkt (#211, Phase 0.1).

**Wer liest sie:** `test-rl-verdrahtung.R` (`84_2025.json`) und
`test-phase5-regionalligen.R` (Rundenfilter, Teamspannen je Saison seit 2019).

**Format:** flach, eine Zeile je Spiel (`fixture_id`, `fixture_date`, `round`,
`teams_home_id`, `teams_away_id`, `teams_home_name`, `teams_away_name`,
`goals_home`, `goals_away`, `fixture_status_short`). Keine Zugangsdaten.

`83_2020.json` fehlt absichtlich: Die Regionalliga Bayern hat die Saison 2020/21
nicht ausgetragen.

**Erneuern** (nur wenn ein Test eine neue Saison braucht): Datei aus
`data/fixture_cache/` hierher kopieren, die Tests laufen lassen und die geänderten
Erwartungen im PR begründen.
