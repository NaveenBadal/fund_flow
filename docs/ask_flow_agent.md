# Ask Flow agent architecture

> Historical implementation reference. Product, UX, navigation, and visual
> decisions are governed exclusively by `docs/design_system.md` v2.0. Where
> this document conflicts with that AI-first specification, ignore it.

Ask Flow uses cloud AI for all natural-language interpretation. It does not
use a local intent parser or local language model. Financial arithmetic,
database filtering, policy enforcement, mutations, and verification remain
deterministic and on-device.

## Trust contract

- The model cannot execute SQL or access SQLite directly.
- Every capability is exposed through a bounded, typed MCP tool.
- Transaction source text and remembered preferences are untrusted data, not
  instructions.
- Totals, comparisons, breakdowns, forecasts, and detections are calculated by
  local code from bound queries.
- Currencies are returned independently and are never implicitly combined.
- Sensitive, destructive, bulk, and persistent-memory changes require a
  human-readable review and explicit user approval.
- Changes report whether they were applied and offer undo when reversible.
- Assistant messages persist the validated artifact separately from generated
  prose, so financial cards never depend on parsing model Markdown.

## Capabilities

- Filtered transaction search and authoritative summaries
- Category, merchant, day, and direction breakdowns
- Explicit period comparisons
- Recurring-payment and possible-duplicate detection
- Spending anomaly detection
- Transparent trailing-average cash-flow forecasts
- Monthly overall and category budgets
- Create, update, delete, and bounded bulk transaction corrections
- Rich ledger fields: account, counterparty account, settlement status,
  provenance, confidence, transfer linkage, and notes
- Explicit remembered preferences and goals
- App settings and destination navigation
- SMS source re-analysis behind explicit consent

## Runtime and performance

- One persistent HTTP client and Ollama keep-alive
- MCP initialization and tool definitions cached for the Ask Flow session
- NDJSON response streaming with incremental UI rendering
- True HTTP request abortion from the Stop action
- Short backoff retries only for 429, 502, and 503 responses
- Immediate deterministic rendering after a successful tool call when further
  model reasoning is unnecessary

## Required regression gates

Before release:

1. `flutter analyze`
2. `flutter test`
3. Development and production Android builds
4. Profile build and launch on the target Pixel configuration
5. Narrow-screen and 200% text validation for structured financial cards
6. Database migration validation on an existing installation

New tools must include a strict JSON schema, bounded database behavior,
explicit confirmation when they can mutate state, deterministic test coverage,
and a renderer-safe structured result.
