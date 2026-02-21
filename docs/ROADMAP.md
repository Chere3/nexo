# Nexo Roadmap

Product roadmap based on phased delivery.

## Phase 0 — Foundation ✅
- Flutter project scaffold
- Material 3 baseline
- Feature-first structure
- Riverpod + GoRouter
- Linux run support

## Phase 1 — Core Finance MVP ✅
- [x] Add expense/income
- [x] Home dashboard (balance + charts)
- [x] Local persistence (SQLite)
- [x] Category monthly budget progress
- [x] Edit/delete transactions
- [ ] Better empty/loading/error states

## Phase 2 — Cashew-inspired Power Features (In progress)
- [x] Recurring transactions (base CRUD)
- [x] Upcoming payments block (initial)
- [ ] Upcoming payments/reminders (state + action flow)
- [ ] Debts and lent/borrowed tracking
- [ ] Category limits per budget
- [ ] Multi-account support
- [ ] Multi-currency support

## Phase 2.5 — Material 3 Expressive System (Next)
- [ ] Define Expressive UI principles for Nexo (shape, type, motion, hierarchy)
- [ ] Build shared expressive components:
  - [ ] `DsScreenScaffold`
  - [ ] `DsSectionCard`
  - [ ] `DsListTile`
  - [ ] `DsTopAppBar`
  - [ ] `DsInput` / `DsSelect` expressive variants
- [ ] Unify spacing/radius/elevation across all core screens
- [ ] Apply expressive pass to Home, Add, Recurring, Debts, Category Limits
- [ ] Add interactive states consistency (hover/focus/pressed/disabled)
- [ ] Add expressive motion patterns (enter/exit, list transitions, feedback)
- [ ] Accessibility guardrails for expressive UI (contrast + touch targets)

## Phase 3 — Analytics & Insights
- [ ] Date-range filters
- [ ] Period-over-period comparisons
- [ ] Cashflow and category trend analysis
- [ ] Smart insight cards (spending anomalies, budget risk)

## Phase 4 — Data Portability & Reliability
- [ ] CSV import/export
- [ ] Backup/restore
- [ ] Optional cloud sync
- [ ] Data migration strategy/versioning

## Phase 5 — Product Quality & OSS Maturity
- [ ] Expanded test suite (unit/widget/integration)
- [ ] Performance profiling and optimization
- [ ] Accessibility audit (contrast, touch targets, semantics)
- [ ] Contributor onboarding improvements
- [ ] Release process and changelog automation

---

## ADHD UX Layer (Cross-phase, aligned to roadmap)
Goal: maximize capture consistency for users with ADHD (low friction, low cognitive load, high habit retention).

### Phase 2 scope (no major module expansion)
- [ ] Quick Add flow (capture in 10–15s)
- [ ] Progressive disclosure in forms (minimum required first)
- [ ] Recurrent templates (rent, subscriptions, payroll, gym)
- [ ] Clear save confirmation with next execution date
- [ ] Upcoming list prioritized by urgency: Hoy / Mañana / Esta semana
- [ ] Undo after create/delete (short snackbar window)

### Phase 3 scope (behavior + adherence)
- [ ] Lightweight streaks / consistency indicators
- [ ] Daily check-in prompt (“¿Te faltó registrar algo hoy?”)
- [ ] Gentle reminders with snooze (non-intrusive)
- [ ] Insight cards optimized for action, not just analytics

### Phase 5 scope (validation + quality)
- [ ] ADHD-focused usability review (task completion + time-to-log)
- [ ] Accessibility conformance pass (WCAG AA + touch ergonomics)
- [ ] UX copy consistency audit (clear language, low ambiguity)

### Success metrics
- [ ] Median time-to-log <= 15s
- [ ] % of days with at least one log (weekly adherence)
- [ ] % of entries created via Quick Add
- [ ] Drop-off rate during add flow

---

## Design System Track (Material 3 Expressive)
Runs in parallel with feature phases.

- [x] DS tokens: spacing, radius, motion, typography
- [x] DS components: section title, card, primary button
- [x] DS components: feature header, stat card, empty state
- [ ] DS components: top app bar, section card, expressive list tile, scaffold shell
- [ ] Expressive shape + elevation strategy documentation
- [ ] Interaction states (hover/focus/pressed) consistency
- [ ] Motion choreography guide (durations, easing, sequence)
- [ ] Theming documentation with examples
