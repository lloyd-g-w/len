import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:len/ui/sync_status_button.dart';

void main() {
  test('the sidebar says how long ago the last sync was', () {
    final now = DateTime(2026, 10, 13, 12);
    String idle(Duration ago) => syncCaption(SyncState.idle, now.subtract(ago), now);
    expect(idle(const Duration(seconds: 20)), 'Synced just now');
    expect(idle(const Duration(minutes: 2, seconds: 30)), 'Synced 2m');
    expect(idle(const Duration(hours: 3, minutes: 5)), 'Synced 3h');
    expect(idle(const Duration(days: 2)), 'Synced 2d');
    expect(syncCaption(SyncState.idle, null, now), 'Not synced yet');
    expect(syncCaption(SyncState.syncing, now, now), 'Syncing…');
    expect(syncCaption(SyncState.error, now, now), 'Sync failed');
    expect(syncCaption(SyncState.disabled, null, now), 'On this device only');
  });
}
