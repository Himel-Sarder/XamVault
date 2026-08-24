import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/core/token_manager.dart';
import 'package:uniexam/core/token_store.dart';

void main() {
  late InMemoryTokenStore store;
  late TokenManager manager;

  setUp(() {
    store = InMemoryTokenStore();
    manager = TokenManager(store);
  });

  test('starts with no session', () async {
    await manager.restore();
    expect(manager.hasSession, isFalse);
    expect(manager.accessToken, isNull);
  });

  test('saved tokens survive a restart', () async {
    await manager.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    final reopened = TokenManager(store);
    await reopened.restore();

    expect(reopened.accessToken, 'access-1');
    expect(reopened.refreshToken, 'refresh-1');
    expect(reopened.hasSession, isTrue);
  });

  test('clear removes the tokens from storage, not just memory', () async {
    await manager.save(accessToken: 'access-1', refreshToken: 'refresh-1');
    await manager.clear();

    final reopened = TokenManager(store);
    await reopened.restore();

    expect(reopened.hasSession, isFalse);
    expect(await store.read('uniexam.access_token'), isNull);
  });
}
