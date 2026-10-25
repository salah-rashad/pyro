import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../../process/process.dart';
import '../../process/providers.dart';

/// The Console (spec 007, FR-023–FR-026): the open project's generator,
/// game and Pyro lines in one virtualized list, filterable by source,
/// following the newest line until the user scrolls up.
///
/// A long line wraps, and the text can be selected and copied; *Copy all*
/// copies every line shown, labelled. Lines are redacted when they enter the
/// buffer, so nothing copied can carry a debugger address (FR-025).
///
/// It rebuilds only on the buffer's throttled changes, so a flood of
/// output costs one build per 50 ms at most (SC-006). Only the rows in view
/// are built, however tall they are.
///
/// Live rows are plain text: letting the selection machinery see every
/// streamed row cost 15 frames over 16 ms in a flood (profile mode, SC-006).
/// *Pause to select text* instead freezes the view into a snapshot of the
/// latest [snapshotLines] lines whose text can be selected; *Resume* goes
/// back to the live view.
class ConsolePanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ConsolePanel({super.key});

  /// How many of the newest lines the selectable snapshot holds.
  static const snapshotLines = 1000;

  @override
  ConsumerState<ConsolePanel> createState() => _ConsolePanelState();
}

/// The source filter's row: a control plus its padding.
const double _filterRowHeight = PrSizes.control + 2 * PrSpacing.s1;

class _ConsolePanelState extends ConsumerState<ConsolePanel> {
  final _scroll = ScrollController();
  StreamSubscription<void>? _changes;
  ConsoleBuffer? _buffer;
  var _following = true;
  List<ConsoleLine>? _snapshot;

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _listenTo(ConsoleBuffer buffer) {
    if (identical(buffer, _buffer)) return;
    unawaited(_changes?.cancel());
    _buffer = buffer;
    _changes = buffer.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_following) _jumpToTailAfterLayout();
    });
  }

  /// Scrolls to the newest line once the list has laid out. Rows wrap to
  /// different heights, so the list only estimates its end until the last
  /// rows are laid out: jump, and again on the next frame until the end stops
  /// moving (a few frames at most).
  void _jumpToTailAfterLayout([int attempts = 4]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_following) return;
      final position = _scroll.position;
      final end = position.maxScrollExtent;
      final moved = position.pixels < end - 1;
      if (moved) _scroll.jumpTo(end);
      if (moved && attempts > 1) _jumpToTailAfterLayout(attempts - 1);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! UserScrollNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    // Only the user's own scrolling changes whether the list follows.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails == null) {
      return false;
    }
    final metrics = notification.metrics;
    final atTail = metrics.pixels >= metrics.maxScrollExtent - 1;
    if (atTail != _following) setState(() => _following = atTail);
    return false;
  }

  /// Freezes the view into a selectable snapshot, or goes back to live.
  void _togglePause(List<ConsoleLine> lines) {
    if (_snapshot != null) {
      setState(() => _snapshot = null);
      _follow();
      return;
    }
    final from = lines.length > ConsolePanel.snapshotLines
        ? lines.length - ConsolePanel.snapshotLines
        : 0;
    setState(() => _snapshot = List.of(lines.sublist(from)));
  }

  /// The snapshot: newest line at the bottom, as in the live view. A
  /// reversed list starts there, so it never has to jump to the end.
  Widget _frozen(List<ConsoleLine> lines) => SelectionArea(
    child: ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: PrSpacing.s2),
      itemCount: lines.length,
      itemBuilder: (context, index) =>
          _ConsoleRow(line: lines[lines.length - 1 - index]),
    ),
  );

  Widget _list(List<ConsoleLine> lines) => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.symmetric(horizontal: PrSpacing.s2),
    itemCount: lines.length,
    itemBuilder: (context, index) => _rowOf(lines[index]),
  );

  /// A line never changes, so its row is built once and handed back: the
  /// framework skips a row that is the very same widget, and the text of a
  /// line already shown is not laid out again when the list rebuilds.
  static final _rows = Expando<Widget>('Console rows');
  static Widget _rowOf(ConsoleLine line) =>
      _rows[line] ??= _ConsoleRow(line: line);

  /// Puts every line shown on the clipboard, each with its source.
  void _copyAll(List<ConsoleLine> lines) {
    final text = lines
        .map((line) => '${_label(line.source).trimRight()}  ${line.text}')
        .join('\n');
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void _follow() {
    setState(() => _following = true);
    _jumpToTailAfterLayout();
  }

  @override
  Widget build(BuildContext context) {
    final buffer = ref.watch(consoleBufferProvider);
    _listenTo(buffer);
    final sources = ref.watch(consoleSourceFilterProvider);
    final lines = buffer.filtered(sources);
    final c = PrColors.of(context);
    final only = sources.length == 1 ? sources.single : null;
    return PrPanel(
      title: 'Console',
      icon: PrIcons.terminal,
      actions: [
        PrIconButton(
          icon: _snapshot == null ? PrIcons.pause : PrIcons.play,
          tooltip: _snapshot == null ? 'Pause to select text' : 'Resume',
          size: PrIconButtonSize.small,
          onPressed: _snapshot == null && lines.isEmpty
              ? null
              : () => _togglePause(lines),
          disabledReason: 'The Console is empty',
        ),
        PrIconButton(
          icon: PrIcons.copy,
          tooltip: 'Copy all',
          size: PrIconButtonSize.small,
          onPressed: lines.isEmpty ? null : () => _copyAll(lines),
          disabledReason: 'The Console is empty',
        ),
        PrIconButton(
          icon: PrIcons.trash,
          tooltip: 'Clear',
          size: PrIconButtonSize.small,
          onPressed: buffer.lines.isEmpty ? null : buffer.clear,
          disabledReason: 'The Console is empty',
        ),
      ],
      // A dock squeezed shorter than the filter row shows only the
      // header rather than overflowing.
      body: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxHeight < _filterRowHeight
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PrSpacing.s2,
                      vertical: PrSpacing.s1,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PrSegmentedControl<ConsoleSource?>(
                        segments: const [
                          PrSegment(value: null, label: 'All'),
                          PrSegment(
                            value: ConsoleSource.generator,
                            label: 'Generator',
                          ),
                          PrSegment(value: ConsoleSource.game, label: 'Game'),
                          PrSegment(value: ConsoleSource.pyro, label: 'Pyro'),
                        ],
                        selected: only,
                        onChanged: (source) {
                          final filter = ref.read(
                            consoleSourceFilterProvider.notifier,
                          );
                          source == null
                              ? filter.showAll()
                              : filter.showOnly(source);
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: lines.isEmpty
                        ? Center(
                            child: Text(
                              buffer.lines.isEmpty
                                  ? 'No output yet. Press Play to run the game.'
                                  : 'No lines from this source.',
                              style: PrText.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: _onScroll,
                            child: _snapshot == null
                                ? Stack(
                                    children: [
                                      Positioned.fill(child: _list(lines)),
                                      if (!_following)
                                        Positioned(
                                          right: PrSpacing.s3,
                                          bottom: PrSpacing.s2,
                                          child: PrIconButton(
                                            icon: PrIcons.chevronDown,
                                            tooltip: 'Follow the newest line',
                                            size: PrIconButtonSize.small,
                                            onPressed: _follow,
                                          ),
                                        ),
                                    ],
                                  )
                                : _frozen(_snapshot!),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One Console line: its source in a column of its own, then its text in
/// the severity's colour, wrapping under itself. The label is left out of a
/// selection, so a copy holds the text alone.
class _ConsoleRow extends StatelessWidget {
  const _ConsoleRow({required this.line});

  final ConsoleLine line;

  @override
  Widget build(BuildContext context) {
    final c = PrColors.of(context);
    final color = switch (line.severity) {
      ConsoleSeverity.error => c.error,
      ConsoleSeverity.warning => c.warning,
      ConsoleSeverity.info => c.textPrimary,
    };
    final text = Text(
      line.text,
      style: PrText.monoConsole.copyWith(color: color),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: Text(
            '${_label(line.source)}  ',
            maxLines: 1,
            softWrap: false,
            style: PrText.monoConsole.copyWith(color: c.textSecondary),
          ),
        ),
        Expanded(child: text),
      ],
    );
  }
}

/// The source's name, padded to one width so the texts line up.
String _label(ConsoleSource source) => switch (source) {
  ConsoleSource.generator => 'generator',
  ConsoleSource.game => 'game     ',
  ConsoleSource.pyro => 'pyro     ',
};
