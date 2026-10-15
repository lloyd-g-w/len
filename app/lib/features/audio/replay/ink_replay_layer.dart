import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../ui/messages.dart';
import '../notebook_audio.dart';
import 'ink_replay_painter.dart';
import 'replay_target.dart';

/// Ink replay over the editor while a recording is open: fades ink, text
/// boxes and images not yet created at the playback time and, with "tap
/// ink to play" on, turns taps on them into jumps to when they were made
/// (the surface below then gets no input; drags and pinches still pan and
/// zoom). Nothing at all without an open recording.
class InkReplayLayer extends StatefulWidget {
  const InkReplayLayer({super.key, required this.audio, required this.target});

  final NotebookAudio audio;
  final ReplayTarget target;

  @override
  State<InkReplayLayer> createState() => _InkReplayLayerState();
}

class _InkReplayLayerState extends State<InkReplayLayer> {
  final ValueNotifier<int?> _wallTime = ValueNotifier(null);
  final ReplayVeils _veils = ReplayVeils();

  /// Last focal point and scale of a pan / pinch in seek mode.
  Offset? _focal;
  double _scale = 1;

  /// Where each pen touching the page in seek mode came down: the pen
  /// taps ink to play but never pans (it writes everywhere else).
  final Map<int, Offset> _pens = {};

  /// Whether a pen stroke here was explained (once per editor).
  bool _told = false;

  @override
  void initState() {
    super.initState();
    widget.audio.playback.addListener(_onPlayback);
    _onPlayback();
  }

  @override
  void didUpdateWidget(InkReplayLayer old) {
    super.didUpdateWidget(old);
    if (old.audio != widget.audio) {
      old.audio.playback.removeListener(_onPlayback);
      widget.audio.playback.addListener(_onPlayback);
    }
    if (old.target != widget.target) _veils.clear();
  }

  @override
  void dispose() {
    widget.audio.playback.removeListener(_onPlayback);
    _wallTime.dispose();
    _veils.clear();
    super.dispose();
  }

  void _onPlayback() {
    final wall = widget.audio.playback.wallTime;
    _wallTime.value = wall;
    if (wall == null) _veils.clear();
  }

  Future<void> _tap(TapUpDetails details) async {
    final createdAt = widget.target.createdAtUnder(details.localPosition);
    if (createdAt == null) return;
    final found = await widget.audio.playInk(createdAt);
    if (found || !mounted) return;
    showMessage(context, 'This ink wasn’t written during a recording');
  }

  void _scaleStart(ScaleStartDetails d) {
    _focal = d.localFocalPoint;
    _scale = 1;
  }

  static bool _isPen(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

  void _penDown(PointerDownEvent e) {
    if (_isPen(e.kind)) _pens[e.pointer] = e.localPosition;
  }

  void _penUp(PointerEvent e) => _pens.remove(e.pointer);

  /// A pen drawn across the page (to write) in seek mode: says once why
  /// it leaves no ink, with the way out.
  void _penMove(PointerMoveEvent e) {
    final down = _pens[e.pointer];
    if (down == null || _told || (e.localPosition - down).distance <= kTouchSlop) return;
    _told = true;
    final playback = widget.audio.playback;
    showMessage(
      context,
      'Tap ink to play is on',
      action: SnackBarAction(label: 'Turn off', onPressed: () => playback.tapToSeek = false),
    );
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    if (_pens.isNotEmpty) return;
    final viewport = widget.target.viewport;
    final last = _focal;
    if (last != null) viewport.panBy(d.localFocalPoint - last);
    if (d.scale != _scale && d.scale > 0) viewport.zoomAt(d.localFocalPoint, d.scale / _scale);
    _focal = d.localFocalPoint;
    _scale = d.scale;
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => widget.target.viewport.panBy(-e.scrollDelta),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.audio.playback;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        if (playback.recording == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: InkReplayPainter(
                    target: widget.target,
                    wallTime: _wallTime,
                    until: playback.veilUntil,
                    veils: _veils,
                  ),
                ),
              ),
            ),
            if (playback.tapToSeek)
              Listener(
                onPointerSignal: _signal,
                onPointerDown: _penDown,
                onPointerMove: _penMove,
                onPointerUp: _penUp,
                onPointerCancel: _penUp,
                child: GestureDetector(
                  key: const ValueKey('ink-replay-seek'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => unawaited(_tap(d)),
                  onScaleStart: _scaleStart,
                  onScaleUpdate: _scaleUpdate,
                  onScaleEnd: (_) => _focal = null,
                ),
              ),
          ],
        );
      },
    );
  }
}
