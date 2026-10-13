import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/app_preferences.dart';
import '../../../domain/preferences.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// One-time hints about input that has no visible affordance.
enum EditorTip {
  /// The stylus side button (after the first stylus contact).
  penButton,

  /// Tapping with two fingers to undo, three to redo (after a few taps on
  /// ↶ on a touch device).
  gestureUndo,

  /// What the lasso does (the first time it is picked; it has no options).
  lasso,

  /// Hold to snap (after a line or shape drawn by hand, once the pen has
  /// rested a moment).
  holdToSnap,

  /// Scribble to erase (the second time the eraser is picked).
  scribble,
}

/// What a shown tip says.
@immutable
class TipMessage {
  const TipMessage(this.tip, this.icon, this.text);

  final EditorTip tip;
  final IconData icon;
  final String text;
}

/// Shows each [EditorTip] once per device, for [visibleFor] or until
/// dismissed. Tips that don't apply to the current settings (e.g. the side
/// button does nothing) are never shown.
class TipsController extends ValueNotifier<TipMessage?> {
  TipsController({required this.seen, required this.markSeen}) : super(null);

  /// Whether a tip was already shown on this device, and recording that.
  final bool Function(String id) seen;
  final void Function(String id) markSeen;

  static const Duration visibleFor = Duration(seconds: 10);

  /// How long the pen must rest after a hand-drawn shape before
  /// [EditorTip.holdToSnap] shows: never while writing on.
  static const Duration calmFor = Duration(seconds: 2);

  Timer? _timer;
  Timer? _calm;
  int _undoTaps = 0;
  int _eraserPicks = 0;
  int Function() _activity = _none;
  ToolSettings? _tools;
  EditorTool? _tool;
  bool Function()? _hasPdf;
  Listenable? _selection;
  bool Function() _selected = _nothing;

  static bool _nothing() => false;
  static int _none() => 0;

  /// Offers [EditorTip.lasso] the first time [tools] switch to the lasso
  /// (mentioning PDF text where the notebook [hasPdf]). The tip never
  /// covers a selection: it waits while something is [selected] and goes
  /// as soon as a selection is made (the user did what it says; [selection]
  /// notifies) or another tool is picked. The second pick of the eraser
  /// offers [EditorTip.scribble] (with scribble to erase on). [activity]
  /// changes whenever the pen writes (see [shapeDrawn]).
  void followTools(
    ToolSettings tools, {
    bool Function()? hasPdf,
    Listenable? selection,
    bool Function()? selected,
    int Function()? activity,
  }) {
    _tools = tools..addListener(_onTools);
    _tool = tools.tool;
    _hasPdf = hasPdf;
    _selection = selection?..addListener(_onSelection);
    _selected = selected ?? _nothing;
    _activity = activity ?? _none;
  }

  void _onTools() {
    final tools = _tools!;
    final tool = tools.tool;
    if (tool == _tool) return;
    _tool = tool;
    if (tool == EditorTool.eraser && ++_eraserPicks == 2 && tools.scribbleToErase) {
      offer(EditorTip.scribble);
    }
    if (tool != EditorTool.lasso) {
      if (value?.tip == EditorTip.lasso) dismiss();
    } else if (!_selected()) {
      offer(EditorTip.lasso, pdf: _hasPdf?.call() ?? false);
    }
  }

  /// Whether [EditorTip.holdToSnap] is still to be shown (the editor then
  /// looks for hand-drawn shapes).
  bool get wantsShapes => !seen(EditorTip.holdToSnap.name);

  /// A line or shape was drawn by hand with hold to snap on: once the pen
  /// has rested for [calmFor] (no new ink: [activity] unchanged), offers
  /// [EditorTip.holdToSnap]. Writing on puts it off to the next shape.
  void shapeDrawn() {
    final tools = _tools;
    if (!wantsShapes || (tools != null && !tools.holdToStraighten)) return;
    final at = _activity();
    _calm?.cancel();
    _calm = Timer(calmFor, () {
      if (_activity() == at && (_tools?.holdToStraighten ?? true)) offer(EditorTip.holdToSnap);
    });
  }

  void _onSelection() {
    if (value?.tip == EditorTip.lasso && _selected()) dismiss();
  }

  /// The ↶ button was tapped. On a touch device with finger-tap undo on,
  /// the third tap in this editor offers [EditorTip.gestureUndo]: the
  /// gesture saves reaching for the top of the screen.
  void undoTapped(AppPreferences preferences) {
    if (!Targets.touchFirst || !preferences.fingerTapUndo) return;
    if (++_undoTaps == 3) offer(EditorTip.gestureUndo);
  }

  /// Offers [tip] as [preferences] have it (the pen button's action).
  void offerFor(EditorTip tip, AppPreferences preferences) =>
      offer(tip, penButton: preferences.penButtonAction);

  /// Offers [tip], phrased for the current settings ([penButton]) and
  /// notebook ([pdf]: it has PDF pages).
  void offer(
    EditorTip tip, {
    PenButtonAction penButton = PenButtonAction.eraser,
    bool pdf = false,
  }) {
    if (seen(tip.name) || value?.tip == tip) return;
    final message = switch (tip) {
      EditorTip.penButton => switch (penButton) {
        PenButtonAction.eraser => TipMessage(
          tip,
          Symbols.draw_sharp,
          'Hold the pen’s side button to erase',
        ),
        PenButtonAction.lasso => TipMessage(
          tip,
          Symbols.highlight_alt_sharp,
          'Hold the pen’s side button to select with the lasso',
        ),
        PenButtonAction.none => null,
      },
      EditorTip.gestureUndo => TipMessage(
        tip,
        Symbols.touch_app_sharp,
        'Tap with two fingers to undo, three to redo',
      ),
      EditorTip.holdToSnap => TipMessage(
        tip,
        Symbols.shape_line_sharp,
        'Hold the pen still at the end of a line or shape to snap it clean',
      ),
      EditorTip.scribble => TipMessage(
        tip,
        Symbols.ink_eraser_sharp,
        'Or scribble over ink with the pen to erase it',
      ),
      EditorTip.lasso => TipMessage(
        tip,
        Symbols.highlight_alt_sharp,
        pdf
            ? 'Circle ink, text or images to select them; tap PDF text to select it'
            : 'Circle ink, text or images to select them',
      ),
    };
    if (message == null) return;
    markSeen(message.tip.name);
    value = message;
    _timer?.cancel();
    _timer = Timer(visibleFor, dismiss);
  }

  /// Hides the current tip.
  void dismiss() {
    _timer?.cancel();
    value = null;
  }

  @override
  void dispose() {
    _tools?.removeListener(_onTools);
    _selection?.removeListener(_onSelection);
    _timer?.cancel();
    _calm?.cancel();
    super.dispose();
  }
}

/// The current tip as a small card (icon, text, close), fading in and out.
class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.controller});

  final TipsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, message, _) => AnimatedSwitcher(
        duration: Motion.medium,
        switchInCurve: Motion.emphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: message == null
            ? const SizedBox.shrink()
            : Semantics(
                key: ValueKey(message.tip),
                liveRegion: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: FloatingPanel(
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(message.icon, size: Glyphs.menu, color: scheme.onSurfaceVariant),
                          const SizedBox(width: Gaps.sm),
                          Flexible(child: Text(message.text, style: theme.textTheme.bodyMedium)),
                          IconButton(
                            tooltip: 'Dismiss tip',
                            iconSize: Glyphs.menu,
                            // A full touch target on touch, compact with a pointer.
                            visualDensity: Targets.touchFirst ? null : VisualDensity.compact,
                            onPressed: controller.dismiss,
                            icon: const Icon(Symbols.close_sharp),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
