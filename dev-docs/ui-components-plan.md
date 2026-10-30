# Pyro — UI components plan

| | |
|---|---|
| **Status** | Built (2026-10-18): every component, the EditorShell, the icons, the gallery with one golden per page, and a side-by-side review against `preview.html` |
| **Date** | 2026-10-17 |
| **Scope** | `packages/pyro_ui`: the 29 components and the EditorShell of the Claude Design design system, their shared foundations, the icon set, a gallery app and the tests |
| **Decisions** | *Q83* (package boundary), *Q84* (this plan) |
| **Sources** | The design system in Claude Design (`project/README.md`, `components/<Name>/README.md` and `preview.html`, `design-system.json`); `packages/pyro_ui/`; [`project-plan.md`](project-plan.md) §8.6, §14 |

The design system's component guidelines already give each widget's inputs ("Consumer provides")
and every state (`preview.html`). So the widgets can be built ahead of the panels, against a gallery,
instead of one at a time as panels need them. This plan says what each widget's Dart API is, what
it depends on, in what order to build it and how long it takes. It contains no widget code.

---

## Contents

1. [Rules every widget follows](#1-rules-every-widget-follows)
2. [Shared foundations](#2-shared-foundations)
3. [Components](#3-components)
4. [EditorShell](#4-editorshell)
5. [Icons](#5-icons)
6. [Gallery app and tests](#6-gallery-app-and-tests)
7. [Decisions for the user](#7-decisions-for-the-user)
8. [Order and estimate](#8-order-and-estimate)
9. [Files](#9-files)

---

## 1. Rules every widget follows

- **Domain-free (*Q83*).** Widgets take plain values (`String`, `double`, `bool`, `Color`,
  `IconData`, `Widget`) and callbacks. No Node, asset, device, scene or Type catalog types. Where
  the design names a domain thing, the API takes what is drawn: a label, an icon, a flag. Payloads
  that pass through a widget untouched (drag data, dropdown values, menu results) are a generic `T`.
- **One widget per component, `Pr` prefix**, one file per component under `lib/src/<group>/`,
  exported from `pyro_ui.dart`. A component that has variants takes an enum
  (`PrButtonVariant.primary`), not separate classes.
- **Colours from tokens only.** `PrColors.of(context)` and `PrShadows`; no hex literals, no
  opacity for disabled (the design says never), no Material `InkWell`, no ripples.
- **States through one wrapper** (§2.1). Every interactive widget reports `hovered`, `pressed`,
  `focused` (keyboard only), `disabled`, `selected` and `error` through `PrInteractive`, so
  states look and behave the same everywhere.
- **`onX == null` means disabled**, as in Flutter. A disabled control still shows its tooltip
  (the design: "say why").
- **Disabled controls are out of the Tab order**, as in native toolkits: a focused control that
  ignores Enter feels broken, and dead stops slow keyboard use down. The exception is opt-in,
  per control: `focusableWhenDisabled: true` (on `PrInteractive`, `PrButton` and
  `PrIconButton`) keeps the Tab stop so keyboard users can reach the tooltip's disabled reason
  ("Run game" with no device connected). Use it only for the few commands whose reason lives in
  the tooltip; prefer showing the reason where it can always be read (a banner, the empty
  state, the status bar). Menus and roving groups keep skipping disabled items, as macOS does.
- **Fixed heights** from `PrSizes`; rows never grow with content.
- **Value conventions shared by the Inspector widgets:**
  - `PrValueSource { codeDefault, overridden }`: how the PropertyRow draws the label and whether
    it shows the reset button. The words are the design's ("default from code", "overridden"); the
    widget doesn't know what an Override is.
  - Mixed values: the value parameter is nullable and `mixed: true` draws "—". For `Vector2Property`
    each axis has its own `mixed` flag.
  - Continuous editing: `onChanged(value)` while scrubbing or dragging, then `onCommit(value)`
    once per gesture or edit, which the app turns into one undo entry (design: "one undo entry per
    scrub gesture").
- **Text from the caller.** Widgets show the strings they are given and add none of their own,
  except the design's fixed glyphs ("—", "×").

---

## 2. Shared foundations

Built first. Every component below uses one or more of them.

### 2.1 `PrInteractive`: the interaction-state wrapper

A widget that turns pointer and keyboard input into a `Set<WidgetState>` and hands it to a
builder. Every button, field box, row, tab, segment, slot and menu item is built on it.

```dart
PrInteractive({
  required Widget Function(BuildContext, Set<WidgetState> states) builder,
  VoidCallback? onPressed,           // null = disabled
  bool selected = false,
  bool error = false,
  WidgetStatesController? statesController, // for callers that need to drive or read states
  FocusNode? focusNode,
  bool autofocus = false,
  bool focusable = true,             // false inside roving-focus groups (Toolbar, SegmentedControl)
  bool focusableWhenDisabled = false, // keep the Tab stop while disabled (§1, disabled controls)
  MouseCursor cursor = SystemMouseCursors.basic,
  Map<ShortcutActivator, Intent>? shortcuts,
  Map<Type, Action<Intent>>? actions,
  String? semanticsLabel,
  bool? semanticsToggled,            // ToggleButton
})
```

- Built on `FocusableActionDetector` and a `WidgetStatesController`; `ActivateIntent`
  (Enter/Space) calls `onPressed`.
- **Keyboard-only focus ring:** `focused` is added only while
  `FocusManager.instance.highlightMode == FocusHighlightMode.traditional`; it listens to
  `addHighlightModeListener`, so a mouse click never shows the ring.
- **Disabled** controls drop out of the Tab order unless `focusableWhenDisabled`. With it, a
  disabled control takes focus and shows the ring, is still announced as disabled, and swallows
  Enter and Space; `onPressed`, `shortcuts` and `actions` stay inactive until it is enabled.
- **Pressed** comes from a `Listener` (pointer down and up inside), not a `GestureDetector`, so
  the wrapper can sit inside drag sources (TreeRow) without fighting the gesture arena.
- **Forced states for the gallery and goldens:** a `PrDebugStates` InheritedWidget, read only in
  debug and profile builds, adds a fixed set of states to every `PrInteractive` below it. This is
  how the gallery shows Hover, Pressed and Focused side by side like `preview.html`.
- Helpers next to it: `PrFocusRing.outside` (`PrShadows.focus`, the 2px ring outside the edge)
  and `PrFocusRing.inset` (`focusInset`, for rows in scrolling lists), and
  `PrStateColor.resolve(states, {...})`, a small map-to-colour helper.

### 2.2 `PrFieldBox`: the shared field chrome

The box drawn by TextField, SearchField, NumberField, Dropdown and the inspector fields: fill
`surface-input`, 1px border `border-control` → hover `border-strong` → focus `focus-ring` border
plus a 1px outer ring, `error` border, disabled `surface-panel` and `border-subtle`, read-only
flat. Two heights: `PrFieldSize.regular` (24) and `.dense` (20, inside property rows). It takes
`leading`, `child` and `trailing` slots and an `accentEdge` flag (scrubbing: `accent-text`
border). It has no text logic of its own.

### 2.3 `PrPanelFocus`: panel-focus propagation

```dart
PrPanelFocus({required Widget child})   // inserted by PrPanel; also usable alone
static bool PrPanelFocus.of(BuildContext context) // true outside any panel
```

A `FocusScope` plus an `InheritedNotifier` that exposes `hasFocus` (the scope's
`hasFocus`, so focus anywhere inside the panel counts). TreeRow, Tabs and list rows read it to
choose `surface-selected` or `surface-selected-inactive`, and Panel uses it for the header
(title colour and the 2px `accent-text` top edge). Panel cycling (⌃Tab, ⌘1–⌘4) is the app's
business: it owns the panel order, and `PrPanel` takes a `focusNode` it can request focus on.

### 2.4 Overlay plumbing: `PrAnchoredOverlay`

One positioner for everything that floats next to an anchor: tooltips, Dropdown lists,
ContextMenu and SplitButton menus, the colour picker popover.

- Built on `OverlayPortal` (no `OverlayEntry` bookkeeping) with a `CustomSingleChildLayout`
  that places the overlay below the anchor (or at a point, for context menus), with a gap,
  then **flips** to the other side when it doesn't fit and **shifts** to stay inside the window.
- Dismissal: outside tap (`TapRegion`), Esc (`DismissIntent`), and anchor removal.
- Menus use `RawMenuAnchor` for focus and submenus (§7.3) and only borrow the positioner;
  tooltips use `RawTooltip` (§7.4) with the same positioner as its `positionDelegate`.

### 2.5 `PrToastHost`

```dart
PrToastHost({required Widget child})            // once, above the EditorShell
PrToastController PrToastHost.of(BuildContext)
PrToastHandle controller.show(PrToastData data) // .update(...) for progress, .dismiss()
```

A host `Stack` at the bottom right with a 16px inset: newest on top, at most 3 visible (older ones
wait in a queue), 200ms enter and exit, and success/info dismissed after 4s with the timer paused
while hovered. Logging every toast to the Console is the app's job (the design says the toast
is "never the only record"), so `show` stays a plain call.

### 2.6 Platform hooks: `PrPlatformHooks`

An InheritedWidget with optional callbacks that need native code, which the app supplies from its
macOS runner (the package stays Flutter-only, *Q83*):

```dart
PrPlatformHooks({
  Future<Color?> Function()? sampleScreenColor, // ColorProperty eyedropper (§7.2)
  PrPointerLock? pointerLock,                    // NumberProperty cursor hide + wrap (§7.1)
  required Widget child,
})
```

Widgets check for the hook and hide or simplify the feature when it is missing, so the gallery and
tests run without native code.

---

## 3. Components

Estimates are in evenings (~3 h) and include the widget, its gallery page and its widget tests
(§6). "Uses" lists the foundations and other components each widget is built from.

### 3.1 Actions

#### `PrButton`: 0.5

```dart
PrButton({
  required String label,
  required VoidCallback? onPressed,
  PrButtonVariant variant = PrButtonVariant.secondary, // primary, secondary, ghost, danger
  IconData? icon,
  String? tooltip, String? shortcut,
  FocusNode? focusNode, bool autofocus = false,
})
```

States: default, hover, pressed, focused, disabled, per variant (4 × 5 in `preview.html`), plus
with-icon. No selected or error state (the design: use ToggleButton, or put the error on the
field). Uses: `PrInteractive`, `PrTooltip`.

#### `PrIconButton`: 0.25

```dart
PrIconButton({
  required IconData icon,
  required String tooltip,          // required; also the semantics label
  required VoidCallback? onPressed,
  String? shortcut,
  bool selected = false,            // latched look
  PrIconButtonSize size = PrIconButtonSize.regular, // regular 24 (toolbar), small 20 (header, row)
})
```

States: default, hover, pressed, focused, disabled, selected; 24 and 20 sizes. Uses:
`PrInteractive`, `PrTooltip`.

#### `PrToggleButton`: 0.25

```dart
PrToggleButton({
  IconData? icon, String? label,    // at least one; icon-only draws like PrIconButton
  required bool value,
  required ValueChanged<bool>? onChanged,
  required String tooltip, String? shortcut,
})
```

States: off, hover, pressed, focused, disabled, on, on + hover (`surface-selected`), on +
focused; icon form and text form (on adds an `accent-text` border). Exposes
`Semantics(toggled:)`. Uses: `PrInteractive`, `PrTooltip`.

#### `PrSplitButton<T>`: 0.5

```dart
PrSplitButton<T>({
  required String label, IconData? icon,
  required VoidCallback? onPressed,             // main action
  required List<PrMenuEntry<T>> menuItems,      // caret menu; a check marks the current default
  ValueChanged<T>? onSelected,
  PrButtonVariant variant = PrButtonVariant.primary, // primary or secondary
  String? tooltip,
})
```

Two hit targets with their own hover and pressed states. States: default, hover main, hover
caret, pressed, focused, open, disabled; primary and secondary. Enter/Space runs the main action;
↓ or Alt+↓ opens the menu. "The main action always repeats the last choice" is the app's rule: it
passes the matching `label` and `onPressed`. Uses: `PrInteractive`, `PrContextMenu` (menu
building), `PrTooltip`.

#### `PrSegmentedControl<T>`: 0.5

```dart
PrSegmentedControl<T>({
  required List<PrSegment<T>> segments, // PrSegment(value:, icon:, label:, count:, tooltip:, shortcut:)
  required T selected,
  required ValueChanged<T>? onChanged,
})
```

States per segment: default, hover, pressed, focused (inset ring), selected, disabled; icon form
(tools) and text form (filters, with count badges). One Tab stop; ← → move and select. The single-key
tool shortcuts (Q W E R) are app shortcuts; the control only shows them in tooltips. Uses:
`PrInteractive` (with `focusable: false` per segment), `PrTooltip`, `PrBadge`.

#### `PrToolbar`: 0.5

```dart
PrToolbar({
  required List<PrToolbarGroup> leading,  // PrToolbarGroup(children: [...])
  List<PrToolbarGroup> center = const [],  // the Play cluster in the main toolbar
  List<PrToolbarGroup> trailing = const [],
  PrToolbarStyle style = PrToolbarStyle.main, // main (surface-raised) or viewport (surface-panel)
})
```

32px; buttons 2px apart inside a group; 1px × 16px `border-subtle` dividers between groups.
**Roving focus:** the toolbar is one Tab stop, ← → move between its controls (a
`FocusTraversalGroup` with a custom policy). The design's running-game state (an `accent` outline on
the toolbar, Prompt 2) is a `bool highlighted` flag. Uses: none of the others directly; hosts
any of them.

### 3.2 Inputs

#### `PrTextField`: 0.75

```dart
PrTextField({
  TextEditingController? controller, String? value, // one or the other
  String? placeholder,
  String? Function(String)? validator,  // non-null result = error state + message
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  bool mono = false,                     // paths
  bool readOnly = false, bool enabled = true,
  PrFieldSize size = PrFieldSize.regular,
  PrErrorDisplay errorDisplay = PrErrorDisplay.below, // below (one line) or tooltip (dense rows)
  FocusNode? focusNode, bool autofocus = false, bool selectAllOnFocus = false,
})
```

States: filled, empty + placeholder, path (mono); default, hover, focused, disabled, error,
read-only. Built on `EditableText` inside `PrFieldBox`, not Material `TextField` (whose
`InputDecoration` fights the 20/24px heights). Text selection colours come from `PrTheme`. The
dense error tooltip stays up while the field has focus, so the message is visible while typing
(not behind hover); either form is announced to screen readers when it appears or changes (WCAG
3.3.1, 4.1.3). Uses: `PrFieldBox`, `PrTooltip` (error in dense rows).

#### `PrSearchField`: 0.25

```dart
PrSearchField({
  required String query,
  required ValueChanged<String> onChanged,  // live, no Enter
  String? resultLabel,      // "3 of 12"; the app formats it
  bool noMatch = false,     // "No match" in error
  String? noMatchLabel,
  String? shortcutHint,     // "⌘F", shown while empty
  VoidCallback? onExit,     // second Esc: focus back to the list
  VoidCallback? onNext, VoidCallback? onPrevious, // ↓ ↑
})
```

States: empty, with query; default, hover, focused, disabled, no results. Uses: `PrTextField`
internals, `PrFieldBox`.

#### `PrNumberField`: 0.5

```dart
PrNumberField({
  required double? value, bool mixed = false,
  PrNumberKind kind = PrNumberKind.double, // int or double
  double? min, double? max, double step = 1,
  String? unit,
  bool stepper = true,
  ValueChanged<double>? onChanged, ValueChanged<double>? onCommit,
  PrFieldSize size = PrFieldSize.regular,
  double? width,
})
```

States: plain, with unit; default, hover, scrubbing (drag the field itself), focused, disabled,
error, mixed. Shares the number-editing core with NumberProperty (parsing, expressions, ↑/↓
steps, scrub maths). Uses: `PrFieldBox`, `PrNumberEditing` (internal, see 3.3).

#### `PrDropdown<T>`: 0.75

```dart
PrDropdown<T>({
  required List<PrDropdownOption<T>> options, // PrDropdownOption(value:, label:, icon:, detail:)
  required T? value, bool mixed = false,
  required ValueChanged<T>? onChanged,
  PrFieldSize size = PrFieldSize.regular,
  bool monoOptions = false,   // enum values in the list show their Dart name in mono
  String? errorText,
})
```

States: default, hover, pressed, focused, disabled, error, mixed, open. Space, Enter and ↓
open it; type-ahead jumps to a match; the list opens on the current value; Esc closes it
without a change. The field shows `label` and the list shows `detail` (the Dart name, e.g.
`Anchor.center`) in mono. Uses: `PrFieldBox`, `PrAnchoredOverlay`, the `PrContextMenu` item
row (for consistent list items).

### 3.3 Inspector

#### `PrPropertyRow` (+ `PrPropertyList`): 0.75

```dart
PrPropertyList({required List<Widget> children, double initialLabelFraction = 0.4,
                ValueChanged<double>? onLabelFractionChanged}) // shares one label column
PrPropertyRow({
  required String label,           // the Dart name, verbatim
  required Widget editor,
  PrValueSource source = PrValueSource.codeDefault,
  VoidCallback? onReset,           // shown when overridden
  String? resetTooltip,
  bool mixed = false, bool readOnly = false, bool enabled = true,
  String? error,
  String? tooltip,                 // type + default value, formatted by the app
  PrScrubHandle? labelScrub,       // set by NumberProperty / Vector2Property
})
```

24px; label 40% (min 72px), resizable by dragging the column boundary. `PrPropertyList` holds
the shared width so every row's boundary moves together, and reports the new width so the app
can persist it. States: default from code, overridden (2px `accent-text` bar, label
`text-primary` 500, ↺ reset), mixed, error, disabled/read-only, hover (whole row
`surface-hover`). Uses: `PrInteractive`, `PrIconButton` (reset), `PrTooltip`.

#### `PrNumberProperty`: 1.25

```dart
PrNumberProperty({
  required String label,
  required double? value, bool mixed = false,
  PrNumberKind kind = PrNumberKind.double,
  double? min, double? max, double? step,
  bool slider = false,            // range variant; needs min and max
  String? unit,                   // "px", "°", "px/s"
  PrValueSource source = PrValueSource.codeDefault, VoidCallback? onReset,
  required ValueChanged<double> onChanged,  // continuous while scrubbing
  required ValueChanged<double> onCommit,   // once per gesture or edit
  String? Function(double)? validator,      // "Expected a number between 0 and 1"
  bool enabled = true,
})
```

- **Scrub:** press on the label and drag; 1 step per 2px, Shift ×10, Alt ×0.1; label and field
  border `accent-text`; cursor ↔ (`SystemMouseCursors.resizeLeftRight`). `onCommit` fires on
  drag end. Cursor hiding and edge wrapping depend on §7.1.
- **Edit:** click or Enter edits with the value selected; Enter or Tab commits; Esc reverts;
  ↑/↓ step (Shift ×10). Simple expressions (`32*2`, `+=8`) are evaluated on commit by a small
  parser in the package (`+ - * /`, parentheses, `+= -= *= /=`); it's ~100 lines and
  needs no dependency.
- **Range variant:** a slider (track `border-control`, fill `accent`, 12px thumb) plus a 56px
  number field.
- States: int, double + unit, range slider; default, hover on the label, scrubbing,
  focused/editing, disabled, error (with its tooltip, on the label: kept up while the row's field
  has focus), mixed, overridden.
- Uses: `PrPropertyRow`, `PrNumberEditing` (internal: parse, format, expression, step,
  scrub), `PrFieldBox`, `PrTooltip`.

#### `PrBoolProperty` (+ `PrCheckbox`, `PrSwitch`): 0.5

```dart
PrCheckbox({required bool? value, required ValueChanged<bool>? onChanged}) // null = mixed
PrSwitch({required bool value, required ValueChanged<bool>? onChanged})
PrBoolProperty({
  required String label, required bool? value, bool mixed = false,
  PrValueSource source = PrValueSource.codeDefault, VoidCallback? onReset,
  required ValueChanged<bool>? onChanged,
  PrBoolStyle style = PrBoolStyle.checkbox, // switch only for live, unsaved toggles
})
```

States: off, on, hover, pressed, focused, disabled off, disabled on, mixed (checkbox only),
overridden. Clicking the label toggles; Space toggles. `PrCheckbox` is exported on its own:
SectionHeader and Dialog use it. Uses: `PrInteractive`, `PrPropertyRow`.

#### `PrVector2Property`: 0.5

```dart
PrVector2Property({
  required String label,
  required double? x, required double? y,
  bool mixedX = false, bool mixedY = false,
  PrValueSource source = PrValueSource.codeDefault, VoidCallback? onReset,
  bool? aspectLocked,                          // null = no lock button
  ValueChanged<bool>? onAspectLockChanged,
  required void Function(double x, double y) onChanged,
  required void Function(double x, double y) onCommit,
  bool enabled = true,
})
```

Two 20px fields with a 16px axis cell ("X" `axis-x`, "Y" `axis-y`); drag a letter to scrub that
axis, drag the label to scrub both. Keeping the aspect ratio while locked is done inside the widget
(it only has the two numbers), so `onChanged` already gets the locked pair. States:
default, hover, scrubbing Y, focused X, disabled, error Y, mixed X, overridden; with and without
the aspect lock. Tab order X → Y → next row. Uses: `PrPropertyRow`, `PrNumberEditing`,
`PrFieldBox`, `PrToggleButton` (lock).

#### `PrColorProperty` (+ `PrColorPicker`): 0.75 + 0.75

```dart
PrColorProperty({
  required String label, required Color? value, bool mixed = false,
  PrValueSource source = PrValueSource.codeDefault, VoidCallback? onReset,
  required ValueChanged<Color> onChanged, required ValueChanged<Color> onCommit,
  ValueChanged<Color>? onPickerClosed,   // the colour the popover closed on, if changed
  List<Color> recentColors = const [],   // the app keeps the list; add to it in onPickerClosed
  bool enabled = true,
})
PrColorPicker({required Color value, required ValueChanged<Color> onChanged,
               required ValueChanged<Color> onCommit, List<Color> recentColors = const [],
               String? areaLabel, String? hueLabel}) // the sliders' semantics labels
```

Swatch 28×16 with a 1px inner white-15% edge, 6-digit upper-case hex field, separate 52px alpha
% field. Invalid hex gives an `error` border, and the swatch keeps the last valid colour. The swatch
opens the picker popover: an SV area, a hue slider, hex + alpha, recent colours, and the eyedropper
when `PrPlatformHooks.sampleScreenColor` is set (§7.2). The popover isn't modal: Enter or Space
on the swatch opens it with focus in its SV area (a click leaves focus put); in the Tab order it
sits between the swatch and the row's hex field, so Tab past its end moves on and ⇧Tab before its
start returns to the swatch, closing it either way; focus moving anywhere else closes it; Esc
anywhere in it closes it and returns focus to the swatch. Inside it the SV area and hue slider are
focusable sliders (Tab order: SV, hue, hex, alpha): the SV area steps saturation with ← → and
brightness with ↑ ↓, the hue slider steps with all four arrows, 1% / 1° per press (Shift ×10), `onChanged`
per press and one `onCommit` per run of presses (it ends after 500ms without one, when focus leaves,
or when the picker closes), like a drag. `onPickerClosed` fires once when the popover closes, if
the colour changed while it was open, so recent colours get the colour picked rather than each
step; screen readers get slider roles with "40%, 80%" and "210°" values and the
app's `areaLabel` / `hueLabel`.
States: default, hover, focused hex,
disabled, error, mixed, overridden; picker open. Uses: `PrPropertyRow`, `PrFieldBox`,
`PrNumberField` (alpha), `PrAnchoredOverlay`, `PrIconButton`.

Keyboard step size, by decision: the SV area and hue slider step whole percents and degrees, not
one hex level (1/255). 1% of saturation is 2.55 channel levels at full brightness, so → from
`#FFFFFF` goes to `#FFFCFC`, then `#FFFAFA`, `#FFF7F7` (−3, −2, −3, … as it rounds). That's kept
because the screen-reader values are whole percents and degrees (a 1/255 step would announce the
same value, or change nothing, on many presses), it matches the slider practice in WAI-ARIA and
Figma's and Photoshop's HSB pickers, and exact colours are typed in the hex field, not stepped.

Possible future updates (not planned yet):

- **Home / End and Page Up / Page Down** on both sliders, the WAI-ARIA slider keys: Home / End go
  to the ends (saturation 0 / 100% in the SV area, hue 0 / 360°), Page Up / Page Down step 10%
  or 10° like Shift+arrow (brightness in the SV area). Small, and expected by screen-reader and
  keyboard users.
- **HSB or RGB number fields** for exact per-channel entry: `PrNumberField`s for H, S, B or R, G,
  B, with a colour-model dropdown as in Figma; their arrows step one unit, so RGB steps one hex
  level. A design addition (layout, picker height, preview.html first), so a separate decision.

#### `PrAssetSlot<D>` and `PrEntitySlot<D>` (on a shared `PrSlot<D>`): 0.75 + 0.25

Both are a 20px reference slot that is also a drop target. They differ in their icon and their actions,
so they share one internal `PrSlot<D>` (`D` = the drag payload type the app uses):

```dart
PrAssetSlot<D>({
  required String? fileName,        // null = empty
  required String placeholder,      // "None (Sprite)"
  Widget? thumbnail, IconData typeIcon = PrIcons.image, // thumbnail wins when set
  bool missing = false, String? missingLabel,           // keeps the old name visible
  bool mixed = false, String? mixedLabel,               // "— (2 different)"
  VoidCallback? onBrowse, VoidCallback? onClear,
  VoidCallback? onReveal, VoidCallback? onOpen,         // click / double-click on the name
  PrDropAcceptance Function(D data)? willAccept,        // accept, reject, ignore
  ValueChanged<D>? onDrop,
  String Function(D data)? dropHint,                    // "Drop coin.png here"
  bool enabled = true,
})
PrEntitySlot<D>({
  required String? name, required String placeholder, // "None (CameraComponent)"
  IconData? typeIcon,
  bool missing = false, bool picking = false,          // picking: crosshair latched
  String? pickingHint,                                 // "Click a node in the scene…"
  VoidCallback? onPick, VoidCallback? onCancelPick, VoidCallback? onClear,
  VoidCallback? onReveal,                              // select and frame the node
  PrDropAcceptance Function(D data)? willAccept, ValueChanged<D>? onDrop,
  String Function(D data)? dropHint, bool enabled = true,
})
```

The *thumbnail provider* the design names is just `Widget? thumbnail`: the app builds the image,
and the package never loads files. The *accepted types* become `willAccept`, so the app decides what
fits. States (both): empty, filled, hover, focused, drop target accepts, drop wrong type
(`error` border, not-allowed cursor), missing, disabled, mixed, overridden; EntitySlot adds
picking. ⌫ clears when focused; Esc cancels picking. The "every compatible slot lights up while a
drag is in flight" behaviour comes from Flutter's `DragTarget.onWillAcceptWithDetails`, which runs
only under the pointer. So `PrSlot` also takes an optional `PrDragInFlight<D>`
(a `ValueListenable<D?>`), which the app sets while a drag runs, to show the quiet accept state
everywhere. Uses: `PrInteractive`, `PrIconButton`, `PrBadge` ("Missing"), `PrPropertyRow`.

### 3.4 Structure

#### `PrPanel`: 0.5

```dart
PrPanel({
  required String title, IconData? icon,
  List<Widget> actions = const [],          // ≤ 3 PrIconButtons
  List<PrMenuEntry<void>> overflow = const [], // the ⋯ menu
  required Widget body,
  Widget? headerProgress,                    // PrProgressBar under the header
  FocusNode? focusNode,                      // the app's panel cycling targets it
})
```

28px header (`surface-raised`, title `heading`), body `surface-panel`. Focused: title
`text-primary` plus the 2px `accent-text` top edge; unfocused: `text-secondary`. Inserts
`PrPanelFocus`. States: focused, unfocused, header action latched and hovered. Uses:
`PrPanelFocus`, `PrIconButton`, `PrContextMenu` (overflow).

#### `PrSectionHeader`: 0.5

```dart
PrSectionHeader({
  required String title, IconData? icon, String? subtitle,
  required bool expanded, required ValueChanged<bool> onExpandedChanged,
  VoidCallback? onToggleAll,           // Alt-click
  bool? enabled, ValueChanged<bool>? onEnabledChanged, // the component checkbox; null = none
  List<PrMenuEntry<void>> menu = const [],
  bool error = false,
})
```

24px; states: expanded, collapsed; default, hover, pressed, focused (inset ring), disabled
(title and icon `text-disabled`, the properties stay editable), error (alert-circle in `error`,
subtitle says why). The expand/collapse body animation (150ms) is `PrCollapsible`, a small helper
exported alongside. Uses: `PrInteractive`, `PrCheckbox`, `PrIconButton`, `PrContextMenu`.

#### `PrTabs<T>`: 0.75

```dart
PrTabs<T>({
  required List<PrTab<T>> tabs, // PrTab(value:, label:, icon:, dirty:, closable:, badges:, error:)
  required T selected,
  required ValueChanged<T> onSelect,
  ValueChanged<T>? onClose,      // ⌘W and middle-click call it too
  PrTabsStyle style = PrTabsStyle.document, // document (above the viewport) or dock (bottom)
})
```

28px. States: default, hover, pressed, focused, disabled, selected, selected in an unfocused
panel (top edge `text-secondary`), dirty (dot that becomes × on hover), error; badges for
counts. ⌃Tab / ⌃⇧Tab cycling is an app shortcut that calls `onSelect`. Uses: `PrInteractive`,
`PrPanelFocus`, `PrBadge`.

#### `PrTreeRow<T>`: 1.25

```dart
PrTreeRow<T>({
  required int depth,
  required String name, IconData? icon,
  bool hasChildren = false, bool expanded = false, ValueChanged<bool>? onExpandedChanged,
  bool selected = false, bool keyboardCursor = false,
  PrTreeRowTone tone = PrTreeRowTone.normal,  // normal, dimmed (hidden node), prefab, error
  List<Widget> badges = const [],
  List<PrTreeRowAction> actions = const [],   // visibility, lock: shown on hover, pinned when set
  VoidCallback? onTap, VoidCallback? onDoubleTap, VoidCallback? onSecondaryTap, // + position
  // Inline rename
  bool renaming = false, ValueChanged<String>? onRenameCommit, VoidCallback? onRenameCancel,
  // Drag and drop
  T? dragData, Widget Function()? dragFeedback,
  bool canHaveChildren = true,                // leaf rows: 50/50 zones
  bool Function(T data, PrDropZone zone)? canAccept,
  void Function(T data, PrDropZone zone)? onAccept,
  VoidCallback? onAutoExpand,                 // after 600ms hovering "inside"
})
enum PrDropZone { above, inside, below }
```

22px; 16px indent per level + 4px; 16px chevron box; 14px icon. States: default, hover (row
actions appear), pressed, focused (keyboard cursor, inset ring), selected with the panel focused or
unfocused, focused + selected, disabled (hidden node), error, badges, inline rename, drag over
above, inside and below, drop not allowed. The row computes the zone (§7.5), asks `canAccept`,
and paints the insertion line, inside fill or reject border. Keyboard navigation (↑ ↓ → ← Space
⇧/⌘) is the app's tree view, because only it knows siblings and parents. The row exposes
`keyboardCursor` and the panel's `Shortcuts`. Rows are meant for a `ListView.builder` over the
flattened, visible tree. Uses: `PrInteractive`, `PrPanelFocus`, `PrTextField` (rename),
`PrIconButton`, `PrBadge`.

### 3.5 Floating

#### `PrContextMenu<T>`: 1.25

```dart
sealed class PrMenuEntry<T>
  PrMenuItem<T>({required String label, IconData? icon, PrShortcutLabel? shortcut,
                 bool enabled = true, bool checked = false, bool destructive = false,
                 T? value, VoidCallback? onSelected, List<PrMenuEntry<T>>? submenu})
  PrMenuSeparator<T>()
  PrMenuHeader<T>(String label)

Future<T?> showFsContextMenu<T>(BuildContext context,
    {required Offset position, required List<PrMenuEntry<T>> entries, String? header})
PrContextMenuRegion<T>({required List<PrMenuEntry<T>> Function() entries,
                        ValueChanged<T>? onSelected, required Widget child}) // right-click
PrMenuButton<T>(...)  // anchored variant used by Dropdown-like triggers, ⋯ menus, SplitButton
PrShortcutLabel(SingleActivator activator) // renders ⌘⇧⌥⌃⌫↩ on macOS, "Ctrl+Shift+D" elsewhere
```

248px wide (min 180), 24px items, the 16px icon column always reserved. Hover and keyboard focus look
the same (`accent` fill, `text-on-accent`). Disabled items show no highlight. Destructive items are
`error`, highlighted with `error-border`. The parent of an open submenu keeps `surface-pressed`. Submenus open
after 150ms hover or →, close with ←, and Esc closes one level. States: default, hover/focus, pressed,
checked, disabled, destructive, destructive hover, submenu open, section header. Built on
`RawMenuAnchor` (§7.3). Uses: `PrAnchoredOverlay` (positioner), `RawMenuAnchor`.

#### `PrTooltip`: 0.75

```dart
PrTooltip({
  required String message, PrShortcutLabel? shortcut, List<String> details = const [],
  required Widget child,
})
PrTooltipGroup({required Widget child}) // optional; one at the app root is enough
```

`surface-overlay`, 1px `border-overlay`, `radius-sm`, `shadow-tooltip`, 4×8 padding, max
240px, `small` text, shortcut in a 16px key cap. 500ms delay, **0ms when moving between adjacent
tooltipped controls** (§7.4), hides on press or Esc, placed below with a 4px gap and flips or
shifts to stay inside the window. Also shown after the same delay when the anchor takes keyboard
focus (not on a click that moves focus) and hidden when focus leaves. Shown for disabled controls
too; keyboard users reach those only with `focusableWhenDisabled`. `showWhileFocused` (a field's
error: dense TextField, NumberField, a PropertyRow's label via `focusTarget`) pins it while focus is
in the field, at once and announced; a separate anchored layer, since `RawTooltip` hides on any press
and on mouse exit. Not for errors the user didn't just cause (Dropdown). States in the gallery: property
label, truncated name, disabled control. Uses: `RawTooltip`, `PrAnchoredOverlay` (positioner).

#### `PrDialog`: 0.5

```dart
Future<T?> showFsDialog<T>(BuildContext context, {required PrDialog<T> dialog})
PrDialog<T>({
  required String title,             // a question or an action
  String? body, Widget? content,     // fields, a checkbox
  required PrDialogAction<T> primary,   // PrDialogAction(label:, value:)
  PrDialogAction<T>? secondary,         // "Cancel": also Esc
  PrDialogAction<T>? destructive,       // left, apart
  PrDialogWidth width = PrDialogWidth.regular, // 440 or form 560
})
```

Built on `showGeneralDialog` with the `scrim` barrier and a 200ms fade (no scale). The primary button has initial focus and answers Enter, Esc returns the secondary value,
focus is trapped (the route's `FocusScope`), and focus goes back to the trigger on close (route
default). Uses: `PrButton`, `PrIconButton` (close).

#### `PrToast`: 0.75 (with `PrToastHost`, §2.5)

```dart
PrToastData({
  required PrToastKind kind,   // success, info, warning, error, progress
  required String title, String? message,
  List<PrToastAction> actions = const [],  // ≤ 2 ghost buttons
  bool dismissible = true,
  double? progress,            // progress kind; null = indeterminate
})
```

320px, overlay surface. States: one per kind, with and without message and actions, a stack of
3, hovered (timer paused). Uses: `PrToastHost`, `PrButton` (ghost), `PrIconButton`,
`PrProgressBar`.

### 3.6 Status

#### `PrBanner`: 0.25

```dart
PrBanner({required PrStatusKind kind,   // info, warning, error, success
          required InlineSpan message,  // the caller bolds the subject
          PrBannerAction? action, VoidCallback? onDismiss})
```

States: the four kinds, with an action, with dismiss. Uses: `PrButton` (ghost, 20px),
`PrIconButton`.

#### `PrBadge` and `PrDeviceChip`: 0.5

```dart
PrBadge({required PrBadgeKind kind,  // warning, error, missing, prefab, info, success, neutral, accent
         String? label, int? count, IconData? icon, bool pill = false})
PrDeviceChip({required IconData icon, required String label, String? detail, // "852×393", "offline"
              bool selected = false, bool error = false, VoidCallback? onPressed})
```

Status badges get their icon from the kind (warning → triangle, error → alert-circle), so colour
never stands alone. `PrDeviceChip` takes an icon, a label and a detail string, so the app maps its
device model to them. States: every badge kind and the pill; chip default, hover, pressed, focused,
disabled, selected, error. Uses: `PrInteractive` (chip).

#### `PrProgressBar`, `PrSpinner`, `PrStatusDot`: 0.5

```dart
PrProgressBar({double? value, PrProgressTone tone = PrProgressTone.foreground}) // or .background (info)
PrSpinner({double size = 14})               // 16 in toolbars
PrStatusDot({required PrStatus status, required String label}) // idle, working, ok, error
PrDelayedProgress({required bool busy, required Widget child}) // shows child after 300ms
```

Under reduce-motion (`MediaQuery.disableAnimations`) spinners and the working pulse slow down
instead of stopping. States: indeterminate, determinate, spinner 14/16, the four dots.
Uses: none.

#### `PrEmptyState`: 0.25

```dart
PrEmptyState({required IconData icon, required String title, required String message,
              required PrButton action, String? shortcutHint})
```

Centred 48px tile, `title` text, the message at most 280px wide, one button (the caller picks primary or
secondary). Uses: `PrButton`.

---

## 4. EditorShell

`PrEditorShell`, 1.5 evenings: a layout that knows only slots and sizes.

```dart
PrEditorShell({
  required Widget titleBar,        // centred document title; the shell reserves the
  double titleBarLeadingInset = 78,//   macOS traffic-light zone on the left
  required Widget toolbar,         // usually a PrToolbar
  required Widget left,            // Scene / Hierarchy panel
  required Widget center,          // document tabs + viewport toolbar + viewport
  required Widget right,           // Inspector
  Widget? bottom,                  // dock (Console / Assets); null hides it
  bool bottomCollapsed = false, ValueChanged<bool>? onBottomCollapsedChanged,
  required Widget statusBar,
  required PrShellSizes sizes,     // left, right, bottom
  required ValueChanged<PrShellSizes> onSizesChanged, // during a drag
  ValueChanged<PrShellSizes>? onSizesChangeEnd,       // the app persists them per project
  PrShellLimits limits = PrShellLimits.standard,
})
```

- Regions: title bar 38, toolbar 32, three columns separated by 1px of `bg-app`, bottom dock under
  the centre column (Prompt 2 and the EditorShell preview put it there, not across the full width),
  status bar 22.
- **Seams:** each 1px line has a 4px hit area (`MouseRegion` with the ↔ or ↕ cursor and a drag
  handler). Hover and dragging show `border-strong` and `accent-text` (Prompt 2 asks for both
  states). Dragging clamps to the limits.
- **Sizes are reported, not stored:** `onSizesChanged` fires during the drag (the parent rebuilds
  with the new `sizes`) and `onSizesChangeEnd` on drag end, when the app saves them per project.
  Defaults 260 / 320 / 220.
- **Fitting the window:** the centre keeps at least 750 × 520 (`PrShellLimits.minCenterWidth`,
  `minCenterHeight`); when the docks don't fit with it, they shrink in proportion, never below
  their minimum (layout, not persisted). At the 1280×800 minimum the defaults come out at about
  237 / 291 / 187. A drag starts from the size on screen. (Built this way rather than a fixed
  240 / 288 / 180 below 1280×800: a cap on the stored size would swallow a drag that grows a
  capped dock, and a rule based on room has no jump when the window shrinks.)
- **Collapsed bottom dock:** shows its top 28px (the dock's tab strip) and keeps the dock laid out
  at its expanded height underneath, so its state survives. With `onBottomCollapsedChanged`,
  dragging the seam below half the minimum height collapses the dock and dragging it up expands it.
- The title bar draws nothing native. Hiding the macOS title bar and placing the traffic lights
  (`NSWindow` full-size content view) is app runner configuration, not package code.
- The gallery shows the full EditorShell preview with placeholder panels built from the package's
  components (§6).

Uses: `PrPanelFocus` (indirectly through the panels the app passes in), nothing else.

---

## 5. Icons

`PrIcons` grows from 11 to the 60 icons in the design system's Icons group. Each was compared
shape-by-shape against `lucide_icons_flutter` 4.0.0 in the pub cache (the design's SVGs from the
artifact against the SVG in each constant's doc comment).

**Naming rule:** each `PrIcons` member takes the **design system's icon name**, camel-cased
(`chevron-down` → `chevronDown`), and its doc comment names the Lucide glyph. That already
covers `hitbox`, and it covers the seven renamed below.

**Role names for node types: not in the package.** Node types (camera, sprite, prefab, script…)
are Pyro concepts, and per *Q83* the package knows nothing about Nodes. The app keeps a
`nodeKindIcon(…)` map in its Hierarchy code. The `PrIcons` doc comment records the design's
convention (camera → video, sprite → image, sprite animation → film, text → type, hitbox → hitbox,
group → layers, world → globe, particles → sparkle, generic component → circle-dot,
component/prefab → box, script → file-code) so the app's map follows it.

### 5.1 Names that differ from Lucide, or where the same name is the wrong glyph

| Design name | `PrIcons` | `LucideIcons` | Note |
|---|---|---|---|
| `external` | `external` | `externalLink` | |
| `more` | `more` | `ellipsis` | `moreHorizontal` is an alias for it |
| `reset` | `reset` | `rotateCcw` | |
| `rotate` | `rotate` | `rotateCw` | |
| `scale` | `scale` | `maximize2` | ⚠ `LucideIcons.scale` exists but is the balance scale |
| `pointer` | `pointer` | `mousePointer2` | ⚠ `LucideIcons.pointer` exists but is a hand |
| `grid` | `grid` | `grid3x3` | `grid` is an alias for it |
| `hitbox` | `hitbox` | `squareDashed` | (already) |
| `stop` | `stop` | `square` | Lucide has no `stop`; the design draws a 14px rounded square, Lucide's is 18px, so it looks slightly larger |
| `sliders` | `sliders` | `slidersHorizontal` | ⚠ `LucideIcons.sliders` is an alias for **sliders-vertical** |
| `step-forward` | `stepForward` | `skipForward` | ⚠ `LucideIcons.stepForward` is a different glyph (bar on the left); the design's triangle + bar on the right is `skip-forward` |
| `check-circle` | `checkCircle` | `circleCheck` | ⚠ `LucideIcons.checkCircle` is an alias for **circle-check-big** (open circle, big tick); the design's is `circle-check` |
| `alert-circle` | `alertCircle` | `circleAlert` | old name is an alias; use the current one |
| `alert-triangle` | `alertTriangle` | `triangleAlert` | as above |
| `unlock` | `unlock` | `lockOpen` | as above |
| `filter` | `filter` | `funnel` | as above |
| `trash` | `trash` | `trash` | not `trash2` (that one has two inner lines) |

Five of these would have been wrong with a plain name match (`scale`, `pointer`, `sliders`,
`stepForward`, `checkCircle`). So `icons_test.dart` should pin each of these to its expected
`LucideIcons` constant, as it already does for `hitbox`.

### 5.2 The other 43: same name in Lucide

`box`, `check`, `chevronDown`, `chevronRight`, `circleDot`, `code`, `copy`, `crosshair`, `eye`,
`eyeOff`, `file`, `fileCode`, `film`, `folder`, `globe`, `image`, `info`, `layers`, `link`,
`listTree`, `lock`, `magnet`, `minus`, `monitor`, `move`, `music`, `panelBottom`, `pause`,
`pipette`, `play`, `plus`, `redo`, `save`, `search`, `smartphone`, `sparkle`, `terminal`,
`type`, `undo`, `user`, `video`, `x`, `zap`.

The shapes are the same glyph. Lucide's current drawings differ in detail (Lucide's `magnet` is
drawn diagonally, the design's is upright; `sparkle` and `play` are rounder; circles are r=10, not r=9).
The design README asks for official Lucide glyphs, so these differences are expected.

### 5.3 The filled Play

The design draws `play` filled in the Play button and nowhere else. An icon font can only draw
Lucide's outline. `PrPlayGlyph`, a ~20-line `CustomPainter` that fills the design's rounded
triangle at 16px, is used only by the Play button. `PrIcons.play` stays the outline glyph for menus
and elsewhere.

Estimate: 0.25 evening (constants, doc comments, the pinning test, `PrPlayGlyph`).

---

## 6. Gallery app and tests

### 6.1 Gallery: `packages/pyro_ui/example`

- A macOS Flutter app (`flutter create --platforms=macos`), added to the root `pubspec.yaml`
  workspace list, depending only on `pyro_ui`. Never released.
- One page per component, in the design system's groups (Actions, Inputs, Inspector,
  Structure, Floating, Status, Shell), and **one grid per `preview.html`**: the same row and column
  labels (Default · Hover · Pressed · Focused · Disabled · …) and the same sample content
  (`Add component`, `jumpForce`, `player_run.png`), so the two can be laid side by side. Static
  states come from `PrDebugStates` (§2.1); next to each grid, a live copy to try with mouse and
  keyboard.
- A last page assembles the EditorShell preview from the package's widgets with placeholder
  content. It is the integration check that the pieces fit at 1440×900 and 1280×800.
- **Comparing with `preview.html`:** open the preview in a browser at the same zoom and compare
  by eye, page by page. That is the acceptance check for each component, recorded with a tick in
  the gallery's page list. Automatic pixel comparison against HTML isn't worth building: font
  rendering differs between Chrome and Skia anyway.

### 6.2 Tests

- **Test config:** `test/flutter_test_config.dart` loads Inter, JetBrains Mono and the Lucide
  font with `FontLoader`, so tests and goldens render real glyphs (by default flutter_test draws
  every glyph as a box).
- **Widget tests per state** (in every component's estimate). Colours: pump with forced states
  and check the resolved fill, border and text colours against `PrColors.dark`. Behaviour, through
  real input: hover with a mouse `TestGesture`; keyboard focus with the highlight mode set to
  traditional (and a check that a click does **not** show the ring); scrub maths and the
  single `onCommit` with drags; DnD zones by dropping at 10%, 50% and 90% of a row; Esc, Enter and Tab;
  roving focus in Toolbar and SegmentedControl; tooltip delay and hand-off with
  `tester.pump(duration)`; toast auto-dismiss and hover pause.
- **Goldens: yes, but one per gallery grid** (~30 files), not one per state. They are the only
  automatic check that a component still *looks* like its `preview.html` after a token or layout
  change, and the tokens test can't see layout. Restrictions keep them cheap: tagged `golden`, run
  only in the macOS CI job (goldens differ between platforms), and refreshed deliberately with
  `--update-goldens` when the design changes. ~0.75 evening for the harness, plus a few minutes per
  component (in its estimate).
- **Out of scope here:** the panels' tests (§13 of `project-plan.md`, "Panels: Light") stay in the
  app.

Estimate: gallery skeleton, test config and golden harness, 0.75 evening.

---

## 7. Decisions for the user

### 7.1 NumberProperty: hide and wrap the cursor while scrubbing

Flutter can hide the cursor (`SystemMouseCursors.none`), but it can't move it. Wrapping at the screen
edges needs native code (macOS `CGWarpMouseCursorPosition` or
`CGAssociateMouseAndMouseCursorPosition(false)`, a ~40-line method channel in the app's runner).
Without wrapping, hiding the cursor is worse than not hiding it: the hidden pointer stops at the screen
edge and the scrub stops with it, and the user can't see why.

**Recommendation: drop hiding and wrapping for v0.1.** Keep the ↔ cursor visible. The 2px-per-step rate with Shift
×10 covers large ranges, and a second drag continues from the new value. The package defines
`PrPointerLock` in `PrPlatformHooks` (§2.6), so the macOS runner can add hide + wrap later without
changing the widget's API. Revisit if the early-preview testers scrub large values.

### 7.2 ColorProperty: the eyedropper

Sampling the screen needs native code. On macOS that's `NSColorSampler` (10.15+), ~30 lines
in the runner, and it also covers the system colour panel's loupe UI.

**Recommendation: ship the picker without the eyedropper first.** The button appears only when
`PrPlatformHooks.sampleScreenColor` is set. Add the `NSColorSampler` channel in the app when Color
fields land (v0.1 work item 5, ~0.25 evening). Sampling only the game viewport, with
`RenderRepaintBoundary.toImage`, is a portable fallback for Windows and Linux in v0.3.

### 7.3 ContextMenu: `flutter_context_menu` or Flutter's menu widgets

`project-plan.md` §8.6 currently says the author's `flutter_context_menu` package provides context
menus. It does submenus, headers, dividers and custom entries, and its theming starts from the Material
theme. Its documentation says nothing about keyboard navigation, shortcut labels or checked items, which the design
requires (→ opens and ← closes submenus, Esc closes one level, focus = hover highlight, parent
item keeps `surface-pressed`). It would also be a second dependency in a package *Q83* limits to
Flutter plus the icon font and the bundled fonts.

Flutter 3.44 has **`RawMenuAnchor`** in the widgets layer (no Material styling). It handles nested
menus, focus traversal with arrow keys, Esc, outside taps and `onOpenRequested`/`onCloseRequested`
hooks, which give the 150ms submenu delay and the open animation. Material's `MenuAnchor` sits on
the same base but adds Material styling to override.

**Recommendation: build `PrContextMenu` on `RawMenuAnchor`** and drop `flutter_context_menu` from
the plan. It keeps the package Flutter-only, the keyboard behaviour comes from the framework, and
the same base serves Dropdown lists, SplitButton menus and the ⋯ menus. If `flutter_context_menu`
should stay in use elsewhere, it can be ported to `RawMenuAnchor` as a separate project.

### 7.4 Tooltip: the 0ms hand-off

Material's `Tooltip` uses the same `waitDuration` for every show, so it can't do "0ms when moving
between adjacent tooltipped controls". Flutter 3.44 has **`RawTooltip`** in the widgets layer:
no Material look, a per-instance `hoverDelay`, a `positionDelegate`, and dismissal on tap and on
`dismissAllToolTips`.

**Recommendation: a custom `PrTooltip` on `RawTooltip`, not one from scratch.** The only custom
part is the hand-off. `PrTooltipGroup` holds a "warm" flag that is set while any tooltip is visible
and for ~300ms after it hides. Each `PrTooltip` listens to it and rebuilds its `RawTooltip`
with `hoverDelay: Duration.zero` while warm and 500ms otherwise. Esc and hide-on-press come from
`RawTooltip`'s dismissal plus a `TapRegion`. This saves rebuilding hover tracking, the overlay and
semantics, ~0.5 evening less than a widget from scratch.

### 7.5 TreeRow: who decides whether a drop is allowed

**Recommendation: yes, the row only computes the zone.** It works out `PrDropZone` from the
pointer's height in the row (top 25% above, middle 50% inside, bottom 25% below; 50/50 above/below
when `canHaveChildren` is false), then asks the app's `canAccept(data, zone)` and paints the
result: insertion line, inside fill, or reject border with the not-allowed cursor. "Into its own
child", type rules and prefab locks are tree knowledge that lives in the app. The only thing the
row adds is the 600ms auto-expand timer (`onAutoExpand`), because that is about the pointer resting
on the row.

---

## 8. Order and estimate

### 8.1 Estimate

| Group | Items | Evenings |
|---|---|---|
| Foundations | `PrInteractive` + focus ring + forced states 1 · `PrFieldBox` 0.5 · `PrPanelFocus` 0.25 · `PrAnchoredOverlay` 0.5 · icons 0.25 · gallery, test config, golden harness 0.75 | 3.25 |
| Actions | Button 0.5 · IconButton 0.25 · ToggleButton 0.25 · SplitButton 0.5 · SegmentedControl 0.5 · Toolbar 0.5 | 2.5 |
| Inputs | TextField 0.75 · SearchField 0.25 · NumberField 0.5 · Dropdown 0.75 | 2.25 |
| Inspector | PropertyRow 0.75 · NumberProperty 1.25 · BoolProperty 0.5 · Vector2Property 0.5 · ColorProperty 0.75 + picker 0.75 · AssetSlot 0.75 · EntitySlot 0.25 | 5.5 |
| Structure | Panel 0.5 · SectionHeader 0.5 · Tabs 0.75 · TreeRow 1.25 | 3 |
| Floating | ContextMenu 1.25 · Tooltip 0.75 · Dialog 0.5 · Toast + host 0.75 | 3.25 |
| Status | Banner 0.25 · Badge + DeviceChip 0.5 · Progress 0.5 · EmptyState 0.25 | 1.5 |
| Shell | EditorShell 1.5 | 1.5 |
| | **Total** (before the usual 1.3–1.5× overrun) | **~23** |

Counted bottom-up, the whole set is **~23 evenings, not 12–16**. The gap is mostly behaviour the
design specifies and a component sheet hides: scrubbing with modifiers and expressions,
drop zones and rename, submenus and keyboard handling, the tooltip hand-off, toast queueing,
resizable seams, and widget tests per state. v0.1 work item 14's 4 evenings
covered tokens and the theme (now done) and a restyle, not this. If ~23 is too much for v0.1,
these can move to v0.1.1 with nothing lost before then: the colour picker popover (hex + alpha
fields still edit, −0.75), NumberProperty expressions (−0.25), goldens (−0.75), SplitButton (a
Button next to a `PrMenuButton` caret works, −0.25). That brings it to ~21.

### 8.2 The early preview (*Q82*)

> *Updated by Q87 (2026-10-18).* All of item 14 was built before the preview. Pyro's UI depends
> on the Pyro components (`Pr` widgets) for everything, the early preview included; a component
> that's missing is proposed, and the author decides whether it is built. The core below is what
> was estimated to land first.

Four widgets carry behaviour the preview's own work items need: **TreeRow** (drop zones,
focus-aware selection, rename), **NumberProperty** and **Vector2Property** (label scrubbing), and **PropertyRow** (the Override marker and *Reset to
default*). The preview's own work items 3 and 5 already have to build that behaviour (reparent by
drag, numeric editing, Override markers). Built inside the panels, it would be written twice. Built
in the package, it is written once.

**Recommendation: move a narrow core into the early preview, not the proposed first set.**

| In the early preview (item 14 core) | Evenings |
|---|---|
| `PrInteractive`, `PrFieldBox`, `PrPanelFocus`, icons, gallery skeleton and test config (no goldens yet) | 2.5 |
| `PrTreeRow` (all states, DnD zones, rename) | 1.25 |
| `PrPropertyRow` (fixed 40% label column; resizing waits) | 0.5 |
| `PrNumberProperty` (scrub, modifiers, edit, commit; no expressions, no range slider) | 0.75 |
| `PrVector2Property` (no aspect lock) | 0.5 |
| **Total** | **~5.5** |

In return, items 3 and 5 no longer build their own drag zones, scrub fields and override rows
(~0.5 off item 3 and ~1 off item 5), so the preview grows by **~4 net (38 → ~42, ~14 weeks)**. Everything else in the
preview (buttons, text fields, dropdowns, context menus, dialogs, toasts, tooltips, the panel layout)
uses the Pyro components too (*Q87*); the rest of item 14 was built ahead of the preview for that.

### 8.3 Build order

**Early preview** (inside the preview's build order, before the panels that use it):
`… → 6 → 4 → 14 core (foundations → PropertyRow → NumberProperty → Vector2Property → TreeRow)
→ 3 → 5 → 9 → …`

**v0.1, after the preview.** Planned as below, with each component built just before the panel
that needs it. All of them were built ahead of the preview instead (*Q84, Q87*); the list is kept
as the record:

1. Button, IconButton, Tooltip (with `PrAnchoredOverlay`), TextField, Panel, SectionHeader,
   ContextMenu: the remainder of the proposed first set.
2. Dropdown, BoolProperty: the rest of the preview inspector's editors.
3. Dialog, Toast + host, Badge, Banner, Progress: the preview's dialogs, image-restart toast,
   Missing states and Play progress.
4. EditorShell, Toolbar, Tabs, StatusDot: the window chrome.
5. Then by deferred panel: SearchField (Hierarchy filter, item 3); SegmentedControl, ToggleButton,
   NumberField (gizmo modes, snapping, grid size, item 4); ColorProperty, AssetSlot, EntitySlot,
   PropertyRow label resizing, NumberProperty expressions and range slider (item 5); SplitButton,
   DeviceChip (device list, item 11); EmptyState (project list and empty panels, item 1).
6. Goldens for every gallery grid, then a final side-by-side pass against `preview.html`.

---

## 9. Files

All under `packages/pyro_ui/` unless noted.

| Path | Holds |
|---|---|
| `lib/pyro_ui.dart` | exports (grows by one line per component) |
| `lib/src/foundation/` | `interactive.dart`, `focus_ring.dart`, `debug_states.dart`, `field_box.dart`, `panel_focus.dart`, `anchored_overlay.dart`, `platform_hooks.dart`, `value_source.dart`, `number_editing.dart`, `shortcut_label.dart` |
| `lib/src/actions/`, `inputs/`, `inspector/`, `structure/`, `floating/`, `status/`, `shell/` | one file per component, grouped as in §3 |
| `lib/src/icons.dart` | 60 `PrIcons` + `PrPlayGlyph` |
| `test/` | `flutter_test_config.dart`, one `<component>_test.dart` each (the goldens live in the gallery, `example/test/goldens/`, since they render its pages) |
| `example/` | the gallery app (macOS) |
| root `pubspec.yaml` | `packages/pyro_ui/example` added to `workspace:` |
| `README.md` | "Not done yet" replaced by a component list with links to the gallery |
