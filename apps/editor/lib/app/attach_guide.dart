import 'package:flutter/material.dart';
import 'package:pyro_ui/pyro_ui.dart';

/// The steps for attaching an IDE to the running game (spec 007, FR-029,
/// research R14). The address is on the clipboard by the time this opens; it
/// never appears here.
const attachGuideVsCode = [
  "Pick the game's device first: macOS (desktop) in VS Code's status bar "
      '(Flutter: Select Device). Attach looks for the game on the selected '
      'device.',
  'Open the Command Palette and run "Flutter: Attach to Process", then paste '
      'the address Pyro copied.',
  'After a hot restart, VS Code may still show the game as paused while it '
      'runs. That is a stale state in VS Code, not a Pyro problem; press '
      'Continue or restart the debug session.',
];

/// Android Studio's steps.
const attachGuideAndroidStudio = [
  "Pick the game's device first: macOS (desktop) in the device menu of the "
      'toolbar.',
  'Choose Run ▸ Flutter Attach. If it asks for the address of the running '
      'game, paste the one Pyro copied.',
];

/// Shows how to attach VS Code or Android Studio to the running game, after
/// *Attach debugger* copied the address. Nothing here is the address.
Future<void> showAttachGuide(BuildContext context) {
  final c = PrColors.of(context);
  Widget steps(String title, List<String> steps) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: PrSpacing.s2,
    children: [
      Text(title, style: PrText.heading.copyWith(color: c.textPrimary)),
      for (final (index, step) in steps.indexed)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: PrSpacing.s2,
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '${index + 1}.',
                style: PrText.small.copyWith(color: c.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                step,
                style: PrText.small.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
    ],
  );
  return showFsDialog<void>(
    context,
    dialog: PrDialog(
      title: 'Attach your IDE to the game',
      width: PrDialogWidth.form,
      content: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: PrSpacing.s4,
              children: [
                Text(
                  'The game’s address is on your clipboard. It lets a '
                  'debugger take full control of the game, so Pyro never '
                  'shows or writes it.',
                  style: PrText.small.copyWith(color: c.textSecondary),
                ),
                steps('VS Code', attachGuideVsCode),
                steps('Android Studio', attachGuideAndroidStudio),
              ],
            ),
          ),
        ),
      ),
      primary: const PrDialogAction(label: 'OK'),
    ),
  );
}
