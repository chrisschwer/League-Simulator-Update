# Scheduler for updates to the results
# Runs indefinitely and performs the following steps:
# 1. Retrieves the results for all three leagues via the API
# 2. Checks if the number of finished games (FT) has changed since the last API call
# 3. If new games have finished, recalculates the respective league prognosis
# 4. Updates the RShiny App
# 5. Determines the wait time until the next API call according to the following rules:
#    a) The minimum wait time is 60 minutes, to avoid payments for API calls
#    b) If a game is still running, the earliest next call is start time of that game plus 115 minutes
#    c) If no game is running, the ealiest next call is the start time of the next game that starts plus 115 minutes
#    d) The maximum wait time is 24 hours to make sure that schedule changes are caught

# Loading all necessary libraries mentioned in ../packagelist.txt



# Sourcing the necessary R scripts


while TRUE {
    
}

