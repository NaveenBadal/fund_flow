# Fund Flow mobile experience

Fund Flow uses one mobile-first interface: the Zero system in `lib/zero`.
The earlier `ui2` implementation was removed rather than retained as a
compatibility layer.

## Product principles

- Quiet by default: show the current financial picture before controls.
- AI with boundaries: explain exactly what leaves the device and why.
- Automation with evidence: every message decision remains inspectable.
- Progressive disclosure: advanced controls appear only when requested.
- One clear action per state: empty, loading, permission, error, and success.
- Accessible restraint: semantic color, scalable type, large targets, and
  reduced-motion-safe transitions.

## Mobile structure

- **Overview** — month, spend, income, net, briefing, and recent activity.
- **Ask** — conversational analysis grounded in the local ledger.
- **Transactions** — searchable history, review, detail, and manual editing.
- **Settings** — automation, intelligence, privacy, preferences, data, about.
- **Onboarding** — value, privacy model, intelligence choice, and clean start.

## Architecture

- `lib/zero/zero_theme.dart` owns semantic color, typography, and component
  theming.
- `lib/zero/zero_home.dart` owns the primary mobile journey and settings.
- `lib/zero/zero_intelligence.dart` owns provider connection and models.
- `lib/zero/zero_automation.dart` owns message import, notification capture,
  permission recovery, and the complete decision audit.
- `lib/zero/zero_editor.dart` owns transaction creation and editing.
- `lib/domain/category_catalog.dart` owns category vocabulary independently of
  presentation code.

No active or fallback UI depends on `lib/ui2`.

## Completion gates

- `flutter analyze`
- `flutter test`
- Pixel emulator visual and semantic inspection
- 200% text-scale and reduced-motion checks
- Split-per-ABI production release build
- repository search confirming no legacy UI references

