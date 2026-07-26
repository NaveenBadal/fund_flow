# Interface rebuild — plan and state

Living document. Update the phase table as phases land.

## Ground-zero refinement — July 2026

The second visual pass replaces the earlier destination model and bright
fintech treatment with a quieter AI-first product:

- permanent destinations are **Home · Activity · Ask**
- Review is contextual work, opened only when transactions need attention
- Analytics, Review, Settings and transaction detail are full routes
- the palette is mineral and low-saturation in light and dark modes
- headings use sentence case; amount typography stays tabular and precise
- phone navigation is a compact dock; wide layouts use a restrained rail and
  a bounded 900px reading measure
- AI answers remain native financial documents rather than chat decoration

The shipped-size pass removed unused direct dependencies
(`riverpod_annotation`, `local_auth_android`, `build_runner`) and the unused
Space Grotesk asset. Android release builds retain code shrinking, resource
shrinking and Material icon tree shaking. The measured arm64 production APK
is 21,264,993 bytes; most of it is the Flutter/native runtime.

## Why

Fund Flow is AI-first: the person never enters data, so the interface exists
to make the model's work **legible, verifiable and correctable**. That is the
thesis every decision follows from.

Jobs, by frequency:

| Job | Frequency | Question |
|---|---|---|
| Position | daily, seconds | Where do I stand? |
| Trust | continuous | Is it catching everything, and is it right? |
| Correct | periodic, bulk | Fix what it got wrong |
| Explore | occasional | Why? What changed? |

Chat is excellent at the fourth and poor at the first three. An earlier build
made conversation the home surface, which optimised for the least frequent
job. That is what this rebuild reverses.

## Architecture

**Chat is an omnipresent input surface, not a destination.** A composer sits
on every screen and carries the context of what is behind it. Home is your
money.

Destinations: **Today · Activity · Review**. Settings is a sheet, not a tab —
it is opened a handful of times ever and a permanent slot would cost a
quarter of the bar.

## Scope

Rebuild the interface. **Keep the engine.**

Kept, because it is verified and load-bearing:

- `lib/data/` — schema, migrations (currently v6), audit trail
- `lib/agent/` — runner, MCP server, proposals, evidence grounding
- `lib/ingestion/` — amount cross-check, OTP double-count guard
- `lib/intelligence/` — provider client, reasoning budget tuning

Rebuilt:

- `lib/ui2/**` — the new design system and screens
- `lib/ui/**` — **legacy**, delete once phases 4–7 land
- `lib/features/**` — legacy screens, replaced phase by phase

## Phases

| # | Phase | State |
|---|---|---|
| 0 | Design system — palette, type, elevation, radius, motion | done |
| 1 | Shell + omnipresent composer | done |
| 2 | Today — position first | done |
| 3 | Review flow — clearing the backlog | done |
| 4 | Activity — dense, groupable, filterable ledger | done |
| 5 | Rich chat — charts, tables, interactive cards, deep links | done |
| 6 | Transaction detail as a route | done |
| 7 | Settings, reorganised by intent | done |
| 8 | Motion | done |
| 8b | Legacy surfaces rebuilt in ui2, `lib/ui` + `lib/features` deleted | done |
| 9 | Verification sweep | done |

### Phase 4 — Activity

Replaces `features/activity/activity_screen.dart` in
`ui2/screens/flow_home.dart`. Dense rows (`FlowDensity.compactRow`), group by
day / category / merchant, date range, filters, bulk select, sort. The old
screen showed about five rows per screen against a ledger of hundreds.

Landed as `ui2/screens/activity_screen.dart`. Rows open the legacy editor
sheet until phase 6 lands the detail route. One defect found on screen and
fixed: the header summary wrapped between a sign and its figure, leaving a
bare `+` at a line end — amounts now carry U+2060 after the sign.

### Phase 5 — Rich chat

The largest phase. **Needs the router from phase 6 first**, because
chat → transaction → back is the requirement current navigation cannot serve.

- bar / line / donut / comparison charts drawn from `ui2/charts/`
- tables for multi-column results
- transaction cards that route to the transaction on tap
- inline actions (recategorise, flag) from inside an answer
- progressive part-by-part streaming
- follow-up chips

Answer parts are already typed — see `agent/agent_presentation.dart`. The
contract the model is given lives in `agent/agent_runner.dart`
(`_systemContract`).

Landed as `ui2/screens/chat_screen.dart` + `ui2/chat/flow_answer_view.dart`,
with `FlowCompareBars` and `FlowDonut` added to `ui2/charts/`. The donut is
guarded mechanically (2–5 segments, real shares, top two ≥ 8 points apart)
because bars beat donuts for close values; comparisons draw as emphasis —
current in accent, previous in gray — never two categorical hues. Evidence
rows route to the transaction detail and back (verified on the emulator with
a synthetic thread seeded into the db), and carry a ⋮ menu for recategorise
and flag/confirm. Part-by-part streaming is visual: the agent delivers parts
in one compose call, so arrival is a staggered entrance (`FlowMotion.stagger`)
on the newest answer only, not a protocol change. Line charts stay
`FlowSpark` — no answer part carries a time series, and the agent contract
is frozen with the engine.

### Phase 6 — Transaction detail

A route, not a sheet. Source message, what was extracted and why, confidence,
edit history, similar transactions. This is where trust is won or lost.

Landed as `ui2/screens/transaction_detail_screen.dart`, opened via
`TransactionDetailScreen.open(context, id)` on the root navigator — which is
what lets chat push it over the sheet and pop back. Activity rows and Today's
captures link into it. Edit history was dropped from scope: the kept engine
records an import audit but no per-transaction edit log, and `lib/data` is
frozen. Two things found by looking: the review callout claimed the model
"was not sure" beside a 96% confidence row (reworded neutrally — review has
non-confidence triggers), and a category outside the standard vocabulary was
invisible because no chip carried it (the record's own category now leads
the chip row).

### Phase 7 — Settings

Landed as `ui2/screens/settings_screen.dart`, grouped by intent: reading
your money, the intelligence behind it, who sees what, how it looks, this
app. Destructive rows (clear conversations, disconnect) now confirm — the
old screen cleared on a single tap. The three legacy sub-sheets (connect,
message intelligence, updates) are reused as-is; restyling them rides with
the `lib/ui` deletion.

### Phase 8 — Motion

Landed as `ui2/motion/flow_motion_widgets.dart`, four named moments built on
the `FlowMotion` tokens, all collapsing under reduced motion:

- `FlowIndexFade` wraps the shell's `IndexedStack` — destinations fade in on
  switch without losing scroll position.
- `FlowCardAdvance` on the review card — a confirm visibly consumes the card
  rather than rewriting it in place.
- `FlowPageRoute` for the transaction detail entrance — fade with a slight
  rise instead of the stock side slide.
- `FlowAnimatedCount` ticks counts over (review "N left", "N done", nav
  badge, side-rail label).

Verified on the emulator: confirm advanced Zomato → Amazon with 14→13
everywhere the count appears.

### Phase 8b — No legacy anywhere

Decision: **every** legacy surface is redesigned in ui2 — nothing from
`lib/ui` or `lib/features` survives, not even restyled. Order:

1. Move `ui/format/money_format.dart` → `ui2/format/money_format.dart`.
2. Rebuild `transaction_editor_sheet` as a ui2 sheet.
3. Rebuild the three settings sub-sheets (connect intelligence, message
   intelligence, updates) in ui2 style.
4. Rebuild onboarding (`app_experience.dart` also leans on current_mark /
   current_button / current_colors).
5. Delete `lib/ui` and `lib/features`; `flutter analyze` after each slice.

Runs before the verification sweep so the sweep covers the new surfaces.

Landed: `lib/ui` and `lib/features` are gone. money_format lives at
`ui2/format/`; the editor, connect, message-intelligence and update sheets
live in `ui2/sheets/` (same class names, ui2 style, category as chips in
the editor instead of free text); onboarding is `ui2/screens/
onboarding_screen.dart` with the mark ported to `ui2/components/flow_mark.
dart`; `app_experience.dart` (loading, locked) restyled on flow tokens.
New shared input: `ui2/components/flow_field.dart`. All verified by
screenshot on the emulator, including a full onboarding pass after
`pm clear`.

### Phase 9 — Verification sweep

Every screen × {light, dark} × {100%, 200% text} × {phone, tablet}.

Never verified visually to date: tablet side rail, 200% text on populated
screens, the connected state of the composer.

Swept on the emulator: phone light/dark at 100%, phone light at 200%
(Today, Activity, Review, detail, settings), tablet 2560×1600 light/dark
(side rail, Today, Activity, Review, chat sheet). One defect found and
fixed: the provenance label column on the detail screen was a fixed 92px,
which broke "Confidence" mid-word at 200% — it now scales by the
multiplier taken at the label's own font size, because Android's
nonlinear text scaling flattens for large values and `scale(92)` itself
barely grows. Still unverified: the composer's connected/busy visual —
it requires a live provider connection, whose key lives in secure
storage and cannot be seeded from the db.

## How to verify — this matters more than it sounds

**Every defect found in the previous session came from looking at a rendered
screen. None came from reading code, and none from tests passing.** Six of
them, three self-inflicted:

- rupee grouping showing `185,000` instead of `1,85,000`
- a modal keeping a stale background across a theme change
- rows sliced mid-glyph at scroll edges
- a currency regression printing `INR36,549.93` (self-inflicted)
- a hero strip putting three copies of one total on screen (self-inflicted)
- category chips stacking one per row (self-inflicted)

So: **build, install, screenshot, read the screenshot** before calling a phase
done. Analyzer and tests are necessary and nowhere near sufficient.

### Emulator loop

```bash
flutter build apk --debug --flavor development      # --flavor is required
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-development-debug.apk
adb -s emulator-5554 shell "run-as com.naveen.fund_flow.dev cp /data/local/tmp/ff.db databases/fund_flow_greenfield.db"
adb -s emulator-5554 shell am force-stop com.naveen.fund_flow.dev
adb -s emulator-5554 shell monkey -p com.naveen.fund_flow.dev -c android.intent.category.LAUNCHER 1
# debug cold start is ~18s before the first frame
adb -s emulator-5554 shell screencap -p /sdcard/s.png && adb -s emulator-5554 pull /sdcard/s.png
```

Seeded database with realistic data lives at `/data/local/tmp/ff.db` on the
emulator. The physical device is CI-signed, so a local debug build cannot be
installed over it without uninstalling — which would destroy real imported
transactions. **Do not uninstall it.** Ship via CI and update in-app instead.

### Widget tests default to tablet

Flutter's default test window is 800px, above the 760 wide breakpoint, so
every widget test renders the **tablet** layout unless it sets
`tester.view.physicalSize`. `test/flow_shell_test.dart` has a `_usePhone`
helper. Earlier tests in the repo do not, and are silently testing tablet.

## Design system notes

`lib/ui2/tokens/`

- **Palette is computed, not chosen.** The previous one failed colour-vision
  separation — income and expense sat 3.0 ΔE apart under protanopia. Slots
  were found by searching an OKLCH grid against the dataviz skill's
  validator. Light passes at 15.2 ΔE deutan / 20.3 normal, dark at 9.2 / 16.3.
  **Re-run the validator if any slot changes.**
- No set of six slots passes at a single lightness at any hue spacing.
  Deuteranopia collapses hue, so adjacent slots alternate **lightness**.
- Dark is selected against the dark surface, not flipped from light.
- Amounts are their own typographic role with tabular figures. They are not
  set in the display face, whose wide apertures compete with precision.
- Direction never rests on colour: always a sign or an arrow as well.
