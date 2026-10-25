import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/project/project.dart';

String _lock(String? buildRunner) =>
    '''
packages:
  analyzer:
    dependency: transitive
    description:
      name: analyzer
    source: hosted
    version: "9.0.0"
${buildRunner == null ? '' : '''
  build_runner:
    dependency: "direct dev"
    description:
      name: build_runner
    source: hosted
    version: "$buildRunner"
'''}sdks:
  dart: ">=3.0.0 <4.0.0"
''';

void main() {
  late MemoryFileSystem fs;

  BuildRunnerVersion read() => BuildRunnerVersion.of('/proj', fileSystem: fs);

  void writeLock(String text) =>
      fs.file('/proj/pubspec.lock').writeAsStringSync(text);

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/proj').createSync();
  });

  test('2.15.1 is ok', () {
    writeLock(_lock('2.15.1'));
    final result = read();
    expect(result, isA<BuildRunnerOk>());
    expect((result as BuildRunnerOk).version, '2.15.1');
    expect(result.reason, isNull);
  });

  test('2.14.0 is ok: the boundary', () {
    writeLock(_lock('2.14.0'));
    expect(read(), isA<BuildRunnerOk>());
  });

  test('2.13.9 is too old, naming what is needed', () {
    writeLock(_lock('2.13.9'));
    final result = read();
    expect(result, isA<BuildRunnerTooOld>());
    expect((result as BuildRunnerTooOld).found, '2.13.9');
    expect(result.required, '2.14.0');
    expect(result.reason, contains('2.13.9'));
    expect(result.reason, contains('2.14'));
  });

  test('a lock with no build_runner is absent', () {
    writeLock(_lock(null));
    final result = read();
    expect(result, isA<BuildRunnerAbsent>());
    expect(result.reason, contains('build_runner'));
  });

  test('no lock at all is absent', () {
    expect(read(), isA<BuildRunnerAbsent>());
  });

  test('a malformed lock is unknown, with the parse reason', () {
    writeLock('packages: [unclosed');
    final result = read();
    expect(result, isA<BuildRunnerUnknown>());
    expect(result.reason, isNotEmpty);
  });

  test('a lock that is not a map is unknown', () {
    writeLock('- just\n- a list\n');
    expect(read(), isA<BuildRunnerUnknown>());
  });

  test('a version that is not a version is unknown', () {
    writeLock(_lock('banana'));
    expect(read(), isA<BuildRunnerUnknown>());
  });

  test('never throws, even on a lock that is not text', () {
    // Not UTF-8: reading it as text throws.
    fs.file('/proj/pubspec.lock').writeAsBytesSync([0xff, 0xfe, 0xfd]);
    expect(read, returnsNormally);
    expect(read(), isA<BuildRunnerUnknown>());
  });

  test('a pre-release of the boundary version counts as the boundary', () {
    writeLock(_lock('2.14.0-dev.1'));
    expect(read(), isA<BuildRunnerOk>());
  });

  group('in a pub workspace the lock is the workspace root\'s', () {
    setUp(() {
      fs.file('/ws/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: ws\nworkspace:\n  - game\n');
      fs.file('/ws/game/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: game\nresolution: workspace\n');
    });

    BuildRunnerVersion readGame() =>
        BuildRunnerVersion.of('/ws/game', fileSystem: fs);

    test('a member without a lock of its own uses the root\'s', () {
      fs.file('/ws/pubspec.lock').writeAsStringSync(_lock('2.15.1'));
      expect(readGame(), isA<BuildRunnerOk>());
    });

    test('the root\'s lock is too old when it is', () {
      fs.file('/ws/pubspec.lock').writeAsStringSync(_lock('2.13.9'));
      expect(readGame(), isA<BuildRunnerTooOld>());
    });

    test('the member\'s own lock wins', () {
      fs.file('/ws/pubspec.lock').writeAsStringSync(_lock('2.13.9'));
      fs.file('/ws/game/pubspec.lock').writeAsStringSync(_lock('2.15.1'));
      expect(readGame(), isA<BuildRunnerOk>());
    });

    test('a folder above that is not a workspace is not searched', () {
      fs.file('/ws/pubspec.yaml').writeAsStringSync('name: plain\n');
      fs.file('/ws/pubspec.lock').writeAsStringSync(_lock('2.15.1'));
      expect(readGame(), isA<BuildRunnerAbsent>());
    });

    test('no lock anywhere is absent', () {
      expect(readGame(), isA<BuildRunnerAbsent>());
    });
  });
}
