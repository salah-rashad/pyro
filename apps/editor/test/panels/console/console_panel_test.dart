import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/panels/panels.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../../helpers/pump.dart';

void main() {
  late ProviderContainer container;
  late ConsoleBuffer buffer;

  setUp(() {
    container = ProviderContainer();
    buffer = container.read(consoleBufferProvider);
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester) => pumpPyro(
    tester,
    const SizedBox(height: 300, child: ConsolePanel()),
    width: 600,
    scope: (child) =>
        UncontrolledProviderScope(container: container, child: child),
  );

  /// Lets the buffer's 50 ms notification fire and the panel rebuild.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  }

  Finder row(String text) => find.textContaining(text, findRichText: true);

  testWidgets('shows lines in order with their source', (tester) async {
    await pump(tester);
    buffer
      ..add('building', source: ConsoleSource.generator)
      ..add('hello from the game', source: ConsoleSource.game)
      ..add('Play started', source: ConsoleSource.pyro);
    await settle(tester);
    final generator = tester.getTopLeft(row('building'));
    final game = tester.getTopLeft(row('hello from the game'));
    final pyro = tester.getTopLeft(row('Play started'));
    expect(generator.dy, lessThan(game.dy));
    expect(game.dy, lessThan(pyro.dy));
    // The source is a label beside the text, which wraps on its own.
    for (final label in ['generator', 'game', 'pyro']) {
      expect(
        find.textContaining(label, findRichText: true),
        findsNWidgets(label == 'game' ? 2 : 1),
        reason: 'the label, and for "game" the line that says "the game"',
      );
    }
    expect(
      tester.getTopLeft(row('building')).dx,
      tester.getTopLeft(row('hello from the game')).dx,
      reason: 'the texts line up in one column',
    );
  });

  testWidgets('filters by each source, and All shows every line again', (
    tester,
  ) async {
    await pump(tester);
    buffer
      ..add('gen line', source: ConsoleSource.generator)
      ..add('game line', source: ConsoleSource.game)
      ..add('pyro line', source: ConsoleSource.pyro);
    await settle(tester);
    for (final (label, kept) in [
      ('Generator', 'gen line'),
      ('Game', 'game line'),
      ('Pyro', 'pyro line'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
      for (final text in ['gen line', 'game line', 'pyro line']) {
        expect(row(text), text == kept ? findsOneWidget : findsNothing);
      }
    }
    await tester.tap(find.text('All'));
    await tester.pump();
    for (final text in ['gen line', 'game line', 'pyro line']) {
      expect(row(text), findsOneWidget);
    }
  });

  testWidgets('Clear empties the list', (tester) async {
    await pump(tester);
    buffer.add('something', source: ConsoleSource.game);
    await settle(tester);
    await tester.tap(find.byTooltip('Clear'));
    await settle(tester);
    expect(row('something'), findsNothing);
    expect(buffer.lines, isEmpty);
    expect(find.text('No output yet. Press Play to run the game.'), findsOne);
  });

  testWidgets('follows the tail until scrolled up, then resumes on request', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 200; i++) {
      buffer.add('line $i', source: ConsoleSource.game);
    }
    await settle(tester);
    expect(row('line 199'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    buffer.add('line 200', source: ConsoleSource.game);
    await settle(tester);
    expect(row('line 200'), findsNothing, reason: 'scrolled up: stays put');

    await tester.tap(find.byTooltip('Follow the newest line'));
    // Rows differ in height, so the end is settled over a few frames.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(row('line 200'), findsOneWidget);
    buffer.add('line 201', source: ConsoleSource.game);
    await settle(tester);
    expect(row('line 201'), findsOneWidget);
  });

  testWidgets('colours an error line differently from an info line', (
    tester,
  ) async {
    await pump(tester);
    buffer
      ..add('all fine', source: ConsoleSource.game)
      ..add(
        'it broke',
        source: ConsoleSource.generator,
        severity: ConsoleSeverity.error,
      );
    await settle(tester);
    Color? colorOf(String text) =>
        tester.widget<RichText>(row(text)).text.style?.color;
    expect(colorOf('it broke'), c.error);
    expect(colorOf('all fine'), isNot(c.error));
  });

  testWidgets('5,000 lines at once render only the visible rows', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 5000; i++) {
      buffer.add('flood $i', source: ConsoleSource.game);
    }
    await settle(tester);
    final rows = find.textContaining('flood ', findRichText: true);
    expect(rows.evaluate().length, lessThan(40));
    expect(buffer.lines.length, 5000);
    for (var i = 0; i < 6000; i++) {
      buffer.add('more $i', source: ConsoleSource.game);
    }
    await settle(tester);
    expect(buffer.lines.length, PlayDefaults.consoleCapacity);
  });

  group('long lines and copying', () {
    final longLine = [for (var i = 0; i < 60; i++) 'word$i'].join(' ');
    String? copied;

    setUp(() => copied = null);

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('a long line wraps and shows in full', (tester) async {
      await pump(tester);
      buffer.add('short', source: ConsoleSource.game);
      buffer.add(longLine, source: ConsoleSource.game);
      await settle(tester);
      final text = tester.widget<Text>(find.text(longLine));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final shortHeight = tester.getSize(find.text('short')).height;
      expect(
        tester.getSize(find.text(longLine)).height,
        greaterThan(shortHeight * 2),
        reason: 'several rows of text, not one cut with an ellipsis',
      );
    });

    testWidgets('the newest line stays in view when rows wrap', (tester) async {
      await pump(tester);
      for (var i = 0; i < 100; i++) {
        buffer.add('$i $longLine', source: ConsoleSource.game);
      }
      buffer.add('the last line', source: ConsoleSource.pyro);
      await settle(tester);
      await tester.pump();
      expect(find.text('the last line'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('the last line')).dy,
        lessThanOrEqualTo(tester.getBottomLeft(find.byType(ListView)).dy),
      );
      buffer.add('one more', source: ConsoleSource.pyro);
      await settle(tester);
      await tester.pump();
      expect(find.text('one more'), findsOneWidget);
    });

    Future<String?> selectAllAndCopy(WidgetTester tester) async {
      copied = null;
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      // ignore: deprecated_member_use
      region.copySelection(SelectionChangedCause.toolbar);
      return copied;
    }

    // Selecting costs a build per streamed row, which broke the flood's frame
    // budget (SC-006, measured in profile mode), so live rows are plain text.
    // *Pause to select text* freezes the view into a selectable snapshot of
    // the latest lines; *Resume* goes back to the live one.
    testWidgets('live rows are not selectable', (tester) async {
      await pump(tester);
      buffer.add('streaming line', source: ConsoleSource.game);
      await settle(tester);
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(SelectableRegion), findsNothing);
    });

    testWidgets(
      'Pause freezes the view into selectable text, labels left out',
      (tester) async {
        mockClipboard(tester);
        await pump(tester);
        buffer
          ..add('first line', source: ConsoleSource.generator)
          ..add(longLine, source: ConsoleSource.game);
        await settle(tester);
        await tester.tap(find.byTooltip('Pause to select text'));
        await settle(tester);
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(find.text(longLine), findsOneWidget, reason: 'wrapped, in full');
        final text = await selectAllAndCopy(tester);
        expect(text, contains('first line'));
        expect(text, contains(longLine));
        expect(text, isNot(contains('generator')));
        expect(text, isNot(contains('game')));

        // The snapshot stands still while output goes on.
        buffer.add('arrived while paused', source: ConsoleSource.game);
        await settle(tester);
        expect(find.text('arrived while paused'), findsNothing);
        expect(find.byTooltip('Resume'), findsOneWidget);

        await tester.tap(find.byTooltip('Resume'));
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        expect(find.byType(SelectionArea), findsNothing);
        expect(find.text('arrived while paused'), findsOneWidget);
        expect(find.byTooltip('Pause to select text'), findsOneWidget);
      },
    );

    testWidgets(
      'the snapshot holds the latest 1,000 lines, newest at the end',
      (tester) async {
        mockClipboard(tester);
        await pump(tester);
        for (var i = 0; i < 1500; i++) {
          buffer.add('numbered $i', source: ConsoleSource.game);
        }
        await settle(tester);
        await tester.tap(find.byTooltip('Pause to select text'));
        await tester.pump();
        await tester.pump();
        // The newest line is the one in view, as with the live tail.
        expect(find.text('numbered 1499'), findsOneWidget);
        expect(find.text('numbered 499'), findsNothing);
      },
    );

    testWidgets('Pause is off while the Console is empty', (tester) async {
      await pump(tester);
      final button = tester.widget<PrIconButton>(
        find.ancestor(
          of: find.byTooltip('Pause to select text'),
          matching: find.byType(PrIconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Copy all copies every line of what is shown, labelled', (
      tester,
    ) async {
      mockClipboard(tester);
      await pump(tester);
      buffer
        ..add('from the generator', source: ConsoleSource.generator)
        ..add('from the game', source: ConsoleSource.game)
        ..add(longLine, source: ConsoleSource.game);
      await settle(tester);
      await tester.tap(find.byTooltip('Copy all'));
      await tester.pump();
      expect(
        copied,
        'generator  from the generator\ngame  from the game\ngame  $longLine',
      );
      await tester.tap(find.text('Game'));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy all'));
      await tester.pump();
      expect(copied, 'game  from the game\ngame  $longLine');
    });

    testWidgets('Copy all is off while the Console is empty', (tester) async {
      await pump(tester);
      final button = tester.widget<PrIconButton>(
        find.ancestor(
          of: find.byTooltip('Copy all'),
          matching: find.byType(PrIconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a copied line carries no auth code', (tester) async {
      mockClipboard(tester);
      await pump(tester);
      buffer.add(
        'attached to ws://127.0.0.1:5001/AbCdEf123456=/ws now',
        source: ConsoleSource.game,
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Copy all'));
      await tester.pump();
      expect(copied, contains('<auth-code>'));
      expect(copied, isNot(contains('AbCdEf123456')));
    });
  });
}
