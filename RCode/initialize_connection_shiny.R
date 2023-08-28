# Initializes the rsconnect connection with the shiny app

library(rsconnect)

account_name <- Sys.getenv("SHINYAPPS_IO_ACCOUNT")
account_token <- Sys.getenv("SHINYAPPS_IO_TOKEN")
account_secret <- Sys.getenv("SHINYAPPS_IO_SECRET")

rsconnect::setAccountInfo(name = account_name, token = account_token, secret = account_secret)