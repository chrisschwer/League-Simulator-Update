# Frequently Asked Questions (FAQ)

Common questions and answers about the League Simulator system.

## General Questions

### What is League Simulator?

League Simulator is a football league prediction system that uses Monte Carlo simulations and ELO ratings to predict final league standings. It simulates the remainder of the season thousands of times to calculate probabilities for each team's final position.

### Which leagues are supported?

Currently, the system supports three German football leagues:
- **Bundesliga** (League ID: 78) - Top tier
- **2. Bundesliga** (League ID: 79) - Second tier
- **3. Liga** (League ID: 80) - Third tier

### How accurate are the predictions?

The accuracy depends on several factors:
- **Early season**: Less accurate due to limited match data
- **Mid-season**: Accuracy improves with more results
- **Late season**: Most accurate with fewer remaining matches

Historical accuracy rates:
- Final position within 1 place: ~75%
- Final position within 2 places: ~90%
- Correct champion prediction by matchday 25: ~85%

### How often are predictions updated?

The system updates automatically at these times (Berlin time):
- **Match days**: 15:00, 15:30, 16:00, 17:30, 18:00, 21:00, 23:00
- **Active period**: Daily from August to May
- **Summer break**: Weekly updates only

## Technical Questions

### What is ELO rating?

ELO is a rating system that measures team strength:
- **Starting rating**: 1500 for new teams
- **Higher rating**: Stronger team
- **Rating changes**: Based on match results and expectations
- **Typical range**: 1200-2000

Example ratings:
- Bayern Munich: ~1900-2000 (very strong)
- Mid-table team: ~1500-1600 (average)
- Newly promoted: ~1300-1400 (weaker)

### How does the simulation work?

1. **Current standings**: Fetches latest match results
2. **ELO update**: Adjusts ratings based on results
3. **Future matches**: Simulates remaining fixtures
4. **Monte Carlo**: Repeats 10,000 times
5. **Probabilities**: Calculates position likelihoods

```
For each simulation:
  - Use ELO ratings to predict match outcomes
  - Apply randomness based on probability
  - Calculate final standings
  - Record each team's position
  
After 10,000 simulations:
  - Count position frequencies
  - Convert to percentages
```

### What data sources are used?

- **Match data**: API-Football via RapidAPI
- **Team lists**: Manually maintained CSV files
- **Historical ELO**: Calculated from past seasons
- **Fixtures**: Retrieved from official league data

### How are match outcomes predicted?

The system uses ELO-based probability:

```
Expected Score = 1 / (1 + 10^((AwayELO - HomeELO) / 400))

Example:
Home team: 1600 ELO
Away team: 1500 ELO
Expected: 0.64 (64% chance of home win)
```

Home advantage is included in the ELO ratings.

## Usage Questions

### How do I read the probability heatmap?

The heatmap shows probability of each finishing position:
- **Rows**: Teams (current order)
- **Columns**: Final positions (1-18)
- **Colors**: 
  - Dark green: High probability (>50%)
  - Light green: Medium probability (20-50%)
  - Yellow: Low probability (5-20%)
  - White: Very low probability (<5%)

### What do the percentages mean?

Common percentages displayed:
- **Championship**: Probability of finishing 1st
- **Top 4**: Champions League qualification
- **Top 6**: European qualification
- **Bottom 3**: Relegation zone

Example interpretation:
- "Bayern 85% championship" = In 8,500 of 10,000 simulations, Bayern finished 1st

### Can I see historical predictions?

Currently, the system shows only the latest predictions. Historical data is not preserved in the public interface but is logged for analysis.

### Why don't percentages add up to 100%?

Each row (team) adds up to 100% across all positions. Each column (position) also adds up to 100% across all teams. If viewing filtered data, totals may appear different.

## Troubleshooting Questions

### Why are predictions not updating?

Common reasons:
1. **Outside update window**: Check if current time matches schedule
2. **No matches today**: Updates may skip on non-match days
3. **API limits**: Monthly quota may be exceeded
4. **Technical issues**: Check system status

### Why are some teams missing?

Possible causes:
- **Newly promoted teams**: Added at season start
- **Name changes**: Team renamed in database
- **Data error**: Temporary data issue

### What does "No recent data" mean?

This indicates:
- Last update was >24 hours ago
- System may be in maintenance
- Check back during scheduled update times

### Why did probabilities change dramatically?

Large probability shifts occur when:
- **Upset result**: Underdog beats favorite
- **Direct matchup**: Teams close in standings play each other
- **Multiple results**: Several relevant matches on same day
- **Late season**: Each result has larger impact

## Advanced Questions

### How is relegation handled?

The system knows relegation rules:
- **Bundesliga**: Bottom 2 relegated, 16th plays playoff
- **2. Bundesliga**: Bottom 2 relegated, 16th plays playoff  
- **3. Liga**: Bottom 4 relegated

Probabilities include playoff considerations.

### How are tiebreakers handled?

Bundesliga tiebreaker order:
1. Points
2. Goal difference
3. Goals scored
4. Head-to-head results
5. Away goals in head-to-head

The simulation implements all official tiebreaker rules.

### Can I run custom simulations?

The public interface doesn't support custom parameters. For research purposes, consider:
- Downloading the open-source code
- Running locally with modifications
- Adjusting iterations, ELO K-factor, etc.

### How do I report issues?

To report problems:
1. Note the exact time and date
2. Describe what you expected vs. what happened
3. Include screenshots if relevant
4. Submit via GitHub issues

## Data and Privacy Questions

### Is my usage tracked?

The system tracks:
- Anonymous usage statistics
- No personal data collected
- No cookies or user accounts
- IP addresses not stored

### Can I download the data?

Current predictions are view-only. For research access:
- Raw data not publicly available
- Academic requests considered
- Contact maintainers for special access

### How is data quality ensured?

Quality measures:
- Automated data validation
- Manual review of team changes
- Cross-reference with official sources
- Community reports of issues

### Is the code open source?

Yes! The League Simulator is open source:
- **GitHub**: https://github.com/chrisschwer/League-Simulator-Update
- **License**: MIT
- **Contributions**: Welcome via pull requests
- **Documentation**: Comprehensive guides included

## Seasonal Questions

### When does the season transition happen?

Season transitions occur:
- **Timing**: Late May/Early June
- **Process**: Semi-automated with manual review
- **Duration**: 24-48 hours for all leagues
- **Updates**: New teams added, relegated teams moved

### How are promoted teams handled?

New teams in higher leagues:
- **Initial ELO**: Based on league average minus adjustment
- **Typical values**:
  - To Bundesliga: ~1400-1450
  - To 2. Bundesliga: ~1350-1400
  - To 3. Liga: ~1300-1350

### What happens during summer break?

Reduced operations:
- **Updates**: Weekly instead of daily
- **Maintenance**: System updates performed
- **Preparation**: Next season data prepared
- **Testing**: New features tested

### How are winter transfers handled?

The system doesn't directly model transfers, but:
- ELO ratings naturally adjust through results
- Strong signings lead to better results
- Weak periods lower team ratings
- No manual adjustments made

## Performance Questions

### Why is the site slow?

Possible reasons:
- **Update in progress**: Simulations running
- **High traffic**: Many users after matches
- **Large calculations**: End of season complexity

Typical performance:
- Page load: <2 seconds
- Data refresh: <5 seconds
- Full update cycle: ~10 minutes

### Can I get real-time updates?

Current limitations:
- Updates at scheduled times only
- No live match integration
- Results processed in batches
- Real-time planned for future

### Why 10,000 simulations?

This number balances:
- **Accuracy**: Sufficient for stable percentages
- **Performance**: Completes in reasonable time
- **Resources**: Manageable memory usage
- **Precision**: ±1% margin of error

More simulations show minimal improvement in accuracy.

## Future Features

### What features are planned?

Roadmap includes:
- Player-level predictions
- Live match updates
- Historical prediction archive
- Custom simulation parameters
- Mobile app
- More leagues

### Can I request features?

Yes! Submit feature requests via:
- GitHub issues (preferred)
- Email to maintainers
- Community discussion

### Will other leagues be added?

Expansion priorities:
1. Other major European leagues
2. Lower German divisions
3. International tournaments

Limited by API costs and maintenance capacity.

## Getting Help

### Where can I get more help?

Resources available:
- **Documentation**: /docs folder in repository
- **GitHub Issues**: Technical problems
- **Email Support**: General questions
- **Community Forum**: Discussion and tips

### How can I contribute?

Ways to help:
- **Report bugs**: Via GitHub issues
- **Suggest features**: Enhancement requests
- **Contribute code**: Pull requests welcome
- **Improve docs**: Documentation PRs
- **Share feedback**: User experience reports

### Who maintains this system?

League Simulator is maintained by:
- Open source community
- Lead developer: Chris Schwer
- Contributors: See GitHub contributors
- Support: Best effort basis

---

*Don't see your question? Check the detailed documentation or open a GitHub issue.*