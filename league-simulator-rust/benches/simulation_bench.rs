use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use league_simulator_rust::*;

fn create_bundesliga_season() -> Season {
    // Create a realistic Bundesliga season (18 teams, 306 matches)
    let mut matches = Vec::new();
    for home in 0..18 {
        for away in 0..18 {
            if home != away {
                matches.push(Match {
                    team_home: home,
                    team_away: away,
                    goals_home: if home < 9 && away < 9 { 
                        Some((home % 3) as i32) 
                    } else { 
                        None 
                    },
                    goals_away: if home < 9 && away < 9 { 
                        Some((away % 2) as i32) 
                    } else { 
                        None 
                    },
                });
            }
        }
    }
    
    let team_elos = vec![
        1850.0, 1800.0, 1750.0, 1700.0, 1650.0, 1600.0,  // Top teams
        1550.0, 1500.0, 1500.0, 1500.0, 1500.0, 1450.0,  // Mid table
        1450.0, 1400.0, 1400.0, 1350.0, 1300.0, 1250.0,  // Bottom teams
    ];
    
    Season {
        matches,
        team_elos,
        number_teams: 18,
    }
}

fn benchmark_elo_calculation(c: &mut Criterion) {
    let params = EloParams {
        elo_home: 1500.0,
        elo_away: 1600.0,
        goals_home: 2,
        goals_away: 1,
        mod_factor: 40.0,
        home_advantage: 65.0,
    };
    
    c.bench_function("elo_calculation", |b| {
        b.iter(|| calculate_elo_change(black_box(&params)))
    });
}

fn benchmark_monte_carlo(c: &mut Criterion) {
    let season = create_bundesliga_season();
    let team_names: Vec<String> = (0..18).map(|i| format!("Team {}", i + 1)).collect();
    
    let mut group = c.benchmark_group("monte_carlo");
    
    for iterations in [100, 1000, 10000] {
        let params = SimulationParams {
            iterations,
            ..Default::default()
        };
        
        group.bench_with_input(
            BenchmarkId::from_parameter(iterations),
            &iterations,
            |b, _| {
                b.iter(|| {
                    run_monte_carlo_simulation(
                        black_box(&season),
                        black_box(&params),
                        black_box(team_names.clone()),
                    )
                })
            },
        );
    }
    group.finish();
}

fn benchmark_single_season_simulation(c: &mut Criterion) {
    use rand::SeedableRng;
    use rand::rngs::StdRng;
    
    let season = create_bundesliga_season();
    
    c.bench_function("single_season_simulation", |b| {
        b.iter(|| {
            let mut rng = StdRng::seed_from_u64(42);
            simulate_season(
                black_box(&season),
                20.0,
                65.0,
                0.0017854953143549,
                1.3218390804597700,
                &mut rng,
            )
        })
    });
}

criterion_group!(
    benches,
    benchmark_elo_calculation,
    benchmark_single_season_simulation,
    benchmark_monte_carlo
);
criterion_main!(benches);