# League Simulator

This repository contains R scripts and a Shiny application for simulating football leagues.

## Scripts

- `retrieveResults.R`: downloads results from the football API.
- `updateScheduler.R`: runs regular update loops inside the container.
- `updateShiny.R`: deploys the Shiny App via rsconnect.
- `update_all_leagues_loop.R`: loops through league updates.
- Additional helper scripts for simulations and data handling.

## Environment Variables

The container expects the following variables at runtime:

- `RAPIDAPI_KEY` – API key for api-football.
- `SHINYAPPS_IO_SECRET` – secret for deploying to shinyapps.io.
- `DURATION` – duration in minutes for each update cycle.
- `SEASON` – season to analyse (for example `2024`).

## Using Docker

Build the image and start the container while providing the required variables:

```bash
docker build -t league-simulator .

docker run -e RAPIDAPI_KEY=your_api_key \
           -e SHINYAPPS_IO_SECRET=your_shiny_secret \
           -e DURATION=480 \
           -e SEASON=2024 \
           league-simulator
```

The container executes `updateScheduler.R` on start and will update the Shiny app accordingly.
