import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:test/test.dart';

void main() {
  test('new-id gives the server a new id and keeps its records', () async {
    final dir = await Directory.systemTemp.createTemp('len_new_id');
    addTearDown(() => dir.delete(recursive: true));
    final env = {'LEN_DB_PATH': '${dir.path}/len.db'};
    final store = RecordStore.open(env['LEN_DB_PATH']!);
    store.push([
      SyncRecord(
        collection: 'notebooks',
        id: 'n',
        updatedAt: 1,
        deviceId: 'd',
        deleted: false,
        data: const {},
      ),
    ]);
    final before = store.serverId;
    store.close();

    final out = StringBuffer();
    expect(runNewIdCommand([], env, out: out, err: StringBuffer()), 0);
    final after = RecordStore.open(env['LEN_DB_PATH']!);
    addTearDown(after.close);
    expect(after.serverId, isNot(before));
    expect(out.toString(), contains(after.serverId));
    expect(after.currentSeq(), 1);

    expect(runNewIdCommand(['x'], env, out: StringBuffer(), err: StringBuffer()), 64);
  });
}
