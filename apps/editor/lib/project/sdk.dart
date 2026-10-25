import 'dart:convert';
import 'dart:io' show Platform, Process, ProcessException;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sdk.freezed.dart';

/// Where a project's Flutter SDK was found (§9.1's detection order).
enum SdkSource {
  /// The project's own fvm config (`.fvmrc` / `.fvm/`).
  fvm,

  /// The `FLUTTER_ROOT` environment variable.
  flutterRoot,

  /// A `flutter` executable on `PATH`.
  path,

  /// No SDK found. Editing goes on; this gates Play (Phase 5), not the
  /// editor (FR-003).
  none,
}

/// A project's detected Flutter SDK (FR-003).
@freezed
sealed class SdkInfo with _$SdkInfo {
  /// Creates the detection result; [version] is null with [SdkSource.none].
  const factory SdkInfo({
    required String? version,
    required SdkSource source,

    /// The SDK's folder, when the source names one (fvm, `FLUTTER_ROOT`);
    /// null for `flutter` on `PATH`, which runs by name.
    String? root,
  }) = _SdkInfo;

  /// No SDK found.
  static const none = SdkInfo(version: null, source: SdkSource.none);
}

/// The `FLUTTER_ROOT` environment value, injected so tests never read the
/// real environment.
typedef FlutterRoot = String?;

/// Reads the process environment, injected so tests stay hermetic.
typedef Env = String? Function(String name);

String? _platformEnv(String name) => Platform.environment[name];

/// Reads `flutter --version`'s first line, injected so tests never run a
/// real SDK (constitution V).
typedef PathVersion = Future<String?> Function();

/// Detects the project at [projectRoot]'s Flutter SDK in §9.1's order:
/// per-project fvm config → `FLUTTER_ROOT` → `flutter` on `PATH` (*Q39*).
///
/// Pyro never bundles or installs an SDK; `none` is a valid answer that
/// never blocks editing.
Future<SdkInfo> detectSdk(
  String projectRoot, {
  FileSystem fileSystem = const LocalFileSystem(),
  FlutterRoot? flutterRoot,
  Env env = _platformEnv,
  PathVersion pathVersion = _noPathVersion,
}) async {
  final fvm = _fvmVersion(fileSystem, projectRoot);
  if (fvm != null) {
    final link = fileSystem.path.join(projectRoot, '.fvm', 'flutter_sdk');
    return SdkInfo(
      version: fvm,
      source: SdkSource.fvm,
      root: fileSystem.directory(link).existsSync() ? link : null,
    );
  }
  final root = flutterRoot ?? env('FLUTTER_ROOT');
  if (root != null) {
    final version = _versionFile(fileSystem, root);
    if (version != null) {
      return SdkInfo(
        version: version,
        source: SdkSource.flutterRoot,
        root: root,
      );
    }
  }
  final onPath = await pathVersion();
  if (onPath != null) return SdkInfo(version: onPath, source: SdkSource.path);
  return SdkInfo.none;
}

Future<String?> _noPathVersion() async => null;

/// The `flutter` executable of [sdk]: `<root>/bin/flutter`, or `flutter` on
/// `PATH` when the SDK has no known folder.
String flutterExecutable(SdkInfo sdk) =>
    sdk.root == null ? 'flutter' : '${sdk.root}/bin/flutter';

/// The `dart` executable of [sdk]: `<root>/bin/dart`, or `dart` on `PATH`.
String dartExecutable(SdkInfo sdk) =>
    sdk.root == null ? 'dart' : '${sdk.root}/bin/dart';

/// Runs `flutter --version` and reads its version number: the app's
/// [PathVersion]. Tests inject a fake instead so they never run a real
/// SDK (constitution V).
Future<String?> flutterPathVersion() async {
  try {
    final result = await Process.run('flutter', ['--version']);
    if (result.exitCode != 0) return null;
    final firstLine = (result.stdout as String)
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    final match = RegExp(r'Flutter\s+(\S+)').firstMatch(firstLine);
    return match?.group(1);
  } on ProcessException {
    // No `flutter` on PATH; §9.1's last source falls through to none.
    return null;
  }
}

// The fvm configs, newest first: `.fvmrc` names the release;
// `.fvm/fvm_config.json` may name the version; `.fvm/flutter_sdk/version`
// reads through fvm's symlink to the SDK itself.
String? _fvmVersion(FileSystem fs, String projectRoot) {
  final fvmrc = fs.file(fs.path.join(projectRoot, '.fvmrc'));
  if (fvmrc.existsSync()) {
    try {
      final json = jsonDecode(fvmrc.readAsStringSync());
      if (json is Map<String, Object?>) {
        final flutter = json['flutter'];
        if (flutter is String && flutter.isNotEmpty) return flutter;
      }
    } on FormatException {
      // An unreadable fvm config falls through to the next source.
    }
  }
  final config = fs.file(fs.path.join(projectRoot, '.fvm', 'fvm_config.json'));
  if (config.existsSync()) {
    try {
      final json = jsonDecode(config.readAsStringSync());
      if (json is Map<String, Object?>) {
        final version = json['flutterVersion'];
        if (version is String && version.isNotEmpty) return version;
      }
    } on FormatException {
      // Same fall-through.
    }
  }
  return _versionFile(fs, fs.path.join(projectRoot, '.fvm', 'flutter_sdk'));
}

/// The SDK's `version` file content, trimmed; null when it can't be read.
String? _versionFile(FileSystem fs, String sdkRoot) {
  try {
    final text = fs
        .file(fs.path.join(sdkRoot, 'version'))
        .readAsStringSync()
        .trim();
    return text.isEmpty ? null : text;
  } on FileSystemException {
    return null;
  }
}
