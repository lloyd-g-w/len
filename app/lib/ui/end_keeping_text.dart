import 'package:flutter/material.dart';

/// A title that, when it doesn't fit in [maxLines], keeps its last word and
/// cuts the middle instead ("Electronics — Lec… 12"): titles sharing a long
/// start ("Electronics — Lecture 11", "… 12") stay told apart where the end
/// would be cut off. A last word too wide to keep (over a third of the
/// line) ends the text in an ellipsis as usual. Screen readers get it whole.
class EndKeepingText extends StatelessWidget {
  const EndKeepingText(this.text, {super.key, this.style, this.maxLines = 1});

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = fitKeepingEnd(
          text,
          style: style,
          maxWidth: constraints.maxWidth,
          maxLines: maxLines,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        );
        return Text(
          shown,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          semanticsLabel: shown == text ? null : text,
        );
      },
    );
  }
}

/// [text] as [EndKeepingText] shows it in [maxLines] lines of [maxWidth]:
/// unchanged when it fits (or can't keep its end), else the longest start
/// that fits before "… " and the last word.
String fitKeepingEnd(
  String text, {
  required TextStyle? style,
  required double maxWidth,
  int maxLines = 1,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return text;
  final painter = TextPainter(
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
  );
  bool fits(String s) {
    painter
      ..text = TextSpan(text: s, style: style)
      ..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }

  try {
    final trimmed = text.trimRight();
    if (fits(trimmed)) return text;
    final cut = trimmed.lastIndexOf(' ');
    if (cut <= 0) return text;
    final tail = '… ${trimmed.substring(cut + 1)}';
    painter
      ..text = TextSpan(text: tail, style: style)
      ..layout();
    if (painter.width > maxWidth / 3) return text;
    final head = trimmed.substring(0, cut).trimRight().characters.toList();
    // The longest start that fits (the tail alone does: it is narrow).
    var lo = 0, hi = head.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits('${head.take(mid).join().trimRight()}$tail')) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo == 0) return text;
    return '${head.take(lo).join().trimRight()}$tail';
  } finally {
    painter.dispose();
  }
}
