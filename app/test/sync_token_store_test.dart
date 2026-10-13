import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/data/sync_token_store.dart';
import 'package:len/platform/secure_store.dart';

/// A clock whose time the test moves.
class _Clock extends Clock {
  int now = 1000000;

  @override
  int nowMs() => now;
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late MemorySecureStore secure;
  late _Clock clock;

  setUp(() {
    db = AppDatabase.inMemory();
    settings = SettingsRepository(db);
    secure = MemorySecureStore();
    clock = _Clock();
  });
  tearDown(() => db.close());

  SyncTokenStore open([SecureStore? store]) =>
      SyncTokenStore(settings, store ?? secure, clock: clock);

  test('saves to the secure store, loads and clears', () async {
    final tokens = open();
    await tokens.save('secret');
    expect(tokens.token, 'secret');
    expect(secure.values.values, ['secret']);
    expect(settings.syncTokenFallback, isNull);
    expect(tokens.inDatabase, isFalse);

    final again = open();
    expect(again.token, '', reason: 'not read yet');
    await again.load();
    expect(again.token, 'secret');

    await again.save('');
    expect(again.token, '');
    expect(secure.values, isEmpty);
    await open().load();
    expect(open().token, '');
  });

  test('keeps the token in the database while the secure store fails', () async {
    secure.available = false;
    final tokens = open();
    await tokens.save('secret');
    expect(tokens.token, 'secret', reason: 'sync keeps working');
    expect(settings.syncTokenFallback, 'secret');
    expect(tokens.inDatabase, isTrue);
    expect(open().token, 'secret', reason: 'after a restart too');

    // Not retried at every sync…
    secure.available = true;
    await tokens.retryIfDue();
    expect(tokens.inDatabase, isTrue);
    // …but later.
    clock.now += SyncTokenStore.retryAfter.inMilliseconds;
    await tokens.retryIfDue();
    expect(tokens.inDatabase, isFalse);
    expect(settings.syncTokenFallback, isNull);
    expect(secure.values.values, ['secret']);
    expect(tokens.token, 'secret');
  });

  test('a token only in a store that fails to read is read later', () async {
    await open().save('secret');
    secure.available = false;
    final tokens = open();
    await tokens.load();
    expect(tokens.token, '');
    secure.available = true;
    clock.now += SyncTokenStore.retryAfter.inMilliseconds;
    await tokens.retryIfDue();
    expect(tokens.token, 'secret');
  });

  test('a token that cannot be deleted from the store is not read again', () async {
    final tokens = open();
    await tokens.save('secret');
    secure.available = false;
    await tokens.save('');
    secure.available = true;
    final again = open();
    await again.load();
    expect(again.token, '');
    expect(settings.syncTokenFallback, isNull);
  });

  test('moves a token found in the database to the secure store once', () async {
    // As an older build left it.
    settings.syncTokenFallback = 'secret';
    final tokens = open();
    expect(tokens.token, 'secret');
    await tokens.load();
    expect(secure.values.values, ['secret']);
    expect(settings.syncTokenFallback, isNull);
    expect(tokens.token, 'secret');
    final again = open();
    await again.load();
    expect(again.token, 'secret');
  });

  test('installations sharing a secure store keep their own tokens', () async {
    await open().save('one');
    final other = AppDatabase.inMemory();
    addTearDown(other.close);
    final otherTokens = SyncTokenStore(SettingsRepository(other), secure, clock: clock);
    await otherTokens.load();
    expect(otherTokens.token, '');
    await otherTokens.save('two');
    final mine = open();
    await mine.load();
    expect(mine.token, 'one');
  });

  test('without a secure store (a browser) the token is in the database', () async {
    final tokens = SyncTokenStore(settings, null, clock: clock);
    await tokens.save('secret');
    expect(settings.syncTokenFallback, 'secret');
    expect(tokens.inDatabase, isFalse, reason: 'nothing better to say');
    await tokens.save('');
    expect(settings.syncTokenFallback, isNull);
  });
}
