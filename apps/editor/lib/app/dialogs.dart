import 'package:flutter/material.dart';
import 'package:pyro/document/document.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_runtime/pyro_runtime.dart';
import 'package:pyro_ui/pyro_ui.dart';

/// The editor's dialogs on `showFsDialog` (spec 006, T014): unsaved
/// changes, new scene, save refused, recovery *Restore* — and the Type
/// catalog's problems (T022).

/// The unsaved-changes dialog's answers (FR-007).
enum UnsavedChangesAnswer { save, discard, cancel }

/// Asks what to do with the unsaved changes of [sceneName]: primary
/// *Save*, destructive *Discard*, secondary *Cancel*.
Future<UnsavedChangesAnswer> showUnsavedChangesDialog(
  BuildContext context,
  String sceneName,
) => showFsDialog<UnsavedChangesAnswer>(
  context,
  dialog: PrDialog(
    title: 'Save changes to "$sceneName"?',
    body:
        'The Scene has unsaved changes. They are kept in a recovery '
        'copy only after a while.',
    primary: const PrDialogAction(
      label: 'Save',
      value: UnsavedChangesAnswer.save,
    ),
    secondary: const PrDialogAction(
      label: 'Cancel',
      value: UnsavedChangesAnswer.cancel,
    ),
    destructive: const PrDialogAction(
      label: 'Discard',
      value: UnsavedChangesAnswer.discard,
    ),
  ),
).then((answer) => answer ?? UnsavedChangesAnswer.cancel);

/// The "Save and play" question's answers (spec 007, FR-006).
enum SaveAndPlayAnswer { saveAndPlay, playWithoutSaving, cancel }

/// Asks what to do with [count] Scenes' unsaved changes before Play:
/// primary *Save and play*, *Play without saving* apart on the left (the
/// "Don't save" place), secondary *Cancel*, which the close × and Esc
/// also answer: they start nothing.
Future<SaveAndPlayAnswer> showSaveAndPlayDialog(
  BuildContext context, {
  required int count,
}) => showFsDialog<SaveAndPlayAnswer>(
  context,
  dialog: PrDialog(
    title: count == 1
        ? 'A Scene has unsaved changes'
        : '$count Scenes have unsaved changes',
    body:
        'The game loads the Scenes saved on disk, so it will not show '
        'unsaved changes.',
    primary: const PrDialogAction(
      label: 'Save and play',
      value: SaveAndPlayAnswer.saveAndPlay,
    ),
    secondary: const PrDialogAction(
      label: 'Cancel',
      value: SaveAndPlayAnswer.cancel,
    ),
    destructive: const PrDialogAction(
      label: 'Play without saving',
      value: SaveAndPlayAnswer.playWithoutSaving,
    ),
    closeTooltip: 'Cancel',
  ),
).then((answer) => answer ?? SaveAndPlayAnswer.cancel);

/// The new-scene dialog's result (FR-008).
class NewSceneResult {
  /// Creates the result.
  const NewSceneResult({required this.name, required this.folder});

  /// The Scene's name, without the extension.
  final String name;

  /// The project-relative folder to save into, such as `assets/scenes`.
  final String folder;
}

/// Asks for the new Scene's [defaultName] and folder; [folders] lists the
/// declared asset folders, [defaultFolder] the offered one
/// (`assets/scenes`, *Q53*). While [isDeclared] says the chosen folder is
/// not one the pubspec declares, the dialog carries the warning that the
/// game cannot load from an undeclared folder — never a pubspec edit
/// (FR-008).
Future<NewSceneResult?> showNewSceneDialog(
  BuildContext context, {
  required String defaultName,
  required List<String> folders,
  required String defaultFolder,
  required bool Function(String folder) isDeclared,
}) {
  var name = defaultName;
  var folder = defaultFolder;
  return showFsDialog<NewSceneResult>(
    context,
    dialog: PrDialog<NewSceneResult>(
      title: 'New Scene',
      width: PrDialogWidth.form,
      content: _NewSceneForm(
        folders: folders,
        initialFolder: defaultFolder,
        isDeclared: isDeclared,
        onName: (value) => name = value,
        onFolder: (value) => folder = value,
      ),
      primary: PrDialogAction(
        label: 'Create',
        value: NewSceneResult(name: defaultName, folder: defaultFolder),
      ),
      secondary: const PrDialogAction(label: 'Cancel'),
    ),
  ).then((result) {
    if (result == null) return null;
    // The form's latest values win over the primary action's snapshot,
    // taken when the button was built.
    return NewSceneResult(
      name: name.isEmpty ? defaultName : name,
      folder: folder,
    );
  });
}

class _NewSceneForm extends StatefulWidget {
  const _NewSceneForm({
    required this.folders,
    required this.initialFolder,
    required this.isDeclared,
    required this.onName,
    required this.onFolder,
  });

  final List<String> folders;
  final String initialFolder;
  final bool Function(String folder) isDeclared;
  final ValueChanged<String> onName;
  final ValueChanged<String> onFolder;

  @override
  State<_NewSceneForm> createState() => _NewSceneFormState();
}

class _NewSceneFormState extends State<_NewSceneForm> {
  late final TextEditingController _name;
  late String _folder;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()
      ..addListener(() => widget.onName(_name.text));
    _folder = widget.initialFolder;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PrColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PrSpacing.s3,
      children: [
        PrTextField(
          controller: _name,
          placeholder: 'Scene name',
          autofocus: true,
        ),
        if (widget.folders.isNotEmpty)
          PrDropdown<String>(
            value: _folder,
            onChanged: (folder) {
              setState(() => _folder = folder);
              widget.onFolder(folder);
            },
            options: [
              for (final folder in widget.folders)
                PrDropdownOption(value: folder, label: folder),
            ],
          ),
        if (!widget.isDeclared(_folder))
          Row(
            spacing: PrSpacing.s2,
            children: [
              Icon(PrIcons.alertTriangle, size: 14, color: c.warning),
              Expanded(
                child: Text(
                  '"$_folder" is not declared in pubspec.yaml, so the game '
                  'cannot load Scenes from it. Pyro never edits the pubspec.',
                  style: PrText.small.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Asks how to answer a refused save (FR-010, *Q95*).
enum SaveRefusedAnswer { overwrite, reload, cancel }

/// The changed-on-disk dialog: *Overwrite* (destructive), *Reload from
/// disk*, *Cancel*.
Future<SaveRefusedAnswer> showSceneChangedOnDiskDialog(
  BuildContext context,
  String path,
) => showFsDialog<SaveRefusedAnswer>(
  context,
  dialog: PrDialog(
    title: 'The Scene file changed on disk',
    body: '"$path" changed since it was opened or last saved.',
    primary: const PrDialogAction(
      label: 'Reload from disk',
      value: SaveRefusedAnswer.reload,
    ),
    secondary: const PrDialogAction(
      label: 'Cancel',
      value: SaveRefusedAnswer.cancel,
    ),
    destructive: const PrDialogAction(
      label: 'Overwrite',
      value: SaveRefusedAnswer.overwrite,
    ),
  ),
).then((answer) => answer ?? SaveRefusedAnswer.cancel);

/// Shows why a save was refused without a way forward (*Q95*/*Q98*): the
/// Runtime gate messages.
Future<void> showSaveBlockedDialog(BuildContext context, SaveRefused reason) =>
    showFsDialog<void>(
      context,
      dialog: PrDialog(
        title: 'The Scene was not saved',
        body: '$reason',
        primary: const PrDialogAction(label: 'OK'),
      ),
    );

/// The recovery *Restore* prompt's answers (FR-009).
enum RestoreAnswer { restore, discard }

/// Offers the recovery copy of [scenePath] written at [writtenAt] (the
/// scene list on multi-copy days is v0.1; one copy per Scene today):
/// primary *Restore*, destructive *Discard*.
Future<RestoreAnswer> showRestoreDialog(
  BuildContext context, {
  required String scenePath,
  required DateTime writtenAt,
}) => showFsDialog<RestoreAnswer>(
  context,
  dialog: PrDialog(
    title: 'Recover unsaved changes?',
    body:
        'Pyro kept a recovery copy of "$scenePath" from '
        '${writtenAt.toLocal()}. Restoring it opens the Scene with '
        'those changes, unsaved.',
    primary: const PrDialogAction(
      label: 'Restore',
      value: RestoreAnswer.restore,
    ),
    secondary: const PrDialogAction(
      label: 'Cancel',
      value: RestoreAnswer.discard,
    ),
    destructive: const PrDialogAction(
      label: 'Discard',
      value: RestoreAnswer.discard,
    ),
  ),
).then((answer) => answer ?? RestoreAnswer.discard);

/// Shows the repair report of a hand-broken tree (FR-009, *Q96*): every
/// issue on its own line.
Future<void> showRepairReportDialog(
  BuildContext context, {
  required String scenePath,
  required RepairReport repairs,
}) => showFsDialog<void>(
  context,
  dialog: PrDialog(
    title: 'The Scene was repaired on open',
    body:
        '"$scenePath" had a broken tree; Pyro repaired it. The Scene '
        'is open with unsaved changes — save to write the repaired '
        'form.',
    content: Text(
      repairs.describe(),
      style: PrText.monoSmall.copyWith(
        color: PrColors.of(context).textSecondary,
      ),
    ),
    primary: const PrDialogAction(label: 'OK'),
  ),
);

/// The Type catalog's status and problems (FR-014): why the catalog is
/// stale when it is, then every [ManifestProblem] with its code, message
/// and location. The types themselves never vanish while the dialog is up
/// (*Q105*).
Future<void> showCatalogProblemsDialog(
  BuildContext context, {
  required TypeCatalog catalog,
}) {
  final c = PrColors.of(context);
  Widget line(String text, Color color) =>
      Text(text, style: PrText.small.copyWith(color: color));
  return showFsDialog<void>(
    context,
    dialog: PrDialog(
      title: 'Type catalog',
      width: PrDialogWidth.form,
      content: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: PrSpacing.s3,
              children: [
                switch (catalog.origin) {
                  ManifestStale(:final reason) => line(
                    'The types are stale — $reason. The last good types are '
                    'still in use.',
                    c.warning,
                  ),
                  ManifestAbsent() => line(
                    'This project has no annotated types, so only the '
                    'built-in kinds are available.',
                    c.textSecondary,
                  ),
                  ManifestUpToDate() => line(
                    'All types are up to date.',
                    c.textSecondary,
                  ),
                },
                if (catalog.problems.isEmpty)
                  line('The Manifest reports no problems.', c.textSecondary)
                else
                  for (final problem in catalog.problems)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: PrSpacing.s1,
                      children: [
                        Text(
                          problem.code,
                          style: PrText.monoSmall.copyWith(
                            color: problem.isWarning ? c.warning : c.error,
                          ),
                        ),
                        line(problem.message, c.textPrimary),
                        if (problem.location != null)
                          line(problem.location!, c.textSecondary),
                      ],
                    ),
              ],
            ),
          ),
        ),
      ),
      primary: const PrDialogAction(label: 'OK'),
    ),
  );
}

/// The generator's failed build (spec 007, FR-019): the file and the
/// message `build_runner` reported. The whole output is in the Console.
Future<void> showGeneratorErrorDialog(
  BuildContext context, {
  required String? file,
  required String? message,
}) {
  final c = PrColors.of(context);
  return showFsDialog<void>(
    context,
    dialog: PrDialog(
      title: 'Generator error',
      width: PrDialogWidth.form,
      content: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: PrSpacing.s2,
          children: [
            if (file != null)
              Text(
                file,
                style: PrText.monoSmall.copyWith(color: c.textSecondary),
              ),
            Text(
              message ?? 'The build failed.',
              style: PrText.small.copyWith(color: c.error),
            ),
            Text(
              'The types stay as they were until the build succeeds. The '
              "generator's whole output is in the Console.",
              style: PrText.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
      primary: const PrDialogAction(label: 'OK'),
    ),
  );
}
