part of 'editor_screen.dart';

/// Events and commands of the editor (those that call `setState` or are
/// torn off as listeners stay in [_EditorScreenState]).
extension _EditorActions on _EditorScreenState {
  void _offerTip(EditorTip tip) => _tips.offerFor(tip, _services.preferences);

  void _onStylusDetected() {
    if (_session.tools.stylusOnly != null) return _offerTip(EditorTip.penButton);
    _setStylusOnly(true);
    // The side-button tip waits for the message, rather than both at once.
    final messenger = ScaffoldMessenger.maybeOf(context)?..removeCurrentSnackBar();
    final shown = messenger == null
        ? null
        : MessageQueue.show(
            messenger,
            appSnackBar(
              context,
              'Stylus detected: fingers now pan and zoom',
              action: SnackBarAction(
                label: 'Keep finger drawing',
                onPressed: () => _setStylusOnly(false),
              ),
            ),
          );
    unawaited(
      (shown?.closed ?? Future<void>.value()).then((_) {
        if (mounted && !_closing) _offerTip(EditorTip.penButton);
      }),
    );
  }

  /// A scribble over a text box or image erased nothing and was dropped.
  void _onScribbleMissed() {
    if (mounted && !_closing) showMessage(context, 'Scribble erases ink only');
  }

  void _onMultiFingerTap(int fingers) => runMultiFingerTap(_session, fingers, _hud);

  void _setStylusOnly(bool value) {
    _session.tools.stylusOnly = value;
    _services.preferences.stylusOnly = value;
  }

  void _setFlow(PageFlow flow) {
    _services.settings.pageFlow = flow.name;
    _session.doc?.setFlow(flow);
  }

  void _toggleFocus() => _setFocus(!_focus);

  /// Enters focus mode with the laser pointer (F5: presenting), or leaves
  /// focus mode.
  void _present() {
    if (_focus) return _setFocus(false);
    final tools = _session.tools;
    _toolBeforeLaser = tools.tool;
    tools.tool = EditorTool.laser;
    _session.content.selection.clear();
    _session.content.text.end();
    _setFocus(true);
  }

  /// Turns [delta] pages on (Space / Shift+Space in focus mode).
  void _turn(int delta) {
    final doc = _session.doc;
    if (doc != null) doc.goToPage(doc.currentPage + delta);
  }

  /// Leaves this pane of the split view.
  void _closePane() => _services.openNotebooks.closeSplit();

  void _back() => widget.secondPane ? _closePane() : unawaited(Navigator.of(context).maybePop());

  void _openSettings() => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );
}
