# pyro_ui

The Pyro design system in Flutter: design tokens, the theme and (as
they are built) the editor's widgets. Only the Pyro app (`apps/editor`)
uses it; it is never published.

```dart
MaterialApp(theme: PrTheme.dark(), home: ...);

final c = PrColors.of(context);
Container(color: c.surfacePanel, height: PrSizes.rowTree);
Text('Inspector', style: PrText.heading.copyWith(color: c.textPrimary));
Icon(PrIcons.hitbox, size: PrSizes.iconSm);
```

## What belongs here (Q83)

- **Yes:** tokens, the theme, and presentational widgets from the design
  system (buttons, fields, property rows, tree rows, menus, dialogs, panel
  chrome). Widgets take plain values and callbacks.
- **No:** anything that knows about scenes, Nodes, the Document, the Type
  catalog, processes or Riverpod. The Hierarchy, Inspector and other panels
  live in the app and compose these widgets.
- **Dependencies:** Flutter and the Lucide icon font (`lucide_icons_flutter`);
  the fonts are bundled. Never `flame`, `pyro_runtime` or the app.

## Source of the tokens

The design system was made in Claude Design from prompt 0 of
[`dev-docs/claude-design-prompts.md`](../../dev-docs/claude-design-prompts.md).
[`design/tokens.json`](design/tokens.json) is an unmodified copy of its
`tokens.json`; `test/tokens_test.dart` fails when the Dart tokens drift from
it. To pick up a design change, replace the file and fix the Dart side until
the test passes.

## Reference designs (HTML)

[`design/`](design) also holds the views designed in Claude Design from the
view prompts, each exported as one self-contained HTML file, so AI agents and
people can match the app's UI to them:

| File | View (prompt) |
|---|---|
| [`Pyro — Welcome window (merged).html`](<design/Pyro — Welcome window (merged).html>) | Project list / welcome window (Prompt 1) |
| [`Flame Studio Editor.html`](<design/Flame Studio Editor.html>) | Editor shell, toolbar and scene tabs (Prompt 2) |

They are references, not sources: nothing is generated from them and no test
reads them (unlike `tokens.json`). Open one in a browser, or grep it for exact
values, then build the screen from `pyro_ui` widgets. Where a design and
`tokens.json` disagree, `tokens.json` wins. The files are large (1.5–2.2 MB,
mostly embedded assets), so search them rather than reading them whole. More
views are added here as they are designed from
[`dev-docs/claude-design-prompts.md`](../../dev-docs/claude-design-prompts.md).

Naming: token `surface-panel` is `PrColors.surfacePanel`, `space-2` is
`PrSpacing.s2`, `radius-sm` is `PrRadii.sm`, `size-row-tree` is
`PrSizes.rowTree`, text style `body-strong` is `PrText.bodyStrong`.

## Fonts and icons

- **Fonts.** [`fonts/`](fonts) holds Inter 4.1 (400, 500, 600) and JetBrains
  Mono 2.304 (400, 500), the static `.ttf` files from the
  [rsms/inter](https://github.com/rsms/inter/releases/tag/v4.1) and
  [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304)
  releases; the design system's `.woff2` files don't load in Flutter. Both are
  SIL OFL 1.1 (`fonts/*-OFL.txt`). The `PrText` styles name the package, so
  the app gets them without declaring anything.
- **Icons.** Lucide, from
  [`lucide_icons_flutter`](https://pub.dev/packages/lucide_icons_flutter)
  (MIT, an icon font; it also ships thinner stroke weights as
  `LucideIcons100`…`600`). Widgets use `PrIcons`, which names the icons the
  design system uses; add an icon there before using it.

## Components

Built from [`dev-docs/ui-components-plan.md`](../../dev-docs/ui-components-plan.md)
(Q84). Each has a page in the [gallery](example) (`cd example && flutter run
-d macos`) laid out like its `preview.html`, and widget tests per state.

All 29 components of the design system, the EditorShell and the 60 icons are
built, and every component page has been compared side by side with its
`preview.html` (ticked in the gallery's page list). One golden per gallery
page guards the look (`example/test/goldens`, macOS only; see the
[gallery README](example/README.md)).

| Group | Widget | Notes |
|---|---|---|
| Foundations | `PrInteractive`, `PrStateColor` | interaction states; focus ring for keyboard focus only |
| | `PrFocusRing`, `PrDebugStates` | ring outside / inset; forced states for the gallery and tests |
| | `PrFieldBox`, `PrPanelFocus`, `PrValueSource`, `PrScrubHandle` | field chrome; panel-focus propagation |
| | `PrAnchoredOverlay`, `PrShortcutLabel` | floating-layer positioner (flip and shift); ⌘⇧ glyphs on macOS, "Ctrl+Shift" elsewhere |
| | `PrPlatformHooks` | native callbacks the app supplies: `sampleScreenColor` (eyedropper), `pointerLock` (scrub cursor) |
| Icons | `PrIcons` (60), `PrPlayGlyph` | `test/icons_test.dart` pins the names that differ from Lucide |
| Actions | `PrButton`, `PrIconButton`, `PrToggleButton` | primary, secondary, ghost, danger; disabled controls keep a tooltip |
| | `PrSplitButton`, `PrSegmentedControl`, `PrToolbar` | split main/caret targets; roving focus in the toolbar and segments |
| Inputs | `PrTextField`, `PrSearchField`, `PrNumberField`, `PrDropdown` | on `EditableText` inside `PrFieldBox`, not Material fields |
| | `PrCheckbox`, `PrSwitch` | the checkbox has a mixed state |
| Inspector | `PrPropertyList`, `PrPropertyRow` | shared, resizable label column; default from code / overridden + reset |
| | `PrNumberProperty` | label scrub with modifiers, expressions (`32*2`, `+=8`), range slider |
| | `PrBoolProperty`, `PrVector2Property` | per-axis scrub and mixed; aspect lock |
| | `PrColorProperty`, `PrColorPicker` | hex + alpha; the eyedropper shows only with `sampleScreenColor` |
| | `PrAssetSlot`, `PrEntitySlot` | on a shared `PrSlot`; drop targets, `PrDragInFlight` for the quiet accept state |
| Structure | `PrPanel`, `PrSectionHeader`, `PrCollapsible` | panel focus edge; collapsible sections |
| | `PrTabs` | document and dock styles; dirty dot, close |
| | `PrTreeRow` | all states, drop zones, inline rename, auto-expand |
| Floating | `PrContextMenu` (`showFsContextMenu`, `PrContextMenuRegion`, `PrMenuButton`) | on `RawMenuAnchor`; submenus, checked and destructive items |
| | `PrTooltip`, `PrTooltipGroup` | on `RawTooltip`; 0ms hand-off between adjacent controls |
| | `PrDialog` (`showFsDialog`), `PrToastHost`, `PrToast` | toasts: at most 3 visible, the rest queue |
| Status | `PrBanner`, `PrBadge`, `PrDeviceChip`, `PrEmptyState` | |
| | `PrProgressBar`, `PrSpinner`, `PrStatusDot`, `PrDelayedProgress` | slower, not stopped, under reduce-motion |
| Shell | `PrEditorShell` | slots and resizable seams; sizes reported to the app, which persists them |

## Not done yet

- **Native hooks.** The eyedropper (`NSColorSampler`) and hiding and wrapping
  the cursor while scrubbing need code in the app's macOS runner; until then
  the widgets hide or simplify those features (Q84).
- **Light theme.** Tokens exist for dark only; a light theme adds a second
  `PrColors` and `PrShadows` constant.
