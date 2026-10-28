import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:yaml/yaml.dart';

import 'pubspec_lock.dart';

/// The oldest `build_runner` whose output and locking Pyro's generator
/// supervisor was written and recorded against (research R8, R9).
const String minimumBuildRunner = '2.14.0';

/// The `build_runner` version a project resolved, from its `pubspec.lock`
/// (FR-017). Reading never throws: what cannot be read is [BuildRunnerUnknown].
sealed class BuildRunnerVersion {
  const BuildRunnerVersion();

  /// Reads [projectPath]'s `pubspec.lock`, or its workspace root's.
  static BuildRunnerVersion of(
    String projectPath, {
    FileSystem fileSystem = const LocalFileSystem(),
  }) {
    try {
      final lock = findPubspecLock(fileSystem, projectPath);
      if (!lock.existsSync()) return const BuildRunnerAbsent();
      final yaml = loadYaml(lock.readAsStringSync());
      if (yaml is! Map) {
        return const BuildRunnerUnknown('pubspec.lock is not a mapping.');
      }
      final entry = (yaml['packages'] as Map?)?['build_runner'];
      if (entry == null) return const BuildRunnerAbsent();
      final found = (entry as Map)['version']?.toString();
      final parsed = found == null ? null : _numbers(found);
      if (found == null || parsed == null) {
        return BuildRunnerUnknown(
          'pubspec.lock has an unreadable build_runner version: $found.',
        );
      }
      return _compare(parsed, _numbers(minimumBuildRunner)!) >= 0
          ? BuildRunnerOk(found)
          : BuildRunnerTooOld(found);
    } on YamlException catch (error) {
      return BuildRunnerUnknown('pubspec.lock is not valid YAML: $error');
    } on Object catch (error) {
      return BuildRunnerUnknown("pubspec.lock couldn't be read: $error");
    }
  }

  /// Why the generator is not set up, or null when this is [BuildRunnerOk].
  String? get reason;

  /// `major.minor.patch` as numbers; suffixes (`-dev.1`, `+build`) ignored.
  static List<int>? _numbers(String version) {
    final core = version.split(RegExp('[-+]')).first.split('.');
    if (core.length != 3) return null;
    final numbers = core.map(int.tryParse).toList();
    return numbers.contains(null) ? null : numbers.cast<int>();
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}

/// `build_runner` resolves to [minimumBuildRunner] or newer.
final class BuildRunnerOk extends BuildRunnerVersion {
  /// Creates the result.
  const BuildRunnerOk(this.version);

  /// The resolved version.
  final String version;

  @override
  String? get reason => null;
}

/// `build_runner` resolves to a version older than [minimumBuildRunner].
final class BuildRunnerTooOld extends BuildRunnerVersion {
  /// Creates the result.
  const BuildRunnerTooOld(this.found);

  /// The resolved version.
  final String found;

  /// The oldest version Pyro supports.
  String get required => minimumBuildRunner;

  @override
  String get reason =>
      'build_runner $found is too old; Pyro needs build_runner '
      '$required or newer.';
}

/// The project does not use `build_runner`, or has no lock yet.
final class BuildRunnerAbsent extends BuildRunnerVersion {
  /// Creates the result.
  const BuildRunnerAbsent();

  @override
  String get reason =>
      'build_runner is not in the project: add it to dev_dependencies and '
      'run `flutter pub get`.';
}

/// The lock could not be read.
final class BuildRunnerUnknown extends BuildRunnerVersion {
  /// Creates the result with the reason it could not be read.
  const BuildRunnerUnknown(this.reason);

  @override
  final String reason;
}
