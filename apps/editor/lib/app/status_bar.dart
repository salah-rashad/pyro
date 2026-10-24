import 'package:flutter/material.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

import 'dialogs.dart';
import 'providers.dart' show ProjectState;

/// The status bar (FR-003/FR-004/FR-014; spec 007, FR-016–FR-019): the
/// detected SDK, the Runtime compatibility result, the Type catalog's
/// status — up to date, built-ins only, or stale with its problems one
/// click away — and the generator's.
class StatusBar extends StatelessWidget {
  /// Creates the bar. [generator] is null until the first state is known
  /// (and with no project): its item is left out then.
  const StatusBar({
    super.key,
    required this.project,
    required this.catalog,
    this.generator,
    this.onStartGenerator,
  });

  /// The open project.
  final ProjectState? project;

  /// The project's types, for the catalog's status item (T022).
  final TypeCatalog catalog;

  /// The generator's state, for its item.
  final GeneratorState? generator;

  /// The *Start* button's action, shown while the generator is stopped.
  final VoidCallback? onStartGenerator;

  @override
  Widget build(BuildContext context) {
    final sdk = project?.sdk;
    final compatibility = project?.compatibility;
    final generator = this.generator;
    return Row(
      spacing: PrSpacing.s4,
      children: [
        _item(
          context,
          icon: PrIcons.terminal,
          text: sdk == null || sdk.version == null
              ? 'No Flutter SDK found'
              : 'Flutter ${sdk.version}',
        ),
        _item(
          context,
          icon: PrIcons.box,
          text: switch (compatibility?.status) {
            RuntimeCompatStatus.ok =>
              'pyro_runtime ${compatibility!.foundVersion}',
            RuntimeCompatStatus.tooOld =>
              'pyro_runtime ${compatibility!.foundVersion} — too old to read saves',
            RuntimeCompatStatus.tooNew =>
              'pyro_runtime ${compatibility!.foundVersion} — needs a newer Pyro',
            RuntimeCompatStatus.unknown || null => 'pyro_runtime: not found',
          },
        ),
        _typesItem(context, catalog),
        if (generator != null)
          Flexible(child: _generatorItem(context, generator)),
      ],
    );
  }

  /// The generator's state (data-model.md, "GeneratorState"). An error opens
  /// its file and message; a stopped generator offers *Start*.
  Widget _generatorItem(BuildContext context, GeneratorState generator) {
    final c = PrColors.of(context);
    final (icon, text) = switch (generator.status) {
      GeneratorStatus.notSetUp => (
        PrIcons.alertCircle,
        generator.reason == null
            ? 'Generator: not set up'
            : 'Generator: not set up — ${generator.reason}',
      ),
      GeneratorStatus.starting => (PrIcons.rotate, 'Generator: starting'),
      GeneratorStatus.generating => (PrIcons.rotate, 'Generating…'),
      GeneratorStatus.upToDate => (PrIcons.checkCircle, 'Up to date'),
      GeneratorStatus.error => (PrIcons.alertTriangle, 'Generator error'),
      GeneratorStatus.external => (PrIcons.external, 'External build_runner'),
      GeneratorStatus.stopped => (PrIcons.pause, 'Generator stopped'),
    };
    final isError = generator.status == GeneratorStatus.error;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: PrSpacing.s1,
      children: [
        Icon(icon, size: 12, color: isError ? c.error : c.textSecondary),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PrText.small.copyWith(
              color: isError ? c.error : c.textSecondary,
            ),
          ),
        ),
      ],
    );
    if (generator.status == GeneratorStatus.stopped) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: PrSpacing.s2,
        children: [
          label,
          PrButton(
            label: 'Start',
            size: PrButtonSize.small,
            tooltip: 'Run build_runner again',
            onPressed: onStartGenerator,
          ),
        ],
      );
    }
    if (isError) {
      return _clickable(
        context,
        message: 'Show the generator error',
        semanticsLabel: 'Generator error',
        onPressed: () => showGeneratorErrorDialog(
          context,
          file: generator.file,
          message: generator.message,
        ),
        child: label,
      );
    }
    return PrTooltip(message: text, child: label);
  }

  /// The catalog's status (FR-014): up to date / built-ins only / stale
  /// with its errors counted — never "no types", because a stale catalog
  /// keeps the last good ones (*Q105*). Clicking opens the problems.
  Widget _typesItem(BuildContext context, TypeCatalog catalog) {
    final c = PrColors.of(context);
    return _clickable(
      context,
      message: 'Show the Type catalog',
      semanticsLabel: 'Type catalog',
      onPressed: () => showCatalogProblemsDialog(context, catalog: catalog),
      child: Row(
        spacing: PrSpacing.s1,
        children: [
          Icon(PrIcons.code, size: 12, color: c.textSecondary),
          Text(
            _typesStatus(catalog),
            style: PrText.small.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  /// A status item that opens something.
  ///
  /// `PrInteractive`, not `InkWell`: the editor window has no Material
  /// ancestor (only `PrDialog` brings its own), and the `Pr` widgets are
  /// built without one.
  Widget _clickable(
    BuildContext context, {
    required String message,
    required String semanticsLabel,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return PrTooltip(
      message: message,
      child: PrInteractive(
        onPressed: onPressed,
        cursor: SystemMouseCursors.click,
        semanticsLabel: semanticsLabel,
        builder: (context, states) {
          final c = PrColors.of(context);
          return PrFocusRing.outside(
            visible: states.contains(WidgetState.focused),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: PrSpacing.s1),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.surfaceHover
                    : null,
                borderRadius: PrRadii.sm,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: states.contains(WidgetState.hovered)
                      ? c.textPrimary
                      : c.textSecondary,
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  String _typesStatus(TypeCatalog catalog) {
    final errors = catalog.problems
        .where((problem) => !problem.isWarning)
        .length;
    return switch (catalog.origin) {
      ManifestUpToDate() => 'Types up to date',
      ManifestAbsent() => 'Built-in types only',
      ManifestStale(:final reason) =>
        errors == 0
            ? 'Types stale — $reason'
            : 'Types stale — ${errors == 1 ? '1 error' : '$errors errors'} '
                  '($reason)',
    };
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final c = PrColors.of(context);
    return Row(
      spacing: PrSpacing.s1,
      children: [
        Icon(icon, size: 12, color: c.textSecondary),
        Text(text, style: PrText.small.copyWith(color: c.textSecondary)),
      ],
    );
  }
}
