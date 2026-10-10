import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/app_database.dart';
import 'platform/app_directory.dart';
import 'platform/blob_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Natively: files in the app-support directory. Web: IndexedDB.
  final dir = await appDataDirectory();
  final database = await AppDatabase.openDefault(dir);
  final services = AppServices.create(database, blobBackend: await openBlobBackend(dir))
    ..sync.start();
  runApp(LenApp(services: services));
}
