//! HTTP-API handler tests.
//!
//! These tests exercise the `axum::Router` returned by `create_router` using
//! `tower::ServiceExt::oneshot`, so no real port is opened. They pin the
//! wire-format contract that the R-side scheduler depends on, and they
//! document the validation paths in `simulate_league` (empty schedule, empty
//! elo_values).

use crate::api::create_router;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;

/// Send `req` through the router and return (status, body).
///
/// Success responses are JSON and are parsed as such. Error responses (e.g.
/// validation failures) are plain text — `(StatusCode, String)` rejections
/// render as a text body, not JSON — so those are wrapped as a JSON string
/// instead of failing the parse.
async fn send(req: Request<Body>) -> (StatusCode, Value) {
    let response = create_router()
        .oneshot(req)
        .await
        .expect("router service should not fail");

    let status = response.status();
    let bytes = response
        .into_body()
        .collect()
        .await
        .expect("body collect")
        .to_bytes();
    let body: Value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)
            .unwrap_or_else(|_| Value::String(String::from_utf8_lossy(&bytes).into_owned()))
    };

    (status, body)
}

/// Prueft Statuscode UND Grund einer abgelehnten Anfrage.
///
/// Der Statuscode allein genuegt nicht: Er faellt auch dann auf 400, wenn
/// die Anfrage aus einem ganz anderen Grund scheitert als dem geprueften --
/// ein Test fuer "zu viele Iterationen" bliebe gruen, obwohl in Wahrheit
/// eine leere ELO-Liste bemaengelt wurde. Die Meldung ist die einzige
/// Stelle, an der die Ablehnung ihren Grund nennt.
fn assert_bad_request(status: StatusCode, body: &Value, erwartet: &str) {
    assert_eq!(status, StatusCode::BAD_REQUEST, "Statuscode; Body: {body}");
    let text = body.as_str().unwrap_or_default();
    assert!(
        text.contains(erwartet),
        "Fehlermeldung sollte {erwartet:?} enthalten, war: {text:?}"
    );
}

fn post_simulate_json(payload: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/simulate")
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap()
}

/// A minimal valid simulate request: 2 teams, 1 played match plus 1 to
/// simulate, low iteration count to keep tests fast.
fn minimal_valid_simulate_payload() -> Value {
    json!({
        "schedule": [
            [1, 2, 1, 0],          // played match
            [2, 1, null, null]     // match to simulate
        ],
        "elo_values": [1500.0, 1500.0],
        "iterations": 50
    })
}

#[tokio::test]
async fn health_returns_ok_with_status_version_and_performance_fields() {
    let req = Request::builder()
        .method("GET")
        .uri("/health")
        .body(Body::empty())
        .unwrap();

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");
    assert!(
        body["version"].is_string(),
        "version field must be present and a string, got: {body}"
    );
    assert!(
        body["performance"].is_string(),
        "performance field must be present and a string, got: {body}"
    );
}

#[tokio::test]
async fn simulate_returns_400_when_schedule_is_empty() {
    let req = post_simulate_json(json!({
        "schedule": [],
        "elo_values": [1500.0, 1500.0],
        "iterations": 10
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "schedule must not be empty");
}

#[tokio::test]
async fn simulate_returns_400_when_elo_values_is_empty() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, 1, 0]],
        "elo_values": [],
        "iterations": 10
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "elo_values must not be empty");
}

#[tokio::test]
async fn simulate_happy_path_returns_probability_matrix_with_expected_shape() {
    let req = post_simulate_json(minimal_valid_simulate_payload());

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);

    let matrix = body["probability_matrix"]
        .as_array()
        .expect("probability_matrix must be a JSON array");
    assert_eq!(matrix.len(), 2, "matrix should have one row per team");
    for row in matrix {
        let cols = row.as_array().expect("each row must be an array");
        assert_eq!(
            cols.len(),
            2,
            "each row should have one column per position"
        );
        let row_sum: f64 = cols.iter().map(|v| v.as_f64().unwrap()).sum();
        assert!(
            (row_sum - 1.0).abs() < 1e-9,
            "row probabilities must sum to 1, got {row_sum}"
        );
    }

    let names = body["team_names"]
        .as_array()
        .expect("team_names must be a JSON array");
    assert_eq!(names.len(), 2);

    assert_eq!(
        body["simulations_performed"].as_u64().unwrap(),
        50,
        "simulations_performed should reflect the requested iterations"
    );
    assert!(
        body["time_ms"].is_number(),
        "time_ms must be a number, got: {body}"
    );
}

#[tokio::test]
async fn simulate_uses_caller_supplied_team_names_in_response() {
    let mut payload = minimal_valid_simulate_payload();
    payload["team_names"] = json!(["Foo FC", "Bar United"]);

    let req = post_simulate_json(payload);
    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    let names: Vec<String> = body["team_names"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    assert!(
        names.contains(&"Foo FC".to_string()),
        "response team_names must contain caller-supplied 'Foo FC', got {names:?}"
    );
    assert!(
        names.contains(&"Bar United".to_string()),
        "response team_names must contain caller-supplied 'Bar United', got {names:?}"
    );
}

#[tokio::test]
async fn simulate_defaults_iterations_to_10000_when_not_provided() {
    // Note: this is the slow test (10k iterations) — kept minimal (2 teams,
    // 2-match schedule) so it still completes well under a second on dev
    // hardware.
    let req = post_simulate_json(json!({
        "schedule": [
            [1, 2, 1, 0],
            [2, 1, null, null]
        ],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, body) = send(req).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["simulations_performed"].as_u64().unwrap(),
        10_000,
        "default iterations should be 10000 when caller omits the field"
    );
}

#[tokio::test]
async fn simulate_rejects_team_index_zero() {
    // team index 0 previously underflowed to usize::MAX and aborted the process
    let req = post_simulate_json(json!({
        "schedule": [[0, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "team_home index 0 out of range 1..=2");
}

#[tokio::test]
async fn simulate_rejects_null_team_index() {
    let req = post_simulate_json(json!({
        "schedule": [[null, 2, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "team_home must not be null");
}

#[tokio::test]
async fn simulate_rejects_out_of_range_team_index() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 3, null, null]],
        "elo_values": [1500.0, 1500.0]
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "team_away index 3 out of range 1..=2");
}

#[tokio::test]
async fn simulate_rejects_excessive_iterations() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "iterations": 100_000_000
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "iterations must be between 1 and 100000");
}

#[tokio::test]
async fn simulate_rejects_mismatched_adjustment_length() {
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1500.0],
        "adj_points": [0, 0, 0]
    }));

    let (status, body) = send(req).await;

    assert_bad_request(status, &body, "adj_points has length 3, expected 2");
}

// ======================================================================
// POST /league-details — deterministic per-match details (ADR 0002).
//
// These tests pin the wire contract the R-side renderer will parse
// (parse_league_details_response in RCode/league_details.R). Expected
// numbers come from the same independent computation as
// league_details/tests.rs.
// ======================================================================

fn post_league_details_json(payload: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/league-details")
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap()
}

/// 4 teams at 1500; 1v2 finished 2:1, 3v4 finished 0:0, 2v3 open.
fn minimal_league_details_payload() -> Value {
    json!({
        "schedule": [
            [1, 2, 2, 1],
            [3, 4, 0, 0],
            [2, 3, null, null]
        ],
        "elo_values": [1500.0, 1500.0, 1500.0, 1500.0],
        "team_names": ["AAA", "BBB", "CCC", "DDD"]
    })
}

#[tokio::test]
async fn league_details_returns_wire_contract() {
    let (status, body) = send(post_league_details_json(minimal_league_details_payload())).await;

    assert_eq!(status, StatusCode::OK);

    // Top level: matches, current_elos, team_names.
    let matches = body["matches"].as_array().expect("matches array");
    assert_eq!(matches.len(), 3);
    assert_eq!(body["team_names"], json!(["AAA", "BBB", "CCC", "DDD"]));

    let elos = body["current_elos"].as_array().expect("current_elos array");
    assert_eq!(elos.len(), 4);
    assert!((elos[0].as_f64().unwrap() - 1508.853767324754).abs() < 1e-6);

    // Played match: 1-based team indices (like the request), flat
    // probability fields, ELO state and delta.
    let m1 = &matches[0];
    assert_eq!(m1["index"], json!(0));
    assert_eq!(m1["team_home"], json!(1));
    assert_eq!(m1["team_away"], json!(2));
    assert_eq!(m1["played"], json!(true));
    assert_eq!(m1["goals_home"], json!(2));
    assert_eq!(m1["goals_away"], json!(1));
    assert!((m1["elo_home_pre"].as_f64().unwrap() - 1500.0).abs() < 1e-9);
    assert!((m1["elo_delta_home"].as_f64().unwrap() - 8.853767324754).abs() < 1e-6);
    assert!((m1["p_home_win"].as_f64().unwrap() - 0.402904706240).abs() < 1e-6);
    assert!((m1["p_draw"].as_f64().unwrap() - 0.260577313073).abs() < 1e-6);
    assert!((m1["p_away_win"].as_f64().unwrap() - 0.336517980687).abs() < 1e-6);
    assert!(m1["lambda_home"].as_f64().is_some());
    assert!(m1["lambda_away"].as_f64().is_some());

    // Score matrix: default max_goals = 6 → 7x7, sums to ~1.
    let grid = m1["score_matrix"].as_array().expect("score_matrix");
    assert_eq!(grid.len(), 7);
    assert_eq!(grid[0].as_array().unwrap().len(), 7);
    let total: f64 = grid
        .iter()
        .flat_map(|row| row.as_array().unwrap())
        .map(|v| v.as_f64().unwrap())
        .sum();
    assert!((total - 1.0).abs() < 1e-9);

    // Unplayed match: no goals, null delta, priced off final ELOs.
    let m3 = &matches[2];
    assert_eq!(m3["played"], json!(false));
    assert!(m3["goals_home"].is_null());
    assert!(m3["elo_delta_home"].is_null());
    assert!((m3["elo_home_pre"].as_f64().unwrap() - 1491.146232675246).abs() < 1e-6);
    assert!((m3["p_home_win"].as_f64().unwrap() - 0.396380047590).abs() < 1e-6);
}

#[tokio::test]
async fn league_details_rejects_empty_schedule() {
    let (status, body) = send(post_league_details_json(json!({
        "schedule": [],
        "elo_values": [1500.0, 1500.0]
    })))
    .await;

    assert_bad_request(status, &body, "schedule must not be empty");
}

#[tokio::test]
async fn league_details_rejects_out_of_range_team_index() {
    let (status, body) = send(post_league_details_json(json!({
        "schedule": [[1, 5, null, null]],
        "elo_values": [1500.0, 1500.0]
    })))
    .await;

    assert_bad_request(status, &body, "team_away index 5 out of range 1..=2");
}

#[tokio::test]
async fn league_details_respects_max_goals_parameter() {
    let mut payload = minimal_league_details_payload();
    payload["max_goals"] = json!(4);

    let (status, body) = send(post_league_details_json(payload)).await;

    assert_eq!(status, StatusCode::OK);
    let grid = body["matches"][0]["score_matrix"].as_array().unwrap();
    assert_eq!(grid.len(), 5);
}

#[tokio::test]
async fn league_details_respects_goal_model_parameters() {
    // Der Intercept ist die halbe Torerwartung je Spiel. Ein hoeherer Wert
    // muss die Wahrscheinlichkeit fuer 0:0 senken -- sonst greift der
    // Parameter nicht durch.
    let mut low = minimal_league_details_payload();
    low["tore_intercept"] = json!(1.0);
    let (status_low, body_low) = send(post_league_details_json(low)).await;
    assert_eq!(status_low, StatusCode::OK);

    let mut high = minimal_league_details_payload();
    high["tore_intercept"] = json!(2.0);
    let (status_high, body_high) = send(post_league_details_json(high)).await;
    assert_eq!(status_high, StatusCode::OK);

    let nil_nil_low = body_low["matches"][0]["score_matrix"][0][0]
        .as_f64()
        .unwrap();
    let nil_nil_high = body_high["matches"][0]["score_matrix"][0][0]
        .as_f64()
        .unwrap();

    assert!(
        nil_nil_high < nil_nil_low,
        "hoeherer Intercept muss P(0:0) senken: {} vs {}",
        nil_nil_high,
        nil_nil_low
    );
}

#[tokio::test]
async fn league_details_defaults_goal_model_when_absent() {
    // Ohne die Felder muss exakt das Ergebnis von vorher herauskommen --
    // die Altligen duerfen sich durch die Parametrisierung nicht bewegen.
    let (_, explicit) = send(post_league_details_json({
        let mut p = minimal_league_details_payload();
        p["tore_slope"] = json!(0.0017854953143549);
        p["tore_intercept"] = json!(1.3218390804597700);
        p
    }))
    .await;

    let (_, implicit) = send(post_league_details_json(minimal_league_details_payload())).await;

    assert_eq!(
        explicit["matches"][0]["score_matrix"],
        implicit["matches"][0]["score_matrix"]
    );
}

// --- elo_neutral: Ergebnis zaehlt fuer die Tabelle, nicht fuer den ELO-Walk ---
//
// Issue #157. Ein am gruenen Tisch gewertetes Spiel (api-football AWD/WO) ist
// sportrechtlich ein Ergebnis und gehoert in die Tabelle -- es sagt aber nichts
// ueber Spielstaerke und darf den ELO-Walk nicht bewegen.
//
// Die Engine kennt keine Verbandsstatus. Sie bekommt deshalb ein neutrales
// Flag je Spiel: `elo_neutral` ist ein paralleler bool-Vektor zu `schedule`
// (gleiche Laenge, gleiche Reihenfolge) -- dieselbe Bauform wie die
// bestehenden adj_*-Vektoren, und rueckwaertskompatibel, weil `schedule`
// selbst ein Array fester Breite 4 bleibt.
//
// Semantik: elo_neutral[i] == true heisst "Tore zaehlen fuer Tabelle und
// Endstand, das Spiel wird NICHT simuliert, aber der ELO-Walk ueberspringt
// es". Fehlt das Feld, verhaelt sich alles wie bisher.

#[tokio::test]
async fn league_details_elo_neutral_match_does_not_move_elo() {
    // Spiel 1 (2:1) bewegt das ELO, Spiel 2 (0:0) ist elo-neutral.
    let mut payload = minimal_league_details_payload();
    payload["elo_neutral"] = json!([false, true, false]);

    let (status, body) = send(post_league_details_json(payload)).await;
    assert_eq!(status, StatusCode::OK);

    // Team 3 und 4 bestreiten nur das neutrale Spiel -- ihr ELO muss exakt
    // auf dem Startwert stehen.
    let elos = body["current_elos"].as_array().unwrap();
    assert_eq!(elos[2].as_f64().unwrap(), 1500.0);
    assert_eq!(elos[3].as_f64().unwrap(), 1500.0);
}

#[tokio::test]
async fn league_details_elo_neutral_reports_no_elo_delta() {
    // Die Anzeige darf fuer ein gewertetes Spiel keine ELO-Anpassung
    // ausweisen -- sonst behauptet die Seite eine Staerkeaenderung, die es
    // nicht gab.
    let mut payload = minimal_league_details_payload();
    payload["elo_neutral"] = json!([false, true, false]);

    let (status, body) = send(post_league_details_json(payload)).await;
    assert_eq!(status, StatusCode::OK);

    assert!(body["matches"][1]["elo_delta_home"].is_null());
}

#[tokio::test]
async fn league_details_without_elo_neutral_is_unchanged() {
    // Verhaltensneutralitaet: Ohne das Feld muss byteweise dasselbe
    // herauskommen wie mit einem reinen false-Vektor.
    let (_, implicit) = send(post_league_details_json(minimal_league_details_payload())).await;

    let mut explicit_payload = minimal_league_details_payload();
    explicit_payload["elo_neutral"] = json!([false, false, false]);
    let (_, explicit) = send(post_league_details_json(explicit_payload)).await;

    assert_eq!(implicit["current_elos"], explicit["current_elos"]);
    assert_eq!(implicit["matches"], explicit["matches"]);
}

#[tokio::test]
async fn league_details_rejects_elo_neutral_of_wrong_length() {
    // Ein zu kurzer Vektor waere eine stille Fehlzuordnung: Ab dem fehlenden
    // Eintrag verschoebe sich die Zuordnung Spiel -> Flag.
    let mut payload = minimal_league_details_payload();
    payload["elo_neutral"] = json!([false, true]); // schedule hat 3 Zeilen

    let (status, body) = send(post_league_details_json(payload)).await;
    assert_bad_request(
        status,
        &body,
        "elo_neutral must have one entry per schedule row",
    );
}

#[tokio::test]
async fn simulate_elo_neutral_match_counts_for_table_but_not_elo() {
    // Der Simulationspfad (/simulate) traegt dieselbe Semantik: Das Ergebnis
    // steht fest und geht in die Endtabelle ein -- das Spiel wird also nicht
    // neu ausgewuerfelt --, aber der ELO-Walk laesst es aus.
    //
    // Messbar ueber die Prognose: Ein 9:0 fuer Team 1 als NORMALES Ergebnis
    // hebt dessen ELO deutlich und damit seine Meisterwahrscheinlichkeit;
    // als elo-neutrales Ergebnis zaehlen nur die drei Punkte.
    let base = json!({
        "schedule": [
            [1, 2, 9, 0],
            [3, 4, null, null],
            [1, 3, null, null],
            [2, 4, null, null],
            [1, 4, null, null],
            [2, 3, null, null]
        ],
        "elo_values": [1500.0, 1500.0, 1500.0, 1500.0],
        "team_names": ["AAA", "BBB", "CCC", "DDD"],
        // 50_000 statt 2_000: Der echte Effekt betraegt rund 2,5
        // Prozentpunkte, das Rauschen bei 2_000 Iterationen aber 1,5 -- die
        // Differenz war damit nicht auflösbar, und der Test wurde
        // gelegentlich rot (CI-Lauf 34042117880: 0,6265 vs 0,6235, Vorzeichen
        // sogar gedreht). Bei 50_000 sinkt das Rauschen auf 0,3 Pp; fuenf
        // Kontrolllaeufe lagen zwischen +0,020 und +0,027.
        "iterations": 50000
    });

    let (status_normal, normal) = send(post_simulate_json(base.clone())).await;
    assert_eq!(status_normal, StatusCode::OK);

    let mut neutral_payload = base.clone();
    neutral_payload["elo_neutral"] = json!([true, false, false, false, false, false]);
    let (status_neutral, neutral) = send(post_simulate_json(neutral_payload)).await;
    assert_eq!(status_neutral, StatusCode::OK);

    let p_first_normal = normal["probability_matrix"][0][0].as_f64().unwrap();
    let p_first_neutral = neutral["probability_matrix"][0][0].as_f64().unwrap();

    // Mit Abstand statt strikter Ungleichung: Der Effekt liegt bei rund 2,5
    // Prozentpunkten, ein Mindestabstand von 1 Pp trennt ihn sicher vom
    // Rauschen (0,3 Pp bei dieser Iterationszahl), ohne den Test an einer
    // exakten Zahl festzunageln.
    assert!(
        p_first_neutral < p_first_normal - 0.01,
        "ohne ELO-Schub muss Team 1 deutlich seltener Erster werden: {} (neutral) vs {} (normal)",
        p_first_neutral,
        p_first_normal
    );

    // Aber die Punkte zaehlen weiterhin: Gegen ein Feld, in dem dieses Spiel
    // gar nicht gespielt waere, muss Team 1 klar besser dastehen.
    let mut ungespielt = base.clone();
    ungespielt["schedule"][0] = json!([1, 2, null, null]);
    let (_, offen) = send(post_simulate_json(ungespielt)).await;
    let p_first_offen = offen["probability_matrix"][0][0].as_f64().unwrap();

    assert!(
        p_first_neutral > p_first_offen,
        "die drei Punkte muessen zaehlen: {} (neutral) vs {} (ungespielt)",
        p_first_neutral,
        p_first_offen
    );
}

#[tokio::test]
async fn simulate_rejects_elo_neutral_of_wrong_length() {
    // schedule hat zwei Zeilen, elo_neutral nur eine.
    let req = post_simulate_json(json!({
        "schedule": [[1, 2, null, null], [2, 1, null, null]],
        "elo_values": [1500.0, 1500.0],
        "elo_neutral": [true]
    }));

    let (status, body) = send(req).await;
    assert_bad_request(
        status,
        &body,
        "elo_neutral must have one entry per schedule row",
    );
}

// --- relegation_group_counts: Absteiger je Staffel exakt auszaehlen ---------
//
// Phase 3 des Ligen-Ausbaus. Die 3. Liga schickt ihre Absteiger in fuenf
// regionale Staffeln, je nach Stammregion des Vereins. Wie viele in eine
// bestimmte Staffel fallen, entscheidet dort mit ueber die Zahl der
// Absteiger -- Phase 6 rechnet damit weiter.
//
// Warum exakt ausgezaehlt und nicht aus der Prognosematrix rekonstruiert:
// Die Matrix enthaelt nur die Randverteilung je Team. Ein Poisson-Binomial
// darueber behandelte die Teams als unabhaengig -- sie sind es aber nicht,
// weil genau k Teams die Abstiegsplaetze belegen (stark negativ korreliert).
// Der Fehler waere strukturell, nicht numerisch: Erwartungswert 4,12 statt
// exakt 4,00 bei vier Abstiegsplaetzen.
//
// Jede Iteration erzeugt ohnehin eine konkrete Abschlusstabelle. Es genuegt,
// je Iteration mitzuschreiben, wie viele Absteiger zu welcher Staffel
// gehoeren.
//
// Das Feld ist eine reine RECHENGROESSE. Es wird nirgends angezeigt; die
// Darstellung folgt spaeter dort, wo sie relevant wird (etwa als Fussnote
// "Abhaengig von Auf- und Abstieg in bzw. aus der 3. Liga koennen bis zu
// zwei weitere Teams absteigen").

/// Vier Teams, drei offene Spiele; Teams 0+1 in Staffel 0, Teams 2+3 in
/// Staffel 1. Zwei Abstiegsplaetze.
fn relegation_payload(iterations: usize) -> Value {
    json!({
        "schedule": [
            [1, 2, null, null],
            [3, 4, null, null],
            [1, 3, null, null],
            [2, 4, null, null],
            [1, 4, null, null],
            [2, 3, null, null]
        ],
        "elo_values": [1500.0, 1500.0, 1500.0, 1500.0],
        "team_names": ["AAA", "BBB", "CCC", "DDD"],
        "iterations": iterations,
        "group_of_team": [0, 0, 1, 1],
        "relegation_places": 2
    })
}

#[tokio::test]
async fn simulate_reports_relegation_group_counts() {
    let (status, body) = send(post_simulate_json(relegation_payload(1000))).await;
    assert_eq!(status, StatusCode::OK);

    let counts = body["relegation_group_counts"]
        .as_array()
        .expect("relegation_group_counts array");

    // Eine Zeile je Staffel, eine Spalte je moeglicher Absteigerzahl
    // (0 bis relegation_places).
    assert_eq!(counts.len(), 2, "zwei Staffeln");
    assert_eq!(
        counts[0].as_array().unwrap().len(),
        3,
        "0, 1 oder 2 Absteiger"
    );
}

#[tokio::test]
async fn relegation_group_counts_rows_sum_to_iterations() {
    // Die starke Invariante: Jede Iteration traegt zu JEDER Staffel genau
    // einen Eintrag bei -- naemlich, wie viele ihrer Teams abgestiegen sind
    // (auch wenn das null ist). Stimmt eine Zeilensumme nicht, wurde entweder
    // doppelt gezaehlt oder eine Iteration verschluckt.
    let iterations = 1000;
    let (status, body) = send(post_simulate_json(relegation_payload(iterations))).await;
    assert_eq!(status, StatusCode::OK);

    for (staffel, row) in body["relegation_group_counts"]
        .as_array()
        .unwrap()
        .iter()
        .enumerate()
    {
        let sum: u64 = row
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_u64().unwrap())
            .sum();
        assert_eq!(
            sum, iterations as u64,
            "Staffel {}: Zeilensumme {} statt {}",
            staffel, sum, iterations
        );
    }
}

#[tokio::test]
async fn relegation_group_counts_total_matches_relegation_places() {
    // Die zweite starke Invariante, und der eigentliche Grund fuer die
    // Auszaehlung: Ueber alle Staffeln summiert muss die erwartete Zahl der
    // Absteiger EXAKT der Zahl der Abstiegsplaetze entsprechen -- keine
    // Toleranz, anders als bei der verworfenen Naeherung.
    let iterations = 1000;
    let (status, body) = send(post_simulate_json(relegation_payload(iterations))).await;
    assert_eq!(status, StatusCode::OK);

    let mut absteiger_gesamt: u64 = 0;
    for row in body["relegation_group_counts"].as_array().unwrap() {
        for (anzahl, count) in row.as_array().unwrap().iter().enumerate() {
            absteiger_gesamt += anzahl as u64 * count.as_u64().unwrap();
        }
    }

    // 2 Abstiegsplaetze x 1000 Iterationen = 2000 Absteiger, exakt.
    assert_eq!(absteiger_gesamt, 2 * iterations as u64);
}

#[tokio::test]
async fn relegation_group_counts_respects_group_assignment() {
    // Alle vier Teams in dieselbe Staffel: Dann muessen dort in JEDER
    // Iteration genau beide Abstiegsplaetze liegen -- die Verteilung ist
    // entartet, und genau das muss herauskommen.
    let mut payload = relegation_payload(500);
    payload["group_of_team"] = json!([0, 0, 0, 0]);

    let (status, body) = send(post_simulate_json(payload)).await;
    assert_eq!(status, StatusCode::OK);

    let counts = body["relegation_group_counts"].as_array().unwrap();
    assert_eq!(counts.len(), 1, "eine Staffel");
    let row = counts[0].as_array().unwrap();
    assert_eq!(row[0].as_u64().unwrap(), 0, "nie null Absteiger");
    assert_eq!(row[1].as_u64().unwrap(), 0, "nie ein Absteiger");
    assert_eq!(row[2].as_u64().unwrap(), 500, "immer beide");
}

#[tokio::test]
async fn simulate_without_group_of_team_is_unchanged() {
    // Verhaltensneutralitaet: Ohne das Feld darf sich nichts aendern -- die
    // Altligen laufen unberuehrt weiter. relegation_group_counts fehlt dann
    // in der Antwort, statt leer dabeizustehen.
    let base = json!({
        "schedule": [[1, 2, 2, 1], [3, 4, 0, 0], [2, 3, null, null]],
        "elo_values": [1500.0, 1500.0, 1500.0, 1500.0],
        "team_names": ["AAA", "BBB", "CCC", "DDD"],
        "iterations": 100
    });

    let (status, body) = send(post_simulate_json(base)).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body.get("relegation_group_counts").is_none() || body["relegation_group_counts"].is_null()
    );
}

#[tokio::test]
async fn simulate_rejects_group_of_team_of_wrong_length() {
    // Ein zu kurzer Vektor waere eine stille Fehlzuordnung: Ab dem fehlenden
    // Eintrag traegt jedes Team die Staffel eines anderen.
    let mut payload = relegation_payload(100);
    payload["group_of_team"] = json!([0, 0, 1]); // 4 Teams, 3 Eintraege

    let (status, _) = send(post_simulate_json(payload)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_relegation_places_out_of_range() {
    // Mehr Abstiegsplaetze als Teams ist ein Konfigurationsfehler, kein
    // Grenzfall -- er soll auffallen, nicht stillschweigend gedeckelt werden.
    let mut payload = relegation_payload(100);
    payload["relegation_places"] = json!(5); // nur 4 Teams

    let (status, _) = send(post_simulate_json(payload)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn simulate_rejects_group_of_team_without_relegation_places() {
    // Beide Felder gehoeren zusammen. Eines allein ist mehrdeutig und
    // vermutlich ein Fehler beim Aufrufer.
    let mut payload = relegation_payload(100);
    payload.as_object_mut().unwrap().remove("relegation_places");

    let (status, _) = send(post_simulate_json(payload)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// --- /match-preview: ein virtuelles Spiel ohne Spielplan ---------------------
//
// Fuer die Aufstiegsspiele Nord gegen Bayern (Par. 55b DFB-SpO) braucht R die
// Tor-Raten einer Paarung, die in keinem Ligaspielplan steht. ADR 0002
// verwirft den Nachbau der Formel ELO -> lambda in R; also liefert sie der
// Server: POST /match-preview nimmt zwei ELO-Werte und antwortet mit dem,
// was /league-details je Spiel liefert -- lambda_home, lambda_away,
// p_home_win, p_draw, p_away_win, score_matrix -- gerechnet mit DERSELBEN
// Funktion (league_details::match_probabilities), kein zweiter Rechenweg.
//
// Request:  { elo_home, elo_away,
//             home_advantage?, tore_slope?, tore_intercept?, max_goals? }
//           Defaults wie /league-details: 40, 0.0017854953143549,
//           1.3218390804597700, 6.
// Response: { lambda_home, lambda_away, p_home_win, p_draw, p_away_win,
//             score_matrix }  -- score_matrix ist (max_goals+1)^2, letzte
//           Zeile/Spalte tragen die Schwanzmasse.
//
// Die R-Seite (tests/testthat/test-aufstiegsspiele.R) macht auf diesen
// Raten nur noch Kombinatorik: Faltung ueber zwei Spiele, Verlaengerung
// mit lambda / 3 ohne Heimvorteil, Elfmeter 50:50.

fn post_match_preview_json(payload: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/match-preview")
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap()
}

fn f64_at(body: &Value, key: &str) -> f64 {
    body[key]
        .as_f64()
        .unwrap_or_else(|| panic!("Feld {key} fehlt oder ist keine Zahl; Body: {body}"))
}

#[tokio::test]
async fn match_preview_returns_rust_goal_model_lambdas() {
    // 1500 gegen 1400 mit dem Default-Heimvorteil 40: elo_delta = 140.
    //   lambda_home = 140 * 0.0017854953143549 + 1.32183908045977
    //               = 1.57180842446946
    //   lambda_away = -140 * 0.0017854953143549 + 1.32183908045977
    //               = 1.07186973645008
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    assert!((f64_at(&body, "lambda_home") - 1.57180842446946).abs() < 1e-12);
    assert!((f64_at(&body, "lambda_away") - 1.07186973645008).abs() < 1e-12);

    // Ohne Heimvorteil: elo_delta = 100.
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0,
        "home_advantage": 0.0
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    assert!((f64_at(&body, "lambda_home") - 1.50038861189526).abs() < 1e-12);
    assert!((f64_at(&body, "lambda_away") - 1.14328954902428).abs() < 1e-12);
}

#[tokio::test]
async fn match_preview_home_advantage_is_additive_on_elo_delta() {
    // Der Heimvorteil ist ELO-Punkte, kein Faktor auf lambda:
    // lambda_home(40) - lambda_home(0) = 40 * tore_slope, und die Summe
    // beider Raten ist immer 2 * tore_intercept.
    let (_, mit) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1500.0
    })))
    .await;
    let (_, ohne) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1500.0,
        "home_advantage": 0.0
    })))
    .await;

    let slope = 0.0017854953143549;
    let intercept = 1.3218390804597700;
    assert!((f64_at(&mit, "lambda_home") - f64_at(&ohne, "lambda_home") - 40.0 * slope).abs() < 1e-13);
    assert!((f64_at(&ohne, "lambda_away") - f64_at(&mit, "lambda_away") - 40.0 * slope).abs() < 1e-13);
    assert!((f64_at(&mit, "lambda_home") + f64_at(&mit, "lambda_away") - 2.0 * intercept).abs() < 1e-13);
    // Ohne Heimvorteil und bei gleicher ELO: beide Raten exakt der Intercept.
    assert!((f64_at(&ohne, "lambda_home") - intercept).abs() < 1e-15);
    assert!((f64_at(&ohne, "lambda_away") - intercept).abs() < 1e-15);
}

#[tokio::test]
async fn match_preview_clamps_lambda_at_0_001() {
    // ELO-Differenz 1000 ohne Heimvorteil: die Gastrate waere -0.4637 und
    // wird auf 0.001 geklemmt -- wie in simulate_match und league_details.
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 2500.0,
        "elo_away": 1500.0,
        "home_advantage": 0.0
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    assert_eq!(f64_at(&body, "lambda_away"), 0.001);
    assert!((f64_at(&body, "lambda_home") - (1000.0 * 0.0017854953143549 + 1.3218390804597700)).abs() < 1e-12);
    assert!(f64_at(&body, "lambda_home") > 0.0);
}

#[tokio::test]
async fn match_preview_agrees_with_league_details_for_an_open_match() {
    // Kein zweiter Rechenweg: Fuer ein offenes Spiel ohne gespielte Partien
    // rechnet /league-details mit den Start-ELOs -- genau das, was
    // /match-preview mit denselben ELOs liefern muss, Feld fuer Feld.
    let (status_ld, ld) = send(post_league_details_json(json!({
        "schedule": [[1, 2, null, null]],
        "elo_values": [1500.0, 1400.0],
        "max_goals": 8
    })))
    .await;
    assert_eq!(status_ld, StatusCode::OK, "Body: {ld}");

    let (status_mp, mp) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0,
        "max_goals": 8
    })))
    .await;
    assert_eq!(status_mp, StatusCode::OK, "Body: {mp}");

    let spiel = &ld["matches"][0];
    for key in ["lambda_home", "lambda_away", "p_home_win", "p_draw", "p_away_win"] {
        assert_eq!(mp[key], spiel[key], "Feld {key}");
    }
    assert_eq!(mp["score_matrix"], spiel["score_matrix"]);
}

#[tokio::test]
async fn match_preview_respects_goal_model_parameters() {
    // Frauen-Tormodell (Ligen 82, 1034): bei gleicher ELO und ohne
    // Heimvorteil sind beide Raten exakt der Frauen-Intercept.
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1500.0,
        "home_advantage": 0.0,
        "tore_slope": 0.0024058833,
        "tore_intercept": 1.6527603153
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    assert!((f64_at(&body, "lambda_home") - 1.6527603153).abs() < 1e-12);
    assert!((f64_at(&body, "lambda_away") - 1.6527603153).abs() < 1e-12);

    // Und mit Steigung: 1600 gegen 1450, Heimvorteil 40, Delta 190.
    //   lambda_home = 190 * 0.0024058833 + 1.6527603153 = 2.1098781423
    let (_, body) = send(post_match_preview_json(json!({
        "elo_home": 1600.0,
        "elo_away": 1450.0,
        "tore_slope": 0.0024058833,
        "tore_intercept": 1.6527603153
    })))
    .await;
    assert!((f64_at(&body, "lambda_home") - 2.1098781423).abs() < 1e-10);
}

#[tokio::test]
async fn match_preview_score_matrix_shape_and_mass() {
    // max_goals = 15 -> 16 x 16; die Masse summiert auf 1, weil die letzte
    // Zeile/Spalte den Schwanz traegt. P(0:0) = exp(-lambda_home - lambda_away).
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0,
        "max_goals": 15
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    let grid = body["score_matrix"].as_array().expect("score_matrix array");
    assert_eq!(grid.len(), 16);
    let mut masse = 0.0;
    for row in grid {
        let row = row.as_array().expect("score_matrix row");
        assert_eq!(row.len(), 16);
        masse += row.iter().map(|v| v.as_f64().unwrap()).sum::<f64>();
    }
    assert!((masse - 1.0).abs() < 1e-12, "Masse {masse}");

    let nil_nil = grid[0][0].as_f64().unwrap();
    let lh = f64_at(&body, "lambda_home");
    let la = f64_at(&body, "lambda_away");
    assert!((nil_nil - (-lh - la).exp()).abs() < 1e-14);

    // Default wie /league-details: max_goals = 6 -> 7 x 7.
    let (_, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0
    })))
    .await;
    assert_eq!(body["score_matrix"].as_array().unwrap().len(), 7);
}

#[tokio::test]
async fn match_preview_outcome_probabilities_sum_to_one_and_are_symmetric_without_home_advantage() {
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1500.0,
        "home_advantage": 0.0
    })))
    .await;

    assert_eq!(status, StatusCode::OK, "Body: {body}");
    let (h, d, a) = (
        f64_at(&body, "p_home_win"),
        f64_at(&body, "p_draw"),
        f64_at(&body, "p_away_win"),
    );
    assert!((h + d + a - 1.0).abs() < 1e-12);
    assert!((h - a).abs() < 1e-14, "ohne Heimvorteil symmetrisch: {h} vs {a}");
    // P(Remis) bei lambda 1.3218 beidseitig: sum_k dpois(k)^2 = 0.2614 --
    // die Decke aus elo_calibration.R::poisson_draw_ceiling().
    assert!((d - 0.261363).abs() < 5e-6, "P(Remis) = {d}");

    // Mit Heimvorteil kippt es zum Heimteam.
    let (_, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1500.0
    })))
    .await;
    assert!(f64_at(&body, "p_home_win") > f64_at(&body, "p_away_win"));
}

#[tokio::test]
async fn match_preview_rejects_max_goals_out_of_range() {
    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0,
        "max_goals": 0
    })))
    .await;
    assert_bad_request(status, &body, "max_goals must be between 1 and 100");

    let (status, body) = send(post_match_preview_json(json!({
        "elo_home": 1500.0,
        "elo_away": 1400.0,
        "max_goals": 101
    })))
    .await;
    assert_bad_request(status, &body, "max_goals must be between 1 and 100");
}

#[tokio::test]
async fn match_preview_rejects_missing_elo() {
    // Ohne elo_home gibt es kein Spiel. Die Ablehnung kommt aus der
    // JSON-Deserialisierung (axum: 422) und muss das fehlende Feld nennen.
    let (status, body) = send(post_match_preview_json(json!({
        "elo_away": 1400.0
    })))
    .await;
    assert!(status.is_client_error(), "Statuscode {status}; Body: {body}");
    let text = body.as_str().unwrap_or_default();
    assert!(text.contains("elo_home"), "Meldung sollte elo_home nennen, war: {text:?}");
}
