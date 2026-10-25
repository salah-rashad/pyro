import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/project/project.dart';

void main() {
  group('detectSdk (T006, FR-003, §9.1)', () {
    test('reads the version from .fvmrc first', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/proj').createSync(recursive: true);
      fs.file('/proj/.fvmrc').writeAsStringSync('{"flutter": "3.44.2"}');
      final info = await detectSdk(
        '/proj',
        fileSystem: fs,
        flutterRoot: '/sdk',
        env: (_) => '/sdk',
      );
      expect(info, const SdkInfo(version: '3.44.2', source: SdkSource.fvm));
    });

    test('falls back to .fvm/fvm_config.json', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/proj/.fvm').createSync(recursive: true);
      fs
          .file('/proj/.fvm/fvm_config.json')
          .writeAsStringSync('{"flutterVersion": "3.44.0"}');
      final info = await detectSdk('/proj', fileSystem: fs, env: (_) => null);
      expect(info, const SdkInfo(version: '3.44.0', source: SdkSource.fvm));
    });

    test('falls back to .fvm/flutter_sdk/version', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/proj/.fvm/flutter_sdk').createSync(recursive: true);
      fs.file('/proj/.fvm/flutter_sdk/version').writeAsStringSync('3.44.2\n');
      final info = await detectSdk('/proj', fileSystem: fs, env: (_) => null);
      expect(
        info,
        const SdkInfo(
          version: '3.44.2',
          source: SdkSource.fvm,
          root: '/proj/.fvm/flutter_sdk',
        ),
      );
      expect(flutterExecutable(info), '/proj/.fvm/flutter_sdk/bin/flutter');
    });

    test('an unreadable .fvmrc falls through to FLUTTER_ROOT', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/proj').createSync(recursive: true);
      fs.directory('/sdk').createSync(recursive: true);
      fs.file('/proj/.fvmrc').writeAsStringSync('{broken');
      fs.file('/sdk/version').writeAsStringSync('3.44.2\n');
      final info = await detectSdk('/proj', fileSystem: fs, env: (_) => '/sdk');
      expect(
        info,
        const SdkInfo(
          version: '3.44.2',
          source: SdkSource.flutterRoot,
          root: '/sdk',
        ),
      );
      expect(flutterExecutable(info), '/sdk/bin/flutter');
      expect(dartExecutable(info), '/sdk/bin/dart');
    });

    test(
      'FLUTTER_ROOT without a readable version file falls to PATH',
      () async {
        final fs = MemoryFileSystem.test();
        final info = await detectSdk(
          '/proj',
          fileSystem: fs,
          env: (_) => '/no-sdk-here',
          pathVersion: () async => '3.44.2',
        );
        expect(info, const SdkInfo(version: '3.44.2', source: SdkSource.path));
      },
    );

    test('no SDK anywhere is none, never an error', () async {
      final fs = MemoryFileSystem.test();
      final info = await detectSdk(
        '/proj',
        fileSystem: fs,
        env: (_) => null,
        pathVersion: () async => null,
      );
      expect(info, SdkInfo.none);
    });
  });
}
