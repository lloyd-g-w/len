import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// A version row's words as one render object: the title (up to two
/// lines) with the time after its first line's baseline, the details below
/// (up to three lines). Lays out as the row's `Row(Flexible(title), gap,
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
    _configure();
    markNeedsLayout();
  }

  final _title = TextPainter(maxLines: 2, ellipsis: '\u2026');
  final _time = TextPainter(maxLines: 1);
  final _details = TextPainter(maxLines: 3, ellipsis: '\u2026');

  /// Where the time and details sit (the title at the top left).
  var _timeAt = Offset.zero;
  var _detailsAt = Offset.zero;
  var _titleTop = 0.0;

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
    // The title flexes into what the time and the gap leave.
    _title.layout(maxWidth: math.max(0, width - gap - _time.width));
    final titleBaseline = _title.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final timeBaseline = _time.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final above = math.max(titleBaseline, timeBaseline);
    _titleTop = above - titleBaseline;
    final timeTop = above - timeBaseline;
    final line = math.max(_titleTop + _title.height, timeTop + _time.height);
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
    _time.paint(canvas, offset + _timeAt);
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
