import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/text/text_data.dart';
import '../../../ink/elements/text_layout.dart';

/// The tables of a text box for screen readers: a table node per table,
/// a row node per row and a cell node per cell (a column header in a
/// header row) reading the cell's text, each where it is laid out. Placed
/// in the box's own node, [offset] (screen pixels) from its top left at
/// [scale] screen pixels per world unit.
class TextTableSemantics extends StatelessWidget {
  const TextTableSemantics({
    super.key,
    required this.data,
    required this.width,
    required this.offset,
    required this.scale,
  });

  final TextData data;

  /// The box's width, in world units.
  final double width;
  final Offset offset;
  final double scale;

  /// [data]'s text before its first table (what the box's node reads; the
  /// text after each table is a node of its own after the table's).
  static String textBefore(TextData data) {
    final first = TextTables.of(data.paras).firstOrNull?.line ?? data.lineCount;
    return data.text.split('\n').take(first).join('\n').trim();
  }

  /// The text of [lines] from [from] up to [to] (between tables).
  static String _between(List<String> lines, int from, int to) =>
      lines.sublist(from, to).join('\n').trim();

  @override
  Widget build(BuildContext context) {
    final layout = TextLayout.layout(data, width);
    final rows = layout.rows;
    final tables = layout.tables;
    final height = layout.height;
    layout.dispose();
    final lines = data.text.split('\n');
    Rect screen(Rect r) =>
        Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale, r.bottom * scale);
    return Stack(
      children: [
        for (final (k, t) in tables.indexed)
          if (rows.where((r) => r.table == k).toList() case final own when own.isNotEmpty)
            Positioned.fromRect(
              rect: screen(own.map((r) => r.rect).reduce((a, b) => a.expandToInclude(b)))
                  .shift(offset),
              child: Semantics(
                role: SemanticsRole.table,
                container: true,
                explicitChildNodes: true,
                child: Stack(
                  children: [
                    for (final r in own)
                      Positioned.fromRect(
                        rect: screen(r.rect.shift(-own.first.rect.topLeft)),
                        child: Semantics(
                          role: SemanticsRole.row,
                          container: true,
                          explicitChildNodes: true,
                          child: Stack(
                            children: [
                              for (var c = 0; c < t.table.columns; c++)
                                Positioned.fromRect(
                                  rect: screen(t.cellRect(r.rect, r.row, c).shift(-r.rect.topLeft)),
                                  child: Semantics(
                                    role: t.table.spec.hasHeaderRow && r.row == 0
                                        ? SemanticsRole.columnHeader
                                        : SemanticsRole.cell,
                                    container: true,
                                    label: t.table.lineOf(r.row, c) < t.table.end
                                        ? lines[t.table.lineOf(r.row, c)]
                                        : '',
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        // The text after each table, read after it.
        for (final (k, t) in tables.indexed)
          if (_between(
                lines,
                t.table.end,
                k + 1 < tables.length ? tables[k + 1].table.line : lines.length,
              )
              case final after when after.isNotEmpty)
            if (rows.where((r) => r.table == k).lastOrNull?.rect.bottom case final top?)
              Positioned.fromRect(
                rect: screen(
                  Rect.fromLTRB(
                    0,
                    top,
                    width,
                    rows.where((r) => r.table == k + 1).firstOrNull?.rect.top ?? height,
                  ),
                ).shift(offset),
                child: Semantics(container: true, label: after, child: const SizedBox.expand()),
              ),
      ],
    );
  }
}
