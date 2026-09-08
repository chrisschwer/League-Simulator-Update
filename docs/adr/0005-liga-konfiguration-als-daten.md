---
status: accepted
date: 2026-09-08
---
# Liga-Eigenschaften stehen als Daten in einer Registry, nicht als Literale im Code

Bis zum Ligen-Ausbau kannte der Code drei Ligen, und er kannte sie als Zeichenketten: `"78"`, `"79"`, `"80"` standen an rund sechzig Stellen in `RCode/` und `scripts/` — als Ligamengen, als dreifach duplizierte Namens-Map, als Teamzahl-Erwartung, als Auf- und Abstiegsregel, sogar in einem Dateinamen-Regex. Für drei Ligen war das lesbar. Für zehn wäre jede neue Liga ein Nachtrag an sechzig Stellen gewesen, und eine vergessene fällt nicht auf: Die Liga verschwindet dann nur aus einer Ligamenge, ohne dass etwas fehlschlägt.

Entschieden: Alles, was eine Liga ausmacht, steht als Daten an einer Stelle — `league_registry()` in `RCode/league_registry.R`. Je Liga ein Eintrag mit API-ID, Wechselgemeinschaft, Slug, Navigationsbeschriftung und -gruppe, Anzeigename, Teamzahl-**Spanne**, erster verfügbarer Saison, Auf-/Abstiegszielen und Platzzahlen. Die Verbraucher fragen über schmale Helfer (`league_ids()`, `league_by_id()`, `league_name()`, `goal_model_args()`), statt Literale zu tragen. Ein Feld `active` trennt dabei „steht in der Registry" von „läuft im Produktivpfad": Der Saisonwechsel und die Validierung kannten die neuen Ligen, bevor sie live gingen — so war die Struktur an echten Anforderungen erprobt, nicht an einem Testfall.

Drei Entwurfsentscheidungen sind erklärungsbedürftig.

**R-Datei, nicht YAML oder CSV.** Die Registry bleibt damit bei den bestehenden Konventionen, ist ohne neue Dependency testbar, und sie kann Ausdrücke tragen — der Default von `checkAPILimits()` ist `1 + length(league_ids()) / 2` und wächst dadurch mit der Ligazahl mit, statt sie als Konstante zu wiederholen. Eine Datendatei hätte dieselben Zahlen ein zweites Mal festgeschrieben.

**Teamzahlen sind Spannen, keine Gleichheiten.** Die Frauen-Bundesliga spielte mit 12 und mit 14 Teams, die Regionalliga Bayern mit 18, 20 und 19. Eine Gleichheitsprüfung hätte die Saison abgebrochen, in der sich das ändert — und zwar erst im Betrieb.

**Die Modellkonstanten stehen ausdrücklich *nicht* in der Registry.** `home_advantage`, `mod_factor` und das Herren-Tormodell leben im Rust-Server; R sendet sie nicht mit (ADR 0002). In der Registry steht allein die *Abweichung*: das Tormodell der Frauen-Ligen, das Rust nicht kennt und das übertragen werden muss (ADR 0004). Was nicht abweicht, hat hier nichts zu suchen — sonst gäbe es zwei Quellen für denselben Wert, und die eine ließe sich ändern, ohne dass die andere folgt. `tests/testthat/test-modellkonstanten-nur-in-rust.R` hält das maschinell fest und führt die Registry als eine von zwei begründeten Ausnahmen.

Bewusst in Kauf genommen: Die Registry ist eine breite Datei, und ein falscher Wert darin wirkt an vielen Stellen zugleich. Das ist der Preis dafür, dass er auch nur an einer Stelle steht. Ebenfalls in Kauf genommen: Nicht alles Saisonabhängige gehört hinein — welche Staffel den rotierenden Aufstiegsplatz trägt, steht bewusst woanders (ADR 0006), weil es keine Eigenschaft der Liga ist, sondern ein jährlicher Beschluss.

Verworfen: **Weiterhin Literale, ergänzt um eine Konstantenliste.** Das hätte die Ligamengen zentralisiert, aber nicht die Namens-Maps, Teamzahlen und Abstiegsregeln — die inhaltlich interessanten Teile wären verstreut geblieben. Verworfen: **eine Konfigurationsdatei außerhalb des Codes** (YAML/JSON) — sie braucht eine Dependency, einen Ladepfad mit Fehlerbehandlung und ein Schema, um dieselbe Sicherheit zu erreichen, die R-Code kostenlos hat, und kann keine abgeleiteten Werte tragen. Verworfen: **die Registry aus der TeamList abzuleiten** — die TeamList sagt, welche Teams es gibt, nicht wie eine Liga heißt, wie viele absteigen oder wohin. Sie hätte die Registry um genau die Felder ergänzen müssen, die sie ersetzen sollte.
