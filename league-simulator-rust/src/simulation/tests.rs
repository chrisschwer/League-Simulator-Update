use super::*;
use crate::models::{Match, Season};
use approx::assert_relative_eq;
use serde_json;
use std::fs;

#[derive(serde::Deserialize)]
struct MatchSimTestCase {
    name: String,
    input: MatchSimInput,
    expected: Vec<f64>,
}

#[derive(serde::Deserialize)]
struct MatchSimInput {
    elo_home: f64,
    elo_away: f64,
    mod_factor: f64,
    home_advantage: f64,
    tore_slope: f64,
    tore_intercept: f64,
    random_home: f64,
    random_away: f64,
}

#[derive(serde::Deserialize)]
struct MatchSimTestData {
    test_cases: Vec<MatchSimTestCase>,
}

#[test]
fn test_match_simulation_matches_r() {
    let data = fs::read_to_string("test_data/match_simulation_cases.json")
        .expect("Failed to read match simulation test data");
    let test_data: MatchSimTestData = serde_json::from_str(&data)
        .expect("Failed to parse match simulation test data");
    
    for test_case in test_data.test_cases {
        println!("Testing match simulation: {}", test_case.name);
        
        let result = simulate_match(
            test_case.input.elo_home,
            test_case.input.elo_away,
            test_case.input.mod_factor,
            test_case.input.home_advantage,
            test_case.input.tore_slope,
            test_case.input.tore_intercept,
            test_case.input.random_home,
            test_case.input.random_away,
        );
        
        // Check ELO changes
        assert_relative_eq!(
            result.new_elo_home,
            test_case.expected[0],
            epsilon = 0.001,
            max_relative = 0.001
        );
        
        assert_relative_eq!(
            result.new_elo_away,
            test_case.expected[1],
            epsilon = 0.001,
            max_relative = 0.001
        );
        
        // Check goals
        assert_eq!(
            result.goals_home,
            test_case.expected[2] as i32,
            "{}: Goals home mismatch", test_case.name
        );
        
        assert_eq!(
            result.goals_away,
            test_case.expected[3] as i32,
            "{}: Goals away mismatch", test_case.name
        );
    }
}

#[test]
fn test_season_simulation() {
    use rand::SeedableRng;
    use rand::rngs::StdRng;
    
    // Create a simple season with 3 teams
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: Some(2), goals_away: Some(1) },
            Match { team_home: 1, team_away: 2, goals_home: Some(1), goals_away: Some(1) },
            Match { team_home: 2, team_away: 0, goals_home: None, goals_away: None },  // To simulate
            Match { team_home: 0, team_away: 2, goals_home: None, goals_away: None },  // To simulate
            Match { team_home: 1, team_away: 0, goals_home: None, goals_away: None },  // To simulate
            Match { team_home: 2, team_away: 1, goals_home: None, goals_away: None },  // To simulate
        ],
        team_elos: vec![1500.0, 1600.0, 1400.0],
        number_teams: 3,
    };
    
    let mut rng = StdRng::seed_from_u64(42);
    
    let (completed_matches, final_elos) = simulate_season(
        &season,
        20.0,  // mod_factor
        65.0,  // home_advantage
        0.0017854953143549,  // tore_slope
        1.3218390804597700,  // tore_intercept
        &mut rng,
    );
    
    // Check that all matches have results
    for match_data in &completed_matches {
        assert!(match_data.goals_home.is_some(), "Match should have home goals");
        assert!(match_data.goals_away.is_some(), "Match should have away goals");
    }
    
    // Check that ELO values have been updated
    assert_eq!(final_elos.len(), 3, "Should have 3 team ELOs");
    
    // ELOs should have changed from initial values
    assert_ne!(final_elos[0], 1500.0, "Team 0 ELO should have changed");
    assert_ne!(final_elos[1], 1600.0, "Team 1 ELO should have changed");
    assert_ne!(final_elos[2], 1400.0, "Team 2 ELO should have changed");
}

#[test]
fn test_table_calculation() {
    let matches = vec![
        Match { team_home: 0, team_away: 1, goals_home: Some(2), goals_away: Some(1) },
        Match { team_home: 1, team_away: 2, goals_home: Some(3), goals_away: Some(1) },
        Match { team_home: 2, team_away: 0, goals_home: Some(0), goals_away: Some(0) },
    ];
    
    let table = calculate_table(&matches, 3, None, None, None, None);
    
    // Check standings
    assert_eq!(table.standings.len(), 3, "Should have 3 teams");
    
    // Team 0: W1 D1 L0, 4 points
    let team0 = table.standings.iter().find(|s| s.team_id == 0).unwrap();
    assert_eq!(team0.won, 1, "Team 0 wins");
    assert_eq!(team0.drawn, 1, "Team 0 draws");
    assert_eq!(team0.lost, 0, "Team 0 losses");
    assert_eq!(team0.points, 4, "Team 0 points");
    assert_eq!(team0.goals_for, 2, "Team 0 goals for");
    assert_eq!(team0.goals_against, 1, "Team 0 goals against");
    
    // Team 1: W1 D0 L1, 3 points
    let team1 = table.standings.iter().find(|s| s.team_id == 1).unwrap();
    assert_eq!(team1.won, 1, "Team 1 wins");
    assert_eq!(team1.drawn, 0, "Team 1 draws");
    assert_eq!(team1.lost, 1, "Team 1 losses");
    assert_eq!(team1.points, 3, "Team 1 points");
    
    // Team 2: W0 D1 L1, 1 point
    let team2 = table.standings.iter().find(|s| s.team_id == 2).unwrap();
    assert_eq!(team2.won, 0, "Team 2 wins");
    assert_eq!(team2.drawn, 1, "Team 2 draws");
    assert_eq!(team2.lost, 1, "Team 2 losses");
    assert_eq!(team2.points, 1, "Team 2 points");
    
    // Check positions (Team 0 should be first)
    assert_eq!(table.standings[0].team_id, 0, "Team 0 should be first");
    assert_eq!(table.standings[0].position, 1, "First position should be 1");
}

#[test]
fn test_table_with_adjustments() {
    let matches = vec![
        Match { team_home: 0, team_away: 1, goals_home: Some(1), goals_away: Some(1) },
    ];
    
    let adj_points = vec![-50, 0, 0];  // Penalize team 0
    let table = calculate_table(&matches, 3, Some(&adj_points), None, None, None);
    
    // Team 0 should have 1 - 50 = -49 points
    let team0 = table.standings.iter().find(|s| s.team_id == 0).unwrap();
    assert_eq!(team0.points, -49, "Team 0 should be penalized");
    
    // Team 0 should be last despite drawing
    assert_eq!(table.standings[2].team_id, 0, "Team 0 should be last");
}

#[test]
fn test_poisson_quantile() {
    // Test some known values
    // For lambda=1.5, p=0.5 should give approximately 1
    let q = poisson_quantile_statrs(0.5, 1.5);
    assert!(q >= 1.0 && q <= 2.0, "Median of Poisson(1.5) should be around 1-2");
    
    // Edge cases
    assert_eq!(poisson_quantile_statrs(0.0, 1.5), 0.0, "p=0 should give 0");
    assert!(poisson_quantile_statrs(0.99999, 1.5) < 20.0, "p~1 should give finite value");
    
    // Test with different lambdas
    let q_small = poisson_quantile_statrs(0.5, 0.5);
    let q_large = poisson_quantile_statrs(0.5, 5.0);
    assert!(q_large > q_small, "Larger lambda should give larger quantile");
}

#[test]
fn test_deterministic_simulation() {
    use rand::SeedableRng;
    use rand::rngs::StdRng;
    
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: None, goals_away: None },
        ],
        team_elos: vec![1500.0, 1500.0],
        number_teams: 2,
    };
    
    // Run simulation twice with same seed
    let mut rng1 = StdRng::seed_from_u64(12345);
    let (matches1, _) = simulate_season(&season, 20.0, 65.0, 0.0017854953143549, 1.3218390804597700, &mut rng1);
    
    let mut rng2 = StdRng::seed_from_u64(12345);
    let (matches2, _) = simulate_season(&season, 20.0, 65.0, 0.0017854953143549, 1.3218390804597700, &mut rng2);
    
    // Results should be identical
    assert_eq!(matches1[0].goals_home, matches2[0].goals_home, "Same seed should give same home goals");
    assert_eq!(matches1[0].goals_away, matches2[0].goals_away, "Same seed should give same away goals");
}