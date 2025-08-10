use crate::elo::calculate_elo_change;
use crate::models::EloParams;
use crate::models::{Match, Season, LeagueTable, TeamStanding};
use crate::simulation::match_sim::simulate_match_random;
use rand::Rng;

/// Simulates a complete season, updating ELO values as matches are played
/// Matches the logic in SaisonSimulierenCPP.R
pub fn simulate_season<R: Rng>(
    season: &Season,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    rng: &mut R,
) -> (Vec<Match>, Vec<f64>) {
    let mut matches = season.matches.clone();
    let mut elos = season.team_elos.clone();
    
    for match_data in &mut matches {
        let team_home = match_data.team_home;
        let team_away = match_data.team_away;
        
        // Check if match needs to be simulated
        if match_data.goals_home.is_none() {
            // Simulate the match
            let result = simulate_match_random(
                elos[team_home],
                elos[team_away],
                mod_factor,
                home_advantage,
                tore_slope,
                tore_intercept,
                rng,
            );
            
            // Update match results
            match_data.goals_home = Some(result.goals_home);
            match_data.goals_away = Some(result.goals_away);
            
            // Update ELO values
            elos[team_home] = result.new_elo_home;
            elos[team_away] = result.new_elo_away;
        } else {
            // Match already played, just update ELO
            let params = EloParams {
                elo_home: elos[team_home],
                elo_away: elos[team_away],
                goals_home: match_data.goals_home.unwrap(),
                goals_away: match_data.goals_away.unwrap(),
                mod_factor,
                home_advantage,
            };
            
            let result = calculate_elo_change(&params);
            elos[team_home] = result.new_elo_home;
            elos[team_away] = result.new_elo_away;
        }
    }
    
    (matches, elos)
}

/// Calculate league table from match results
/// Matches the logic in Tabelle.R
pub fn calculate_table(
    matches: &[Match],
    number_teams: usize,
    adj_points: Option<&[i32]>,
    adj_goals: Option<&[i32]>,
    adj_goals_against: Option<&[i32]>,
    adj_goal_diff: Option<&[i32]>,
) -> LeagueTable {
    let mut standings: Vec<TeamStanding> = (0..number_teams)
        .map(|i| TeamStanding {
            team_id: i,
            played: 0,
            won: 0,
            drawn: 0,
            lost: 0,
            goals_for: adj_goals.map(|a| a[i]).unwrap_or(0),
            goals_against: adj_goals_against.map(|a| a[i]).unwrap_or(0),
            goal_difference: adj_goal_diff.map(|a| a[i]).unwrap_or(0),
            points: adj_points.map(|a| a[i]).unwrap_or(0),
            position: 0,
        })
        .collect();
    
    // Process all matches
    for match_data in matches {
        if let (Some(goals_home), Some(goals_away)) = (match_data.goals_home, match_data.goals_away) {
            let home_idx = match_data.team_home;
            let away_idx = match_data.team_away;
            
            // Update games played
            standings[home_idx].played += 1;
            standings[away_idx].played += 1;
            
            // Update goals
            standings[home_idx].goals_for += goals_home;
            standings[home_idx].goals_against += goals_away;
            standings[away_idx].goals_for += goals_away;
            standings[away_idx].goals_against += goals_home;
            
            // Update goal difference
            standings[home_idx].goal_difference += goals_home - goals_away;
            standings[away_idx].goal_difference += goals_away - goals_home;
            
            // Update points and W/D/L
            if goals_home > goals_away {
                standings[home_idx].won += 1;
                standings[home_idx].points += 3;
                standings[away_idx].lost += 1;
            } else if goals_home < goals_away {
                standings[away_idx].won += 1;
                standings[away_idx].points += 3;
                standings[home_idx].lost += 1;
            } else {
                standings[home_idx].drawn += 1;
                standings[home_idx].points += 1;
                standings[away_idx].drawn += 1;
                standings[away_idx].points += 1;
            }
        }
    }
    
    // Sort by points (descending), then goal difference, then goals for
    standings.sort_by(|a, b| {
        b.points.cmp(&a.points)
            .then_with(|| b.goal_difference.cmp(&a.goal_difference))
            .then_with(|| b.goals_for.cmp(&a.goals_for))
    });
    
    // Update positions
    for (pos, standing) in standings.iter_mut().enumerate() {
        standing.position = pos + 1;
    }
    
    LeagueTable { standings }
}

/// Process a season with played and unplayed matches
/// Returns the final table after simulating remaining matches
pub fn process_season<R: Rng>(
    season: &Season,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    adj_points: Option<&[i32]>,
    adj_goals: Option<&[i32]>,
    adj_goals_against: Option<&[i32]>,
    adj_goal_diff: Option<&[i32]>,
    rng: &mut R,
) -> (LeagueTable, Vec<f64>) {
    // Simulate the season
    let (completed_matches, final_elos) = simulate_season(
        season,
        mod_factor,
        home_advantage,
        tore_slope,
        tore_intercept,
        rng,
    );
    
    // Calculate the table
    let table = calculate_table(
        &completed_matches,
        season.number_teams,
        adj_points,
        adj_goals,
        adj_goals_against,
        adj_goal_diff,
    );
    
    (table, final_elos)
}