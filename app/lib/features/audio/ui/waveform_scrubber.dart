import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../playback_controller.dart';
import '../recording_overview.dart';
import 'audio_format.dart';

/// The player's position control: the recording's waveform (the part
/// already heard in the accent colour) above a strip showing where ink was
/// written, with a dot at the start of each burst of writing.
///
/// Tap or drag to seek; a tap on (or near) an ink dot plays from just
/// before that writing began.
class WaveformScrubber extends StatefulWidget {
  const WaveformScrubber({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.overview,
    required this.onSeek,
  });

  final int durationMs;
  final int positionMs;
  final RecordingOverview overview;

  /// Called with the position (ms) to play from.
  final ValueChanged<int> onSeek;

  /// Height of the waveform and of the ink strip below it.
  static const double waveHeight = 32, inkHeight = 12;

  /// Bars are this wide with this gap.
  static const double barWidth = 2.5, barGap = 1.5;

  /// A tap this close (logical px) to an ink dot snaps to it.
  static const double snapDistance = 14;

  @override
  State<WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<WaveformScrubber> {
  /// Position while dragging (seeks on release).
  int? _dragging;

  int _positionAt(double dx, double width) =>
      (dx / math.max(1, width) * widget.durationMs).round().clamp(0, widget.durationMs);

  void _tap(Offset local, double width) {
    final ink = widget.overview.ink;
    final duration = math.max(1, widget.durationMs);
    int? snapped;
    var best = WaveformScrubber.snapDistance;
    for (final m in ink.markers) {
      final distance = (m / duration * width - local.dx).abs();
      if (distance <= best) {
        best = distance;
        snapped = m;
      }
    }
    widget.onSeek(
      snapped == null
          ? _positionAt(local.dx, width)
          : math.max(0, snapped - PlaybackController.leadMs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final position = _dragging ?? widget.positionMs;
    final step = (widget.durationMs / 20).round().clamp(1000, PlaybackController.skipMs);
    return Semantics(
      slider: true,
      label: 'Playback position',
      value: formatClock(position),
      increasedValue: formatClock(position + step),
      decreasedValue: formatClock(position - step),
      onIncrease: () => widget.onSeek(math.min(widget.durationMs, position + step)),
      onDecrease: () => widget.onSeek(math.max(0, position - step)),
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
                durationMs: widget.durationMs,
                positionMs: position,
                played: scheme.primary,
                unplayed: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                ink: scheme.tertiary,
                head: scheme.primary,
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
    required this.durationMs,
    required this.positionMs,
    required this.played,
    required this.unplayed,
    required this.ink,
    required this.head,
  });

  final RecordingOverview overview;
  final int durationMs;
  final int positionMs;
  final Color played, unplayed, ink, head;

  /// Bar heights are memoised per waveform and bar count (they are
  /// recomputed only when the width or the waveform changes).
  static final Expando<Map<String, List<double>>> _bars = Expando('waveform bars');

  List<double> _barsFor(int count) {
    final waveform = overview.waveform;
    if (waveform == null) return List.filled(count, 0);
    final byCount = _bars[waveform] ??= {};
    return byCount['$count/$durationMs'] ??= waveform.bars(count, durationMs: durationMs);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = WaveformScrubber.barWidth + WaveformScrubber.barGap;
    final count = math.max(1, ((size.width + WaveformScrubber.barGap) / pitch).floor());
    final bars = _barsFor(count);
    final duration = math.max(1, durationMs);
    final headX = (positionMs / duration).clamp(0.0, 1.0) * size.width;
    const mid = WaveformScrubber.waveHeight / 2;
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    for (var i = 0; i < count; i++) {
      final x = i * pitch;
      // Silence still shows as a thin line, so the track is visible.
      final h = math.max(2.0, bars[i] * (WaveformScrubber.waveHeight - 2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, WaveformScrubber.barWidth, h),
          const Radius.circular(WaveformScrubber.barWidth / 2),
        ),
        x + WaveformScrubber.barWidth / 2 <= headX ? playedPaint : unplayedPaint,
      );
    }
    _paintInk(canvas, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headX - 1, 0, 2, WaveformScrubber.waveHeight),
        const Radius.circular(1),
      ),
      Paint()..color = head,
    );
  }

  void _paintInk(Canvas canvas, Size size) {
    final activity = overview.ink;
    if (activity.isEmpty) return;
    const top = WaveformScrubber.waveHeight + 2;
    const stripHeight = 3.0;
    final slices = math.max(1, (size.width / 3).floor());
    final density = activity.density(slices, durationMs: durationMs);
    final sliceWidth = size.width / slices;
    for (var i = 0; i < slices; i++) {
      if (density[i] == 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(i * sliceWidth, top + 6, sliceWidth, stripHeight),
        Paint()..color = ink.withValues(alpha: 0.25 + 0.75 * density[i]),
      );
    }
    final duration = math.max(1, durationMs);
    final dot = Paint()..color = ink;
    for (final m in activity.markers) {
      canvas.drawCircle(Offset(m / duration * size.width, top + 7.5), 3, dot);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.overview != overview ||
      old.durationMs != durationMs ||
      old.positionMs != positionMs ||
      old.played != played ||
      old.unplayed != unplayed ||
      old.ink != ink ||
      old.head != head;
}
