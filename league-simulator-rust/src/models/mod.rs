use serde::{Deserialize, Serialize};

/// Result of an ELO calculation after a match
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EloResult {
    pub new_elo_home: f64,
    pub new_elo_away: f64,
    pub goals_home: i32,
    pub goals_away: i32,
    pub win_probability_home: f64,
}

/// Parameters for ELO calculation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EloParams {
    pub elo_home: f64,
    pub elo_away: f64,
    pub goals_home: i32,
    pub goals_away: i32,
    pub mod_factor: f64,
    pub home_advantage: f64,
}

/// Match result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Match {
    pub team_home: usize,
    pub team_away: usize,
    pub goals_home: Option<i32>,
    pub goals_away: Option<i32>,

    /// Das Ergebnis steht fest und zaehlt fuer die Tabelle, soll den ELO-Walk
    /// aber nicht bewegen.
    ///
    /// Hintergrund: Die Engine leitet "gespielt" sonst allein aus der Praesenz
    /// beider Tore ab und aktualisiert dann zwingend auch das ELO. Fuer ein am
    /// gruenen Tisch gewertetes Spiel ist das falsch -- es ist sportrechtlich
    /// ein Ergebnis, sagt aber nichts ueber Spielstaerke (Issue #157).
    ///
    /// Die Engine kennt bewusst keine Verbandsstatus; sie erfaehrt nur, dass
    /// dieses eine Ergebnis ELO-neutral ist. Ohne Tore hat das Flag keine
    /// Wirkung: Ein ungespieltes Spiel wird simuliert, und das simulierte
    /// Ergebnis zaehlt wie immer.
    #[serde(default)]
    pub elo_neutral: bool,
}

/// Season schedule with matches
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Season {
    pub matches: Vec<Match>,
    pub team_elos: Vec<f64>,
    pub number_teams: usize,
}

/// League table entry for a team
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamStanding {
    pub team_id: usize,
    pub played: i32,
    pub won: i32,
    pub drawn: i32,
    pub lost: i32,
    pub goals_for: i32,
    pub goals_against: i32,
    pub goal_difference: i32,
    pub points: i32,
    pub position: usize,
}

/// Complete league table
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LeagueTable {
    pub standings: Vec<TeamStanding>,
}

/// Simulation parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationParams {
    pub mod_factor: f64,
    pub home_advantage: f64,
    pub iterations: usize,
    pub tore_slope: f64,
    pub tore_intercept: f64,
    /// Optional point adjustments per team (e.g., penalties)
    pub adj_points: Option<Vec<i32>>,
    /// Optional goals scored adjustments per team
    pub adj_goals: Option<Vec<i32>>,
    /// Optional goals against adjustments per team
    pub adj_goals_against: Option<Vec<i32>>,
    /// Optional goal difference adjustments per team
    pub adj_goal_diff: Option<Vec<i32>>,

    /// Staffel-Index je Team, parallel zu den Teams (0-basiert).
    ///
    /// Die 3. Liga schickt ihre Absteiger in fuenf regionale Staffeln, je
    /// nach Stammregion des Vereins. Wie viele in eine bestimmte Staffel
    /// fallen, entscheidet dort mit ueber die Zahl der Absteiger.
    ///
    /// None = keine Auszaehlung; die Antwort traegt dann kein
    /// `relegation_group_counts`.
    pub group_of_team: Option<Vec<usize>>,

    /// Zahl der Abstiegsplaetze am Tabellenende.
    pub relegation_places: Option<usize>,

    /// Zahl der Staffeln -- bestimmt die Zeilenzahl der Ergebnismatrix.
    ///
    /// Der HTTP-Handler leitet sie als `max(group_of_team) + 1` ab. Das
    /// genuegt, solange die hoechstnummerierte Staffel (Bayern, Index 4) in
    /// der Liga vertreten ist -- in TeamList_2026 trifft das auf alle drei
    /// Herren-Ligen zu.
    ///
    /// GRENZE: Stellt eine Liga kein Team der hintersten Staffel, faellt
    /// deren Zeile weg und die Matrix ist kuerzer als erwartet. Wer die
    /// Zeilen fest einer Staffel zuordnet, muss die Laenge also pruefen,
    /// statt sie vorauszusetzen. Als Feld ist `group_count` bereits
    /// vorgesehen, damit ein Aufrufer die Zahl spaeter explizit setzen
    /// kann, ohne die Signatur zu aendern.
    pub group_count: Option<usize>,
}

impl Default for SimulationParams {
    fn default() -> Self {
        Self {
            mod_factor: 20.0,
            home_advantage: 40.0,
            iterations: 10000,
            tore_slope: 0.0017854953143549,
            tore_intercept: 1.3218390804597700,
            adj_points: None,
            adj_goals: None,
            adj_goals_against: None,
            adj_goal_diff: None,
            group_of_team: None,
            relegation_places: None,
            group_count: None,
        }
    }
}

/// Result of Monte Carlo simulation - probability distribution of final positions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    /// Probability matrix: rows are teams, columns are positions
    /// probability[team_id][position] = probability of team finishing in that position
    pub probability_matrix: Vec<Vec<f64>>,
    pub team_names: Vec<String>,

    /// Absteiger je Staffel, exakt ausgezaehlt: `[staffel][anzahl]` ist die
    /// Zahl der Iterationen, in denen genau `anzahl` Teams dieser Staffel
    /// auf einem Abstiegsplatz landeten.
    ///
    /// Exakt statt aus der Prognosematrix rekonstruiert: Die Matrix enthaelt
    /// nur die Randverteilung je Team. Ein Poisson-Binomial darueber
    /// behandelte die Teams als unabhaengig -- sie sind es aber nicht, weil
    /// genau `relegation_places` Teams die Abstiegsplaetze belegen und damit
    /// stark negativ korreliert sind. Der Fehler waere strukturell, nicht
    /// numerisch (Erwartungswert 4,12 statt exakt 4,00 bei vier Plaetzen).
    pub relegation_group_counts: Option<Vec<Vec<usize>>>,
}
