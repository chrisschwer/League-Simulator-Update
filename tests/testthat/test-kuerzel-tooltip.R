# Kürzel-Tooltips: Heatmap, Auf-/Abstiegspanels und Aufstiegsseite zeigen
# Teams als Kürzel. Mit der Maus (title) und per Antippen (kleines Skript)
# erscheint der volle Vereinsname.
#
# Die Zuordnung Kürzel -> Name gilt je Liga, nie global: Kürzel sind nur
# innerhalb einer Liga eindeutig (FCH = Heidenheim in der 2. Bundesliga,
# Hansa Rostock in der 3. Liga). Sie stammt aus der Ligatabelle der Seite
# (tabelle$kuerzel -> tabelle$name), damit der Tooltip denselben Namen zeigt
# wie die Tabelle darunter.

source_generator <- function() {
  source(test_path("..", "..", "RCode", "generate_static_site.R"), local = TRUE)
  environment()
}

read_html <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

namen <- c(ALP = "FC Alpha", BET = "SV Beta")

mk_matrix <- function(teams, n = length(teams)) {
  m <- matrix(1 / n, nrow = length(teams), ncol = n,
              dimnames = list(teams, as.character(seq_len(n))))
  as.table(m)
}

# --- build_league_page_data: Kürzel in der Tabelle --------------------------

test_that("die Ligatabelle traegt das Kuerzel aus der TeamList (id-Join)", {
  source(test_path("..", "..", "RCode", "league_details.R"), local = TRUE)
  fixtures <- tibble::tibble(
    fixture = list(data.frame(id = 1, date = "2026-08-28T18:30:00+00:00",
                              status = I(list(data.frame(short = "FT"))))),
    league = list(data.frame(round = "Regular Season - 1")),
    teams = list(data.frame(
      home = I(list(data.frame(id = 102, name = "SV Beta"))),
      away = I(list(data.frame(id = 101, name = "FC Alpha")))
    )),
    goals = list(data.frame(home = 1, away = 0))
  )
  teams <- data.frame(TeamID = c(101, 102, 999),
                      ShortText = c("ALP", "BET", "ALP"),
                      Promotion = 0, InitialELO = c(1500, 1500, 1700),
                      stringsAsFactors = FALSE)
  antwort <- '{
    "matches": [
      {"index": 0, "team_home": 2, "team_away": 1, "played": true,
       "goals_home": 1, "goals_away": 0,
       "elo_home_pre": 1500.0, "elo_away_pre": 1500.0,
       "elo_delta_home": 5.0,
       "lambda_home": 1.4, "lambda_away": 1.3,
       "p_home_win": 0.4, "p_draw": 0.3, "p_away_win": 0.3,
       "score_matrix": [[0.5, 0.5], [0.0, 0.0]]}
    ],
    "current_elos": [1495.0, 1505.0],
    "team_names": ["ALP", "BET"]
  }'

  pd <- build_league_page_data(fixtures, teams, fetch_fn = function(...) antwort)

  tab <- pd$tabelle
  expect_equal(tab$kuerzel[tab$team_id == 101], "ALP")
  expect_equal(tab$kuerzel[tab$team_id == 102], "BET")
})

# --- Renderer ---------------------------------------------------------------

test_that("die Heatmap zeigt bei bekanntem Namen ein abbr mit title", {
  gen <- source_generator()
  html <- gen$render_heatmap(mk_matrix(c("ALP", "BET")), namen = namen)

  expect_match(html, '<abbr class="kz" title="FC Alpha" tabindex="0">ALP</abbr>',
               fixed = TRUE)
  expect_match(html, '<abbr class="kz" title="SV Beta" tabindex="0">BET</abbr>',
               fixed = TRUE)
})

test_that("ohne Namen bleibt die Heatmap zeichengleich", {
  gen <- source_generator()
  m <- mk_matrix(c("ALP", "BET"))
  expect_identical(gen$render_heatmap(m, namen = NULL), gen$render_heatmap(m))
  expect_false(grepl("<abbr", gen$render_heatmap(m), fixed = TRUE))
})

test_that("ohne Namen behaelt jede Panelzeile ihr eigenes Kuerzel", {
  gen <- source_generator()
  panel <- list(labels = "Abstieg", computed = TRUE)
  obj <- data.frame(Abstieg = c(0.3, 0.2), row.names = c("ALP", "BET"))
  html <- gen$render_panel_table(obj, panel)

  expect_match(html, '<th scope="row">ALP</th>', fixed = TRUE)
  expect_match(html, '<th scope="row">BET</th>', fixed = TRUE)
})

test_that("ein Kuerzel ohne Namen bleibt schlicht", {
  gen <- source_generator()
  html <- gen$render_heatmap(mk_matrix(c("ALP", "UNB")), namen = namen)

  expect_match(html, '<th scope="row">UNB</th>', fixed = TRUE)
})

test_that("Namen werden im title-Attribut escaped", {
  gen <- source_generator()
  html <- gen$render_heatmap(mk_matrix("ALP"),
                             namen = c(ALP = "A & \"B\" <FC>"))

  expect_match(html, 'title="A &amp; &quot;B&quot; &lt;FC&gt;"', fixed = TRUE)
})

test_that("Platzgruppen-Panels zeigen die Tooltips", {
  gen <- source_generator()
  panel <- list(labels = "Abstieg", groups = cbind(c(2, 2)), filter_cols = 2)
  html <- gen$render_panel_table(mk_matrix(c("ALP", "BET")), panel,
                                 namen = namen)

  expect_match(html, 'title="FC Alpha"', fixed = TRUE)
})

test_that("ganz berechnete Panels zeigen die Tooltips", {
  gen <- source_generator()
  panel <- list(labels = "Abstieg", computed = TRUE)
  obj <- data.frame(Abstieg = c(0.3, 0.2), row.names = c("ALP", "BET"))
  html <- gen$render_panel_table(obj, panel, namen = namen)

  expect_match(html, 'title="SV Beta"', fixed = TRUE)
})

test_that("die Aufstiegstabelle zeigt die Tooltips", {
  gen <- source_generator()
  html <- gen$.aufstiegs_tabelle(
    "Nord", "Regionalliga Nord",
    meister = c(ALP = 0.6, BET = 0.4), aufstieg = c(ALP = 0.3, BET = 0.2),
    quote_zeigen = TRUE, namen = namen
  )

  expect_match(html, 'title="FC Alpha"', fixed = TRUE)
})

# --- Seite ------------------------------------------------------------------

test_that("die Liga-Seite nimmt die Namen aus ihrer eigenen Ligatabelle", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  teams <- paste0("T", 1:18)
  env <- new.env()
  env$Ergebnis <- mk_matrix(teams)
  entry <- list(tabelle = data.frame(
    platz = 1:18, team_id = 1:18, kuerzel = teams,
    name = paste("Verein", 1:18), spiele = 0, tore = 0, gegentore = 0,
    tordifferenz = 0, punkte = 0, elo = 1500, delta_elo = 0,
    stringsAsFactors = FALSE
  ))

  html <- read_html(gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-09-24 20:00", tz = "Europe/Berlin"),
    league_entry = entry
  ))

  # Heatmap und beide Panels: T1 steht mehrfach mit Tooltip auf der Seite.
  treffer <- gregexpr('title="Verein 1" tabindex="0">T1<', html, fixed = TRUE)[[1]]
  expect_gte(length(treffer[treffer > 0]), 2)
  # Das Tipp-Skript ist eingebunden.
  expect_match(html, "abbr.kz", fixed = TRUE)
})

test_that("ohne league_entry gibt es weder Tooltips noch Tipp-Skript", {
  gen <- source_generator()
  out <- withr::local_tempdir()
  env <- new.env()
  env$Ergebnis <- mk_matrix(paste0("T", 1:18))

  html <- read_html(gen$render_league_page(
    gen$league_views()$bundesliga, env, out,
    now = as.POSIXct("2026-09-24 20:00", tz = "Europe/Berlin")
  ))

  expect_false(grepl("<abbr", html, fixed = TRUE))
  expect_false(grepl("abbr.kz", html, fixed = TRUE))
})

test_that("das Stylesheet kennt Kuerzel und Tipp-Label", {
  css <- paste(readLines(test_path("..", "..", "RCode", "site_assets", "site.css")),
               collapse = "\n")
  expect_match(css, "abbr.kz", fixed = TRUE)
  expect_match(css, ".kz-tip", fixed = TRUE)
})

# --- Umgekehrt: Ligatabelle zeigt beim Namen das Kuerzel --------------------

test_that("die Ligatabelle zeigt zum Vereinsnamen das Kuerzel als Tooltip", {
  gen <- source_generator()
  tab <- data.frame(
    platz = 1:2, team_id = 1:2, kuerzel = c("ALP", "BET"),
    name = c("FC Alpha", "A & B"), spiele = 0, tordifferenz = 0, punkte = 0,
    elo = 1500, delta_elo = 0, stringsAsFactors = FALSE
  )
  html <- gen$render_liga_tabelle(tab)

  expect_match(html, '<abbr class="kz" title="ALP" tabindex="0">FC Alpha</abbr>',
               fixed = TRUE)
  expect_match(html, '<abbr class="kz" title="BET" tabindex="0">A &amp; B</abbr>',
               fixed = TRUE)
})

test_that("ohne Kuerzel-Spalte bleibt der Name in der Ligatabelle schlicht", {
  gen <- source_generator()
  tab <- data.frame(
    platz = 1L, team_id = 1L, name = "FC Alpha", spiele = 0,
    tordifferenz = 0, punkte = 0, elo = 1500, delta_elo = 0,
    stringsAsFactors = FALSE
  )
  html <- gen$render_liga_tabelle(tab)

  expect_match(html, '<th scope="row">FC Alpha</th>', fixed = TRUE)
})
