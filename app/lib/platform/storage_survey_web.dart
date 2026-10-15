import '../data/app_database.dart';
import '../data/storage_queries.dart';

/// [StorageQueries.survey] on the app's connection: a Web Worker cannot
/// share the database (see ARCHITECTURE, *Platforms*). [keep]: notebooks
/// whose files must stay.
Future<StorageSurvey> surveyStorage(AppDatabase database, {Set<String> keep = const {}}) async =>
    StorageQueries(database.db).survey(keep: keep);
