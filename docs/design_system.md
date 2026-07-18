# Fund Flow — AI-First Product and Design System

Status: **LOCKED canonical specification**
Version: 2.0
Locked: 2026-07-18

This document is the source of truth for every product, interaction, content,
and visual decision in Fund Flow. Future sessions must read it before changing
the experience. If implementation and this document disagree, this document
wins unless the product owner explicitly changes the product direction.

Flutter primitives live in `lib/theme/app_tokens.dart` and
`lib/theme/app_theme.dart`. Product behavior belongs here, not only in code.

---

## 1. The non-negotiable product definition

**Fund Flow is an AI-first personal financial agent that turns transaction SMS
into an understandable, queryable, and actionable picture of the user's money.**

It is not a manual expense tracker with an AI tab. It is not a budgeting app
with optional chat. It is not a dashboard that asks users to interpret charts.

The core product loop is:

1. **Connect** — the user securely connects AI and grants SMS access.
2. **Understand** — Flow scans supported financial messages, extracts records,
   resolves duplicates, communicates confidence, and produces an immediate
   financial brief.
3. **Ask and act** — the user talks naturally to Flow. The agent verifies facts
   with local tools, explains evidence, and safely completes approved actions.

Everything else is supporting infrastructure. Activity exists to inspect the
agent's evidence. Insights exist to make the agent proactive. Settings exists
to control trust and sources. Manual creation/editing is a recovery path, never
the promoted product experience.

### Product filter

Before adding or retaining anything, ask:

> Does this help Flow understand the user's money, help the user understand
> Flow's answer, or let the user safely act on that answer?

If not, remove it. If it can be expressed as a conversation or a compact agent
artifact, do not create a separate management screen. Complexity must be earned
by recurring user value.

### Success promise

Within the first useful session, a user should be able to say:

> “Flow understood my transaction messages, told me what matters, and answered
> a real money question with evidence.”

Target first-value experience: under three minutes after an AI connection is
available, excluding operating-system permission and provider sign-in time.

---

## 2. Experience principles

1. **The agent is the interface.** The default surface is a useful conversation,
   not a collection of navigation destinations.
2. **Outcome before configuration.** Explain the result first, request only the
   capability needed next, and show progress immediately.
3. **Proactive, never noisy.** Flow presents a short brief when something
   changed; it does not manufacture alerts or generic financial advice.
4. **Verified before confident.** Every financial claim comes from a local tool,
   a visible source set, or is clearly labelled as an estimate.
5. **Trust is visible in context.** Source, freshness, confidence, processing
   boundary, and correction are available where a decision is made.
6. **Conversation compresses complexity.** Filters, comparisons, recurring
   detection, anomaly checks, and planning should feel like asking—not operating
   finance software.
7. **Actions are reversible.** Sensitive or multi-record changes show an exact
   preview, require approval, and offer Undo where technically possible.
8. **One next best action.** Every state has one dominant action. Secondary
   choices remain visually quiet.
9. **Quiet until useful.** Visual expression belongs to intelligence, progress,
   and meaning; routine data stays restrained.
10. **Permission denial is not failure.** Explain the lost capability and keep a
    respectful recovery route. Never pretend the fallback is the main product.

---

## 3. Product architecture

### Phone navigation

Use three persistent destinations:

| Destination | Role | User question |
| --- | --- | --- |
| **Flow** | Primary and default agent workspace | What should I know or do? |
| **Activity** | Evidence and review ledger | What did Flow understand? |
| **You** | Trust, connections, preferences | What can Flow access and remember? |

Do not create primary tabs for Today, Plan, Analytics, Budgets, or Add. Their
useful outputs become agent briefs and interactive artifacts in Flow. Their
detailed evidence may deep-link into Activity. Settings is renamed **You** in
navigation because it represents the relationship and controls, not a utility
drawer.

Tablet and desktop use the same three destinations in a rail. Flow may use a
conversation/evidence split view. Navigation occupies layout space and never
floats over content.

### Primary hierarchy

1. Flow prompt/composer or current agent task.
2. Latest AI brief, answer, or review request.
3. Suggested questions based on actual available data.
4. Sync freshness and compact source status.
5. History and supporting controls.

The manual add action is never a global FAB. It lives in Activity's overflow or
an agent suggestion such as “Add a cash transaction.” Manual editing remains in
transaction detail and agent-confirmed actions.

---

## 4. The Flow workspace

Flow is both home and agent. It must feel immediately alive without resembling
a generic chatbot.

### Header

- Product mark and the name **Flow**.
- One compact intelligence state: `Ready`, `Syncing`, `Needs review`, `Offline`,
  or `Connect AI`.
- Avatar opens You.
- Do not use a large static app-bar title that consumes conversation space.

### Agent brief

When no conversation is active, show a living financial brief derived from
verified data. It contains at most:

- one plain-language headline;
- two or three evidence-backed signals;
- freshness/source note;
- one recommended follow-up.

Examples: “Dining drove most of this week's increase”; “Two similar debits need
review”; “Your latest bank message was understood 12 minutes ago.” Never show a
made-up health score. Never call ordinary spending “bad.”

If no data exists, the brief becomes the SMS connection/import flow. If a sync
is incomplete, it becomes progress. If ambiguity exists, it becomes a review
queue. The home surface always reflects the most valuable current agent state.

### Conversation

- User and agent messages are visually distinct but compact.
- Agent answers lead with a direct answer, then evidence, then an optional
  action. Avoid greetings after the first session.
- Stream meaningful text while tools run; show a concise live activity label
  such as `Checking 84 transactions` rather than developer tool names.
- Preserve conversation history locally.
- Long answers use progressive disclosure, not walls of Markdown.
- Tables are replaced with native artifacts: ranked lists, comparison cards,
  timelines, or transaction groups.

### Composer

- Anchored above keyboard and system insets.
- Large enough for two lines by default; expands to a sensible maximum.
- Placeholder adapts: `Ask about your money`, `Reply to approve`, or
  `Correct what Flow misunderstood`.
- Send is the only persistent trailing action.
- Stop replaces Send during generation.
- Voice or attachment controls are not added without complete functionality.

### Suggested prompts

Suggestions are contextual, not generic. Generate them deterministically from
available capability and data state:

- New data: “What changed this week?”
- Sufficient history: “Where am I spending more than usual?”
- Recurring records: “Show my recurring payments.”
- Ambiguity: “Help me review uncertain transactions.”
- No SMS data: “Import my transaction messages.”

Use no more than four, and never place a horizontal chip maze above the primary
action.

### Agent artifacts

Native artifacts are the bridge between conversation and trustworthy finance.
Required artifact families:

- Transaction group
- Period comparison
- Category breakdown
- Recurring payment set
- Anomaly/review item
- Cash-flow or spending outlook
- Change preview and result

Every artifact states its date range and currency, has an accessible prose
summary, and opens the exact supporting records. Charts are optional; the
takeaway is mandatory.

---

## 5. SMS intelligence system

SMS understanding is the primary data acquisition experience and must feel like
an agent task, not a settings operation.

### Import sequence

1. Explain why: Flow reads supported transaction messages to build the user's
   private financial picture.
2. Explain boundary immediately before consent: selected message text is sent
   to the configured AI endpoint for extraction; structured records and source
   provenance are stored locally.
3. Request Android SMS permission.
4. Scan locally for likely financial messages within the selected range.
5. Show bounded progress: discovered, analyzing, understood, skipped, needs
   review. Allow safe cancellation and background/resume.
6. Present an import result brief, not merely a success toast.
7. Route uncertain or duplicate records into review.

Never request SMS permission before explaining value and processing. Never
claim the entire inbox is uploaded. Never expose raw message text in ordinary
agent responses. Re-analysis of original text requires explicit intent and a
confirmation boundary.

### Confidence and review

- High confidence imports silently and remains inspectable.
- Medium confidence imports with a visible `Check` status when a meaningful
  field is uncertain.
- Low confidence is proposed, not committed, until reviewed.
- Duplicate detection explains the matching basis.
- Correction improves the record; future learning may only be claimed when a
  real mechanism exists.

Review uses one decision per screen/sheet: show the extracted result, minimum
source context, uncertainty, and `Confirm` / `Correct` / `Not a transaction`.

### Freshness

The user sees human time (`Updated 12 min ago`) and source (`Bank SMS`). Sync is
available from Flow's state/brief and pull-to-refresh where natural. It is not a
prominent permanent button after automation is healthy.

Notification capture may supplement future transactions, but it must not rival
SMS import in onboarding. Offer it later as an optional continuity enhancement.

---

## 6. Onboarding and first value

Onboarding is a guided activation of the agent, not a carousel and not a source
preference survey.

### Stage 1 — Promise

One screen. Show the transformation:

**Your transaction messages, understood.**
Flow turns bank SMS into answers about where your money went, what changed, and
what deserves attention.

Primary action: `Set up Flow`.

### Stage 2 — Connect intelligence

Connect the supported AI provider inside onboarding. Explain that the credential
is stored securely on device, show endpoint/model only under Advanced, validate
the connection, and show a clear success state.

Do not send users to Settings. Do not complete onboarding without explaining
that core AI analysis is unavailable. `Continue without AI` may exist as a quiet
escape for evaluation/accessibility, with explicit reduced-capability copy; it
must never be selected by default or described as the full experience.

### Stage 3 — Connect transaction SMS

Explain value and privacy in plain language, then request permission. Primary
action: `Allow and analyze`. A quiet `Not now` route remains available and lands
in the same guided connection state in Flow.

### Stage 4 — First analysis

Run the first import in place. Show real stages and partial counts. On success,
show the first three useful findings or review needs. Primary action:
`Ask Flow` / `See my brief`.

Currency is inferred from understood records when reliable. Ask only if mixed
or unknown. Planning inputs, categories, app lock, notifications, themes, and
manual entry do not belong in onboarding.

Returning users resume the incomplete activation stage. Permission or provider
failure always explains how to recover.

---

## 7. Activity: evidence, not the product

Activity is the trustworthy record of what Flow understood.

- Default grouping is chronological with a clear date and daily total.
- Search accepts merchant/description; advanced filters remain behind one
  filter control.
- Rows show description, category/account context when useful, signed amount,
  and time. Source/confidence appears only when it needs attention.
- Tapping opens provenance, original source (privacy protected), AI confidence,
  duplicate relation, correction history, and actions.
- A compact review filter surfaces uncertain records.
- Manual add is in overflow and described as a cash/fallback action.
- Do not place dashboard heroes, planning forms, or decorative charts here.

Empty Activity does not promote manual entry. It says `Connect transaction SMS`
and returns to the Flow activation task.

---

## 8. Insights, planning, and proactive intelligence

There is no standalone Plan destination in the core architecture. Flow answers
planning questions and renders outlook artifacts when data supports them.

Deterministic calculations may support answers, but the experience remains
agent-led. A safe-to-spend estimate must state inputs, horizon, missing sources,
and uncertainty. It must never imply access to bank balances the app does not
have.

Budgets, commitments, and preferences are created conversationally or through a
focused artifact/sheet only when needed. Do not require setup before users see
value. Remove planning UI that asks the user to maintain a second financial
system without improving agent answers.

Proactive signals require one of:

- statistically meaningful change;
- likely duplicate or anomaly;
- upcoming recurring payment;
- user-defined threshold or remembered preference;
- stale or broken data connection.

Each signal includes evidence and a dismissible next action. No generic tips,
gamification, guilt, streaks, or fabricated urgency.

---

## 9. You: trust and control

Organize this destination by user intent:

1. **Flow intelligence** — AI connection status, provider, model, reconnect.
2. **Transaction sources** — SMS permission, history range, last sync;
   notification capture as optional enhancement.
3. **Privacy and safety** — what is sent, local storage, app lock, data export
   if implemented, delete conversation/data with exact scope.
4. **Personalization** — currency override, remembered preferences, theme.
5. **Advanced** — category library, audit logs, AI diagnostics, developer
   updates. Hide the section by default for ordinary users.

Avoid nested settings cards inside cards. Use clear section headers, rows, and
status text. Dangerous actions are isolated at the end and require confirmation.

---

## 10. Visual identity — Quiet Intelligence

The visual system is called **Quiet Intelligence**: a premium, editorial
financial canvas with a single luminous AI signal. It combines Pixel-level
expressive motion and geometry with native iOS spatial discipline, but does not
imitate either platform.

### Personality

- Calm, incisive, private, capable.
- Warm enough to converse; restrained enough to trust with money.
- AI is expressed as responsive light, state, and motion—not robot icons,
  sparkles on every surface, or sci-fi gradients.

### Color roles

Structural colors come from the Material `ColorScheme`, but brand-critical
roles must remain stable across dynamic color:

- **Flow signal**: deep electric indigo/violet for intelligence, focus, and the
  primary action.
- **Canvas**: near-white mineral in light mode; near-black ink in dark mode.
- **Surface**: subtle neutral tonal steps, not floating white cards everywhere.
- **Income**: teal; **expense**: warm rose; **review**: amber.
- **Error** is reserved for actual failure or destructive consequence.

Color never carries meaning alone. Avoid saturated finance colors on large
areas. Gradients are reserved for the active agent state or one brief surface,
never routine containers.

### Typography

- Inter: body, controls, labels, long-form answers.
- Space Grotesk: Flow identity, concise editorial headings, important values.
- Financial values use tabular figures.
- Use sentence case everywhere.
- Prefer 2–3 clear levels per screen. Do not make multiple numbers compete.

### Spacing

Use a 4-point base: 4 micro, 8 related, 12 compact, 16 component, 20 phone
gutter, 24 section, 32 region, 48 narrative break. Maximum reading/conversation
width is 720 logical pixels. Dense ledger content may reach 960 on split views.

### Shape

- Controls: 14–18 radius.
- Content surfaces: 20–24 radius.
- Agent brief / singular hero: 28–32 radius with one consistent signature
  asymmetry.
- Pills: status and compact filters only.

Do not randomize corners by list index. Avoid excessive nested rounding.

### Elevation and material

Pages are level 0; grouped tonal surfaces level 1; active composer/context level
2; sheets/dialogs level 3. Prefer tonal separation and hairlines to shadows.
Blur and glass are not structural materials. The composer may use a restrained
elevated surface when it improves keyboard separation.

### Iconography

Use rounded platform-consistent symbols with a single optical weight. `Flow`
uses a distinctive wave/orbit mark, not generic `auto_awesome`. Icons support
labels; primary navigation always has labels. Avoid decorative icons in every
settings row.

---

## 11. Core components

Implementation should converge on these shared primitives:

- `FlowScaffold` — adaptive safe area, content width, rail/nav integration.
- `FlowMark` — product/agent identity and live intelligence state.
- `AgentStatePill` — concise connected/syncing/review/offline status.
- `AgentBrief` — headline, signals, evidence/freshness, next action.
- `FlowComposer` — text input, send/stop, keyboard and accessibility behavior.
- `AgentActivity` — human-readable tool/progress feedback.
- `AgentArtifactCard` — common artifact frame and evidence affordance.
- `SourceDisclosure` — data range, currency, records checked, provenance.
- `ReviewCard` — one ambiguity and its corrective actions.
- `TransactionRow` — compact evidence record.
- `StatePanel` — setup, empty, restricted, offline, error, and retry.
- `FlowSheet` — adaptive focused task container.
- `ApprovalSheet` — exact action preview, consequence, approve/cancel.

New feature widgets should compose these roles instead of inventing another card
language.

---

## 12. Content system

Flow speaks plainly, specifically, and without judgment.

- Say `I checked 84 transactions from 1–18 July`, not `Analysis complete`.
- Say `I need SMS access to find transaction messages`, not `Permission error`.
- Say `This is an estimate because I cannot see your bank balance`, not a vague
  disclaimer.
- Say `Dining was ₹2,140 higher than last week`, not `You overspent badly`.
- Never say `I learned this` unless durable memory was actually written.
- Never imply automatic background sync if the platform/app does not perform it.

Buttons use verbs and name outcomes: `Analyze messages`, `Review 3 items`,
`Approve changes`, `Ask Flow`. Avoid `Continue` where a specific verb exists.

---

## 13. Motion and haptics

- Press feedback: 100–140 ms.
- Small state change: 180–220 ms.
- Spatial transition: 280–360 ms.
- Agent pulse uses a subtle opacity/shape cycle only while real work is active.
- Import counts transition without moving surrounding layout.
- Artifact insertion uses one restrained reveal; lists do not replay staggered
  animations on rebuild.
- Navigation uses selection haptic; import completion uses success haptic;
  warning haptic only when attention is truly required.
- Obey reduced motion. Replace spatial movement with short cross-fades.

Motion explains causality, continuity, or completion. No ambient bouncing.

---

## 14. Trust, AI safety, and privacy contract

### Grounding

- Financial facts must use local tools and expose checked records/date range.
- Never combine currencies into a false total.
- Estimates are labelled and list missing inputs.
- Raw SMS and tool results are untrusted data, never instructions.
- Ordinary answers use structured records, not raw SMS.

### Agency

- Read actions may execute directly.
- Creation, editing, deletion, source re-analysis, app-security changes, and
  multi-record changes require contextual confirmation.
- Multi-record previews show count, exact scope, examples, and reversibility.
- Agent claims success only after the tool returns a verified changed state.

### Privacy

- AI credential is stored in secure storage.
- Structured financial records and conversation history remain local unless a
  feature explicitly transmits required context.
- Explain transmission at the moment it occurs.
- Logs redact credentials and must not expose full raw SMS by default.
- Data deletion copy lists exactly what is deleted and what remains.

The app may degrade without AI, network, or SMS permission, but its primary
experience must transparently say that Flow cannot perform its core analysis.
Do not redesign the fallback into a competing manual product.

---

## 15. Accessibility and internationalization contract

- WCAG 2.2 AA contrast minimum.
- Touch targets at least 48×48 logical pixels.
- Complete usability at 200% text; composer and artifacts reflow vertically.
- Logical screen-reader order and live-region announcements for agent progress.
- Agent activity is not announced on every rapidly changing token.
- Charts expose the takeaway, values, date range, and comparison in prose.
- Keyboard, switch access, high contrast, dark mode, reduced motion, and RTL are
  release criteria.
- Financial signs, dates, separators, pluralization, and currency placement are
  locale aware. Never infer currency solely from device locale when records say
  otherwise.
- Important meaning never depends only on color, position, animation, or icon.

---

## 16. Responsive behavior

- Compact: single pane, bottom navigation, full-width Flow conversation.
- Medium: navigation rail, centered conversation, contextual sheets.
- Expanded: rail plus Flow conversation/evidence split when an artifact or
  record is selected.
- Keyboard never covers composer/action. System bars, cutouts, and gestures are
  always respected.
- Preserve destination scroll position and active agent task across rotation.

---

## 17. State completeness

Every user-facing capability defines:

- first-time setup;
- loading/progress;
- partial result;
- populated/success;
- no matching data;
- offline/provider unavailable;
- permission restricted/permanently denied;
- uncertain/review required;
- cancellation and resume;
- error and safe retry;
- large text, RTL, dark mode, and reduced motion.

Errors answer four things: what happened, what remains safe, what the user can
do now, and whether retry may duplicate work.

---

## 18. Performance contract

- Render the first frame without nonessential plugin/network blocking.
- Keep primary destinations mounted and preserve conversation state.
- No database query inside a list row build.
- Import uses a bounded queue, incremental persistence, cancellation, resume,
  and idempotent duplicate protection.
- Do not refresh the full ledger after every parsed message.
- Stream model output without rebuilding the entire conversation.
- Expensive artifact/chart work occurs only when visible and data changed.
- Use selectors for high-frequency sync/token state and repaint boundaries for
  complex visuals.

---

## 19. Analytics and quality signals

Measure product usefulness without collecting sensitive financial content:

- onboarding stage completion and recovery;
- time to first understood transaction;
- time to first verified answer;
- import success/skipped/review counts (aggregate only);
- suggested-prompt use;
- answer follow-up, correction, and failed-tool rates;
- confirmation accept/cancel rate by action type;
- permission/provider failure stage;
- crash-free sessions and interaction latency.

Never log prompts, raw SMS, merchant text, amounts, credentials, or answer bodies
to analytics by default.

---

## 20. Locked implementation roadmap

### Phase 0 — Product correction

- Replace the previous manual-first design specification with this document.
- Remove Today and Plan from primary navigation.
- Make Flow the first/default destination; add You as the third.
- Reframe retained planning code as internal agent capability.

### Phase 1 — Shared Quiet Intelligence system

- Align theme/tokens with stable Flow roles and restrained expressive geometry.
- Build shared Flow mark, state, scaffold, state panel, brief, composer, artifact,
  disclosure, review, and approval primitives.
- Remove conflicting premium/experimental component languages.

### Phase 2 — AI-first activation

- Rebuild onboarding as Promise → Connect AI → Connect SMS → First analysis.
- Validate provider credentials in place.
- Run/resume first SMS analysis with useful progress and result brief.
- Persist activation stage and provide accurate denied/offline recovery.

### Phase 3 — Flow home and agent

- Rebuild Ask Flow into the default agent workspace.
- Add source/intelligence status, proactive brief, contextual prompts, streaming
  activity, native artifacts, evidence links, and durable conversation.
- Make sync, review, and reconnect first-class agent tasks.

### Phase 4 — SMS understanding and review

- Consolidate disclosure and sync logic into one reusable experience.
- Add bounded scan/analyze progress, cancellation/resume, result summary,
  confidence routing, duplicate explanation, and ambiguity review.
- Ensure original SMS is protected and re-analysis explicitly approved.

### Phase 5 — Evidence and control

- Reduce Activity to ledger, review, search, provenance, and correction.
- Move manual creation to overflow/fallback and remove its global prominence.
- Rebuild Settings as You with intelligence, sources, privacy, personalization,
  and collapsed Advanced sections.

### Phase 6 — Agent-led insight and action

- Convert useful Today/Plan calculations into brief and artifact providers.
- Expose recurring, anomaly, comparison, outlook, budget, and commitment work
  through conversation and focused artifacts.
- Remove standalone UI and data-maintenance flows that do not improve answers.

### Phase 7 — Finish and validation

- Complete every state in section 17.
- Validate compact/expanded layouts, 200% text, dark mode, RTL, keyboard,
  reduced motion, and screen readers.
- Run static analysis and full automated tests; add agent/SMS/onboarding/widget
  coverage for all critical paths.
- Inspect representative screens on a real emulator/device and fix visual or
  interaction regressions before declaring completion.

---

## 21. Definition of done

The redesign is complete only when:

1. A new user understands that Flow is an AI financial agent before any
   permission request.
2. AI connection and SMS analysis are the primary onboarding path.
3. Flow is the default destination and can initiate/recover sync.
4. The first import ends in a useful brief or review task.
5. Every financial answer is grounded, evidence-linked, currency-safe, and
   honest about uncertainty.
6. Sensitive actions preview scope, require approval, and report verified
   results.
7. Activity supports evidence and correction without becoming the home screen.
8. Manual tracking and standalone planning no longer compete with the agent.
9. The visual and component system is consistent across every state.
10. Accessibility, privacy, performance, tests, and visual inspection meet the
    contracts above.

No phase is complete because a screen merely exists. It is complete when the
end-to-end user outcome works, including failure and recovery.
