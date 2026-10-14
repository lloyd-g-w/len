import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/notebook_style.dart';
import '../domain/preferences.dart';
import 'settings_repository.dart';

/// Observable view of the user's preferences, backed by [SettingsRepository].
///
/// Getters always read the store (cheap, indexed key lookups), so values
/// written elsewhere (e.g. the editor setting [stylusOnly]) are never stale.
/// Setters persist and notify listeners — the app rebuilds its theme from
/// this, and the editor can listen for gesture settings.
class AppPreferences extends ChangeNotifier {
  AppPreferences(this._settings);

  final SettingsRepository _settings;

  ThemePreference get themeMode => _settings.themeMode;
  set themeMode(ThemePreference value) => _update(() => _settings.themeMode = value);

  /// Only the stylus draws; fingers pan and zoom. Null = not decided yet.
  bool? get stylusOnly => _settings.stylusOnly;
  set stylusOnly(bool? value) => _update(() => _settings.stylusOnly = value);

  /// Two-finger tap on the canvas undoes, three-finger tap redoes.
  bool get fingerTapUndo => _settings.fingerTapUndo;
  set fingerTapUndo(bool value) => _update(() => _settings.fingerTapUndo = value);

  /// Holding the pen still at the end of a stroke snaps it to a clean line
  /// or shape.
  bool get holdToSnap => _settings.holdToSnap;
  set holdToSnap(bool value) => _update(() => _settings.holdToSnap = value);

  /// A quick back-and-forth scribble with the pen over ink erases it.
  bool get scribbleToErase => _settings.scribbleToErase;
  set scribbleToErase(bool value) => _update(() => _settings.scribbleToErase = value);

  /// What holding the stylus side button does.
  PenButtonAction get penButtonAction => _settings.penButtonAction;
  set penButtonAction(PenButtonAction value) => _update(() => _settings.penButtonAction = value);

  /// The zoom window's box docks under the top chrome instead of above
  /// the bottom: a left hand writing in it then hides none of the page.
  bool get zoomBoxAtTop => _settings.zoomBoxAtTop;
  set zoomBoxAtTop(bool value) => _update(() => _settings.zoomBoxAtTop = value);

  /// Where the editor toolbar sits.
  ToolbarPlacement get toolbarPlacement => _settings.toolbarPlacement;
  set toolbarPlacement(ToolbarPlacement value) => _update(() => _settings.toolbarPlacement = value);

  /// Whether infinite canvases show the minimap.
  bool get canvasMinimap => _settings.canvasMinimap;
  set canvasMinimap(bool value) => _update(() => _settings.canvasMinimap = value);

  /// Whether the minimap stays shown in focus mode ("pinned").
  bool get minimapInFocus => _settings.minimapInFocus;
  set minimapInFocus(bool value) => _update(() => _settings.minimapInFocus = value);

  /// Centre of the floating toolbar, as fractions of the editor's size.
  (double, double)? get toolbarFloat => _settings.toolbarFloat;
  set toolbarFloat((double, double)? value) => _update(() => _settings.toolbarFloat = value);

  /// Where the focus-mode tool puck sits, as fractions of the editor's size.
  (double, double)? get puckFloat => _settings.puckFloat;
  set puckFloat((double, double)? value) => _update(() => _settings.puckFloat = value);

  LibraryLayout get libraryLayout => _settings.libraryLayout;
  set libraryLayout(LibraryLayout value) => _update(() => _settings.libraryLayout = value);

  LibrarySort get librarySort => _settings.librarySort;
  set librarySort(LibrarySort value) => _update(() => _settings.librarySort = value);

  /// Paper styles (by name) of the latest new notebooks, most recent first
  /// (the new-notebook sheet offers them).
  List<String> get recentPapers => _settings.recentPapers;

  /// Puts [name] first in [recentPapers] (keeping a few).
  void notePaperUsed(String name) =>
      _settings.recentPapers = [name, ...recentPapers.where((n) => n != name)].take(12).toList();

  /// What the last new notebook was made as: where the new-notebook sheet
  /// starts when no notebook style is the default. Null before the first
  /// (or when unreadable).
  NotebookChoice? get lastNotebookChoice {
    final json = _settings.lastNotebookChoice;
    if (json == null) return null;
    try {
      final value = jsonDecode(json);
      return value is Map<String, Object?> ? NotebookChoice.fromJson(value) : null;
    } on FormatException {
      return null;
    }
  }

  set lastNotebookChoice(NotebookChoice? value) =>
      _settings.lastNotebookChoice = value == null ? null : jsonEncode(value.toJson());

  void _update(VoidCallback write) {
    write();
    notifyListeners();
  }
}
