import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/app_database.dart';
import 'platform/app_directory.dart';
import 'platform/blob_backend.dart';
import 'platform/single_instance.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: one tab at a time owns the database.
  await claimSingleInstance(onWaiting: () => runApp(const _OpenElsewhere()));
  // Natively: files in the app-support directory. Web: IndexedDB.
  final dir = await appDataDirectory();
  final database = await AppDatabase.openDefault(dir);
  final services = AppServices.create(database, blobBackend: await openBlobBackend(dir))
    ..sync.start();
  runApp(LenApp(services: services));
  // Throttled to once a day; deletes blobs unreferenced for a week.
  unawaited(services.blobGc.runIfDue());
}

/// Shown in a browser tab while Len is open in another tab.
class _OpenElsewhere extends StatelessWidget {
  const _OpenElsewhere();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Len',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(Gaps.lg),
          child: Text(
            'Len is open in another tab.\nClose it to continue here.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
