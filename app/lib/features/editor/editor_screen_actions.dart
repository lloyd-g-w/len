part of 'editor_screen.dart';

/// Events and commands of the editor (those that call `setState` or are
/// torn off as listeners stay in [_EditorScreenState]).
extension _EditorActions on _EditorScreenState {
  /// The first stylus contact in this editor. The first ever turns finger
  /// drawing off, with a message; later ones offer the side-button tip (it
  /// never follows the message: one teaching moment per opening).
  void _onStylusDetected() {
    if (_session.tools.stylusOnly != null) return _tips.offer(EditorTip.penButton);
    _setStylusOnly(true);
    showMessage(
      context,
      'Stylus detected: fingers now pan and zoom',
      action: SnackBarAction(label: 'Keep finger drawing', onPressed: () => _setStylusOnly(false)),
    );
  }

  /// A scribble over a text box or image erased nothing and was dropped.
  void _onScribbleMissed() {
    if (mounted && !_closing) showMessage(context, 'Scribble erases ink only');
  }

  /// A line or shape drawn by hand: the hold to snap tip, until it was
  /// shown (then nothing looks for shapes any more).
  void _onShapeDrawn() {
    if (_tips.wantsShapes) return _tips.shapeDrawn();
    _session.input.events.shapeDrawn = null;
  }

  void _followLink(Paper target) {
    if (mounted && !_closing) _session.commands?.followLink(context, target);
  }

  void _onMultiFingerTap(int fingers) => runMultiFingerTap(_session, fingers, _hud);

  /// Also from the stylus message's action, which outlives the editor.
  void _setStylusOnly(bool value) {
    if (mounted) _session.tools.stylusOnly = value;
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
    _session.parkZoomWindow();
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
