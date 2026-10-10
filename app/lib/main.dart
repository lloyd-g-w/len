import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true); // Not guaranteed to exist on desktop.
  final database = AppDatabase.open(p.join(dir.path, 'len.db'));
  final services = AppServices.create(database)..sync.start();
  runApp(LenApp(services: services));
}
