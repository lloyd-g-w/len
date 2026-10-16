part of 'editor_screen.dart';

/// Connecting [_EditorScreenState] to the session, the app's services and
/// the split view, and disconnecting it again.
extension _EditorWiring on _EditorScreenState {
  /// Wires the editor up (from `initState`).
  void _start() {
    _session.gestures
      ..onMultiFingerTap = _onMultiFingerTap
      ..onContextMenu = _openMenu
      ..onTwoFingerHold = _togglePresenting;
    _lifecycle.start();
    // Created now: it takes a result the library asked to show.
    _search = EditorSearchController.forSession(_services, _session, notebookId: _notebook.id);
    _services.openNotebooks.addListener(_onTabs);
    _services.preferences.addListener(_onPreferences);
    _audio.onNotice = _onAudioNotice;
    _session.input.events
      ..scribbleMissed = _onScribbleMissed
      ..shapeDrawn = _tips.wantsShapes ? _onShapeDrawn : null
      ..fingerStroke = _tips.seen(EditorTip.fingers.name) ? null : _onFingerStroke;
    // Reading where there is something to read, while fingers draw (R20-6).
    _session.reading
      ..onRead = _onReading
      ..open();
    _services.incomingFiles.targets.add(_importTarget);
    // Of two editors (split view), files go to the one used last.
    _focusNode.addListener(_onFocus);
    attachPdfLinks(context, _session);
    if (_pane case final pane?) widget.split!.attach(pane);
    // Take the keyboard even when another editor (the previous tab) still
    // held it while this one was built; autofocus would not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _showRecordingsIfAsked();
  }

  /// Takes the editor apart again (from `dispose`).
  void _stop() {
    // A text box still being typed is committed while the split view
    // still mirrors this editor's edits into the other pane, and focus
    // mode puts back the tool (shared, with linked tools) before the view
    // is saved.
    if (!_closing) _session.content.text.end(); // Counts as an edit below.
    if (_focus) _setFocus(false, disposing: true); // (`detach` shows the other pane.)
    if (_pane case final pane?) widget.split!.detach(pane);
    _focusNode.removeListener(_onFocus);
    _services.incomingFiles.targets.remove(_importTarget);
    _services.routeOwners.forget(this);
    _services.openNotebooks.removeListener(_onTabs);
    _lifecycle.dispose();
    _services.preferences.removeListener(_onPreferences);
    final edited = _session.edited;
    _search.dispose();
    if (_audio.onNotice == _onAudioNotice) _audio.onNotice = null;
    _session.dispose(); // Commits a text box still being edited.
    _shared.removeListener(_onShared);
    // The last editor of the notebook disposes what they shared (and
    // saves a running recording).
    _services.sharedNotebooks.release(_shared);
    _lifecycle.finish(edited: edited);
    _hud.dispose();
    _tips.dispose();
    _toolbar.dispose();
    _guard.dispose();
    _eyedropper.dispose();
    _focusNode.dispose();
  }

  /// Shows the recordings list once shown, if it was asked for (Settings →
  /// Storage opens a notebook at its recordings).
  void _showRecordingsIfAsked() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _parked || _closing) return;
    if (_services.openNotebooks.takeRecordingsRequest(widget.notebook.id)) {
      // Where the bar's audio button is: the top right corner.
      final box = context.findRenderObject()! as RenderBox;
      final corner = box.localToGlobal(box.size.topRight(Offset.zero));
      final anchor = Rect.fromLTWH(corner.dx - Targets.bar, corner.dy, Targets.bar, Targets.bar);
      unawaited(showRecordingsSheet(context, _audio, anchor: anchor));
    }
  });

  /// This editor is the one in use (focused, files dropped on it): the
  /// split view's, and where files and dialogs go.
  void _use() {
    if (_pane case final pane?) widget.split!.use(pane);
    _services.incomingFiles.targets.add(_importTarget);
    _services.routeOwners.current = this; // Dialogs opened by keyboard.
  }
}
