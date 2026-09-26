# Kürzel-Tooltips: Heatmap, Auf-/Abstiegspanels und Aufstiegsseite zeigen
# Teams als Kürzel. Mit der Maus (title) und per Antippen (kleines Skript)
# erscheint der volle Vereinsname.
#
# Die Zuordnung Kürzel -> Name gilt je Liga, nie global: Kürzel sind nur
# innerhalb einer Liga eindeutig (FCH = Heidenheim in der 2. Bundesliga,
# Hansa Rostock in der 3. Liga). Sie stammt aus der Ligatabelle der Seite
# (tabelle$kuerzel -> tabelle$name), damit der Tooltip denselben Namen zeigt
# wie die Tabelle darunter.

# --- Umgekehrt: Ligatabelle zeigt beim Namen das Kuerzel --------------------

test_that("die Ligatabelle zeigt zum Vereinsnamen das Kuerzel als Tooltip", {
  gen <- source_module("generate_static_site")
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
  gen <- source_module("generate_static_site")
  tab <- data.frame(
    platz = 1L, team_id = 1L, name = "FC Alpha", spiele = 0,
    tordifferenz = 0, punkte = 0, elo = 1500, delta_elo = 0,
    stringsAsFactors = FALSE
  )
  html <- gen$render_liga_tabelle(tab)

  expect_match(html, '<th scope="row">FC Alpha</th>', fixed = TRUE)
})
