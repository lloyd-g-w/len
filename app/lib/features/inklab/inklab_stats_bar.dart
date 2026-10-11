import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ink/lab/lab_stats.dart';
import '../../ink/render/stroke_renderer.dart';
import '../../ui/app_theme.dart';
import 'inklab_session.dart';

/// Live figures for the Ink Lab, refreshed four times a second (never per
/// input event, so the bar itself costs next to nothing): digitiser rate,
/// samples per frame, frame build / raster times, the time to build the
/// live stroke's outline, and counts.
class InkLabStatsBar extends StatefulWidget {
  const InkLabStatsBar({super.key, required this.session, this.replaying = false});

  final InkLabSession session;

  /// Whether the figures come from a recording being replayed.
  final bool replaying;

  /// How often the bar refreshes.
  static const Duration period = Duration(milliseconds: 250);

  @override
  State<InkLabStatsBar> createState() => _InkLabStatsBarState();
}

class _InkLabStatsBarState extends State<InkLabStatsBar> {
  late final Timer _timer;
  double _outlineMs = 0, _maxOutlineMs = 0;
  int _outlinePoints = 0;
  LabStats? _stats;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(InkLabStatsBar.period, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final session = widget.session;
    if (!identical(session.stats, _stats)) {
      _stats = session.stats; // Cleared: start the maxima afresh.
      _outlineMs = _maxOutlineMs = 0;
      _outlinePoints = 0;
    }
    final live = session.live;
    if (live.isDrawing) {
      final points = live.points;
      final watch = Stopwatch()..start();
      StrokeRenderer.buildPath(
        points,
        tool: live.tool,
        width: live.width,
        style: live.style,
        complete: false,
      );
      _outlineMs = watch.elapsedMicroseconds / 1000;
      _maxOutlineMs = math.max(_maxOutlineMs, _outlineMs);
      _outlinePoints = points.length;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.stats;
    String ms(double v) => v.toStringAsFixed(1);
    final items = [
      if (widget.replaying) 'replay',
      '${s.sampleHz.round()} Hz',
      '${s.samplesPerFrame.toStringAsFixed(1)} samples/frame',
      'build ${ms(s.buildMs)} (max ${ms(s.maxBuildMs)}) ms',
      'raster ${ms(s.rasterMs)} (max ${ms(s.maxRasterMs)}) ms',
      'latency ${ms(s.latencyMs)} ms',
      'outline ${ms(_outlineMs)} (max ${ms(_maxOutlineMs)}) ms @ $_outlinePoints pts',
      '${s.samples} samples',
      '${s.contacts} contacts',
      '${session.strokeCount} strokes',
      '${session.recorder.entries.length} entries',
    ];
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
        child: Wrap(
          spacing: Gaps.md,
          runSpacing: Gaps.xxs,
          children: [
            for (final item in items)
              Text(item, style: theme.textTheme.labelSmall?.copyWith(fontFeatures: _tabular)),
          ],
        ),
      ),
    );
  }

  static const _tabular = [FontFeature.tabularFigures()];
}
