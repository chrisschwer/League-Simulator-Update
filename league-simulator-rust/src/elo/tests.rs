use super::*;
use approx::assert_relative_eq;
use serde_json;
use std::fs;

#[derive(serde::Deserialize)]
struct EloTestCase {
    name: String,
    input: EloTestInput,
    expected: Vec<f64>,
}

#[derive(serde::Deserialize)]
struct EloTestInput {
    elo_home: f64,
    elo_away: f64,
    goals_home: i32,
    goals_away: i32,
    mod_factor: f64,
    home_advantage: f64,
}

#[derive(serde::Deserialize)]
struct EloTestData {
    test_cases: Vec<EloTestCase>,
}

fn load_test_cases() -> EloTestData {
    let data = fs::read_to_string("test_data/elo_test_cases.json")
        .expect("Failed to read test data file");
    serde_json::from_str(&data).expect("Failed to parse test data")
}

#[test]
fn test_elo_calculations_match_r_implementation() {
    let test_data = load_test_cases();
    
    for test_case in test_data.test_cases {
        println!("Testing: {}", test_case.name);
        
        let params = EloParams {
            elo_home: test_case.input.elo_home,
            elo_away: test_case.input.elo_away,
            goals_home: test_case.input.goals_home,
            goals_away: test_case.input.goals_away,
            mod_factor: test_case.input.mod_factor,
            home_advantage: test_case.input.home_advantage,
        };
        
        let result = calculate_elo_change(&params);
        
        // Check against R implementation results
        assert_relative_eq!(
            result.new_elo_home,
            test_case.expected[0],
            epsilon = 0.0001,
            max_relative = 0.0001
        );
        
        assert_relative_eq!(
            result.new_elo_away,
            test_case.expected[1],
            epsilon = 0.0001,
            max_relative = 0.0001
        );
        
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
        
        assert_relative_eq!(
            result.win_probability_home,
            test_case.expected[4],
            epsilon = 0.0001,
            max_relative = 0.0001
        );
    }
}

#[test]
fn test_elo_conservation() {
    // ELO changes should sum to zero (conservation principle)
    let params = EloParams {
        elo_home: 1500.0,
        elo_away: 1600.0,
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let result = calculate_elo_change(&params);
    let home_change = result.new_elo_home - params.elo_home;
    let away_change = result.new_elo_away - params.elo_away;
    
    assert_relative_eq!(
        home_change + away_change,
        0.0,
        epsilon = 0.0001
    );
}

#[test]
fn test_draw_smaller_elo_change_than_win() {
    let draw_params = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 1,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let win_params = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let draw_result = calculate_elo_change(&draw_params);
    let win_result = calculate_elo_change(&win_params);
    
    let draw_change = (draw_result.new_elo_home - draw_params.elo_home).abs();
    let win_change = (win_result.new_elo_home - win_params.elo_home).abs();
    
    assert!(
        draw_change < win_change,
        "Draw should produce smaller ELO change than win"
    );
}

#[test]
fn test_underdog_win_larger_change() {
    // Underdog winning should produce larger ELO change
    let underdog_wins = EloParams {
        elo_home: 1300.0,  // Underdog
        elo_away: 1700.0,  // Favorite
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let favorite_wins = EloParams {
        elo_home: 1700.0,  // Favorite
        elo_away: 1300.0,  // Underdog
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let underdog_result = calculate_elo_change(&underdog_wins);
    let favorite_result = calculate_elo_change(&favorite_wins);
    
    let underdog_gain = underdog_result.new_elo_home - underdog_wins.elo_home;
    let favorite_gain = favorite_result.new_elo_home - favorite_wins.elo_home;
    
    assert!(
        underdog_gain > favorite_gain,
        "Underdog win should produce larger ELO gain than favorite win"
    );
}

#[test]
fn test_goal_difference_effect() {
    // Larger goal difference should produce larger ELO change
    let small_win = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 1,
        goals_away: 0,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let large_win = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 5,
        goals_away: 0,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let small_result = calculate_elo_change(&small_win);
    let large_result = calculate_elo_change(&large_win);
    
    let small_change = small_result.new_elo_home - small_win.elo_home;
    let large_change = large_result.new_elo_home - large_win.elo_home;
    
    assert!(
        large_change > small_change,
        "Larger goal difference should produce larger ELO change"
    );
}

#[test]
fn test_home_advantage_effect() {
    // Home advantage should affect win probability
    let no_advantage = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 0.0,
    };
    
    let with_advantage = EloParams {
        elo_home: 1500.0,
        elo_away: 1500.0,
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 65.0,
    };
    
    let no_adv_result = calculate_elo_change(&no_advantage);
    let with_adv_result = calculate_elo_change(&with_advantage);
    
    assert!(
        with_adv_result.win_probability_home > no_adv_result.win_probability_home,
        "Home advantage should increase home win probability"
    );
    
    // With home advantage, winning as expected should produce smaller ELO change
    let home_change_no_adv = no_adv_result.new_elo_home - no_advantage.elo_home;
    let home_change_with_adv = with_adv_result.new_elo_home - with_advantage.elo_home;
    
    assert!(
        home_change_with_adv < home_change_no_adv,
        "Winning with home advantage should produce smaller ELO gain"
    );
}