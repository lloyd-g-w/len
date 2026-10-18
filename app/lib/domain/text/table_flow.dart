import 'rich_text_buffer.dart';
import 'text_data.dart';

/// A table split between the boxes of a chain flowing across pages
/// (`TextFlow`) stays one table when one box is edited on its own (pages
/// shown one at a time): what was done to the table's columns there —
/// columns inserted or removed, widths, the header — is done to its parts
/// in the boxes before and after it too, so the chain joins into one
/// table again.
abstract final class TableFlow {
  /// [parts] (a chain's texts, head first) with part [edited] just
  /// edited: its first table, if it goes on from the part before, and its
  /// last, if it goes on into the part after, give their columns to those
  /// parts' tables (through [TableSpec.columnIds]; the parts around keep
  /// the columns they were read with). A line left after a table going on
  /// into the next part (the editor keeps one after a table) goes.
  static void carry(List<TextData> parts, int edited) {
    var data = parts[edited];
    final hasNext = edited + 1 < parts.length && _goesOn(parts[edited + 1]);
    if (hasNext) data = _withoutLineAfter(data);
    parts[edited] = data;
    final tables = TextTables.of(data.paras);
    if (tables.isEmpty) return;
    if (_goesOn(data)) {
      final spec = tables.first.spec;
      for (var k = edited - 1; k >= 0; k--) {
        final t = TextTables.of(parts[k].paras).lastOrNull;
        if (t == null || t.end != parts[k].lineCount) break;
        parts[k] = _reshaped(parts[k], t, spec);
        if (t.line > 0 || !_goesOn(parts[k])) break;
      }
    }
    final last = tables.last;
    if (hasNext && last.end == data.lineCount) {
      for (var k = edited + 1; k < parts.length && _goesOn(parts[k]); k++) {
        final t = TextTables.of(parts[k].paras).first;
        parts[k] = _reshaped(parts[k], t, last.spec);
        if (t.end != parts[k].lineCount) break;
      }
    }
  }

  /// Whether [data] begins with a table going on from the box before.
  static bool _goesOn(TextData data) => data.paras.firstOrNull?.cell?.spec.continued ?? false;

  /// [data] without an empty last line after a table.
  static TextData _withoutLineAfter(TextData data) {
    final paras = data.paras;
    final n = paras.length;
    if (n < 2 || paras[n - 1].isCell || paras[n - 2].cell == null) return data;
    final buffer = RichTextBuffer(data);
    if (buffer.lineAt(n - 1).text.isNotEmpty) return data;
    buffer.spliceLines(n - 1, n, const []);
    return buffer.toData(data);
  }

  /// [data] with its table [t] given the columns of [spec]: a column of
  /// [t] (ids 0, 1, … as read) where [spec] has its id, an empty one where
  /// [spec] has a column [t] lacks; [spec]'s widths and header, [t]'s
  /// continuation.
  static TextData _reshaped(TextData data, TextTable t, TableSpec spec) {
    final ids = spec.columnIds;
    final shape = TableSpec(spec.widths, header: spec.header, continued: t.spec.continued);
    final buffer = RichTextBuffer(data);
    final lines = <BufferLine>[];
    for (var r = 0; r < t.rows; r++) {
      for (final id in ids) {
        final line = t.lineOf(r, id);
        final cell = ParaStyle(cell: TextTableCell(shape, first: lines.isEmpty));
        final keep = id >= 0 && id < t.columns && line < t.end;
        lines.add(
          keep
              ? (text: buffer.lineAt(line).text, chars: buffer.lineAt(line).chars, para: cell)
              : (text: '', chars: const <SpanStyle>[], para: cell),
        );
      }
    }
    buffer.spliceLines(t.line, t.end, lines);
    return buffer.toData(data);
  }
}
