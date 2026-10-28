import 'package:file/file.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

/// The `pubspec.lock` that resolved [projectPath]'s packages.
///
/// A project has its own, unless it is a member of a pub workspace, whose one
/// lock sits in the workspace root. So without its own lock the nearest
/// folder above that holds a lock and lists the project in its `workspace:`
/// is used, provided the project resolves as a workspace member
/// (`resolution: workspace`, from its `pubspec_overrides.yaml` when that sets
/// it). A folder merely inside a workspace root is not a member, and its
/// packages were not resolved by that lock. The file may not exist: the
/// result is where it would be.
File findPubspecLock(FileSystem fileSystem, String projectPath) {
  final context = fileSystem.path;
  final project = context.normalize(context.absolute(projectPath));
  final own = fileSystem.file(context.join(projectPath, 'pubspec.lock'));
  if (own.existsSync()) return own;
  if (!_resolvesInWorkspace(fileSystem, project)) return own;
  var folder = context.dirname(project);
  while (true) {
    final lock = fileSystem.file(context.join(folder, 'pubspec.lock'));
    if (lock.existsSync() && _isMemberOf(fileSystem, folder, project)) {
      return lock;
    }
    final parent = context.dirname(folder);
    if (parent == folder) return own;
    folder = parent;
  }
}

/// Whether [project]'s own pubspec says `resolution: workspace`; its
/// `pubspec_overrides.yaml` overrides `pubspec.yaml` where it sets it.
bool _resolvesInWorkspace(FileSystem fileSystem, String project) {
  final context = fileSystem.path;
  for (final name in ['pubspec_overrides.yaml', 'pubspec.yaml']) {
    final yaml = _readMap(fileSystem.file(context.join(project, name)));
    if (yaml != null && yaml.containsKey('resolution')) {
      return yaml['resolution'] == 'workspace';
    }
  }
  return false;
}

/// Whether [project] is a workspace member of [folder], directly or through
/// nested workspaces: each hop up the chain is a pubspec whose `workspace:`
/// lists the folder below it, up to [folder] itself.
bool _isMemberOf(FileSystem fileSystem, String folder, String project) {
  final context = fileSystem.path;
  final root = context.normalize(context.absolute(folder));
  var member = context.normalize(context.absolute(project));
  if (member == root) return false;
  while (member != root) {
    var hop = context.dirname(member);
    while (hop != root && !_listsMember(fileSystem, hop, member)) {
      final parent = context.dirname(hop);
      if (parent == hop) return false;
      hop = parent;
    }
    if (!_listsMember(fileSystem, hop, member)) return false;
    member = hop;
  }
  return true;
}

/// Whether the `workspace:` of the pubspec in [folder] lists [project]; its
/// `pubspec_overrides.yaml` overrides `pubspec.yaml` where it declares the
/// key, even with a non-list value (which lists nothing).
bool _listsMember(FileSystem fileSystem, String folder, String project) {
  final context = fileSystem.path;
  final entries = _workspaceEntries(fileSystem, folder);
  if (entries == null) return false;
  final relative = context.relative(project, from: folder);
  return entries.whereType<String>().any((entry) {
    return Glob(entry, context: context).matches(relative);
  });
}

/// The declared `workspace:` entries of the pubspec in [folder], or null when
/// neither pubspec declares the key. A declared non-list value is present but
/// empty, so it overrides without listing anything.
List<dynamic>? _workspaceEntries(FileSystem fileSystem, String folder) {
  final context = fileSystem.path;
  for (final name in ['pubspec_overrides.yaml', 'pubspec.yaml']) {
    final yaml = _readMap(fileSystem.file(context.join(folder, name)));
    if (yaml != null && yaml.containsKey('workspace')) {
      final value = yaml['workspace'];
      return value is List ? value : const [];
    }
  }
  return null;
}

Map<dynamic, dynamic>? _readMap(File file) {
  if (!file.existsSync()) return null;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    return yaml is Map ? yaml : null;
  } on Object {
    return null;
  }
}
