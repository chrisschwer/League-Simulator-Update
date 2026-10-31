use super::*;
use crate::models::Match;

#[test]
fn test_monte_carlo_basic() {
    // Create a simple season with mostly played matches
    let season = Season {
        matches: vec![
            Match {
                team_home: 0,
                team_away: 1,
                goals_home: Some(3),
                goals_away: Some(0),
                elo_neutral: false,
            },
            Match {
                team_home: 1,
                team_away: 2,
                goals_home: Some(1),
                goals_away: Some(1),
                elo_neutral: false,
            },
            Match {
                team_home: 2,
                team_away: 0,
                goals_home: Some(0),
                goals_away: Some(2),
                elo_neutral: false,
            },
            Match {
                team_home: 1,
                team_away: 0,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            }, // To simulate
            Match {
                team_home: 0,
                team_away: 2,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            }, // To simulate
            Match {
                team_home: 2,
                team_away: 1,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            }, // To simulate
        ],
        team_elos: vec![1600.0, 1500.0, 1400.0],
        number_teams: 3,
    };

    let params = SimulationParams {
        iterations: 100, // Small number for testing
        ..Default::default()
    };

    let team_names = vec![
        "Team A".to_string(),
        "Team B".to_string(),
        "Team C".to_string(),
    ];

    let result = run_monte_carlo_simulation(&season, &params, team_names.clone());

    // Check basic properties
    assert_eq!(result.probability_matrix.len(), 3, "Should have 3 teams");
    assert_eq!(
        result.probability_matrix[0].len(),
        3,
        "Should have 3 positions"
    );
    assert_eq!(result.team_names.len(), 3, "Should have 3 team names");

    // Check probabilities sum to 1 for each team
    for team_probs in &result.probability_matrix {
        let sum: f64 = team_probs.iter().sum();
        assert!(
            (sum - 1.0).abs() < 0.001,
            "Probabilities should sum to 1, got {}",
            sum
        );
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
            Match {
                team_home: 0,
                team_away: 1,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
            Match {
                team_home: 1,
                team_away: 2,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
            Match {
                team_home: 2,
                team_away: 0,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
        ],
        team_elos: vec![1500.0, 1500.0, 1500.0], // Equal teams
        number_teams: 3,
    };

    let params = SimulationParams {
        iterations: 100,
        // Penalize team 2 (like Liga 3 second teams)
        adj_points: Some(vec![0, 0, -50]),
        ..Default::default()
    };

    let team_names = vec![
        "Team A".to_string(),
        "Team B".to_string(),
        "Team C (2nd)".to_string(),
    ];

    let result = run_monte_carlo_simulation(&season, &params, team_names);

    // Team 2 should almost certainly finish last due to -50 points penalty
    // Find team 2 in the results (it might not be at index 2 due to sorting)
    let team_c_idx = result
        .team_names
        .iter()
        .position(|n| n.contains("(2nd)"))
        .unwrap();
    let last_position_prob = result.probability_matrix[team_c_idx][2]; // Position 3 (index 2)

    assert!(
        last_position_prob > 0.9,
        "Team with -50 points should almost certainly finish last, got probability {}",
        last_position_prob
    );
}

#[test]
fn seeded_run_is_idempotent_and_sensitive_to_the_seed() {
    // Pins two halves of the seeded contract — see issue #96.
    //
    // (1) Idempotence: same `master_seed` → identical probability matrix.
    //     Catches "seed is silently ignored" (e.g. the function pulls from
    //     `thread_rng()` instead of seeding from the parameter).
    //
    // (2) Sensitivity: different `master_seed` → different probability matrix.
    //     Catches "seed is consumed but flattened to a constant" (e.g. someone
    //     replaces `master_seed` with `0` or hard-codes the per-iteration seed
    //     vector).
    //
    // Neither assertion is bit-exact against a recorded reference value, so
    // refactoring how `process_season` consumes RNG values won't break this
    // test as long as the seeded variant remains genuinely deterministic and
    // genuinely seed-dependent.
    let season = Season {
        matches: vec![
            Match {
                team_home: 0,
                team_away: 1,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
            Match {
                team_home: 1,
                team_away: 2,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
            Match {
                team_home: 2,
                team_away: 0,
                goals_home: None,
                goals_away: None,
                elo_neutral: false,
            },
        ],
        team_elos: vec![1500.0, 1500.0, 1500.0],
        number_teams: 3,
    };

    let params = SimulationParams {
        iterations: 200,
        ..Default::default()
    };

    let team_names = vec!["A".to_string(), "B".to_string(), "C".to_string()];

    let same_a = run_monte_carlo_simulation_seeded(&season, &params, team_names.clone(), 42);
    let same_b = run_monte_carlo_simulation_seeded(&season, &params, team_names.clone(), 42);
    let other = run_monte_carlo_simulation_seeded(&season, &params, team_names.clone(), 43);

    assert_eq!(
        same_a.probability_matrix, same_b.probability_matrix,
        "Same seed produced different probability matrices — the seed is being ignored"
    );
    assert_ne!(
        same_a.probability_matrix, other.probability_matrix,
        "Distinct seeds produced bit-identical probability matrices — the seed has no effect"
    );
}

#[test]
fn test_monte_carlo_all_played_matches() {
    // When all matches are played, every simulation should give same result
    let season = Season {
        matches: vec![
            Match {
                team_home: 0,
                team_away: 1,
                goals_home: Some(2),
                goals_away: Some(0),
                elo_neutral: false,
            },
            Match {
                team_home: 1,
                team_away: 2,
                goals_home: Some(1),
                goals_away: Some(3),
                elo_neutral: false,
            },
            Match {
                team_home: 2,
                team_away: 0,
                goals_home: Some(1),
                goals_away: Some(1),
                elo_neutral: false,
            },
        ],
        team_elos: vec![1500.0, 1600.0, 1400.0],
        number_teams: 3,
    };

    let params = SimulationParams {
        iterations: 10, // Few iterations since result is deterministic
        ..Default::default()
    };

    let team_names = vec!["A".to_string(), "B".to_string(), "C".to_string()];
    let result = run_monte_carlo_simulation(&season, &params, team_names);

    // Each team should have probability 1.0 for exactly one position
    for team_probs in &result.probability_matrix {
        let ones = team_probs.iter().filter(|&&p| p == 1.0).count();
        let zeros = team_probs.iter().filter(|&&p| p == 0.0).count();

        assert_eq!(
            ones, 1,
            "Each team should have exactly one position with probability 1.0"
        );
        assert_eq!(
            zeros, 2,
            "Each team should have exactly two positions with probability 0.0"
        );
    }
}

#[test]
fn test_parallel_performance() {
    use std::time::Instant;

    let season = Season {
        matches: (0..90)
            .map(|i| Match {
                team_home: i % 10,
                team_away: (i / 10) % 10,
                goals_home: if i < 45 { Some((i % 3) as i32) } else { None },
                goals_away: if i < 45 { Some((i % 2) as i32) } else { None },
                elo_neutral: false,
            })
            .collect(),
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

    println!(
        "Monte Carlo simulation with 100 iterations took: {:?}",
        duration
    );

    // Just ensure it completes without panic
    assert!(
        duration.as_secs() < 10,
        "Simulation should complete in reasonable time"
    );
}

/// Vier Teams, Hin- und Rueckspiele, alle offen.
fn double_round_robin_open() -> Season {
    let mut matches = Vec::new();
    for h in 0..4 {
        for a in 0..4 {
            if h != a {
                matches.push(Match {
                    team_home: h,
                    team_away: a,
                    goals_home: None,
                    goals_away: None,
                    elo_neutral: false,
                });
            }
        }
    }
    Season {
        matches,
        team_elos: vec![1700.0, 1600.0, 1500.0, 1450.0],
        number_teams: 4,
    }
}

/// Die Berechtigungsmaske ersetzt den frueheren zweiten Lauf mit -50 Punkten
/// (ADR 0009). Mit festem Seed und denselben Parametern muessen beide Wege
/// EXAKT dieselbe Verteilung liefern: Die Punkte der Gesperrten aendern den
/// Spielverlauf nicht (der ELO-Walk haengt nur an den Toren), und mit hoechstens
/// 18 Punkten stehen Teams mit -50 sicher am Tabellenende -- ihre Plaetze
/// sind dann genau die uebrigen Raenge der Berechtigten.
#[test]
fn eligibility_mask_equals_minus_50_run_exactly_with_fixed_seed() {
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();

    let mit_maske = SimulationParams {
        iterations: 3000,
        eligibility_masks: Some(vec![vec![false, true, false, true]]),
        ..SimulationParams::default()
    };
    let mit_malus = SimulationParams {
        iterations: 3000,
        adj_points: Some(vec![-50, 0, -50, 0]),
        ..SimulationParams::default()
    };

    let a = run_monte_carlo_simulation_seeded(&season, &mit_maske, names.clone(), 7);
    let b = run_monte_carlo_simulation_seeded(&season, &mit_malus, names.clone(), 7);
    let rang = &a.eligible_rank_probabilities.as_ref().unwrap()[0];

    for team in ["BBB", "DDD"] {
        let zeile_a = a.team_names.iter().position(|n| n == team).unwrap();
        let zeile_b = b.team_names.iter().position(|n| n == team).unwrap();
        // Rang 1 und 2 unter den Berechtigten = Platz 1 und 2 im Malus-Lauf.
        assert_eq!(
            &rang[zeile_a][..2],
            &b.probability_matrix[zeile_b][..2],
            "{team}"
        );
        // Mehr als zwei Berechtigte gibt es nicht.
        assert!(rang[zeile_a][2..].iter().all(|&p| p == 0.0));
    }
    for team in ["AAA", "CCC"] {
        let zeile = a.team_names.iter().position(|n| n == team).unwrap();
        assert!(rang[zeile].iter().all(|&p| p == 0.0), "{team}");
    }
}

// --- tracked_class_patterns: gemeinsame Klassenvektoren (#322) --------------

fn tracked_params(teams: Vec<usize>, direct: usize, playoff: usize) -> SimulationParams {
    SimulationParams {
        iterations: 4000,
        tracked_teams: Some(teams),
        tracked_direct_places: Some(direct),
        tracked_playoff_places: Some(playoff),
        ..SimulationParams::default()
    }
}

#[test]
fn tracked_patterns_sum_to_iterations_and_respect_place_counts() {
    // Vier Teams, zwei direkte Abstiegsplaetze (3, 4), ein Relegationsplatz (2).
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let params = tracked_params(vec![0, 1, 2, 3], 2, 1);
    let r = run_monte_carlo_simulation_seeded(&season, &params, names, 11);
    let muster = r.tracked_class_patterns.as_ref().unwrap();

    assert_eq!(muster.iter().map(|m| m.count).sum::<usize>(), 4000);
    for m in muster {
        // Genau zwei Teams direkt abgestiegen, eines in der Relegation, eines sicher.
        assert_eq!(m.classes.iter().filter(|&&c| c == 1).count(), 2, "{m:?}");
        assert_eq!(m.classes.iter().filter(|&&c| c == 2).count(), 1, "{m:?}");
        assert_eq!(m.classes.iter().filter(|&&c| c == 0).count(), 1, "{m:?}");
    }
    // Sortiert und ohne Dopplung.
    assert!(muster.windows(2).all(|w| w[0].classes < w[1].classes));
}

#[test]
fn tracked_patterns_agree_with_the_marginals_of_the_probability_matrix() {
    // Die Randverteilung eines Teams aus den Mustern muss exakt der
    // Prognosematrix entsprechen: dieselben Iterationen, dieselbe Tabelle.
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let params = tracked_params(vec![0, 1, 2, 3], 2, 1);
    let r = run_monte_carlo_simulation_seeded(&season, &params, names, 11);
    let muster = r.tracked_class_patterns.as_ref().unwrap();

    for (i, name) in ["AAA", "BBB", "CCC", "DDD"].iter().enumerate() {
        let zeile = r.team_names.iter().position(|n| n == name).unwrap();
        let direkt: usize = muster
            .iter()
            .filter(|m| m.classes[i] == 1)
            .map(|m| m.count)
            .sum();
        let p_matrix = r.probability_matrix[zeile][2] + r.probability_matrix[zeile][3];
        assert!((direkt as f64 / 4000.0 - p_matrix).abs() < 1e-12, "{name}");
        let relegation: usize = muster
            .iter()
            .filter(|m| m.classes[i] == 2)
            .map(|m| m.count)
            .sum();
        assert!(
            (relegation as f64 / 4000.0 - r.probability_matrix[zeile][1]).abs() < 1e-12,
            "{name}"
        );
    }
}

#[test]
fn tracked_patterns_keep_the_request_order_and_subset() {
    // Nur zwei Teams, in umgekehrter Reihenfolge: classes[0] gehoert zu Team 3.
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = run_monte_carlo_simulation_seeded(&season, &tracked_params(vec![3, 0], 2, 0), names, 5);
    let muster = r.tracked_class_patterns.as_ref().unwrap();
    assert!(muster.iter().all(|m| m.classes.len() == 2));
    // DDD (schwaechstes Team) steigt haeufiger direkt ab als AAA (staerkstes).
    let ddd: usize = muster
        .iter()
        .filter(|m| m.classes[0] == 1)
        .map(|m| m.count)
        .sum();
    let aaa: usize = muster
        .iter()
        .filter(|m| m.classes[1] == 1)
        .map(|m| m.count)
        .sum();
    assert!(ddd > aaa);
    // Ohne Relegationsplaetze gibt es keine Klasse 2.
    assert!(muster.iter().all(|m| m.classes.iter().all(|&c| c <= 1)));
}

#[test]
fn without_tracked_teams_there_are_no_patterns() {
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let params = SimulationParams {
        iterations: 100,
        ..SimulationParams::default()
    };
    let r = run_monte_carlo_simulation_seeded(&season, &params, names, 1);
    assert!(r.tracked_class_patterns.is_none());
}

#[test]
fn tracked_counting_does_not_change_the_probability_matrix() {
    // Dieselbe Seed, mit und ohne Zaehlung: die Prognose bleibt bitgleich.
    let season = double_round_robin_open();
    let names: Vec<String> = ["AAA", "BBB", "CCC", "DDD"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let ohne = SimulationParams {
        iterations: 2000,
        ..SimulationParams::default()
    };
    let mit = SimulationParams {
        iterations: 2000,
        ..tracked_params(vec![1, 2], 2, 1)
    };
    let a = run_monte_carlo_simulation_seeded(&season, &ohne, names.clone(), 9);
    let b = run_monte_carlo_simulation_seeded(&season, &mit, names, 9);
    assert_eq!(a.probability_matrix, b.probability_matrix);
}
