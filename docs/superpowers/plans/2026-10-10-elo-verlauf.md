# ELO-Verlaufsseiten (Issue #184) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Je Liga eine statische Seite `<slug>-verlauf.html`, die den ELO-Verlauf aller Vereine der laufenden Saison als interaktives Liniendiagramm zeigt (Tufte + 30-Punkte-Design, Vorlage `docs/designs/elo-verlauf-2bl-2024-25.html`).

**Architecture:** `RCode/elo_verlauf.R` formt aus dem vorhandenen `league_entry` (Ausgabe von `build_league_page_data()`, enthält bereits den ELO-Walk von `/league-details`) rein funktional die Verlaufsdaten. Der Generator bereitet sie vor dem Rendern für alle Ligen auf, rendert je Liga eine Verlaufsseite (Tabelle serverseitig, Daten als eingebettetes JSON) und verdrahtet Links und Navigation. `RCode/site_assets/verlauf.js` zeichnet das SVG im Browser.

**Tech Stack:** R 4.3 (htmltools, jsonlite, testthat 3, withr), Vanilla-JS (ES2017, kein Build, keine Bibliothek), Node + jsdom für Client-Tests, Rust-Server nur für das Fixture-Skript.

**Spec:** `docs/superpowers/specs/2026-10-10-elo-verlauf-design.md` (freigegeben 2026-10-10). Executors lesen Spec und Plan.

## Global Constraints

- Keine Modellkonstante als Zahl in R-Code, Seitentext oder JS (Heimvorteil, k-Faktor, Tormodell): Sie leben nur im Rust-Server (ADR 0002).
- Farben und Schriften nur über die Tokens in `RCode/site_assets/site.css`; neu sind genau zwei Tokens: `--rule-dim:#EDE9DE` und `--ink-dim:#BDB6A8`.
- Keine externen Skripte oder Bibliotheken; JS nur aus `assets/`. `verlauf.js` darf die Zeichenfolge `</script` nicht enthalten.
- Testdateien folgen `tests/testthat/README.md`: `test-<einheit>[-<thema>].R`, jede Datei nennt ihre Einheit per `source_module("<einheit>")` bzw. Pfadliteral; kein Top-Level-Name in zwei Testdateien oder überschattet einen Helfer.
- **Tests sind ab Christophs Testfreigabe (Gate nach Phase A) eingefroren.** Passt eine Implementierung nicht zu einem freigegebenen Test: anhalten und zurückfragen, nie den Test ändern.
- `RCode/` bleibt lint-frei: `Rscript -e 'l <- lintr::lint_dir("RCode"); print(l); quit(status = length(l) > 0)'` (lintr 3.4.0, Zeilenlänge 120).
- Seitentexte deutsch mit echten Umlauten; Zahlen mit Dezimalkomma, Minus als U+2212, Null als `±0,0` (vorhandene Helfer `.komma()`/`.vorzeichen()` in `RCode/render_sections.R`).
- Commit-Nachrichten enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **league_data ohne `matches`** (Alt-Fixtures und bestehende Tests übergeben nur `list(tabelle = …)`) → keine Verlaufsseite, kein Link, **keine Warnung**. Test: Task A2, Block 3.
2. **Saisonauftakt mit einem einzigen gespielten Spiel** → Diagramm zeichnet ohne Fehler und ohne `NaN` in den Pfaden; Vereine ohne Spiel sind ein Punkt am linken Rand. Test: Task A3, Block 11.
3. **Verschobenes, noch offenes Spiel (PST)** → der Verein endet ein Spiel früher, die Saison läuft, Endbeschriftungen überlappen trotzdem nicht. Tests: Task A1, Block 8; Task A3, Block 12.
4. **Abgesagtes Spiel (CANC) am Saisonende** → Saison gilt als abgeschlossen, kein Überhang. Test: Task A1, Block 7.
5. **Vereinsname mit `&`, `"`, `</script>`** → JSON und Tabelle bleiben intakt, Name erscheint korrekt. Test: Task A2, Block 11.

## Ablauf und Modelle

Die Umsetzung läuft subagent-driven (`superpowers:subagent-driven-development`): je Task ein frischer Implementierer, danach ein frischer Reviewer, erst dann der nächste Task.

**Phase A – Tests (rot):** Tasks A1–A4 schreiben alle Tests und die nötigen Stubs. Danach **Gate**: Branch pushen, Draft-PR öffnen, Christoph gibt die Tests frei. Erst dann Phase B.

**Phase B – Implementierung (grün):** Tasks B1–B5 machen die Tests grün, ohne sie anzufassen. B6 ist die gestalterische Abnahme im Browser durch den Controller.

| Task | Inhalt | Implementierer | Reviewer |
|---|---|---|---|
| A1 | Helfer + Datentests `test-elo_verlauf.R`, Stub `elo_verlauf.R` | sonnet | sonnet |
| A2 | Seitentests `test-generate_static_site-verlauf.R` + `test-league_views.R`-Block | sonnet | sonnet |
| A3 | JS-Runner-Szenario + `test-generate_static_site-verlauf-js.R` | sonnet | sonnet |
| A4 | Skripttests (Vorschau 3. Argument, Fixture-Skript) + Stub | sonnet | sonnet |
| Gate | Draft-PR, Testfreigabe durch Christoph | Controller | — |
| B1 | `RCode/elo_verlauf.R` | sonnet | sonnet |
| B2 | Generator: `verlauf_slug`, Navigation, Seite, Link, Asset | sonnet | opus |
| B3 | `verlauf.js` + CSS (Gestaltungstreue zum Entwurf) | opus | opus |
| B4 | `preview_site.R` 3. Argument + `scripts/verlauf_fixture.R` | sonnet | sonnet |
| B5 | Dokumentation | haiku | sonnet |
| B6 | Sichtprüfung neben dem Entwurf, Screenshots, Feinschliff nur in CSS/JS | Controller (opus, Chrome) | — |
| Ende | Whole-Branch-Review | — | opus |

Begründung: Tests und R-Logik sind im Plan vollständig ausformuliert, das trägt sonnet sicher. B2 berührt den zentralen Generator (Seiteninventar, Navigation), daher opus im Review. B3 ist gestalterische Feinarbeit nach Vorlage, dort zählt Urteilsvermögen, deshalb opus für beides. B5 ist mechanisch.

**Testbefehle** (vom Repo-Wurzelverzeichnis):

- eine Einheit: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^elo_verlauf$")'`
- Seitentests: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site-verlauf$")'`
- JS-Tests: `npm ci` (einmalig), dann `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site-verlauf-js$")'`
- gesamte Suite: `Rscript -e 'source("tests/testthat.R")'`

---

## Phase A – Tests

### Task A1: Testhelfer und Datentests für `elo_verlauf_daten()`

**Files:**
- Create: `tests/testthat/helper-elo-verlauf.R`
- Create: `tests/testthat/test-elo_verlauf.R`
- Create: `RCode/elo_verlauf.R` (Stub)
- Modify: `tests/testthat/README.md` (Helfertabelle, eine Zeile)

**Interfaces:**
- Produces (Helfer, von A2–A4 genutzt):
  - `verlauf_teams()` → data.frame im TeamList-Format, IDs 101–104
  - `verlauf_spiel(fixture_id, round, kickoff, status, home_id, away_id, goals_home = NA_real_, goals_away = NA_real_, delta = NA_real_, p = c(0.5, 0.25, 0.25))` → eine Spielzeile
  - `verlauf_entry(spiele, teams = verlauf_teams(), namen = NULL)` → `league_entry` wie `build_league_page_data()` (`details`, `teams`, `matches`, `current_elos`, `tabelle`)
  - `verlauf_beispiel(laeuft = TRUE, nachhol = FALSE, gewertet = FALSE, verschoben = FALSE, abgesagt = FALSE, leer = FALSE, nur_erstes = FALSE, pause_tage = 0, namen = NULL)` → `league_entry`
  - `verlauf_site(league_data, envir = parent.frame())` → Pfad eines temporären Ausgabeverzeichnisses mit der gerenderten Site
- Produces (Stub, von B1 gefüllt): `elo_verlauf_saison(kickoff)` → `character(1)`, `elo_verlauf_daten(league_entry)` → Liste (siehe Spec, Abschnitt 2)

- [ ] **Step 1: Stub `RCode/elo_verlauf.R` anlegen**

Der Stub existiert, damit `test-waechter-teststruktur.R` die neue Testdatei einer Einheit zuordnen kann. Die Funktionen brechen ab.

```r
# ELO-Verlauf je Liga (Issue #184). Spec:
# docs/superpowers/specs/2026-10-10-elo-verlauf-design.md
#
# TDD: Signaturen stehen, die Implementierung folgt nach der Testfreigabe
# (tests/testthat/test-elo_verlauf.R).

elo_verlauf_saison <- function(kickoff) {
  stop("elo_verlauf_saison: noch nicht implementiert (Issue #184, Task B1)")
}

elo_verlauf_daten <- function(league_entry) {
  stop("elo_verlauf_daten: noch nicht implementiert (Issue #184, Task B1)")
}
```

- [ ] **Step 2: Helfer `tests/testthat/helper-elo-verlauf.R` schreiben**

```r
# Helfer fuer die Tests der ELO-Verlaufsseiten (Issue #184).
#
# verlauf_entry() baut einen league_entry in der Form, die
# build_league_page_data() liefert -- ohne Rust: Die Endpunktspalten
# (played, elo_home_pre, elo_away_pre, elo_delta_home, p_*) entstehen aus
# einem einfachen Walk mit vorgegebenen Heim-Deltas. Gespielt ist ein Spiel
# wie im Seam: Status beendet (STATUS_BEENDET) und beide Tore vorhanden;
# gewertete Spiele (AWD) bewegen das ELO nicht (Issue #157).
#
# verlauf_beispiel(): vier Vereine, drei Runden. Von Hand nachgerechnet
# (Standardfall, laufende Saison):
#   Start          101: 1600  102: 1500  103: 1400  104: 1450
#   f1 R1 101-102 2:1, Delta +10    -> 101 1610, 102 1490
#   f2 R1 103-104 0:0, Delta -2     -> 103 1398, 104 1452
#   f3 R2 102-103 1:1, Delta -1,5   -> 102 1488,5, 103 1399,5
#   f4 R2 104-101 2:0, Delta +40    -> 104 1492, 101 1570
#   f5/f6 R3 offen (NS) am 22.08.
#   Heute: 101 1570, 104 1492, 102 1488,5, 103 1399,5
# f1 hat Anstoss 22:30 UTC am 08.08. -- in Berlin schon der 09.08.

verlauf_teams <- function() {
  data.frame(
    TeamID = c(101, 102, 103, 104),
    ShortText = c("AAA", "BBB", "CCC", "DDD"),
    Promotion = c(0, 0, 0, 0),
    InitialELO = c(1600, 1500, 1400, 1450),
    stringsAsFactors = FALSE
  )
}

verlauf_spiel <- function(fixture_id, round, kickoff, status, home_id, away_id,
                          goals_home = NA_real_, goals_away = NA_real_,
                          delta = NA_real_, p = c(0.5, 0.25, 0.25)) {
  zeile <- fd_row(fixture_id, round, kickoff, status, home_id, away_id,
                  goals_home, goals_away)
  zeile$delta <- delta
  zeile$p_home_win <- p[1]
  zeile$p_draw <- p[2]
  zeile$p_away_win <- p[3]
  zeile
}

verlauf_entry <- function(spiele, teams = verlauf_teams(), namen = NULL) {
  ld <- source_module("league_details")
  spiele <- spiele[order(spiele$kickoff), ]
  rownames(spiele) <- NULL

  elo <- stats::setNames(teams$InitialELO, as.character(teams$TeamID))
  n <- nrow(spiele)
  played <- logical(n)
  pre_h <- numeric(n)
  pre_a <- numeric(n)
  d <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    h <- as.character(spiele$home_id[i])
    a <- as.character(spiele$away_id[i])
    played[i] <- spiele$status[i] %in% ld$STATUS_BEENDET &&
      !is.na(spiele$goals_home[i]) && !is.na(spiele$goals_away[i])
    pre_h[i] <- elo[[h]]
    pre_a[i] <- elo[[a]]
    if (played[i]) {
      d[i] <- spiele$delta[i]
      elo[[h]] <- elo[[h]] + d[i]
      elo[[a]] <- elo[[a]] - d[i]
    }
  }

  details <- spiele[, c("fixture_id", "round", "kickoff", "status", "home_id",
                        "away_id", "home_name", "away_name", "goals_home",
                        "goals_away")]
  endpunkt <- data.frame(
    index = seq_len(n) - 1L, played = played,
    elo_home_pre = pre_h, elo_away_pre = pre_a, elo_delta_home = d,
    p_home_win = spiele$p_home_win, p_draw = spiele$p_draw,
    p_away_win = spiele$p_away_win
  )
  matches <- cbind(details, endpunkt)

  tabelle <- ld$build_league_table(details, teams)
  tabelle$name <- paste("Team", tabelle$team_id)
  if (!is.null(namen)) {
    treffer <- match(names(namen), as.character(tabelle$team_id))
    tabelle$name[treffer] <- unname(namen)
  }
  tabelle$kuerzel <- teams$ShortText[match(tabelle$team_id, teams$TeamID)]
  tabelle$elo <- unname(elo[as.character(tabelle$team_id)])
  tabelle$delta_elo <- tabelle$elo -
    teams$InitialELO[match(tabelle$team_id, teams$TeamID)]

  list(details = details, teams = teams, matches = matches,
       current_elos = unname(elo[as.character(teams$TeamID)]),
       tabelle = tabelle)
}

verlauf_beispiel <- function(laeuft = TRUE, nachhol = FALSE, gewertet = FALSE,
                             verschoben = FALSE, abgesagt = FALSE,
                             leer = FALSE, nur_erstes = FALSE,
                             pause_tage = 0, namen = NULL) {
  # pause_tage verschiebt Runde 2 und 3 nach hinten (Winterpause).
  t2 <- function(x) {
    format(as.POSIXct(x, tz = "UTC") + pause_tage * 86400, "%Y-%m-%d %H:%M:%S",
           tz = "UTC")
  }
  f4_zeit <- if (nachhol) "2026-08-26 18:30:00" else "2026-08-15 16:30:00"
  spiele <- rbind(
    verlauf_spiel(1, 1, "2026-08-08 22:30:00", "FT", 101, 102, 2, 1,
                  delta = 10, p = c(0.6, 0.25, 0.15)),
    if (gewertet) {
      verlauf_spiel(2, 1, "2026-08-09 13:30:00", "AWD", 103, 104, 0, 3)
    } else {
      verlauf_spiel(2, 1, "2026-08-09 13:30:00", "FT", 103, 104, 0, 0, delta = -2)
    },
    verlauf_spiel(3, 2, t2("2026-08-15 13:30:00"), "FT", 102, 103, 1, 1,
                  delta = -1.5),
    if (verschoben) {
      verlauf_spiel(4, 2, t2("2026-08-15 16:30:00"), "PST", 104, 101)
    } else {
      verlauf_spiel(4, 2, t2(f4_zeit), "FT", 104, 101, 2, 0, delta = 40,
                    p = c(0.2, 0.3, 0.5))
    },
    if (laeuft) {
      verlauf_spiel(5, 3, t2("2026-08-22 13:30:00"), "NS", 101, 103)
    } else {
      verlauf_spiel(5, 3, t2("2026-08-22 13:30:00"), "FT", 101, 103, 1, 0, delta = 5)
    },
    if (laeuft) {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "NS", 102, 104)
    } else if (abgesagt) {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "CANC", 102, 104)
    } else {
      verlauf_spiel(6, 3, t2("2026-08-22 13:30:00"), "FT", 102, 104, 1, 1, delta = -3)
    }
  )
  offen <- if (leer) rep(TRUE, nrow(spiele)) else if (nur_erstes) spiele$fixture_id != 1 else NULL
  if (!is.null(offen)) {
    spiele$status[offen] <- "NS"
    spiele$goals_home[offen] <- NA_real_
    spiele$goals_away[offen] <- NA_real_
  }
  verlauf_entry(spiele, namen = namen)
}

# Rendert die Site mit der Preview-Fixture (make_data_env) und `league_data`
# in ein temporaeres Verzeichnis, das mit `envir` aufgeraeumt wird.
verlauf_site <- function(league_data, envir = parent.frame()) {
  gen <- source_module("generate_static_site")
  out <- withr::local_tempdir(.local_envir = envir)
  suppressMessages(gen$generate_static_site(
    ergebnisse = ergebnisse_aus_env(make_data_env()), output_dir = out,
    now = as.POSIXct("2026-10-10 12:00:00", tz = "Europe/Berlin"),
    league_data = league_data
  ))
  out
}
```

- [ ] **Step 3: Datentests `tests/testthat/test-elo_verlauf.R` schreiben**

```r
# ELO-Verlauf (Issue #184): elo_verlauf_daten() formt aus dem league_entry die
# Daten der Verlaufsseite. Erwartungswerte aus verlauf_beispiel()
# (helper-elo-verlauf.R), dort von Hand nachgerechnet.

ev_daten <- function(...) {
  fn(source_module("elo_verlauf"), "elo_verlauf_daten")(verlauf_beispiel(...))
}
ev_verein <- function(daten, id) Filter(function(t) t$id == id, daten$teams)[[1]]
ev_punkt <- function(verein, n) Filter(function(p) p$n == n, verein$punkte)[[1]]

test_that("die Vereine stehen nach ELO heute, nicht nach Startwert", {
  d <- ev_daten()
  expect_identical(vapply(d$teams, function(t) t$id, numeric(1)), c(101, 104, 102, 103))
  expect_equal(vapply(d$teams, function(t) t$aktuell, numeric(1)), c(1570, 1492, 1488.5, 1399.5))
  expect_equal(vapply(d$teams, function(t) t$start, numeric(1)), c(1600, 1450, 1500, 1400))
  expect_identical(vapply(d$teams, function(t) t$kuerzel, ""), c("AAA", "DDD", "BBB", "CCC"))
  expect_identical(vapply(d$teams, function(t) t$name, ""), c("Team 101", "Team 104", "Team 102", "Team 103"))
})

test_that("der erste Punkt ist der Saisonstart, danach ein Punkt je ELO-wirksamem Spiel", {
  v <- ev_verein(ev_daten(), 101)
  expect_length(v$punkte, 3)
  expect_identical(v$punkte[[1]], list(n = 0L, nach = 1600))
  expect_identical(vapply(v$punkte, function(p) as.integer(p$n), integer(1)), 0:2)
})

test_that("Heim- und Gastsicht: Delta mit Vorzeichen, Siegchance des eigenen Vereins", {
  d <- ev_daten()
  heim <- ev_punkt(ev_verein(d, 104), 2)
  expect_true(heim$heim)
  expect_equal(c(heim$vor, heim$delta, heim$nach), c(1452, 40, 1492))
  expect_equal(c(heim$p_sieg, heim$p_remis), c(0.2, 0.3))
  expect_identical(c(heim$gegner, heim$gegner_name), c("AAA", "Team 101"))
  expect_equal(c(heim$tore_heim, heim$tore_gast), c(2, 0))

  gast <- ev_punkt(ev_verein(d, 101), 2)
  expect_false(gast$heim)
  expect_equal(c(gast$vor, gast$delta, gast$nach), c(1610, -40, 1570))
  expect_equal(c(gast$p_sieg, gast$p_remis), c(0.5, 0.3))
  expect_identical(c(gast$gegner, gast$gegner_name), c("DDD", "Team 104"))
  expect_identical(gast$runde, 2L)
  expect_false(gast$nachhol)
})

test_that("das Datum ist der Berliner Kalendertag des Anstosses", {
  p <- ev_punkt(ev_verein(ev_daten(), 101), 1)
  # Anstoss 2026-08-08 22:30 UTC = 2026-08-09 00:30 in Berlin
  expect_identical(p$datum, "2026-08-09")
  expect_identical(p$runde, 1L)
})

test_that("laufende Saison: die Achse reicht ein Spiel und sieben Tage weiter", {
  d <- ev_daten()
  expect_true(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
})

test_that("abgeschlossene Saison: kein Ueberhang auf der Achse", {
  d <- ev_daten(laeuft = FALSE)
  expect_false(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_equal(vapply(d$teams, function(t) t$aktuell, numeric(1)), c(1575, 1495, 1485.5, 1394.5))
})

test_that("ein abgesagtes Spiel haelt die Saison nicht offen", {
  d <- ev_daten(laeuft = FALSE, abgesagt = TRUE)
  expect_false(d$saison_laeuft)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_length(ev_verein(d, 102)$punkte, 3)
})

test_that("ein verschobenes offenes Spiel: der Verein endet ein Spiel frueher, die Saison laeuft", {
  d <- ev_daten(verschoben = TRUE)
  expect_true(d$saison_laeuft)
  expect_length(ev_verein(d, 101)$punkte, 2)
  expect_length(ev_verein(d, 102)$punkte, 3)
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(d$achse_datum_ende, "2026-08-22")
  expect_equal(ev_verein(d, 101)$aktuell, 1610)
})

test_that("ein Nachholspiel steht chronologisch und ist markiert", {
  d <- ev_daten(nachhol = TRUE)
  v <- ev_verein(d, 101)
  expect_false(ev_punkt(v, 1)$nachhol)
  nach <- ev_punkt(v, 2)
  expect_true(nach$nachhol)
  expect_identical(nach$datum, "2026-08-26")
  expect_identical(nach$runde, 2L)
  expect_identical(d$achse_datum_ende, "2026-09-02")
})

test_that("ein am gruenen Tisch gewertetes Spiel erzeugt keinen Punkt", {
  d <- ev_daten(gewertet = TRUE)
  expect_length(ev_verein(d, 103)$punkte, 2)
  expect_length(ev_verein(d, 104)$punkte, 2)
  expect_equal(ev_verein(d, 103)$aktuell, 1401.5)
  expect_true(d$saison_laeuft)
})

test_that("vor dem ersten Spiel: nur Startpunkte, Achse ein Spiel, kein Datum", {
  d <- ev_daten(leer = TRUE)
  expect_true(all(vapply(d$teams, function(t) length(t$punkte), integer(1)) == 1L))
  expect_identical(d$achse_spiele_max, 1L)
  expect_identical(d$achse_datum_ende, NA_character_)
  expect_true(d$saison_laeuft)
})

test_that("die Saison heisst nach dem fruehesten Anstoss", {
  expect_identical(ev_daten()$saison, "2026/27")
  saison <- fn(source_module("elo_verlauf"), "elo_verlauf_saison")
  expect_identical(saison(as.POSIXct("2099-08-01 12:00:00", tz = "UTC")), "2099/00")
  expect_identical(saison(as.POSIXct(character(0), tz = "UTC")), "")
})

test_that("weicht der Verlauf von der Tabelle ab, bricht die Funktion mit Verein und Werten ab", {
  e <- verlauf_beispiel()
  e$tabelle$elo[e$tabelle$team_id == 104] <- 1500
  f <- fn(source_module("elo_verlauf"), "elo_verlauf_daten")
  expect_error(f(e), "ELO-Verlauf von Team 104 endet bei 1492.000, die Tabelle sagt 1500.000",
               fixed = TRUE)
})
```

- [ ] **Step 4: README-Helfertabelle ergänzen**

In `tests/testthat/README.md`, Tabelle „Helfer“, nach der Zeile `helper-league-details.R` einfügen:

```markdown
| `helper-elo-verlauf.R` | seit #184: `verlauf_teams`, `verlauf_spiel`, `verlauf_entry` (league_entry ohne Rust), `verlauf_beispiel` (vier Vereine, drei Runden, Varianten für Nachhol-, gewertete, verschobene, abgesagte Spiele), `verlauf_site` (rendert die Site in ein Temp-Verzeichnis) |
```

- [ ] **Step 5: Tests laufen lassen, Rot prüfen**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^elo_verlauf$")'`
Expected: Alle 13 Blöcke FAIL mit „noch nicht implementiert (Issue #184, Task B1)“, kein anderer Fehler (insbesondere kein Fehler aus dem Helfer). Danach `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^waechter")'` → PASS.

- [ ] **Step 6: Commit**

```bash
git add RCode/elo_verlauf.R tests/testthat/helper-elo-verlauf.R tests/testthat/test-elo_verlauf.R tests/testthat/README.md
git commit -m "test(#184): Datentests ELO-Verlauf (rot) und Testhelfer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A2: Seiten- und Navigationstests

**Files:**
- Create: `tests/testthat/test-generate_static_site-verlauf.R`
- Modify: `tests/testthat/test-league_views.R` (ein Block am Dateiende)

**Interfaces:**
- Consumes: `verlauf_beispiel()`, `verlauf_site()` (A1); `html_lesen()` (helper-html.R)
- Produces (Vertrag für B2, wörtlich so im HTML):
  - Datei `<verlauf_slug>.html`, `verlauf_slug` = `bundesliga-verlauf` bzw. `<slug>-verlauf`
  - Ligaseite: `<a href="<verlauf_slug>.html">ELO-Verlauf der Saison ansehen →</a>` im Abschnitt `id="tabelle"`
  - Verlaufsseite: `<a href="<slug>.html">← Prognose <nav_label></a>`, `<h2>ELO-Verlauf <nav_label> <saison></h2>`, `<script type="application/json" id="verlauf-daten">`, `<script src="assets/verlauf.js"></script>`, `id="verlauf-box"`, Buttons `data-mode="spiel" aria-pressed="true"` / `data-mode="datum" aria-pressed="false"`, `<table class="verlauf-tab" id="verlauf-tab">`, Zeilen `<tr data-i="…">`, Leerfall `<p class="sectionlead" id="verlauf-leer">Die Saison hat noch nicht begonnen.</p>`
  - Navigation auf Verlaufsseiten: `<a class="nav-current" aria-current="page" href="bundesliga-verlauf.html">Bundesliga</a>`

- [ ] **Step 1: Block in `tests/testthat/test-league_views.R` anhängen**

```r
test_that("jede Liga traegt einen eigenen verlauf_slug, die Bundesliga bundesliga-verlauf (#184)", {
  views <- source_module("league_views")$league_views()
  slugs <- vapply(names(views), function(k) views[[k]]$slug, "")
  vs <- vapply(names(views), function(k) {
    v <- views[[k]]$verlauf_slug
    if (is.null(v)) NA_character_ else v
  }, "")
  expect_length(vs, 10)
  expect_false(anyNA(vs))
  expect_identical(unname(vs[["bundesliga"]]), "bundesliga-verlauf")
  andere <- names(vs) != "bundesliga"
  expect_identical(unname(vs[andere]), paste0(unname(slugs[andere]), "-verlauf"))
  expect_false(any(vs %in% c(slugs, "methodik", "rl-aufstieg")))
  expect_null(views[["rl-aufstieg"]]$verlauf_slug)
})
```

- [ ] **Step 2: `tests/testthat/test-generate_static_site-verlauf.R` schreiben**

```r
# Verlaufsseiten im Generator (Issue #184): Seite je Liga mit league_data,
# Link auf der Ligaseite, Ruecklink, kontextabhaengige Navigation, Tabelle
# aus R, Daten als eingebettetes JSON. Spec:
# docs/superpowers/specs/2026-10-10-elo-verlauf-design.md, Abschnitt 1.

gsv_gen <- source_module("generate_static_site")

gsv_seite <- function(dir, slug) html_lesen(file.path(dir, paste0(slug, ".html")))

gsv_nav <- function(html) sub("(?s).*?(<nav.*?</nav>).*", "\\1", html, perl = TRUE)

gsv_json <- function(html) {
  roh <- sub('(?s).*<script type="application/json" id="verlauf-daten">(.*?)</script>.*',
             "\\1", html, perl = TRUE)
  jsonlite::fromJSON(roh, simplifyVector = FALSE)
}

gsv_zwei_ligen <- function(...) {
  list(bundesliga = verlauf_beispiel(...), zweite_bundesliga = verlauf_beispiel())
}

test_that("mit league_data entsteht je Liga eine Verlaufsseite unter ihrem verlauf_slug", {
  dir <- verlauf_site(gsv_zwei_ligen())
  expect_true(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_true(file.exists(file.path(dir, "2-bundesliga-verlauf.html")))
  expect_false(file.exists(file.path(dir, "3-liga-verlauf.html")))
  expect_true(file.exists(file.path(dir, "assets", "verlauf.js")))
})

test_that("ohne league_data entsteht keine Verlaufsseite und kein Link", {
  dir <- verlauf_site(NULL)
  expect_length(list.files(dir, pattern = "-verlauf\\.html$"), 0)
  expect_false(grepl("ELO-Verlauf der Saison ansehen", gsv_seite(dir, "index"), fixed = TRUE))
})

test_that("ein league_entry ohne matches erzeugt keine Verlaufsseite und keine Warnung", {
  ld <- list(bundesliga = list(tabelle = verlauf_beispiel()$tabelle))
  # envir ausdruecklich: innerhalb von expect_*() waere parent.frame() eine
  # Auswertungsumgebung, mit der das Temp-Verzeichnis zu frueh verschwaende.
  ziel <- environment()
  expect_no_warning(dir <- verlauf_site(ld, envir = ziel))
  expect_false(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_false(grepl("bundesliga-verlauf.html", gsv_seite(dir, "index"), fixed = TRUE))
})

test_that("die Ligaseite verlinkt ihre Verlaufsseite im Tabellenabschnitt", {
  dir <- verlauf_site(gsv_zwei_ligen())
  html <- gsv_seite(dir, "index")
  link <- '<a href="bundesliga-verlauf.html">ELO-Verlauf der Saison ansehen →</a>'
  expect_match(html, link, fixed = TRUE)
  expect_gt(regexpr(link, html, fixed = TRUE), regexpr('<section id="tabelle">', html, fixed = TRUE))
  expect_match(gsv_seite(dir, "2-bundesliga"), '<a href="2-bundesliga-verlauf.html">', fixed = TRUE)
  expect_false(grepl("-verlauf.html", gsv_seite(dir, "3-liga"), fixed = TRUE))
})

test_that("die Verlaufsseite verlinkt zurueck auf die Prognose ihrer Liga", {
  dir <- verlauf_site(gsv_zwei_ligen())
  expect_match(gsv_seite(dir, "bundesliga-verlauf"), '<a href="index.html">← Prognose Bundesliga</a>', fixed = TRUE)
  expect_match(gsv_seite(dir, "2-bundesliga-verlauf"), '<a href="2-bundesliga.html">← Prognose 2. Bundesliga</a>',
               fixed = TRUE)
})

test_that("auf der Verlaufsseite fuehren die Ligalinks zu den Verlaufsseiten, sonst zur Ligaseite", {
  dir <- verlauf_site(gsv_zwei_ligen())
  nav <- gsv_nav(gsv_seite(dir, "bundesliga-verlauf"))
  expect_match(nav, '<a class="nav-current" aria-current="page" href="bundesliga-verlauf.html">Bundesliga</a>',
               fixed = TRUE)
  expect_match(nav, '<a href="2-bundesliga-verlauf.html">2. Bundesliga</a>', fixed = TRUE)
  expect_match(nav, '<a href="3-liga.html">3. Liga</a>', fixed = TRUE)
  expect_match(nav, '<a href="rl-aufstieg.html">', fixed = TRUE)
  expect_match(nav, '<a href="methodik.html">Methodik</a>', fixed = TRUE)
})

test_that("die Navigation der Ligaseiten bleibt unveraendert", {
  dir <- verlauf_site(gsv_zwei_ligen())
  nav <- gsv_nav(gsv_seite(dir, "index"))
  expect_match(nav, '<a class="nav-current" aria-current="page" href="index.html">Bundesliga</a>', fixed = TRUE)
  expect_match(nav, '<a href="2-bundesliga.html">2. Bundesliga</a>', fixed = TRUE)
  expect_false(grepl("-verlauf.html", nav, fixed = TRUE))
})

test_that("Titel und Ueberschrift nennen Liga und Saison", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, "<title>30 Punkte · ELO-Verlauf Bundesliga</title>", fixed = TRUE)
  expect_match(html, "<h2>ELO-Verlauf Bundesliga 2026/27</h2>", fixed = TRUE)
})

test_that("die Daten stehen als JSON vor dem Zeichenskript, in Tabellenreihenfolge", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  d <- gsv_json(html)
  expect_identical(d$liga, "Bundesliga")
  expect_identical(d$saison, "2026/27")
  expect_identical(d$achse_spiele_max, 3L)
  expect_identical(vapply(d$teams, function(t) t$id, numeric(1)), c(101, 104, 102, 103))
  expect_gt(regexpr('<script src="assets/verlauf.js"></script>', html, fixed = TRUE),
            regexpr('id="verlauf-daten"', html, fixed = TRUE))
})

test_that("die Tabelle rendert R: Startwert, heute, Veraenderung", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, '<table class="verlauf-tab" id="verlauf-tab">', fixed = TRUE)
  expect_match(html, paste0('<tr data-i="0"><th scope="row">Team 101</th><td class="num">1600,0</td>',
                            '<td class="num">1570,0</td><td class="num dneg">−30,0</td></tr>'), fixed = TRUE)
  expect_match(html, paste0('<tr data-i="1"><th scope="row">Team 104</th><td class="num">1450,0</td>',
                            '<td class="num">1492,0</td><td class="num dpos">+42,0</td></tr>'), fixed = TRUE)
})

test_that("Sonderzeichen im Vereinsnamen zerbrechen weder JSON noch Tabelle", {
  boese <- 'A&B "</script><b>x'
  ld <- list(bundesliga = verlauf_beispiel(namen = c(`101` = boese)))
  html <- gsv_seite(verlauf_site(ld), "bundesliga-verlauf")
  expect_false(grepl("</script><b>x", html, fixed = TRUE))
  expect_identical(gsv_json(html)$teams[[1]]$name, boese)
  expect_match(html, '<th scope="row">A&amp;B "&lt;/script&gt;&lt;b&gt;x</th>', fixed = TRUE)
  skripte <- regmatches(html, gregexpr("<script", html, fixed = TRUE))[[1]]
  enden <- regmatches(html, gregexpr("</script>", html, fixed = TRUE))[[1]]
  expect_identical(length(enden), length(skripte))
})

test_that("scheitert die Aufbereitung einer Liga, fehlen nur ihre Seite und ihr Link", {
  e <- verlauf_beispiel()
  e$tabelle$elo[e$tabelle$team_id == 104] <- 1500
  ziel <- environment()
  expect_warning(dir <- verlauf_site(list(bundesliga = e, zweite_bundesliga = verlauf_beispiel()), envir = ziel),
                 "ELO-Verlauf von Team 104")
  expect_false(file.exists(file.path(dir, "bundesliga-verlauf.html")))
  expect_false(grepl("bundesliga-verlauf.html", gsv_seite(dir, "index"), fixed = TRUE))
  expect_true(file.exists(file.path(dir, "2-bundesliga-verlauf.html")))
  expect_match(gsv_nav(gsv_seite(dir, "2-bundesliga-verlauf")), '<a href="index.html">Bundesliga</a>', fixed = TRUE)
})

test_that("vor dem ersten Spiel steht ein Hinweis statt des Diagramms, die Tabelle bleibt", {
  html <- gsv_seite(verlauf_site(list(bundesliga = verlauf_beispiel(leer = TRUE))), "bundesliga-verlauf")
  expect_match(html, '<p class="sectionlead" id="verlauf-leer">Die Saison hat noch nicht begonnen.</p>',
               fixed = TRUE)
  expect_false(grepl('id="verlauf-box"', html, fixed = TRUE))
  expect_match(html, '<table class="verlauf-tab" id="verlauf-tab">', fixed = TRUE)
})

test_that("Diagrammabschnitt: Umschalter, Diagrammflaeche, noscript-Hinweis", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  expect_match(html, '<button type="button" data-mode="spiel" aria-pressed="true">', fixed = TRUE)
  expect_match(html, '<button type="button" data-mode="datum" aria-pressed="false">', fixed = TRUE)
  expect_match(html, 'id="verlauf-box"', fixed = TRUE)
  expect_match(html, 'id="verlauf-tip"', fixed = TRUE)
  expect_match(html, "<noscript>", fixed = TRUE)
})

test_that("der Hinweis nennt keine Modellkonstanten, sondern verlinkt die Methodik", {
  html <- gsv_seite(verlauf_site(gsv_zwei_ligen()), "bundesliga-verlauf")
  hinweis <- sub('(?s).*<p class="hinweis">(.*?)</p>.*', "\\1", html, perl = TRUE)
  expect_match(hinweis, '<a href="methodik.html">Methodik</a>', fixed = TRUE)
  expect_false(grepl("Heimvorteil|k-Faktor|Tormodell", html))
})
```

- [ ] **Step 3: Rot prüfen**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site-verlauf$")'` und `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^league_views$")'`
Expected: Der neue `league_views`-Block FAIL (`anyNA` / Länge), alle übrigen `league_views`-Blöcke PASS. In `generate_static_site-verlauf` FAIL: alle Blöcke außer „ohne league_data …“ und „ein league_entry ohne matches …“ (die bestehen schon heute; sie sichern, dass B2 nichts kaputt macht). Kein Syntax- oder Helferfehler.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-generate_static_site-verlauf.R tests/testthat/test-league_views.R
git commit -m "test(#184): Seiten- und Navigationstests der Verlaufsseiten (rot)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A3: Client-JS-Tests (jsdom)

**Files:**
- Modify: `tests/testthat/helpers/js-runner.mjs` (Szenario `verlauf`, Kopfkommentar)
- Modify: `tests/testthat/helper-js.R` (Funktion `js_assets_einbetten`)
- Modify: `tests/testthat/README.md` (Zeile `helper-js.R`: `js_assets_einbetten()` ergänzen)
- Create: `tests/testthat/test-generate_static_site-verlauf-js.R`

**Interfaces:**
- Consumes: `verlauf_site()`, `verlauf_beispiel()` (A1); HTML-Vertrag aus A2
- Produces (Vertrag für B3): `window.eloVerlauf = { modus(m), waehle(i), zeigeSpiel(i, n), loesche() }`; SVG `#verlauf-box svg` mit `g.team[data-i]`, darin `path.linie`, `path.hit`, `circle.punkt[data-p]` (`cx`/`cy` mit einer Nachkommastelle), `text.endkuerzel`, `text.endlabel`; `.pause` nur im Datumsmodus; Tooltip `#verlauf-tip` mit Klasse `show`; Geometrie `W=1080, H=640, M={t:16,r:80,b:26,l:52}`.

- [ ] **Step 1: `js_assets_einbetten()` in `tests/testthat/helper-js.R` anhängen**

```r
# Ersetzt <script src="assets/<datei>"></script> durch den Inhalt der Datei aus
# <output_dir>/assets. Der Runner laedt keine externen Ressourcen; so laeuft
# das Skript der Verlaufsseiten (assets/verlauf.js) wie im Browser.
js_assets_einbetten <- function(html, output_dir) {
  tags <- regmatches(html, gregexpr('<script src="assets/[^"]+"></script>', html))[[1]]
  for (tag in tags) {
    datei <- sub('<script src="(assets/[^"]+)"></script>', "\\1", tag)
    inhalt <- paste(readLines(file.path(output_dir, datei), warn = FALSE, encoding = "UTF-8"),
                    collapse = "\n")
    pos <- regexpr(tag, html, fixed = TRUE)
    html <- paste0(substr(html, 1, pos - 1), "<script>\n", inhalt, "\n</script>",
                   substr(html, pos + nchar(tag), nchar(html)))
  }
  html
}
```

- [ ] **Step 2: Szenario `verlauf` in `tests/testthat/helpers/js-runner.mjs`**

Im Kopfkommentar die Szenarioliste ergänzen: `Szenarien: stale (Veraltet-Hinweis), sort (Ligatabelle), tooltip (Kuerzel), verlauf (ELO-Verlauf).` Dann im Objekt `szenarien` nach `tooltip` einfügen:

```js
  // args: { schritte: [{ art, wert?, index?, n? }, ...] } mit art =
  // modus (wert: spiel|datum, Klick auf den Umschalter) | zeile (Klick auf
  // tr[data-i=index] der Tabelle) | zeige (window.eloVerlauf.zeigeSpiel(index, n))
  // | loesche (window.eloVerlauf.loesche()). jsdom kennt kein Layout, deshalb
  // laeuft der Tooltip ueber die Schnittstelle statt ueber Zeigerkoordinaten.
  verlauf({ window, args, fehler }) {
    const doc = window.document;
    const zustand = () => {
      const svg = doc.querySelector("#verlauf-box svg");
      const tip = doc.getElementById("verlauf-tip");
      const gruppen = svg ? Array.from(svg.querySelectorAll("g.team")) : [];
      const xs = (g) => Array.from(g.querySelectorAll(".punkt"), (c) => Number(c.getAttribute("cx")));
      return {
        hat_svg: svg !== null,
        linien: gruppen.length,
        an: gruppen.filter((g) => g.classList.contains("on")).map((g) => Number(g.dataset.i)),
        gedimmt: gruppen.filter((g) => g.classList.contains("dim")).length,
        zeilen_an: Array.from(doc.querySelectorAll("#verlauf-tab tbody tr.on"), (r) => Number(r.dataset.i)),
        gedrueckt: Array.from(doc.querySelectorAll(".modes button"), (b) => b.getAttribute("aria-pressed")),
        tip_sichtbar: tip ? tip.classList.contains("show") : false,
        tip_text: tip ? tip.textContent : null,
        label_y: svg ? Array.from(svg.querySelectorAll(".endkuerzel"), (t) => Number(t.getAttribute("y"))) : [],
        erste_x: Object.fromEntries(gruppen.map((g) => [g.dataset.i, xs(g)[0]])),
        letzte_x: Object.fromEntries(gruppen.map((g) => [g.dataset.i, xs(g)[xs(g).length - 1]])),
        pause: svg ? svg.querySelector(".pause") !== null : false,
        pfad_kaputt: svg
          ? Array.from(svg.querySelectorAll("path.linie"), (p) => p.getAttribute("d")).some((d) => /NaN|Infinity/.test(d))
          : false,
      };
    };
    const api = window.eloVerlauf;
    const vorher = zustand();
    const schritte = (args.schritte || []).map((s) => {
      switch (s.art) {
        case "modus":
          doc.querySelector(`.modes button[data-mode="${s.wert}"]`).click();
          break;
        case "zeile":
          doc.querySelector(`#verlauf-tab tbody tr[data-i="${s.index}"]`)
            .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
          break;
        case "zeige":
          api.zeigeSpiel(s.index, s.n);
          break;
        case "loesche":
          api.loesche();
          break;
        default:
          throw new Error(`unbekannte Aktion: ${s.art}`);
      }
      return zustand();
    });
    return { vorher, schritte, api: typeof api, fehler };
  },
```

- [ ] **Step 3: `tests/testthat/test-generate_static_site-verlauf-js.R` schreiben**

```r
# Client-JS der Verlaufsseiten (Issue #184): assets/verlauf.js zeichnet das
# Diagramm aus #verlauf-daten. Node + jsdom fuehren es auf der gerenderten
# Seite aus (Runner-Szenario "verlauf"). Geometrie wie im Entwurf:
# W = 1080, M.l = 52, M.r = 80, also Zeichenbreite 948, rechter Rand x = 1000.

vjs_seite <- function(league_data, slug = "bundesliga-verlauf", envir = parent.frame()) {
  dir <- verlauf_site(league_data, envir = envir)
  js_assets_einbetten(html_lesen(file.path(dir, paste0(slug, ".html"))), dir)
}

vjs_lauf <- function(..., schritte = list()) {
  html <- vjs_seite(list(bundesliga = verlauf_beispiel(...)))
  js_szenario(html, "verlauf", list(schritte = schritte))
}

test_that("die Skripte der Verlaufsseite bestehen die Syntaxpruefung", {
  skip_ohne_js()
  html <- vjs_seite(list(bundesliga = verlauf_beispiel()))
  html <- gsub('(?s)<script type="application/json".*?</script>', "", html, perl = TRUE)
  skripte <- js_skripte_aus_html(html)
  expect_gt(length(skripte), 1)
  expect_true(all(js_syntax_status(skripte) == 0L))
})

test_that("eine Linie je Verein, Schnittstelle vorhanden, keine Skriptfehler", {
  skip_ohne_js()
  r <- vjs_lauf()
  expect_length(r$fehler, 0)
  expect_identical(r$api, "object")
  expect_true(r$vorher$hat_svg)
  expect_identical(r$vorher$linien, 4L)
  expect_false(r$vorher$pfad_kaputt)
  expect_identical(unlist(r$vorher$gedrueckt), c("true", "false"))
})

test_that("Spielachse: laufend endet die laengste Linie vor dem rechten Rand, abgeschlossen am Rand", {
  skip_ohne_js()
  laufend <- unlist(vjs_lauf()$vorher$letzte_x)
  expect_equal(unname(laufend), rep(684, 4), tolerance = 0.11)
  fertig <- unlist(vjs_lauf(laeuft = FALSE)$vorher$letzte_x)
  expect_equal(unname(fertig), rep(1000, 4), tolerance = 0.11)
})

test_that("Datumsachse: Saisonstart am linken Rand, Spiele nach Kalendertag", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "modus", wert = "datum")))
  s <- r$schritte[[1]]
  expect_identical(unlist(s$gedrueckt), c("false", "true"))
  expect_equal(unname(unlist(s$erste_x)), rep(52, 4), tolerance = 0.11)
  # Verein 101 (data-i 0): letztes Spiel 15.08.; Achse 02.08. bis 22.08. (20 Tage)
  expect_equal(s$letzte_x[["0"]], 52 + 948 * 13 / 20, tolerance = 0.11)
})

test_that("die Winterpause erscheint nur auf der Datumsachse", {
  skip_ohne_js()
  r <- vjs_lauf(pause_tage = 40, schritte = list(list(art = "modus", wert = "datum"),
                                                 list(art = "modus", wert = "spiel")))
  expect_false(r$vorher$pause)
  expect_true(r$schritte[[1]]$pause)
  expect_false(r$schritte[[2]]$pause)
})

test_that("die Endbeschriftungen ueberlappen in beiden Modi nicht", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "modus", wert = "datum")))
  for (zustand in list(r$vorher, r$schritte[[1]])) {
    y <- sort(unlist(zustand$label_y))
    expect_length(y, 4)
    expect_true(all(diff(y) >= 12.4))
  }
})

test_that("Tooltip: Datum, Spieltag, Paarung, Ergebnis, Erwartung, ELO", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeige", index = 0, n = 2)))
  s <- r$schritte[[1]]
  expect_true(s$tip_sichtbar)
  expect_identical(unlist(s$an), 0L)
  for (teil in c("Sa. 15. Aug. 2026 · 2. Spieltag", "Team 104", "Team 101", "2:0",
                 "50 % Sieg, 30 % Remis", "1610,0 → 1570,0", "−40,0")) {
    expect_match(s$tip_text, teil, fixed = TRUE)
  }
  expect_false(grepl("Nachholspiel", s$tip_text, fixed = TRUE))
})

test_that("ein Nachholspiel ist im Tooltip gekennzeichnet", {
  skip_ohne_js()
  r <- vjs_lauf(nachhol = TRUE, schritte = list(list(art = "zeige", index = 0, n = 2),
                                                list(art = "zeige", index = 0, n = 1)))
  expect_match(r$schritte[[1]]$tip_text, "2. Spieltag · Nachholspiel", fixed = TRUE)
  expect_false(grepl("Nachholspiel", r$schritte[[2]]$tip_text, fixed = TRUE))
})

test_that("eine Tabellenzeile hebt ihre Linie hervor, ein zweiter Klick hebt es auf", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeile", index = 1), list(art = "zeile", index = 1)))
  expect_identical(unlist(r$schritte[[1]]$an), 1L)
  expect_identical(unlist(r$schritte[[1]]$zeilen_an), 1L)
  expect_identical(r$schritte[[1]]$gedimmt, 3L)
  expect_length(unlist(r$schritte[[2]]$an), 0)
  expect_identical(r$schritte[[2]]$gedimmt, 0L)
  expect_length(r$fehler, 0)
})

test_that("der Moduswechsel behaelt die Auswahl", {
  skip_ohne_js()
  r <- vjs_lauf(schritte = list(list(art = "zeile", index = 2), list(art = "modus", wert = "datum")))
  expect_identical(unlist(r$schritte[[2]]$an), 2L)
})

test_that("Saisonauftakt mit einem einzigen Spiel: Diagramm ohne Fehler und ohne NaN", {
  skip_ohne_js()
  r <- vjs_lauf(nur_erstes = TRUE, schritte = list(list(art = "modus", wert = "datum")))
  expect_length(r$fehler, 0)
  expect_identical(r$vorher$linien, 4L)
  expect_false(r$vorher$pfad_kaputt)
  expect_false(r$schritte[[1]]$pfad_kaputt)
  # Achse: 1 Spiel + Ueberhang = 2; 101 (data-i 0) steht bei der Haelfte
  expect_equal(r$vorher$letzte_x[["0"]], 52 + 948 / 2, tolerance = 0.11)
})

test_that("ein offenes verschobenes Spiel: der Verein endet frueher, Beschriftungen ueberlappen nicht", {
  skip_ohne_js()
  r <- vjs_lauf(verschoben = TRUE)
  # Reihenfolge heute: 101 (1610), 102 (1488,5), 104 (1452), 103 (1399,5)
  expect_equal(r$vorher$letzte_x[["0"]], 52 + 948 / 3, tolerance = 0.11)
  expect_equal(r$vorher$letzte_x[["1"]], 52 + 948 * 2 / 3, tolerance = 0.11)
  expect_true(all(diff(sort(unlist(r$vorher$label_y))) >= 12.4))
})

test_that("ohne gespielte Spiele: kein Diagramm, kein Fehler", {
  skip_ohne_js()
  r <- vjs_lauf(leer = TRUE)
  expect_false(r$vorher$hat_svg)
  expect_length(r$fehler, 0)
})
```

- [ ] **Step 4: Rot prüfen**

Run: `npm ci` (falls `node_modules/jsdom` fehlt), dann `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site-verlauf-js$")'`
Expected: FAIL in allen Blöcken (es gibt noch keine Verlaufsseite, `html_lesen` findet die Datei nicht). Danach `Rscript -e 'testthat::test_dir("tests/testthat", filter = "js$")'`: die bestehenden JS-Tests (`generate_static_site-js`, `render_sections-js`) PASS (Runner-Änderung bricht nichts).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helpers/js-runner.mjs tests/testthat/helper-js.R tests/testthat/README.md tests/testthat/test-generate_static_site-verlauf-js.R
git commit -m "test(#184): Client-JS-Tests der Verlaufsseiten (rot)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A4: Skripttests (Vorschau mit league_data, Fixture-Skript)

**Files:**
- Modify: `tests/testthat/test-scripts-preview_site.R` (ein Block am Dateiende)
- Create: `tests/testthat/test-scripts-verlauf_fixture.R`
- Create: `scripts/verlauf_fixture.R` (Stub)

**Interfaces:**
- Consumes: `fixture_zehn_ligen()`, `skript_pfad()` (beide in `test-scripts-preview_site.R`), `verlauf_beispiel()` (A1), `skip_if_no_rust()` (helper-rust.R)
- Produces (Vertrag für B4): `Rscript scripts/preview_site.R <ergebnis.Rds> <out> [<league_data.rds>]`; `Rscript scripts/verlauf_fixture.R <ziel.rds>` schreibt `list(bundesliga, zweite_bundesliga, dritte_liga)` von league_entries.

- [ ] **Step 1: Stub `scripts/verlauf_fixture.R`**

```r
#!/usr/bin/env Rscript
# Synthetische league_data fuer die Sichtpruefung der ELO-Verlaufsseiten
# (Issue #184). Implementierung folgt nach der Testfreigabe (Task B4).
stop("verlauf_fixture.R: noch nicht implementiert (Issue #184, Task B4)")
```

- [ ] **Step 2: Block in `tests/testthat/test-scripts-preview_site.R` anhängen**

```r
test_that("preview_site.R nimmt league_data als drittes Argument -- die Verlaufsseiten entstehen (#184)", {
  rscript <- Sys.which("Rscript")
  skip_if(!nzchar(rscript), "Rscript nicht im PATH")
  fixture <- withr::local_tempfile(fileext = ".Rds")
  ld_datei <- withr::local_tempfile(fileext = ".rds")
  out <- withr::local_tempdir()
  fixture_zehn_ligen(fixture)
  saveRDS(list(bundesliga = verlauf_beispiel(), zweite_bundesliga = verlauf_beispiel()), ld_datei)

  ausgabe <- suppressWarnings(system2(
    rscript, c(shQuote(skript_pfad()), shQuote(fixture), shQuote(out), shQuote(ld_datei)),
    stdout = TRUE, stderr = TRUE
  ))
  status <- attr(ausgabe, "status")
  expect_true(is.null(status) || status == 0L, info = paste(ausgabe, collapse = "\n"))
  expect_true(file.exists(file.path(out, "bundesliga-verlauf.html")))
  expect_true(file.exists(file.path(out, "2-bundesliga-verlauf.html")))
  expect_match(html_lesen(file.path(out, "index.html")), 'href="bundesliga-verlauf.html"', fixed = TRUE)
})
```

- [ ] **Step 3: `tests/testthat/test-scripts-verlauf_fixture.R` schreiben**

```r
# scripts/verlauf_fixture.R (Issue #184): erzeugt synthetische league_data fuer
# die Sichtpruefung -- drei Staende, ELO aus dem echten /league-details.
# Braucht den Rust-Server; ohne ihn skippt der Test (in der CI laeuft er).

test_that("verlauf_fixture.R schreibt drei Ligen, deren Verlauf sich aufbereiten laesst", {
  skip_if_no_rust(source_module("rust_integration"))
  rscript <- Sys.which("Rscript")
  skip_if(!nzchar(rscript), "Rscript nicht im PATH")
  skript <- normalizePath(test_path("..", "..", "scripts", "verlauf_fixture.R"), mustWork = TRUE)
  ziel <- withr::local_tempfile(fileext = ".rds")

  ausgabe <- suppressWarnings(system2(rscript, c(shQuote(skript), shQuote(ziel)), stdout = TRUE, stderr = TRUE))
  status <- attr(ausgabe, "status")
  expect_true(is.null(status) || status == 0L, info = paste(ausgabe, collapse = "\n"))

  ld <- readRDS(ziel)
  expect_setequal(names(ld), c("bundesliga", "zweite_bundesliga", "dritte_liga"))
  daten <- lapply(ld, fn(source_module("elo_verlauf"), "elo_verlauf_daten"))

  # Frueh: 18 Vereine nach 3 Spielen, Achse mit Ueberhang
  expect_length(daten$bundesliga$teams, 18)
  expect_identical(daten$bundesliga$achse_spiele_max, 4L)

  # Saisonmitte ueber die Winterpause: eine Luecke von mehr als 18 Tagen
  tage <- unique(unlist(lapply(daten$zweite_bundesliga$teams, function(t) {
    vapply(t$punkte[-1], function(p) p$datum, "")
  })))
  expect_gt(max(as.numeric(diff(sort(as.Date(tage))))), 18)

  # 20er-Liga mit Nachholspiel und einem gewerteten Spiel
  expect_length(daten$dritte_liga$teams, 20)
  nachhol <- unlist(lapply(daten$dritte_liga$teams, function(t) {
    vapply(t$punkte[-1], function(p) p$nachhol, logical(1))
  }))
  expect_true(any(nachhol))
  expect_true("AWD" %in% ld$dritte_liga$matches$status)

  expect_true(all(vapply(daten, function(d) d$saison_laeuft, logical(1))))
})
```

- [ ] **Step 4: Rot prüfen**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^scripts-")'`
Expected: Der neue `preview_site`-Block FAIL (keine Verlaufsseiten), der `verlauf_fixture`-Block FAIL („noch nicht implementiert“) bzw. SKIP ohne Rust-Server; alle übrigen `scripts-`-Blöcke PASS. `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^waechter")'` PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/verlauf_fixture.R tests/testthat/test-scripts-preview_site.R tests/testthat/test-scripts-verlauf_fixture.R
git commit -m "test(#184): Skripttests fuer Vorschau mit league_data und Fixture-Skript (rot)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Gate: Testfreigabe

- [ ] **Step 1:** Gesamte Suite laufen lassen und festhalten, dass genau die neuen Blöcke rot sind: `Rscript -e 'source("tests/testthat.R")'`.
- [ ] **Step 2:** `git push -u origin feat/184-elo-verlauf`, Draft-PR „ELO-Verlaufsseiten je Liga (#184)“ mit Spec-Link, Liste der neuen Testdateien und dem Hinweis „Tests rot, Testfreigabe erbeten“. PR-Text endet mit `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] **Step 3:** **Stopp.** Christoph prüft und gibt die Tests frei. Änderungswünsche an Tests werden jetzt eingearbeitet, nicht später. Ab der Freigabe sind alle Testdateien eingefroren.

---

## Phase B – Implementierung

### Task B1: `RCode/elo_verlauf.R`

**Files:**
- Modify: `RCode/elo_verlauf.R` (Stub ersetzen)

**Interfaces:**
- Consumes: `league_entry` aus `build_league_page_data()`; `STATUS_ERGEBNIS`, `nachholspiel_markierung()` aus `RCode/league_details.R`
- Produces: `elo_verlauf_saison(kickoff)` → `"JJJJ/jj"` oder `""`; `elo_verlauf_daten(league_entry)` → `list(saison, saison_laeuft, achse_spiele_max, achse_datum_ende, teams)` wie in der Spec, Abschnitt 2, mit Punktfeldern `n, datum, runde, nachhol, gegner, gegner_name, heim, tore_heim, tore_gast, vor, nach, delta, p_sieg, p_remis`

- [ ] **Step 1: Implementierung schreiben** (ersetzt den Stub vollständig)

```r
# ELO-Verlauf je Liga (Issue #184). Spec:
# docs/superpowers/specs/2026-10-10-elo-verlauf-design.md, Abschnitt 2.
#
# Rein: liest nur den league_entry, den build_league_page_data() je Liga baut,
# und formt daraus die Daten der Verlaufsseite. Nichts wird gespeichert --
# /league-details geht in jedem Zyklus die ganze Saison durch und liefert je
# Spiel den ELO-Stand davor und die Verschiebung. Damit ist der Verlauf aus
# dem aktuellen Spielplan vollstaendig rekonstruierbar.

# Nachbardateien relativ zu dieser Datei finden -- Muster wie in
# generate_static_site.R.
.ev_dir <- local({
  d <- NULL
  for (f in rev(sys.frames())) {
    if (!is.null(f$ofile)) {
      d <- dirname(f$ofile)
      break
    }
  }
  if (is.null(d) || is.na(d) || !nzchar(d)) "RCode" else d
})

if (!exists("nachholspiel_markierung", mode = "function") || !exists("STATUS_ERGEBNIS")) {
  source(file.path(.ev_dir, "league_details.R"), local = TRUE)
}

.ev_berliner_tag <- function(x) format(x, "%Y-%m-%d", tz = "Europe/Berlin")

# Saisonangabe aus der fruehesten Anstosszeit: Jahr J -> "J/J+1" zweistellig.
# Bewusst nicht aus SEASON: so stimmt sie auch in der Vorschau mit alter
# Fixture.
elo_verlauf_saison <- function(kickoff) {
  k <- kickoff[!is.na(kickoff)]
  if (length(k) == 0) {
    return("")
  }
  jahr <- as.integer(format(min(k), "%Y", tz = "Europe/Berlin"))
  sprintf("%d/%02d", jahr, (jahr + 1L) %% 100L)
}

elo_verlauf_daten <- function(league_entry) {
  m <- league_entry$matches
  tab <- league_entry$tabelle
  teams <- league_entry$teams

  nachhol <- nachholspiel_markierung(m)
  gespielt <- !is.na(m$played) & m$played
  # Abgesagte Spiele (CANC) werden nie nachgeholt; ohne Ausnahme hielte ein
  # einziges die Saison fuer immer offen.
  saison_laeuft <- any(!(m$status %in% c(STATUS_ERGEBNIS, "CANC")))

  name_von <- stats::setNames(as.character(tab$name), as.character(tab$team_id))
  kuerzel_von <- stats::setNames(as.character(tab$kuerzel), as.character(tab$team_id))
  start_von <- stats::setNames(teams$InitialELO, as.character(teams$TeamID))

  verein <- function(id) {
    sid <- as.character(id)
    start <- unname(start_von[[sid]])
    punkte <- list(list(n = 0L, nach = start))
    zeilen <- which(gespielt & (m$home_id == id | m$away_id == id))
    for (k in seq_along(zeilen)) {
      i <- zeilen[k]
      heim <- m$home_id[i] == id
      gegner <- as.character(if (heim) m$away_id[i] else m$home_id[i])
      vor <- if (heim) m$elo_home_pre[i] else m$elo_away_pre[i]
      delta <- if (heim) m$elo_delta_home[i] else -m$elo_delta_home[i]
      punkte[[k + 1L]] <- list(
        n = k,
        datum = .ev_berliner_tag(m$kickoff[i]),
        runde = as.integer(m$round[i]),
        nachhol = nachhol[i],
        gegner = unname(kuerzel_von[[gegner]]),
        gegner_name = unname(name_von[[gegner]]),
        heim = heim,
        tore_heim = m$goals_home[i],
        tore_gast = m$goals_away[i],
        vor = vor,
        nach = vor + delta,
        delta = delta,
        p_sieg = if (heim) m$p_home_win[i] else m$p_away_win[i],
        p_remis = m$p_draw[i]
      )
    }

    aktuell <- tab$elo[tab$team_id == id]
    ende <- punkte[[length(punkte)]]$nach
    if (abs(ende - aktuell) > 1e-6) {
      stop(sprintf("ELO-Verlauf von %s endet bei %.3f, die Tabelle sagt %.3f",
                   name_von[[sid]], ende, aktuell), call. = FALSE)
    }

    list(id = id, kuerzel = unname(kuerzel_von[[sid]]), name = unname(name_von[[sid]]),
         start = start, aktuell = aktuell, punkte = punkte)
  }

  vereine <- lapply(tab$team_id, verein)
  reihenfolge <- order(-vapply(vereine, function(v) v$aktuell, numeric(1)),
                       vapply(vereine, function(v) v$name, character(1)))
  vereine <- vereine[reihenfolge]

  spiele_max <- max(vapply(vereine, function(v) length(v$punkte) - 1L, integer(1)))
  tage <- .ev_berliner_tag(m$kickoff[gespielt])
  datum_ende <- if (length(tage) == 0) {
    NA_character_
  } else {
    format(as.Date(max(tage)) + if (saison_laeuft) 7L else 0L)
  }

  list(
    saison = elo_verlauf_saison(m$kickoff),
    saison_laeuft = saison_laeuft,
    achse_spiele_max = spiele_max + as.integer(saison_laeuft),
    achse_datum_ende = datum_ende,
    teams = vereine
  )
}
```

Hinweis zu `m$goals_home`: `matches` entsteht in `build_league_page_data()` per `cbind(details, parsed$matches)`; beide tragen `goals_home`. `$` liefert die erste Spalte, also die aus `details` mit dem echten Ergebnis. Das ist gewollt.

- [ ] **Step 2: Tests grün**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^elo_verlauf$")'`
Expected: 13 Blöcke PASS. Schlägt ein Test fehl: Implementierung prüfen; der Test bleibt unverändert (Gate). Bei echtem Widerspruch zwischen Test und Spec: anhalten, Controller fragt Christoph.

- [ ] **Step 3: Lint**

Run: `Rscript -e 'l <- lintr::lint("RCode/elo_verlauf.R"); print(l); quit(status = length(l) > 0)'`
Expected: keine Meldungen.

- [ ] **Step 4: Commit**

```bash
git add RCode/elo_verlauf.R
git commit -m "feat(#184): elo_verlauf_daten -- Verlaufsdaten je Liga aus dem league_entry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B2: Generator – Seiten, Link, Navigation, Asset

**Files:**
- Modify: `RCode/league_views.R` (`verlauf_slug` je Liga)
- Modify: `RCode/generate_static_site.R` (Sourcing, `.nav_html`, `.masthead_html`, `render_league_page`, neue Funktionen, `generate_static_site`, `.copy_assets`)
- Create: `RCode/site_assets/verlauf.js` (Gerüst, B3 füllt es)

**Interfaces:**
- Consumes: `elo_verlauf_daten()` (B1); `.komma()`, `.vorzeichen()` (render_sections.R)
- Produces: `views[[key]]$verlauf_slug`; `.nav_html(current_slug, verlauf_ziele = NULL)`; `.masthead_html(current_slug, verlauf_ziele = NULL)`; `render_league_page(..., verlauf_slug = NULL)`; `.verlauf_je_liga(views, league_data)` → benannte Liste key → Verlaufsdaten; `render_verlauf_tabelle(daten)` → HTML; `render_verlauf_page(view, daten, output_dir, now, mtime, verlauf_ziele)` → Pfad

- [ ] **Step 1: `verlauf_slug` in `RCode/league_views.R`**

In `league_views()` direkt vor dem abschließenden `structure(views, class = "league_views", …)` einfügen:

```r
  # Je Liga eine Verlaufsseite (Issue #184). Die einzige Stelle, an der die
  # Namensregel steht: Die Bundesliga heisst "index", ihre Verlaufsseite soll
  # trotzdem einen sprechenden Namen tragen.
  for (key in names(views)) {
    slug <- views[[key]]$slug
    views[[key]]$verlauf_slug <- if (identical(slug, "index")) {
      "bundesliga-verlauf"
    } else {
      paste0(slug, "-verlauf")
    }
  }
```

- [ ] **Step 2: Sourcing und Navigation in `RCode/generate_static_site.R`**

Nach `source(file.path(.gss_dir, "render_sections.R"), local = TRUE)` ergänzen:

```r
# Verlaufsdaten je Liga (Issue #184).
source(file.path(.gss_dir, "elo_verlauf.R"), local = TRUE)
```

`.nav_html` ersetzen durch:

```r
# `verlauf_ziele`: NULL auf Liga-, Aufstiegs- und Methodikseite. Auf einer
# Verlaufsseite ein benannter Vektor Liga-Slug -> verlauf_slug: Wer in den
# Verlaeufen blaettert und oben eine Liga waehlt, will deren Verlauf sehen
# (Issue #184). Ligen ohne Verlaufsseite fuehren auf ihre Ligaseite.
.nav_html <- function(current_slug, verlauf_ziele = NULL) {
  link <- function(v) {
    label <- htmltools::htmlEscape(v$nav_label)
    ziel <- if (!is.null(verlauf_ziele) && v$slug %in% names(verlauf_ziele)) {
      verlauf_ziele[[v$slug]]
    } else {
      v$slug
    }
    href <- paste0(ziel, ".html")
    if (identical(v$slug, current_slug)) {
      paste0("<a class=\"nav-current\" aria-current=\"page\" href=\"", href,
             "\">", label, "</a>")
    } else {
      paste0("<a href=\"", href, "\">", label, "</a>")
    }
  }
```

(Der Rest der Funktion ab `zeilen <- vapply(.nav_groups(), …` bleibt unverändert.)

`.masthead_html` bekommt den Parameter und reicht ihn durch:

```r
.masthead_html <- function(current_slug, verlauf_ziele = NULL) {
```

und darin `.nav_html(current_slug, verlauf_ziele), "\n",` statt `.nav_html(current_slug), "\n",`.

- [ ] **Step 3: Link auf der Ligaseite**

In `render_league_page` die Signatur um `verlauf_slug = NULL` erweitern:

```r
render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now,
                               league_entry = NULL,
                               view_key = NULL,
                               verlauf_slug = NULL) {
```

Vor `tabelle_html <- …` einfügen:

```r
  # Link zur Verlaufsseite (Issue #184) -- nur, wenn es sie gibt. Der
  # Generator entscheidet das vorab fuer alle Ligen.
  verlauf_link <- if (!is.null(verlauf_slug)) {
    paste0("<p class=\"verlauf-link\"><a href=\"", verlauf_slug,
           ".html\">ELO-Verlauf der Saison ansehen →</a></p>\n")
  } else {
    ""
  }
```

und in `tabelle_html` `"</div>\n", zonen_fussnote, "\n</section>\n"` ersetzen durch `"</div>\n", zonen_fussnote, "\n", verlauf_link, "</section>\n"`.

- [ ] **Step 4: Verlaufsseite rendern** — nach `render_league_page` (vor dem Abschnitt „Phase 5: die Seite …“) einfügen:

```r
# --- ELO-Verlauf je Liga (Issue #184) ---------------------------------------

.VERLAUF_LEAD <- paste0(
  "Jede Linie ist ein Verein, jeder Knick ein Spiel. Die Höhe ist die ",
  "Stärkeschätzung des Modells; sie steigt, wenn ein Verein besser abschneidet, ",
  "als das Modell erwartet hat — und fällt, wenn schlechter. Am rechten Rand ",
  "steht der heutige Stand."
)

# Die Verlaufsdaten aller Ligen, VOR dem Rendern: Die Menge entscheidet ueber
# den Link auf der Ligaseite und ueber die Ziele der Navigation auf den
# Verlaufsseiten. Ohne `matches` (Alt-Fixtures, Tests mit nur einer Tabelle)
# gibt es keinen Verlauf -- still, ohne Warnung. Scheitert die Aufbereitung,
# fehlt nur diese eine Seite; die uebrige Site entsteht.
.verlauf_je_liga <- function(views, league_data) {
  daten <- list()
  for (key in names(views)) {
    entry <- league_data[[key]]
    if (is.null(entry) || is.null(entry$matches)) {
      next
    }
    ergebnis <- tryCatch(elo_verlauf_daten(entry), error = function(e) {
      warning(sprintf("generate_static_site: kein ELO-Verlauf fuer %s: %s",
                      key, conditionMessage(e)), call. = FALSE)
      NULL
    })
    if (!is.null(ergebnis)) {
      daten[[key]] <- ergebnis
    }
  }
  daten
}

# JSON fuer <script type="application/json">: "</" maskiert, damit ein Name
# wie "</script>" das Element nicht schliesst.
.verlauf_json <- function(daten) {
  json <- jsonlite::toJSON(daten, auto_unbox = TRUE, digits = 4, na = "null",
                           null = "null")
  gsub("</", "<\\/", as.character(json), fixed = TRUE)
}

render_verlauf_tabelle <- function(daten) {
  zeilen <- vapply(seq_along(daten$teams), function(i) {
    t <- daten$teams[[i]]
    veraenderung <- round(t$aktuell - t$start, 1)
    klasse <- if (veraenderung > 0) "num dpos" else if (veraenderung < 0) "num dneg" else "num"
    paste0(
      "<tr data-i=\"", i - 1L, "\"><th scope=\"row\">", htmltools::htmlEscape(t$name), "</th>",
      "<td class=\"num\">", .komma(t$start, 1), "</td>",
      "<td class=\"num\">", .komma(t$aktuell, 1), "</td>",
      "<td class=\"", klasse, "\">", .vorzeichen(t$aktuell - t$start, 1), "</td></tr>"
    )
  }, character(1))
  paste0(
    "<table class=\"verlauf-tab\" id=\"verlauf-tab\">\n",
    "<thead><tr><th scope=\"col\">Verein</th>",
    "<th scope=\"col\" class=\"num\">ELO Saisonbeginn</th>",
    "<th scope=\"col\" class=\"num\">ELO heute</th>",
    "<th scope=\"col\" class=\"num\">Veränderung</th></tr></thead>\n",
    "<tbody>\n", paste(zeilen, collapse = "\n"), "\n</tbody>\n</table>"
  )
}

render_verlauf_page <- function(view, daten, output_dir, now = Sys.time(),
                                mtime = now, verlauf_ziele = NULL) {
  .copy_assets(output_dir)
  daten$liga <- view$nav_label
  label <- htmltools::htmlEscape(view$nav_label)
  titel <- trimws(paste("ELO-Verlauf", view$nav_label, daten$saison))
  gespielt <- any(vapply(daten$teams, function(t) length(t$punkte) > 1L, logical(1)))

  diagramm <- if (gespielt) {
    paste0(
      "<div class=\"chartcard\">\n",
      "<div class=\"chartbar\">\n",
      "<div class=\"modes\" role=\"group\" aria-label=\"Darstellung der Zeitachse\">",
      "<button type=\"button\" data-mode=\"spiel\" aria-pressed=\"true\">Nach Spielen</button>",
      "<button type=\"button\" data-mode=\"datum\" aria-pressed=\"false\">Nach Datum</button>",
      "</div>\n",
      "<p class=\"legend\">Auf eine Linie zeigen oder tippen, um einen Verein zu verfolgen. ",
      "Gewählt wird das zuletzt gespielte Spiel links vom Zeiger.</p>\n",
      "</div>\n",
      "<div class=\"chartbox\" id=\"verlauf-box\">",
      "<div class=\"tip\" id=\"verlauf-tip\" role=\"status\" aria-live=\"polite\"></div>",
      "<noscript><p class=\"legend\">Das Diagramm braucht JavaScript; die Tabelle unten ",
      "zeigt die Zahlen.</p></noscript></div>\n",
      "</div>\n"
    )
  } else {
    "<p class=\"sectionlead\" id=\"verlauf-leer\">Die Saison hat noch nicht begonnen.</p>\n"
  }

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    .head_html(paste("ELO-Verlauf", view$nav_label)),
    "</head>\n<body>\n<div class=\"wrap\">\n",
    .masthead_html(view$slug, verlauf_ziele), "\n",
    .stale_banner_html(), "\n",
    "<p class=\"zurueck\"><a href=\"", view$slug, ".html\">← Prognose ", label, "</a></p>\n",
    "<section id=\"verlauf\">\n",
    "<p class=\"eyebrow\">ELO-Verlauf</p>\n",
    "<h2>", htmltools::htmlEscape(titel), "</h2>\n",
    "<p class=\"sectionlead\">", .VERLAUF_LEAD, "</p>\n",
    diagramm,
    "<p class=\"hinweis\">Die Kurven entstehen aus denselben Spielen und demselben Modell ",
    "wie die Prognose. Wie das Modell aus einem Ergebnis eine neue Stärkeschätzung macht, ",
    "steht unter <a href=\"methodik.html\">Methodik</a>.</p>\n",
    "</section>\n",
    "<section id=\"verlauf-tabelle\">\n",
    "<p class=\"eyebrow\">Tabelle</p>\n",
    "<h2>Stärkeschätzung heute</h2>\n",
    "<p class=\"sectionlead\">Sortiert nach der heutigen Stärkeschätzung, nicht nach ",
    "Punkten. Eine Zeile anzuwählen hebt die Linie im Diagramm hervor.</p>\n",
    "<div class=\"scroll\">", render_verlauf_tabelle(daten), "</div>\n",
    "</section>\n",
    .footer_html(mtime), "\n",
    "<script type=\"application/json\" id=\"verlauf-daten\">", .verlauf_json(daten), "</script>\n",
    .stale_script, "\n",
    "<script src=\"assets/verlauf.js\"></script>\n",
    "</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$verlauf_slug, ".html"))
  .write_atomically(html, out_path)
  invisible(out_path)
}
```

- [ ] **Step 5: Verdrahtung in `generate_static_site()`**

Nach `views <- views[renderbar]` einfügen:

```r
  # ELO-Verlauf (Issue #184): erst die Daten aller Ligen, dann rendern --
  # die Menge steuert Link und Navigationsziele.
  verlauf <- .verlauf_je_liga(views, league_data)
  verlauf_ziele <- vapply(names(verlauf), function(k) views[[k]]$verlauf_slug, character(1))
  names(verlauf_ziele) <- vapply(names(verlauf), function(k) views[[k]]$slug, character(1))
```

Im `league_paths`-Aufruf `render_league_page(...)` um `verlauf_slug = if (key %in% names(verlauf)) view$verlauf_slug else NULL` ergänzen. Nach `league_paths` einfügen:

```r
  verlauf_paths <- vapply(names(verlauf), function(key) {
    view <- views[[key]]
    message(sprintf("generate_static_site: rendering %s", view$verlauf_slug))
    render_verlauf_page(view, verlauf[[key]], output_dir, now = now, mtime = now,
                        verlauf_ziele = verlauf_ziele)
  }, character(1))
```

und `paths <- c(unname(league_paths), unname(verlauf_paths), aufstiegs_path, methodik_path)`.

- [ ] **Step 6: Asset kopieren und Gerüst anlegen**

In `.copy_assets` nach der `favicon.svg`-Kopie:

```r
  file.copy(file.path(src_dir, "verlauf.js"), file.path(assets_dir, "verlauf.js"),
            overwrite = TRUE)
```

Kommentar über `.copy_assets` auf `# Copies site.css, verlauf.js, fonts/*.woff2 and favicon.svg …` anpassen. Gerüst `RCode/site_assets/verlauf.js` (B3 ersetzt es):

```js
// ELO-Verlauf je Liga (Issue #184). Geruest; die Zeichnung folgt in Task B3.
(function () {
  "use strict";
})();
```

- [ ] **Step 7: Tests grün (R-Seite)**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site")'` und `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^league_views$")'`
Expected: `generate_static_site-verlauf` alle Blöcke PASS, `league_views` PASS, alle bestehenden `generate_static_site*`-Blöcke PASS. `generate_static_site-verlauf-js` darf noch FAIL sein (Gerüst, B3).

- [ ] **Step 8: Lint und Commit**

Run: `Rscript -e 'l <- lintr::lint_dir("RCode"); print(l); quit(status = length(l) > 0)'` → keine Meldungen.

```bash
git add RCode/league_views.R RCode/generate_static_site.R RCode/site_assets/verlauf.js
git commit -m "feat(#184): Verlaufsseiten je Liga, Link auf der Ligaseite, Navigation im Verlauf

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B3: Zeichenskript und Gestaltung

**Files:**
- Modify: `RCode/site_assets/verlauf.js` (Gerüst ersetzen)
- Modify: `RCode/site_assets/site.css` (zwei Tokens im `:root`-Block, Verlaufsabschnitt am Dateiende)

**Interfaces:**
- Consumes: JSON-Felder aus B1/B2 (`liga, saison, saison_laeuft, achse_spiele_max, achse_datum_ende, teams[].{id,kuerzel,name,start,aktuell,punkte[]}`), HTML-IDs aus B2
- Produces: `window.eloVerlauf = { modus(m), waehle(i), zeigeSpiel(i, n), loesche() }`; SVG-Struktur laut A3

Gestaltungsmaßstab ist `docs/designs/elo-verlauf-2bl-2024-25.html` (im Browser öffnen und beim Arbeiten danebenlegen) und der Abschnitt „Gestaltungsanspruch“ der Spec. Seitenweite Typografie (`h2`, `.eyebrow`, `.sectionlead`, `section`) kommt aus `site.css` und wird **nicht** überschrieben; neu sind nur diagrammspezifische Regeln.

- [ ] **Step 1: `RCode/site_assets/verlauf.js` schreiben**

```js
// ELO-Verlauf je Liga (Issue #184). Zeichnet aus #verlauf-daten ein SVG mit
// einer Linie je Verein. Vorlage: docs/designs/elo-verlauf-2bl-2024-25.html
// (Entwurf 8.9.2026); Spec docs/superpowers/specs/2026-10-10-elo-verlauf-design.md.
//
// Gestaltung nach Tufte: alle Linien leise grau, genau eine hervorgehoben;
// direkte Beschriftung an den Linienenden statt Legende; wenige Hilfslinien.
(function () {
  "use strict";
  const datenEl = document.getElementById("verlauf-daten");
  const box = document.getElementById("verlauf-box");
  if (!datenEl || !box) return;

  const DATEN = JSON.parse(datenEl.textContent);
  const teams = DATEN.teams;
  const tip = document.getElementById("verlauf-tip");

  const W = 1080, H = 640, M = { t: 16, r: 80, b: 26, l: 52 };
  const INNEN = W - M.l - M.r;
  const TAG_MS = 864e5;
  const ABSTAND = 12.5;
  const PAUSE_MIN_TAGE = 18;
  const MON = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."];
  const TAG = ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."];
  let modus = "spiel";
  let aktiv = null;

  // --- Skalen ---------------------------------------------------------------
  const alleElo = teams.flatMap((t) => t.punkte.map((p) => p.nach));
  const eloMin = Math.min(...alleElo), eloMax = Math.max(...alleElo);
  const pad = Math.max((eloMax - eloMin) * 0.06, 10);
  const y = (v) => M.t + (H - M.t - M.b) * (1 - (v - (eloMin - pad)) / (eloMax + pad - (eloMin - pad)));

  const tag = (d) => new Date(d + "T12:00:00Z").getTime();
  const alleTage = [...new Set(teams.flatMap((t) => t.punkte.filter((p) => p.datum).map((p) => p.datum)))].sort();
  // Saisonstart-Punkt (n = 0) liegt eine Woche vor dem ersten Spiel.
  const tStart = alleTage.length ? tag(alleTage[0]) - 7 * TAG_MS : 0;
  const tEnde = DATEN.achse_datum_ende ? tag(DATEN.achse_datum_ende) : tStart + TAG_MS;
  const xDatum = (t) => M.l + INNEN * ((t - tStart) / (tEnde - tStart));
  const xOf = (p) => (modus === "spiel"
    ? M.l + INNEN * (p.n / DATEN.achse_spiele_max)
    : xDatum(p.datum ? tag(p.datum) : tStart));

  // Winterpause: groesste Luecke zwischen aufeinanderfolgenden Spieltagen.
  let pause = null;
  for (let i = 1; i < alleTage.length; i++) {
    const a = tag(alleTage[i - 1]), b = tag(alleTage[i]);
    if (!pause || b - a > pause.d) pause = { a, b, d: b - a };
  }
  const pauseSichtbar = () => modus === "datum" && pause !== null && pause.d > PAUSE_MIN_TAGE * TAG_MS;

  // --- Formate --------------------------------------------------------------
  const nz1 = (n) => n.toFixed(1).replace(".", ",");
  const vz = (n) => {
    const r = Math.round(n * 10) / 10;
    return (r > 0 ? "+" : r < 0 ? "−" : "±") + nz1(Math.abs(r));
  };
  const pct = (x) => String(Math.round(x * 100));
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const fmtDatum = (iso) => {
    const d = new Date(iso + "T12:00:00Z");
    return TAG[d.getUTCDay()] + " " + d.getUTCDate() + ". " + MON[d.getUTCMonth()] + " " + d.getUTCFullYear();
  };

  // --- Zeichnen -------------------------------------------------------------
  function zeichne() {
    const titel = `ELO-Verlauf aller ${teams.length} Vereine – ${DATEN.liga} ${DATEN.saison}`;
    let s = `<svg class="verlauf" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(titel)}">`;

    if (pauseSichtbar()) {
      const xa = xDatum(pause.a), xb = xDatum(pause.b);
      s += `<rect class="pause" x="${xa.toFixed(1)}" y="${M.t}" width="${(xb - xa).toFixed(1)}" height="${H - M.t - M.b}"/>`;
      s += `<text class="pauselabel" x="${((xa + xb) / 2).toFixed(1)}" y="${M.t + 12}" text-anchor="middle">Winterpause</text>`;
    }

    // Wenige waagerechte Hilfslinien im 50er-Schritt.
    const von = Math.ceil((eloMin - pad) / 50) * 50, bis = Math.floor((eloMax + pad) / 50) * 50;
    for (let v = von; v <= bis; v += 50) {
      s += `<line class="gridline" x1="${M.l}" y1="${y(v).toFixed(1)}" x2="${W - M.r}" y2="${y(v).toFixed(1)}"/>`;
      s += `<text class="axislabel" x="${M.l - 8}" y="${(y(v) + 3.2).toFixed(1)}" text-anchor="end">${v}</text>`;
    }

    const yAchse = H - M.b + 14;
    if (modus === "spiel") {
      const max = DATEN.achse_spiele_max;
      const schritt = max <= 10 ? 1 : 5;
      s += `<text class="axislabel" x="${M.l}" y="${yAchse}" text-anchor="middle">Start</text>`;
      for (let k = schritt; k <= max; k += schritt) {
        s += `<text class="axislabel" x="${(M.l + INNEN * (k / max)).toFixed(1)}" y="${yAchse}" text-anchor="middle">${k}</text>`;
      }
    } else {
      const d0 = new Date(tStart);
      for (let jahr = d0.getUTCFullYear(), m = d0.getUTCMonth(); ;) {
        const t = Date.UTC(jahr, m, 1, 12);
        if (t > tEnde) break;
        const inPause = pauseSichtbar() && t > pause.a && t < pause.b;
        if (t >= tStart && !inPause) {
          s += `<text class="axislabel" x="${xDatum(t).toFixed(1)}" y="${yAchse}" text-anchor="middle">${MON[m]}</text>`;
        }
        m++;
        if (m > 11) { m = 0; jahr++; }
      }
    }

    // Endbeschriftungen entzerren: Etiketten duerfen sich nicht ueberdecken.
    const geo = teams.map((t, ti) => {
      const pts = t.punkte.map((p) => [xOf(p), y(p.nach)]);
      return { ti, pts, ende: pts[pts.length - 1], ly: 0 };
    });
    const sortiert = [...geo].sort((a, b) => a.ende[1] - b.ende[1]);
    sortiert.forEach((g, k) => {
      g.ly = g.ende[1];
      if (k && g.ly < sortiert[k - 1].ly + ABSTAND) g.ly = sortiert[k - 1].ly + ABSTAND;
    });
    const unten = H - M.b - 2;
    for (let k = sortiert.length - 1; k >= 0; k--) {
      if (sortiert[k].ly > unten) sortiert[k].ly = unten;
      if (k < sortiert.length - 1 && sortiert[k].ly > sortiert[k + 1].ly - ABSTAND) {
        sortiert[k].ly = sortiert[k + 1].ly - ABSTAND;
      }
    }

    geo.forEach((g) => {
      const t = teams[g.ti];
      const d = g.pts.map((c, i) => (i ? "L" : "M") + c[0].toFixed(1) + " " + c[1].toFixed(1)).join(" ");
      s += `<g class="team" data-i="${g.ti}">`;
      s += `<path class="linie" d="${d}"/><path class="hit" d="${d}"/>`;
      g.pts.forEach((c, i) => {
        s += `<circle class="punkt" data-p="${i}" cx="${c[0].toFixed(1)}" cy="${c[1].toFixed(1)}" r="2.6"/>`;
      });
      if (Math.abs(g.ly - g.ende[1]) > 1.2) {
        s += `<line class="fuehrung" x1="${(g.ende[0] + 2).toFixed(1)}" y1="${g.ende[1].toFixed(1)}" x2="${(g.ende[0] + 7).toFixed(1)}" y2="${g.ly.toFixed(1)}"/>`;
      }
      s += `<text class="endkuerzel" x="${(g.ende[0] + 9).toFixed(1)}" y="${(g.ly + 3.4).toFixed(1)}">${esc(t.kuerzel)}</text>`;
      s += `<text class="endlabel" x="${(g.ende[0] + 40).toFixed(1)}" y="${(g.ly + 3.4).toFixed(1)}">${Math.round(t.aktuell)}</text>`;
      s += "</g>";
    });
    s += "</svg>";

    const alt = box.querySelector("svg");
    if (alt) alt.remove();
    box.insertAdjacentHTML("afterbegin", s);
    verdrahte();
    if (aktiv !== null) setzeAktiv(aktiv);
  }

  // --- Auswahl und Tooltip ----------------------------------------------------
  function setzeAktiv(i) {
    aktiv = i;
    box.querySelectorAll("g.team").forEach((g) => {
      const an = Number(g.dataset.i) === i;
      g.classList.toggle("on", an);
      g.classList.toggle("dim", i !== null && !an);
      if (an) g.parentNode.appendChild(g);
    });
    document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => {
      tr.classList.toggle("on", Number(tr.dataset.i) === i);
    });
  }

  function loesche() {
    aktiv = null;
    box.querySelectorAll("g.team").forEach((g) => g.classList.remove("on", "dim"));
    box.querySelectorAll(".punkt").forEach((c) => c.classList.remove("aktiv"));
    document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => tr.classList.remove("on"));
    if (tip) tip.classList.remove("show");
  }

  // Linkslastig: das letzte Spiel, dessen x-Position hoechstens am Zeiger liegt.
  function spielAn(t, mx) {
    let best = 0;
    for (let i = 1; i < t.punkte.length; i++) {
      if (xOf(t.punkte[i]) <= mx + 4) best = i; else break;
    }
    return best;
  }

  function zeigeTip(ti, pi) {
    const t = teams[ti], p = t.punkte[pi];
    const svg = box.querySelector("svg");
    if (!tip || !svg || !p || !p.datum) { if (tip) tip.classList.remove("show"); return; }
    const heim = p.heim ? t.name : p.gegner_name, gast = p.heim ? p.gegner_name : t.name;
    tip.innerHTML =
      `<p class="tdate">${fmtDatum(p.datum)} · ${p.runde}. Spieltag${p.nachhol ? " · Nachholspiel" : ""}</p>` +
      `<p class="tpair">${esc(heim)}<span class="dash">–</span>${esc(gast)} ` +
      `<span class="tres">${p.tore_heim}:${p.tore_gast}</span></p>` +
      `<p class="terw">Das Modell gab ${esc(t.kuerzel)} vorher ${pct(p.p_sieg)} % Sieg, ${pct(p.p_remis)} % Remis.</p>` +
      `<p class="telo">ELO ${nz1(p.vor)} → ${nz1(p.nach)} ` +
      `<span class="tdelta ${p.delta >= 0 ? "pos" : "neg"}">${vz(p.delta)}</span></p>`;
    const g = svg.querySelector(`g.team[data-i="${ti}"]`);
    g.querySelectorAll(".punkt").forEach((c) => c.classList.toggle("aktiv", Number(c.dataset.p) === pi));
    const r = svg.getBoundingClientRect(), br = box.getBoundingClientRect();
    const px = xOf(p) * (r.width / W) + (r.left - br.left) + box.scrollLeft;
    const py = y(p.nach) * (r.height / H) + (r.top - br.top);
    tip.classList.add("show");
    const tw = tip.offsetWidth, th = tip.offsetHeight;
    let L = px + 14;
    if (L + tw > box.scrollLeft + br.width - 4) L = px - tw - 14;
    if (L < 2) L = 2;
    let T = py - th - 12;
    if (T < 2) T = py + 16;
    tip.style.left = L + "px";
    tip.style.top = T + "px";
  }

  function zeigerX(svg, e) {
    const r = svg.getBoundingClientRect();
    return r.width ? (e.clientX - r.left) * (W / r.width) : 0;
  }

  function verdrahte() {
    const svg = box.querySelector("svg");
    svg.querySelectorAll("g.team").forEach((g) => {
      const ti = Number(g.dataset.i);
      const hit = g.querySelector(".hit");
      hit.addEventListener("pointermove", (e) => {
        if (e.pointerType === "touch") return;
        setzeAktiv(ti);
        zeigeTip(ti, spielAn(teams[ti], zeigerX(svg, e)));
      });
      hit.addEventListener("pointerleave", (e) => {
        if (e.pointerType !== "touch") loesche();
      });
      // Klick und Antippen: waehlen und Tooltip zeigen; erneut hebt auf.
      hit.addEventListener("click", (e) => {
        if (aktiv === ti && tip && tip.classList.contains("show")) { loesche(); return; }
        setzeAktiv(ti);
        zeigeTip(ti, spielAn(teams[ti], zeigerX(svg, e)));
      });
    });
  }

  // --- Tabelle und Umschalter -----------------------------------------------
  document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => {
    const i = Number(tr.dataset.i);
    tr.addEventListener("mouseenter", () => setzeAktiv(i));
    tr.addEventListener("mouseleave", () => { if (aktiv === i) loesche(); });
    tr.addEventListener("click", () => (aktiv === i ? loesche() : setzeAktiv(i)));
  });

  function setzeModus(m) {
    modus = m;
    document.querySelectorAll("#verlauf .modes button").forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.mode === m));
    });
    if (tip) tip.classList.remove("show");
    zeichne();
  }
  document.querySelectorAll("#verlauf .modes button").forEach((b) => {
    b.addEventListener("click", () => setzeModus(b.dataset.mode));
  });
  window.addEventListener("resize", () => { if (tip) tip.classList.remove("show"); });

  // Schnittstelle: dieselben Funktionen, die die Ereignisse rufen (Tests in
  // jsdom, das kein Layout kennt).
  window.eloVerlauf = {
    modus: setzeModus,
    waehle: (i) => (i === null ? loesche() : setzeAktiv(i)),
    zeigeSpiel: (i, n) => {
      const pi = teams[i].punkte.findIndex((p) => p.n === n);
      setzeAktiv(i);
      zeigeTip(i, pi);
    },
    loesche,
  };

  zeichne();
})();
```

Hinweis: In jsdom liefert `getBoundingClientRect()` Nullen. `zeigerX` fängt die Division ab, `zeigeTip` rechnet dann Position 0. Beides ist im Browser ohne Wirkung.

- [ ] **Step 2: CSS in `RCode/site_assets/site.css`**

Im `:root`-Block hinter `--gruen:#3F7D3A;` ergänzen:

```css
  /* ELO-Verlauf (Issue #184): gedaempfte Kontextlinien und -etiketten,
     sobald eine Linie hervorgehoben ist. */
  --rule-dim:#EDE9DE; --ink-dim:#BDB6A8;
```

Am Dateiende anhängen:

```css
/* ---------- ELO-Verlauf je Liga (Issue #184) ----------
   Vorlage: docs/designs/elo-verlauf-2bl-2024-25.html. Tufte: leise
   Kontextlinien, eine hervorgehobene Linie, direkte Beschriftung. */
.zurueck{font-family:var(--sans);font-size:13px;margin:0 0 28px}
.zurueck a{color:var(--ink-2);text-decoration:none}
.zurueck a:hover{color:var(--ink);text-decoration:underline;text-decoration-color:var(--akzent)}
.verlauf-link{font-family:var(--sans);font-size:13px;margin:14px 0 0}

#verlauf .chartcard{margin-top:28px;position:relative}
#verlauf .chartbar{display:flex;align-items:baseline;gap:18px;flex-wrap:wrap;margin:0 0 14px}
#verlauf .chartbar .legend{margin:0}
#verlauf .modes{display:flex;border:1px solid var(--rule);align-items:stretch}
#verlauf .modes button{all:unset;font-family:var(--sans);font-size:11.5px;font-weight:600;letter-spacing:.04em;
  padding:5px 11px;cursor:pointer;color:var(--ink-3);border-right:1px solid var(--rule)}
#verlauf .modes button:last-child{border-right:none}
#verlauf .modes button[aria-pressed="true"]{background:var(--ink);color:var(--paper)}
#verlauf .modes button:focus-visible{outline:2px solid var(--akzent);outline-offset:-2px}

#verlauf .chartbox{position:relative;overflow-x:auto;overflow-y:hidden}
svg.verlauf{display:block;width:100%;height:auto;touch-action:pan-y}
svg.verlauf text{font-family:var(--mono);font-variant-numeric:tabular-nums}
svg.verlauf .gridline{stroke:var(--rule-soft);stroke-width:.5}
svg.verlauf .axislabel{font-family:var(--sans);font-size:9.5px;fill:var(--ink-3);font-variant-numeric:normal}
svg.verlauf .pause{fill:var(--surface-2)}
svg.verlauf .pauselabel{font-family:var(--sans);font-size:9px;fill:var(--ink-3);font-variant-numeric:normal;
  letter-spacing:.06em;text-transform:uppercase}
svg.verlauf .linie{fill:none;stroke:var(--rule);stroke-width:1;stroke-linejoin:round;stroke-linecap:round;
  transition:stroke .14s ease,stroke-width .14s ease,opacity .14s ease}
svg.verlauf .endlabel{font-size:10.5px;fill:var(--ink-3);transition:fill .14s ease}
svg.verlauf .endkuerzel{font-family:var(--sans);font-size:10.5px;fill:var(--ink-3);font-weight:600;
  font-variant-numeric:normal;transition:fill .14s ease}
svg.verlauf .hit{fill:none;stroke:transparent;stroke-width:11;cursor:pointer}
svg.verlauf .fuehrung{stroke:var(--rule-soft);stroke-width:.5;transition:stroke .14s ease}
svg.verlauf .punkt{fill:var(--tinte);opacity:0;pointer-events:none;transition:opacity .12s ease}
svg.verlauf g.team.on .linie{stroke:var(--tinte);stroke-width:2}
svg.verlauf g.team.on .endlabel{fill:var(--ink);font-weight:600}
svg.verlauf g.team.on .endkuerzel{fill:var(--tinte)}
svg.verlauf g.team.on .fuehrung{stroke:var(--tinte)}
svg.verlauf g.team.on .punkt.aktiv{opacity:1}
svg.verlauf g.team.dim .linie{stroke:var(--rule-soft);opacity:.55}
svg.verlauf g.team.dim .endlabel,svg.verlauf g.team.dim .endkuerzel{fill:var(--ink-dim)}
svg.verlauf g.team.dim .fuehrung{stroke:var(--rule-dim)}

#verlauf .tip{position:absolute;z-index:5;pointer-events:none;opacity:0;transform:translateY(2px);
  transition:opacity .12s ease,transform .12s ease;background:var(--paper);border:1px solid var(--rule);
  padding:9px 12px 10px;max-width:250px;box-shadow:0 1px 2px rgba(21,19,15,.06)}
#verlauf .tip.show{opacity:1;transform:translateY(0)}
#verlauf .tip p{margin:0}
#verlauf .tip .tdate{font-family:var(--sans);font-size:10px;letter-spacing:.08em;text-transform:uppercase;
  color:var(--ink-3);margin:0 0 3px}
#verlauf .tip .tpair{font-family:var(--serif);font-size:15px;margin:0 0 1px;line-height:1.3}
#verlauf .tip .tpair .dash{color:var(--ink-3);padding:0 2px}
#verlauf .tip .tres{font-family:var(--mono);font-size:15px;font-weight:700;font-variant-numeric:tabular-nums}
#verlauf .tip .terw{font-family:var(--sans);font-size:11px;color:var(--ink-3);margin:3px 0 0}
#verlauf .tip .telo{font-family:var(--mono);font-size:12px;font-variant-numeric:tabular-nums;color:var(--ink-2);
  margin:6px 0 0;padding-top:6px;border-top:1px solid var(--rule-soft)}
#verlauf .tip .tdelta.pos{color:var(--tinte);font-weight:700}
#verlauf .tip .tdelta.neg{color:var(--akzent);font-weight:700}

#verlauf .hinweis{font-family:var(--sans);font-size:12.5px;color:var(--ink-2);border-left:2px solid var(--ocker);
  padding:2px 0 2px 14px;margin-top:34px;max-width:66ch;line-height:1.5}

table.verlauf-tab{width:100%;font-size:15px;margin-top:8px}
table.verlauf-tab th[scope=col]{font-family:var(--sans);font-size:11px;font-weight:600;letter-spacing:.1em;
  text-transform:uppercase;color:var(--ink-3);text-align:left;padding:0 10px 7px 0;border-bottom:1px solid var(--ink)}
table.verlauf-tab th.num,table.verlauf-tab td.num{text-align:right}
table.verlauf-tab td{font-family:var(--mono);font-size:13px;font-variant-numeric:tabular-nums;
  padding:6px 10px 6px 0;border-bottom:.5px solid var(--rule-soft)}
table.verlauf-tab th[scope=row]{font-family:var(--serif);font-weight:400;font-size:15px;text-align:left;
  padding:6px 10px 6px 0;border-bottom:.5px solid var(--rule-soft)}
table.verlauf-tab tbody tr{cursor:pointer;transition:background .12s ease}
table.verlauf-tab tbody tr:hover,table.verlauf-tab tbody tr.on{background:var(--surface-2)}
table.verlauf-tab tbody tr.on th[scope=row]{font-weight:600}
table.verlauf-tab .dpos{color:var(--tinte)}
table.verlauf-tab .dneg{color:var(--akzent)}

@media (max-width:760px){
  svg.verlauf{min-width:640px}
  #verlauf .modes button{padding:5px 9px;font-size:11px}
}
```

- [ ] **Step 3: Tests grün**

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^generate_static_site")'`
Expected: alle Blöcke PASS, inkl. `generate_static_site-verlauf-js` (14 Blöcke). Prüfen: `grep -c "</script" RCode/site_assets/verlauf.js` → `0`.

- [ ] **Step 4: Erster Blick im Browser** (Gestaltung ist Teil dieses Tasks, die ausführliche Abnahme folgt in B6)

```bash
Rscript -e 'source("tests/testthat/helper-league-details.R"); source("tests/testthat/helper-source.R"); test_path <- function(...) file.path("tests", "testthat", ...); source("tests/testthat/helper-html.R"); source("tests/testthat/helper-elo-verlauf.R"); d <- "/tmp/vl-b3"; dir.create(d, showWarnings = FALSE); gen <- source_module("generate_static_site"); gen$generate_static_site(ergebnisse = ergebnisse_aus_env(make_data_env()), output_dir = d, league_data = list(bundesliga = verlauf_beispiel(pause_tage = 40)))'
open /tmp/vl-b3/bundesliga-verlauf.html
open docs/designs/elo-verlauf-2bl-2024-25.html
```

Beide Seiten vergleichen: Linienfarben und -stärken, Etiketten, Tooltip, Umschalter, Tabelle. Abweichungen in CSS beheben (nicht in Tests).

- [ ] **Step 5: Commit**

```bash
git add RCode/site_assets/verlauf.js RCode/site_assets/site.css
git commit -m "feat(#184): Zeichenskript und Gestaltung der ELO-Verlaufsseiten

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B4: Vorschau mit league_data und Fixture-Skript

**Files:**
- Modify: `scripts/preview_site.R`
- Modify: `scripts/verlauf_fixture.R` (Stub ersetzen)

**Interfaces:**
- Consumes: `generate_static_site(..., league_data)`, `build_league_page_data(fixtures, teams)` (league_details.R)
- Produces: CLI wie in A4

- [ ] **Step 1: `scripts/preview_site.R`**

Kopfkommentar: Usage-Zeile auf `# Usage: Rscript scripts/preview_site.R [ergebnis.Rds] [output_dir] [league_data.rds]` ändern und ergänzen:

```r
#   league_data.rds  optional: benannte Liste von league_entries wie im
#                 Betrieb (z. B. aus scripts/verlauf_fixture.R). Mit ihr
#                 entstehen Ligatabellen und ELO-Verlaufsseiten (#184).
```

Nach der `output_dir`-Zeile einfügen:

```r
league_data_path <- if (length(args) >= 3) args[[3]] else NULL
```

Den Aufruf `generate_static_site(ergebnisse = ergebnisse, output_dir = output_dir)` ersetzen durch:

```r
league_data <- NULL
if (!is.null(league_data_path)) {
  if (!file.exists(league_data_path)) {
    stop(sprintf("preview_site: league_data-Datei nicht gefunden: %s", league_data_path))
  }
  league_data <- readRDS(league_data_path)
}

generate_static_site(ergebnisse = ergebnisse, output_dir = output_dir,
                     league_data = league_data)
```

- [ ] **Step 2: `scripts/verlauf_fixture.R`**

```r
#!/usr/bin/env Rscript

# Synthetische league_data fuer die Sichtpruefung der ELO-Verlaufsseiten
# (Issue #184). Drei Staende, reproduzierbar (fester Seed):
#   bundesliga         18 Vereine nach 3 Spielen (Saisonauftakt)
#   zweite_bundesliga  18 Vereine nach 20 Spielen ueber die Winterpause
#   dritte_liga        20 Vereine nach 15 Spielen, mit Nachholspiel und einem
#                      am gruenen Tisch gewerteten Spiel
# Die ELO-Spalten kommen aus dem echten /league-details: Der Rust-Server muss
# laufen (RUST_API_URL, Default http://localhost:8080).
#
# Usage: Rscript scripts/verlauf_fixture.R <ziel.rds>
# Danach: Rscript scripts/preview_site.R <Ergebnis.Rds> <out> <ziel.rds>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Aufruf: Rscript scripts/verlauf_fixture.R <ziel.rds>")
}
ziel <- args[[1]]

# Pfad wie in preview_site.R: R kodiert Leerzeichen im --file=-Argument als "~+~".
file_arg <- sub("^--file=", "",
                grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
file_arg <- gsub("~+~", " ", file_arg, fixed = TRUE)
script_dir <- dirname(file_arg)
rcode_dir <- if (length(script_dir) == 1 && nzchar(script_dir)) {
  file.path(dirname(script_dir), "RCode")
} else {
  file.path("RCode")
}
source(file.path(rcode_dir, "league_details.R"))

basis <- Sys.getenv("RUST_API_URL", "http://localhost:8080")
erreichbar <- tryCatch(
  httr::status_code(httr::GET(paste0(basis, "/health"), httr::timeout(5))) == 200,
  error = function(e) FALSE
)
if (!erreichbar) {
  stop(sprintf("verlauf_fixture: Rust-Server unter %s nicht erreichbar -- erst starten", basis))
}

set.seed(184)

# Doppelrunde nach der Kreismethode (gerade Vereinszahl).
spielplan <- function(ids) {
  n <- length(ids)
  rot <- ids
  hin <- vector("list", n - 1)
  for (r in seq_len(n - 1)) {
    paare <- cbind(rot[seq_len(n / 2)], rev(rot)[seq_len(n / 2)])
    if (r %% 2 == 0) paare <- paare[, 2:1, drop = FALSE]
    hin[[r]] <- paare
    rot <- c(rot[1], rot[n], rot[2:(n - 1)])
  }
  c(hin, lapply(hin, function(p) p[, 2:1, drop = FALSE]))
}

# Rundentermine (Sekunden seit Epoche): samstags 13:30 UTC ab `start`,
# woechentlich; ab Runde `pause_ab` weiter ab `nach_pause`.
termine <- function(n_runden, start, pause_ab = Inf, nach_pause = NULL) {
  sek <- function(tag) as.numeric(as.POSIXct(paste(tag, "13:30:00"), tz = "UTC"))
  vapply(seq_len(n_runden), function(r) {
    if (r >= pause_ab) {
      sek(nach_pause) + (r - pause_ab) * 7 * 86400
    } else {
      sek(start) + (r - 1) * 7 * 86400
    }
  }, numeric(1))
}

iso <- function(sekunden) {
  format(as.POSIXct(sekunden, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%S+00:00", tz = "UTC")
}

liga <- function(praefix, n, gespielt, start, id_basis, pause_ab = Inf,
                 nach_pause = NULL, nachhol = FALSE, gewertet = FALSE) {
  ids <- id_basis + seq_len(n)
  kuerzel <- sprintf("%s%02d", praefix, seq_len(n))
  teams <- data.frame(TeamID = ids, ShortText = kuerzel, Promotion = 0,
                      InitialELO = round(stats::rnorm(n, 1450, 90), 1),
                      stringsAsFactors = FALSE)
  runden <- spielplan(ids)
  zeit <- termine(length(runden), start, pause_ab, nach_pause)

  zeilen <- list()
  for (r in seq_along(runden)) {
    for (k in seq_len(nrow(runden[[r]]))) {
      gesp <- r <= gespielt
      zeilen[[length(zeilen) + 1L]] <- data.frame(
        id = length(zeilen) + 1L, sek = zeit[r] + (k %% 3) * 7200, runde = r,
        status = if (gesp) "FT" else "NS",
        home = runden[[r]][k, 1], away = runden[[r]][k, 2],
        gh = if (gesp) stats::rpois(1, 1.6) else NA_real_,
        ga = if (gesp) stats::rpois(1, 1.2) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  df <- do.call(rbind, zeilen)

  if (nachhol) {
    # Ein Spiel aus Runde gespielt-3, nachgeholt am Dienstag nach der letzten
    # gespielten Runde -- also nach dem Beginn spaeterer Spieltage.
    i <- which(df$runde == gespielt - 3)[1]
    df$sek[i] <- zeit[gespielt] + 3 * 86400
  }
  if (gewertet) {
    i <- which(df$runde == 2)[1]
    df$status[i] <- "AWD"
    df$gh[i] <- 3
    df$ga[i] <- 0
  }

  name <- function(id) paste("Verein", kuerzel[match(id, ids)])
  fixtures <- data.frame(row.names = seq_len(nrow(df)))
  fixtures$fixture <- data.frame(id = df$id, date = iso(df$sek))
  fixtures$fixture$status <- data.frame(short = df$status)
  fixtures$league <- data.frame(round = paste("Regular Season -", df$runde))
  fixtures$teams <- data.frame(row.names = seq_len(nrow(df)))
  fixtures$teams$home <- data.frame(id = df$home, name = name(df$home))
  fixtures$teams$away <- data.frame(id = df$away, name = name(df$away))
  fixtures$goals <- data.frame(home = df$gh, away = df$ga)

  entry <- build_league_page_data(fixtures, teams)
  if (is.null(entry)) {
    stop("verlauf_fixture: build_league_page_data lieferte NULL fuer ", praefix)
  }
  entry
}

league_data <- list(
  bundesliga = liga("BL", 18, gespielt = 3, start = "2026-08-22", id_basis = 91000),
  zweite_bundesliga = liga("ZB", 18, gespielt = 20, start = "2026-08-01", id_basis = 92000,
                           pause_ab = 18, nach_pause = "2027-01-23"),
  dritte_liga = liga("DL", 20, gespielt = 15, start = "2026-07-25", id_basis = 93000,
                     nachhol = TRUE, gewertet = TRUE)
)
saveRDS(league_data, ziel)
cat(ziel, "\n", sep = "")
```

- [ ] **Step 3: Tests grün**

Run: Rust-Server lokal starten (siehe `docs/deployment/local-development.md`), dann `Rscript -e 'testthat::test_dir("tests/testthat", filter = "^scripts-")'`
Expected: alle Blöcke PASS (ohne Rust-Server skippt nur `scripts-verlauf_fixture`).

- [ ] **Step 4: Commit**

```bash
git add scripts/preview_site.R scripts/verlauf_fixture.R
git commit -m "feat(#184): Vorschau mit league_data und Fixture-Skript fuer die Sichtpruefung

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B5: Dokumentation

**Files:**
- Modify: `CLAUDE.md` (Architekturpunkt 4, Quick Commands)
- Modify: `docs/architecture/overview.md` (Zeilen 25, 86–90, 178)
- Modify: `docs/deployment/static-site.md` (Zeilen 3 ff., 118, 130)

- [ ] **Step 1: `CLAUDE.md`**

Punkt 4 der Architektur ersetzen durch:

```markdown
4. **Static Site** - self-contained HTML pages rendered by the scheduler into `STATIC_SITE_DIR`, served by Caddy at fussball.csdatascience.de: ten league views, the Regionalliga promotion page, Methodik, and one ELO-Verlauf page per league (`<slug>-verlauf.html`, Bundesliga: `bundesliga-verlauf.html`) — 22 pages in production. Heatmaps are inline HTML; the ELO-Verlauf chart is drawn client-side by `assets/verlauf.js` (#184). `scripts/preview_site.R` renders a local preview from a saved fixture
```

In „Quick Commands“ (R-Block) nach der Zeile mit `preview_site.R` ergänzen:

```r
# Preview including ELO-Verlauf pages (needs the Rust server for the fixture)
# Rscript scripts/verlauf_fixture.R /tmp/ld.rds
# Rscript scripts/preview_site.R ShinyApp/data/Ergebnis.Rds /tmp/site /tmp/ld.rds
```

- [ ] **Step 2: `docs/architecture/overview.md`**

- Zeile 25: `SITE[Static Site<br/>12 HTML pages + assets]` → `SITE[Static Site<br/>22 HTML pages + assets]`
- Abschnitt „4. Static Site“, Satz „… plus the Regionalliga promotion page and Methodik: twelve in total, …“ → „… plus the Regionalliga promotion page, Methodik and one ELO-Verlauf page per league (#184): 22 in total, …“
- Zeile 178: `B --> C[12 HTML Pages + assets]` → `B --> C[22 HTML Pages + assets]`

- [ ] **Step 3: `docs/deployment/static-site.md`**

- Einleitungssatz „renders twelve pages (one per …“ so ergänzen, dass die zehn Verlaufsseiten genannt werden („… twelve pages … plus one ELO-Verlauf page per league, 22 in total“).
- Zeile 118: Kommentar `# 12 HTML + assets/` → `# 22 HTML + assets/`.
- Zeile 130: „renders all twelve current pages“ → „renders all twelve prognosis pages; ELO-Verlauf pages need league data (third argument, see `scripts/verlauf_fixture.R`)“.

- [ ] **Step 4: Prüfen und committen**

Run: `grep -n "twelve\|12 HTML" CLAUDE.md docs/architecture/overview.md docs/deployment/static-site.md`
Expected: keine Treffer mehr, die die Gesamtzahl der Seiten behaupten (Treffer, die ausdrücklich die zwölf Prognoseseiten meinen, sind in Ordnung).

```bash
git add CLAUDE.md docs/architecture/overview.md docs/deployment/static-site.md
git commit -m "docs(#184): Seiteninventar um die ELO-Verlaufsseiten ergaenzt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B6: Gestalterische Abnahme (Controller)

Wird vom Controller in dieser Sitzung mit Chrome durchgeführt, nicht von einem Subagenten.

- [ ] **Step 1: Vorschau erzeugen**

```bash
Rscript scripts/verlauf_fixture.R /tmp/vl-ld.rds
Rscript scripts/preview_site.R ShinyApp/data/Ergebnis.Rds /tmp/vl-site /tmp/vl-ld.rds
```

- [ ] **Step 2: Vergleich neben dem Entwurf** (`docs/designs/elo-verlauf-2bl-2024-25.html`), jeweils beide Achsenmodi, bei 1280 px und 390 px Breite:
  - `bundesliga-verlauf.html` (frühe Saison, 3 Spiele)
  - `2-bundesliga-verlauf.html` (Saisonmitte, Winterpause sichtbar)
  - `3-liga-verlauf.html` (20 Vereine, Nachholspiel im Tooltip)
  - Prüfpunkte: Kontextlinien leise, eine Linie in `--tinte`; Etiketten ohne Überlappung; Hilfslinien sparsam; Tooltip vollständig und im Bild; Umschalter; Tabelle↔Linie; Ruck- und Navigationslinks; Handy: horizontal scrollbar, Tooltip per Antippen.
- [ ] **Step 3: Feinschliff** nur in `site.css`/`verlauf.js` (Tests bleiben unverändert und grün), je Änderung Commit `style(#184): …`.
- [ ] **Step 4: Screenshots** (Entwurf und neue Seite, beide Breiten) für den PR ablegen.

### Abschluss

- [ ] Gesamte Suite: `Rscript -e 'source("tests/testthat.R")'` → grün (Rust- und JS-Skips nur, wo Server bzw. Node fehlen).
- [ ] Lint: `Rscript -e 'l <- lintr::lint_dir("RCode"); print(l); quit(status = length(l) > 0)'` → keine Meldungen.
- [ ] Whole-Branch-Review (opus) gegen Spec und Plan.
- [ ] PR aus Draft holen, Screenshots einfügen, Christoph um gestalterische Abnahme bitten. Ohne seine Abnahme kein Merge.
