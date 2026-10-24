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
}
