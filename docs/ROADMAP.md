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
- [x] Better empty/loading/error states

## Phase 2 — Cashew-inspired Power Features ✅
- [x] Recurring transactions (base CRUD)
- [x] Upcoming payments/reminders (state + action flow)
- [x] Debts and lent/borrowed tracking
- [x] Category limits per budget
- [x] Multi-account support
- [x] Multi-currency support (base)

## Phase 2.5 — Material 3 Expressive System (In progress)
- [x] Define Expressive UI principles for Nexo (shape, type, hierarchy)
- [x] Build shared expressive components:
  - [x] `DsScreenScaffold`
  - [x] `DsSectionCard`
  - [x] `DsListTile`
  - [x] `DsTopAppBar`
  - [x] `DsInput` / `DsSelect` expressive variants
- [x] Unify spacing/radius/elevation across core screens (initial pass)
- [x] Apply expressive pass to Home, Add, Recurring, Debts, Category Limits
- [x] Add interactive states consistency (hover/focus/pressed/disabled)
- [x] Add expressive motion patterns (enter/exit, list transitions, feedback)
- [x] Accessibility guardrails full pass (contrast + touch targets, initial pass)

## Phase 3 — Analytics & Insights (In progress)
- [x] P3-01 Date-range filters (7d / 30d / mes actual / custom)
- [x] P3-02 Period-over-period comparisons
- [ ] P3-03 Cashflow and category trend analysis
- [ ] P3-04 Smart insight cards (spending anomalies, budget risk)
- [ ] P3-05 Analytics Period Hub (overview de periodos → detalle seleccionado)

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
- [x] Quick Add flow (capture in 10–15s)
- [ ] Progressive disclosure in forms (minimum required first)
- [x] Recurrent templates (rent, subscriptions, payroll, gym)
- [x] Clear save confirmation with next execution date
- [x] Upcoming list prioritized by urgency: Hoy / Mañana / Esta semana
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
- [x] DS components: top app bar, section card, expressive list tile, scaffold shell
- [x] Expressive shape + elevation strategy (initial implementation)
- [ ] Interaction states (hover/focus/pressed) consistency
- [x] Motion choreography guide (durations, easing, sequence)
- [x] Theming documentation (initial) in `lib/design_system/README.md`
