# Static site generation — 30-Punkte-Design (Relaunch, Phase 3).
#
# Renders the three league views plus a Methodik page to self-contained HTML
# pages with an HTML prognosis heatmap (no PNGs). Replaces the shinyapps.io
# deployment: the simulator writes these files after each cycle and any web
# server serves the directory.

suppressPackageStartupMessages({
  library(htmltools)
})

# Resolve sibling modules relative to this file so the generator works from any
# working directory. source() records the file being sourced as `ofile` in its
# own frame; walk the call stack from the innermost frame outwards to find it.
.gss_dir <- local({
  d <- NULL
  for (f in rev(sys.frames())) {
    if (!is.null(f$ofile)) {
      d <- dirname(f$ofile)
      break
    }
  }
  if (is.null(d) || is.na(d) || !nzchar(d)) "RCode" else d
})

source(file.path(.gss_dir, "render_helpers.R"), local = TRUE)
source(file.path(.gss_dir, "league_views.R"), local = TRUE)
source(file.path(.gss_dir, "league_registry.R"), local = TRUE)

BLOG_URL <- "http://30punkte.wordpress.com"
SITE_WORDMARK <- "30 Punkte"
SITE_TAGLINE <- paste0(
  "Prognosen für Bundesliga, 2. Bundesliga und 3. Liga ",
  "— nach jedem Spiel neu gerechnet."
)
STALE_THRESHOLD_HOURS <- 24

# The four nav destinations, in display order. Methodik has no league_views()
# entry of its own (it carries no panels/heatmap), so it is appended as a
# fixed entry after the league slugs/labels derived from league_views().
.nav_items <- function() {
  league_items <- lapply(league_views(), function(v) {
    list(slug = v$slug, nav_label = v$nav_label)
  })
  names(league_items) <- NULL
  c(league_items, list(list(slug = "methodik", nav_label = "Methodik")))
}

# Die Ligen nach nav_group gebuendelt, in Registry-Reihenfolge.
#
# Zehn Ligen sprengen die flache "·"-Zeile. Die Gruppe steht als Label vor
# ihrer Zeile ("Herren  Bundesliga · 2. Bundesliga · 3. Liga"), Methodik
# bleibt eigenstaendig -- sie ist keine Liga.
.nav_groups <- function() {
  reg <- league_registry()
  views <- league_views()

  gruppen <- list()
  hinzu <- function(gruppen, grp, eintrag) {
    if (is.null(grp)) grp <- ""
    if (is.null(gruppen[[grp]])) {
      gruppen[[grp]] <- list(group = grp, items = list(eintrag))
    } else {
      gruppen[[grp]]$items <- c(gruppen[[grp]]$items, list(eintrag))
    }
    gruppen
  }

  for (key in names(views)) {
    gruppen <- hinzu(gruppen, reg[[key]]$nav_group,
                     list(slug = views[[key]]$slug,
                          nav_label = views[[key]]$nav_label))
  }

  # Die Aufstiegsseite ist keine Liga und steht deshalb nicht in der Registry;
  # ihre Gruppe traegt sie selbst. Sie kommt NACH den Staffeln: Sie fasst sie
  # zusammen, sie leitet sie nicht ein.
  aufstieg <- .aufstiegsseite_view()
  gruppen <- hinzu(gruppen, aufstieg$nav_group,
                   list(slug = aufstieg$slug, nav_label = aufstieg$nav_label))

  unname(gruppen)
}

# Die Ansicht der Aufstiegsseite. Ueber league_views() nachgeschlagen, damit
# es nur eine Quelle gibt -- sie steht dort neben der Ligaliste, nicht darin.
.AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

.aufstiegsseite_view <- function() {
  league_views()[[.AUFSTIEGSSEITE_SLUG]]
}

footer_timestamp <- function(mtime) {
  lt <- as.POSIXlt(mtime, tz = "Europe/Berlin")
  # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
  tzlabel <- if (lt$isdst > 0) "MESZ" else "MEZ"
  paste0("Letztes Update: ", format(lt, "%d.%m.%Y %H:%M"), " ", tzlabel)
}

iso_utc <- function(t) {
  format(as.POSIXct(t), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# ---------------------------------------------------------------------------
# Heatmap cell colour: white -> tinte (#1F3A4D), t = p^0.6 so low
# probabilities stay legible instead of washing out linearly. Text flips to
# white once the tile is dark enough (t > 0.52).
# ---------------------------------------------------------------------------

.HEAT_INK <- c(0x1F, 0x3A, 0x4D)
.HEAT_PAPER <- c(255, 255, 255)

.heat_style <- function(p) {
  t <- p^0.6
  rgb <- round(.HEAT_PAPER + (.HEAT_INK - .HEAT_PAPER) * t)
  text_colour <- if (t > 0.52) "#FFFFFF" else "#15130F"
  sprintf("background:rgb(%d,%d,%d);color:%s", rgb[1], rgb[2], rgb[3], text_colour)
}

# One heatmap <td> for probability p, in team-row order (columns = places).
.heatmap_cell <- function(p) {
  if (p <= 0) {
    return(paste0("<td style=\"", .heat_style(0), "\"></td>"))
  }
  label <- prozent(p)
  cell_html <- if (identical(label, "<1")) {
    "<span class=\"lt1\">&lt;1</span>"
  } else {
    htmltools::htmlEscape(as.character(label))
  }
  paste0("<td style=\"", .heat_style(p), "\">", cell_html, "</td>")
}

render_heatmap <- function(result) {
  n <- ncol(result)
  header <- paste0(
    "<thead><tr><th scope=\"col\">Team</th>",
    paste0("<th scope=\"col\">", seq_len(n), "</th>", collapse = ""),
    "</tr></thead>"
  )

  rows <- vapply(seq_len(nrow(result)), function(i) {
    cells <- paste0(vapply(seq_len(n), function(j) .heatmap_cell(result[i, j]),
                           character(1)), collapse = "")
    paste0("<tr><th scope=\"row\">",
          htmltools::htmlEscape(rownames(result)[i]), "</th>", cells, "</tr>")
  }, character(1))

  paste0(
    "<table class=\"heatmap\" aria-label=\"Wahrscheinlichkeit je Endplatz\">\n",
    "<colgroup><col class=\"teamcol\"><col span=\"", n, "\"></colgroup>\n",
    header, "\n<tbody>", paste0(rows, collapse = ""), "</tbody></table>"
  )
}

# Loest Panel-Grenzen gegen die tatsaechliche Ligagroesse auf.
#
# Positive Werte sind absolute Plaetze und bleiben, wie sie sind. NEGATIVE
# zaehlen von unten: -1 ist der letzte Platz, -2 der vorletzte. Damit
# beschreibt ein Abstiegspanel "die letzten beiden" unabhaengig davon, ob die
# Liga 12, 14 oder 20 Teams hat -- die Frauen-Bundesliga ist 2025 von 12 auf
# 14 gewachsen, feste Indizes waeren stillschweigend falsch geworden.
#
# ACHTUNG: Die Aufloesung MUSS vor jeder Indizierung passieren. R liest
# negative Indizes als AUSSCHLUSS -- `data[, c(-2, -1)]` liefert alle Spalten
# AUSSER den ersten beiden. Das Panel rendert dann klaglos und zeigt die
# Summe der falschen Spalten (86 % statt 14 % bei 14 gleichverteilten
# Plaetzen).
.resolve_bounds <- function(bounds, n) {
  ifelse(bounds < 0, n + 1 + bounds, bounds)
}

# `computed` je Spalte, aufgefuellt auf die Zahl der Labels.
#
# Fehlt das Feld, ist nichts berechnet -- das ist der Zustand aller Ligen vor
# Phase 5 und bleibt der Default. Ein einzelnes TRUE gilt fuer alle Spalten
# (so schreibt sich das ganz berechnete Abstiegspanel der Regionalligen),
# ein Vektor traegt einen Eintrag je Label.
.panel_computed <- function(panel) {
  if (is.null(panel$computed)) {
    return(rep(FALSE, length(panel$labels)))
  }
  rep_len(as.logical(panel$computed), length(panel$labels))
}

# Die berechneten Spalten eines Panels als Matrix, Zeilen = Teams.
#
# Sie werden UNVERAENDERT durchgereicht: Es sind fertige Wahrscheinlichkeiten
# je Team (rl_abstiegsprognose(), rl_aufstiegsprognose()), keine Platzspalten,
# die sich summieren liessen. Wer sie ueber ein Platzband ausrechnen wollte,
# muesste eine Zahl von Abstiegsplaetzen behaupten, die das Modell nicht kennt.
#
# Zugeordnet wird ueber die SPALTENNAMEN, nicht ueber die Position: Die Spalten
# heissen wie die Labels ("Abstieg", "Relegation", "Aufstieg"). Eine
# Positionszuordnung stellte bei Bayern Relegation und Abstieg lautlos um.
.computed_spalten <- function(obj, labels, wo) {
  df <- as.data.frame(obj)
  fehlend <- setdiff(labels, colnames(df))
  if (length(fehlend)) {
    stop(sprintf(
      paste0(
        "%s: die berechnete Spalte(n) %s fehlt/fehlen im Objekt (vorhanden: ",
        "%s). Ohne sie stuende die falsche Zahl unter der Ueberschrift."
      ),
      wo, paste(fehlend, collapse = ", "),
      paste(colnames(df), collapse = ", ")
    ), call. = FALSE)
  }
  m <- as.matrix(df[, labels, drop = FALSE])
  rownames(m) <- rownames(df)
  m
}

#' Rendert ein Panel als Tabelle.
#'
#' @param data_obj Prognosematrix (Teams x Plaetze) fuer die Platzgruppen des
#'   Panels; bei einem ganz berechneten Panel das fertige Objekt.
#' @param panel Der `top`/`bottom`-Eintrag aus league_views().
#' @param computed_obj Objekt fuer die berechneten Spalten eines GEMISCHTEN
#'   Panels (`computed_source`). Bei einem ganz berechneten Panel unnoetig --
#'   dort ist `data_obj` bereits das fertige Objekt.
render_panel_table <- function(data_obj, panel, computed_obj = NULL) {
  computed <- .panel_computed(panel)

  # Ganz berechnetes Panel: keine Platzaufloesung, keine Zeilenfilterung ueber
  # Platzspalten -- es GIBT keine. Die Spalten gehen so hinaus, wie sie
  # hereinkamen.
  if (all(computed)) {
    grouped <- as.data.frame(
      .computed_spalten(data_obj, panel$labels, "render_panel_table")
    )
    return(.panel_html(grouped, panel$labels))
  }

  n <- ncol(data_obj)
  filter_cols <- .resolve_bounds(panel$filter_cols, n)
  groups <- .resolve_bounds(panel$groups, n)

  keep <- rowSums(data_obj[, filter_cols, drop = FALSE]) >= 0.01
  subset_obj <- data_obj[keep, , drop = FALSE]

  if (nrow(subset_obj) == 0) {
    return("")
  }

  # `groups` traegt nur die Platzspalten; die Labels dazu sind die, deren
  # `computed` FALSE ist.
  grouped <- groupResultsDF(subset_obj,
                            labels = panel$labels[!computed],
                            groups = groups)

  # Gemischtes Panel: die berechneten Spalten kommen aus dem zweiten Objekt
  # und werden in die Reihenfolge der Labels eingesetzt. Die Zeilen werden
  # ueber die TEAMNAMEN gezogen, nicht ueber die Position -- das Objekt kommt
  # aus einer anderen Rechnung und muss die Filterung von oben mitmachen.
  if (any(computed)) {
    if (is.null(computed_obj)) {
      stop(sprintf(
        paste0(
          "render_panel_table: das Panel weist %s als berechnet aus, aber es ",
          "wurde kein Objekt dafuer uebergeben (computed_source)."
        ),
        paste(panel$labels[computed], collapse = ", ")
      ), call. = FALSE)
    }
    berechnet <- .computed_spalten(computed_obj, panel$labels[computed],
                                   "render_panel_table")
    fehlend <- setdiff(rownames(grouped), rownames(berechnet))
    if (length(fehlend)) {
      stop(sprintf(
        "render_panel_table: keine berechnete Zeile fuer: %s.",
        paste(fehlend, collapse = ", ")
      ), call. = FALSE)
    }

    voll <- data.frame(matrix(NA_real_, nrow = nrow(grouped),
                              ncol = length(panel$labels)))
    colnames(voll) <- panel$labels
    rownames(voll) <- rownames(grouped)
    voll[, panel$labels[!computed]] <- grouped
    voll[, panel$labels[computed]] <-
      berechnet[rownames(grouped), , drop = FALSE]
    grouped <- voll
  }

  .panel_html(grouped, panel$labels)
}

# Der gemeinsame Ausgabeteil: Prozentformatierung und Markup. Getrennt vom
# Rechenteil, damit der berechnete und der Platzgruppen-Pfad garantiert
# dieselbe Tabelle erzeugen.
.panel_html <- function(grouped, labels) {
  if (nrow(grouped) == 0) {
    return("")
  }

  formatted <- apply(grouped, c(1, 2), prozent)

  # apply() drops to a vector when there is a single label column; restore shape.
  if (is.null(dim(formatted))) {
    formatted <- matrix(formatted, ncol = length(labels),
                        dimnames = list(rownames(grouped), labels))
  }

  cells <- apply(formatted, 1, function(row) {
    paste0("<td>", htmltools::htmlEscape(as.character(row)), "</td>",
           collapse = "")
  })

  rows <- paste0(
    "<tr><th scope=\"row\">",
    htmltools::htmlEscape(rownames(formatted)), "</th>",
    cells, "</tr>",
    collapse = "\n"
  )

  paste0(
    "<table class=\"panel\">\n<thead><tr><th scope=\"col\"></th>",
    paste0("<th scope=\"col\">", htmltools::htmlEscape(labels), "</th>",
          collapse = ""),
    "</tr></thead>\n<tbody>\n", rows, "\n</tbody>\n</table>"
  )
}

.nav_html <- function(current_slug) {
  link <- function(v) {
    label <- htmltools::htmlEscape(v$nav_label)
    href <- paste0(v$slug, ".html")
    if (identical(v$slug, current_slug)) {
      paste0("<a class=\"nav-current\" aria-current=\"page\" href=\"", href,
             "\">", label, "</a>")
    } else {
      paste0("<a href=\"", href, "\">", label, "</a>")
    }
  }

  zeilen <- vapply(.nav_groups(), function(g) {
    links <- vapply(g$items, link, character(1))
    paste0(
      "<div class=\"nav-row\"><span class=\"nav-group\">",
      htmltools::htmlEscape(g$group), "</span>",
      paste(links, collapse = "<span class=\"sep\">·</span>"),
      "</div>"
    )
  }, character(1))

  methodik <- paste0(
    "<div class=\"nav-row\"><span class=\"nav-group\"></span>",
    link(list(slug = "methodik", nav_label = "Methodik")),
    "</div>"
  )

  paste0("<nav aria-label=\"Ligen\">", paste(zeilen, collapse = ""),
         methodik, "</nav>")
}

# The stale banner is decided in the browser, not at render time: a static page
# goes stale precisely when the scheduler has stopped re-rendering it, so a
# server-side check would never fire. The page ships the banner hidden, with
# the generation time in <time datetime>, and a few lines of inline JS reveal
# it once the page is older than STALE_THRESHOLD_HOURS.
.stale_banner_html <- function() {
  # Reuse the wording from app_helpers.R; the hour count is filled in by JS.
  template <- htmltools::htmlEscape(stale_warning_text(STALE_THRESHOLD_HOURS + 1))
  template <- sub(as.character(STALE_THRESHOLD_HOURS + 1),
                  "<span id=\"stale-hours\">?</span>", template, fixed = TRUE)
  paste0("<div class=\"stale\" id=\"stale\" hidden>", template, "</div>")
}

.stale_script <- paste0(
  "<script>\n(function () {\n",
  "  var t = document.getElementById(\"generated\");\n",
  "  if (!t) return;\n",
  "  var age = (Date.now() - Date.parse(t.getAttribute(\"datetime\"))) / 36e5;\n",
  "  if (!(age > ", STALE_THRESHOLD_HOURS, ")) return;\n",
  "  var h = document.getElementById(\"stale-hours\");\n",
  "  if (h) h.textContent = Math.round(age);\n",
  "  var s = document.getElementById(\"stale\");\n",
  "  if (s) s.hidden = false;\n",
  "})();\n</script>"
)

.head_html <- function(title_suffix) {
  title <- paste0("30 Punkte · ", title_suffix)
  paste0(
    "<meta charset=\"utf-8\">\n",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
    "<title>", htmltools::htmlEscape(title), "</title>\n",
    "<meta name=\"description\" content=\"", htmltools::htmlEscape(SITE_TAGLINE),
    "\">\n",
    "<meta property=\"og:title\" content=\"", htmltools::htmlEscape(title),
    "\">\n",
    "<link rel=\"icon\" href=\"assets/favicon.svg\" type=\"image/svg+xml\">\n",
    "<link rel=\"stylesheet\" href=\"assets/site.css\">\n"
  )
}

.masthead_html <- function(current_slug) {
  paste0(
    "<header class=\"mast\">\n",
    "<div class=\"masthead-row\"><div>\n",
    "<h1 class=\"wordmark\">", htmltools::htmlEscape(SITE_WORDMARK), "</h1>\n",
    "<div class=\"mastrule\"></div>\n",
    "<p class=\"tagline\">", htmltools::htmlEscape(SITE_TAGLINE), "</p>\n",
    "</div></div>\n",
    .nav_html(current_slug), "\n",
    "</header>\n"
  )
}

# WORTWAHL: "Mehr dazu unter", nicht "Naehere Infos unter". Die
# Aufstiegsseite darf die Zeichenfolge "Inf" nirgends tragen -- dort steht
# eine Siegquote, deren Nenner null werden kann, und ein durchgerutschtes
# Inf waere auf der Seite ununterscheidbar von diesem Wort. Ein Test prueft
# das maschinell. Eine Ausnahme nur fuer eine Seite haette zwei Fusszeilen
# ergeben, die auseinanderlaufen koennen.
.footer_html <- function(mtime) {
  paste0(
    "<footer>\n",
    "<span>", htmltools::htmlEscape(footer_timestamp(mtime)),
    " <time id=\"generated\" datetime=\"", iso_utc(mtime), "\"></time></span>\n",
    "<span>Mehr dazu unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></span>\n",
    "</footer>\n"
  )
}

render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now,
                               league_entry = NULL) {
  .copy_assets(output_dir)

  result <- get(view$plot_source, envir = data_env)
  heatmap_html <- render_heatmap(result)

  # Ein gemischtes Panel liest aus ZWEI Objekten: die Platzgruppe aus
  # `source`, die berechnete Spalte aus `computed_source`. Fehlt letzteres,
  # bleibt es NULL -- render_panel_table() bricht dann mit dem Namen der
  # Spalte ab, statt eine leere Spalte zu rendern.
  panel_html <- function(panel) {
    computed_obj <- if (!is.null(panel$computed_source)) {
      get(panel$computed_source, envir = data_env)
    } else {
      NULL
    }
    render_panel_table(get(panel$source, envir = data_env), panel,
                       computed_obj = computed_obj)
  }

  top_html <- panel_html(view$top)
  bottom_html <- panel_html(view$bottom)

  tabelle_html <- if (!is.null(league_entry)) {
    paste0(
      "<section id=\"tabelle\">\n",
      "<p class=\"eyebrow\">Tabelle</p>\n",
      "<h2>Ligatabelle und ELO</h2>\n",
      "<p class=\"sectionlead\">Die aktuelle Tabelle, daneben die ELO-Stärkeschätzung ",
      "des Modells und ihre Veränderung seit Saisonbeginn.</p>\n",
      "<div class=\"scroll\">", render_liga_tabelle(league_entry$tabelle),
      "</div>\n</section>\n"
    )
  } else {
    ""
  }
  sort_script <- if (!is.null(league_entry)) .LIGA_SORT_SCRIPT else ""

  rueckblick_html <- if (!is.null(league_entry) &&
                         !is.null(league_entry$rueckblick) &&
                         nrow(league_entry$rueckblick) > 0) {
    render_rueckblick(league_entry$rueckblick, league_entry$spieltag$rueckblick)
  } else {
    ""
  }
  live_html <- if (!is.null(league_entry) &&
                   !is.null(league_entry$live) &&
                   nrow(league_entry$live) > 0) {
    render_live(league_entry$live)
  } else {
    ""
  }
  ausblick_html <- if (!is.null(league_entry) &&
                       !is.null(league_entry$ausblick) &&
                       nrow(league_entry$ausblick) > 0) {
    render_ausblick(league_entry$ausblick, league_entry$spieltag$ausblick)
  } else {
    ""
  }

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    .head_html(view$nav_label),
    "</head>\n<body>\n<div class=\"wrap\">\n",
    .masthead_html(view$slug), "\n",
    .stale_banner_html(), "\n",
    "<section id=\"prognose\">\n",
    "<p class=\"eyebrow\">Prognose</p>\n",
    "<h2>", htmltools::htmlEscape(view$plot_title), "</h2>\n",
    "<p class=\"sectionlead\">10 000 Monte-Carlo-Simulationen des ",
    "Saisonrests. Jede Zeile zeigt, mit welcher Wahrscheinlichkeit ein Team ",
    "auf welchem Platz landet.</p>\n",
    "<div class=\"scroll\">", heatmap_html, "</div>\n",
    "<p class=\"legend\">Angaben in Prozent. Leer = in keiner Simulation ",
    "eingetreten, &lt;1 = unter einem Prozent.",
    "<span class=\"legend-mobile\"> Auf schmalen Bildschirmen stehen Werte ",
    "unter einem Prozent nur als Färbung.</span></p>\n",
    "<div class=\"panels\">\n",
    "<div class=\"scroll\">", top_html, "</div>\n",
    "<div class=\"scroll\">", bottom_html, "</div>\n",
    "</div>\n</section>\n",
    tabelle_html,
    rueckblick_html,
    live_html,
    ausblick_html,
    .footer_html(mtime), "\n",
    .stale_script, "\n",
    sort_script, "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

# --- Phase 5: die Seite "Aufstieg in die 3. Liga" ---------------------------

#' Die Siegquote einer Zeile als Prozenttext.
#'
#' Siegquote = P(Aufstieg) / P(Meister) -- die ueber den Gegner
#' ausintegrierte Zweikampfquote.
#'
#' WO ES KEINE MEISTERCHANCE GIBT, BLEIBT DIE ZELLE LEER. Der Quotient ist
#' dort 0/0, also undefiniert. Eine 0 waere eine Aussage ueber die
#' Spielstaerke ("verliert das Aufstiegsspiel sicher"), die aus den Daten
#' nicht folgt -- das Team erreicht das Spiel ja gar nicht. NaN oder Inf
#' waeren ein sichtbarer Rechenfehler auf einer veroeffentlichten Seite.
#' Dieselbe Konvention wie in der Heatmap, wo eine Null-Zelle leer bleibt.
#'
#' Der Grenzfall P(Aufstieg) > 0 bei P(Meister) = 0 ist rechnerisch
#' unmoeglich und deshalb ein Datenfehler -- auch er bleibt leer, statt eine
#' Unendlichkeit auf die Seite zu bringen.
#' Der Rueckgabewert ist der von prozent() -- also die Zahl, das Haekchen
#' oder "<1" --, nur der undefinierte Fall wird zu "". So bleibt die
#' Formatierung an EINER Stelle; eine eigene Umwandlung in Text hier haette
#' die Sonderfaelle von prozent() ein zweites Mal nachbauen muessen.
.siegquote <- function(aufstieg, meister) {
  if (!is.finite(meister) || !is.finite(aufstieg) || meister <= 0) {
    return("")
  }
  prozent(aufstieg / meister)
}

#' Eine Zeile der Aufstiegstabelle.
#'
#' `quote_zeigen` steuert, ob die Siegquote ueberhaupt eine Groesse ist: Bei
#' den Direktaufsteigern gibt es kein Spiel, das noch zu gewinnen waere --
#' der Quotient ist dann trivial 1 und sagt nichts. Die Zelle bleibt leer,
#' wie ueberall sonst, wo das Modell zu einer Frage nichts weiss.
.aufstiegs_zeile <- function(team, meister, aufstieg, quote_zeigen) {
  quote <- if (quote_zeigen) .siegquote(aufstieg, meister) else ""
  paste0(
    "<tr><th scope=\"row\">", htmltools::htmlEscape(team), "</th>",
    "<td>", htmltools::htmlEscape(as.character(prozent(meister))), "</td>",
    "<td>", htmltools::htmlEscape(as.character(prozent(aufstieg))), "</td>",
    "<td>", htmltools::htmlEscape(quote), "</td></tr>"
  )
}

#' Die Tabelle einer Staffel auf der Aufstiegsseite.
#'
#' `aufstieg` ist der data.frame aus rl_aufstiegsprognose() (rownames = Teams,
#' Spalte "Aufstieg"); `meister` die Meisterspalte der Prognose. Zugeordnet
#' wird ueber die Teamnamen, nicht ueber die Position: beide kommen aus
#' verschiedenen Rechnungen.
#'
#' Nur Teams mit einer Meister- ODER Aufstiegschance stehen in der Tabelle.
#' Achtzehn Zeilen, von denen fuenfzehn "0 0" zeigen, beantworten keine Frage.
.aufstiegs_tabelle <- function(staffel, titel, meister, aufstieg,
                               quote_zeigen) {
  teams <- names(meister)
  zeigen <- meister > 0 | aufstieg[teams] > 0
  teams <- teams[zeigen]

  if (length(teams) == 0) {
    return("")
  }

  zeilen <- vapply(teams, function(team) {
    .aufstiegs_zeile(team, meister[[team]], aufstieg[[team]], quote_zeigen)
  }, character(1))

  paste0(
    "<h3>", htmltools::htmlEscape(titel), "</h3>\n",
    "<div class=\"scroll\"><table class=\"panel\">\n",
    "<thead><tr><th scope=\"col\"></th>",
    "<th scope=\"col\">Meister</th><th scope=\"col\">Aufstieg</th>",
    "<th scope=\"col\">Siegquote</th></tr></thead>\n<tbody>\n",
    paste0(zeilen, collapse = "\n"),
    "\n</tbody>\n</table></div>\n"
  )
}

#' Rendert die Seite "Aufstieg in die 3. Liga".
#'
#' @param view Die Ansicht aus league_views()[["rl-aufstieg"]].
#' @param aufstiegsdaten Benannte Liste je Staffel mit den Elementen
#'   `meister` (benannter Vektor P(Meister)), `aufstieg` (benannter Vektor
#'   P(Aufstieg)) und `playoff` (TRUE, wenn die Staffel die Aufstiegsspiele
#'   bestreitet). Die Zuordnung, WELCHE Staffel das ist, faellt in
#'   aufstiegsmodus() und wird hier nur mitgefuehrt -- der Renderer darf
#'   keine Staffel als Playoff-Staffel verdrahten, sonst waere die Seite ab
#'   der naechsten Rotation lautlos falsch.
.render_aufstiegsseite <- function(view, aufstiegsdaten, output_dir,
                                   now = Sys.time(), mtime = now) {
  .copy_assets(output_dir)

  tabellen <- vapply(view$staffeln, function(staffel) {
    daten <- aufstiegsdaten[[staffel]]
    if (is.null(daten)) {
      return("")
    }
    .aufstiegs_tabelle(staffel, daten$titel, daten$meister, daten$aufstieg,
                       quote_zeigen = isTRUE(daten$playoff))
  }, character(1))

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    .head_html(view$plot_title),
    "</head>\n<body>\n<div class=\"wrap\">\n",
    .masthead_html(view$slug), "\n",
    .stale_banner_html(), "\n",
    "<section id=\"aufstieg\">\n",
    "<p class=\"eyebrow\">Regionalliga</p>\n",
    "<h2>", htmltools::htmlEscape(view$plot_title), "</h2>\n",
    "<p class=\"sectionlead\">Vier Mannschaften steigen in die 3. Liga auf. ",
    "Drei Staffeln stellen ihren Aufsteiger direkt, die beiden uebrigen ",
    "ermitteln den vierten in zwei Aufstiegsspielen gegeneinander. ",
    "<em>Meister</em> ist die Wahrscheinlichkeit, die Staffel zu gewinnen, ",
    "<em>Aufstieg</em> die, danach auch in der 3. Liga zu stehen. Die ",
    "<em>Siegquote</em> ist der Anteil davon, also die Chance in den ",
    "Aufstiegsspielen; wo direkt aufgestiegen wird, gibt es sie nicht.</p>\n",
    paste0(tabellen, collapse = ""),
    "<p class=\"legend\">Angaben in Prozent. Leer = in keiner Simulation ",
    "eingetreten, &lt;1 = unter einem Prozent.</p>\n",
    "</section>\n",
    .footer_html(mtime), "\n",
    .stale_script, "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

.render_methodik_page <- function(output_dir, now = Sys.time(), mtime = now) {
  .copy_assets(output_dir)

  content_path <- file.path(.gss_dir, "site_assets", "methodik_content.html")
  content_lines <- readLines(content_path, warn = FALSE, encoding = "UTF-8")
  # Drop the editorial comment header (the leading <!-- ... --> block) but
  # keep the content untouched otherwise.
  content <- paste(content_lines, collapse = "\n")
  content <- sub("^\\s*<!--.*?-->\\s*", "", content)

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    .head_html("Methodik"),
    "</head>\n<body>\n<div class=\"wrap\">\n",
    .masthead_html("methodik"), "\n",
    .stale_banner_html(), "\n",
    "<section id=\"methodik\">\n",
    "<p class=\"eyebrow\">Methodik</p>\n",
    "<div class=\"prose\">\n", content, "\n</div>\n",
    "</section>\n",
    .footer_html(mtime), "\n",
    .stale_script, "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, "methodik.html")
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

.render_fallback_page <- function(output_dir) {
  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    .head_html("Bundesliga"),
    "</head>\n<body>\n<div class=\"wrap\">\n",
    "<header class=\"mast\">\n<div class=\"masthead-row\"><div>\n",
    "<h1 class=\"wordmark\">", htmltools::htmlEscape(SITE_WORDMARK), "</h1>\n",
    "<div class=\"mastrule\"></div>\n",
    "<p class=\"tagline\">", htmltools::htmlEscape(SITE_TAGLINE), "</p>\n",
    "</div></div>\n</header>\n",
    "<section id=\"prognose\">\n",
    "<h2>Noch keine Prognosedaten verfügbar</h2>\n",
    "<p>Die Simulationsergebnisse wurden noch nicht erzeugt oder konnten ",
    "nicht geladen werden. Bitte versuchen Sie es später erneut.</p>\n",
    "</section>\n",
    "<footer><span>Mehr dazu unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></span></footer>\n",
    "</div>\n</body>\n</html>\n"
  )
  .copy_assets(output_dir)
  out_path <- file.path(output_dir, "index.html")
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

# Copies site.css, fonts/*.woff2 and favicon.svg from RCode/site_assets into
# <output_dir>/assets. Idempotent: safe to call on every page render.
.copy_assets <- function(output_dir) {
  assets_dir <- file.path(output_dir, "assets")
  fonts_dir <- file.path(assets_dir, "fonts")
  dir.create(fonts_dir, recursive = TRUE, showWarnings = FALSE)

  src_dir <- file.path(.gss_dir, "site_assets")
  file.copy(file.path(src_dir, "site.css"), file.path(assets_dir, "site.css"),
           overwrite = TRUE)
  file.copy(file.path(src_dir, "favicon.svg"),
           file.path(assets_dir, "favicon.svg"), overwrite = TRUE)

  font_files <- list.files(file.path(src_dir, "fonts"), pattern = "\\.woff2$",
                           full.names = TRUE)
  file.copy(font_files, fonts_dir, overwrite = TRUE)

  invisible(NULL)
}

#' Rendert die statische Seite.
#'
#' Zwei Aufrufformen, absichtlich in dieser Reihenfolge:
#'
#'  - NEU: `ergebnisse` als benannte Liste, Schluessel = Registry-/
#'    league_views()-Schluessel plus `dritte_liga_aufstieg` fuer den zweiten
#'    Lauf der 3. Liga. Traegt beliebig viele Ligen.
#'  - ALT: die vier Einzelargumente auf Position 1-4.
#'
#' `ergebnisse` steht ans ENDE der Signatur, nicht an den Anfang: Sieben
#' bestehende Aufrufe uebergeben die vier Ergebnisse POSITIONAL. Stuende
#' `ergebnisse` vorn, schluckte es das erste davon -- lautlos, weil beides
#' `table`-Objekte sind.
# Abbildung Registry-Schluessel -> Objektname, den league_views() aufloest.
# Die Namen sind historisch gewachsen (Ergebnis, Ergebnis2, Ergebnis3) und
# stehen als Strings in league_views(); sie bleiben, damit die Renderlogik
# unveraendert bleibt. Fuer neue Ligen gilt die generische Form
# "Ergebnis_<schluessel>".
.ERGEBNIS_OBJEKTNAMEN <- c(
  bundesliga = "Ergebnis",
  zweite_bundesliga = "Ergebnis2",
  dritte_liga = "Ergebnis3",
  dritte_liga_aufstieg = "Ergebnis3_Aufstieg"
)

.ergebnis_objektname <- function(key) {
  # `[[` auf einem benannten Vektor wirft bei unbekanntem Schluessel, statt
  # NULL zu liefern -- deshalb der Mitgliedschaftstest.
  if (key %in% names(.ERGEBNIS_OBJEKTNAMEN)) {
    unname(.ERGEBNIS_OBJEKTNAMEN[[key]])
  } else {
    paste0("Ergebnis_", key)
  }
}

#' Die Zahlen der Aufstiegsseite, je Staffel.
#'
#' Sammelt aus den gerenderten Ligen alles ein, was die Seite braucht: die
#' Meisterspalte der Prognose und die Aufstiegsspalte. Welche Staffel welche
#' hat, ergibt sich aus der VIEW, nicht aus einer Liste von Staffelnamen:
#'
#'   Staffel mit `computed_source` im oberen Panel  -> Aufstiegsspiele, die
#'       Aufstiegsspalte kommt aus dem eigenen Objekt (rl_aufstiegsprognose()).
#'   Staffel ohne                                   -> Direktaufstieg,
#'       P(Aufstieg) = P(Meister), und eine Siegquote gibt es nicht.
#'
#' Damit folgt die Seite der Rotation aus aufstiegsmodus(): Wechselt der
#' dritte Direktplatz die Staffel, aendert sich die View, und die Seite geht
#' mit. Stuenden hier Staffelnamen als Bedingung, waere sie ab der naechsten
#' Rotation lautlos falsch.
#'
#' @param keys Die Registry-Schluessel der gerenderten Ligen.
#' @param data_env Umgebung mit den Ergebnisobjekten.
#' @return Benannte Liste Staffel -> list(titel, meister, aufstieg, playoff).
#'   Leer, wenn keine Regionalliga dabei ist.
.aufstiegsdaten <- function(keys, data_env) {
  reg <- league_registry()
  views <- league_views()

  daten <- list()
  for (key in keys) {
    staffel <- reg[[key]]$staffel
    # Nur die Regionalligen tragen eine Staffel -- die uebrigen Ligen fuehren
    # keinen Aufstieg in die 3. Liga.
    if (is.null(staffel)) {
      next
    }

    view <- views[[key]]
    prognose <- as.matrix(get(view$plot_source, envir = data_env))
    meister <- prognose[, 1L]
    names(meister) <- rownames(prognose)

    quelle <- view$top$computed_source
    if (is.null(quelle)) {
      # Direktaufstieg: beide Groessen fallen zusammen. Kein Umweg ueber ein
      # eigenes Objekt -- er lieferte exakt dieselbe Zahl.
      aufstieg <- meister
      playoff <- FALSE
    } else {
      spalte <- .computed_spalten(get(quelle, envir = data_env), "Aufstieg",
                                  ".aufstiegsdaten")
      aufstieg <- spalte[, "Aufstieg"]
      names(aufstieg) <- rownames(spalte)
      playoff <- TRUE
    }

    fehlend <- setdiff(names(meister), names(aufstieg))
    if (length(fehlend)) {
      stop(sprintf(
        paste0(
          ".aufstiegsdaten: keine Aufstiegswahrscheinlichkeit fuer: %s. Ohne ",
          "sie stuende die Zeile mit einer Meisterchance und ohne Aufstieg da."
        ),
        paste(fehlend, collapse = ", ")
      ), call. = FALSE)
    }

    daten[[staffel]] <- list(
      titel = reg[[key]]$display_name,
      meister = meister,
      aufstieg = aufstieg[names(meister)],
      playoff = playoff
    )
  }
  daten
}

generate_static_site <- function(Ergebnis = NULL, Ergebnis2 = NULL,
                                 Ergebnis3 = NULL,
                                 Ergebnis3_Aufstieg = Ergebnis3,
                                 output_dir = Sys.getenv("STATIC_SITE_DIR",
                                                         "ShinyApp/public"),
                                 now = Sys.time(),
                                 league_data = NULL,
                                 ergebnisse = NULL) {
  # Alte Form in die neue uebersetzen, damit es intern nur einen Pfad gibt.
  if (is.null(ergebnisse)) {
    ergebnisse <- list(
      bundesliga = Ergebnis,
      zweite_bundesliga = Ergebnis2,
      dritte_liga = Ergebnis3,
      dritte_liga_aufstieg =
        if (is.null(Ergebnis3_Aufstieg)) Ergebnis3 else Ergebnis3_Aufstieg
    )
  }

  # Keine Prognose vorhanden -> Fallback-Seite. Frueher pruefte der Guard drei
  # feste Objekte; jetzt zaehlt, ob ueberhaupt Ergebnisse vorliegen.
  vorhanden <- Filter(Negate(is.null), ergebnisse)
  if (length(vorhanden) == 0) {
    message("generate_static_site: no simulation data, writing fallback page")
    return(invisible(.render_fallback_page(output_dir)))
  }

  views <- league_views()

  # Nur Ligen rendern, fuer die Ergebnisse vorliegen. Der Kompatibilitaetspfad
  # (scripts/preview_site.R, aeltere Fixtures) kennt nur die drei Altligen --
  # er soll die Vorschau weiterhin erzeugen, nicht abbrechen.
  #
  # Ein Abbruch bliebe falsch: Faellt im Betrieb die Simulation einer Liga
  # aus, ist eine Seite ohne sie besser als gar keine Seite.
  #
  # `computed_source` zaehlt mit: Bei Nord und Bayern steht die
  # Aufstiegsspalte in einem eigenen Objekt. Fehlte es, riefe
  # render_panel_table() get() auf einen Namen, den data_env nicht kennt --
  # die ganze Seite bliebe aus, statt uebersprungen zu werden.
  vorhandene_objekte <- vapply(names(vorhanden), .ergebnis_objektname,
                               character(1))
  renderbar <- names(views)[vapply(names(views), function(key) {
    quellen <- unique(c(views[[key]]$plot_source,
                        views[[key]]$top$source,
                        views[[key]]$top$computed_source,
                        views[[key]]$bottom$source,
                        views[[key]]$bottom$computed_source))
    all(quellen %in% vorhandene_objekte)
  }, logical(1))]

  if (length(renderbar) == 0) {
    message("generate_static_site: no simulation data, writing fallback page")
    return(invisible(.render_fallback_page(output_dir)))
  }

  uebersprungen <- setdiff(names(views), renderbar)
  if (length(uebersprungen) > 0) {
    message(sprintf(
      "generate_static_site: ohne Ergebnisse, uebersprungen: %s",
      paste(uebersprungen, collapse = ", ")
    ))
  }
  views <- views[renderbar]

  # data_env traegt die Ergebnisse unter den Namen, die league_views() in
  # plot_source/top$source/bottom$source erwartet. Die namensbasierte
  # Aufloesung bleibt unangetastet -- sie traegt die 3.-Liga-Asymmetrie
  # (Aufstiegstabelle aus einem anderen Objekt als Heatmap und Abstieg).
  data_env <- new.env(parent = emptyenv())
  for (key in names(ergebnisse)) {
    assign(.ergebnis_objektname(key), ergebnisse[[key]], envir = data_env)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  league_paths <- vapply(names(views), function(key) {
    view <- views[[key]]
    message(sprintf("generate_static_site: rendering %s", view$slug))
    render_league_page(view, data_env, output_dir, now = now, mtime = now,
                       league_entry = league_data[[key]])
  }, character(1))

  # Die Aufstiegsseite entsteht nur, wenn wenigstens eine Regionalliga
  # gerendert wurde. Ohne Staffeln waere sie eine leere Seite in der
  # Navigation -- schlechter als keine Seite (der Kompatibilitaetspfad
  # rendert weiterhin genau vier Seiten).
  aufstiegsdaten <- .aufstiegsdaten(names(views), data_env)
  aufstiegs_path <- character(0)
  if (length(aufstiegsdaten) > 0) {
    aufstiegs_view <- .aufstiegsseite_view()
    message(sprintf("generate_static_site: rendering %s", aufstiegs_view$slug))
    aufstiegs_path <- .render_aufstiegsseite(aufstiegs_view, aufstiegsdaten,
                                             output_dir, now = now,
                                             mtime = now)
  }

  message("generate_static_site: rendering methodik")
  methodik_path <- .render_methodik_page(output_dir, now = now, mtime = now)

  paths <- c(unname(league_paths), aufstiegs_path, methodik_path)

  message(sprintf("generate_static_site: wrote %d pages to %s",
                  length(paths), output_dir))
  invisible(paths)
}

# --- Phase 4a: Ligatabelle ---------------------------------------------------

# Deutsche Dezimalformatierung: Punkt -> Komma.
.komma <- function(x, digits) {
  sub(".", ",", formatC(x, digits = digits, format = "f", big.mark = ""),
     fixed = TRUE)
}

# Vorzeichenbehaftete Zahl mit U+2212 als Minus (statt Bindestrich) und
# "±0" bei exakt Null. digits = Nachkommastellen (0 für Tordifferenz,
# 1 für Delta-ELO). Das Vorzeichen wird vom GERUNDETEN Wert abgeleitet,
# nicht vom Rohwert: sonst zeigt z.B. -0.04 bei einer Nachkommastelle ein
# "−0,0" statt des korrekten "±0,0", weil der Rohwert negativ ist, der
# angezeigte gerundete Wert aber Null.
.vorzeichen <- function(x, digits) {
  gerundet <- round(x, digits)
  formatted <- .komma(abs(gerundet), digits)
  ifelse(gerundet > 0, paste0("+", formatted),
        ifelse(gerundet < 0, paste0("−", formatted),
              paste0("±", formatted)))
}

render_liga_tabelle <- function(tabelle) {
  header <- paste0(
    "<thead><tr>\n",
    "<th scope=\"col\"><button data-key=\"platz\" data-dir=\"asc\" ",
    "aria-sort=\"ascending\">Platz</button></th>\n",
    "<th scope=\"col\">Team</th>",
    "<th scope=\"col\" class=\"num opt\">Sp.</th>",
    "<th scope=\"col\" class=\"num opt\">Tordiff.</th>\n",
    "<th scope=\"col\"><button data-key=\"pkt\" data-dir=\"desc\">Punkte</button></th>\n",
    "<th scope=\"col\"><button data-key=\"elo\" data-dir=\"desc\">ELO</button></th>\n",
    "<th scope=\"col\" class=\"num\">&Delta; ELO</th>\n",
    "</tr></thead>"
  )

  rows <- vapply(seq_len(nrow(tabelle)), function(i) {
    row <- tabelle[i, ]
    paste0(
      "<tr data-platz=\"", row$platz, "\" data-pkt=\"", row$punkte,
      "\" data-elo=\"", row$elo, "\">",
      "<td class=\"num\">", row$platz, "</td>",
      "<th scope=\"row\">", htmltools::htmlEscape(row$name), "</th>",
      "<td class=\"num opt\">", row$spiele, "</td>",
      "<td class=\"num opt\">", .vorzeichen(row$tordifferenz, 0), "</td>",
      "<td class=\"num\">", row$punkte, "</td>",
      "<td class=\"num\">", .komma(row$elo, 1), "</td>",
      "<td class=\"num\">", .vorzeichen(row$delta_elo, 1), "</td>",
      "</tr>"
    )
  }, character(1))

  paste0(
    "<table class=\"liga\" id=\"ligatabelle\">\n",
    header, "<tbody>", paste0(rows, collapse = ""), "</tbody></table>"
  )
}

.LIGA_SORT_SCRIPT <- paste0(
  "<script>\n(function(){\n",
  "  var table=document.getElementById('ligatabelle');\n",
  "  if(!table)return;\n",
  "  var tbody=table.tBodies[0];\n",
  "  table.querySelectorAll('th button[data-key]').forEach(function(btn){\n",
  "    btn.addEventListener('click',function(){\n",
  "      var key=btn.dataset.key, dir=btn.dataset.dir;\n",
  "      table.querySelectorAll('th button').forEach(function(b){b.removeAttribute('aria-sort')});\n",
  "      btn.setAttribute('aria-sort',dir==='asc'?'ascending':'descending');\n",
  "      var rows=Array.prototype.slice.call(tbody.rows);\n",
  "      rows.sort(function(a,b){\n",
  "        var va=parseFloat(a.dataset[key]),vb=parseFloat(b.dataset[key]);\n",
  "        return dir==='asc'?va-vb:vb-va;\n",
  "      });\n",
  "      rows.forEach(function(r){tbody.appendChild(r)});\n",
  "    });\n",
  "  });\n",
  "})();\n</script>"
)

# --- Phase 4b: Rückblick- und Live-Sektion --------------------------------

.WOCHENTAGE_KURZ <- c("So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa.")

# Anstoßzeit (UTC, wie aus league_details.R) als Berliner Zeit formatiert:
# "Wd. T.M., HH:MM<NNBSP>Uhr" — Tag/Monat ohne führende Null.
.mwhen <- function(kickoff) {
  lt <- as.POSIXlt(kickoff, tz = "Europe/Berlin")
  wd <- .WOCHENTAGE_KURZ[lt$wday + 1]
  tag <- as.integer(format(lt, "%d"))
  monat <- as.integer(format(lt, "%m"))
  zeit <- format(lt, "%H:%M")
  paste0(wd, " ", tag, ".", monat, ".,", " ", zeit, " Uhr")
}

# 1/X/2-Balken: Segmente Heim/Remis/Gast aus den ex-ante-Wahrscheinlichkeiten;
# Remis wird als Rest (100 - Heim - Gast) berechnet, nicht separat gerundet,
# damit die drei Werte immer exakt 100 ergeben (Mock-up-Regel). Segmente
# unter 8 % verlieren ihr Zahlen-Label (bleiben aber als Farbfläche sichtbar).
.oddsbar <- function(p_home, p_draw, p_away) {
  h <- round(100 * p_home)
  a <- round(100 * p_away)
  x <- 100 - h - a

  seg <- function(cls, wert) {
    nolabel <- if (wert < 8) " nolabel" else ""
    paste0("<span class=\"", cls, nolabel, "\" style=\"flex-basis:", wert, "%\">",
          "<i>", wert, "</i></span>")
  }

  aria <- paste0("Sieg Heim ", h, " %, Remis ", x, " %, Sieg Gast ", a, " %")

  paste0(
    "<div class=\"oddsbar\" role=\"img\" aria-label=\"",
    htmltools::htmlEscape(aria), "\">",
    seg("oh", h), seg("ox", x), seg("oa", a),
    "</div>"
  )
}

# ELO-Anpassung als Heim/Gast-Paar; bei NA (Nachholspiele, die noch nicht
# gespielt sind, tauchen hier nicht auf, aber die dritte Rückblick-Zeile im
# Mock-up hat absichtlich NA) auf beiden Seiten ein Halbgeviertstrich, nie
# "NA" im Markup.
.melo <- function(delta_home) {
  if (is.na(delta_home)) {
    return("– / –")
  }
  heim <- .vorzeichen(delta_home, 1)
  gast <- .vorzeichen(-delta_home, 1)
  paste0(heim, " / ", gast)
}

# Überschrift der Rückblick-Sektion: "N. Spieltag" bei einer Runde,
# "N./M. Spieltag" bei mehreren (Rundennummern mit "/" verbunden, ein
# gemeinsamer Punkt am Ende — z.B. "1./2. Spieltag").
.spieltag_ueberschrift <- function(runden) {
  paste0(paste(runden, collapse = "./"), ". Spieltag")
}

# Paarung "Heim – Gast" mit htmltools-Escaping und dem Halbgeviertstrich
# als eigenem Span (fuer CSS-Faerbung). Gemeinsam fuer Rueckblick-, Live- und
# (4c) Ausblick-Zeilen, die alle dieselbe Paarungsdarstellung brauchen.
.match_pair <- function(home_name, away_name) {
  paste0(
    htmltools::htmlEscape(home_name),
    "<span class=\"dash\"> – </span>",
    htmltools::htmlEscape(away_name)
  )
}

# Ergebnis "H:A" (Rueckblick/Live; fuer Live ist es der laufende Zwischenstand).
# NA-Guard (4b-Review-Uebertrag): fehlende Tore -> "–:–" (Halbgeviertstriche),
# nie "NA:NA" im Markup. Betrifft z.B. Live-Zeilen, deren Tore noch nicht
# uebermittelt wurden.
.match_ergebnis <- function(goals_home, goals_away) {
  if (is.na(goals_home) || is.na(goals_away)) {
    return("–:–")
  }
  paste0(goals_home, ":", goals_away)
}

.match_zeile <- function(row) {
  nachhol <- if (isTRUE(row$nachholspiel)) {
    paste0("<span class=\"nachhol\">Nachholspiel, ", row$round, ". Spieltag</span>")
  } else {
    ""
  }

  # Am grünen Tisch gewertete Spiele als solche ausweisen: Das Ergebnis zählt
  # für die Tabelle, wurde aber nicht erspielt -- und die ELO-Spalte bleibt
  # deshalb leer (Issue #157). Ohne Hinweis sähe das wie ein Datenfehler aus.
  wertung <- if (!is.null(row$status) && row$status %in% c("AWD", "WO")) {
    "<span class=\"nachhol\">Wertung</span>"
  } else {
    ""
  }

  paste0(
    "<div class=\"match\">\n",
    "<div class=\"mwhen\">", .mwhen(row$kickoff), "</div>\n",
    "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
    .oddsbar(row$p_home_win, row$p_draw, row$p_away_win), "\n",
    "<div class=\"mres\">", .match_ergebnis(row$goals_home, row$goals_away), "</div>\n",
    "<div class=\"melo\" title=\"ELO-Anpassung Heim / Gast\">",
    .melo(row$elo_delta_home), "</div>\n",
    nachhol,
    wertung,
    "</div>\n"
  )
}

# Rückblick-Sektion: gefensterte, gejointe Spielliste + Spieltagsnummern
# für die Überschrift ("N. Spieltag" bzw. "N./M. Spieltag").
render_rueckblick <- function(rueckblick, runden) {
  zeilen <- vapply(seq_len(nrow(rueckblick)), function(i) {
    .match_zeile(rueckblick[i, ])
  }, character(1))

  paste0(
    "<section id=\"rueckblick\">\n",
    "<p class=\"eyebrow\">Rückblick</p>\n",
    "<h2>", .spieltag_ueberschrift(runden), "</h2>\n",
    "<p class=\"oddslegend\">Balken: Wahrscheinlichkeit vor dem Spiel in Prozent ",
    "—<span class=\"chip h\"></span><b>Sieg Heim</b>",
    "<span class=\"chip x\"></span><b>Remis</b>",
    "<span class=\"chip a\"></span><b>Sieg Gast</b> · rechts: Ergebnis und ",
    "ELO-Anpassung Heim / Gast</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}

# Live-Sektion: Zwischenstände ohne Prognose (Planergänzung 8a);
# leeres Fenster -> "".
render_live <- function(live) {
  if (nrow(live) == 0) {
    return("")
  }

  zeilen <- vapply(seq_len(nrow(live)), function(i) {
    row <- live[i, ]
    paste0(
      "<div class=\"match live\">\n",
      "<div class=\"mwhen\">", .mwhen(row$kickoff), "</div>\n",
      "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
      "<div class=\"mres\">", .match_ergebnis(row$goals_home, row$goals_away), "</div>\n",
      "</div>\n"
    )
  }, character(1))

  paste0(
    "<section id=\"live\">\n",
    "<p class=\"eyebrow\">Live</p>\n",
    "<h2>Laufende Spiele</h2>\n",
    "<p class=\"sectionlead\">Prognosen werden während des Spiels nicht ",
    "aktualisiert.</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}

# --- Phase 4c: Ausblick-Sektion --------------------------------------------

# Deutsche Ein-Nachkommastellen-Prozentzelle für die Ergebnis-Matrix; Werte
# unter 0,1 % (0.001) bleiben leer statt auf "0,0" zu runden.
.score_zelle_text <- function(p) {
  if (p < 0.001) {
    ""
  } else {
    .komma(100 * p, 1)
  }
}

# Eine Ergebnis-Matrix (score_matrix, quadratisch: 0..(n-2) Tore, letzte
# Zeile/Spalte = Restmasse "n-1+") als <table class="score">. Färbung wie im
# Mock-up über .heat_style((p / Zellenmaximum) * 0.75) — die Spitzenzelle
# bekommt so t = 0.75 statt volle Tinte. Anteil wird auf 1 geclamped
# (Rundungsdrift/entartete Matrizen), sonst würde .heat_style() bei > 1
# negative RGB-Kanäle erzeugen (ungültiges CSS, Zelle rendert weiß auf weiß).
.render_score_matrix <- function(m) {
  n <- nrow(m)
  achse <- c(as.character(seq_len(n - 1) - 1), paste0(n - 1, "+"))
  zellenmax <- max(m)

  header <- paste0(
    "<thead><tr><th class=\"corner\"><span>Heim&nbsp;&#8595;&nbsp;&middot;&nbsp;Gast&nbsp;&#8594;</span></th>",
    paste0("<th>", achse, "</th>", collapse = ""),
    "</tr></thead>"
  )

  rows <- vapply(seq_len(n), function(i) {
    cells <- paste0(vapply(seq_len(n), function(j) {
      p <- m[i, j]
      anteil <- if (is.finite(zellenmax) && zellenmax > 0) (p / zellenmax) * 0.75 else 0
      anteil <- min(1, anteil)
      paste0("<td style=\"", .heat_style(anteil), "\">",
             .score_zelle_text(p), "</td>")
    }, character(1)), collapse = "")
    paste0("<tr><th scope=\"row\">", achse[i], "</th>", cells, "</tr>")
  }, character(1))

  paste0(
    "<table class=\"score\" aria-label=\"Wahrscheinlichkeit je Ergebnis in Prozent\">\n",
    header, "\n<tbody>", paste0(rows, collapse = ""), "</tbody></table>"
  )
}

.ausblick_zeile <- function(row) {
  nachhol <- if (isTRUE(row$nachholspiel)) {
    paste0("<span class=\"nachhol\">Nachholspiel, ", row$round, ". Spieltag</span>")
  } else {
    ""
  }

  paste0(
    "<div class=\"match outlook\">\n",
    "<div class=\"mwhen\">", .mwhen(row$kickoff), "</div>\n",
    "<div class=\"mpair\">", .match_pair(row$home_name, row$away_name), "</div>\n",
    .oddsbar(row$p_home_win, row$p_draw, row$p_away_win), "\n",
    "<details class=\"mscore\"><summary>Ergebnis-Matrix</summary>",
    .render_score_matrix(row$score_matrix[[1]]), "</details>\n",
    nachhol,
    "</div>\n"
  )
}

# Ausblick-Sektion: kommende Spiele mit 1/X/2-Balken und aufklappbarer
# Ergebnis-Matrix (Score-Matrix aus der Endpoint-Antwort).
render_ausblick <- function(ausblick, runde) {
  zeilen <- vapply(seq_len(nrow(ausblick)), function(i) {
    .ausblick_zeile(ausblick[i, ])
  }, character(1))

  paste0(
    "<section id=\"ausblick\">\n",
    "<p class=\"eyebrow\">Ausblick</p>\n",
    "<h2>", .spieltag_ueberschrift(runde), "</h2>\n",
    "<p class=\"sectionlead\">Die Wahrscheinlichkeiten für die kommenden ",
    "Spiele, gerechnet mit den ELO-Werten von heute. Die Ergebnis-Matrix ",
    "zeigt je Paarung die Wahrscheinlichkeit jedes Endstands.</p>\n",
    "<p class=\"oddslegend\">Balken: <span class=\"chip h\"></span><b>Sieg Heim</b>",
    "<span class=\"chip x\"></span><b>Remis</b>",
    "<span class=\"chip a\"></span><b>Sieg Gast</b> — Angaben in Prozent</p>\n",
    "<div class=\"matches\">\n",
    paste0(zeilen, collapse = ""),
    "</div>\n</section>\n"
  )
}
