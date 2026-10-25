import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyro/panels/panels.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

import 'dialogs.dart';
import 'open_scene.dart';
import 'play_notices.dart';
import 'play_toolbar.dart';
import 'providers.dart';
import 'save_scene.dart';
import 'shortcuts.dart';
import 'status_bar.dart';

/// The title bar's leading inset on macOS: the traffic lights (close,
/// minimise, zoom) sit over the full-size content view there, so the
/// title keeps this much clear on each side. Wide enough for macOS 26's
/// larger buttons, with a margin.
const double macTrafficLightsInset = 88;

/// The title bar's leading inset elsewhere, where the native title bar
/// keeps the window buttons out of the content.
const double plainTitleBarInset = PrSpacing.s3;

/// The editor window (spec 006, T012): the `PrEditorShell` layout with
/// the panel slots, the status bar and the title bar, dock sizes
/// persisted per project (T008), and the app-quit interception that
/// walks dirty tabs through the unsaved-changes dialog (FR-007).
///
/// The panel widgets arrive with their stories; until then the slots
/// show placeholders. The scene tabs (T013) mount on top of the centre.
class PyroEditorWindow extends ConsumerStatefulWidget {
  /// Creates the window for the open project.
  const PyroEditorWindow({
    super.key,
    required this.command,
    required this.settings,
    this.tabs,
    this.left,
    this.center,
    this.right,
  });

  /// The open-scene command for the open project.
  final OpenSceneCommand command;

  /// The editor-settings store the dock sizes persist through (T008).
  final RecentProjectsStore settings;

  /// The centre's tab strip (T013); null shows only the placeholder.
  final Widget? tabs;

  /// The left dock (Hierarchy); null shows the placeholder.
  final Widget? left;

  /// The centre (Viewport); null shows the placeholder.
  final Widget? center;

  /// The right dock (Inspector); null shows the placeholder.
  final Widget? right;

  @override
  ConsumerState<PyroEditorWindow> createState() => _PyroEditorWindowState();
}

class _PyroEditorWindowState extends ConsumerState<PyroEditorWindow> {
  PrShellSizes _sizes = PrShellSizes.standard;
  var _consoleCollapsed = false;
  late final AppLifecycleListener _listener;

  /// The panels' focus scopes (T016): Hierarchy, Viewport, Inspector —
  /// the cycle order the shortcuts walk.
  final List<FocusScopeNode> panelNodes = [
    PrPanelFocus.createNode(debugLabel: 'hierarchy'),
    PrPanelFocus.createNode(debugLabel: 'viewport'),
    PrPanelFocus.createNode(debugLabel: 'inspector'),
  ];

  @override
  void initState() {
    super.initState();
    // App-quit interception (FR-007): every dirty tab is walked through
    // the unsaved-changes dialog before the app may exit. *Cancel* on any
    // tab denies the exit.
    _listener = AppLifecycleListener(
      onExitRequested: () => _exitWhenScenesClean(context),
    );
    unawaited(_loadSizes());
  }

  @override
  void dispose() {
    _listener.dispose();
    for (final node in panelNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSizes() async {
    final root = ref.read(projectProvider)?.root;
    if (root == null) return;
    await widget.settings.read().then((recent) {
      if (!mounted) return;
      setState(() => _sizes = recent.sizes[root] ?? PrShellSizes.standard);
    });
  }

  void _persistSizes(PrShellSizes sizes) {
    final root = ref.read(projectProvider)?.root;
    if (root == null) return;
    unawaited(
      widget.settings.read().then((recent) {
        return widget.settings.write(
          recent.copyWith(sizes: recent.sizes.add(root, sizes)),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final scenes = ref.watch(openScenesProvider);
    String title = 'Pyro';
    if (project != null) {
      final name = project.root
          .split('/')
          .where((part) => part.isNotEmpty)
          .last;
      for (final scene in scenes.scenes) {
        if (scene.sceneId == scenes.active) {
          title = '$name — ${scene.displayName}';
        }
      }
      if (scenes.active == null) title = name;
    }

    Widget dock(int index, Widget? slot, String label) => PrPanelFocus(
      node: panelNodes[index],
      child: slot ?? _PanelPlaceholder(label: label),
    );

    return Scaffold(
      body: PlayNotices(
        child: PyroShortcuts(
          command: widget.command,
          panels: panelNodes,
          child: PrEditorShell(
            titleBar: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PrText.small.copyWith(
                  color: PrColors.of(context).textSecondary,
                ),
              ),
            ),
            titleBarLeadingInset: Platform.isMacOS
                ? macTrafficLightsInset
                : plainTitleBarInset,
            toolbar: PlayToolbar(command: widget.command),
            left: dock(0, widget.left, 'Hierarchy'),
            center: dock(
              1,
              widget.tabs != null
                  ? Column(
                      children: [
                        widget.tabs!,
                        Expanded(
                          child:
                              widget.center ??
                              const _PanelPlaceholder(label: 'Viewport'),
                        ),
                      ],
                    )
                  : widget.center,
              'Viewport',
            ),
            right: dock(2, widget.right, 'Inspector'),
            bottom: const ConsolePanel(),
            bottomCollapsed: _consoleCollapsed,
            onBottomCollapsedChanged: (collapsed) =>
                setState(() => _consoleCollapsed = collapsed),
            statusBar: StatusBar(
              project: project,
              catalog: ref.watch(typeCatalogProvider),
              generator: ref.watch(generatorStateProvider).value,
              onStartGenerator: () =>
                  unawaited(ref.read(generatorProvider)?.start()),
            ),
            sizes: _sizes,
            onSizesChanged: (sizes) => setState(() => _sizes = sizes),
            onSizesChangeEnd: _persistSizes,
          ),
        ),
      ),
    );
  }

  Future<AppExitResponse> _exitWhenScenesClean(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    for (final scene in container.read(openScenesProvider).scenes) {
      if (!container.read(documentProvider(scene.sceneId)).isDirty) continue;
      if (!context.mounted) return AppExitResponse.cancel;
      final answer = await showUnsavedChangesDialog(context, scene.displayName);
      switch (answer) {
        case UnsavedChangesAnswer.cancel:
          return AppExitResponse.cancel;
        case UnsavedChangesAnswer.save:
          if (!context.mounted) return AppExitResponse.cancel;
          final saved = await saveScene(
            context,
            container,
            sceneId: scene.sceneId,
            command: widget.command,
          );
          if (!saved) return AppExitResponse.cancel;
        case UnsavedChangesAnswer.discard:
          await discardScene(container, scene.sceneId);
      }
    }
    if (!context.mounted) return AppExitResponse.cancel;
    // The game runs from the saved Scenes; it is only stopped once the user
    // has settled their unsaved changes.
    if (!await confirmStopGame(context, container)) {
      return AppExitResponse.cancel;
    }
    // Pyro's own build_runner would outlive the app and make the next run
    // see an "External build_runner" (FR-022); an external one is left alone.
    await container.read(generatorProvider)?.dispose();
    return AppExitResponse.exit;
  }
}

/// Closes the open project, after asking to stop a running game (spec 007,
/// FR-015). The entry point of a *Close project* command: stopping happens
/// before the project goes, so the controller isn't torn down under a
/// running game. Returns false when the user said no.
Future<bool> closeProject(
  BuildContext context,
  ProviderContainer container,
) async {
  if (!await confirmStopGame(
    context,
    container,
    reason: StopGameFor.closeProject,
  )) {
    return false;
  }
  container.read(projectProvider.notifier).close();
  return true;
}

/// Closes [sceneId]'s tab discarding unsaved changes. The document
/// provider is pinned for the await so the session isn't auto-closed
/// mid-dialog (the shared half of the tabs' close flow, T013).
Future<void> discardScene(ProviderContainer container, String sceneId) async {
  // A live listener pins the autoDispose family for the await (the
  // KeepAliveLink of research §2, from outside the provider).
  final link = container.listen(documentProvider(sceneId), (_, _) {});
  try {
    final session = container.read(sessionRegistryProvider)[sceneId];
    if (session != null && !session.isClosed) {
      await session.discardAndClose();
    }
    container.read(sessionRegistryProvider.notifier).forget(sceneId);
    container.read(openScenesProvider.notifier).close(sceneId);
  } finally {
    link.close();
  }
}

/// A panel slot's stand-in until its story lands.
class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder({required this.label});

  final String label;

  /// Below this height the empty state would overflow; only the label
  /// shows.
  static const double _fullHeight = 240;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: constraints.maxHeight < _fullHeight
            ? Text(
                label,
                style: PrText.small.copyWith(
                  color: PrColors.of(context).textSecondary,
                ),
              )
            : PrEmptyState(
                icon: PrIcons.box,
                title: label,
                message: 'This panel arrives with its story.',
                action: PrButton(label: 'Coming soon', onPressed: () {}),
              ),
      ),
    );
  }
}
