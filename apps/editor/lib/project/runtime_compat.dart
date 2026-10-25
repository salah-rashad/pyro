import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pyro_runtime/pyro_runtime.dart';
import 'package:yaml/yaml.dart';

import 'pubspec_lock.dart';

part 'runtime_compat.freezed.dart';

/// The outcome of checking the project's `pyro_runtime` against Pyro's
/// built-in compatibility table (FR-004, *Q49*).
enum RuntimeCompatStatus {
  /// The Runtime reads the `schemaVersion` Pyro writes; saving is normal.
  ok,

  /// The Runtime predates the current Scene version; saving is gated
  /// (FR-010) and the message names the versions.
  tooOld,

  /// The Runtime postdates every version Pyro's table knows — "needs a
  /// newer Pyro" (*Q105* parity).
  tooNew,

  /// No readable resolved version; `readsUpTo` is null and saving is
  /// blocked (*Q98*).
  unknown,
}

/// The compatibility check's result.
@freezed
sealed class RuntimeCompatibility with _$RuntimeCompatibility {
  /// Creates the result.
  const factory RuntimeCompatibility({
    required RuntimeCompatStatus status,

    /// The resolved `pyro_runtime` version, when one was found.
    required String? foundVersion,

    /// The newest `schemaVersion` the project's Runtime reads, for every
    /// save (`DocumentSession.save(runtimeReadsUpTo:)`); null when unknown.
    required int? readsUpTo,
  }) = _RuntimeCompatibility;

  /// The check before anything was read.
  static const unknown = RuntimeCompatibility(
    status: RuntimeCompatStatus.unknown,
    foundVersion: null,
    readsUpTo: null,
  );
}

/// Each `pyro_runtime` version Pyro knows, mapped to the newest
/// `schemaVersion` it reads (FR-004). This workspace's runtime is the
/// source for its own entry (`Scene.currentSchemaVersion`).
const Map<String, int> runtimeCompatTable = {'0.0.1': 1};

/// Reads the project's `pubspec.lock`, resolves its `pyro_runtime` version
/// and maps it through [runtimeCompatTable] (FR-004).
///
/// A workspace member's lock holds no entry for path-resolved packages
/// (the lock of this very repository, for instance), so when the lock has
/// no `pyro_runtime` the fallback reads the version out of the sibling
/// runtime package's own pubspec — the dev-time layout this repository
/// uses for `example/`.
Future<RuntimeCompatibility> checkRuntimeCompatibility(
  String projectRoot, {
  FileSystem fileSystem = const LocalFileSystem(),
}) async {
  final lock = findPubspecLock(fileSystem, projectRoot);
  String? version;
  if (lock.existsSync()) {
    try {
      final yaml = loadYaml(lock.readAsStringSync()) as Map;
      final Map<Object?, Object?>? entry =
          (yaml['packages'] as Map?)?['pyro_runtime'] as Map?;
      version = entry?['version']?.toString();
    } on YamlException {
      // An unreadable lock is the same as none.
    }
  }
  version ??= _workspaceRuntimeVersion(fileSystem, projectRoot);
  if (version == null) return RuntimeCompatibility.unknown;
  final readsUpTo = runtimeCompatTable[version];
  if (readsUpTo != null) {
    return RuntimeCompatibility(
      status: readsUpTo >= Scene.currentSchemaVersion
          ? RuntimeCompatStatus.ok
          : RuntimeCompatStatus.tooOld,
      foundVersion: version,
      readsUpTo: readsUpTo,
    );
  }
  return RuntimeCompatibility(
    status: _isNewer(version)
        ? RuntimeCompatStatus.tooNew
        : RuntimeCompatStatus.tooOld,
    foundVersion: version,
    readsUpTo: null,
  );
}

/// Reads `../packages/pyro_runtime`'s own version — the workspace layout —
/// so developing against `example/` still checks out.
String? _workspaceRuntimeVersion(FileSystem fs, String projectRoot) {
  final pubspec = fs.file(
    fs.path.join(projectRoot, '..', 'packages', 'pyro_runtime', 'pubspec.yaml'),
  );
  if (!pubspec.existsSync()) return null;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync()) as Map;
    final version = yaml['version'];
    return version is String && version.isNotEmpty ? version : null;
  } on YamlException {
    return null;
  }
}

bool _isNewer(String version) =>
    _compare(version, runtimeCompatTable.keys.last) > 0;

// A pre-release-aware three-way compare of plain version strings: shared
// numeric segments compare numerically; extra numeric segments are newer,
// extra non-numeric ones (0.0.1-pre.1) are older.
int _compare(String a, String b) {
  final pa = a.split(RegExp(r'[.+-]')), pb = b.split(RegExp(r'[.+-]'));
  final common = pa.length < pb.length ? pa.length : pb.length;
  for (var i = 0; i < common; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    if (na != null && nb != null) {
      if (na != nb) return na.compareTo(nb);
    } else if (pa[i] != pb[i]) {
      return pa[i].compareTo(pb[i]);
    }
  }
  if (pa.length == pb.length) return 0;
  final longer = pa.length > pb.length ? pa : pb;
  return int.tryParse(longer[common]) == null ? -1 : 1;
}
