import 'package:flutter/widgets.dart';

import 'core/clock.dart';
import 'data/app_database.dart';
import 'data/element_repository.dart';
import 'data/notebook_repository.dart';
import 'data/page_repository.dart';
import 'data/settings_repository.dart';
import 'data/stroke_repository.dart';
import 'sync/sync_api.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_engine.dart';

/// Composition root: constructs and owns the app's long-lived services.
class AppServices {
  AppServices._({
    required this.database,
    required this.settings,
    required this.notebooks,
    required this.pages,
    required this.strokes,
    required this.elements,
    required this.sync,
  });

  /// Wires up all services on [database]. [syncApiFactory] lets tests
  /// substitute the sync transport.
  factory AppServices.create(
    AppDatabase database, {
    Clock clock = const Clock(),
    SyncApi Function(String url, String token)? syncApiFactory,
  }) {
    final settings = SettingsRepository(database);
    final deviceId = settings.deviceId(clock);
    final strokes = StrokeRepository(database, deviceId: deviceId, clock: clock);
    final elements = ElementRepository(database, deviceId: deviceId, clock: clock);
    final pages = PageRepository(database, deviceId: deviceId, clock: clock);
    final notebooks = NotebookRepository(
      database,
      deviceId: deviceId,
      pages: pages,
      strokes: strokes,
      elements: elements,
      clock: clock,
    );
    final engine = SyncEngine(
      database: database,
      settings: settings,
      notebooks: notebooks,
      pages: pages,
      strokes: strokes,
      elements: elements,
    );
    return AppServices._(
      database: database,
      settings: settings,
      notebooks: notebooks,
      pages: pages,
      strokes: strokes,
      elements: elements,
      sync: syncApiFactory == null
          ? SyncController(engine: engine, settings: settings)
          : SyncController(engine: engine, settings: settings, apiFactory: syncApiFactory),
    );
  }

  final AppDatabase database;
  final SettingsRepository settings;
  final NotebookRepository notebooks;
  final PageRepository pages;
  final StrokeRepository strokes;
  final ElementRepository elements;
  final SyncController sync;

  void dispose() {
    sync.dispose();
    database.close();
  }
}

/// Makes [AppServices] available to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.services;
  }

  /// Like [of] but without subscribing; safe to call from `initState`.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
