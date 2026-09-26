# Vergleicht die Multimenge aller test_that()-Blocktexte zweier Testverzeichnisse --
# Nachweiswerkzeug fuer reine Refactoring-PRs des Testsuite-Umbaus (#211), aus
# Stufe 2 uebernommen (dort ad hoc genutzt, hier als Entwicklerwerkzeug eingecheckt).
# Aufruf: Rscript scripts/dev/blockmenge_tests.R <dirA> <dirB>
#   dirA/dirB: Verzeichnisse mit test-*.R (z. B. ein Export von HEAD~1 und das Arbeitsverzeichnis)
# Ausgabe: Zahl der Bloecke je Seite, dann jede Abweichung (Titel, Datei, Seite).
# Blocktext = Quelltext des test_that()-Aufrufs (srcref), Leerraum normalisiert.
# Zaehlt nur oberste (Top-Level-)`test_that()`-Aufrufe mit woertlichem Titel;
# verschachtelte oder programmatisch erzeugte test_that()-Aufrufe werden nicht erfasst.
# Exit 0 bei identischer Multimenge, sonst 1.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2)
leer <- data.frame(datei = character(0), titel = character(0), text = character(0),
                    stringsAsFactors = FALSE)
bloecke <- function(dir) {
  out <- list()
  for (d in list.files(dir, pattern = "^test-.*\\.R$", full.names = TRUE)) {
    ex <- parse(d, keep.source = TRUE, encoding = "UTF-8")
    sr <- attr(ex, "srcref")
    for (i in seq_along(ex)) {
      e <- ex[[i]]
      if (is.call(e) && identical(e[[1]], as.name("test_that"))) {
        txt <- gsub("\\s+", " ", paste(as.character(sr[[i]]), collapse = "\n"))
        out[[length(out) + 1]] <- data.frame(datei = basename(d), titel = as.character(e[[2]]),
                                             text = txt, stringsAsFactors = FALSE)
      }
    }
  }
  res <- do.call(rbind, out)
  if (is.null(res)) leer else res
}
a <- bloecke(args[1]); b <- bloecke(args[2])
cat(sprintf("A: %d Bloecke in %d Dateien; B: %d Bloecke in %d Dateien\n",
            nrow(a), length(unique(a$datei)), nrow(b), length(unique(b$datei))))
alle <- union(a$text, b$text)
ha <- table(factor(a$text, levels = alle)); hb <- table(factor(b$text, levels = alle))
abw <- alle[ha != hb]
if (length(abw) == 0) {
  cat("Blockmenge identisch.\n"); quit(status = 0)
}
for (t in abw) {
  ia <- a[a$text == t, ]; ib <- b[b$text == t, ]
  cat(sprintf("ABWEICHUNG: %dx in A (%s), %dx in B (%s) -- Titel: %s\n",
              nrow(ia), paste(unique(ia$datei), collapse = ","),
              nrow(ib), paste(unique(ib$datei), collapse = ","),
              if (nrow(ia)) ia$titel[1] else ib$titel[1]))
}
quit(status = 1)
