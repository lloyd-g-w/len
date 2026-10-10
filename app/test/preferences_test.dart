import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/app_preferences.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/preferences.dart';

void main() {
  test('preferences default sensibly, persist and notify', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = AppPreferences(SettingsRepository(db));
    addTearDown(prefs.dispose);

    expect(prefs.themeMode, ThemePreference.system);
    expect(prefs.accentColor, isNull);
    expect(prefs.twoFingerTapUndo, isTrue);
    expect(prefs.threeFingerTapRedo, isTrue);
    expect(prefs.penButtonAction, PenButtonAction.eraser);
    expect(prefs.libraryLayout, LibraryLayout.grid);
    expect(prefs.librarySort, LibrarySort.edited);
    expect(prefs.lowLatencyInk, isFalse, reason: 'experimental: off by default');

    var notified = 0;
    prefs.addListener(() => notified++);
    prefs
      ..themeMode = ThemePreference.dark
      ..accentColor = 0xFF0B7285
      ..twoFingerTapUndo = false
      ..penButtonAction = PenButtonAction.lasso
      ..libraryLayout = LibraryLayout.list
      ..librarySort = LibrarySort.name
      ..lowLatencyInk = true;
    expect(notified, 7);

    // A fresh view over the same database sees the stored values.
    final reread = SettingsRepository(db);
    expect(reread.themeMode, ThemePreference.dark);
    expect(reread.accentColor, 0xFF0B7285);
    expect(reread.twoFingerTapUndo, isFalse);
    expect(reread.penButtonAction, PenButtonAction.lasso);
    expect(reread.libraryLayout, LibraryLayout.list);
    expect(reread.librarySort, LibrarySort.name);
    expect(reread.lowLatencyInk, isTrue);

    prefs.accentColor = null;
    expect(reread.accentColor, isNull);
  });
}
