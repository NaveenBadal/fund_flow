# Expense Manager — Product Redesign Blueprint

> Archived direction. The canonical replacement is `docs/design_system.md`
> v2.0, which defines Fund Flow as an AI-first SMS financial agent. Do not
> implement product decisions from this file.

## Product idea — Flow environment

The app is a private financial intelligence environment, not a generic expense tracker. It should
answer four questions immediately:

1. What changed today?
2. Am I safe for the rest of the month?
3. What needs my attention?
4. What should I do next?

The interface uses editorial hierarchy, dense but calm data, and purposeful
color. It avoids nested Material cards, decorative gradients on every surface,
and dashboards that expose every feature at once.

## Interaction model

There is no permanent navigation bar or feature grid. The product is four
swipeable mental spaces connected by a summonable Flow Portal:

- **Now** senses what changed and what is safe.
- **Memory** holds the explainable stream of money events.
- **Possible** simulates commitments, boundaries, and future anchors.
- **Oracle** is grounded conversation over the user's actual records.

Grounded AI is available as a persistent composer on every primary surface. A
question can be typed and sent without opening navigation or visiting a chat
destination. Manual teaching remains adjacent, while spaces are changed with a
compact context signal or horizontal gesture.

Now is deliberately non-scrolling. It renders a living financial world-state:
flexible money is the center of gravity, recent movements orbit it, opposing
inflow/outflow forces sit on an axis, and financial pressure changes the field.
It contains no dashboard sections, metric carousel, or transaction feed.

Flow DNA is intent-driven configuration. Natural commands such as “hide
amounts,” “use AED,” “scan 60 days,” and “switch to dark mode” execute directly.
Four contextual DNA strands remain as transparent fallbacks for precise control.

## Information architecture

### Today

The default landing screen. A large month position, a short daily narrative,
three meaningful signals, and the latest activity. Search, privacy, settings,
manual entry, and sync remain reachable without dominating the page.

### Activity

All transactions, grouped by time. Search and filters live here rather than in
the home header. Transaction details use a full-height editor with a dominant
amount field and progressive disclosure for metadata.

### Plan

Budgets, recurring commitments, and savings goals become one planning space.
The first view shows free-to-spend, fixed commitments, funded goals, and budget
pressure. Detail views handle editing.

### Intelligence

Analytics, merchant patterns, financial health, calendar heatmap, anomalies,
and year review share one exploration space. The landing page is insight-first;
charts support conclusions rather than existing as decoration.

## Screen decisions

| Existing screen | New role |
| --- | --- |
| Dashboard | Rebuilt as Today; long category/chart sections removed |
| Analytics | Rebuilt as Intelligence hub; period controls become a compact timeline |
| Budgets | Moved into Plan and retained as a focused detail view |
| Subscriptions | Moved into Plan as Commitments |
| Savings goals | Moved into Plan as Goals |
| Merchant profile | Retained as a clean merchant dossier |
| Financial health | Retained as a score explanation, not a decorative gauge page |
| Heatmap | Retained as a calendar exploration view |
| Year review | Retained as a narrative report |
| Audit | Renamed SMS Inbox; used to resolve uncertain imports |
| AI logs | Kept as Diagnostics and visually demoted |
| Custom categories | Kept as Category library |
| Settings | Configuration only; feature navigation removed |
| Onboarding | Rebuilt as three concise value/permission steps |

## Visual language

- Near-black ink and warm porcelain surfaces in light mode; carbon and graphite
  in dark mode.
- Electric chartreuse is the singular action/status accent. Blue is reserved
  for information, coral for spending pressure, and mint for positive movement.
- `Space Grotesk` carries large numeric and editorial display roles. `Inter`
  carries controls and reading text.
- Surfaces are separated primarily by spacing, tonal shifts, and hairlines.
  Shadows appear only on floating navigation, sheets, and active controls.
- Corners use 14, 22, and 30 px tiers. Pills are reserved for filters/status.
- Amounts are tabular, high contrast, and never compete with multiple equally
  large metrics.

## Component system

- `CommandScaffold`: shared safe-area, atmospheric background, title/actions,
  and scroll behavior.
- `HeroBalance`: one primary number plus contextual comparison.
- `SignalStrip`: compact horizontally scrolling insights.
- `LedgerRow`: merchant identity, context, and aligned amount.
- `SectionLabel`: editorial section title with optional action.
- `MetricTile`: border-led data block without nested elevation.
- `ActionDock`: floating four-destination navigation with a central quick action.
- `StatePanel`: consistent loading, empty, offline, and error presentation.
- `CommandSheet`: full-height adaptive form/detail container.

## Interaction and motion

- Navigation preserves tab state and scroll positions.
- Page entrance uses one restrained stagger; lists do not animate every rebuild.
- Number/privacy transitions cross-fade without resizing layout.
- Sync is a persistent state in Today, not a blocking modal.
- Backgrounding pauses unsent cloud work. Resuming continues the queue.
- Destructive actions require confirmation; reversible edits use undo snackbars.

## Performance rules

- No service initialization before the first frame unless required to render.
- No database query inside a list-row build.
- No full-list refresh per imported transaction.
- Cloud work uses a bounded queue, retries transient failures, and never marks a
  failed item complete.
- Primary tabs remain mounted. Expensive charts render only when their tab is
  visible and data has changed.
- Prefer const widgets, slivers, repaint boundaries around charts, and selectors
  for high-frequency state.
