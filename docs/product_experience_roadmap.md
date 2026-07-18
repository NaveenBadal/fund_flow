# Fund Flow — Product Experience Roadmap

> Archived direction. This roadmap predates the locked AI-first product system
> in `docs/design_system.md` v2.0 and must not guide new product or UI work.

## Product promise

Fund Flow should reduce the number of money decisions a person has to make. It
is not a ledger with charts; it is a private daily money guide that explains:

1. what is genuinely safe to spend;
2. what is already spoken for;
3. what changed unexpectedly;
4. the one action most worth taking now.

## Current product audit

### Strong foundation

- Automatic SMS ingestion with progressive sync feedback.
- Local ledger, merchant normalization, learned categorization and audit trail.
- Recurring-charge detection, anomaly detection and computed insights.
- Budgets, goals, merchant dossiers, financial health, heatmap and year review.
- Privacy mode, app lock, export, Drive backup and responsive navigation.
- A consistent, distinctive visual system and clear four-part information
  architecture.

### Experience gaps

- Features mostly report information in separate screens instead of working
  together to recommend a decision.
- The old available balance ignored future bills and goal deadlines.
- Insights have little direct resolution: users can see a pattern but cannot
  consistently act on it in one step.
- Recurring detection describes historical commitments but does not yet offer
  confirmation, cancellation tracking, price-rise alerts or renewal reminders.
- Budgets are static limits; they do not adapt to pay cycles, irregular income,
  rollover or expected bills.
- Goals track totals but lack contribution history, automatic pacing and
  scenario planning.
- Imported transactions need confidence-based review, duplicate resolution and
  bulk correction flows.
- Onboarding explains permissions but should build the first useful plan and
  produce value before asking for every integration.

## Delivery sequence

### Experience system overhaul — delivered

- Replaced the passive bottom navigation with a responsive global action dock.
- Made add, sync, Action Inbox and Settings reachable from every primary tab,
  with an equivalent action on desktop navigation.
- Unified primary and secondary product screens under the command-screen
  hierarchy and corrected route-aware bottom spacing.
- Propagated private mode across every screen that displays money and persisted
  the preference across restarts.
- Added preferred-currency planning and prevented cross-currency aggregation in
  forecasts, trends, budgets, calendars, merchant views and annual stories.
- Rebuilt onboarding around currency, expected income, safety buffer and an
  explicit optional SMS permission decision.
- Made goal deletion discoverable and confirmed, improved responsive insight
  grids, amount fitting and user-friendly error presentation.

### 1. Daily money briefing — started

- Safe-to-spend after upcoming commitments and deadline-based goal pace.
- Month-end run-rate forecast.
- Budget-pressure detection and one recommended next move.
- A shared number across Today and Plan so the product never contradicts
  itself.

Next: add an explainable breakdown sheet, pay-cycle selection, user-adjustable
buffers and forecast confidence.

### 2. Action inbox — delivered

Create one queue for uncertain imports, unusual spending, price increases,
budget pressure and upcoming renewals. Every item should offer a direct action,
such as confirm, recategorize, ignore, cancel, move money or set a reminder.

Delivered foundation: prioritized import failures, unusual merchant activity,
budget pressure, upcoming commitments and incomplete planning signals; direct
retry/edit/navigation actions; durable dismissals with undo; live badges on
Today and Intelligence.

Next: add confirmation and recategorization for low-confidence imports, then
feed commitment price increases and renewal decisions into the same queue.

### 3. Commitment concierge

Let users confirm detected subscriptions, see the next expected charge, detect
price increases, record cancellation attempts and receive reminders before
renewal. Show monthly and annual cost plus a “what if I cancel?” impact.

### 4. Adaptive plan

Support salary/pay-cycle planning, irregular income, category rollover,
essential versus flexible spending, emergency buffer and weekly course
correction. Replace static warnings with achievable suggestions.

### 5. Goal autopilot

Add contribution history, suggested transfers, missed-pace recovery and
trade-off simulations. Show how a purchase or cancelled commitment changes a
goal date.

### 6. Trust and delight

Add import confidence, duplicate handling, undo for destructive edits, clear
forecast explanations, local-first messaging and optional celebratory moments
for meaningful progress rather than generic streaks.

## Product rules

- Every primary screen answers a user question, not a database question.
- A warning without a useful action is unfinished.
- Forecasts must show what they protected and never pretend uncertain data is
  exact.
- Automation is suggested first and user-controlled always.
- Sensitive data remains local unless the user explicitly enables a service.
- Delight comes from relief, clarity and progress—not decorative motion.
