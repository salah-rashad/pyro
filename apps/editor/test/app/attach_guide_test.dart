import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/attach_guide.dart';
import 'package:pyro_ui/pyro_ui.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: Builder(
          builder: (context) => Material(
            child: TextButton(
              onPressed: () => showAttachGuide(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('says the three things about VS Code (FR-029)', (tester) async {
    await open(tester);
    expect(find.text('VS Code'), findsOneWidget);
    // Select the game's device first.
    expect(find.textContaining("Pick the game's device first"), findsWidgets);
    expect(find.textContaining('macOS (desktop)'), findsWidgets);
    // Paste it into "Flutter: Attach to Process".
    expect(find.textContaining('Flutter: Attach to Process'), findsOneWidget);
    expect(find.textContaining('paste'), findsWidgets);
    // The stale "paused" state after a restart.
    expect(find.textContaining('paused'), findsOneWidget);
    expect(find.textContaining('hot restart'), findsOneWidget);
  });

  testWidgets('has Android Studio\'s steps', (tester) async {
    await open(tester);
    expect(find.text('Android Studio'), findsOneWidget);
    expect(find.textContaining('Flutter Attach'), findsOneWidget);
  });

  testWidgets('shows no address and closes with OK', (tester) async {
    await open(tester);
    expect(find.textContaining('ws://'), findsNothing);
    expect(find.textContaining('http://'), findsNothing);
    expect(find.textContaining('127.0.0.1'), findsNothing);
    expect(find.textContaining('=/'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('VS Code'), findsNothing);
  });
}
