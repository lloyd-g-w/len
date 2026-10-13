import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/install_identity.dart';
import 'package:len/data/settings_repository.dart';

void main() {
  late AppDatabase database;
  late SettingsRepository settings;

  setUp(() {
    database = AppDatabase.inMemory();
    settings = SettingsRepository(database);
  });
  tearDown(() => database.close());

  test('a fresh installation makes its device id', () {
    final first = InstallIdentity.check(settings, marker: null);
    expect(first.adopted, isFalse);
    expect(settings.storedDeviceId, first.deviceId);
  });

  test('its own database keeps its id and sync position', () {
    final id = settings.deviceId();
    settings
      ..syncLastSeq = 42
      ..syncServerId = 'server';
    final again = InstallIdentity.check(settings, marker: id);
    expect(again, (deviceId: id, adopted: false));
    expect(settings.syncLastSeq, 42);
    expect(settings.syncServerId, 'server');
  });

  test('a restored database takes a new id and syncs again from scratch', () {
    final old = settings.deviceId();
    settings
      ..syncUrl = 'https://len.example'
      ..syncLastSeq = 42
      ..syncServerId = 'server'
      ..syncBlobsCollectedAt = 7;
    // No marker: Android backups leave it out.
    final restored = InstallIdentity.check(settings, marker: null);
    expect(restored.adopted, isTrue);
    expect(restored.deviceId, isNot(old));
    expect(settings.deviceId(), restored.deviceId);
    expect(settings.syncLastSeq, 0);
    expect(settings.syncServerId, '');
    expect(settings.syncBlobsCollectedAt, 0);
    // The login stays: the next sync with the same server is a full one.
    expect(settings.syncUrl, 'https://len.example');
    // Once the marker holds the new id, nothing changes any more.
    expect(InstallIdentity.check(settings, marker: restored.deviceId).adopted, isFalse);
  });

  test("another installation's marker counts as a copy", () {
    final old = settings.deviceId();
    final copied = InstallIdentity.check(settings, marker: 'someone-else');
    expect(copied.adopted, isTrue);
    expect(copied.deviceId, isNot(old));
  });
}
