import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording_overview.dart';
import '../trim_range.dart';
import 'audio_format.dart';
import 'waveform_scrubber.dart';

/// The waveform of a whole recording framed by trim handles: drag the
/// handle at either end of the kept audio (or focus one and press ← / →,
/// a second at a time, with Shift a tenth), tap or drag inside to move the
/// preview position. Audio outside the frame is drawn faint.
class TrimScrubber extends StatefulWidget {
  const TrimScrubber({
    super.key,
    required this.durationMs,
    required this.range,
    required this.positionMs,
    required this.overview,
    required this.onChanged,
    required this.onSeek,
  });

  final int durationMs;
  final TrimRange range;
  final int positionMs;
  final RecordingOverview overview;
  final ValueChanged<TrimRange> onChanged;

  /// Called with the position (ms) to preview from.
  final ValueChanged<int> onSeek;

  /// Width of a handle's tab (outside the kept audio).
  static const double tab = 14;

  /// Extra width around a handle that still grabs it.
  static const double slop = 8;

  @override
  State<TrimScrubber> createState() => _TrimScrubberState();
}

class _TrimScrubberState extends State<TrimScrubber> {
  final _startFocus = FocusNode(debugLabel: 'trim start');
  final _endFocus = FocusNode(debugLabel: 'trim end');

  /// Track x of the handle being dragged.
  double? _dragX;

  @override
  void initState() {
    super.initState();
    _startFocus.addListener(_refresh);
    _endFocus.addListener(_refresh);
  }

  @override
  void dispose() {
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  TrimRange _moved(bool start, int ms) => start
      ? widget.range.withStart(ms, widget.durationMs)
      : widget.range.withEnd(ms, widget.durationMs);

  int _edge(bool start, TrimRange range) => start ? range.start : range.end;

  /// After a handle moved, preview from the new start, or the last
  /// seconds before the new end.
  void _previewEdge(bool start) {
    final range = widget.range;
    widget.onSeek(start ? range.start : (range.end - 2000).clamp(range.start, range.end));
  }

  KeyEventResult _key(bool start, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final forward = key == LogicalKeyboardKey.arrowRight;
    if (!forward && key != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final step = HardwareKeyboard.instance.isShiftPressed ? 100 : 1000;
    final at = start ? widget.range.start : widget.range.end;
    widget.onChanged(_moved(start, at + (forward ? step : -step)));
    return KeyEventResult.handled;
  }

  Widget _handle(TrimTrack track, {required bool start, required double height}) {
    final range = widget.range;
    final x = TrimScrubber.tab + track.xOf(start ? range.start : range.end);
    const reach = TrimScrubber.tab + TrimScrubber.slop;
    final at = start ? range.start : range.end;
    return Positioned(
      left: start ? x - reach : x - TrimScrubber.slop,
      width: reach + TrimScrubber.slop,
      top: 0,
      height: height,
      child: Semantics(
        slider: true,
        label: start ? 'Trim start' : 'Trim end',
        value: formatClock(at),
        increasedValue: formatClock(_edge(start, _moved(start, at + 1000))),
        decreasedValue: formatClock(_edge(start, _moved(start, at - 1000))),
        onIncrease: () => widget.onChanged(_moved(start, at + 1000)),
        onDecrease: () => widget.onChanged(_moved(start, at - 1000)),
        child: Focus(
          focusNode: start ? _startFocus : _endFocus,
          onKeyEvent: (_, event) => _key(start, event),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: ValueKey(start ? 'trim-start' : 'trim-end'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => (start ? _startFocus : _endFocus).requestFocus(),
              onHorizontalDragStart: (_) => _dragX = track.xOf(at),
              onHorizontalDragUpdate: (d) {
                final dragX = (_dragX ?? track.xOf(at)) + d.delta.dx;
                _dragX = dragX;
                widget.onChanged(_moved(start, track.msAt(dragX)));
              },
              onHorizontalDragEnd: (_) {
                _dragX = null;
                _previewEdge(start);
              },
              onHorizontalDragCancel: () => _dragX = null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const height = WaveformScrubber.waveHeight + WaveformScrubber.inkHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * TrimScrubber.tab;
        final track = TrimTrack(width, widget.durationMs);
        final scheme = Theme.of(context).colorScheme;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: TrimScrubber.tab,
                width: width,
                top: 0,
                height: height,
                child: WaveformScrubber(
                  toMs: widget.durationMs,
                  positionMs: widget.positionMs,
                  overview: widget.overview,
                  kept: widget.range,
                  onSeek: widget.onSeek,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: TrimFramePainter(
                      startX: TrimScrubber.tab + track.xOf(widget.range.start),
                      endX: TrimScrubber.tab + track.xOf(widget.range.end),
                      color: scheme.primary,
                      grip: scheme.onPrimary,
                      focusedStart: _startFocus.hasFocus,
                      focusedEnd: _endFocus.hasFocus,
                      focus: scheme.tertiary,
                    ),
                  ),
                ),
              ),
              _handle(track, start: true, height: height),
              _handle(track, start: false, height: height),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the trim frame: a tab at each end of the kept audio joined by
/// thin lines above and below it.
class TrimFramePainter extends CustomPainter {
  TrimFramePainter({
    required this.startX,
    required this.endX,
    required this.color,
    required this.grip,
    required this.focus,
    this.focusedStart = false,
    this.focusedEnd = false,
  });

  final double startX, endX;
  final Color color, grip, focus;
  final bool focusedStart, focusedEnd;

  @override
  void paint(Canvas canvas, Size size) {
    const tab = TrimScrubber.tab;
    const r = Radius.circular(6);
    final fill = Paint()..color = color;
    final h = size.height;
    canvas
      ..drawRect(Rect.fromLTRB(startX, 0, endX, 2), fill)
      ..drawRect(Rect.fromLTRB(startX, h - 2, endX, h), fill);
    final left = Rect.fromLTWH(startX - tab, 0, tab, h);
    final right = Rect.fromLTWH(endX, 0, tab, h);
    canvas
      ..drawRRect(RRect.fromRectAndCorners(left, topLeft: r, bottomLeft: r), fill)
      ..drawRRect(RRect.fromRectAndCorners(right, topRight: r, bottomRight: r), fill);
    final gripPaint = Paint()
      ..color = grip
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final rect in [left, right]) {
      canvas.drawLine(rect.center.translate(0, -7), rect.center.translate(0, 7), gripPaint);
    }
    final ring = Paint()
      ..color = focus
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (focusedStart) canvas.drawRRect(RRect.fromRectAndRadius(left.inflate(2), r), ring);
    if (focusedEnd) canvas.drawRRect(RRect.fromRectAndRadius(right.inflate(2), r), ring);
  }

  @override
  bool shouldRepaint(TrimFramePainter old) =>
      old.startX != startX ||
      old.endX != endX ||
      old.color != color ||
      old.grip != grip ||
      old.focus != focus ||
      old.focusedStart != focusedStart ||
      old.focusedEnd != focusedEnd;
}
