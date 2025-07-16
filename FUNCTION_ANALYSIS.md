# League Simulator Function Analysis

## 1. SpielCPP.R - Match Simulation/ELO Update Function

**Function Signature:**
```r
SpielCPP(ELOHeim, ELOGast, ToreHeim, ToreGast, 
         ZufallHeim, ZufallGast, 
         ModFaktor = 20, Heimvorteil = 65, 
         Simulieren = FALSE, 
         ToreSlope = 0.0017854953143549, ToreIntercept = 1.3218390804597700)
```

**Parameters:**
- `ELOHeim`: ELO value for home team (numeric)
- `ELOGast`: ELO value for away team (numeric)
- `ToreHeim`: Goals scored by home team (numeric, ignored if Simulieren=TRUE)
- `ToreGast`: Goals scored by away team (numeric, ignored if Simulieren=TRUE)
- `ZufallHeim`: Random value for home team simulation (numeric between 0-1)
- `ZufallGast`: Random value for away team simulation (numeric between 0-1)
- `ModFaktor`: ELO adjustment multiplier (default: 20)
- `Heimvorteil`: Home field advantage in ELO points (default: 65)
- `Simulieren`: Whether to simulate goals (TRUE) or use actual results (FALSE)
- `ToreSlope`: Goals per ELO delta point (default: 0.0017854953143549)
- `ToreIntercept`: Average goals for equal teams (default: 1.3218390804597700)

**Return Value:**
- Calls and returns the result from `SpielNichtSimulieren()` - a NumericVector with 5 elements

**Key Logic:**
- If `Simulieren=TRUE`: Uses Poisson distribution with random values to generate goals
- Always calls `SpielNichtSimulieren()` with adjusted home ELO (ELOHeim + Heimvorteil)

## 2. SpielNichtSimulieren.cpp - Core ELO Calculation

**Function Signature (C++):**
```cpp
NumericVector SpielNichtSimulieren(double ELOHome, double ELOAway, 
                                  double GoalsHome, double GoalsAway,
                                  double modFactor, double homeAdvantage)
```

**Parameters:**
- `ELOHome`: Home team ELO (already includes home advantage from SpielCPP)
- `ELOAway`: Away team ELO
- `GoalsHome`: Goals scored by home team
- `GoalsAway`: Goals scored by away team
- `modFactor`: ELO adjustment multiplier
- `homeAdvantage`: Not used (always 0 when called from SpielCPP)

**Return Value (NumericVector with 5 elements):**
1. `out(0)`: New ELO value for home team
2. `out(1)`: New ELO value for away team
3. `out(2)`: Goals scored by home team (unchanged)
4. `out(3)`: Goals scored by away team (unchanged)
5. `out(4)`: ELO-based win probability for home team

**Key Logic:**
- Calculates ELO probability using standard formula: 1 / (1 + 10^(ELODelta/400))
- Adjusts ELO based on actual vs expected result, modified by goal difference

## 3. SaisonSimulierenCPP.R - Season Simulation

**Function Signature:**
```r
SaisonSimulierenCPP(Spielplan, ELOWerte,
                    ModFaktor = 20, Heimvorteil = 65,
                    AnzahlTeams, AnzahlSpiele)
```

**Parameters:**
- `Spielplan`: n×4 matrix (TeamHeim, TeamGast, ToreHeim, ToreGast)
- `ELOWerte`: Vector of ELO values indexed by team number
- `ModFaktor`: ELO adjustment multiplier
- `Heimvorteil`: Home field advantage
- `AnzahlTeams`: Number of teams
- `AnzahlSpiele`: Number of matches

**Return Value (list with 2 elements):**
1. Updated `Spielplan` matrix with simulated results for NA games
2. Updated `ELOWerte` vector with final ELO values

**Key Logic:**
- Iterates through all matches
- For NA results: generates random values and calls SpielCPP with Simulieren=TRUE
- For actual results: calls SpielCPP with Simulieren=FALSE
- Updates both Spielplan and ELOWerte after each match

## 4. simulationsCPP.R - Monte Carlo Simulations

**Function Signature:**
```r
simulationsCPP(season, ELOValue,
               numberTeams, numberGames,
               modFactor = 20, homeAdvantage = 65, 
               iterations = 10000,
               AdjPoints = rep_len(0, numberTeams),
               AdjGoals = rep_len(0, numberTeams),
               AdjGoalsAgainst = rep_len(0, numberTeams),
               AdjGoalDiff = rep_len(0, numberTeams))
```

**Parameters:**
- `season`: m×4 matrix of all matches
- `ELOValue`: Initial ELO values
- Adjustment vectors for points, goals, etc. (for handling penalties/bonuses)

**Return Value:**
- If unplayed games exist: Matrix with iterations×numberTeams rows, 6 columns per team
- If all games played: Single table with numberTeams rows, 6 columns

**Key Logic:**
1. Splits season into played and unplayed games
2. Processes played games to update ELO and calculate current standings
3. Runs Monte Carlo simulations for unplayed games
4. Returns aggregated results from all iterations

## 5. Tabelle.R - League Table Calculator

**Function Signature:**
```r
Tabelle(season, 
        numberTeams, numberGames,
        AdjPoints = rep_len(0, numberTeams),
        AdjGoals = rep_len(0, numberTeams),
        AdjGoalsAgainst = rep_len(0, numberTeams),
        AdjGoalDiff = rep_len(0, numberTeams))
```

**Parameters:**
- `season`: m×4 matrix of completed matches
- Adjustment vectors for handling penalties/bonuses

**Return Value (Matrix with 6 columns):**
1. Team number (1 to numberTeams)
2. Rank (1 = first place, based on points/goals)
3. Goals scored
4. Goals against
5. Goal difference
6. Points (3-point system)

**Key Logic:**
- Calculates points using 3-point system
- Handles teams that haven't played yet (keeps adjustment values only)
- Ranks teams by: Points → Goal Difference → Goals Scored

## 6. transform_data.R - API Data Transformer

**Function Signature:**
```r
transform_data(fixtures, teams)
```

**Parameters:**
- `fixtures`: Raw fixture data from API (nested structure)
- `teams`: Team mapping data with TeamID, ShortText, InitialELO

**Return Value (tibble with columns):**
- `TeamHeim`: Home team short name
- `TeamGast`: Away team short name
- `ToreHeim`: Home goals (NA if not finished)
- `ToreGast`: Away goals (NA if not finished)
- One column per team with their ELO value in row 1, NA elsewhere

**Key Logic:**
- Unnests API data structure
- Sets goals to NA for unfinished games (status != "FT")
- Creates wide format with ELO values in first row

## 7. leagueSimulatorCPP.R - Main Wrapper Function

**Function Signature:**
```r
leagueSimulatorCPP(season, n = 10000,
                   modFactor = 20, homeAdvantage = 65,
                   numberTeams = 18,
                   adjPoints = rep_len(0, numberTeams), 
                   adjGoals = rep_len(0, numberTeams),
                   adjGoalsAgainst = rep_len(0, numberTeams), 
                   adjGoalDiff = rep_len(0, numberTeams))
```

**Parameters:**
- `season`: Output from transform_data() function
- `n`: Number of Monte Carlo iterations

**Return Value:**
- Matrix: rows = teams (ordered by average rank), columns = final positions (1-18)
- Values: Probability of each team finishing in each position (0-1)

**Key Logic:**
1. Extracts ELO values from first row
2. Converts team names to numeric indices
3. Calls simulationsCPP for Monte Carlo simulation
4. Aggregates results into probability distribution
5. Orders teams by average finishing position

## Data Flow Summary

1. **API Data** → `transform_data()` → Wide format with ELOs
2. **Wide format** → `leagueSimulatorCPP()` → Probability matrix
3. Inside `leagueSimulatorCPP()`:
   - Calls `simulationsCPP()` for Monte Carlo
   - Which calls `SaisonSimulierenCPP()` for each iteration
   - Which calls `SpielCPP()` for each match
   - Which calls `SpielNichtSimulieren()` for ELO updates
   - Results aggregated by `Tabelle()` after each season

## Key Data Structures

**Season/Spielplan Matrix (m×4):**
- Column 1: Home team number (1-based)
- Column 2: Away team number (1-based)
- Column 3: Home goals (or NA)
- Column 4: Away goals (or NA)

**Table Matrix (numberTeams×6):**
- Column 1: Team number
- Column 2: Rank
- Column 3: Goals scored
- Column 4: Goals against
- Column 5: Goal difference
- Column 6: Points

**ELO Vector:**
- Length: numberTeams
- Indexed by team number (1-based)