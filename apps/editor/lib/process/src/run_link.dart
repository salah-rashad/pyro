import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

/// A symlink to the project under Pyro's application support, through which
/// `flutter run` names its DevFS, so an IDE attached to the game cannot
/// clash with it (spec 007, research R2; spike #1 finding 4).
///
/// The link lives at `<support>/run/<project-id>/<name>-pyro`. It is the only
/// thing Play writes outside the project, and never inside it (constitution
/// IV).
final class RunLink {
  RunLink._(this.path, this._fs);

  /// Makes the link for [projectPath] under [supportDir].
  ///
  /// Returns null when the link cannot be made (a read-only support folder, a
  /// file system without symlinks): Play then runs without it (research R2).
  /// An existing link of the same name is replaced.
  static Future<RunLink?> create(
    String projectPath, {
    required String supportDir,
    FileSystem fileSystem = const LocalFileSystem(),
  }) async {
    try {
      final project = _canonical(fileSystem, projectPath);
      final folder = fileSystem.path.join(
        _canonical(fileSystem, supportDir, create: true),
        'run',
        _id(project),
      );
      fileSystem.directory(folder).createSync(recursive: true);
      final path = fileSystem.path.join(
        folder,
        '${fileSystem.path.basename(project)}-pyro',
      );
      final link = fileSystem.link(path);
      if (fileSystem.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        // Only ever a link: a file or folder of that name is not ours.
        if (!link.existsSync()) return null;
        link.deleteSync();
      }
      link.createSync(project);
      return RunLink._(path, fileSystem);
    } on FileSystemException {
      return null;
    }
  }

  /// The link's path: what `--project-root` is given.
  final String path;

  final FileSystem _fs;

  /// Removes the link, never what it points to.
  Future<void> remove() async {
    final link = _fs.link(path);
    if (_fs.typeSync(path, followLinks: false) == FileSystemEntityType.link) {
      link.deleteSync();
    }
    _removeIfEmpty(_fs, _fs.path.dirname(path));
  }

  /// Removes every link left for [projectPath] by an earlier run that did not
  /// end cleanly, never following one.
  static Future<void> sweep(
    String projectPath, {
    required String supportDir,
    FileSystem fileSystem = const LocalFileSystem(),
  }) async {
    try {
      final project = _canonical(fileSystem, projectPath);
      final folder = fileSystem.directory(
        fileSystem.path.join(supportDir, 'run', _id(project)),
      );
      if (!folder.existsSync()) return;
      for (final entry in folder.listSync(followLinks: false)) {
        if (entry is Link) entry.deleteSync();
      }
      _removeIfEmpty(fileSystem, folder.path);
    } on FileSystemException {
      // Nothing to sweep that can be swept.
    }
  }

  static String _id(String canonicalProject) =>
      sha1.convert(canonicalProject.codeUnits).toString().substring(0, 12);

  /// [path] with symlinks resolved, so one project has one id however it
  /// is reached. A path that does not exist yet stays as it is.
  static String _canonical(FileSystem fs, String path, {bool create = false}) {
    final directory = fs.directory(path);
    if (create) directory.createSync(recursive: true);
    return directory.existsSync()
        ? directory.resolveSymbolicLinksSync()
        : fs.path.normalize(fs.path.absolute(path));
  }

  static void _removeIfEmpty(FileSystem fs, String folder) {
    final directory = fs.directory(folder);
    if (directory.existsSync() && directory.listSync().isEmpty) {
      directory.deleteSync();
    }
  }
}
