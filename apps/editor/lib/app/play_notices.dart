import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../process/process.dart';
import '../process/providers.dart';

/// Shows the running game's notices as toasts (spec 007, FR-014, FR-011;
/// contracts/play-orchestration.md, "Notices"): the game exited by itself,
/// Scene saves stopped reaching it, or an image it uses changed. A notice replaces the previous one of
/// its kind rather than stacking.
class PlayNotices extends StatelessWidget {
  /// Wraps [child] with a toast host and the notice listener.
  const PlayNotices({super.key, required this.child});

  /// The editor window.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      PrToastHost(child: _NoticeListener(child: child));
}

class _NoticeListener extends ConsumerStatefulWidget {
  const _NoticeListener({required this.child});

  final Widget child;

  @override
  ConsumerState<_NoticeListener> createState() => _NoticeListenerState();
}

class _NoticeListenerState extends ConsumerState<_NoticeListener> {
  StreamSubscription<PlayNotice>? _notices;
  StreamSubscription<PlayPhase>? _phases;
  PlayController? _controller;
  final _shown = <Type, PrToastHandle>{};

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    unawaited(_phases?.cancel());
    super.dispose();
  }

  void _listenTo(PlayController? controller) {
    if (identical(controller, _controller)) return;
    unawaited(_notices?.cancel());
    unawaited(_phases?.cancel());
    _controller = controller;
    _notices = controller?.notices.listen(_show);
    _phases = controller?.phases.listen(_onPhase);
  }

  /// A notice that offers *Restart game* means nothing once the game is
  /// gone: it leaves with the game, and the next run starts clean.
  void _onPhase(PlayPhase phase) {
    if (phase != PlayPhase.stopped) return;
    for (final kind in [ImageChanged, HotSwapFailed]) {
      _shown.remove(kind)?.dismiss();
    }
  }

  void _show(PlayNotice notice) {
    if (!mounted) return;
    final toasts = PrToastHost.of(context);
    _shown.remove(notice.runtimeType)?.dismiss();
    _shown[notice.runtimeType] = toasts.show(_toast(notice));
  }

  PrToastData _toast(PlayNotice notice) => switch (notice) {
    GameStopped(:final exitCode) => PrToastData(
      kind: PrToastKind.info,
      title: 'Game stopped',
      message: exitCode == 0
          ? 'The game was closed.'
          : 'The game exited with code $exitCode.',
    ),
    ImageChanged(:final paths) => PrToastData(
      kind: PrToastKind.warning,
      title: 'Image changed',
      message: paths.length == 1
          ? '${paths.single} changed. The game shows the old image until it '
                'restarts.'
          : '${paths.length} images changed. The game shows the old ones '
                'until it restarts.',
      actions: [
        PrToastAction(
          label: 'Restart game',
          onPressed: () => unawaited(_controller?.restartGame()),
        ),
      ],
    ),
    HotSwapFailed() => PrToastData(
      kind: PrToastKind.warning,
      title: 'Hot-swap stopped working',
      message:
          'Saved Scenes are not reaching the game. An attached IDE or an '
          'old game can cause this.',
      actions: [
        PrToastAction(
          label: 'Restart game',
          onPressed: () => unawaited(_controller?.restartGame()),
        ),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    _listenTo(ref.watch(playControllerProvider));
    return widget.child;
  }
}
