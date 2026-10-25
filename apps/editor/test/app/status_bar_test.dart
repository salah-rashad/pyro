import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/providers.dart';
import 'package:pyro/app/status_bar.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

const _project = ProjectState(
  root: '/proj',
  sdk: SdkInfo(version: '3.44.2', source: SdkSource.flutterRoot, root: '/sdk'),
  compatibility: RuntimeCompatibility(
    status: RuntimeCompatStatus.ok,
    foundVersion: '0.0.1',
    readsUpTo: 1,
  ),
);

final _catalog = TypeCatalog(
  types: IMap(),
  problems: IList(),
  origin: const ManifestAbsent(),
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    GeneratorState? generator, {
    VoidCallback? onStart,
    double width = 1280,
  }) async {
    tester.view.physicalSize = Size(width, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 24,
            child: StatusBar(
              project: _project,
              catalog: _catalog,
              generator: generator,
              onStartGenerator: onStart,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('keeps the SDK, Runtime and catalog items', (tester) async {
    await pump(tester, const GeneratorState(GeneratorStatus.upToDate));
    expect(find.text('Flutter 3.44.2'), findsOneWidget);
    expect(find.text('pyro_runtime 0.0.1'), findsOneWidget);
    expect(find.text('Built-in types only'), findsOneWidget);
  });

  testWidgets('has no generator item before the first state', (tester) async {
    await pump(tester, null);
    expect(find.textContaining('Generat'), findsNothing);
    expect(find.text('Up to date'), findsNothing);
  });

  group('shows each state', () {
    final cases = {
      GeneratorStatus.starting: 'Generator: starting',
      GeneratorStatus.generating: 'Generating…',
      GeneratorStatus.upToDate: 'Up to date',
      GeneratorStatus.external: 'External build_runner',
    };
    for (final MapEntry(key: status, value: text) in cases.entries) {
      testWidgets('$status', (tester) async {
        await pump(tester, GeneratorState(status));
        expect(find.text(text), findsOneWidget);
        expect(find.widgetWithText(PrButton, 'Start'), findsNothing);
      });
    }

    testWidgets('notSetUp, with its reason', (tester) async {
      await pump(
        tester,
        const GeneratorState(
          GeneratorStatus.notSetUp,
          reason: 'build_runner 2.13.9 is too old; Pyro needs 2.14.0.',
        ),
      );
      expect(find.textContaining('Generator: not set up'), findsOneWidget);
      expect(find.textContaining('2.13.9'), findsOneWidget);
      expect(find.widgetWithText(PrButton, 'Start'), findsNothing);
    });

    testWidgets('notSetUp survives a narrow window', (tester) async {
      await pump(
        tester,
        const GeneratorState(
          GeneratorStatus.notSetUp,
          reason:
              'build_runner is not in the project: add it to dev_dependencies '
              'and run `flutter pub get`.',
        ),
        width: 700,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Generator: not set up'), findsOneWidget);
    });

    testWidgets('error, opening its file and message', (tester) async {
      await pump(
        tester,
        const GeneratorState(
          GeneratorStatus.error,
          file: 'lib/behaviors/spin.dart',
          message: '11:27: Expected an identifier.',
        ),
      );
      expect(find.text('Generator error'), findsOneWidget);
      await tester.tap(find.text('Generator error'));
      await tester.pumpAndSettle();
      expect(find.text('lib/behaviors/spin.dart'), findsOneWidget);
      expect(find.text('11:27: Expected an identifier.'), findsOneWidget);
      expect(find.textContaining('Console'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('lib/behaviors/spin.dart'), findsNothing);
    });

    testWidgets('stopped, with Start calling start()', (tester) async {
      var starts = 0;
      await pump(
        tester,
        const GeneratorState(GeneratorStatus.stopped),
        onStart: () => starts++,
      );
      expect(find.text('Generator stopped'), findsOneWidget);
      await tester.tap(find.widgetWithText(PrButton, 'Start'));
      await tester.pump();
      expect(starts, 1);
    });
  });
}
