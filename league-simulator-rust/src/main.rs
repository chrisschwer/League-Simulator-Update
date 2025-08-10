use league_simulator_rust::*;
use std::time::Instant;

fn main() {
    println!("League Simulator Rust - High Performance Monte Carlo Engine");
    println!("============================================================");
    
    // Example usage - will be replaced with REST API server
    let season = Season {
        matches: vec![
            Match { team_home: 0, team_away: 1, goals_home: Some(2), goals_away: Some(1) },
            Match { team_home: 1, team_away: 2, goals_home: None, goals_away: None },
            Match { team_home: 2, team_away: 0, goals_home: None, goals_away: None },
        ],
        team_elos: vec![1500.0, 1600.0, 1400.0],
        number_teams: 3,
    };
    
    let params = SimulationParams {
        iterations: 1000,
        ..Default::default()
    };
    
    let team_names = vec![
        "Bayern Munich".to_string(),
        "Borussia Dortmund".to_string(),
        "RB Leipzig".to_string(),
    ];
    
    println!("\nRunning {} Monte Carlo simulations...", params.iterations);
    let start = Instant::now();
    
    let result = run_monte_carlo_simulation(&season, &params, team_names);
    
    let duration = start.elapsed();
    println!("Completed in {:.2?}", duration);
    
    println!("\nProbability Matrix (Team x Position):");
    println!("Team                  | 1st    | 2nd    | 3rd    |");
    println!("--------------------- |--------|--------|--------|");
    
    for (i, team_name) in result.team_names.iter().enumerate() {
        print!("{:20} |", team_name);
        for prob in &result.probability_matrix[i] {
            print!(" {:.2}% |", prob * 100.0);
        }
        println!();
    }
    
    println!("\nPerformance: {:.0} simulations/second", 
             params.iterations as f64 / duration.as_secs_f64());
}