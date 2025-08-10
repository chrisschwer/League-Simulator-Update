use league_simulator_rust::*;
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

#[test]
fn test_exact_elo_compatibility_with_r() {
    // Load test data generated from R
    let data = fs::read_to_string("test_data/elo_test_cases.json")
        .expect("Failed to read test data - run extract_test_data.R first");
    
    let test_data: EloTestData = serde_json::from_str(&data)
        .expect("Failed to parse test data");
    
    println!("Running {} ELO compatibility tests against R implementation", test_data.test_cases.len());
    
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
        
        // Verify exact match with R implementation (within floating point precision)
        let tolerance = 0.0000001;  // Very tight tolerance
        
        assert!(
            (result.new_elo_home - test_case.expected[0]).abs() < tolerance,
            "{}: ELO home mismatch. Rust: {}, R: {}", 
            test_case.name, result.new_elo_home, test_case.expected[0]
        );
        
        assert!(
            (result.new_elo_away - test_case.expected[1]).abs() < tolerance,
            "{}: ELO away mismatch. Rust: {}, R: {}",
            test_case.name, result.new_elo_away, test_case.expected[1]
        );
        
        assert_eq!(
            result.goals_home, test_case.expected[2] as i32,
            "{}: Goals home mismatch", test_case.name
        );
        
        assert_eq!(
            result.goals_away, test_case.expected[3] as i32,
            "{}: Goals away mismatch", test_case.name
        );
        
        assert!(
            (result.win_probability_home - test_case.expected[4]).abs() < tolerance,
            "{}: Win probability mismatch. Rust: {}, R: {}",
            test_case.name, result.win_probability_home, test_case.expected[4]
        );
    }
    
    println!("✅ All ELO calculations match R implementation exactly!");
}