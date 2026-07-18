# Fund Flow greenfield rebuild

This document is the implementation contract for the unreleased application.
No code, schema, component, navigation structure, or copy from versions before
this document is an implementation reference.

## Product

Fund Flow is a private money companion that turns supported transaction
messages into a trustworthy local activity record, then lets a person ask
questions and approve suggested corrections in ordinary language.

The primary loop is:

`allow a source → understand activity → notice what matters → ask → inspect
supporting transactions → approve a change when needed`

AI is a capability, not a visual theme. The interface earns trust through
useful conclusions, clear boundaries, visible sources, and reversible actions.

## Root journeys

### Ask

- Opens first after onboarding.
- Disconnected: one explanation and one connection action.
- Empty: one monthly orientation and up to three relevant questions.
- Conversation: user question, concise answer, calculation note, expandable
  supporting activity, and contextual follow-ups.
- Work: a static named stage and Stop action; never decorative animation.
- Mutation: a plain-language approval sheet naming affected objects,
  reversibility, and device/cloud boundary.

### Activity

- Month total and review count are a single quiet summary.
- Search is immediately available; advanced filters live in one sheet.
- Transactions are grouped by day and use a stable merchant/amount baseline.
- The inspector reveals normalized fields before original message text.
- Editing and manual entry use the same transaction editor.

### You

- Sections: Intelligence, Money sources, Privacy, Preferences, Advanced.
- Every row includes a current state or consequence.
- Provider endpoint/model, raw import history, and request logs remain behind
  Advanced disclosure.

### Onboarding

- Welcome: product value, no feature list.
- Intelligence: what the provider receives and how the key is stored.
- Messages: exact permission and candidate-only transfer boundary.
- Ready: imported, skipped, and review counts with one next action.

## State inventory

The new implementation explicitly supports:

- new installation and interrupted onboarding;
- intelligence disconnected, validating, connected, rejected, rate-limited,
  offline, and malformed response;
- SMS permission undecided, denied, permanently denied, granted, empty,
  importing, paused, cancelled, partially failed, and complete;
- no transactions, populated activity, filtered empty, needs review, private
  amounts, manual transaction, corrected transaction, and deletion;
- Ask empty, streaming, stopped, failed, verified read-only answer, unsupported
  request, approval pending, rejected, applied, and undo;
- loading, empty, error, and recovery for every asynchronous destination;
- light, dark, high contrast, reduced motion, RTL, 200% text, narrow phone,
  standard phone, and tablet.

## Visual language: Current

Current is an editorial financial interface, not a themed Material skin.

- Warm paper and deep ink canvases.
- Desaturated river blue for intelligence and selection.
- Moss for money in/success, clay for money out/destruction, ochre for review.
- Space Grotesk only for financial values and conclusions; Inter elsewhere.
- A paired horizontal line is the sole identity mark.
- Open space is the default container. A surface exists only for grouped
  content, input, selection, or a consequence.
- No gradients, glass, glow, cut corners, neon, timelines, node grids,
  coordinate labels, uppercase telemetry, dashboard tile grids, or AI sparkles.

## Component anatomy

Every live component is implemented once under `lib/ui/`.

### CurrentButton

- One continuous rounded shape: 16dp radius, never square.
- Heights: 48 compact, 56 standard.
- Variants: filled, tonal, outline, text, destructive.
- Disabled state changes fill/content contrast but never introduces an inner
  rectangle.
- Loading replaces the leading icon with a static named label; no spinner.

### CurrentField

- Exactly one rounded 16dp container including prefix, input, suffix, helper,
  and error.
- Inner `TextField` is always transparent with no independent border/fill.
- Disabled state changes the single outer surface.
- Multiline composer and single-line form field share focus/error grammar.

### CurrentRow

- Optional 3dp semantic line, title, detail, and one trailing control.
- Rows within a section share one grouped surface and dividers; they are not
  independent cards.
- A row is at least 60dp and remains usable at 200% text.

### CurrentSheet

- Rounded 28dp top corners, 36dp drag mark, title, explanation, scrollable
  content, and bottom actions.
- One primary action. Destructive confirmation names the verb and object.

### TransactionRow

- Merchant and signed amount dominate.
- Category, account, source, and confidence are secondary.
- Review uses an ochre line plus the words `Needs review`.

### Answer

- No chat bubble around assistant prose.
- Conclusion, explanation, calculation/source note, supporting rows, actions.
- User questions use a quiet tonal plane with the same 18/16 asymmetric
  radius used throughout the product.

### Navigation

- Three equal destinations: Ask, Activity, You.
- Phone uses a bounded bottom bar; tablet uses a left column.
- Selection is a paired current line and weight change, never a filled pill.

## Architecture

```text
lib/
  app/          bootstrap, routing shell, app state
  domain/       immutable entities, value objects, finance rules
  data/         schema, repositories, secure preferences
  intelligence/provider client, prompts, validated tool loop
  ingestion/    SMS candidate gate, parsing queue, duplicate policy
  features/     onboarding, ask, activity, you
  ui/           tokens, theme, primitives, components, responsive layout
```

Dependencies flow inward. Features can depend on application interfaces and
domain types. Domain code imports no Flutter, database, network, or plugin API.

## Data and AI boundaries

- SQLite stores normalized transactions, sources, conversations, approvals,
  categories, preferences, import attempts, and undo records.
- Secure storage contains only credentials and privacy/security preferences.
- Candidate filtering happens locally before provider transfer.
- The provider never receives arbitrary SQL access.
- Financial arithmetic and mutation validation are deterministic local code.
- Currency totals are never implicitly combined.
- Every mutation requires a preview and explicit approval.

## Acceptance gates

- No imports from or files under the previous `flow_os`, `models`, `providers`,
  `services`, `theme`, or `widgets` namespaces.
- No `BeveledRectangleBorder`, `BorderRadius.zero`, filled inner `TextField`,
  stock `Card`, `ListTile`, `NavigationBar`, `NavigationRail`, `FilterChip`,
  `ChoiceChip`, or `SegmentedButton` in live UI.
- Static analysis, unit/widget/integration tests, both Android flavors, and
  profile build pass.
- Rendered audits cover every inventory state on phone and representative
  states in dark, 200% text, RTL, high contrast, reduced motion, and tablet.
- No overflow, uncaught exception, idle scheduled frame, or ambiguous action.
