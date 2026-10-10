import 'package:path_provider/path_provider.dart';

/// The application-support directory, created if missing (it is not
/// guaranteed to exist on desktop).
Future<String> appDataDirectory() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return dir.path;
}
