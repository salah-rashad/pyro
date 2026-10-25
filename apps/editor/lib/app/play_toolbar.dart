import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../process/process.dart';
import '../process/providers.dart';
import 'attach_guide.dart';
import 'dialogs.dart';
import 'open_scene.dart';
import 'providers.dart';
import 'save_scene.dart';

/// The main toolbar's Play cluster (spec 007, FR-001–FR-006): Play or
/// Stop, the game's phase, and why Play is disabled with its fix.
class PlayToolbar extends ConsumerWidget {
  /// Creates the toolbar for the open project.
  const PlayToolbar({super.key, required this.command});

  /// The open-scene command, for "Save and play"'s saves.
  final OpenSceneCommand command;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playControllerProvider);
    final phase =
        ref.watch(playPhaseProvider).value ??
        controller?.phase ??
        PlayPhase.stopped;
    final block = controller?.block;
    final c = PrColors.of(context);
    final busy = phase != PlayPhase.stopped;
    final Widget button = busy
        ? PrButton(
            label: 'Stop',
            icon: PrIcons.stop,
            tooltip: 'Stop the game',
            onPressed: phase == PlayPhase.stopping || controller == null
                ? null
                : () => unawaited(controller.stop()),
            disabledReason: 'The game is stopping',
          )
        : PrButton(
            label: 'Play',
            icon: PrIcons.play,
            variant: PrButtonVariant.primary,
            tooltip: 'Run the game on macOS',
            onPressed: controller == null || block != null
                ? null
                : () => unawaited(
                    pressPlay(
                      context,
                      ProviderScope.containerOf(context),
                      command: command,
                    ),
                  ),
            disabledReason: block == null
                ? null
                : '${block.reason} ${block.fix}',
          );
    return PrToolbar(
      leading: const [],
      highlighted: phase == PlayPhase.running,
      center: [
        PrToolbarGroup(
          spacing: PrSpacing.s2,
          children: [
            button,
            Text(
              _phaseLabel(phase),
              style: PrText.small.copyWith(color: c.textSecondary),
            ),
            PrIconButton(
              icon: PrIcons.link,
              tooltip: 'Attach debugger',
              onPressed: controller == null || !controller.canAttach
                  ? null
                  : () => unawaited(_attach(context, controller)),
              disabledReason: 'Press Play first',
            ),
          ],
        ),
      ],
      trailing: [
        if (block != null && !busy)
          PrToolbarGroup(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  '${block.reason} ${block.fix}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PrText.small.copyWith(color: c.warning),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _phaseLabel(PlayPhase phase) => switch (phase) {
    PlayPhase.stopped => 'Stopped',
    PlayPhase.starting => 'Starting…',
    PlayPhase.running => 'Running',
    PlayPhase.stopping => 'Stopping…',
  };
}

/// *Attach debugger* (FR-027): puts the running game's address on the
/// clipboard, says so without showing it, and opens the guide.
Future<void> _attach(BuildContext context, PlayController controller) async {
  final address = controller.copyDebuggerAddress();
  if (address == null) return;
  await Clipboard.setData(ClipboardData(text: address));
  if (!context.mounted) return;
  PrToastHost.of(context).show(
    const PrToastData(kind: PrToastKind.info, title: 'Debugger address copied'),
  );
  await showAttachGuide(context);
}

/// Play's press (FR-006): with unsaved Scenes, asks "Save and play" or
/// "Play without saving" first; *Save and play* saves each unsaved Scene
/// and starts nothing if a save fails or is cancelled. Dismissing the
/// question starts nothing.
Future<void> pressPlay(
  BuildContext context,
  ProviderContainer container, {
  required OpenSceneCommand command,
}) async {
  final controller = container.read(playControllerProvider);
  if (controller == null || controller.block != null) return;
  final unsaved = [
    for (final scene in container.read(openScenesProvider).scenes)
      if (container.read(documentProvider(scene.sceneId)).isDirty)
        scene.sceneId,
  ];
  if (unsaved.isNotEmpty) {
    final answer = await showSaveAndPlayDialog(context, count: unsaved.length);
    switch (answer) {
      case SaveAndPlayAnswer.cancel:
        return;
      case SaveAndPlayAnswer.playWithoutSaving:
        break;
      case SaveAndPlayAnswer.saveAndPlay:
        for (final sceneId in unsaved) {
          if (!context.mounted) return;
          final saved = await saveScene(
            context,
            container,
            sceneId: sceneId,
            command: command,
          );
          if (!saved) return;
        }
    }
  }
  await controller.play();
}
