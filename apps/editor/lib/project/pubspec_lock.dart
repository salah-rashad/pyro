import 'package:file/file.dart';
import 'package:yaml/yaml.dart';

/// The `pubspec.lock` that resolved [projectPath]'s packages.
///
/// A project has its own, unless it is a member of a pub workspace
/// (`resolution: workspace`), whose one lock sits in the workspace root. So
/// without its own lock the nearest folder above that declares a
/// `workspace:` in its `pubspec.yaml` and holds a lock is used. The file may
/// not exist: the result is where it would be.
File findPubspecLock(FileSystem fileSystem, String projectPath) {
  final context = fileSystem.path;
  final own = fileSystem.file(context.join(projectPath, 'pubspec.lock'));
  if (own.existsSync()) return own;
  var folder = context.dirname(context.normalize(projectPath));
  while (true) {
    final lock = fileSystem.file(context.join(folder, 'pubspec.lock'));
    if (lock.existsSync() && _isWorkspaceRoot(fileSystem, folder)) return lock;
    final parent = context.dirname(folder);
    if (parent == folder) return own;
    folder = parent;
  }
}

bool _isWorkspaceRoot(FileSystem fileSystem, String folder) {
  final pubspec = fileSystem.file(fileSystem.path.join(folder, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    return yaml is Map && yaml['workspace'] is List;
  } on Object {
    return false;
  }
}
