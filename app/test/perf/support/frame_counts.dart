import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:len/features/editor/document/document_painters.dart';
import 'package:len/ink/render/ink_painters.dart';

/// What [n] frames of [step] cost after [warmUp] more: widgets rebuilt and
/// render objects painted a frame (the most frequent by type), and the
/// time a frame took in the harness.
///
/// [step] gets the frame's number and pumps it.
Future<String> countFrames(Future<void> Function(int i) step, int n, {int warmUp = 20}) async {
  for (var i = 0; i < warmUp; i++) {
    await step(i);
  }
  var rebuilds = 0;
  final built = <String, int>{};
  final painted = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    rebuilds++;
    final name = e.widget.runtimeType.toString();
    built[name] = (built[name] ?? 0) + 1;
  };
  debugProfilePaintsEnabled = true;
  debugOnProfilePaint = (r) {
    final painter = r is RenderCustomPaint ? r.painter : null;
    final name = switch (painter) {
      DocumentPaperPainter() ||
      DocumentInkPainter() ||
      CommittedInkPainter() ||
      LiveInkPainter() => 'CP:${painter.runtimeType}',
      _ => r.runtimeType.toString(),
    };
    painted[name] = (painted[name] ?? 0) + 1;
  };
  final watch = Stopwatch()..start();
  try {
    for (var i = warmUp; i < warmUp + n; i++) {
      await step(i);
    }
  } finally {
    watch.stop();
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    debugProfilePaintsEnabled = false;
  }
  String per(Map<String, int> counts) => counts.entries
      .where((e) => e.value >= n ~/ 12)
      .map((e) => '${e.key} ${(e.value / n).toStringAsFixed(1)}')
      .join(', ');
  final paints = painted.values.fold(0, (a, b) => a + b);
  return '${(rebuilds / n).toStringAsFixed(1)} rebuilds (${per(built)}), '
      '${(paints / n).toStringAsFixed(1)} paints (${per(painted)}), '
      '${(watch.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms a frame';
}
