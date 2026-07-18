# Fund Flow — Blank-Slate AI-First Rebuild Plan

Status: **LOCKED IMPLEMENTATION PLAN**
Date: 2026-07-18
Working name: **Flow Loom**

This plan supersedes the screen composition and component styling in
`design_system.md`. The existing repository is a capability reference, not a
visual reference. No current screen, widget hierarchy, navigation pattern,
shape, or layout is assumed to survive.

## 1. Why the current direction is rejected

The app remains recognizably a styled Material application because it still
depends visually on these familiar patterns:

- `Scaffold` plus conventional `AppBar` plus bottom navigation;
- rounded container/card stacks;
- `ListTile`, `SwitchListTile`, `FilterChip`, `ChoiceChip`, and segmented
  controls retaining their stock anatomy;
- a search pill followed by grouped list rows;
- generic settings sections;
- chat history represented as vertically stacked response blocks;
- color used as container fill rather than as a meaningful system;
- different features arranged screen-first instead of around one AI task loop.

Changing radius, color, icon, or adding a signal rail does not solve this.
Those are decorations on the same composition.

### Repository demolition baseline

Measured at the start of this plan, the visible code still contains:

- 10 `ListTile` usages;
- 3 `SwitchListTile` usages;
- 4 `SegmentedButton` usages;
- 3 stock chip families used for filters/selection;
- 4 conventional app-bar implementations;
- 8 generic `StatePanel` usages;
- 3 `FlowGlass`/floating-material usages;
- multiple feature widgets whose names and anatomy remain “Card.”

Phase D must reduce each visually dominant baseline to zero. A Material widget
may remain only when wrapped by a replacement component whose rendered anatomy
is entirely Flow Loom.

## 2. Demolition contract

The following visual implementations must be deleted or made visually
unrecognizable:

1. The current three-item rounded bottom navigation and tablet navigation rail.
2. Conventional top app bars as the identity/header of a workspace.
3. Assistant/user bubble or card history.
4. Generic transaction avatar + merchant + subtitle + amount rows.
5. Generic settings cards containing `ListTile` families.
6. Stock chips as primary filtering, status, or appearance controls.
7. Stock segmented control for theme selection.
8. Generic modal-sheet headers and two-button confirmation rows.
9. Generic empty state: icon tile, heading, paragraph, button.
10. Generic loading skeletons, spinners, shimmer, and delayed item reveals.
11. Generic purple primary-container fills used as “brand.”
12. Repeated rounded rectangles without a semantic reason.

Material may remain underneath for semantics, focus, text editing, routing,
safe areas, and platform behavior. It may not determine visible anatomy.

## 3. Product architecture from zero

### Product sentence

Fund Flow is an evidence-bound financial agent that turns transaction messages
into a private money model, answers questions from that model, and performs
approved actions without hiding uncertainty.

### Dominant loop

`Signal arrives → Flow understands → proof is attached → user asks → Flow
computes locally → conclusion is shown → evidence can be inspected → action is
approved → correction improves future understanding.`

Every primary element must serve that loop. Manual CRUD, categories, logs, and
technical configuration remain recovery/control tools.

### Root spaces

There are three conceptual spaces but only one dominant workspace:

- **Flow** — default command canvas. Brief, Ask, composed answers, approvals.
- **Proof** — evidence model. Understood events, source, confidence, review.
- **System** — AI connection, consent, privacy, preferences, diagnostics.

They are not presented as three equal tabs. Flow owns the canvas; Proof and
System open from a persistent **Command Rail**.

## 4. Proprietary visual concept: Flow Loom

Flow Loom visualizes intelligence as threads turning noisy signals into a
trustworthy financial fabric.

### Signature forms

- **The Loom mark** — a compact field of nodes connected by three implied
  vertical threads. It is static at rest. State is expressed through density,
  color, and completed nodes, never perpetual movement.
- **The Proof Thread** — a 2–4dp spectral line connecting conclusion, value,
  provenance, confidence, and action.
- **The Ledger Cut** — evidence surfaces use one clipped/notched corner and one
  aligned edge, not four generic rounded corners.
- **Coordinates** — tiny uppercase labels (`PROOF 04`, `CHECKED LOCALLY`,
  `SOURCE SMS`) anchor content like an instrument, not decoration.
- **Open canvas** — space and rules establish hierarchy. A surface is added
  only for interaction, contrast, or semantic grouping.

### Geometry

- 4dp base grid; 8/12/16/24/32/48 spacing cadence.
- Reading measure: 620dp. Evidence measure: 760dp.
- Interactive surfaces: 12–18dp corners, never automatic pills.
- Ledger cuts: one 0–6dp corner paired with one 28–44dp corner.
- Command Rail: full-width structural bar with three unequal zones; Flow gets
  52% of visual weight, Proof 30%, System 18%.
- Touch targets remain at least 48dp regardless of visible geometry.

### Color

Color is a signal system, not a theme fill:

- **Ink** `#090A0F` — OLED canvas.
- **Paper** `#F7F7F2` — light canvas, slightly warm.
- **Loom Violet** `#5B4BFF` — intelligence and command.
- **Proof Cyan** `#22D3EE` — provenance and verified computation.
- **Mint** `#2ED3A7` — money in and successful verification.
- **Coral** `#FF5F7A` — money out or destructive consequence, context decides.
- **Amber** `#F6B94A` — uncertainty and review.
- Neutral surfaces are ink/paper mixtures, never generic Material seed output.

No screen may be 90% gray plus one purple button. Each primary viewport needs
one deliberate spectral relationship while keeping reading surfaces calm.

### Typography

- Display/result voice: Space Grotesk or another bundled geometric grotesk.
- Reading/control voice: Inter.
- Money: tabular figures, strong baseline alignment, never `FittedBox` unless
  accessibility makes it unavoidable.
- Coordinate labels: 9–11sp, 700–900 weight, 0.8–1.4 tracking.
- Conversational prose: 15–17sp, 1.5–1.6 height.
- No screen title exists merely because an app bar expects one.

### Depth

- Level 0: canvas.
- Level 1: tonal plane separated by a rule or cut edge.
- Level 2: interactive command surface with one restrained shadow.
- Level 3: transient approval/system overlay.
- No elevation on scrolling evidence items.
- No backdrop blur.

### Motion and energy

- No continuous animation, shimmer, live blur, ambient particles, or ticker.
- Loom state changes may use one 160–240ms node-density crossfade.
- New streamed text appears without moving previous content.
- Navigation uses a 180–260ms spatial transition and respects reduced motion.
- Lists mount immediately; no stagger or scroll-entry opacity.
- Static painters live in `RepaintBoundary`.
- Progress is numeric/determinate or expressed as named stages without a
  constantly repainting indicator.

## 5. New shell

### Mobile

- No conventional app bar.
- Each root space begins with an in-canvas masthead: Loom coordinate, current
  state, one contextual control.
- Persistent Command Rail sits above the system inset.
- Flow zone contains Loom mark plus `ASK`; Proof contains evidence count and a
  ledger glyph; System is a compact control port.
- Selection is shown by an illuminated proof thread and typography, not a
  filled rounded selection capsule.

### Tablet

- Command Rail becomes a narrow left instrument column.
- Flow/Proof content uses a centered two-zone layout when useful: conclusion
  and proof, or chronology and inspector.
- It is not a widened phone screen and not a stock `NavigationRail`.

## 6. Flow workspace

### Activation

- One-page activation narrative: private AI connection → message consent →
  first proof.
- Connection is part of Flow, not buried in settings.
- Show exactly what leaves the device before requesting credentials.

### Ready state

- Masthead states: `READY`, `CHECKING`, `NEEDS PROOF`, `OFFLINE`.
- The first viewport contains one useful brief, not a dashboard grid.
- Suggested questions are plain command lines attached to the brief, not chips.
- `Analyze messages` appears as a source command with scope and last check.

### Composer

- The composer is the Command Surface, not a search/text-field pill.
- It states the evidence scope (`ASKING 143 LOCAL EVENTS`).
- Multiline input grows without covering the answer.
- Send/stop are custom cut-corner controls.

### Answer Report

Order:

1. user intent coordinate;
2. one-sentence conclusion;
3. authoritative local result plate;
4. explanation;
5. checked-record count, filters, freshness;
6. expandable evidence;
7. safe next commands;
8. approval when mutation is requested.

No assistant bubble and no generic card surrounding the whole answer.

### Approval

- Describe exact mutation, affected records, reversibility, and data transfer.
- Destructive actions use coral only at the consequence edge.
- Approval language uses the verb and object (`DELETE 3 EVENTS`), never generic
  `Apply` when specificity is available.

## 7. Proof workspace

### Overview

- Evidence health, last analysis, understood count, uncertain count, rejected
  candidate count.
- No decorative dashboard tiles.

### Chronology

- A continuous Proof Thread, not independent cards.
- Each event is a ledger strip: time coordinate, direction, counterparty,
  amount, source, confidence.
- Income/outgoing direction is apparent without relying only on color.
- Manual fallback is visually quieter and marked `MANUAL`.
- Uncertain events interrupt the thread with an amber decision node.

### Search and filter

- Search is an inline evidence command.
- Filters open a dedicated query editor with readable active scope.
- No horizontal chip collection.

### Event inspector

- Source → extraction → normalized event → confidence → corrections.
- Raw SMS stays concealed by default and is never sent or copied accidentally.
- `Confirm`, `Correct`, `Not a transaction`, and `Re-analyze` explain their
  effect on future understanding.

## 8. System workspace

- A system map, not a settings list.
- Four first-level nodes: Intelligence, Sources, Privacy, Personalization.
- Each node shows state and consequence before opening.
- Toggles are custom binary rails with explicit On/Off text.
- Theme is a three-option visual swatch, not a segmented Material control.
- Advanced diagnostics are behind one clearly technical boundary.
- Categories/manual organization are secondary recovery tools.

## 9. Onboarding and SMS ingestion

Stages:

1. **Promise** — transaction messages become private evidence and answers.
2. **AI boundary** — provider, credential storage, transmitted data.
3. **Message boundary** — requested scope, ignored messages, Android consent.
4. **First analysis** — named stages, numeric progress, progressive proof.
5. **Trust handoff** — understood, skipped, uncertain, retryable; open Flow.

There is no celebratory animation loop. Completion is expressed by the Loom
becoming dense and the first verified evidence appearing.

## 10. State inventory

Every primary surface must explicitly implement:

- first run;
- AI disconnected;
- AI connection invalid;
- SMS permission denied permanently;
- no transaction candidates;
- analysis queued/running/paused/stopped;
- partial batch failure;
- successful import with zero events;
- uncertain extraction;
- offline question failure;
- tool failure;
- streaming answer;
- read-only verified answer;
- mutation approval/rejection/success/undo;
- empty Proof;
- filtered-empty Proof;
- privacy-hidden values;
- locked app;
- large text, RTL, tablet, high contrast, reduced motion.

## 11. Component replacement map

| Existing visible pattern | Replacement |
|---|---|
| Bottom navigation pill | Command Rail |
| AppBar/SliverAppBar title | In-canvas Masthead |
| FlowOrb/dotted icon variants | Single Loom Mark |
| Card | Plane / Proof Plate / Command Surface |
| ListTile | Control Node / Ledger Strip |
| Chat bubble | Intent Coordinate / Answer Report |
| Transaction row | Evidence Strip on Proof Thread |
| Chip/filter chip | Query Scope Editor / coordinate token |
| SegmentedButton | Visual Swatch Selector |
| SwitchListTile | Explicit Binary Rail |
| Generic bottom sheet | Inspector / Approval Overlay |
| StatePanel | State Narrative |
| Spinner/shimmer | Static named stage + determinate work |

## 12. Code architecture

Create a new component namespace rather than continuing to inflate old files:

```text
lib/flow_os/
  foundation/
    flow_color.dart
    flow_type.dart
    flow_geometry.dart
    flow_motion.dart
    flow_energy.dart
  primitives/
    loom_mark.dart
    proof_thread.dart
    cut_surface.dart
    coordinate_label.dart
    binary_rail.dart
  shell/
    flow_shell.dart
    command_rail.dart
    flow_masthead.dart
  ask/
    ask_workspace.dart
    command_surface.dart
    answer_report.dart
    result_plate.dart
    approval_overlay.dart
  proof/
    proof_workspace.dart
    evidence_strip.dart
    evidence_query.dart
    event_inspector.dart
  system/
    system_workspace.dart
    system_node.dart
    visual_swatches.dart
  states/
    state_narrative.dart
    analysis_stage.dart
```

Old widgets are deleted after parity, not retained as alternate styling paths.

## 13. Implementation phases and gates

### Phase A — demolition and prototypes

- Screenshot current app and annotate every retained Material pattern.
- Build isolated Loom Mark, Command Rail, Proof Thread, Evidence Strip, Answer
  Report, Control Node.
- Render all prototypes in dark/light, 320dp, and 200% text.

Gate: the prototype sheet must not be mistaken for a standard Material app when
all copy and logos are removed.

### Phase B — shell and Ask

- Replace shell/navigation and Ask completely.
- Implement every Ask state and approval flow.

Gate: Ask is usable without visiting any other workspace; AI/SMS motive is
obvious within five seconds.

### Phase C — Proof and ingestion

- Replace chronology, inspector, search/filter, sync, uncertainty, retry.

Gate: every amount can reveal source, confidence, and correction path within
two actions.

### Phase D — System and secondary tools

- Replace connection/privacy/personalization and diagnostic routes.
- Remove visual `ListTile`, stock chips, and segmented controls.

Gate: no first-party screen visually falls back to a generic settings/list
template.

### Phase E — deletion and validation

- Delete superseded UI and unused tokens.
- Full responsive/accessibility/RTL/high-contrast/reduced-motion audit.
- Profile idle scheduled frames, scroll frame time, rebuild counts, and APK.

Gate: zero known overflow/flash/delayed-render issue; zero continuous decorative
frame scheduling; full tests/analyze/build pass.

## 14. Visual acceptance rubric

Each major viewport is scored 0–2 on:

1. AI motive is immediately obvious.
2. Flow Loom identity is recognizable without logo text.
3. Hierarchy is understandable in five seconds.
4. Evidence and uncertainty are honest.
5. Primary action is unambiguous.
6. No stock Material anatomy is visually dominant.
7. Color has a semantic purpose and sufficient contrast.
8. Layout survives 320dp and 200% text.
9. Idle UI schedules no decorative frames.
10. The screen feels related to every other Flow screen.

No screen ships below 18/20. Any score of 0 blocks the phase.

## 15. Definition of complete

The rebuild is complete only when:

- every state in section 10 is implemented;
- every replacement in section 11 is complete;
- old visual paths are deleted;
- annotated dark/light phone and tablet screenshots pass the rubric;
- tests, analyzer, diff check, and Android build pass;
- idle and fast-scroll energy/performance checks pass;
- the product owner can identify a prominent, coherent Fund Flow design
  language without being told where custom styling was added.
