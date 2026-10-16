import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../editor/tabs/editor_workspace.dart';
import 'library_screen.dart';

/// The routes Len launches with (`MaterialApp.onGenerateInitialRoutes`):
/// the library and, when Len last went away from the editor, the editor
/// over it with the kept tabs ([restoreWorkspace]). Both are in place for
/// the first frame; the library under the editor is built but not laid
/// out, so it renders no covers until it is shown.
List<Route<void>> launchRoutes(AppServices services) {
  final restored = restoreWorkspace(services);
  return [
    _library(const RouteSettings(name: Navigator.defaultRouteName), restored: restored),
    ?restored,
  ];
}

/// The app's named routes (`MaterialApp.onGenerateRoute`): only the
/// library. (An app without them has no navigator.)
Route<void>? namedRoute(RouteSettings settings) =>
    settings.name == Navigator.defaultRouteName ? _library(settings) : null;

Route<void> _library(RouteSettings settings, {Route<void>? restored}) => MaterialPageRoute<void>(
  settings: settings,
  builder: (_) => LibraryScreen(restored: restored),
);
