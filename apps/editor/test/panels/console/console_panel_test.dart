import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/panels/panels.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';

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
    expect(row('generator  building'), findsOneWidget);
    expect(row('game       hello from the game'), findsOneWidget);
    expect(row('pyro       Play started'), findsOneWidget);
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
    await tester.pump();
    await tester.pump();
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
}
