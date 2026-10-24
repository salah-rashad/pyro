import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';

/// The classes of [name]'s lines, `other` left out.
List<GeneratorLine> classes(String name) => [
  for (final line in recorded(name))
    if (classifyGeneratorLine(line) != GeneratorLine.other)
      classifyGeneratorLine(line),
];

void main() {
  const building = GeneratorLine.building;
  const succeeded = GeneratorLine.succeeded;

  group('the recorded output', () {
    test('a first build, then a second after a save', () {
      expect(classes('build-runner-watch.txt'), [
        building, // 0s pyro_scan …;
        building, // 0s pyro_aggregate …;
        succeeded,
        building, // Starting build #2.
        building,
        building,
        succeeded,
      ]);
    });

    test('a watcher taken over ends with the takeover line', () {
      final all = classes('build-runner-takeover.txt');
      expect(all.last, GeneratorLine.takeover);
      expect(all.where((c) => c == succeeded), hasLength(2));
    });

    test('a stopped watcher prints the same takeover line', () {
      expect(classes('build-runner-stop.txt'), [
        building,
        building,
        succeeded,
        GeneratorLine.takeover,
      ]);
    });

    test('the second run waits, then builds', () {
      expect(classes('build-runner-waiting.txt'), [
        GeneratorLine.waiting,
        building,
        building,
        succeeded,
      ]);
    });

    test(
      'a syntax error is a severe line, then a failed build, then a fix',
      () {
        expect(classes('build-runner-error.txt'), [
          building,
          building,
          succeeded,
          building, // Starting build #2.
          building,
          GeneratorLine.severe,
          building,
          GeneratorLine.failed,
          building, // Starting build #3.
          building,
          building,
          succeeded,
          GeneratorLine.takeover,
        ]);
      },
    );
  });

  group('single lines', () {
    final cases = {
      'Starting build #2.': building,
      '  0s pyro_generator:pyro_scan on 9 inputs; lib/a.dart': building,
      '  0s pyro_generator:pyro_aggregate on 1 input; lib/\$lib\$': building,
      '  Built with build_runner/aot in 3s; wrote 1 output.': succeeded,
      '  Built with build_runner/aot in 0s; wrote 0 outputs.': succeeded,
      '  Failed to build with build_runner/aot in 0s; wrote 2 outputs.':
          GeneratorLine.failed,
      'E pyro_generator:pyro_scan on lib/a.dart:': GeneratorLine.severe,
      'Exiting as requested by another build_runner process.':
          GeneratorLine.takeover,
      'Waiting for already-running build_runner.': GeneratorLine.waiting,
    };
    for (final MapEntry(key: line, value: kind) in cases.entries) {
      test('"$line" is $kind', () {
        expect(classifyGeneratorLine(line), kind);
      });
    }

    for (final line in [
      '',
      '  11:27: Expected an identifier.',
      '  0s pyro_generator:pyro_scan on 9 inputs: 9 skipped',
      '  3s pyro_generator:pyro_scan on 9 inputs: 1 same; spent 2s analyzing',
      'Unhandled exception:',
      'Built something else entirely',
      '[INFO] Succeeded after 1.2s with 3 outputs',
    ]) {
      test('"$line" is other', () {
        expect(classifyGeneratorLine(line), GeneratorLine.other);
      });
    }
  });

  group('severe lines', () {
    test('give their file', () {
      expect(
        severeFile('E pyro_generator:pyro_scan on lib/behaviors/spin.dart:'),
        'lib/behaviors/spin.dart',
      );
      expect(severeFile('E something without a file'), isNull);
    });
  });
}
