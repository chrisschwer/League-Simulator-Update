---
name: architecture-review-prd
description: Run a focused architecture review on a code area and write a PRD that hands off cleanly to superpowers:writing-plans. Use whenever the user says "review this module", "this feels too complicated", "ist X zu shallow?", "split this PRD", "architektur-review für X", or otherwise expresses a vague sense that an area needs structural work — even if they don't use the word "architecture". The skill bridges hunch → actionable spec.
---

# Architecture Review → PRD

## What this skill does

Take a focused area of code (a module, a directory, a small set of related files) and produce a PRD that the user can feed directly into `superpowers:writing-plans`. The output is a structural critique grounded in John Ousterhout's *Deep Modules* lens (small interface, large implementation; deletion test; vocabulary discipline) but expressed as a concrete refactor proposal — not a design essay.

This skill is the bridge between "I have a feeling something is wrong here" and "there is a plan I can execute."

## What this skill does NOT do

- It does not explore the whole codebase. Scope is given (or asked for) up front and respected.
- It does not write the implementation plan. That's `superpowers:writing-plans`.
- It does not enforce a fixed stack. R, Rust, Python, TypeScript, anything — the skill detects conventions at runtime.
- It does not enforce vocabulary purity. If the codebase says `Service`, the PRD uses `Service`. We critique shallow modules, not naming.

## Workflow

Five phases. Do them in order. Don't skip the user check-in in Phase 4 — the value of this skill comes from making the user pick which finding to deepen, not from auto-deepening everything.

### Phase 1 — Detect repo conventions

Before reading any code, build a quick picture of how this repo works. You'll reuse it throughout.

Look for and note (mentally or in a short scratchpad):

- **Language(s)** — manifest files: `package.json`, `Cargo.toml`, `pyproject.toml` / `setup.py` / `requirements.txt`, `DESCRIPTION` (R), `go.mod`, `Gemfile`, `pom.xml`, `build.gradle`, etc.
- **Test framework** — directory layout (`tests/`, `test/`, `__tests__/`, `spec/`), framework signals in manifests (pytest, jest, vitest, testthat, cargo test, JUnit, RSpec, …). If signals conflict (e.g., both jest and vitest configured), ask the user.
- **Module/package boundaries** — how the codebase organizes units. R sources in flat `RCode/`, Python packages, Rust crates, TS workspaces, Go packages.
- **Existing architecture artifacts** — `README.md`, `docs/architecture/`, `ARCHITECTURE.md`, `CONTEXT.md`, `docs/adr/`, `CLAUDE.md`. Read what exists; don't require what doesn't.
- **Issue / commit language** — sample 5–10 recent commits and 1–2 open issues. Match that language in the PRD output. If the repo is bilingual, ask.
- **PRD/issue templates** — `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md`. Borrow tonality, not schema (the schema is fixed by `references/PRD-TEMPLATE.md`).

If detection is ambiguous, **ask the user** rather than guessing. Wrong assumptions here cascade into the PRD.

Map the abstract vocabulary to what this repo uses:

| Concept       | R           | Rust    | Python      | TS          | Go      |
|---------------|-------------|---------|-------------|-------------|---------|
| Module        | source file | module  | module      | module/file | package |
| Interface     | exported fn | pub fn  | public fn   | export      | exported|
| Implementation| internal fn | priv fn | _private fn | non-export  | unexported |

Use the repo's own terms in the PRD.

### Phase 2 — Establish scope

The user gave you a scope (a module, a directory, a feature area) — or didn't. If they didn't, ask: "Which area? Give me a path or a feature name." Don't proceed without scope. Codebase-wide review is a different, much larger job and not what this skill does.

Once you have scope, **read only**:

- The files in scope.
- Their direct callers (one hop out — find with grep or your repo's import-tracing convention; don't follow chains).
- The test files that exercise them, if any.
- **Operator-facing entry points** that might invoke the scope outside production code paths: `scripts/`, `bin/`, `Makefile`, `justfile`, `package.json` scripts, CI configs (`.github/workflows/`), and **the documentation that describes how the system is operated** — typically `README.md`, `docs/user-guide/`, `docs/operations/`, runbooks, deployment guides.

That's it. No exploration beyond this. The point of a focused review is the focus — but the focus must include *all* the places a function might legitimately be called from, not just other code in the same language.

**Why the documentation matters here:** in repos with a clear production-vs-tooling split (data pipelines, ML projects, anything with a "build artifact + runtime" pattern), some functions are deliberately operator tools that are invoked by humans from a REPL, a one-off `Rscript -e '...'`, or an out-of-band deployment step. These functions look "dead" to a code-only grep but are documented (or *should be* documented) in the operator guide. Reading the operator-facing docs tells you whether an unreferenced function is truly unused or just unwired-from-code-on-purpose. If the docs *should* mention an operator tool but don't, that itself is the architectural finding.

### Phase 3 — Collect findings

Read with the *deep modules* lens. You're looking for structural smells, not style nits. Examples of what counts as a finding:

- **Shallow module** — a unit whose interface is almost as wide as its implementation (a thin wrapper that adds little). The deletion test: would deleting this module just push the same complexity into callers, or would it bundle scattered logic into a smaller surface?
- **Leaky interface** — callers must know internal details to use the unit correctly (ordering of calls, magic flags, reach-through to internal state).
- **Misplaced responsibility** — orchestration mixed with I/O mixed with validation in one function or file.
- **Coupling** — two modules that always change together, or a module that knows too much about another's internals.
- **Untestable seams** — logic that can only be tested by spinning up the world (DB, network, filesystem) when it could be a pure function.
- **Vocabulary drift** — the same concept named three different ways across the scope, or one name used for three different things. (Note it; don't crusade against it.)

You don't need to find all of these. Two or three real findings beat a checklist. If the scope looks healthy, **say so** — the right output for a healthy scope is a short PRD that says "no structural work needed, here's why" and stops. Don't manufacture findings to justify the skill.

### Phase 4 — User picks 1–2 to deepen (REQUIRED CHECK-IN)

Present findings as a numbered list. Each entry: one sentence naming the smell, one sentence on the evidence (file:line is great). Ask the user which 1–2 to deepen.

Why this matters: you don't know which finding aligns with the user's actual pain. They do. Skipping this turns the skill into a generic critique generator. The check-in is what makes the output useful.

Example presentation:

```
Found 4 candidates in scope:

1. `season_processor.R:23` — `process_season_transition` orchestrates, transforms, writes
   files, and validates in one ~90-line function. Likely shallow at the orchestration layer.
2. `csv_generation.R` and `team_data_carryover.R` both reach into the same team-record
   shape but neither owns it. Suggests a missing data type.
3. `validate_season_processing` (line 490) re-derives expected counts from constants
   defined in three other files. Coupling via constants.
4. Tests in `test-season-processor.R` mock the API rather than the data shape, making
   them brittle to API-shape changes that don't matter to the logic.

Which 1–2 should I deepen? (or say "all" / "none of these, here's the real concern…")
```

Wait for the user. Don't deepen until they answer.

**Before flagging a function as unused, check operator-facing entry points.** A function with no in-language callers is not necessarily dead. Common patterns where it's alive but invisible to a code grep:

- Run by a human from a REPL during a manual operation (e.g., season transition, data migration, schema validation).
- Wired into a `Makefile` / `justfile` target rather than called from another source file.
- Documented in a README or runbook as `Rscript -e 'source("X"); my_fn()'` or `python -c "from X import my_fn; my_fn()"`.
- Invoked by a CI step or deployment hook outside the repo's primary code paths.

If a function isn't called from production code, do not assume "dead" — name it as a finding ("no in-language callers; need to confirm operator usage") and **ask the user** whether they invoke it manually. The right outcome may be "delete it" *or* "make the operator entry-point visible" (a `scripts/` wrapper + README mention) — only the user knows which.

### Phase 5 — Deepen and write the PRD

**One PRD per chosen finding.** If the user picked two findings, write two PRDs. Do not combine them — `superpowers:writing-plans` consumes one PRD = one plan, and bundled PRDs produce muddled plans.

For each chosen finding, deepen along these axes:

- **Current state** — what the interface looks like *now*, what the implementation does, who calls it. Be specific (signatures, line ranges).
- **Design options** — at least two. For each: sketch the new interface, name the trade-off, name the migration cost. Don't pad to three if two cover the space; don't compress to one to seem decisive.
- **Recommendation** — pick one. Say why it wins on the trade-off that matters here.
- **Risks & migration** — what breaks during the transition, what the cutover sequence looks like, what's reversible.
- **Test strategy** — using the test framework you detected in Phase 1, what tests pin the *current* behavior before refactoring (regression net), and what tests prove the *new* interface. TDD-friendly: red → green → refactor.

Write the PRD using the template in `references/PRD-TEMPLATE.md`. The template's structure is what `superpowers:writing-plans` expects to consume — don't reorder sections or rename fields without a reason.

**Save to:** `docs/prds/YYYY-MM-DD-<short-slug>.md` (create the directory if it doesn't exist). Use the user's date (today). Slug should be 2–4 words, kebab-case, derived from the finding ("season-processor-split", "csv-team-data-ownership").

**Language:** match the repo's commit/issue convention you detected in Phase 1. If the repo is English, write English. Don't switch to the user's chat language — the PRD lives in the repo, not the chat.

### Phase 6 — Hand off

End with three concrete next-step options for the user. Don't pick for them; they know which fits their workflow:

```
PRD saved to docs/prds/<filename>.md. Suggested next steps:

1. If the structure feels right and you want a TDD plan:
   → Hand the PRD to `superpowers:writing-plans`.

2. If the problem still feels fuzzy and you want to brainstorm before locking in:
   → Open `superpowers:brainstorming` with the PRD as input.

3. If you want to track this as a GitHub issue first:
   → `gh issue create -F docs/prds/<filename>.md`
```

## Sizing: when the finding is too big for one TDD cycle

If the deepened finding implies a refactor that can't be RED → GREEN → REFACTOR'd in a single cycle (rough heuristic: more than ~5 files touched, more than one public interface changing, or a data-shape migration), don't pretend it can. Add a **"Suggested Phasing"** section to the PRD that:

- Names Phase 1 explicitly: the smallest valuable, shippable slice.
- Notes that Phases 2+ should be re-derived by re-running this skill on whatever's left after Phase 1 lands. Don't try to write Phases 2+ in detail now — the codebase will look different by then.

This is the alternative to writing a 12-task mega-PRD that goes stale. Better one PRD that fits, plus a return visit, than one PRD that doesn't.

## Things to resist

- **Resist exploring beyond scope.** If you find something interesting two hops out, mention it in a short "Adjacent observations" footer in your *chat reply* (not in the PRD). Don't widen the review.
- **Resist deepening more than 2 findings.** Three deep dives produce PRDs nobody will read. If the user says "all of them," push back gently: "That's a 4-PRD job. Which one first?"
- **Resist prescribing a stack.** Don't say "use a class" in a Go repo, "use generics" in a pre-1.18 Go repo, "use traits" in a Python repo. The repo's idioms win.
- **Resist the urge to fix while reviewing.** This skill writes a PRD. It does not edit source files. The user (or `subagent-driven-development`) does the edits later.
- **Resist generic PRDs.** Every section should reference *this* file, *this* function, *this* test. If a section could be copy-pasted into another repo unchanged, it's not specific enough.
- **Resist treating "no in-language callers" as "dead code".** A function with zero hits in your grep across `*.R` / `*.py` / `*.ts` may still be invoked from a Makefile target, a CI step, a documented `Rscript -e '...'` operator command, or a human at a REPL during a manual procedure. Confirm with the user before recommending deletion. The right answer is sometimes "make the operator entry-point visible" rather than "delete."

## When NOT to use this skill

- The user is debugging a specific failure → use `superpowers:systematic-debugging`.
- The user is starting a new feature from scratch → use `superpowers:brainstorming`.
- The user already has a clear refactor target and just wants the plan → skip straight to `superpowers:writing-plans`.
- The user asks for a review of a PR diff → that's code review, not architecture review; use the project's review tooling.

## Reference

- `references/PRD-TEMPLATE.md` — the exact output schema. Read this before writing the PRD; it determines what `superpowers:writing-plans` can consume downstream.
