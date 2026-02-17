# portfolio-lab

Portfolio tracker + projections + ML lab (local-first), built with reproducibility and auditability in mind.

## Goals
- Single source of truth for portfolio data (transactions, prices, FX, dividends)
- Daily portfolio snapshots (positions, PnL, allocation)
- Projections (scenarios, Monte Carlo) and goal tracking
- ML research with rigorous backtesting (walk-forward, no leakage)

## Repository layout
- infra/      -> local stack (docker compose), env templates
- src/        -> application code (pipelines, analytics, projections, ml)
- sql/        -> schema, views, saved queries (versioned)
- docs/       -> ADRs, definitions, roadmap
- notebooks/  -> research only
- data/       -> NOT versioned (broker exports, personal files)

## Workflow
- Trunk-based: main protected, work via short-lived branches + PR
- Conventional Commits
- CI required before merge (next milestone)

## Status
Scaffold phase (Milestone 0).
