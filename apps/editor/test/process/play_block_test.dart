import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

void main() {
  group('PlayBlock.of', () {
    PlayBlock? of({
      String? projectError,
      bool hasSdk = true,
      String? runtimeProblem,
      bool hasMacosFolder = true,
    }) => PlayBlock.of(
      projectError: projectError,
      hasSdk: hasSdk,
      runtimeProblem: runtimeProblem,
      hasMacosFolder: hasMacosFolder,
    );

    test('is null when nothing blocks Play', () {
      expect(of(), isNull);
    });

    test('a project that failed to open comes first, with its own error', () {
      final block = of(
        projectError: 'pubspec.yaml is not valid YAML',
        hasSdk: false,
        runtimeProblem: 'pyro_runtime: not found',
        hasMacosFolder: false,
      )!;
      expect(block.reason, contains('project'));
      expect(block.fix, 'pubspec.yaml is not valid YAML');
    });

    test('then no Flutter SDK, naming where Pyro looked', () {
      final block = of(
        hasSdk: false,
        runtimeProblem: 'pyro_runtime: not found',
        hasMacosFolder: false,
      )!;
      expect(block.reason, contains('Flutter SDK'));
      expect(block.fix, contains('.fvmrc'));
      expect(block.fix, contains('FLUTTER_ROOT'));
      expect(block.fix, contains('PATH'));
    });

    test('then the Runtime check, with its message', () {
      final block = of(
        runtimeProblem: 'pyro_runtime 0.0.0 — too old to read saves',
        hasMacosFolder: false,
      )!;
      expect(block.reason, contains('Runtime'));
      expect(block.fix, contains('pyro_runtime 0.0.0 — too old to read saves'));
    });

    test('then a missing macos/ folder, with the command that adds it', () {
      final block = of(hasMacosFolder: false)!;
      expect(block.reason, contains('macos/'));
      expect(block.fix, contains('flutter create --platforms=macos .'));
    });

    test('says what it is in toString', () {
      final block = of(hasMacosFolder: false)!;
      expect('$block', contains(block.reason));
    });
  });
}
