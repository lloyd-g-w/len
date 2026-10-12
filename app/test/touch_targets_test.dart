import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/folder.dart';
import 'package:len/features/library/dialogs/folder_icon_picker.dart';
import 'package:len/features/library/folder_icons.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_dot.dart';
import 'package:len/ui/even_grid.dart';

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  );
}

void main() {
  for (final (name, size, phone) in [
    ('phone', const Size(360, 740), true),
    ('desktop', const Size(1280, 800), false),
  ]) {
    testWidgets('swatch grids: 48 dp cells on phones, compact elsewhere ($name)', (tester) async {
      int? tapped;
      await pumpAt(
        tester,
        size,
        EvenGrid(
          itemExtent: 40,
          minItemExtent: 32,
          touchTargets: true,
          children: [
            for (var i = 0; i < 14; i++)
              ColorDot(color: 0xFF000000 + i, size: 40, selected: false, onTap: () => tapped = i),
          ],
        ),
      );
      final cell = tester.getRect(find.byType(ColorDot).first);
      expect(cell.width, phone ? greaterThanOrEqualTo(48) : lessThan(48));
      // A tap in the cell's corner, outside the round dot, still counts.
      await tester.tapAt(cell.topLeft + const Offset(2, 2));
      expect(tapped, 0);
    });

    testWidgets('folder icon tiles: 48 dp targets on phones ($name)', (tester) async {
      String? picked = 'none';
      await pumpAt(
        tester,
        size,
        FolderIconPicker(selected: null, color: Colors.blue, onChanged: (k) => picked = k),
      );
      final key = Folder.iconKeys.first;
      final tile = find.ancestor(
        of: find.byIcon(folderIconData(key)),
        matching: find.byType(Tooltip),
      );
      final cell = tester.getRect(tile);
      expect(cell.width, phone ? greaterThanOrEqualTo(48) : lessThan(48));
      await tester.tapAt(cell.topLeft + const Offset(1, 1));
      expect(picked, key);
    });
  }
}
