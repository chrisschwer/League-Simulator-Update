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
# Die Sektionsrenderer (Ligatabelle, Zonen, Rueckblick, Live, Ausblick)
# liegen seit #211 in render_sections.R.
source(file.path(.gss_dir, "render_sections.R"), local = TRUE)

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

# Die Reihenfolge der Gruppenzeilen im Menue.
#
# Eigene Angabe, NICHT die Registry-Reihenfolge (Issue #178): Die
# Regionalligen standen als dritte Gruppe unter den Frauen-Ligen und lasen
# sich dadurch, als stuenden sie quer zu den beiden Geschlechter-Gruppen.
# Es sind Herren-Ligen derselben Wechselgemeinschaft (ADR 0004) -- ein
# Regionalliga-Meister steigt in die 3. Liga auf. Zwischen Herren und
# Frauen gestellt, sagt die Nachbarschaft das, ohne dass das Label es
# buchstabieren muss.
#
# Die Registry behaelt ihre Reihenfolge: Sie bestimmt ueber league_ids(),
# in welcher Folge der Loop die API abruft. Anzeige und Abruf haben nichts
# miteinander zu tun und duerfen sich unabhaengig bewegen -- die
# Abstiegskopplung der Regionalligen laeuft nach der Simulationsschleife
# und mit einer Zaehlung, die Loops ueberlebt (update_all_leagues_loop.R:110).
NAV_GRUPPEN_REIHENFOLGE <- c("Herren", "Regionalliga", "Frauen")

#' Gruppennamen in Anzeigereihenfolge.
#'
#' Unbekannte Gruppen haengen HINTEN an, statt herauszufallen: Traegt eine
#' kuenftige Liga eine nav_group, die oben nicht steht, waere sie sonst
#' lautlos aus dem Menue verschwunden -- eine ganze Liga, ohne dass etwas
#' fehlschlaegt. Hinten und sichtbar ist der bessere Fehlerfall.
#'
#' @param gruppen Vorgefundene Gruppennamen.
#' @return Dieselben Namen, sortiert.
.nav_gruppen_sortiert <- function(gruppen) {
  rang <- match(gruppen, NAV_GRUPPEN_REIHENFOLGE)
  # Unbekannte hinten, untereinander in der Reihenfolge ihres Auftretens.
  rang[is.na(rang)] <- length(NAV_GRUPPEN_REIHENFOLGE) + seq_len(sum(is.na(rang)))
  gruppen[order(rang)]
}

# Die Ligen nach nav_group gebuendelt, in NAV_GRUPPEN_REIHENFOLGE.
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

  # Erst hier sortiert, nicht beim Einsammeln: Die Zugehoerigkeit der
  # Aufstiegsseite entsteht ueber den Gruppennamen, sie muss also schon
  # eingemischt sein.
  unname(gruppen[.nav_gruppen_sortiert(names(gruppen))])
}

# Die Ansicht der Aufstiegsseite. Ueber league_views() nachgeschlagen, damit
# es nur eine Quelle gibt -- sie steht dort neben der Ligaliste, nicht darin.
.AUFSTIEGSSEITE_SLUG <- "rl-aufstieg"

.aufstiegsseite_view <- function() {
  league_views()[[.AUFSTIEGSSEITE_SLUG]]
}

# Der Takt, den der Seitenfuss nennt, wenn er vom Normalfall abweicht.
# Modulweite Variable statt eines weiteren Arguments durch vier
# Render-Funktionen: `.footer_html()` wird an drei Stellen gerufen, die
# Seitenrenderer an weiteren -- ein durchgereichtes Argument haette den
# halben Generator angefasst und sich mit PR #220 (atomares Schreiben in
# denselben Funktionen) gebissen. generate_static_site() setzt sie, der
# Fussbauer liest sie; beide stehen in dieser Datei.
.aktueller_takt <- NULL

# Ab wann ein Takt "eingeschraenkt" ist: mehr als das Anderthalbfache des
# Normaltakts. Darunter ist die Abweichung Rundung, kein Ausfall -- und ein
# Hinweis, der immer dasteht, ist nach einer Woche unsichtbar.
.TAKT_NORMAL_SEKUNDEN <- 120
.TAKT_HINWEIS_FAKTOR <- 1.5

footer_timestamp <- function(mtime, waittime = NULL) {
  lt <- as.POSIXlt(mtime, tz = "Europe/Berlin")
  # isdst: >0 = DST (MESZ), 0 = standard (MEZ), <0 = unknown -> falls through to MEZ
  tzlabel <- if (lt$isdst > 0) "MESZ" else "MEZ"
  zeile <- paste0("Letztes Update: ", format(lt, "%d.%m.%Y %H:%M"), " ", tzlabel)

  # Der Hinweis auf eingeschraenkten Service (Issue #224). Am 14.09.2026
  # lief der Scheduler im 83-Minuten-Takt, ohne dass die Seite das verriet:
  # Sie zeigte "Letztes Update 18:51" und sah aus wie eine, die gleich
  # wieder aktualisiert wird. Ein Spiel um 18:00 fiel in die Luecke bis
  # 20:15. Der Stale-Banner greift erst nach 24 Stunden und haette hier nie
  # angeschlagen.
  if (length(waittime) == 1L && !is.na(waittime) &&
        waittime > .TAKT_NORMAL_SEKUNDEN * .TAKT_HINWEIS_FAKTOR) {
    zeile <- paste0(
      zeile, " — Eingeschränkter Service, Update etwa alle ",
      round(waittime / 60), " Minuten"
    )
  }

  zeile
}

iso_utc <- function(t) {
  format(as.POSIXct(t), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
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

# Ein Team-Kuerzel als Zeilenkopf, mit dem vollen Namen als Tooltip.
# `namen` ist ein benannter Vektor Kuerzel -> Name EINER Liga (.teamnamen());
# Kuerzel sind nur innerhalb einer Liga eindeutig.
.kuerzel_html <- function(kuerzel, namen = NULL) {
  .tooltip_html(kuerzel, if (is.null(namen)) NULL else unname(namen[kuerzel]))
}

# Kuerzel -> Name aus der Ligatabelle einer Seite, NULL ohne Tabelle (die
# Seite degradiert dann auf schlichte Kuerzel).
.teamnamen <- function(league_entry) {
  tab <- league_entry$tabelle
  if (is.null(tab) || is.null(tab$kuerzel) || is.null(tab$name)) {
    return(NULL)
  }
  stats::setNames(as.character(tab$name), as.character(tab$kuerzel))
}

render_heatmap <- function(result, namen = NULL) {
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
          .kuerzel_html(rownames(result)[i], namen), "</th>", cells, "</tr>")
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
render_panel_table <- function(data_obj, panel, computed_obj = NULL,
                               namen = NULL) {
  computed <- .panel_computed(panel)

  # Ganz berechnetes Panel: keine Platzaufloesung -- es GIBT keine
  # Platzspalten. Die Spalten gehen so hinaus, wie sie hereinkamen. Der
  # Zeilenfilter gilt trotzdem, mit demselben 1-%-Kriterium wie unten, nur
  # ueber die berechneten Spalten statt ueber `filter_cols` (Issue #229).
  if (all(computed)) {
    grouped <- as.data.frame(
      .computed_spalten(data_obj, panel$labels, "render_panel_table")
    )
    grouped <- grouped[rowSums(grouped) >= 0.01, , drop = FALSE]
    if (nrow(grouped) == 0) {
      return("")
    }
    return(.panel_html(grouped, panel$labels, namen))
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

  .panel_html(grouped, panel$labels, namen)
}

# Der gemeinsame Ausgabeteil: Prozentformatierung und Markup. Getrennt vom
# Rechenteil, damit der berechnete und der Platzgruppen-Pfad garantiert
# dieselbe Tabelle erzeugen.
.panel_html <- function(grouped, labels, namen = NULL) {
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
    .kuerzel_html(rownames(formatted), namen), "</th>",
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
    "<span>", htmltools::htmlEscape(footer_timestamp(mtime, .aktueller_takt)),
    " <time id=\"generated\" datetime=\"", iso_utc(mtime), "\"></time></span>\n",
    "<span>Mehr dazu unter <a href=\"", BLOG_URL,
    "\" target=\"blank_\">30punkte.wordpress.com</a></span>\n",
    "</footer>\n"
  )
}

render_league_page <- function(view, data_env, output_dir,
                               now = Sys.time(), mtime = now,
                               league_entry = NULL,
                               view_key = NULL) {
  .copy_assets(output_dir)

  result <- get(view$plot_source, envir = data_env)
  namen <- .teamnamen(league_entry)
  heatmap_html <- render_heatmap(result, namen)

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
                       computed_obj = computed_obj, namen = namen)
  }

  top_html <- panel_html(view$top)
  bottom_html <- panel_html(view$bottom)

  # Auf-/Abstiegszonen (Issue #185): nur die Regionalligen tragen welche.
  # rl_zonen() liefert fuer alle anderen NULL, und ohne zonen rendert die
  # Tabelle zeichengleich wie vorher.
  zonen <- if (!is.null(view_key)) rl_zonen(view_key, data_env) else NULL
  zonen_fussnote <- if (!is.null(zonen)) {
    regel <- league_registry()[[view_key]]$relegation_regel
    if (is.null(regel)) "" else render_zonen_fussnote(zonen, regel)
  } else {
    ""
  }

  tabelle_html <- if (!is.null(league_entry)) {
    paste0(
      "<section id=\"tabelle\">\n",
      "<p class=\"eyebrow\">Tabelle</p>\n",
      "<h2>Ligatabelle und ELO</h2>\n",
      "<p class=\"sectionlead\">Die aktuelle Tabelle, daneben die ELO-Stärkeschätzung ",
      "des Modells und ihre Veränderung seit Saisonbeginn.</p>\n",
      "<div class=\"scroll\">", render_liga_tabelle(league_entry$tabelle, zonen = zonen),
      "</div>\n", zonen_fussnote, "\n</section>\n"
    )
  } else {
    ""
  }
  sort_script <- if (!is.null(league_entry)) .LIGA_SORT_SCRIPT else ""
  kuerzel_script <- if (!is.null(namen)) .KUERZEL_SCRIPT else ""

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
    sort_script, "\n", kuerzel_script, "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  .write_atomically(html, out_path)
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
.aufstiegs_zeile <- function(team, meister, aufstieg, quote_zeigen,
                             namen = NULL) {
  quote <- if (quote_zeigen) .siegquote(aufstieg, meister) else ""
  paste0(
    "<tr><th scope=\"row\">", .kuerzel_html(team, namen), "</th>",
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
                               quote_zeigen, namen = NULL) {
  teams <- names(meister)
  zeigen <- meister > 0 | aufstieg[teams] > 0
  teams <- teams[zeigen]

  if (length(teams) == 0) {
    return("")
  }

  zeilen <- vapply(teams, function(team) {
    .aufstiegs_zeile(team, meister[[team]], aufstieg[[team]], quote_zeigen,
                     namen)
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
                       quote_zeigen = isTRUE(daten$playoff),
                       namen = daten$namen)
  }, character(1))
  hat_namen <- any(vapply(aufstiegsdaten, function(d) !is.null(d$namen),
                          logical(1)))

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
    .stale_script, "\n",
    if (hat_namen) .KUERZEL_SCRIPT else "", "\n</div>\n</body>\n</html>\n"
  )

  out_path <- file.path(output_dir, paste0(view$slug, ".html"))
  .write_atomically(html, out_path)
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
  .write_atomically(html, out_path)
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
  .write_atomically(html, out_path)
  invisible(out_path)
}

# Schreibt `text` atomar nach `path` (Issue #208, Punkt 4): erst in eine
# Temp-Datei IM SELBEN Verzeichnis -- damit file.rename() ein guenstiger
# Rename innerhalb eines Dateisystems bleibt statt eines Kopiervorgangs --
# dann per file.rename() an den Zielnamen. writeLines() direkt auf out_path
# hinterlaesst bei einem Absturz mittendrin eine halb geschriebene Datei,
# die Caddy waehrenddessen ausliefern kann; ein Rename ist auf demselben
# Dateisystem atomar, Leser sehen entweder die alte oder die vollstaendige
# neue Datei, nie etwas dazwischen.
#
# Schlaegt das Rename fehl (Platte voll, Rechteproblem, ...), bleibt die
# ALTE Datei unangetastet -- die Temp-Datei wird aufgeraeumt und ein Fehler
# geworfen, statt die Zieldatei in einem undefinierten Zustand zu lassen.
.write_atomically <- function(text, path) {
  tmp_path <- paste0(path, ".tmp")
  writeLines(text, tmp_path, useBytes = TRUE)
  if (!file.rename(tmp_path, path)) {
    unlink(tmp_path)
    stop(sprintf(".write_atomically: file.rename nach %s fehlgeschlagen", path))
  }
  invisible(path)
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
.aufstiegsdaten <- function(keys, data_env, league_data = NULL) {
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
      playoff = playoff,
      # Kuerzel -> Name aus der Ligatabelle DIESER Staffel (Tooltips).
      namen = .teamnamen(league_data[[key]])
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
                                 ergebnisse = NULL,
                                 waittime = NULL) {
  # Der aktuelle Update-Takt fuer den Seitenfuss (Issue #224). NULL = keine
  # Angabe = Fuss unveraendert, damit scripts/preview_site.R und alle
  # Bestandsaufrufe nichts davon merken. Gesetzt wird eine modulweite
  # Variable, weil der Fussbauer tief in den Render-Funktionen sitzt --
  # siehe Kommentar bei `.aktueller_takt`.
  #
  # on.exit: Der Wert gehoert zu DIESEM Aufruf. Bliebe er stehen, truege
  # ein spaeterer Aufruf ohne Taktangabe den Hinweis des vorigen weiter --
  # in den Tests derselben Sitzung sofort sichtbar, in Produktion nach dem
  # ersten gedrosselten Zyklus dauerhaft.
  alter_takt <- .aktueller_takt
  .aktueller_takt <<- waittime
  on.exit(.aktueller_takt <<- alter_takt, add = TRUE)

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
                       league_entry = league_data[[key]], view_key = key)
  }, character(1))

  # Die Aufstiegsseite entsteht nur, wenn wenigstens eine Regionalliga
  # gerendert wurde. Ohne Staffeln waere sie eine leere Seite in der
  # Navigation -- schlechter als keine Seite (der Kompatibilitaetspfad
  # rendert weiterhin genau vier Seiten).
  aufstiegsdaten <- .aufstiegsdaten(names(views), data_env, league_data)
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
