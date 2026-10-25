import 'dart:async';
import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

import 'app/app.dart';
import 'panels/panels.dart';
import 'viewport/viewport.dart';

void main() {
  runApp(const PyroApp());
}

/// Pyro's settings folder: the user's application-support folder, never
/// inside a user project (research §3).
String pyroSupportFolder(FileSystem fileSystem) {
  final home = Platform.environment['HOME'];
  if (home == null) return fileSystem.path.join('/tmp', 'pyro');
  return fileSystem.path.join(
    home,
    'Library',
    'Application Support',
    'io.github.salah-rashad.pyro',
  );
}

/// The Pyro desktop app (spec 006, T017): the project list / welcome
/// window over the recent projects, and the editor window once a project
/// opens. One container owns the whole app.
class PyroApp extends StatefulWidget {
  /// Creates the app.
  const PyroApp({
    super.key,
    this.fileSystem = const LocalFileSystem(),
    this.pathVersion = flutterPathVersion,
  });

  /// The file system everything reads; tests inject a memory FS.
  final FileSystem fileSystem;

  /// Reads the `flutter` on `PATH`'s version for SDK detection; tests
  /// inject a fake so they never run a real SDK (constitution V).
  final PathVersion pathVersion;

  @override
  State<PyroApp> createState() => _PyroAppState();
}

class _PyroAppState extends State<PyroApp> {
  late final ProviderContainer _container;
  late final RecentProjectsStore _settings;
  OpenSceneCommand? _command;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer(
      overrides: [
        runLinkSupportProvider.overrideWithValue(
          pyroSupportFolder(widget.fileSystem),
        ),
      ],
    );
    _settings = RecentProjectsStore(
      widget.fileSystem.file(
        widget.fileSystem.path.join(
          pyroSupportFolder(widget.fileSystem),
          'recent_projects.json',
        ),
      ),
      fileSystem: widget.fileSystem,
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  /// Opens the project at [path]; the welcome window has already checked
  /// that its folder exists (FR-001).
  Future<void> _openProject(String path) async {
    final root = RecentProjectsStore.normalize(path);
    final sdk = await detectSdk(
      root,
      fileSystem: widget.fileSystem,
      pathVersion: widget.pathVersion,
    );
    final compatibility = await checkRuntimeCompatibility(
      root,
      fileSystem: widget.fileSystem,
    );
    if (!mounted) return;
    setState(() {
      _command = OpenSceneCommand(
        projectRoot: root,
        recoveryFolder: widget.fileSystem.path.join(
          pyroSupportFolder(widget.fileSystem),
          'recovery',
        ),
        fileSystem: widget.fileSystem,
      );
    });
    _container
        .read(projectProvider.notifier)
        .open(ProjectState(root: root, sdk: sdk, compatibility: compatibility));
    final recent = await _settings.read();
    await _settings.write(RecentProjectsStore.opened(recent, root));
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        title: 'Pyro',
        theme: PrTheme.dark(),
        home: _command == null
            ? _WelcomeWindow(
                onOpen: _openProject,
                settings: _settings,
                fileSystem: widget.fileSystem,
                pathVersion: widget.pathVersion,
              )
            : _EditorWindow(command: _command!, settings: _settings),
      ),
    );
  }
}

/// The editor window: the app's shortcuts over the shell with the scene
/// tabs.
class _EditorWindow extends StatelessWidget {
  const _EditorWindow({required this.command, required this.settings});

  final OpenSceneCommand command;
  final RecentProjectsStore settings;

  @override
  Widget build(BuildContext context) {
    return PyroEditorWindow(
      command: command,
      settings: settings,
      tabs: SceneTabs(command: command),
      left: const HierarchyPanel(),
      center: const ViewportPane(),
      right: const InspectorPanel(),
    );
  }
}

/// The welcome window (FR-001/FR-003): the recent projects with their
/// detected SDK, or the empty state, and open-by-path. A native folder
/// picker arrives with Settings (no new dependency this phase,
/// constitution II).
///
/// A recent project whose folder is gone (moved, renamed, deleted) stays
/// on the list, marked "Folder not found"; opening it explains why it
/// can't open and offers to remove it. Nothing is removed automatically.
class _WelcomeWindow extends StatefulWidget {
  const _WelcomeWindow({
    required this.onOpen,
    required this.settings,
    required this.fileSystem,
    required this.pathVersion,
  });

  final Future<void> Function(String root) onOpen;
  final RecentProjectsStore settings;
  final FileSystem fileSystem;
  final PathVersion pathVersion;

  @override
  State<_WelcomeWindow> createState() => _WelcomeWindowState();
}

/// One row of the recent list: the project's root, its detected SDK, and
/// whether its folder still exists.
typedef _RecentEntry = ({String root, SdkInfo sdk, bool exists});

void _logUnreadable(Object error) =>
    debugPrint('Pyro: unreadable recent_projects.json: $error');

class _WelcomeWindowState extends State<_WelcomeWindow> {
  List<_RecentEntry> _recent = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  bool _exists(String root) => widget.fileSystem.directory(root).existsSync();

  Future<void> _load() async {
    final recent = await widget.settings.read(_logUnreadable);
    final entries = <_RecentEntry>[];
    for (final root in recent.paths) {
      final exists = _exists(root);
      entries.add((
        root: root,
        sdk: exists
            ? await detectSdk(
                root,
                fileSystem: widget.fileSystem,
                pathVersion: widget.pathVersion,
              )
            : SdkInfo.none,
        exists: exists,
      ));
    }
    if (mounted) setState(() => _recent = entries);
  }

  /// Opens [root] when its folder exists. Otherwise explains why it
  /// can't, and — for an entry of the recent list ([recent]) — offers to
  /// remove it.
  Future<void> _open(String root, {required bool recent}) async {
    if (_exists(root)) return widget.onOpen(root);
    final remove = await showFsDialog<bool>(
      context,
      dialog: recent
          ? PrDialog<bool>(
              title: 'Folder not found',
              body:
                  "Pyro can't open this project: $root no longer exists. It "
                  'may have been moved, renamed or deleted.',
              primary: const PrDialogAction(
                label: 'Remove from list',
                value: true,
              ),
              secondary: const PrDialogAction(label: 'Keep'),
            )
          : PrDialog<bool>(
              title: 'Folder not found',
              body: 'There is no folder at $root.',
              primary: const PrDialogAction(label: 'OK'),
            ),
    );
    if (remove != true) return;
    final value = await widget.settings.read(_logUnreadable);
    try {
      await widget.settings.write(RecentProjectsStore.removed(value, root));
    } on FileSystemException catch (error) {
      debugPrint('Pyro: could not update recent_projects.json: $error');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = PrColors.of(context);
    final labels = RecentProjectsStore.distinctLabels([
      for (final entry in _recent) entry.root,
    ]);
    return Scaffold(
      backgroundColor: c.bgApp,
      body: Center(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PrSpacing.s6,
            children: [
              Text('Pyro', style: PrText.title.copyWith(color: c.textPrimary)),
              if (_recent.isEmpty)
                PrEmptyState(
                  icon: PrIcons.layers,
                  title: 'No recent projects',
                  message: 'Open a Flutter project folder to begin.',
                  action: _openByPathButton(context),
                )
              else ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: PrSpacing.s1,
                  children: [
                    for (final (i, entry) in _recent.indexed)
                      _RecentProjectTile(
                        label: labels[i],
                        root: entry.root,
                        sdk: entry.sdk,
                        exists: entry.exists,
                        onOpen: () => _open(entry.root, recent: true),
                      ),
                  ],
                ),
                _openByPathButton(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The "Open project…" button (v0.1 opens by path; a native folder
  /// picker arrives with Settings — no new dependency this phase,
  /// constitution II). A path with no folder behind it is refused.
  PrButton _openByPathButton(BuildContext context) => PrButton(
    label: 'Open project…',
    onPressed: () async {
      final controller = TextEditingController();
      final opened = await showFsDialog<bool>(
        context,
        dialog: PrDialog<bool>(
          title: 'Open project',
          width: PrDialogWidth.form,
          content: PrTextField(
            controller: controller,
            placeholder: '/path/to/project',
            autofocus: true,
          ),
          primary: const PrDialogAction(label: 'Open', value: true),
          secondary: const PrDialogAction(label: 'Cancel'),
        ),
      );
      final path = RecentProjectsStore.normalize(controller.text);
      if (opened != true || path.isEmpty) return;
      await _open(path, recent: false);
    },
  );
}

/// A recent project: its distinct [label] over its full [root] and the SDK
/// icon or, when the folder is gone, a warning and "Folder not found".
class _RecentProjectTile extends StatelessWidget {
  const _RecentProjectTile({
    required this.label,
    required this.root,
    required this.sdk,
    required this.exists,
    required this.onOpen,
  });

  final String label;
  final String root;
  final SdkInfo sdk;
  final bool exists;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final noSdk = sdk.version == null;
    final String tooltip;
    if (!exists) {
      tooltip = '$root — folder not found';
    } else if (noSdk) {
      tooltip = '$root — no Flutter SDK found';
    } else {
      tooltip = '$root — Flutter ${sdk.version}';
    }
    return PrTooltip(
      message: tooltip,
      child: PrInteractive(
        onPressed: onOpen,
        cursor: SystemMouseCursors.click,
        semanticsLabel: exists ? label : '$label, folder not found',
        builder: (context, states) {
          final c = PrColors.of(context);
          final warn = !exists || noSdk;
          return PrFocusRing.outside(
            visible: states.contains(WidgetState.focused),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PrSpacing.s3,
                vertical: PrSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.surfaceHover
                    : c.surfaceRaised,
                borderRadius: PrRadii.sm,
              ),
              child: Row(
                spacing: PrSpacing.s2,
                children: [
                  Icon(
                    warn ? PrIcons.alertTriangle : PrIcons.folder,
                    size: 14,
                    color: warn ? c.warning : c.textSecondary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: PrText.bodyStrong.copyWith(
                            color: exists ? c.textPrimary : c.textSecondary,
                          ),
                        ),
                        Text(
                          root,
                          overflow: TextOverflow.ellipsis,
                          style: PrText.small.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (!exists)
                    Text(
                      'Folder not found',
                      style: PrText.small.copyWith(color: c.warning),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
