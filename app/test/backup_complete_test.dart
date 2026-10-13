import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/features/backup/len_file_flows.dart';

/// Only a complete library backup counts as the last backup: one missing
/// files that aren't downloaded yet is saved, but the library keeps
/// suggesting a backup.
void main() {
  Future<bool> backUp(WidgetTester tester, AppServices services, LenWriteReport? written) async {
    late BuildContext context;
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return backupLibraryFlow(
      context,
      export: (_, scope, {required name, toDevice = false}) async {
        expect(scope.kind, LenArchiveKind.library);
        return written;
      },
    );
  }

  late AppServices services;
  setUp(
    () => services = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend()),
  );
  tearDown(() => services.dispose());

  testWidgets('a complete backup is remembered', (tester) async {
    final report = LenWriteReport(records: 3, blobs: 1, missingBlobs: 0);
    expect(await backUp(tester, services, report), isTrue);
    expect(services.settings.lastBackupAt, isNotNull);
  });

  testWidgets('a backup with missing files is not', (tester) async {
    final report = LenWriteReport(records: 3, blobs: 1, missingBlobs: 2);
    expect(await backUp(tester, services, report), isFalse);
    expect(services.settings.lastBackupAt, isNull);
  });

  testWidgets('nor a cancelled one', (tester) async {
    expect(await backUp(tester, services, null), isFalse);
    expect(services.settings.lastBackupAt, isNull);
  });
}
