# Liga-Registry: Die Probe-Liga und der Fallback skalieren mit der Ligazahl.
if (!exists("league_ids")) {
  local({
    d <- NULL
    for (f in rev(sys.frames())) {
      if (!is.null(f$ofile)) {
        d <- dirname(f$ofile)
        break
      }
    }
    if (is.null(d) || is.na(d) || !nzchar(d)) d <- "RCode"
    source(file.path(d, "league_registry.R"))
  })
}

# Function to check API rate limits and determine safe number of loops
# Returns the maximum number of loops that can be safely run without exceeding limits

#' @param avg_calls_per_loop Requests je Loop. Default aus der Registry: ein
#'   Live-Poll deckt alle Ligen mit EINEM Request ab, dazu kommen die
#'   Vollabrufe. Der frühere feste Wert 2 stammte aus der Drei-Ligen-Zeit.
# Der Default steht im Signaturausdruck, nicht als NULL mit Nachberechnung:
# So ist er ueber formals() ablesbar und dokumentiert sich selbst.
#
# Ein Live-Poll deckt alle Ligen mit EINEM Request ab; ein Vollabruf kostet
# einen je Liga. Weil das Live-Poll-Gating die meisten Loops im Leerlauf
# laesst (siehe update_all_leagues_loop), ist die halbe Ligazahl die
# konservative Mitte zwischen 1 (Leerlauf) und 1 + n (Vollabruf).
checkAPILimits <- function(ideal_loops,
                           avg_calls_per_loop = 1 + length(league_ids()) / 2,
                           safety_margin = 0.9) {
  # Try to make a simple API call to check headers
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    warning("No RAPIDAPI_KEY found, returning ideal_loops")
    return(ideal_loops)
  }

  # Get season using same logic as updateScheduler.R
  season <- Sys.getenv("SEASON")
  if (season == "") {
    current_month <- as.numeric(format(Sys.Date(), "%m"))
    current_year <- as.numeric(format(Sys.Date(), "%Y"))

    if (current_month >= 7) {
      season <- as.character(current_year)
    } else {
      season <- as.character(current_year - 1)
    }
  }

  # Ein eigener Probe-Request, bewusst (Issue #129, Punkt 1): Hier stand ein
  # Zweig, der die von retrieveResults() aufgezeichneten Header
  # (.api_rate_limit, 10-Minuten-Frist) wiederverwenden sollte. Er war in
  # Produktion unerreichbar -- calculate_loops() ist der einzige Aufrufer,
  # laeuft genau einmal je Prozess (updateScheduler.R:189) und damit VOR dem
  # ersten retrieveResults() (:192). Der Cache war bei der einzigen Abfrage
  # immer leer, der Request ging ohnehin jedes Mal hinaus.
  #
  # Ein Request pro Tag gegen 7.500 ist der ehrlichere Preis: Toter Code,
  # der nach Funktion aussieht, kostet mehr -- er laesst kuenftige Leser
  # glauben, die Abfrage sei manchmal gratis.
  #
  # Make a lightweight API call (e.g., get current round for one league)
  # This costs 1 API call but gives us the rate limit info
  tryCatch(
    {
      response <- httr::GET(
        url = "https://api-football-v1.p.rapidapi.com/v3/fixtures/rounds",
        httr::add_headers(
          "X-RapidAPI-Key" = api_key,
          "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
        ),
        query = list(
          league = league_ids()[[1]], # erste aktive Liga aus der Registry
          season = season,
          current = "true"
        )
      )

      # Extract rate limit headers
      headers <- httr::headers(response)

      # Get remaining requests
      remaining <- as.numeric(headers$`x-ratelimit-requests-remaining`)
      limit <- as.numeric(headers$`x-ratelimit-requests-limit`)

      if (is.na(remaining)) {
        warning("Could not read rate limit headers, returning ideal_loops")
        return(ideal_loops)
      }

      message(sprintf("API Rate Limit: %d/%d requests remaining", remaining, limit))

      # Calculate safe number of loops
      # Apply safety margin to avoid hitting exact limit
      safe_loops <- floor((remaining * safety_margin) / avg_calls_per_loop)

      # Return minimum of ideal and safe loops
      actual_loops <- min(ideal_loops, safe_loops)

      if (actual_loops < ideal_loops) {
        message(sprintf(
          "Reducing loops from %d to %d to respect API limits",
          ideal_loops, actual_loops
        ))
      } else {
        message(sprintf("Running %d loops (within API limits)", actual_loops))
      }

      return(actual_loops)
    },
    error = function(e) {
      warning(sprintf("Error checking API limits: %s", e$message))
      warning("Falling back to conservative estimate")
      # Fallback ohne Header-Information. Der Wert 33 stammte aus
      # "100 Requests/Tag / 3 Ligen" und war damit an die Ligazahl gebunden,
      # ohne das kenntlich zu machen. Jetzt folgt er der Registry: je Loop ein
      # Live-Poll plus im ungünstigsten Fall ein Vollabruf je aktiver Liga.
      conservative_loops <- min(
        ideal_loops,
        floor(100 / (1 + length(league_ids())))
      )
      return(conservative_loops)
    }
  )
}
