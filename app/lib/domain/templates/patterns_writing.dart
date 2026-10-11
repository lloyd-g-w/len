import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'pattern_builder.dart';
import 'patterns_basic.dart';

/// Structured writing pages: Cornell notes, to-do list, meeting notes and
/// storyboard. Page layouts only (a canvas gets ruled lines instead).
extension WritingPatterns on PatternBuilder {
  /// Cornell notes: header, cue column, note lines and a summary box.
  void cornell(Rect page) {
    final header = page.top + 3 * s;
    final summary = page.top + page.height * 0.78;
    final cue = page.left + page.width * 0.3;
    ruled(bottom: summary - s / 2);
    lines.removeWhere((l) => l.weight == PatternWeight.margin);
    h(header, page.left, page.right, PatternWeight.heavy);
    h(summary, page.left, page.right, PatternWeight.heavy);
    v(cue, header, summary, PatternWeight.heavy);
  }

  /// A checklist: a title line, then rows with a checkbox each.
  void todo(Rect page) {
    final c = content(page);
    _titleRow(c, 'To do', fields: const ['Date']);
    final top = c.top + 3.5 * s;
    final box = s * 0.45;
    for (final y in rules(top, c.bottom, c.left + box + s * 0.4, c.right)) {
      checkbox(c.left, y, box);
    }
  }

  /// Meeting notes: title, date / time / location, attendees, agenda,
  /// notes and an action-items box with checkboxes.
  void meeting(Rect page) {
    final c = content(page);
    _titleRow(c, 'Meeting');
    var y = c.top + 3 * s;
    // Date, time and location side by side.
    const fields = [('Date', 0.3), ('Time', 0.22), ('Location', 0.48)];
    const gap = 16.0;
    final usable = c.width - gap * (fields.length - 1);
    var x = c.left;
    for (final (name, share) in fields) {
      final w = usable * share;
      heading(name, x, y + s * 0.2, width: w);
      h(y + s * 1.2, x, x + w);
      x += w + gap;
    }
    y += 2.4 * s;
    for (final (name, count) in const [('Attendees', 2), ('Agenda', 3)]) {
      heading(name, c.left, y + s * 0.2);
      rules(y + 1.2 * s, y + (count + 0.2) * s, c.left, c.right);
      y += (count + 1.4) * s;
    }
    final actions = c.bottom - math.max(5.5 * s, c.height * 0.2);
    heading('Notes', c.left, y + s * 0.2);
    rules(y + 1.2 * s, actions - s * 0.8, c.left, c.right);
    final frame = Rect.fromLTRB(c.left, actions, c.right, c.bottom);
    box(frame);
    heading('Action items', c.left + 12, actions + s * 1.0);
    final checkbox = s * 0.5;
    for (final ly in rules(
      actions + 2 * s,
      c.bottom - s * 0.5,
      c.left + 24 + checkbox,
      c.right - 12,
    )) {
      this.checkbox(c.left + 12, ly, checkbox);
    }
  }

  /// Storyboard: numbered 16:9 frames with lines for notes under each.
  void storyboard(Rect page) {
    final c = content(page);
    _titleRow(c, 'Storyboard', fields: const ['Scene']);
    final grid = Rect.fromLTRB(c.left, c.top + 3 * s, c.right, c.bottom);
    final cols = page.width > page.height ? 3 : 2;
    const minGap = 20.0, minNotes = 2;
    final cellW = (grid.width - minGap * (cols - 1)) / cols;
    final frameH = cellW * 9 / 16;
    double cellHeight(int notes) => frameH + (notes + 0.9) * s;
    final rows = math.max(1, ((grid.height + minGap) / (cellHeight(minNotes) + minGap)).floor());
    // Spend the space left over on more note lines, then on the gaps.
    final slack = grid.height - rows * cellHeight(minNotes) - (rows - 1) * minGap;
    final notes = minNotes + math.max(0, (slack / rows / s).floor()).toInt();
    final cellH = cellHeight(notes);
    final gap = rows == 1 ? minGap : (grid.height - rows * cellH) / (rows - 1);
    var n = 1;
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final left = grid.left + col * (cellW + minGap);
        final top = grid.top + r * (cellH + gap);
        final frame = Rect.fromLTWH(left, top, cellW, frameH);
        box(frame);
        label('${n++}', Rect.fromLTWH(left + 6, top + 4, 40, 16), size: 10, muted: true);
        rules(top + frameH + s, top + frameH + notes * s, left, left + cellW);
      }
    }
  }

  /// A heading at the top-left, a heavy line under the title, and small
  /// [fields] (e.g. "Date") to the right.
  void _titleRow(Rect c, String title, {List<String> fields = const []}) {
    heading(title, c.left, c.top + 18);
    final line = c.top + 2 * s;
    h(line, c.left, c.right, PatternWeight.heavy);
    var right = c.right;
    for (final f in fields.reversed) {
      const w = 150.0;
      heading(f, right - w, c.top + 18, width: w);
      right -= w + 16;
    }
  }
}
