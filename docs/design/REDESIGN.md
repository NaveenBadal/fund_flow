# Fund Flow — Ground-Zero Redesign Plan

**Design system: Flux.** Product: an AI-first money agent that reads your bank SMS
and answers questions about your own money.

---

## 0. Why the last attempt failed

The "Precision" pass produced a *style guide*, not a product:

| Symptom | Evidence |
| --- | --- |
| Screens are mockups | `lib/ui/screens/activity.dart` renders a hardcoded `'Apple Store' / '- $99.00'` list |
| Settings are fiction | `lib/ui/screens/you.dart` shows "Bank Sync — Connected (3)" and a "Sign Out" button; the app has no accounts and no bank sync |
| UI is disconnected | Only `app_experience.dart` reads `appControllerProvider`; the three tab screens read nothing |
| Style choices fight the domain | True `#000000` + 12% hairlines + `fontFamily: 'monospace'` for money = austere spreadsheet. Money needs *hierarchy*, not uniform greyness |
| No data visualisation at all | A spend tracker with zero charts. Every number is a bare string |
| Neon `#00FF9D` on black | Vibrating, unbrandable, fails as a system colour |

The aesthetic problem underneath: **flat monochrome minimalism has no way to express
importance.** In a money app, three things must be instantly separable — *how much*,
*what it was*, *whether it needs you*. That requires a scale of emphasis: size, weight,
colour semantics, depth, motion. Precision threw away four of those five.

So Flux keeps the restraint (one accent family, no decoration, generous whitespace) and
adds back the expressive range: a real type scale with big jumps, tonal surfaces instead
of hairline boxes, semantic colour, physics-based motion, and charts as a first-class
component family.

---

## 1. Design principles (the five rules everything is judged against)

1. **The number is the interface.** Money is the largest, heaviest, most tabular thing
   on any screen it appears on. Never centred, never mono-by-accident — tabular figures
   so digits don't jitter as they animate.
2. **Spending is not an error.** Outflow is ink-coloured, not red. Colour is reserved for
   *meaning*: green = money in, amber = needs your attention, red = destructive or broken.
   A day of normal spending should look calm.
3. **Every claim is traceable.** Any figure the AI states can be tapped down to the
   transactions, and any transaction down to the raw SMS that produced it. Trust is the
   product.
4. **Depth over borders.** Layer surfaces and blur floating chrome. Hairlines only where
   a genuine list separation exists.
5. **Motion explains, never decorates.** A row expands into its detail page. A balance
   rolls when it changes. Nothing bounces for fun.

---

## 2. Flux foundations

### 2.1 Colour

Not a Material seed-generated palette (too much tonal mush) — a hand-tuned set with
generated tonal steps only for the brand ramp.

**Neutrals** (cool-tinted, never pure black — pure black kills depth perception on OLED
at the surface layers):

```
Dark    bg #0A0A0F   s1 #131319   s2 #1B1B22   s3 #24242C   line #FFFFFF14
Light   bg #FAFAFC   s1 #FFFFFF   s2 #F2F2F7   s3 #E8E8EF   line #0A0A0F14
Text    dark:  #F5F5F7 / #A0A0AB / #6E6E78      light: #0A0A0F / #5C5C66 / #8E8E98
```

**Brand — Iris** (AI / interactive / focus). This is the only hue that means "the app is
doing something".

```
50 #EEEEFF · 100 #DEDEFF · 300 #A8A8F5 · 500 #5B5BD6 · 600 #4A48C4 · 700 #3A38A0
```

**Semantic**

```
income     light #0E8F5F   dark #34D399
attention  light #B45309   dark #FBBF24     (review needed, over budget, anomaly)
danger     light #C6293B   dark #F87171     (delete, failure only)
outflow    = text primary  (deliberate: expenses are not alarming)
```

**AI gradient** — one gradient in the whole app, only on agent affordances (composer
focus ring, thinking indicator, Ask tab icon when active):
`#5B5BD6 → #7C5CE6 → #22A6C3`, 135°.

**Category palette** — 8 hues, max-spaced, checked in both themes, used *only* in charts
and category chips (never as row backgrounds):
`#5B5BD6 iris · #22A6C3 cyan · #0E8F5F green · #B0870A amber · #D4653B clay ·
#C2478F magenta · #6B7280 slate · #7C5CE6 violet` — `Other` always slate.

> At implementation time, load the `dataviz` skill before writing any chart code and
> validate this categorical set against it.

### 2.2 Type

Keep Inter, but replace the static `assets/fonts/Inter.ttf` with **Inter Variable** so
weight is a continuous axis (Flux uses 450/550/650 — the in-between weights are most of
why it will look designed rather than default). All money uses
`FontFeature.tabularFigures()`, globally, via the text theme — not per-widget.

| Token | Size / Line | Weight | Use |
| --- | --- | --- | --- |
| `moneyHero` | 52 / 56 | 700, -2.0 | Home net-flow figure |
| `moneyLarge` | 30 / 34 | 650, -1.0 | Detail page amount, stat tiles |
| `moneyRow` | 17 / 22 | 600, -0.2 | Ledger row amount |
| `display` | 34 / 40 | 700, -1.2 | Page titles (large, collapsing) |
| `title` | 22 / 28 | 650, -0.4 | Section / sheet titles |
| `bodyLg` | 17 / 24 | 450 | Chat prose, merchant names |
| `body` | 15 / 22 | 450 | Default |
| `label` | 13 / 16 | 550, +0.1 | Chips, buttons, nav |
| `caption` | 12 / 16 | 500 | Timestamps, source notes |
| `overline` | 11 / 14 | 650, +0.8, caps | Section headers |

Type scale ratio is intentionally jumpy (52 → 30 → 17) so hierarchy reads at a glance.

### 2.3 Shape

Flutter ≥3.32 ships `RoundedSuperellipseBorder` — real continuous ("squircle") corners
with no package. Use it for every card, sheet, button and chip. That single choice is
most of what people read as "Apple made this".

`xs 8 · sm 14 · md 20 · lg 28 · sheet 32 (top only) · full`

### 2.4 Elevation & glass

Three levels, expressed differently per theme:

- **Light**: two-layer shadow — `0 1 2 rgba(10,10,15,.06)` + `0 8 24 rgba(10,10,15,.08)`.
- **Dark**: no shadow (invisible). Step the surface (`s1→s2→s3`) and add a 1px
  `#FFFFFF0F` top inner highlight. This is the trick that makes dark UI look layered.

**Glass** = `BackdropFilter(blur 24) + surface @ 72% + hairline`. Allowed on exactly four
things: bottom nav bar, collapsed sticky page headers, sheet grabber chrome, chat
composer. Rule: never nest glass in glass, never glass over a static background (it
degrades to grey and costs a raster pass for nothing).

### 2.5 Motion

Springs, not curves, for anything the finger drives:

```
snap        stiffness 520  damping 32   press/toggle/chip
standard    stiffness 380  damping 28   nav, sheets, reveals
expressive  stiffness 300  damping 22   FAB → sheet, approval card entry (slight overshoot)
emphasized  Cubic(0.2, 0, 0, 1)  240ms  non-interactive fades
```

Patterns:

| Interaction | Motion |
| --- | --- |
| Tab switch | Shared axis X, 24px offset + fade, `standard` |
| Ledger row → detail | Container transform (hero on the amount + merchant) |
| Sheet | Spring up + scale 0.98→1, scrim fades to 40% |
| Balance changes | Odometer digit roll, per-digit 40ms stagger |
| List load | Skeleton → content crossfade; first 8 rows stagger 30ms |
| AI thinking | Gradient sweep along the composer's top edge, 1.4s loop |
| Answer parts arrive | Each part fades + rises 8px, 60ms apart |
| Approval card | `expressive` spring in, haptic `mediumImpact` |

Honour `MediaQuery.disableAnimationsOf(context)` → durations collapse to 0, crossfades
only.

### 2.6 Haptics

`selectionClick` on chips/tabs · `lightImpact` on swipe-action commit ·
`mediumImpact` on approval card appear · `heavyImpact` on destructive confirm ·
none on scroll.

---

## 3. Information architecture

Three tabs. Settings are **pushed pages**, never stacked sheets. (Sheets are for a single
decision; settings are a hierarchy.)

```
┌─ Home ───────────────┬─ Activity ──────────┬─ Ask ────────────────┐
│ this month's flow    │ the full ledger     │ the agent            │
│ what needs you       │ search / filter     │ threads, proposals   │
│ where money goes     │ bulk edit           │ suggestions          │
└──────────────────────┴─────────────────────┴──────────────────────┘
        ⚙ pushed from Home header → Settings hierarchy
```

The current 3-tab set is `Ask / Activity / You`. **Change: drop `You` as a tab, promote
`Home`.** Reasons: (a) a settings tab spends a third of the app's most valuable real
estate on something used twice a month; (b) an AI money app with no dashboard forces you
to *ask* before you can *see*, which is a worse first 5 seconds; (c) Ask stays reachable
in one tap regardless.

Tab order `Home · Activity · Ask` — Ask last/right because it's the "compose" action, and
the composer lives at the bottom-right where the thumb is.

---

## 4. Feature inventory — keep, build, cut

### Keep (already built, needs a real UI)

| Feature | Where it lives now | Where it goes |
| --- | --- | --- |
| SMS historical import w/ progress, pause, stop | `ImportStatus`, `app_controller.importMessages` | Onboarding step 3 + Settings → Sources, with a live progress sheet |
| Notification capture | `notification_source.dart` | Settings → Sources, toggle + permission explainer |
| Needs-review queue | `ReviewState.needsReview` | **Home banner + dedicated Review flow** (currently invisible) |
| Duplicates / anomalies / recurring | `finance_duplicates`, `finance_anomalies`, `finance_recurring_candidates` | Home cards + Insights, not only reachable by asking |
| Agent proposals + undo | `agent_proposal.dart`, `_applyAgentProposal` | Inline approval card in chat, undo snackbar |
| Durable memory | `memory_list/set/delete` | Settings → Memory (list, edit, delete) |
| Multi-provider AI + model catalog | `intelligence/` | Settings → Intelligence, with a Test-connection result row |
| App lock / biometric | `local_auth`, `setAppLock` | Settings → Privacy |
| Hide amounts | `hideAmounts` | Privacy + a long-press-to-peek gesture on Home |
| Verified GitHub updater | `update/app_updater.dart` | Settings → About, with a badge when available |
| Thread history | `ConversationThread` | Pushed page from Ask header |
| Agent telemetry | `agent_performance` | Settings → Intelligence → Diagnostics (collapsed, not front-of-house) |

### Build (new)

| Feature | Why | Placement |
| --- | --- | --- |
| **Home / this-month view** | Answers "am I OK?" with zero input | Tab 1 |
| **Review flow** | Low-confidence extractions currently rot unseen. Card stack: amount + raw SMS + guessed category, swipe right = confirm, left = fix. This is the single highest-value new screen | Home banner → full-screen |
| **Budgets (category limits)** | The only way "how am I doing" has an answer with a *target* | Home rings → pushed Budgets page; AI can propose one |
| **Subscriptions** | `finance_recurring_candidates` already finds them; confirming turns them into forecast + "you'll be charged Fri" | Pushed from Home |
| **Merchant profile** | Tap any merchant → all transactions, total, avg, cadence, sparkline | Pushed from ledger row / detail |
| **Transaction detail w/ evidence** | Shows the raw SMS + confidence + what was parsed from where. Trust anchor | Pushed from ledger row |
| **Search + filter bar** | 26 MCP filters exist; the UI exposes none | Activity tab header |
| **Manual add** | `TransactionSource.manual` exists with no entry point. Cash spend is real | FAB on Activity, amount keypad sheet |
| **Monthly report** | One scrollable "here's your month" with charts, generated on the 1st | Pushed from Home; notification |
| **CSV export** | Data ownership; cheap | Settings → Privacy |
| **Charts** | Sparkline, category donut, daily bars, budget ring | Component family |

### Cut

| Cutting | Reason |
| --- | --- |
| "Bank Sync / Connected (3)" | Doesn't exist. Fake affordances destroy trust faster than missing features |
| "Sign Out" | No accounts. Nothing to sign out of |
| `You` tab | Replaced by Home + pushed settings |
| `lib/ui2/**` (empty dirs) | Dead |
| `monospace` font for money | Replaced by Inter tabular figures |
| Generic markdown chat rendering as the primary path | Replaced by typed parts (below) |
| Agent telemetry as a top-level surface | Diagnostics, collapsed |

---

## 5. Screen specs

### 5.1 Home — "your money right now"

Large-title collapsing header (`display` → `label` on scroll, header becomes glass).

1. **Flow card** (hero) — net for the current month in `moneyHero` with an odometer roll.
   Below: two inline stats `In` / `Out` with a 30-day sparkline behind them at 12% opacity.
   A thin progress arc shows how far through the month you are, so "₹42k spent" is read
   against "you're 60% through July".
2. **Attention strip** — appears only when it has content. One row per item, amber leading
   dot: `7 transactions need review`, `Netflix charged twice on Aug 3`,
   `Food is 118% of its limit`. Tapping opens the relevant flow. Empty state: the strip is
   absent (not a "you're all caught up" card taking 80px forever).
3. **Where it went** — donut + top 5 categories with amounts and change vs last month.
   Tap a slice → filtered Activity.
4. **Budgets** — horizontal ring row, only if budgets exist. Otherwise a single
   `Set a limit` ghost row.
5. **Upcoming** — confirmed subscriptions in the next 14 days, with dates.
6. **Insight** — *one* agent-authored observation, generated once a day and cached (never
   blocks the screen, never spins). Tapping it opens Ask with that thread pre-loaded.

Pull-to-refresh triggers notification drain + recompute. Long-press anywhere on the flow
card peeks past `hideAmounts`.

### 5.2 Activity — the ledger

- Sticky glass header: search field + filter chips row (`Period · Direction · Category ·
  Account · Needs review`). Active filters are Iris-filled; a `Clear` chip appears at the
  head of the row.
- Grouped by day with a section header carrying that day's net (`Wed 6 Aug · −₹2,340`).
- Row: merchant avatar (initial on a colour derived from a hash of the name), merchant +
  category · time, amount right-aligned in `moneyRow`. Needs-review rows carry an amber
  left edge, 2px.
- Swipe right → confirm/categorise; swipe left → delete (with undo snackbar).
- Long-press → multi-select mode → bulk recategorise (maps to
  `transactions_bulk_update_category`).
- Infinite scroll paging against `transactions_search`, 50/page.
- FAB (`expressive` spring) → manual-add sheet with a numeric keypad, merchant field,
  category grid, date. Amount is entered in major units and converted once, centrally.
- Row → **Detail page** (container transform): amount hero, merchant (tap → profile),
  category chip (tap → change), date/account/source, confidence meter if <1, and an
  expandable **"From this message"** block showing `sourceText` verbatim with the parsed
  spans highlighted. Actions: edit, delete, "always categorise X as Y".

### 5.3 Ask — the agent

- Empty state: gradient-edged composer, `What do you want to know?`, and 4 suggestion
  chips generated from actual data (`Why was July higher?`, `Food this month`,
  `Show duplicates`, `Set a ₹10,000 food limit`) — not static copy.
- Header: thread title, `+` new chat, history icon → pushed thread list (swipe to delete).
- **Answer rendering is typed, not markdown.** `AgentPartKind` already defines
  `conclusion · narrative · metricRow · comparison · breakdown · transactionList ·
  insight · sourceNote · followUps · proposal · warning`. Each gets a real widget:
  - `conclusion` → `bodyLg` 450, the only part at full width, no card
  - `metricRow` → stat tiles with `changeFraction` as a coloured delta
  - `comparison` → two-bar chart with labels
  - `breakdown` → ranked rows with inline proportional bars, category colours
  - `transactionList` → real ledger rows, tappable through to detail
  - `sourceNote` → `caption`, muted, with the app-appended record count
  - `followUps` → chips
  - `warning` → amber-edged block
  - `proposal` → approval card (see 6.4)
- **Working trace**: while `asking`, show the live `askStage` as a compact line with a
  gradient sweep. After the answer, collapse it into a tappable `Checked 412 records ·
  3 tools · 4.1s` row that expands to the actual tool calls and arguments. This is the
  trust surface, and it costs one row.
- Stop button while running (`stopAgent` exists). Retry chip on failure (`retryQuestion`
  exists).
- Composer: glass, grows to 5 lines, Iris gradient focus ring, send button morphs to stop.

### 5.4 Settings (pushed hierarchy from Home ⚙)

```
Intelligence   provider · chat model · parsing model · test connection · Diagnostics ▸
Sources        SMS lookback (7–30d) · run import · notification capture · permissions
Memory         list of approved facts, add/edit/delete
Privacy        what leaves the device (from privacy_boundary) · hide amounts · app lock ·
               export CSV · delete all data
Appearance     system / light / dark · currency
About          version · check for update · licences
```

Each row is a `ListRow` with a value on the right; destructive rows are `danger` and
require a typed/biometric confirm.

### 5.5 Onboarding (4 screens, ~40s)

1. What this is — one sentence, animated flow illustration.
2. Connect intelligence — provider picker, key field, live `Test` (this must succeed
   before continuing; a wrong key discovered at import time is the worst failure mode).
3. Read your messages — the honest explanation of SMS access + lookback slider, then a
   live import with a running count. Skippable.
4. Optional: notification capture + app lock. Then land on Home with real data already in
   it — never an empty state on first run if the import found anything.

---

## 6. The AI agent — making it a real agent, not a chatbot

### 6.1 Scope (the "write me a python program" bug)

Root cause is structural, not prompt-level: `agent_runner.dart:192` falls back to
`AgentPresentation.unstructured(text)`, so any free-text model reply renders as prose.
That is the escape hatch through which general-assistant answers arrive.

Fix, three layers:

1. **Add a `redirect` part kind.** In-scope = this person's money, this ledger, this app,
   and finance concepts *as they apply to their data*. Out of scope = code, general
   knowledge, other people's finances, market/stock advice, anything requiring the
   internet. Out-of-scope questions get `{"type":"redirect"}` → a card reading
   *"I only work on your money. I can't help with that — but I can tell you where your
   money went last month."* plus follow-up chips.
2. **Make `answer_compose` mandatory.** Prose-only replies get exactly one repair turn
   ("your reply must call answer_compose"); a second failure renders a structured error
   card, not the raw text. `unstructured` stays only as a crash-safe last resort and gets
   a visible "unverified" marker.
3. **Regulated advice guardrail** in the contract: describe the person's own numbers,
   never recommend an investment or product.

### 6.2 New tools to add to the local MCP server

| Tool | Risk | Why |
| --- | --- | --- |
| `budgets_get` / `budgets_set` | read / proposal | Makes "am I on track" answerable and lets "cap food at 10k" work conversationally |
| `subscriptions_list` / `subscriptions_confirm` | read / proposal | Promotes recurring *candidates* into confirmed facts |
| `review_queue` | read | So the agent can say "7 need review" and offer to open the flow |
| `merchant_profile` | read | Per-merchant totals/cadence without dumping rows |
| `forecast_month` | read | Deterministic run-rate projection — no model arithmetic |
| `transactions_categorize_rule` | proposal | "always call SWIGGY food" → a durable rule, not 40 edits |
| `ui_navigate` | action | Lets an answer end in a real destination: "opened your food transactions". The agent driving the app is what makes it an agent |

### 6.3 Speed (this decides whether the feature gets used)

- **Deterministic fast path**: the ~10 canonical questions (`this month`, `top
  categories`, `vs last month`, `needs review`, `subscriptions`) are answered locally
  with zero model round trip, rendered through the exact same typed parts. Suggestion
  chips map to this path, so the first tap is instant.
- Parallel tool calls (contract already asks for it), briefing cached per period.
- Prefetch the daily insight in the background after import, never on tab open.
- Optimistic composer: the question appears in the thread immediately; the answer streams
  parts in as they arrive.

### 6.4 Proposals

One card, inside the thread, `expressive` spring + haptic: title, an explicit
before → after diff (`Food → Groceries`, `₹0 → ₹10,000`), `Approve` (Iris, filled) /
`Dismiss` (ghost). After approval it becomes a settled row (`✓ Applied · Undo`) — undo
lives on the card for 10s, not only in a snackbar that scrolls away.

### 6.5 Memory

Never silent (already true in the contract). Approving a memory shows the exact string
being stored. Settings → Memory lists every fact with its age and an edit/delete.

---

## 7. Code plan

```
lib/
  design/           # Flux — zero app knowledge, no imports from features/
    tokens/         colors.dart  typography.dart  shape.dart  motion.dart  spacing.dart
    theme/          flux_theme.dart          (light + dark from one source)
    components/     buttons · cards · sheets · list_rows · chips · fields ·
                    empty_states · skeletons · banners · money_text · avatar
    charts/         sparkline · donut · bars · budget_ring · delta_badge
    motion/         spring.dart · shared_axis.dart · container_transform.dart · odometer.dart
  features/
    home/           home_page.dart  flow_card.dart  attention_strip.dart  …
    activity/       activity_page.dart  filters.dart  tx_detail.dart  merchant_page.dart
                    manual_add_sheet.dart  review_flow.dart
    ask/            ask_page.dart  composer.dart  parts/  trace.dart  proposal_card.dart
                    threads_page.dart
    settings/       settings_page.dart  intelligence.dart  sources.dart  memory.dart
                    privacy.dart  appearance.dart  about.dart
    onboarding/
    shell/          shell.dart  glass_nav_bar.dart
  domain/ data/ agent/ intelligence/ ingestion/ update/    # unchanged
```

- **Delete**: `lib/ui/**`, `lib/ui2/**`.
- **Split `app_controller.dart` (1628 lines)** into `ImportController`, `AgentController`,
  `LedgerController`, `PreferencesController` over the same store. It's currently the
  single biggest obstacle to changing anything safely.
- Widen `MoneyTransaction` for the new features: `tags`, `excludedFromTotals`,
  `recurringId`, `ruleId`. New tables: `budgets`, `subscriptions`, `category_rules`.
  Migration, not a wipe.
- `lib/design` must not import `lib/features` or `lib/domain` — enforced by review, so the
  system stays portable and demonstrable in isolation.
- Add a `/design` debug route rendering every component in both themes at 1.0 and 1.4 text
  scale. This is what gets screenshotted each phase.

---

## 8. Phases (each ends in a screenshot pass on the emulator)

| # | Scope | Done when |
| --- | --- | --- |
| **P0** | `lib/design` complete + shell + glass nav + theme + `/design` gallery. Delete `lib/ui`, `lib/ui2` | Gallery screenshots clean in light/dark, 1.0/1.4 scale |
| **P1** | Activity: real data, search, filters, grouping, swipe, detail + SMS evidence, merchant page, manual add | Real ledger is fully usable; no dummy data anywhere in the repo |
| **P2** | Home: flow card, attention strip, donut, charts, cached insight | Opens in <300ms with real numbers |
| **P3** | Ask: typed part widgets, trace row, proposal card, threads, `redirect` + mandatory `answer_compose`, fast path | "Write a python program" gets the redirect card; "food last month" answers instantly |
| **P4** | Review flow · budgets · subscriptions · monthly report · export | Each reachable without asking the agent |
| **P5** | Onboarding rewrite, motion polish, empty states, a11y (44px targets, contrast, semantics, reduce-motion), perf pass | Full screenshot sweep, jank-free scroll on a mid-range device |

Split-controller refactor lands with P1 (it blocks everything after).

---

## 8a. What shipped, and what did not (2026-08-07)

Built and verified on the emulator against a seeded ledger of 111 transactions:
Flux (`lib/design`), the three-tab shell, Home, Activity with filters and swipe
actions, transaction detail with SMS evidence, merchant profile, the review flow,
budgets, subscriptions, breakdown, the whole settings hierarchy, onboarding, the
Ask surface with typed answer parts, and the `/design` gallery. `lib/ui` and
`lib/ui2` are deleted.

Six defects were found by looking at screenshots, not by the analyzer, and all
six are fixed:

| Defect | Cause |
| --- | --- |
| Yellow underline under every label | No `Material` ancestor, so text inherited Flutter's fallback debug style |
| The whole page blurred behind the tab bar | An unclipped `BackdropFilter` blurs its entire ancestor layer |
| A 50%-black smudge under every light-mode card | `withValues(alpha:)` *replaces* alpha; the ambient shadow was derived from an already-transparent token |
| Every tab switch left the app 7.5% darker, permanently | The tab fade's opacity layer re-composited through the tab bar's backdrop filter |
| Pushed pages showed dark text on a black window | Only the shell painted a background; routes above it painted none |
| Sparkline flat across future dates, bars washed out, donut figure through the ring | Series ran to month end; "today" highlighted a bar with no value; centre text unbounded |

**Deferred, with reasons:**

- **The `app_controller.dart` split.** It is 1628 lines and still is. Budgets went
  into a *new* `BudgetsController` rather than being folded in, which gets the
  same structural benefit without editing working import and agent code that has
  no test suite behind it. The split is still worth doing on its own.
- **Ledger paging.** The store loads every transaction into memory and Activity
  filters that list. Correct at this app's scale (a 30-day lookback), wrong at
  ten years of data.
- **`merchant_profile`, `forecast_month`, `transactions_categorize_rule` and
  `ui_navigate` agent tools.** `budgets_get`, `budgets_set`, `budgets_clear`,
  `review_queue` and `subscriptions_list` shipped; the rest are additive.
- **The deterministic fast path** for canonical questions. The suggestion chips
  still go through the model, so the first tap costs a round trip.
- **Monthly report** as its own surface — the breakdown page covers most of it.
- **Runtime verification of the agent** (the redirect card, proposals, typed
  parts against a live model). Every path is built and compiles, but it needs a
  provider key to exercise, so it is verified by construction and not by
  screenshot. This is the largest untested area.

## 9. Decisions (settled 2026-08-06)

1. **Android only.** No iOS compromise. Auto-ingestion (SMS + notification capture) is the
   spine of the product, blur/glass budget is generous, and manual entry exists for cash
   rather than as a fallback platform story.
2. **Hard redirect.** Scope is this person's money, this ledger, this app. Code, trivia,
   general knowledge and market/product advice all get the `redirect` part — refused in one
   sentence, followed by follow-up chips pointing at something it *can* answer. No
   finance-education surface, because that boundary cannot be enforced cleanly.
3. **Budgets: user-set, agent-proposed.** Manual limits from day one. After 30 days of data
   the agent may propose limits derived from actual history, always through the approval
   card — never applied silently.
4. **Lands on Home.** Flow card keeps the hero treatment; Ask is one tap right.
