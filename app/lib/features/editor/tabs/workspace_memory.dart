import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../../../data/settings_repository.dart';
import '../../../domain/notebook.dart';
import 'open_notebooks.dart';

/// Remembers the notebooks opened lately (the library's Recent row) and
/// the open-notebook workspace across launches (UX_AUDIT R7-6, R7-7).
///
/// While the editor is [shown], its tabs, the active tab and the split
/// view are kept in the settings store as they change and when the app is
/// hidden or a window closes (Android kills hidden apps freely). Going
/// back to the library forgets them, so the next launch shows the library;
/// otherwise [restore] opens them again. Each tab's page and zoom are kept
/// per notebook by the editor itself (`EditorLifecycle`).
class WorkspaceMemory {
  WorkspaceMemory({required this.settings, required this.tabs, required this.isClosed}) {
    tabs.addListener(_onTabs);
  }

  final SettingsRepository settings;
  final OpenNotebooks tabs;

  /// Whether the store is closed (the app is shutting down): nothing is
  /// written then.
  final bool Function() isClosed;

  /// How many notebooks [recent] keeps.
  static const int recentCount = 8;

  bool _shown = false;
  bool _listening = false;
  String? _lastActive;

  late final AppLifecycleListener _app = AppLifecycleListener(
    onHide: save,
    onExitRequested: () async {
      save();
      return AppExitResponse.exit;
    },
  );

  /// Notebooks opened lately (ids), most recent first.
  List<String> get recent => settings.recentNotebooks;

  /// Puts notebook [id] first in [recent].
  void noteOpened(String id) {
    if (isClosed()) return;
    final ids = recent;
    if (ids.isNotEmpty && ids.first == id) return;
    settings.recentNotebooks = [id, ...ids.where((r) => r != id)].take(recentCount).toList();
  }

  /// Whether the editor workspace is on screen. Leaving it for the library
  /// forgets the workspace.
  bool get shown => _shown;
  set shown(bool value) {
    _shown = value;
    if (isClosed()) return;
    if (value) {
      if (!_listening) {
        _listening = true;
        _app; // Starts listening.
      }
      if (tabs.activeId case final id?) noteOpened(id);
      save();
    } else {
      settings.workspace = null;
    }
  }

  void _onTabs() {
    final id = tabs.activeId;
    if (id != null && id != _lastActive) noteOpened(id);
    _lastActive = id;
    save();
  }

  /// Keeps the workspace as it is now (while it is [shown]).
  void save() {
    if (!_shown || isClosed()) return;
    if (tabs.isEmpty) {
      settings.workspace = null;
      return;
    }
    settings.workspace = jsonEncode({
      'tabs': [for (final t in tabs.tabs) t.id],
      'active': tabs.activeId,
      'split': tabs.splitId,
      'fraction': tabs.splitFraction,
      'splitView': tabs.splitView?.encode(),
    });
  }

  /// Opens the tabs kept when the app last went away from the editor, if
  /// it did, and returns the notebook to show (null: show the library).
  /// [lookup] finds a notebook by id; deleted and trashed ones are left
  /// out.
  Notebook? restore(Notebook? Function(String id) lookup) {
    final kept = _decode(settings.workspace);
    if (kept == null) return null;
    Notebook? find(Object? id) => switch (id is String ? lookup(id) : null) {
      final n? when !n.isTrashed => n,
      _ => null,
    };
    final open = [for (final id in kept.tabs) ?find(id)];
    if (open.isEmpty) return null;
    for (final n in open) {
      if (!tabs.contains(n.id)) tabs.open(n);
    }
    final active = find(kept.active) ?? open.last;
    tabs.activate(active.id);
    if (find(kept.split) case final split?) {
      tabs.openSplit(split.id);
      tabs.splitView = EditorViewState.decode(kept.splitView);
    }
    if (kept.fraction case final fraction?) tabs.splitFraction = fraction;
    return active;
  }

  static ({List<Object?> tabs, Object? active, Object? split, double? fraction, String? splitView})?
  _decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> || json['tabs'] is! List) return null;
      final fraction = json['fraction'];
      final splitView = json['splitView'];
      return (
        tabs: json['tabs']! as List<Object?>,
        active: json['active'],
        split: json['split'],
        fraction: fraction is num ? fraction.toDouble() : null,
        splitView: splitView is String ? splitView : null,
      );
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    tabs.removeListener(_onTabs);
    if (_listening) _app.dispose();
  }
}
