#include <Rcpp.h>
using namespace Rcpp;

//[[Rcpp::export]]
NumericVector SpielNichtSimulieren (double ELOHome, double ELOAway, double GoalsHome, double GoalsAway,
                                    double modFactor, double homeAdvantage) {
    
    // Recalculate ELO based on an actual result
    
#include <algorithm>
    
    
    NumericVector out (5);
    
    double ELODeltaInv = ELOAway - ELOHome - homeAdvantage;
    ELODeltaInv = std::min ( std::max( ELODeltaInv, double (-400)), double (400));
    
    double ELOProb = 1 / ( 1 + pow (10, (ELODeltaInv / double (400))));
    
    int goalDiff = GoalsHome - GoalsAway;
    double result = ((0 < goalDiff) - (goalDiff < 0) + 1) / 2.0;
    double goalMod = sqrt (std::max (abs (goalDiff), 1));
    
    double ELOModificator = (result - ELOProb) * goalMod * modFactor;
    
    out (0) = ELOHome + ELOModificator;
    out (1) = ELOAway - ELOModificator;
    
    out (2) = GoalsHome;
    out (3) = GoalsAway;
    
    out (4) = ELOProb;
    
    return (out);
    
}

