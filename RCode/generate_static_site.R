# Static site generation.
#
# Renders the three league views to self-contained HTML pages plus PNG heatmaps.
# Replaces the shinyapps.io deployment: the simulator writes these files after
# each cycle and any web server serves the directory.

suppressPackageStartupMessages({
  library(ggplot2)
  library(reshape2)
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
SITE_TITLE <- "Fußball-Prognosen von 30Punkte"
STALE_THRESHOLD_HOURS <- 24

footer_timestamp <- function(mtime) {
  lt <- as.POSIXlt(mtime, tz = "Europe/Berlin")
  # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
  tzlabel <- if (lt$isdst > 0) "MESZ" else "MEZ"
  paste0("Letztes Update: ", format(lt, "%d.%m.%Y %H:%M"), " ", tzlabel)
}

iso_utc <- function(t) {
  format(as.POSIXct(t), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
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
    "<table>\n<thead><tr><th></th>",
    paste0("<th>", htmltools::htmlEscape(panel$labels), "</th>", collapse = ""),
    "</tr></thead>\n<tbody>\n", rows, "\n</tbody>\n</table>"
  )
}

.nav_html <- function(current_slug, views) {
  items <- vapply(views, function(v) {
    label <- htmltools::htmlEscape(v$nav_label)
    if (identical(v$slug, current_slug)) {
      paste0("<a href=\"", v$slug, ".html\" class=\"nav-current\" ",
             "aria-current=\"page\">", label, "</a>")
    } else {
      paste0("<a href=\"", v$slug, ".html\">", label, "</a>")
    }
  }, character(1))
  paste0("<nav>", paste(items, collapse = " · "), "</nav>")
}

.page_css <- paste(
  "body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;",
  "margin:0 auto;max-width:1000px;padding:1rem;line-height:1.5}",
  "nav{margin:1rem 0}nav a{margin-right:.25rem}",
  ".nav-current{font-weight:700;text-decoration:underline}",
  "table{border-collapse:collapse;margin:1rem 0;width:100%}",
  "th,td{border:1px solid #ddd;padding:.3rem .5rem;text-align:right}",
  "th[scope=row]{text-align:left}",
  "img{max-width:100%;height:auto}",
  ".stale{background-color:#f8d7da;color:#721c24;padding:10px;",
  "border-radius:4px;margin-bottom:12px}",
  ".stale[hidden]{display:none}",
  "footer{margin-top:2rem;font-size:.9rem;color:#555}",
  sep = ""
)

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

render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now) {
  dir.create(file.path(output_dir, "assets"), recursive = TRUE,
             showWarnings = FALSE)

  plot_obj <- get(view$plot_source, envir = data_env)
  png_rel <- file.path("assets", paste0(view$slug, ".png"))
  ggplot2::ggsave(
    filename = file.path(output_dir, png_rel),
    plot = display_result(plot_obj, Titel = view$plot_title,
                          Teams = view$teams),
    width = 10, height = 6, dpi = 110
  )

  top_html <- render_panel_table(get(view$top$source, envir = data_env),
                                 view$top)
  bottom_html <- render_panel_table(get(view$bottom$source, envir = data_env),
                                    view$bottom)

  html <- paste0(
    "<!doctype html>\n<html lang=\"de\">\n<head>\n",
    "<meta charset=\"utf-8\">\n",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
    "<title>", htmltools::htmlEscape(SITE_TITLE), " – ",
    htmltools::htmlEscape(view$nav_label), "</title>\n",
    "<style>", .page_css, "</style>\n</head>\n<body>\n",
    "<h1>", htmltools::htmlEscape(SITE_TITLE), "</h1>\n",
    .nav_html(view$slug, league_views()), "\n",
    .stale_banner_html(), "\n",
    "<img src=\"", png_rel, "\" alt=\"",
    htmltools::htmlEscape(view$plot_title), "\">\n",
    top_html, "\n", bottom_html, "\n",
    "<footer>\n<p>Alle Prognosen als Wahrscheinlichkeiten in Prozent ",
    "angegeben. Nähere Infos unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></p>\n",
    "<p><time id=\"generated\" datetime=\"", iso_utc(mtime), "\">",
    htmltools::htmlEscape(footer_timestamp(mtime)), "</time></p>\n",
    "</footer>\n", .stale_script, "\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  writeLines(html, out_path, useBytes = TRUE)
  invisible(out_path)
}
