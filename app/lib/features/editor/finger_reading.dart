import 'dart:async';

import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';

/// Reading on a phone without a stylus (R20-6): while fingers draw (no
/// stylus ever seen), one finger always writes, so reading back would take
/// two fingers and a resting thumb would mark the page. This puts the
/// editor in [ToolSettings.reading] (one finger scrolls, zooms, follows
/// links, double-tap zooms and long-presses for the menu) where there is
/// something to read:
///
/// - opening ([open]) a page — or canvas — with content starts in reading;
///   an empty one in writing;
/// - choosing a tool or a quick slot starts writing (see [ToolSettings]),
///   as does adding a blank page ([write]);
/// - after [idle] without a drawing contact ([wrote]) — nothing being
///   typed or selected ([busy]) — it goes back to reading, if the page has
///   content.
///
/// Only while [applies]: no stylus seen ([ToolSettings.stylusOnly] null,
/// so fingers draw by default; once a stylus was seen fingers scroll
/// anyway, and choosing Draw with finger then is a deliberate choice) on a
/// device used with fingers ([Targets.touchFirst]: phones and tablets
/// alike — it is about finger drawing, not screen size; with a mouse
/// nothing draws by finger).
class FingerReading {
  FingerReading({
    required this.tools,
    required this._hasContent,
    bool Function()? busy,
    bool Function()? touchFirst,
  }) : _busy = busy ?? _never,
       _touchFirst = touchFirst ?? _targets,
       _tool = tools.tool {
    tools.addListener(_onTools);
  }

  static bool _never() => false;
  static bool _targets() => Targets.touchFirst;

  /// The editor's tools, whose [ToolSettings.reading] this sets.
  final ToolSettings tools;

  /// Whether the page in view (or the canvas) has anything to read: ink,
  /// text boxes, images or a PDF or scanned background.
  final FutureOr<bool> Function() _hasContent;

  /// Whether something is under way that reading would get in the way of
  /// (a text box being typed, a selection, the zoom window, a stroke).
  final bool Function() _busy;
  final bool Function() _touchFirst;

  /// How long without writing before the editor reads again.
  static const Duration idle = Duration(minutes: 2);

  /// Called whenever this put the editor in reading (the editor offers the
  /// reading tip).
  void Function()? onRead;

  /// Whether reading applies at all (see the class doc).
  bool get applies => tools.stylusOnly == null && _touchFirst();

  EditorTool _tool;
  Timer? _timer;
  bool _wrote = false;
  bool _disposed = false;

  /// The editor opened: reading if the page has content (once known),
  /// unless a contact drew or a tool was chosen meanwhile.
  void open() {
    if (!applies) return;
    _check();
  }

  /// A contact drew (ink, erasing, a tool): the idle time starts over.
  void wrote() {
    _wrote = true;
    if (!tools.reading) _arm();
  }

  /// Starts writing (a blank page added: it is there to write on).
  void write() {
    _wrote = true;
    tools.reading = false;
  }

  void _onTools() {
    final changed = tools.tool != _tool;
    _tool = tools.tool;
    if (changed) _wrote = true;
    if (tools.reading || !applies) {
      _timer?.cancel();
      _timer = null;
    } else if (changed || _timer == null) {
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = applies ? Timer(idle, _onIdle) : null;
  }

  void _onIdle() {
    _timer = null;
    if (_disposed || tools.reading || !applies) return;
    if (_busy()) return _arm();
    _check();
  }

  /// Enters reading if the page has content, unless a contact drew or a
  /// tool was chosen while that was being found out.
  void _check() {
    _wrote = false;
    final has = _hasContent();
    if (has is bool) return _settle(has);
    unawaited(has.then(_settle));
  }

  void _settle(bool hasContent) {
    if (_disposed || tools.reading) return;
    if (!hasContent || _wrote || !applies || _busy()) return _arm();
    tools.reading = true;
    onRead?.call();
  }

  /// Stops the idle timer and following the tools.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    tools.removeListener(_onTools);
  }
}
