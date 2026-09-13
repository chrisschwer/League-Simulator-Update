# Team Management Guide

How team data is structured and maintained in the League Simulator system.

## The TeamList is maintained data, not a generated file

`RCode/TeamList_<Jahr>.csv` is a **curated master file**, not a build
artifact. Short names and reserve-team status are decided by the operator;
the season transition only rewrites ELO and league membership and proposes
values for newcomers. See [`CONTEXT.md`](../../CONTEXT.md) for the
authoritative vocabulary (**TeamList**, **Kurzname**, **League**,
**Stammregion**) and
[ADR 0007](../adr/0007-teamlist-ist-gepflegtes-stammdatenblatt.md) for why
the file is maintained by hand rather than generated end-to-end.

## CSV File Format

Team data is stored in `RCode/TeamList_<Jahr>.csv`, semicolon-separated,
seven columns (header copied verbatim from `RCode/TeamList_2026.csv`):

```csv
TeamID;ShortText;Promotion;InitialELO;League;Region;Name
157;FCB;0;2057.25650898366;78;Bayern;Bayern München
165;BVB;0;1876.14499515202;78;West;Borussia Dortmund
```

| Column | Meaning |
|---|---|
| `TeamID` | Team identifier from api-football |
| `ShortText` | Short code (**Kurzname**) — becomes a column name in the simulation data frame; must be unique per league (see CONTEXT.md for cross-league exceptions) |
| `Promotion` | Reserve-team promotion malus flag — see [ADR 0008](../adr/0008-zweitvertretungs-malus-nach-55b-nr-3-1.md) |
| `InitialELO` | Season-start ELO rating |
| `League` | Most recently known league ID (78, 79, 80, 82, 83–87, 1034 — **not** necessarily "plays there this season", see CONTEXT.md) |
| `Region` | **Stammregion** — the Regionalliga a club is permanently assigned to; see CONTEXT.md |
| `Name` | Full club name |

There is no separate `liga` column with codes 1/2/3 — league membership is
the real api-football league ID.

## Editing the TeamList

Manual edits to short names, promotion flags, or region assignments are
made directly in `RCode/TeamList_<Jahr>.csv` with a text editor or
spreadsheet tool that preserves the semicolon delimiter and does not
reformat the `InitialELO` column. `load_team_list()` in
`RCode/transform_data.R` is authoritative for what a valid row looks like
(short-name format, uniqueness rule) — it rejects violations at load time
rather than during the season transition.

To find a team's api-football ID or verify a team name, use the
`/teams?search=<name>` endpoint documented at
<https://www.api-football.com/documentation-v3>.

## Season transition and short-name rules

The mechanics of how the TeamList is updated once a year — ELO carryover,
league reassignment from the API, the short-name uniqueness contract — are
documented once, in [Season Transition](season-transition.md); this guide
does not repeat them.

## Related Documentation

- [Season Transition](season-transition.md)
- [CONTEXT.md](../../CONTEXT.md) — TeamList, Kurzname, League, Stammregion
- [ADR 0006](../adr/0006-abstiegskopplung-der-regionalligen.md) — Abstiegskopplung (depends on `Region`)
- [ADR 0007](../adr/0007-teamlist-ist-gepflegtes-stammdatenblatt.md) — TeamList as maintained master data
- [ADR 0008](../adr/0008-zweitvertretungs-malus-nach-55b-nr-3-1.md) — reserve-team promotion malus
