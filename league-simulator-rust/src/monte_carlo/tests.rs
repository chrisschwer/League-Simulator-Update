use super::*;
use crate::models::Match;

#[test]
fn test_monte_carlo_basic() {
    // Create a simple season with mostly played matches
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: Some(3), goals_away: Some(0) },
            Match { team_home: 1, team_away: 2, goals_home: Some(1), goals_away: Some(1) },
            Match { team_home: 2, team_away: 0, goals_home: Some(0), goals_away: Some(2) },
            Match { team_home: 1, team_away: 0, goals_home: None, goals_away: None },  // To simulate
            Match { team_home: 0, team_away: 2, goals_home: None, goals_away: None },  // To simulate
            Match { team_home: 2, team_away: 1, goals_home: None, goals_away: None },  // To simulate
        ],
        team_elos: vec![1600.0, 1500.0, 1400.0],
        number_teams: 3,
    };
    
    let params = SimulationParams {
        iterations: 100,  // Small number for testing
        ..Default::default()
    };
    
    let team_names = vec!["Team A".to_string(), "Team B".to_string(), "Team C".to_string()];
    
    let result = run_monte_carlo_simulation(&season, &params, team_names.clone());
    
    // Check basic properties
    assert_eq!(result.probability_matrix.len(), 3, "Should have 3 teams");
    assert_eq!(result.probability_matrix[0].len(), 3, "Should have 3 positions");
    assert_eq!(result.team_names.len(), 3, "Should have 3 team names");
    
    // Check probabilities sum to 1 for each team
    for team_probs in &result.probability_matrix {
        let sum: f64 = team_probs.iter().sum();
        assert!((sum - 1.0).abs() < 0.001, "Probabilities should sum to 1, got {}", sum);
    }
    
    // Team 0 (highest ELO and good results) should likely finish high
    // Note: With only 100 iterations this is probabilistic, not guaranteed
    println!("Team probabilities:");
    for (i, name) in result.team_names.iter().enumerate() {
        println!("{}: {:?}", name, result.probability_matrix[i]);
    }
}

#[test]
fn test_monte_carlo_with_adjustments() {
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: None, goals_away: None },
            Match { team_home: 1, team_away: 2, goals_home: None, goals_away: None },
            Match { team_home: 2, team_away: 0, goals_home: None, goals_away: None },
        ],
        team_elos: vec![1500.0, 1500.0, 1500.0],  // Equal teams
        number_teams: 3,
    };
    
    let params = SimulationParams {
        iterations: 100,
        ..Default::default()
    };
    
    let team_names = vec!["Team A".to_string(), "Team B".to_string(), "Team C (2nd)".to_string()];
    
    // Penalize team 2 (like Liga 3 second teams)
    let adj_points = Some(vec![0, 0, -50]);
    
    let result = run_monte_carlo_with_adjustments(
        &season,
        &params,
        team_names,
        adj_points,
        None,
        None,
        None,
    );
    
    // Team 2 should almost certainly finish last due to -50 points penalty
    // Find team 2 in the results (it might not be at index 2 due to sorting)
    let team_c_idx = result.team_names.iter().position(|n| n.contains("(2nd)")).unwrap();
    let last_position_prob = result.probability_matrix[team_c_idx][2];  // Position 3 (index 2)
    
    assert!(
        last_position_prob > 0.9,
        "Team with -50 points should almost certainly finish last, got probability {}",
        last_position_prob
    );
}

#[test]
fn test_monte_carlo_deterministic() {
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: None, goals_away: None },
        ],
        team_elos: vec![1500.0, 1500.0],
        number_teams: 2,
    };
    
    let params = SimulationParams {
        iterations: 50,
        ..Default::default()
    };
    
    let team_names = vec!["A".to_string(), "B".to_string()];
    
    // Run twice - should get same results due to seeded RNG
    let result1 = run_monte_carlo_simulation(&season, &params, team_names.clone());
    let result2 = run_monte_carlo_simulation(&season, &params, team_names.clone());
    
    // Results should be identical
    for i in 0..2 {
        for j in 0..2 {
            assert_eq!(
                result1.probability_matrix[i][j],
                result2.probability_matrix[i][j],
                "Results should be deterministic"
            );
        }
    }
}

#[test]
fn test_monte_carlo_all_played_matches() {
    // When all matches are played, every simulation should give same result
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: Some(2), goals_away: Some(0) },
            Match { team_home: 1, team_away: 2, goals_home: Some(1), goals_away: Some(3) },
            Match { team_home: 2, team_away: 0, goals_home: Some(1), goals_away: Some(1) },
        ],
        team_elos: vec![1500.0, 1600.0, 1400.0],
        number_teams: 3,
    };
    
    let params = SimulationParams {
        iterations: 10,  // Few iterations since result is deterministic
        ..Default::default()
    };
    
    let team_names = vec!["A".to_string(), "B".to_string(), "C".to_string()];
    let result = run_monte_carlo_simulation(&season, &params, team_names);
    
    // Each team should have probability 1.0 for exactly one position
    for team_probs in &result.probability_matrix {
        let ones = team_probs.iter().filter(|&&p| p == 1.0).count();
        let zeros = team_probs.iter().filter(|&&p| p == 0.0).count();
        
        assert_eq!(ones, 1, "Each team should have exactly one position with probability 1.0");
        assert_eq!(zeros, 2, "Each team should have exactly two positions with probability 0.0");
    }
}

#[test]
fn test_parallel_performance() {
    use std::time::Instant;
    
    let season = Season {
        matches: (0..90).map(|i| {
            Match {
                team_home: i % 10,
                team_away: (i / 10) % 10,
                goals_home: if i < 45 { Some((i % 3) as i32) } else { None },
                goals_away: if i < 45 { Some((i % 2) as i32) } else { None },
            }
        }).collect(),
        team_elos: vec![1500.0; 10],
        number_teams: 10,
    };
    
    let params = SimulationParams {
        iterations: 100,
        ..Default::default()
    };
    
    let team_names: Vec<String> = (0..10).map(|i| format!("Team {}", i)).collect();
    
    let start = Instant::now();
    let _result = run_monte_carlo_simulation(&season, &params, team_names);
    let duration = start.elapsed();
    
    println!("Monte Carlo simulation with 100 iterations took: {:?}", duration);
    
    // Just ensure it completes without panic
    assert!(duration.as_secs() < 10, "Simulation should complete in reasonable time");
}