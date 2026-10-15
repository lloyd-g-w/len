import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../domain/preferences.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/selection/lasso_path.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/messages.dart';
import 'tip_message.dart';

export 'tip_message.dart';

/// Shows each [EditorTip] once per device, on a calm budget (R9-1):
/// - at most one tip per editor (each opening of a notebook), at least
///   [between] apart (across openings), none within [afterMessage] of a
///   snack bar anywhere in the app ([MessageQueue.activity]);
/// - only once the pen has rested for [calmFor]; the tip fades while the
///   pen is down ([writing]), and its time stops meanwhile. Drawing a lasso
///   loop or a shape counts as the pen being down;
/// - a tip never replaces another: a trigger while one shows is dropped,
///   and waits for its next trigger;
/// - a tip counts as seen after [seenAfter] on screen; one that goes
///   sooner stays due for a later opening;
/// - of tips due at once, the first in [EditorTip]'s order wins.
///
/// Tips that don't apply to the current settings (e.g. the side button
/// does nothing) are never shown.
class TipsController extends ValueNotifier<TipMessage?> {
  TipsController({
    required this.seen,
    required this.markSeen,
    int? Function()? lastShownAt,
    void Function(int ms)? shownAt,
    this.clock = const Clock(),
    MessageActivity? messages,
  }) : _lastShownAt = lastShownAt ?? _never,
       _shownAt = shownAt ?? _ignore,
       _messages = messages ?? MessageQueue.activity,
       super(null);

  /// Whether a tip was already seen on this device, and recording that.
  final bool Function(String id) seen;
  final void Function(String id) markSeen;

  /// When a tip last showed (ms since the epoch, by [clock]), and recording
  /// that.
  final int? Function() _lastShownAt;
  final void Function(int ms) _shownAt;
  final Clock clock;

  /// Whether a snack bar is up, and when one last was (app-wide, so a
  /// snack bar in another notebook counts too).
  final MessageActivity _messages;

  static int? _never() => null;
  static void _ignore(int _) {}
  static bool _nothing() => false;
  static PenButtonAction _eraser() => PenButtonAction.eraser;

  /// How long a tip stays up (time with the pen down or behind a snack bar
  /// doesn't count).
  static const Duration visibleFor = Duration(seconds: 10);

  /// On screen this long, a tip counts as seen.
  static const Duration seenAfter = Duration(seconds: 3);

  /// How long the pen must rest before a tip shows: never mid-writing.
  static const Duration calmFor = Duration(seconds: 2);

  /// The least time between two tips.
  static const Duration between = Duration(minutes: 10);

  /// No tip this soon after a snack bar (anywhere in the app).
  static const Duration afterMessage = Duration(seconds: 60);

  static const Duration _tick = Duration(milliseconds: 250);

  /// Whether the pen is down: the tip fades meanwhile.
  ValueListenable<bool> get writing => _writing;
  final _writing = ValueNotifier(false);

  final Set<EditorTip> _due = {};
  bool _pdf = false;
  bool _spent = false;
  bool _disposed = false;
  bool _rested = true;
  Timer? _rest;
  Timer? _ticker;
  Duration _shownFor = Duration.zero;
  int _eraserPicks = 0;
  ToolSettings? _tools;
  EditorTool? _tool;
  LiveInk? _pen;
  LassoPath? _lasso;
  bool Function()? _hasPdf;
  Listenable? _selection;
  bool Function() _selected = _nothing;
  PenButtonAction Function() _penButton = _eraser;

  /// Follows [tools]: picking the lasso offers [EditorTip.lasso] (mentioning
  /// PDF text where the notebook [hasPdf]) unless something is [selected];
  /// a selection ([selection] notifies) is the tip done. Picking the eraser
  /// a second time offers [EditorTip.scribble]. Any change of [pen] (the
  /// live ink: pens, the highlighter, shapes) or of [lasso] (the loop being
  /// drawn) is pen activity. [penButton] is what the side button does.
  void followTools(
    ToolSettings tools, {
    bool Function()? hasPdf,
    Listenable? selection,
    bool Function()? selected,
    LiveInk? pen,
    LassoPath? lasso,
    PenButtonAction Function()? penButton,
  }) {
    _tools = tools..addListener(_onTools);
    _tool = tools.tool;
    _hasPdf = hasPdf;
    _selection = selection?..addListener(_onSelection);
    _selected = selected ?? _nothing;
    _pen = pen?..addListener(_onPen);
    _lasso = lasso?..addListener(_onPen);
    _penButton = penButton ?? _eraser;
  }

  void _onTools() {
    final tool = _tools!.tool;
    if (tool == _tool) return;
    _tool = tool;
    if (tool == EditorTool.eraser && ++_eraserPicks >= 2) offer(EditorTip.scribble);
    if (tool == EditorTool.lasso) offer(EditorTip.lasso, pdf: _hasPdf?.call() ?? false);
    if (value case final shown? when !_applies(shown.tip)) _hide();
  }

  void _onSelection() {
    // The user did what the lasso tip says.
    if (value?.tip == EditorTip.lasso && _selected()) _hide(done: true);
  }

  void _onPen() {
    final down = (_pen?.isDrawing ?? false) || !(_lasso?.isEmpty ?? true);
    // Writing on puts hold to snap off to the next shape.
    if (down && !_writing.value) _due.remove(EditorTip.holdToSnap);
    _writing.value = down;
    _rested = false;
    _rest?.cancel();
    _rest = Timer(calmFor, () {
      _rested = true;
      _tryShow();
    });
  }

  bool get _messageUp => _messages.value;

  /// Whether a snack bar is up, or was less than [afterMessage] ago.
  bool _nearMessage(int now) {
    final last = _messages.lastUpAt;
    return last != null && now - last < afterMessage.inMilliseconds;
  }

  /// Whether [EditorTip.holdToSnap] is still to be shown (the editor then
  /// looks for hand-drawn shapes).
  bool get wantsShapes => !seen(EditorTip.holdToSnap.name);

  /// A line or shape was drawn by hand: offers [EditorTip.holdToSnap].
  void shapeDrawn() => offer(EditorTip.holdToSnap);

  /// Offers [tip] (phrased for a notebook with PDF pages if [pdf]). It shows
  /// once the pen rests, if the budget allows; otherwise it waits for its
  /// next trigger.
  void offer(EditorTip tip, {bool pdf = false}) {
    if (_spent || value != null || seen(tip.name) || !_applies(tip)) return;
    _due.add(tip);
    if (tip == EditorTip.lasso) _pdf = pdf;
    // After the event at hand: a stylus contact is the trigger of the
    // side-button tip, and its stroke begins right after.
    scheduleMicrotask(_tryShow);
  }

  bool _applies(EditorTip tip) {
    final tools = _tools;
    return switch (tip) {
      // Automatic only: someone who chose finger drawing knows.
      EditorTip.fingers => tools == null || tools.stylusOnly == null,
      EditorTip.penButton => _penButton() != PenButtonAction.none,
      EditorTip.holdToSnap => tools?.holdToStraighten ?? true,
      EditorTip.lasso => (tools == null || tools.tool == EditorTool.lasso) && !_selected(),
      EditorTip.scribble =>
        tools == null || (tools.tool == EditorTool.eraser && tools.scribbleToErase),
    };
  }

  /// Shows the first due tip if the pen rests and the budget allows; the
  /// others wait for their next trigger.
  void _tryShow() {
    if (_disposed || _due.isEmpty || !_rested || _writing.value) return;
    final due = [..._due]..sort((a, b) => a.index - b.index);
    _due.clear();
    final now = clock.nowMs(), last = _lastShownAt();
    if (_spent || value != null || _nearMessage(now)) return;
    if (last != null && now - last < between.inMilliseconds) return;
    for (final tip in due) {
      if (seen(tip.name) || !_applies(tip)) continue;
      final message = tipMessage(
        tip,
        penButton: _penButton(),
        lasso: _tools?.lasso.shape ?? LassoShape.freehand,
        pdf: _pdf,
      );
      if (message == null) continue;
      _spent = true;
      _shownAt(now);
      _shownFor = Duration.zero;
      value = message;
      _ticker = Timer.periodic(_tick, _onTick);
      return;
    }
  }

  void _onTick(Timer _) {
    // Time behind a snack bar or under the pen doesn't count.
    if (_messageUp || _writing.value) return;
    _shownFor += _tick;
    if (_shownFor == seenAfter) markSeen(value!.tip.name);
    if (_shownFor >= visibleFor) _hide();
  }

  /// Hides the tip; [done] (the user did what it says) counts it as seen.
  void _hide({bool done = false}) {
    if (value case final shown? when done) markSeen(shown.tip.name);
    _ticker?.cancel();
    value = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _tools?.removeListener(_onTools);
    _selection?.removeListener(_onSelection);
    _pen?.removeListener(_onPen);
    _lasso?.removeListener(_onPen);
    _rest?.cancel();
    _ticker?.cancel();
    _writing.dispose();
    super.dispose();
  }
}
