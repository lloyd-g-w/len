import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/browser_names.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_version.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/history/version_labels.dart';
import 'package:len/sync/device_name.dart';

NotebookVersion _version(String device, String name) => NotebookVersion(
  id: 'v-$device-$name',
  notebookId: 'n',
  createdAt: 0,
  kind: VersionKind.auto,
  name: null,
  deviceId: device,
  deviceName: name,
  notebook: const {},
  table: const [],
  summary: const VersionSummary(pages: 1, strokes: 0),
  size: 0,
);

void main() {
  late SettingsRepository settings;
  late DeviceName name;
  setUp(() {
    settings = SettingsRepository(AppDatabase.inMemory());
    name = DeviceName(settings, platformName: () => 'Linux (studio)');
  });

  test('suggested until named; empty or the suggestion goes back to it', () {
    expect(name.value, 'Linux (studio)');
    var told = 0;
    name.addListener(() => told++);
    name.rename('  Desk  ');
    expect((name.value, settings.deviceName, told), ('Desk', 'Desk', 1));
    name.rename('Desk');
    expect(told, 1);
    name.rename('');
    expect((name.value, settings.deviceName, told), ('Linux (studio)', null, 2));
    name.rename('Linux (studio)');
    expect((settings.deviceName, told), (null, 2));
    name.rename('x' * 80);
    expect(name.value.length, DeviceName.maxLength);
  });

  test('the system\'s name, once known, is the suggestion from then on', () async {
    var told = 0;
    name.addListener(() => told++);
    await name.detect(ask: () async => 'Galaxy Tab S9');
    expect((name.value, told), ('Galaxy Tab S9', 1));
    // Kept: known at the next start before asking again.
    expect(DeviceName(settings, platformName: () => 'Android').value, 'Galaxy Tab S9');
    name.rename('Sketchbook');
    await name.detect(ask: () async => 'Galaxy Tab S10');
    expect((name.value, name.suggested, told), ('Sketchbook', 'Galaxy Tab S10', 2));
    await name.detect(ask: () async => throw StateError('no channel'));
    expect(name.suggested, 'Galaxy Tab S10');
  });

  test('browsers are named by their user agent', () {
    const linuxFirefox = 'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0';
    const androidChrome =
        'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36';
    const windowsEdge =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0';
    const ipadSafari =
        'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1';
    expect(browserDeviceName(linuxFirefox), 'Firefox on Linux');
    expect(browserDeviceName(androidChrome), 'Chrome on Android');
    expect(browserDeviceName(windowsEdge), 'Edge on Windows');
    expect(browserDeviceName(ipadSafari), 'Safari on iPad');
    expect(browserDeviceName('curl/8'), 'Browser');
  });

  test('history rows name a device as it is called now, else as it was', () {
    final devices = (thisDevice: 'me', names: {'d1': 'Studio laptop'});
    expect(VersionLabels.device(_version('me', 'Linux'), devices), 'This device');
    expect(VersionLabels.device(_version('d1', 'Linux'), devices), 'Studio laptop');
    expect(VersionLabels.device(_version('d2', 'Android'), devices), 'Android');
    expect(VersionLabels.device(_version('d3', ''), devices), 'Another device');
    expect(VersionLabels.madeOn(_version('d1', 'Linux'), devices), 'on Studio laptop');
  });

  test('versions carry the name; a device is called what its newest version says', () async {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'n',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF000000,
    );
    s.sync.deviceName.rename('Desk');
    final first = (await s.versions.save(nb.id, name: 'One'))!;
    s.sync.deviceName.rename('Studio laptop');
    await s.versions.save(nb.id, name: 'Two');
    expect(s.versions.store.get(first.id)!.deviceName, 'Desk');
    expect(s.versions.store.deviceNames(), {s.strokes.deviceId: 'Studio laptop'});
  });
}
