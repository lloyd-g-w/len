import 'package:flutter/foundation.dart';

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

  /// ARGB seed colour of the colour scheme; null means the default accent.
  int? get accentColor => _settings.accentColor;
  set accentColor(int? value) => _update(() => _settings.accentColor = value);

  /// Only the stylus draws; fingers pan and zoom. Null = not decided yet.
  bool? get stylusOnly => _settings.stylusOnly;
  set stylusOnly(bool? value) => _update(() => _settings.stylusOnly = value);

  /// Two-finger tap on the canvas undoes.
  bool get twoFingerTapUndo => _settings.twoFingerTapUndo;
  set twoFingerTapUndo(bool value) => _update(() => _settings.twoFingerTapUndo = value);

  /// Three-finger tap on the canvas redoes.
  bool get threeFingerTapRedo => _settings.threeFingerTapRedo;
  set threeFingerTapRedo(bool value) => _update(() => _settings.threeFingerTapRedo = value);

  /// What holding the stylus side button does.
  PenButtonAction get penButtonAction => _settings.penButtonAction;
  set penButtonAction(PenButtonAction value) => _update(() => _settings.penButtonAction = value);

  /// Android: low-latency (front-buffered) ink overlay, experimental.
  bool get lowLatencyInk => _settings.lowLatencyInk;
  set lowLatencyInk(bool value) => _update(() => _settings.lowLatencyInk = value);

  /// Where the editor toolbar sits.
  ToolbarPlacement get toolbarPlacement => _settings.toolbarPlacement;
  set toolbarPlacement(ToolbarPlacement value) => _update(() => _settings.toolbarPlacement = value);

  /// Whether the toolbar shows tool names under the icons (wide screens).
  bool get toolbarLabels => _settings.toolbarLabels;
  set toolbarLabels(bool value) => _update(() => _settings.toolbarLabels = value);

  /// Centre of the floating toolbar, as fractions of the editor's size.
  (double, double)? get toolbarFloat => _settings.toolbarFloat;
  set toolbarFloat((double, double)? value) => _update(() => _settings.toolbarFloat = value);

  LibraryLayout get libraryLayout => _settings.libraryLayout;
  set libraryLayout(LibraryLayout value) => _update(() => _settings.libraryLayout = value);

  LibrarySort get librarySort => _settings.librarySort;
  set librarySort(LibrarySort value) => _update(() => _settings.librarySort = value);

  void _update(VoidCallback write) {
    write();
    notifyListeners();
  }
}
