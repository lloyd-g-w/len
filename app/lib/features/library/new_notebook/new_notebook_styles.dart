part of '../new_notebook_sheet.dart';

/// The form's notebook styles: pick one at the top (the Styles row, once
/// there are any), save the form as one at the end ("Save as style…"), so
/// a first notebook's form starts with what it makes (UX_AUDIT R12-5).
extension _NewNotebookStyles on _NewNotebookSheetState {
  /// What the form shows, as a style; null with a user's image template.
  NotebookChoice? get _choice =>
      NotebookChoice.of(kind: _kind, template: _template, coverColor: _cover);

  /// The style the form matches, if any.
  String? get _matchingStyle {
    final choice = _choice;
    for (final style in _styles) {
      if (style.choice == choice) return style.id;
    }
    return null;
  }

  /// "Styles" and its row; nothing before the first style.
  List<Widget> _styleSection() {
    if (_styles.isEmpty) return const [];
    return [
      const SizedBox(height: Gaps.xl),
      const PickerLabel('Styles'),
      StyleRow(
        styles: _styles,
        selected: _matchingStyle,
        onApply: _applyStyle,
        onMenu: (style, at) => unawaited(_styleMenu(style, at)),
      ),
    ];
  }

  /// "Save as style…" under the form; nothing when the form is a style
  /// already or can't be one (a user's image template).
  List<Widget> _saveStyleLink() {
    final choice = _choice;
    if (choice == null || _matchingStyle != null || AppScope.maybeRead(context) == null) {
      return const [];
    }
    return [
      const SizedBox(height: Gaps.lg),
      SaveStyleButton(onPressed: () => unawaited(_saveStyle(choice))),
    ];
  }

  Future<void> _saveStyle(NotebookChoice choice) async {
    final repo = AppScope.read(context).notebookStyles;
    final saved = await saveNotebookStyle(context, repo, choice, suggested: _paper.label);
    if (saved != null) _reloadStyles();
  }

  Future<void> _styleMenu(NotebookStyle style, Offset at) async {
    final repo = AppScope.read(context).notebookStyles;
    if (await showNotebookStyleMenu(context, repo, style, at: at)) _reloadStyles();
  }
}
