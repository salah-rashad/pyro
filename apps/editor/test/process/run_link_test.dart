import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

final p = const LocalFileSystem().path;

void main() {
  late Directory root;
  late Directory support;
  late Directory project;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pyro_run_link_');
    support = Directory('${root.path}/support')..createSync();
    project = Directory('${root.path}/my_game')..createSync();
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    File('${project.path}/main.dart').writeAsStringSync('void main() {}\n');
  });

  tearDown(() {
    // A read-only folder cannot be emptied.
    Process.runSync('chmod', ['-R', 'u+w', root.path]);
    root.deleteSync(recursive: true);
  });

  String canonical(Directory directory) => directory.resolveSymbolicLinksSync();

  String projectId() =>
      sha1.convert(canonical(project).codeUnits).toString().substring(0, 12);

  test(
    'creates <support>/run/<id>/<name>-pyro pointing at the project',
    () async {
      final link = await RunLink.create(project.path, supportDir: support.path);
      expect(link, isNotNull);
      expect(
        link!.path,
        p.join(canonical(support), 'run', projectId(), 'my_game-pyro'),
      );
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      expect(
        Directory(link.path).resolveSymbolicLinksSync(),
        canonical(project),
      );
      // Through the link, the project's files are the project's own.
      expect(
        File('${link.path}/pubspec.yaml').readAsStringSync(),
        contains('my_game'),
      );
    },
  );

  test('the id is 12 hex digits of the canonical path\'s SHA-1', () async {
    final link = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    final id = p.basename(p.dirname(link.path));
    expect(id, matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(id, projectId());
  });

  test('the same project through a symlink gets the same id', () async {
    final alias = Link('${root.path}/alias')..createSync(project.path);
    final first = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    final second = (await RunLink.create(
      alias.path,
      supportDir: support.path,
    ))!;
    expect(p.dirname(second.path), p.dirname(first.path));
  });

  test('the link name never equals the project folder name', () async {
    for (final name in ['my_game', 'x', 'my_game-pyro']) {
      final dir = Directory('${root.path}/$name')..createSync(recursive: true);
      final link = (await RunLink.create(dir.path, supportDir: support.path))!;
      expect(p.basename(link.path), isNot(name));
      expect(p.basename(link.path), '$name-pyro');
    }
  });

  test('creating twice replaces the link', () async {
    final first = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    final second = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    expect(second.path, first.path);
    expect(FileSystemEntity.isLinkSync(second.path), isTrue);
  });

  test(
    'is null, not an exception, when the support folder is read-only',
    () async {
      Process.runSync('chmod', ['555', support.path]);
      final link = await RunLink.create(project.path, supportDir: support.path);
      expect(link, isNull);
    },
  );

  test('is null when the support folder cannot exist', () async {
    File('${root.path}/file').writeAsStringSync('');
    final link = await RunLink.create(
      project.path,
      supportDir: '${root.path}/file/inside',
    );
    expect(link, isNull);
  });

  test('remove deletes the link and never follows it', () async {
    final link = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    await link.remove();
    expect(
      FileSystemEntity.typeSync(link.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(project.existsSync(), isTrue);
    expect(File('${project.path}/main.dart').existsSync(), isTrue);
    expect(File('${project.path}/pubspec.yaml').existsSync(), isTrue);
    // A second remove is harmless.
    await link.remove();
  });

  test(
    'sweep removes every link of the project and never follows them',
    () async {
      final link = (await RunLink.create(
        project.path,
        supportDir: support.path,
      ))!;
      // A crash left another one behind, under an older name.
      Link('${p.dirname(link.path)}/old_name-pyro').createSync(project.path);
      await RunLink.sweep(project.path, supportDir: support.path);
      expect(Directory(p.dirname(link.path)).existsSync(), isFalse);
      expect(File('${project.path}/main.dart').existsSync(), isTrue);
      expect(File('${project.path}/pubspec.yaml').existsSync(), isTrue);
    },
  );

  test('sweep leaves other projects\' links alone', () async {
    final other = Directory('${root.path}/other')..createSync();
    final mine = (await RunLink.create(
      project.path,
      supportDir: support.path,
    ))!;
    final theirs = (await RunLink.create(
      other.path,
      supportDir: support.path,
    ))!;
    await RunLink.sweep(project.path, supportDir: support.path);
    expect(FileSystemEntity.isLinkSync(mine.path), isFalse);
    expect(FileSystemEntity.isLinkSync(theirs.path), isTrue);
  });

  test('sweep with nothing there does nothing', () async {
    await RunLink.sweep(project.path, supportDir: support.path);
    await RunLink.sweep(project.path, supportDir: '${root.path}/missing');
  });
}
