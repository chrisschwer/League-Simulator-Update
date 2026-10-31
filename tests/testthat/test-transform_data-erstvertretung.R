library(testthat)
source("../../RCode/transform_data.R")

# pruefe_erstvertretung() und die Warnung in load_team_list(): Die Spalten
# Erstvertretung_TeamID / Erstvertretung_ShortText (#322) werden von Hand
# gepflegt, ein Fehler soll auffallen, ohne die TeamList abzulehnen.

erstvertretung_teamlist <- function() {
  data.frame(
    TeamID = c(171, 9332, 9348, 161),
    ShortText = c("FCN", "FCN2", "WO2", "WOB"),
    InitialELO = 1500,
    League = c(79, 83, 84, 79),
    Erstvertretung_TeamID = c(NA, 171, 161, NA),
    Erstvertretung_ShortText = c("", "FCN", "WOB", ""),
    stringsAsFactors = FALSE
  )
}

test_that("eine stimmige Zuordnung ergibt keinen Verstoss", {
  expect_identical(pruefe_erstvertretung(erstvertretung_teamlist()), character(0))
})

test_that("ohne die Spalten gibt es nichts zu pruefen (TeamList vor #322)", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID <- NULL
  tl$Erstvertretung_ShortText <- NULL
  expect_identical(pruefe_erstvertretung(tl), character(0))
})

test_that("nur eine der beiden Spalten ist ein Verstoss", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_ShortText <- NULL
  expect_match(pruefe_erstvertretung(tl), "Erstvertretung_ShortText fehlt")
})

test_that("eine unbekannte TeamID wird gemeldet", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID[2] <- 99999
  expect_match(pruefe_erstvertretung(tl), "99999 kommt in der TeamList nicht vor")
})

test_that("ein Kurzname, der nicht zur TeamID passt, wird gemeldet", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_ShortText[3] <- "WOLF"
  v <- pruefe_erstvertretung(tl)
  expect_length(v, 1L)
  expect_match(v, "WO2 .*'WOLF' passt nicht zur TeamID 161 .*'WOB'")
})

test_that("eine Zeile darf nicht ihre eigene Erstvertretung sein", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID[2] <- 9332
  tl$Erstvertretung_ShortText[2] <- "FCN2"
  expect_match(pruefe_erstvertretung(tl), "ist die Zeile selbst")
})

test_that("ein Kurzname ohne TeamID wird gemeldet", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID[3] <- NA
  expect_match(pruefe_erstvertretung(tl), "ohne Erstvertretung_TeamID")
})

test_that("der Verstoss sammelt alle Fehler statt beim ersten aufzuhoeren", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID[2] <- 99999
  tl$Erstvertretung_ShortText[3] <- "WOLF"
  expect_length(pruefe_erstvertretung(tl), 2L)
})

test_that("load_team_list warnt bei einem Fehler, lehnt die TeamList aber nicht ab", {
  tl <- erstvertretung_teamlist()
  tl$Erstvertretung_TeamID[2] <- 99999
  pfad <- tempfile(fileext = ".csv")
  utils::write.table(tl, pfad, sep = ";", quote = FALSE, row.names = FALSE)

  expect_warning(geladen <- load_team_list(pfad), "99999 kommt in der TeamList nicht vor")
  expect_identical(nrow(geladen), 4L)
})

test_that("die echte TeamList hat eine stimmige Erstvertretung-Zuordnung", {
  tl <- load_team_list("../../RCode/TeamList_2026.csv")
  expect_identical(pruefe_erstvertretung(tl), character(0))
  # Die neun Reserven von Zweitligisten, auf die #322 zielt.
  zweitliga <- c("FCN2", "SGF2", "H962", "STP2", "WO2", "FCM2", "BSC2", "FCK2", "BOC2")
  zeilen <- tl[tl$ShortText %in% zweitliga & as.character(tl$League) %in% as.character(83:87), ]
  expect_identical(nrow(zeilen), 9L)
  erst <- tl$League[match(as.character(zeilen$Erstvertretung_TeamID), as.character(tl$TeamID))]
  expect_true(all(as.character(erst) == "79"))
})
