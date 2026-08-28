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
source(file.path(.gss_dir, "..", "ShinyApp", "app_helpers.R"), local = TRUE)

BLOG_URL <- "http://30punkte.wordpress.com"
SITE_WORDMARK <- "30 Punkte"
SITE_TAGLINE <- paste0(
  "Prognosen für Bundesliga, 2. Bundesliga und 3. Liga ",
  "— nach jedem Spiel neu gerechnet."
)
STALE_THRESHOLD_HOURS <- 24

# The four nav destinations, in display order. Methodik has no league_views()
# entry of its own (it carries no panels/heatmap), so the nav is assembled
# from this fixed list rather than derived from league_views().
.NAV_ITEMS <- list(
  list(slug = "index", nav_label = "Bundesliga"),
  list(slug = "2-bundesliga", nav_label = "2. Bundesliga"),
  list(slug = "3-liga", nav_label = "3. Liga"),
  list(slug = "methodik", nav_label = "Methodik")
)

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

render_panel_table <- function(data_obj, panel) {
  keep <- rowSums(data_obj[, panel$filter_cols, drop = FALSE]) >= 0.01
  subset_obj <- data_obj[keep, , drop = FALSE]

  if (nrow(subset_obj) == 0) {
    return("")
  }

  grouped <- groupResultsDF(subset_obj,
                            labels = panel$labels,
                            groups = panel$groups)
  formatted <- apply(grouped, c(1, 2), prozent)

  # apply() drops to a vector when there is a single label column; restore shape.
  if (is.null(dim(formatted))) {
    formatted <- matrix(formatted, ncol = length(panel$labels),
                        dimnames = list(rownames(grouped), panel$labels))
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
    paste0("<th scope=\"col\">", htmltools::htmlEscape(panel$labels), "</th>",
          collapse = ""),
    "</tr></thead>\n<tbody>\n", rows, "\n</tbody>\n</table>"
  )
}

.nav_html <- function(current_slug) {
  items <- vapply(.NAV_ITEMS, function(v) {
    label <- htmltools::htmlEscape(v$nav_label)
    href <- paste0(v$slug, ".html")
    if (identical(v$slug, current_slug)) {
      paste0("<a class=\"nav-current\" aria-current=\"page\" href=\"", href,
             "\">", label, "</a>")
    } else {
      paste0("<a href=\"", href, "\">", label, "</a>")
    }
  }, character(1))
  paste0("<nav aria-label=\"Ligen\">",
        paste(items, collapse = "<span class=\"sep\">·</span>"), "</nav>")
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

.footer_html <- function(mtime) {
  paste0(
    "<footer>\n",
    "<span>", htmltools::htmlEscape(footer_timestamp(mtime)),
    " <time id=\"generated\" datetime=\"", iso_utc(mtime), "\"></time></span>\n",
    "<span>Nähere Infos unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></span>\n",
    "</footer>\n"
  )
}

render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now) {
  dir.create(file.path(output_dir, "assets"), recursive = TRUE,
             showWarnings = FALSE)
  .copy_assets(output_dir)

  result <- get(view$plot_source, envir = data_env)
  heatmap_html <- render_heatmap(result)

  top_html <- render_panel_table(get(view$top$source, envir = data_env),
                                 view$top)
  bottom_html <- render_panel_table(get(view$bottom$source, envir = data_env),
                                    view$bottom)

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
    .footer_html(mtime), "\n",
    .stale_script, "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}

.render_methodik_page <- function(output_dir, now = Sys.time(), mtime = now) {
  dir.create(file.path(output_dir, "assets"), recursive = TRUE,
             showWarnings = FALSE)
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
    "<footer><span>Nähere Infos unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></span></footer>\n",
    "</div>\n</body>\n</html>\n"
  )
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
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

generate_static_site <- function(Ergebnis, Ergebnis2, Ergebnis3,
                                 Ergebnis3_Aufstieg = Ergebnis3,
                                 output_dir = Sys.getenv("STATIC_SITE_DIR",
                                                         "ShinyApp/public"),
                                 now = Sys.time()) {
  have_data <- !is.null(Ergebnis) && !is.null(Ergebnis2) && !is.null(Ergebnis3)

  if (!have_data) {
    message("generate_static_site: no simulation data, writing fallback page")
    return(invisible(.render_fallback_page(output_dir)))
  }

  data_env <- new.env(parent = emptyenv())
  assign("Ergebnis", Ergebnis, envir = data_env)
  assign("Ergebnis2", Ergebnis2, envir = data_env)
  assign("Ergebnis3", Ergebnis3, envir = data_env)
  assign("Ergebnis3_Aufstieg",
         if (is.null(Ergebnis3_Aufstieg)) Ergebnis3 else Ergebnis3_Aufstieg,
         envir = data_env)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  league_paths <- vapply(league_views(), function(view) {
    message(sprintf("generate_static_site: rendering %s", view$slug))
    render_league_page(view, data_env, output_dir, now = now, mtime = now)
  }, character(1))

  message("generate_static_site: rendering methodik")
  methodik_path <- .render_methodik_page(output_dir, now = now, mtime = now)

  paths <- c(unname(league_paths), methodik_path)

  message(sprintf("generate_static_site: wrote %d pages to %s",
                  length(paths), output_dir))
  invisible(paths)
}
