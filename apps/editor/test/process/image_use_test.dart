import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemEvent, FileSystemModifyEvent;

import 'package:fake_async/fake_async.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/src/image_use.dart';

import 'fake_process.dart';

const _quiet = Duration(milliseconds: 150);

/// A Scene whose Nodes use [sprite] as a Sprite Node's image, [behavior] as an
/// Image-path Override of an entity's Behavior and [custom] as one of a
/// Custom component's fields (each may be null).
String scene({String? sprite, String? behavior, String? custom}) => jsonEncode({
  'schemaVersion': 1,
  'rootId': 'root',
  'nodes': {
    'root': {
      'kind': 'root',
      'childIds': ['ship', 'title'],
    },
    'ship': {
      'kind': 'entity',
      'name': 'ship',
      'childIds': [if (sprite != null) 'hull'],
      'transform': _transform,
      'behaviors': [
        {
          'type': 'Glow',
          'fields': {
            'size': 3,
            if (behavior != null) 'texture': {'asset': behavior},
          },
        },
      ],
    },
    if (sprite != null)
      'hull': {
        'kind': 'sprite',
        'name': 'hull',
        'props': {'image': sprite},
        'transform': _transform,
      },
    'title': {
      'kind': 'custom',
      'name': 'title',
      'type': 'Banner',
      'transform': _transform,
      'fields': {
        'message': 'plain text, assets/images/not-an-image.png',
        if (custom != null) 'background': {'asset': custom},
      },
    },
  },
});

const _transform = {
  'anchor': 'center',
  'angle': 0,
  'position': [0, 0],
  'scale': [1, 1],
  'size': [64, 64],
};

void main() {
  late MemoryFileSystem fs;
  // A broadcast stream the test drives; nothing to release.
  // ignore: close_sinks
  late StreamController<FileSystemEvent> changes;
  late List<Set<String>> raised;

  setUp(() {
    fs = projectFileSystem();
    fs.file('$projectPath/pubspec.yaml').writeAsStringSync('''
name: game
flutter:
  assets:
    - assets/images/
    - assets/scenes/
''');
    fs.directory('$projectPath/assets/images').createSync(recursive: true);
    for (final image in ['ship', 'glow', 'bg', 'unused']) {
      fs.file('$projectPath/assets/images/$image.png').writeAsStringSync(image);
    }
    fs
        .file('$projectPath/assets/scenes/level1.scene.json')
        .writeAsStringSync(
          scene(
            sprite: 'assets/images/ship.png',
            behavior: 'assets/images/glow.png',
          ),
        );
    fs.file('$projectPath/assets/scenes/nested/menu.scene.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(scene(custom: 'assets/images/bg.png'));
    changes = StreamController<FileSystemEvent>.broadcast();
    raised = [];
  });

  Future<ImageUse> started() async {
    final use = ImageUse(
      fileSystem: fs,
      projectPath: projectPath,
      watch: (_) => changes.stream,
      onChanged: raised.add,
    );
    await use.start();
    return use;
  }

  void modify(String relative) =>
      changes.add(FileSystemModifyEvent('$projectPath/$relative', false, true));

  test(
    'collects the images Sprite Nodes and Image-path Overrides name',
    () async {
      final use = await started();
      expect(use.images, {
        'assets/images/ship.png',
        'assets/images/glow.png',
        'assets/images/bg.png',
      });
      use.close();
    },
  );

  test('a scene that cannot be read adds nothing and breaks nothing', () async {
    fs
        .file('$projectPath/assets/scenes/broken.scene.json')
        .writeAsStringSync('{ not json');
    fs
        .file('$projectPath/assets/scenes/newer.scene.json')
        .writeAsStringSync(
          jsonEncode({
            'schemaVersion': 99,
            'rootId': 'x',
            'nodes': <String, Object?>{},
          }),
        );
    final use = await started();
    expect(use.images, hasLength(3));
    use.close();
  });

  test('a changed image a Scene names raises ImageChanged once per batch', () {
    fakeAsync((async) {
      late ImageUse use;
      unawaited(started().then((u) => use = u));
      async.flushMicrotasks();
      modify('assets/images/ship.png');
      async.elapse(const Duration(milliseconds: 100));
      modify('assets/images/ship.png');
      modify('assets/images/glow.png');
      async.elapse(_quiet);
      expect(raised, [
        {'assets/images/ship.png', 'assets/images/glow.png'},
      ]);
      expect(use.changed, {'assets/images/ship.png', 'assets/images/glow.png'});
      use.close();
    });
  });

  test('an image no Scene names raises nothing', () {
    fakeAsync((async) {
      late ImageUse use;
      unawaited(started().then((u) => use = u));
      async.flushMicrotasks();
      modify('assets/images/unused.png');
      modify('assets/images/new-file.png');
      modify('assets/scenes/readme.txt');
      async.elapse(const Duration(seconds: 5));
      expect(raised, isEmpty);
      expect(use.changed, isEmpty);
      use.close();
    });
  });

  test('the set is rebuilt when a Scene file changes', () {
    fakeAsync((async) {
      late ImageUse use;
      unawaited(started().then((u) => use = u));
      async.flushMicrotasks();
      // The Scene now names unused.png instead of ship.png.
      fs
          .file('$projectPath/assets/scenes/level1.scene.json')
          .writeAsStringSync(scene(sprite: 'assets/images/unused.png'));
      modify('assets/scenes/level1.scene.json');
      async.elapse(_quiet);
      expect(use.images, {'assets/images/unused.png', 'assets/images/bg.png'});
      expect(
        raised,
        isEmpty,
        reason: 'a Scene change is Hot-swapped, not this',
      );
      modify('assets/images/ship.png');
      async.elapse(_quiet);
      expect(raised, isEmpty);
      modify('assets/images/unused.png');
      async.elapse(_quiet);
      expect(raised, hasLength(1));
      use.close();
    });
  });

  test(
    'clear() (a restart) forgets the changes and reads the Scenes again',
    () {
      fakeAsync((async) {
        late ImageUse use;
        unawaited(started().then((u) => use = u));
        async.flushMicrotasks();
        modify('assets/images/bg.png');
        async.elapse(_quiet);
        expect(use.changed, {'assets/images/bg.png'});
        fs
            .file('$projectPath/assets/scenes/nested/menu.scene.json')
            .writeAsStringSync(scene());
        unawaited(use.clear());
        async.flushMicrotasks();
        expect(use.changed, isEmpty);
        expect(use.images, {
          'assets/images/ship.png',
          'assets/images/glow.png',
        });
        modify('assets/images/bg.png');
        async.elapse(const Duration(seconds: 1));
        expect(
          raised,
          hasLength(1),
          reason: 'only the change before the restart',
        );
        use.close();
      });
    },
  );

  test('close() stops watching and drops a batch in progress', () {
    fakeAsync((async) {
      late ImageUse use;
      unawaited(started().then((u) => use = u));
      async.flushMicrotasks();
      expect(changes.hasListener, isTrue);
      modify('assets/images/ship.png');
      async.elapse(const Duration(milliseconds: 100));
      use.close();
      async.elapse(const Duration(seconds: 1));
      expect(raised, isEmpty);
      expect(changes.hasListener, isFalse);
    });
  });

  test('a project without asset folders watches nothing', () async {
    fs.file('$projectPath/pubspec.yaml').writeAsStringSync('name: game\n');
    fs.directory('$projectPath/assets').deleteSync(recursive: true);
    final use = await started();
    expect(use.images, isEmpty);
    expect(changes.hasListener, isFalse);
    use.close();
  });
}
