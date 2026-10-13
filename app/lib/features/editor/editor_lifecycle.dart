import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../ui/messages.dart';
import 'editor_session.dart';

/// Ties one editor to the app and to sync: remembers where it looks (when
/// the app is hidden and when the editor closes), closes the editor when
/// the notebook is deleted on another device, and after edits marks the
/// notebook edited and syncs. (Remote changes to the notebook itself are
/// followed by its `SharedNotebook`.)
///
/// A feature that must react to the app going to the background or to the
/// editor closing hooks in here.
class EditorLifecycle {
  EditorLifecycle({
    required this.services,
    required this.session,
    required this.secondPane,
    required this.inWorkspace,
  });

  final AppServices services;
  final EditorSession session;

  /// The split view's second pane keeps its place in memory only (it may
  /// show the same notebook as the first).
  final bool secondPane;

  /// Shown in the editor workspace (tabs, split view), not on its own.
  final bool inWorkspace;

  Notebook get _notebook => session.notebook;

  /// Set once the editor is leaving because its notebook was deleted
  /// remotely: nothing more is written to it.
  bool closing = false;

  /// Commits a text box being typed and saves where the editor looks when
  /// the app goes to the background (it may be killed there without
  /// [dispose]).
  late final AppLifecycleListener _app = AppLifecycleListener(
    onHide: () {
      session.content.text.end();
      saveView();
    },
  );

  void start() {
    _app; // Starts listening.
  }

  /// Remembers this notebook's page, zoom and pan for the next launch.
  void saveView() {
    if (closing || secondPane || services.database.isClosed) return;
    services.settings.setEditorView(_notebook.id, session.viewState.encode());
  }

  /// The notebook was deleted (or [trashed]) on another device: closes
  /// the editor seen from [context] together with what it opened on top
  /// (dialogs, sheets, pages; [owner] in [AppServices.routeOwners]) — but
  /// not what the split view's other pane opened. Nothing in progress is
  /// written to the deleted notebook. The message goes to [announce] if
  /// given (the other pane: this one's messages would go with it).
  void closeDeleted(
    BuildContext context, {
    required bool trashed,
    required Object owner,
    bool Function(String message)? announce,
  }) {
    closing = true;
    session.input.cancelDraw();
    session.content.text.discard();
    session.content.selection.clear();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    final message =
        '“${_notebook.title}” was ${trashed ? 'moved to the trash' : 'deleted'} '
        'on another device';
    if (!(announce?.call(message) ?? false)) showMessage(context, message);
    final routes = services.routeOwners;
    if (routes.tracking) {
      routes.closeRoutesOf(owner);
    } else if (!secondPane && route != null && route.isActive) {
      navigator.popUntil((r) => r == route); // Untracked: all of them.
    }
    final tabs = services.openNotebooks;
    if (tabs.contains(_notebook.id)) {
      tabs.close(_notebook.id); // The workspace shows another tab or leaves.
      return;
    }
    // In the workspace, the other view of the notebook closed its tab.
    if (inWorkspace || route == null || !route.isActive) return;
    navigator
      ..popUntil((r) => r == route)
      ..pop();
  }

  /// Stops listening and keeps where the editor looks: in its tab (or, in
  /// the second pane, the split view) and for the next launch. Called
  /// while the session is still alive.
  void dispose() {
    final tabs = services.openNotebooks;
    if (secondPane) {
      // Not after a swap: the pane now shows another notebook.
      if (tabs.splitId == _notebook.id) tabs.splitView = session.viewState;
    } else {
      tabs.saveView(_notebook.id, session.viewState);
    }
    saveView();
    _app.dispose();
  }

  /// After the session is gone: if anything was [edited], bumps the
  /// notebook's "last edited" and syncs.
  void finish({required bool edited}) {
    if (!edited) return;
    services.notebooks.touch(_notebook.id);
    // Deferred: syncing notifies listeners (e.g. the library's sync button),
    // which must not happen while the tree is locked during dispose.
    final sync = services.sync;
    scheduleMicrotask(() => unawaited(sync.syncInBackground()));
  }
}
