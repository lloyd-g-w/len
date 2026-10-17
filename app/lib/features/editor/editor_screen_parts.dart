part of 'editor_screen.dart';

/// The pieces [_EditorScreenState] wires together: the session, its pane
/// in the split view, the tips and the commands.
extension _EditorParts on _EditorScreenState {
  EditorSession _newSession() {
    final notebook = widget.notebook;
    final shown = widget.secondPane
        ? _services.openNotebooks.splitView
        : _services.openNotebooks.viewOf(notebook.id);
    final fresh = shown == null && !widget.secondPane;
    final kept = fresh ? keptView(_services, notebook) : null;
    final session = EditorSession(
      services: _services,
      shared: _shared,
      onStylusDetected: _onStylusDetected,
      initialView: shown ?? kept,
      // The second pane leaves the zoom window to the first.
      initialZoom: widget.secondPane
          ? null
          : ZoomWindowState.decode(_services.settings.zoomWindow(notebook.id)),
    );
    // Opened afresh (not a tab shown again): it may move on to where
    // another device wrote since (R16-4).
    if (session.doc case final doc? when fresh) {
      final from = doc.currentPage;
      unawaited(
        writtenElsewhere(_services, notebook, kept).then((page) {
          if (page != null && mounted) doc.resumeAt(page, from: from);
        }),
      );
    }
    return session;
  }

  SplitPane _newPane() => SplitPane(
    session: _session,
    secondary: widget.secondPane,
    area: () => _areaKey.currentContext?.findRenderObject() as RenderBox?,
    showMessage: (message) {
      if (mounted) showMessage(context, message);
    },
    // Leaving focus mode puts back the tool in both panes.
    onLeave: () {
      if (_focus) _setFocus(false, disposing: true);
    },
  );

  TipsController _newTips() =>
      TipsController(
        seen: (id) => _services.settings.seenTips.contains(id),
        markSeen: _services.settings.markTipSeen,
        lastShownAt: () => _services.settings.lastTipAt,
        shownAt: (ms) => _services.settings.lastTipAt = ms,
        clock: _services.clock,
      )..followTools(
        _session.tools,
        hasPdf: () => _session.pdf?.hasPdf ?? false,
        selection: Listenable.merge([_session.content.selection, _session.pdf?.selection]),
        selected: () =>
            !_session.content.selection.isEmpty || !(_session.pdf?.selection.isEmpty ?? true),
        curveSelected: () => _session.content.selection.shapeStroke?.shape?.kind == ShapeKind.curve,
        attaching: () => _session.content.selection.attachHint != null,
        pen: _session.live,
        lasso: _session.content.lassoPath,
        penButton: () => _services.preferences.penButtonAction,
      );

  EditorScreenCommands _newCommands() => EditorScreenCommands(
    back: _back,
    rename: () => unawaited(renameNotebook(context, _shared)),
    toggleFocus: _toggleFocus,
    setStylusOnly: _setStylusOnly,
    openSettings: _openSettings,
    setFlow: _setFlow,
    pickBackground: () => unawaited(pickCanvasBackground(context, _shared)),
    openSearch: _search.open,
  );
}
