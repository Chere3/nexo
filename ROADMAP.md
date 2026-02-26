# ROADMAP

Portfolio objective: keep Nexo visibly production-minded, testable, and contributor-ready while shipping user-facing value.

## Quick wins (1-2 weeks)

- [ ] Add a single quality gate script (`scripts/quality.sh`) and document it in README.
- [ ] Add `docs/architecture.md` with current feature boundaries and ownership.
- [ ] Add screenshots/gifs for core flows in README.
- [ ] Ensure every feature folder has a short README (purpose, state, pending work).

## Medium (2-6 weeks)

- [ ] Introduce robust transaction form validation and failure UX.
- [ ] Add repository-level test strategy doc (unit/widget/integration split).
- [ ] Add CI job cache optimization for Flutter dependencies.
- [ ] Add seed/demo data tooling for quick local onboarding.

## Big bets (6-12 weeks)

- [ ] Multi-account budget envelopes with monthly rollovers.
- [ ] Recurring transactions and forecast simulation.
- [ ] Smart spending insights with category anomaly detection.
- [ ] Data export/import (CSV + encrypted backup).

## Strategic rewrites (if complexity demands)

- [ ] Re-evaluate state boundaries if feature modules begin leaking cross-domain dependencies.
- [ ] Extract domain services from UI layers to improve testability and scale.
- [ ] Introduce offline sync abstraction if cloud sync becomes a requirement.

## Delivery discipline

Each roadmap item should land with:

1. PR link and concise rationale.
2. Validation evidence (commands + output).
3. Updated docs for onboarding continuity.
4. Follow-up tasks explicitly tracked.
