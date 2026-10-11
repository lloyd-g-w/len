// The Ink Lab visual report (opt-in, slow):
//
//   flutter test test/inklab/report/report_test.dart --dart-define=INKLAB_REPORT=true
//
// writes build/inklab_report/index.html with, per suite entry, its metrics
// and pictures: the final ink at 1×/4×/16× with the true path, raw samples
// and centre line, a filmstrip of live frames, a frame-to-frame diff
// heatmap and the low-latency overlay sheet. See docs/INK_LAB.md.
@Tags(['inklab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../suite.dart';
import 'filmstrip.dart';
import 'final_views.dart';
import 'html.dart';
import 'overlay_sheet.dart';
import 'picture.dart';

const bool _enabled = bool.fromEnvironment('INKLAB_REPORT');
const String _dir = 'build/inklab_report';

/// Optional regex: only entries whose name matches (quick looks).
const String _only = String.fromEnvironment('INKLAB_ONLY');

void main() {
  test(
    'visual report',
    () {
      final entries = <ReportEntry>[];
      for (final e in suiteEntries()) {
        if (!RegExp(_only).hasMatch(e.name)) continue;
        final s = e.subject;
        final file = e.name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
        final images = <String, String>{};
        void save(String caption, String suffix, Picture pic) {
          final name = '$file-$suffix.png';
          pic.save('$_dir/$name');
          images[caption] = name;
        }

        final views = finalViews(s, focusOf(s, e.metrics));
        for (final MapEntry(key: zoom, value: pic) in views.entries) {
          save('final ink ${zoom}x', '${zoom}x', pic);
        }
        // Follow the contact where ink behind the tip changed (or popped).
        final live = [
          for (final id in ['temporal.behindTip', 'pop.pixels'])
            if (e.metric(id) case final m? when !m.pass) m.where,
        ].nonNulls.firstOrNull;
        save('live frames (last tile: committed)', 'film', filmstrip(s.replay, live));
        save('changes behind the tip over all frames', 'heat', diffHeatmap(s.replay, live));
        final overlay = overlaySheet(s.replay);
        if (overlay.width > 1) save('low-latency overlay, worst moments', 'overlay', overlay);
        entries.add(
          ReportEntry(
            e.name,
            e.caseName,
            e.streamline,
            s.replay.recording.meta.note,
            e.metrics,
            images,
          ),
        );
      }
      File('$_dir/index.html').writeAsStringSync(reportHtml(entries));
    },
    skip: _enabled ? false : 'opt-in: --dart-define=INKLAB_REPORT=true',
    timeout: Timeout.none,
  );
}
