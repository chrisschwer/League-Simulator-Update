# Dark Mode: Die Heatmap-Zellen tragen keine Farbe mehr im HTML, sondern
# nur ihren Anteil an der Skala. Das Stylesheet mischt daraus die Farbe --
# hell von Papier zu Tinte, dunkel von dunklem Grund zu hellem Graublau.
# Stuende die Farbe weiter inline, kaeme kein prefers-color-scheme-Block an
# sie heran, und die Heatmap bliebe im Dunkeln ein weisser Kasten.

test_that(".heat_style traegt nur den Skalenwert, keine Farbe", {
  env <- source_module("render_helpers")
  style <- env$.heat_style(0.5)
  expect_false(grepl("rgb(", style, fixed = TRUE))
  expect_false(grepl("#", style, fixed = TRUE))
  expect_match(style, sprintf("--t:%.3f", 0.5^0.6), fixed = TRUE)
})

test_that(".heat_style kippt die Schriftfarbe ab t > 0.52", {
  # Bisher wechselte die Schrift dort auf Weiss; die Schwelle bleibt, nur
  # welche Farbe 'kraeftig' heisst, entscheidet jetzt das Stylesheet.
  env <- source_module("render_helpers")
  unter <- 0.52^(1 / 0.6) - 0.01
  ueber <- 0.52^(1 / 0.6) + 0.01
  expect_match(env$.heat_style(unter), "--hi:0", fixed = TRUE)
  expect_match(env$.heat_style(ueber), "--hi:1", fixed = TRUE)
  expect_match(env$.heat_style(0), "--t:0.000;--hi:0", fixed = TRUE)
  expect_match(env$.heat_style(1), "--t:1.000;--hi:1", fixed = TRUE)
})
