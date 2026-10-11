import '../known_failures.dart';
import '../metrics/metric.dart';

/// One suite entry in the report: its metrics and image files.
class ReportEntry {
  ReportEntry(this.name, this.caseName, this.streamline, this.note, this.metrics, this.images);
  final String name, caseName, note;
  final double streamline;
  final List<Metric> metrics;

  /// Caption → file name (relative to the report directory).
  final Map<String, String> images;
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _row(ReportEntry e, Metric m) {
  final known = knownFailure(m.id, e.caseName, e.streamline);
  final status = m.pass ? 'ok' : (known != null ? 'known' : 'fail');
  final label = switch (status) {
    'ok' => 'ok',
    'known' => 'known: ${_esc(known!.finding)}',
    _ => 'FAIL',
  };
  final where = m.where == null
      ? ''
      : '(${m.where!.dx.toStringAsFixed(1)}, ${m.where!.dy.toStringAsFixed(1)})';
  return '<tr class="$status"><td>${m.id}</td><td>${_esc(m.formatted)}</td>'
      '<td>$label</td><td>$where</td><td>${_esc(m.note)}</td></tr>';
}

/// The report's `index.html`: a summary table, then per entry its metrics
/// and pictures.
String reportHtml(List<ReportEntry> entries) {
  final b = StringBuffer()
    ..writeln('<!doctype html><meta charset="utf-8"><title>Ink Lab report</title>')
    ..writeln('<style>$_css</style><h1>Ink Lab report</h1>')
    ..writeln(
      '<p>Colours: ink grey; <b style="color:#00a050">true path</b>, '
      '<b style="color:#e0302a">raw samples</b>, <b style="color:#2f6fe0">centre line</b>. '
      'Filmstrip: red = changed behind the tip, blue = changed at the tip, '
      'magenta = changed at pen-up. Overlay: dark = Flutter now, light = Flutter once caught '
      'up, blue = overlay, red = ghost, orange = gap. See docs/INK_LAB.md.</p>',
    )
    ..writeln('<table><tr><th>entry</th><th>ok</th><th>known</th><th>fail</th></tr>');
  for (final e in entries) {
    var ok = 0, known = 0, fail = 0;
    for (final m in e.metrics) {
      if (m.pass) {
        ok++;
      } else if (knownFailure(m.id, e.caseName, e.streamline) != null) {
        known++;
      } else {
        fail++;
      }
    }
    b.writeln(
      '<tr><td><a href="#${e.name}">${e.name}</a></td><td>$ok</td>'
      '<td>$known</td><td class="${fail > 0 ? 'fail' : ''}">$fail</td></tr>',
    );
  }
  b.writeln('</table>');
  for (final e in entries) {
    b
      ..writeln('<h2 id="${e.name}">${e.name}</h2><p>${_esc(e.note)}</p>')
      ..writeln(
        '<table><tr><th>metric</th><th>value</th><th>status</th>'
        '<th>where (px)</th><th>note</th></tr>',
      );
    for (final m in e.metrics) {
      b.writeln(_row(e, m));
    }
    b.writeln('</table>');
    for (final MapEntry(key: caption, value: file) in e.images.entries) {
      b.writeln(
        '<figure><img src="$file" loading="lazy"><figcaption>$caption</figcaption>'
        '</figure>',
      );
    }
  }
  return b.toString();
}

const String _css = '''
body{font:14px system-ui,sans-serif;margin:24px;color:#222}
table{border-collapse:collapse;margin:8px 0}td,th{border:1px solid #ccc;padding:2px 6px}
tr.ok td:nth-child(3){color:#080}tr.known td:nth-child(3){color:#a60}
tr.fail td:nth-child(3),td.fail{color:#c00;font-weight:bold}
figure{display:inline-block;margin:8px;vertical-align:top}img{max-width:100%;border:1px solid #ddd}
''';
