# Fund Flow agent architecture

This is the implementation contract for Fund Flow's intelligence layer. It
supersedes the one-shot answer client, precomputed context prompt, regex SMS
parser, candidate gate, and single-category change envelope.

## Product promise

The agent is the primary operating interface for a person's money record. It
can investigate, explain, compare, find evidence, and prepare changes in
ordinary language. It never receives database access, never invents financial
arithmetic, and never applies a mutation without local validation and explicit
human approval.

AI is responsible for semantic interpretation:

- understanding questions and deciding which capabilities to use;
- classifying and extracting transaction messages and notifications;
- choosing useful evidence and follow-up paths;
- turning structured tool results into a concise typed presentation.

Local code is responsible for authority and correctness:

- permission and privacy boundaries;
- schema validation, money units, currency separation, and date boundaries;
- querying, aggregation, deduplication, transactionality, approvals, and undo;
- app authentication and Android platform operations;
- rendering only known, typed presentation components.

There is no regex, keyword, or merchant/category heuristic transaction parser.
Validation may reject malformed AI output but may not infer missing financial
meaning.

## Embedded MCP model

Fund Flow hosts an in-process MCP-style server. It uses MCP concepts—named
tools, JSON Schema inputs, structured content, errors, and capability
discovery—without opening a network port. The provider sees an allowlisted
tool catalog through its native tool-calling API. Tool calls return structured
JSON to the same model conversation.

Every tool declares:

- stable name and description;
- JSON input schema with no permissive unknown fields;
- `read`, `propose`, or `platform` risk class;
- whether authentication, provider connectivity, or Android permission is
  required;
- a result schema and human-readable audit summary.

The execution loop is bounded to 12 tool turns, 50 total tool calls, 100
transactions per result page, and 60 seconds. Repeated identical calls are
detected. The user can stop a run. Timeout, malformed arguments, unsupported
tools, and provider failures become recoverable chat states rather than partial
database changes.

## Capability catalog

### Money reads

- `transactions.search`: dates, direction, currency, merchant, category,
  account, source, review state, amount range, paging, and stable sort.
- `transactions.get`: one normalized transaction plus original-source
  disclosure when explicitly requested.
- `finance.summary`: incoming, outgoing, net, count, and review count grouped
  by currency for a date range.
- `finance.breakdown`: deterministic category, merchant, account, source, day,
  week, or month grouping.
- `finance.compare`: two explicit periods with absolute and percentage deltas;
  percentage is omitted when the baseline is zero.
- `finance.recurring_candidates`: deterministic repeated-merchant evidence;
  the agent interprets it but the tool does not label subscriptions as fact.
- `categories.list`, `sources.status`, and `privacy.boundary`.

### App reads

- `settings.get`: appearance, primary currency, amount privacy, app lock,
  message lookback, capture state, and provider/model state. Credentials are
  never returned.
- `conversation.search`: prior locally stored answers when needed for a
  follow-up.
- `app_update_status`: live read-only status from the verified GitHub
  development channel. Download and installation remain explicit UI actions.

### Proposed mutations

- `transactions.create`, `transactions.update`, `transactions.delete`.
- `transactions.bulk_update_category` with an explicit affected-ID list.
- `settings.update` for appearance, currency, hidden amounts, message lookback,
  and notification capture.
- `security.set_app_lock`, which additionally requires device authentication.
- `conversation.clear`.

Mutation tools do not mutate. They produce a durable proposal containing the
validated before/after values, affected object count, local/cloud boundary,
authentication requirement, reversibility, expiry, and a deterministic
fingerprint. Approval executes the proposal in a SQLite transaction and writes
an undo record. Rejection and expiry are persisted.

## AI-only message ingestion

SMS permission remains an Android/platform concern. After permission:

1. Fund Flow reads messages for the chosen lookback window.
2. Exact message fingerprints are checked locally for previous attempts. This
   is deduplication, not semantic parsing.
3. Unseen messages are sent in bounded batches with opaque IDs, sender, receive
   time, and body. The UI clearly says that all unseen messages in the selected
   window—not locally prefiltered candidates—are sent to the configured
   provider for classification.
4. The ingestion model must return one result for every opaque ID:
   `transaction`, `not_transaction`, or `uncertain`.
5. A transaction result must include integer minor units, ISO currency,
   direction, merchant, category, occurred-at time, optional account/reference,
   confidence, and a short uncertainty note.
6. Local schema validation rejects missing IDs, unknown IDs, floating-point
   money, unsupported currencies/directions, impossible dates, duplicate
   results, or extra transactions.
7. Valid transactions are stored as `needsReview`; uncertain and rejected
   results remain visible in import history and can be retried.
8. Database insertion and attempt recording happen atomically per batch.

Notification capture follows the same AI classification path. Opt-in capture
stores a bounded encrypted-at-rest platform queue. It performs no financial
keyword filtering. The consent copy therefore states that captured notification
text can be sent to the configured provider.

Imports support progress by batch, pause/stop, retry of failed batches, provider
offline/rate-limit states, and idempotent resume. Stopping never discards a
committed batch or acknowledges an uncommitted platform event.

## Agent run protocol

The provider request includes:

- a stable system contract and locale/time-zone/current-time metadata;
- recent conversation parts needed for the current turn;
- the MCP tool catalog;
- no eager transaction dump and no precomputed question context.

The model calls read tools as needed. Fund Flow validates each call and returns
structured results. A proposed mutation ends execution in `approvalRequired`.
A read-only run ends with an `answer.compose` tool call containing the typed
presentation. Free-form provider prose is accepted only as a recoverable plain
text answer marked `Unstructured`; it cannot contain an executable action.

## Typed chat presentation

An assistant turn is persisted as ordered parts rather than one text blob:

- `conclusion`: one direct answer, visually dominant;
- `narrative`: short explanation paragraphs with safe inline emphasis;
- `metricRow`: up to four currency-safe values with labels and period;
- `comparison`: baseline/current values, delta, direction, and caveat;
- `breakdown`: ranked bars or rows with amount, share, and tappable filter;
- `transactionList`: compact supporting transactions with stable local IDs;
- `insight`: observation plus why it matters, never alarmist;
- `sourceNote`: tool names, period, filters, transaction count, and calculation
  boundary;
- `followUps`: two or three context-aware actions that submit a real question;
- `proposal`: embedded summary plus an action opening the approval sheet;
- `warning`: insufficient data, mixed currency, partial import, or uncertainty.

Assistant prose is not placed in a chat bubble. Evidence expands in place.
Transaction rows open the normal inspector. A breakdown row can open Activity
with the corresponding filter. Currency values are never combined. Long
answers progressively disclose details and remain usable at 200% text.

## Conversation and audit persistence

SQLite stores runs, messages, ordered parts, tool calls, sanitized arguments,
results or errors, proposals, approvals, import attempts, and undo records.
Raw API keys remain only in secure storage. Original SMS/notification text is
shown only through explicit disclosure and is not copied into general tool
logs. Tool logs use IDs and normalized fields.

Clearing a conversation removes its messages and tool traces but not financial
activity. A privacy action can independently delete raw source text while
retaining normalized transactions.

## Security rules

- The model cannot provide SQL, table names, filesystem paths, Android intents,
  or arbitrary method names.
- Unknown tool calls and unknown JSON fields are rejected.
- Read tools enforce paging and date limits.
- Mutations re-read affected rows at approval time and reject stale proposals.
- Bulk operations show count and representative objects before approval.
- Settings changes disclose immediate consequences; app lock invokes local
  authentication after approval.
- Tool output is treated as data, never appended to the system prompt as
  instructions.
- Prompt injection inside merchant names, notes, SMS, or notifications cannot
  grant capabilities.

## Required states

Chat supports disconnected, ready, composing, calling a named capability,
stopped, provider offline, rejected credentials, rate limited, malformed model
output, tool validation error, partial evidence, approval pending, stale
approval, applied, rejected, and undone.

Ingestion exposes permission denied/permanently denied, provider disconnected,
reading, analyzing a bounded batch, stopped, rate limited, partial completion,
schema rejection, retry, complete, empty, and all-seen outcomes. Stop takes
effect at the next safe batch boundary so an in-flight provider request cannot
leave a half-committed batch.

## Acceptance gates

- `LocalMessageParser`, `CandidateGate`, regex/keyword transaction inference,
  and eager `_contextFor` prompting do not exist.
- Every semantic SMS/notification decision is attributable to an AI ingestion
  result with model, timestamp, and attempt state.
- Every numeric claim in chat traces to a deterministic local tool result.
- Every mutation has a durable preview, explicit approval, transactional apply,
  and undo or an explicit non-reversible explanation.
- Fake-provider contract tests cover multi-tool loops, malformed calls,
  injection content, pagination, mixed currencies, stop, timeout, and proposal
  staleness.
- Render tests cover every part type, long content, empty evidence, dark mode,
  RTL, 200% text, phone, and tablet.
