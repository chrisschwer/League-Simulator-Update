# Helfer fuer die Client-JS-Tests (Stufe 4.6, #212): Node + jsdom fuehren die
# drei Inline-Skripte der gerenderten Seite aus. Der Runner liegt unter
# helpers/js-runner.mjs; Node und jsdom kommen lokal per `npm ci`, in der CI
# vom Runner (ci.yml, Job image-build-and-test).

js_repo_root <- function() normalizePath(test_path("..", ".."), mustWork = TRUE)

# Ueberspringt den Test, wenn Node oder jsdom fehlt. Der Skip-Text ist
# Vertrag: scripts/ci/testthat_ci.R erkennt ihn (js_skips) und bricht in der
# CI ab, damit ein fehlendes Node dort nicht lautlos gruen bleibt.
skip_ohne_js <- function() {
  if (!nzchar(Sys.which("node")) ||
      !dir.exists(file.path(js_repo_root(), "node_modules", "jsdom"))) {
    skip("Node/jsdom fehlt")
  }
}

# Fuehrt ein Szenario des Runners auf `html` aus und liefert sein JSON-Ergebnis
# als Liste. Ein Exit-Status != 0 ist ein Testfehler mit der Runner-Meldung.
js_szenario <- function(html, szenario, args = list()) {
  datei <- withr::local_tempfile(fileext = ".html")
  writeLines(enc2utf8(html), datei, useBytes = TRUE)
  runner <- file.path(js_repo_root(), "tests", "testthat", "helpers", "js-runner.mjs")
  # stderr getrennt: eine Node-Warnung darf das JSON auf stdout nicht zerbrechen.
  fehlerdatei <- withr::local_tempfile(fileext = ".txt")
  out <- suppressWarnings(system2(
    "node",
    c(shQuote(runner), shQuote(datei), szenario,
      shQuote(jsonlite::toJSON(args, auto_unbox = TRUE, null = "null"))),
    stdout = TRUE, stderr = fehlerdatei
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop(sprintf("js-runner '%s' endete mit Status %d:\n%s\n%s",
                 szenario, status, paste(out, collapse = "\n"),
                 paste(readLines(fehlerdatei, warn = FALSE), collapse = "\n")),
         call. = FALSE)
  }
  jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
}

# Der Inhalt aller <script>-Bloecke einer Seite (ohne die Tags).
js_skripte_aus_html <- function(html) {
  treffer <- regmatches(html, gregexpr("(?s)<script[^>]*>.*?</script>", html, perl = TRUE))[[1]]
  sub("(?s)^<script[^>]*>(.*)</script>$", "\\1", treffer, perl = TRUE)
}

# `node --check` je Skript; liefert die Exit-Status (0 = Syntax in Ordnung).
js_syntax_status <- function(skripte) {
  vapply(seq_along(skripte), function(i) {
    datei <- withr::local_tempfile(fileext = ".js")
    writeLines(enc2utf8(skripte[[i]]), datei, useBytes = TRUE)
    status <- suppressWarnings(system2("node", c("--check", shQuote(datei)),
                                       stdout = FALSE, stderr = FALSE))
    as.integer(status)
  }, integer(1))
}

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
