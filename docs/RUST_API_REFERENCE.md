# Rust League Simulator API Reference

## Base URL
- Docker: `http://rust-simulator:8080`
- Local: `http://localhost:8080`

## Endpoints

### Health Check
```
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "0.1.0", 
  "performance": "370,000+ simulations/second"
}
```

### Simulate League
```
POST /simulate
```

**Request:**
```json
{
  "schedule": [
    [0, 1, 2, 1],        // [home_team, away_team, goals_home, goals_away]
    [1, 2, null, null],  // null = unplayed match
    [2, 0, 1, 0]
  ],
  "elo_values": [1500.0, 1600.0, 1400.0],
  "team_names": ["Bayern", "Dortmund", "Leipzig"],
  "iterations": 10000,
  "mod_factor": 20.0,
  "home_advantage": 65.0
}
```

**Optional fields:**
```json
{
  "adj_points": [0, 0, 0],
  "adj_goals": [0, 0, 0], 
  "adj_goals_against": [0, 0, 0],
  "adj_goal_diff": [0, 0, 0]
}
```

**Response:**
```json
{
  "probability_matrix": [
    [0.45, 0.35, 0.20],  // Bayern: 45% 1st, 35% 2nd, 20% 3rd
    [0.35, 0.40, 0.25],  // Dortmund probabilities
    [0.20, 0.25, 0.55]   // Leipzig probabilities
  ],
  "team_names": ["Bayern", "Dortmund", "Leipzig"],
  "simulations_performed": 10000,
  "time_ms": 27
}
```

### Batch Simulate
```
POST /simulate/batch
```

**Request:**
```json
{
  "leagues": [
    {
      "name": "Bundesliga",
      "request": {
        "schedule": [...],
        "elo_values": [...],
        "team_names": [...],
        "iterations": 10000
      }
    }
  ]
}
```

**Response:**
```json
{
  "results": [
    {
      "name": "Bundesliga",
      "response": {
        "probability_matrix": [...],
        "team_names": [...],
        "simulations_performed": 10000,
        "time_ms": 27
      }
    }
  ],
  "total_time_ms": 58
}
```

## Data Format Requirements

### Team Indices
- **Must be 0-based**: First team is `0`, second is `1`, etc.
- **Range**: `0` to `team_count - 1`

### Schedule Format
- Each match: `[home_team_index, away_team_index, goals_home, goals_away]`
- Use `null` for goals in unplayed matches
- Team indices must reference existing teams

### Array Lengths
All arrays must have same length as number of teams:
- `elo_values.length == team_names.length`
- `adj_*` arrays (if provided) must match team count

### Data Types
- Team indices: integers
- ELO values: floats
- Goals: integers or `null`
- Iterations: positive integer

## Error Responses

**422 Unprocessable Entity** - Validation failed:
```json
{
  "error": "Team index 18 out of range for 18 teams (valid range: 0-17)"
}
```

**400 Bad Request** - Invalid JSON or missing fields

**500 Internal Server Error** - Server processing error

## Performance
- **Speed**: 370,000+ simulations/second
- **Typical response time**: 20-50ms for 10,000 simulations
- **Memory usage**: ~50MB for 18-team league