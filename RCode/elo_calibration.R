# Offline-ELO-Kalibrierung fuer Ligen ohne Historie (Phase 4 Ligen-Ausbau).
#
# Die sieben neuen Ligen (fuenf Regionalligen, Frauen-BL, 2. Frauen-BL) haben
# keine ELO-Historie. Diese Datei enthaelt die reinen Rechenschritte, die aus
# einem historischen Spieldatensatz Startwerte auf der bestehenden ELO-Skala
# machen.
#
# Bewusst NICHT hier: der ELO-Walk selbst. Er lebt im Rust-Server
# (POST /league-details liefert current_elos) und wird ueber
# calibration_walk() nur angestossen. ADR 0002 verwirft den Nachbau der
# Modelllogik in R ausdruecklich -- calculate_elo_update() ist bereits ein
# Teilduplikat, ein zweites kommt nicht dazu.
#
# Modellkonstanten: Der Intercept ist fuer ALLE Ligen gleich. ELO ist die
# einzige Groesse, die ein Team beim Ligawechsel mitnimmt; nur wenn Ligen,
# die Mannschaften austauschen, dasselbe Tormodell benutzen, bedeutet ein
# ELO-Wert dies- und jenseits der Ligagrenze dasselbe.

# Spiegel der Rust-Konstanten (league-simulator-rust/src/models/mod.rs:84-87).
# Nur fuer die Diagnostik hier -- der Produktivpfad liest sie nie von hier.
TORE_INTERCEPT <- 1.3218390804597700
TORE_SLOPE <- 0.0017854953143549
HOME_ADVANTAGE_MODEL <- 40

#' Verschiebt eine ELO-Verteilung additiv auf einen Zielmittelwert.
#'
#' Nutzt die ELO-Erhaltung des Walks: Weil der Mittelwert einer geschlossenen
#' Liga ueber die Saison konstant bleibt (Rust-Test
#' `elo_is_conserved_by_the_walk`), wirkt eine Verschiebung des Startniveaus
#' unveraendert bis zum Saisonende durch. Die Ankerung ist damit eine reine
#' Startwertfrage -- kein Nachjustieren, keine Iteration.
#'
#' Additiv, nicht multiplikativ: Die Abstaende zwischen den Teams sind das
#' Ergebnis des Walks und duerfen nicht angetastet werden.
#'
#' @param elos Numerischer Vektor von ELO-Werten.
#' @param target_mean Gewuenschter Mittelwert.
#' @return Verschobener Vektor, Namen bleiben erhalten.
anchor_to_mean <- function(elos, target_mean) {
  if (length(elos) == 0) {
    stop("anchor_to_mean: ELO-Vektor ist leer")
  }
  elos + (target_mean - mean(elos))
}

#' Koppelt zwei Ligen ueber das Ergebnis ihrer Relegationsspiele.
#'
#' Relegationsspiele sind die einzige direkte Evidenz dafuer, wie zwei sonst
#' getrennte Ligen zueinander stehen. Ein Delta aus wenigen Partien traegt
#' aber viel Zufall, deshalb wirkt nur ein Anteil (`share`, per Default die
#' Haelfte) -- und zwar auf ALLE Teams beider Ligen, nicht nur auf die
#' beteiligten. So wird aus einem Zwei-Team-Ergebnis ein Liga-Signal.
#'
#' Die Verschiebung ist summenerhaltend: Was Liga A gewinnt, verliert Liga B.
#' Bei ungleicher Teamzahl wird entsprechend gewichtet, damit die Kopplung
#' keine ELO aus dem Nichts erzeugt.
#'
#' @param elos_a,elos_b ELO-Vektoren der beiden Ligen.
#' @param delta Gemessener ELO-Unterschied (positiv: Liga A ist staerker).
#' @param share Anteil des Deltas, der angewandt wird.
#' @return Liste mit `league_a` und `league_b`.
apply_relegation_coupling <- function(elos_a, elos_b, delta, share = 0.5) {
  if (share < 0 || share > 1) {
    stop("apply_relegation_coupling: share muss in [0, 1] liegen")
  }

  n_a <- length(elos_a)
  n_b <- length(elos_b)
  if (n_a == 0 || n_b == 0) {
    stop("apply_relegation_coupling: beide Ligen brauchen mindestens ein Team")
  }

  # Jedes Team bewegt sich um `share` des Deltas -- bei share = 0.5 also um
  # die Haelfte, gegenlaeufig in beiden Ligen.
  shift_a <- delta * share
  shift_b <- -delta * share

  # Bei ungleicher Teamzahl waere das nicht summenerhaltend (die groessere
  # Liga truege mehr Gesamt-ELO bei). Dann wird so umgewichtet, dass die
  # Summe konstant bleibt und die kleinere Liga sich staerker bewegt.
  if (n_a != n_b) {
    total_shift <- delta * share * 2
    shift_a <- total_shift * n_b / (n_a + n_b)
    shift_b <- -total_shift * n_a / (n_a + n_b)
  }

  list(
    league_a = elos_a + shift_a,
    league_b = elos_b + shift_b
  )
}

#' Hoechste Remisquote, die das unabhaengige Poisson-Modell erzeugen kann.
#'
#' Bestfall: gleich starke Teams, kein Heimvorteil -- dann ist lambda auf
#' beiden Seiten gleich dem Intercept und P(Remis) = sum_k dpois(k)^2.
#' Jede ELO-Differenz und jeder Heimvorteil senken die Quote von dort aus.
#'
#' Praktische Bedeutung: Liegt eine beobachtete Remisquote UEBER dieser
#' Decke, ist sie mit diesem Modell grundsaetzlich nicht darstellbar -- dann
#' hilft auch keine Streuungskalibrierung.
#'
#' @param intercept tore_intercept des Modells.
#' @return Wahrscheinlichkeit als Anteil.
poisson_draw_ceiling <- function(intercept = TORE_INTERCEPT) {
  sum(dpois(0:60, intercept)^2)
}

#' Simuliert die Remisquote fuer eine gegebene ELO-Streuung.
#'
#' Physik wie Rust (`simulation/match_sim.rs:17-25`): lambda ergibt sich
#' linear aus ELO-Differenz plus Heimvorteil, Tore sind unabhaengig Poisson.
#'
#' @keywords internal
.simulate_draw_rate <- function(sd_elo, intercept = TORE_INTERCEPT,
                                home_advantage = HOME_ADVANTAGE_MODEL,
                                n = 200000, seed = 42) {
  set.seed(seed)
  # Differenz zweier unabhaengiger Teams aus derselben Verteilung.
  d <- rnorm(n, 0, sd_elo * sqrt(2))
  lambda_home <- pmax((d + home_advantage) * TORE_SLOPE + intercept, 0.001)
  lambda_away <- pmax(-(d + home_advantage) * TORE_SLOPE + intercept, 0.001)
  mean(rpois(n, lambda_home) == rpois(n, lambda_away))
}

#' Prueft die ELO-Streuung gegen die beobachtete Remisquote.
#'
#' Bewusst pruefend, nicht setzend: Die Streuung ist das ERGEBNIS des Walks,
#' kein freier Parameter. Diese Funktion sagt nur, ob der Walk die Spreizung
#' erzeugt hat, die zur beobachteten Remisquote passt -- eine stille
#' Nachjustierung waere eine Modellentscheidung, die in den Report gehoert.
#'
#' Erwartungswerte aus der Vorabrechnung (Intercept 1.32184, HA 40):
#' Frauen-BL 15.9 % Remis -> SD ~460; 2. Frauen-BL 17.5 % -> SD ~400;
#' Bundesliga 25.0 % -> SD ~100.
#'
#' @param elos ELO-Vektor der Liga (Ergebnis des Walks).
#' @param observed_draw_rate Beobachtete Remisquote als Anteil.
#' @param intercept,home_advantage Modellkonstanten.
#' @return Liste: reachable, ceiling, actual_sd, required_sd, actual_draw_rate.
check_spread <- function(elos, observed_draw_rate,
                         intercept = TORE_INTERCEPT,
                         home_advantage = HOME_ADVANTAGE_MODEL) {
  ceiling_rate <- poisson_draw_ceiling(intercept)
  actual_sd <- stats::sd(elos)

  reachable <- observed_draw_rate <= ceiling_rate

  # Noetige SD durch Suche: die Remisquote faellt monoton in der Streuung.
  required_sd <- NA_real_
  if (reachable) {
    objective <- function(s) .simulate_draw_rate(s, intercept, home_advantage) -
      observed_draw_rate
    lo <- 1
    hi <- 1200
    if (objective(hi) < 0) {
      required_sd <- tryCatch(
        stats::uniroot(objective, c(lo, hi), tol = 1)$root,
        error = function(e) NA_real_
      )
    }
  }

  list(
    reachable = reachable,
    ceiling = ceiling_rate,
    actual_sd = actual_sd,
    required_sd = required_sd,
    actual_draw_rate = .simulate_draw_rate(actual_sd, intercept, home_advantage)
  )
}
