import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// A version row's words as one render object: the title (up to two
/// lines) with the time after its first line's baseline, the details below
/// (up to three lines). Where the title's longest word has no room beside
/// the time (a narrow phone at a large text size), the time begins the
/// details line instead ([timeBelow]), so the title wraps between words. Lays out as the row's `Row(Flexible(title), gap,
/// time)` over `Text(details)` did, with a fraction of the widgets (the
/// history builds a screen of rows a frame when it jumps). Screen readers
/// read the row's label instead.
class VersionRowText extends LeafRenderObjectWidget {
  const VersionRowText({
    super.key,
    required this.title,
    required this.time,
    required this.details,
    required this.titleStyle,
    required this.timeStyle,
    required this.detailsStyle,
    required this.textScaler,
    required this.textDirection,
  });

  /// Whether the time goes on the details line: [title] laid out with
  /// [titleStyle] at [scaler] has a word wider than what [time] (with
  /// [timeStyle]) and the gap between them leave of [width].
  static bool timeBelow({
    required String title,
    required TextStyle? titleStyle,
    required String time,
    required TextStyle? timeStyle,
    required TextScaler scaler,
    required double width,
  }) {
    TextPainter painter(String text, TextStyle? style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout();
    final t = painter(title, titleStyle), m = painter(time, timeStyle);
    final below = _wordWider(t, m, width);
    t.dispose();
    m.dispose();
    return below;
  }

  /// Whether laid-out [title] has a word wider than the room [time] and
  /// the gap leave of [width].
  static bool _wordWider(TextPainter title, TextPainter time, double width) =>
      title.minIntrinsicWidth > width - Gaps.sm - time.width + 0.01;

  /// The style each text gets as a [Text] would ([DefaultTextStyle]'s,
  /// merged with [style]).
  static TextStyle styleOf(BuildContext context, TextStyle? style) =>
      DefaultTextStyle.of(context).style.merge(style);

  final String title;
  final String time;
  final String details;
  final TextStyle titleStyle;
  final TextStyle timeStyle;
  final TextStyle detailsStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  @override
  RenderVersionRowText createRenderObject(BuildContext context) => RenderVersionRowText(this);

  @override
  void updateRenderObject(BuildContext context, RenderVersionRowText renderObject) =>
      renderObject.text = this;
}

/// The render object of [VersionRowText].
class RenderVersionRowText extends RenderBox {
  RenderVersionRowText(VersionRowText text) : _text = text {
    _configure();
  }

  VersionRowText _text;
  set text(VersionRowText value) {
    final old = _text;
    _text = value;
    if (old.title == value.title &&
        old.time == value.time &&
        old.details == value.details &&
        old.titleStyle == value.titleStyle &&
        old.timeStyle == value.timeStyle &&
        old.detailsStyle == value.detailsStyle &&
        old.textScaler == value.textScaler &&
        old.textDirection == value.textDirection) {
      return;
    }
    _timeBelow = false;
    _configure();
    markNeedsLayout();
  }

  /// Puts the time at the start of the details line, or takes it off.
  void _placeTime(bool below) {
    if (below == _timeBelow) return;
    _timeBelow = below;
    final t = _text;
    _details.text = below
        ? TextSpan(
            children: [
              TextSpan(text: t.time, style: t.timeStyle),
              TextSpan(text: ' · ${t.details}', style: t.detailsStyle),
            ],
          )
        : TextSpan(text: t.details, style: t.detailsStyle);
  }

  final _title = TextPainter(maxLines: 2, ellipsis: '\u2026');
  final _time = TextPainter(maxLines: 1);
  final _details = TextPainter(maxLines: 3, ellipsis: '\u2026');

  /// Where the time and details sit (the title at the top left).
  var _timeAt = Offset.zero;
  var _detailsAt = Offset.zero;
  var _titleTop = 0.0;

  /// Whether the time begins the details line (see [VersionRowText]).
  var _timeBelow = false;

  void _configure() {
    final t = _text;
    for (final (painter, text, style) in [
      (_title, t.title, t.titleStyle),
      (_time, t.time, t.timeStyle),
      (_details, t.details, t.detailsStyle),
    ]) {
      painter
        ..text = TextSpan(text: text, style: style)
        ..textScaler = t.textScaler
        ..textDirection = t.textDirection;
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _time.layout();
    final gap = Gaps.sm;
    // The title flexes into what the time and the gap leave, unless a
    // word of it would not fit there: then it takes the whole width.
    _title.layout(maxWidth: math.max(0, width - gap - _time.width));
    _placeTime(VersionRowText._wordWider(_title, _time, width));
    if (_timeBelow) _title.layout(maxWidth: width);
    final titleBaseline = _title.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final timeBaseline = _timeBelow
        ? 0.0
        : _time.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final above = math.max(titleBaseline, timeBaseline);
    _titleTop = above - titleBaseline;
    final timeTop = above - timeBaseline;
    final line = math.max(_titleTop + _title.height, _timeBelow ? 0.0 : timeTop + _time.height);
    final ltr = _text.textDirection == TextDirection.ltr;
    final timeX = _title.width + gap;
    _timeAt = Offset(ltr ? timeX : width - timeX - _time.width, timeTop);
    _details.layout(maxWidth: width);
    _detailsAt = Offset(ltr ? 0 : width - _details.width, line);
    size = constraints.constrain(Size(width, line + _details.height));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _titleTop + _title.computeDistanceToActualBaseline(baseline);

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final ltr = _text.textDirection == TextDirection.ltr;
    final titleX = ltr ? 0.0 : size.width - _title.width;
    _title.paint(canvas, offset + Offset(titleX, _titleTop));
    if (!_timeBelow) _time.paint(canvas, offset + _timeAt);
    _details.paint(canvas, offset + _detailsAt);
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    _details.dispose();
    super.dispose();
  }
}
