part of 'editor_screen.dart';

/// The pieces [_EditorScreenState] wires together: the session, its pane
/// in the split view, the tips and the commands.
extension _EditorParts on _EditorScreenState {
  EditorSession _newSession() => EditorSession(
    services: _services,
    shared: _shared,
    onStylusDetected: _onStylusDetected,
    initialView: widget.secondPane
        ? _services.openNotebooks.splitView
        : _services.openNotebooks.viewOf(widget.notebook.id) ??
              EditorViewState.decode(_services.settings.editorView(widget.notebook.id)),
    // The second pane leaves the zoom window to the first.
    initialZoom: widget.secondPane
        ? null
        : ZoomWindowState.decode(_services.settings.zoomWindow(widget.notebook.id)),
  );

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
