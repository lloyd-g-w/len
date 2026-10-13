import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

import '../playback_controller.dart';
import '../recording_overview.dart';
import '../trim_range.dart';
import 'audio_format.dart';

/// The player's position control: the recording's waveform on a solid
/// track (the part already heard in the accent colour) with an Ink tick
/// at the position (the slider's thumb, DESIGN §6), above a strip showing where ink was
/// written, with a dot at the start of each burst of writing.
///
/// Tap or drag to seek; a tap on (or near) an ink dot plays from just
/// before that writing began.
///
/// Shows audio [fromMs]…[toMs] (positions in the whole recording): the
/// kept part of a trimmed recording, or all of it while trimming.
class WaveformScrubber extends StatefulWidget {
  const WaveformScrubber({
    super.key,
    this.fromMs = 0,
    required this.toMs,
    required this.positionMs,
    required this.overview,
    required this.onSeek,
    this.kept,
  });

  final int fromMs, toMs;
  final int positionMs;

  /// While trimming: the range kept (audio outside it is drawn faint).
  final TrimRange? kept;
  final RecordingOverview overview;

  /// Called with the position (ms) to play from.
  final ValueChanged<int> onSeek;

  /// Height of the waveform and of the ink strip below it.
  static const double waveHeight = 32, inkHeight = 12;

  /// Bars are this wide with this gap.
  static const double barWidth = 2.5, barGap = 1.5;

  /// Size of the Ink tick at the position (the slider's thumb).
  static const Size thumb = Size(4, 20);

  /// A tap this close (logical px) to an ink dot snaps to it.
  static const double snapDistance = 14;

  @override
  State<WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<WaveformScrubber> {
  /// Position while dragging (seeks on release).
  int? _dragging;

  int get _span => math.max(1, widget.toMs - widget.fromMs);

  int _positionAt(double dx, double width) =>
      (widget.fromMs + dx / math.max(1, width) * _span).round().clamp(widget.fromMs, widget.toMs);

  void _tap(Offset local, double width) {
    final ink = widget.overview.ink;
    int? snapped;
    var best = WaveformScrubber.snapDistance;
    for (final m in ink.markers) {
      if (m < widget.fromMs || m > widget.toMs) continue;
      final distance = ((m - widget.fromMs) / _span * width - local.dx).abs();
      if (distance <= best) {
        best = distance;
        snapped = m;
      }
    }
    widget.onSeek(
      snapped == null
          ? _positionAt(local.dx, width)
          : math.max(widget.fromMs, snapped - PlaybackController.leadMs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final position = _dragging ?? widget.positionMs;
    final step = (_span / 20).round().clamp(1000, PlaybackController.skipMs);
    final shown = position - widget.fromMs;
    return Semantics(
      slider: true,
      label: 'Playback position',
      value: formatClock(shown),
      increasedValue: formatClock(shown + step),
      decreasedValue: formatClock(shown - step),
      onIncrease: () => widget.onSeek(math.min(widget.toMs, position + step)),
      onDecrease: () => widget.onSeek(math.max(widget.fromMs, position - step)),
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            key: const ValueKey('waveform-scrubber'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition, width),
            onHorizontalDragStart: (d) =>
                setState(() => _dragging = _positionAt(d.localPosition.dx, width)),
            onHorizontalDragUpdate: (d) =>
                setState(() => _dragging = _positionAt(d.localPosition.dx, width)),
            onHorizontalDragEnd: (_) {
              final target = _dragging;
              setState(() => _dragging = null);
              if (target != null) widget.onSeek(target);
            },
            onHorizontalDragCancel: () => setState(() => _dragging = null),
            child: CustomPaint(
              size: Size(width, WaveformScrubber.waveHeight + WaveformScrubber.inkHeight),
              painter: WaveformPainter(
                overview: widget.overview,
                fromMs: widget.fromMs,
                toMs: widget.toMs,
                kept: widget.kept,
                positionMs: position,
                played: scheme.primary,
                unplayed: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                ink: scheme.primary,
                head: scheme.onSurface,
                // The docked audio strip's Board.
                halo: Surfaces.chrome(scheme),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints a [WaveformScrubber].
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.overview,
    this.fromMs = 0,
    required this.toMs,
    this.kept,
    required this.positionMs,
    required this.played,
    required this.unplayed,
    required this.ink,
    required this.head,
    required this.halo,
  });

  final RecordingOverview overview;
  final int fromMs, toMs;
  final TrimRange? kept;
  final int positionMs;
  final Color played, unplayed, ink, head;

  /// The panel behind the thumb: a ring of it sets the thumb off the bars.
  final Color halo;

  int get _span => math.max(1, toMs - fromMs);

  /// Bar heights are memoised per waveform and bar count (they are
  /// recomputed only when the width or the waveform changes).
  static final Expando<Map<String, List<double>>> _bars = Expando('waveform bars');

  List<double> _barsFor(int count) {
    final waveform = overview.waveform;
    if (waveform == null) return List.filled(count, 0);
    final byCount = _bars[waveform] ??= {};
    return byCount['$count/$fromMs/$toMs'] ??= waveform.bars(count, fromMs: fromMs, toMs: toMs);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = WaveformScrubber.barWidth + WaveformScrubber.barGap;
    final count = math.max(1, ((size.width + WaveformScrubber.barGap) / pitch).floor());
    final bars = _barsFor(count);
    final headX = ((positionMs - fromMs) / _span).clamp(0.0, 1.0) * size.width;
    const mid = WaveformScrubber.waveHeight / 2;
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    final cutPaint = Paint()..color = unplayed.withValues(alpha: unplayed.a * 0.4);
    final kept = this.kept;
    _paintTrack(canvas, size, headX, playedPaint, unplayedPaint, cutPaint);
    for (var i = 0; i < count; i++) {
      final x = i * pitch;
      final at = fromMs + (x + WaveformScrubber.barWidth / 2) / size.width * _span;
      // Silence is the track itself.
      final h = bars[i] * (WaveformScrubber.waveHeight - 2);
      if (h <= _track) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, WaveformScrubber.barWidth, h),
          const Radius.circular(WaveformScrubber.barWidth / 2),
        ),
        kept != null && (at < kept.start || at > kept.end)
            ? cutPaint
            : x + WaveformScrubber.barWidth / 2 <= headX
            ? playedPaint
            : unplayedPaint,
      );
    }
    _paintInk(canvas, size);
    final tick = Rect.fromCenter(
      center: Offset(headX, mid),
      width: WaveformScrubber.thumb.width,
      height: WaveformScrubber.thumb.height,
    );
    canvas
      ..drawRect(tick.inflate(1.5), Paint()..color = halo)
      ..drawRect(tick, Paint()..color = head);
  }

  /// Thickness of the track line.
  static const double _track = 2;

  /// The solid track along the middle: heard, still to hear, and (while
  /// trimming) cut away.
  void _paintTrack(
    Canvas canvas,
    Size size,
    double headX,
    Paint played,
    Paint unplayed,
    Paint cut,
  ) {
    const mid = WaveformScrubber.waveHeight / 2;
    void line(double from, double to, Paint paint) {
      if (to <= from) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(from, mid - _track / 2, to, mid + _track / 2),
          const Radius.circular(_track / 2),
        ),
        paint,
      );
    }

    final kept = this.kept;
    double xOf(int ms) => ((ms - fromMs) / _span).clamp(0.0, 1.0) * size.width;
    final start = kept == null ? 0.0 : xOf(kept.start);
    final end = kept == null ? size.width : xOf(kept.end);
    line(0, start, cut);
    line(start, math.min(headX, end), played);
    line(math.max(headX, start), end, unplayed);
    line(end, size.width, cut);
  }

  void _paintInk(Canvas canvas, Size size) {
    final activity = overview.ink;
    if (activity.isEmpty) return;
    const top = WaveformScrubber.waveHeight + 2;
    const stripHeight = 3.0;
    final slices = math.max(1, (size.width / 3).floor());
    final density = activity.density(slices, fromMs: fromMs, toMs: toMs);
    final sliceWidth = size.width / slices;
    for (var i = 0; i < slices; i++) {
      if (density[i] == 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(i * sliceWidth, top + 6, sliceWidth, stripHeight),
        Paint()..color = ink.withValues(alpha: 0.25 + 0.75 * density[i]),
      );
    }
    final dot = Paint()..color = ink;
    for (final m in activity.markers) {
      if (m < fromMs || m > toMs) continue;
      canvas.drawCircle(Offset((m - fromMs) / _span * size.width, top + 7.5), 3, dot);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.overview != overview ||
      old.fromMs != fromMs ||
      old.toMs != toMs ||
      old.kept != kept ||
      old.positionMs != positionMs ||
      old.played != played ||
      old.unplayed != unplayed ||
      old.ink != ink ||
      old.head != head ||
      old.halo != halo;
}
