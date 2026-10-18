import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/features/fonts/font_import.dart';
import 'package:len/ink/fonts/text_fonts.dart';
import 'package:len/ui/app_theme.dart';

import 'support/font_fixtures.dart';

void main() {
  tearDown(TextFonts.reset);

  testWidgets('importing says what happened: added, already here, not a font', (tester) async {
    final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(s.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    Future<void> pick(Uint8List bytes, String name) async {
      await tester.runAsync(
        () => FontImport.pick(
          context,
          file: XFile.fromData(bytes, name: name, path: name),
        ),
      );
      await tester.pump();
    }

    await pick(caveatFile(), 'Caveat-Regular.ttf');
    expect(find.text('Added “Caveat”'), findsOneWidget);
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await pick(caveatFile(), 'Caveat copy.ttf');
    expect(find.text('“Caveat” is already in your fonts'), findsOneWidget);
    expect(s.fonts.fonts, hasLength(1));
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    // Why it was refused, said at once (no Details to open).
    await pick(Uint8List.fromList(List.filled(64, 7)), 'notes.otf');
    expect(find.text('“notes.otf” isn’t a TrueType or OpenType font'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });
}
