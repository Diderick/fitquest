import 'dart:convert';
import 'package:fitquest/offline_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('offline edits and pending sync survive restart, then sync once',
      () async {
    var online = false;
    var submissions = 0;
    final remote = <String, dynamic>{};
    final client = MockClient((request) async {
      if (request.url.path == '/v2/auth/register') {
        return http.Response(
            '{"token":"session-token","user":{"id":"alice","username":"Alice"}}',
            200);
      }
      if (!online) throw http.ClientException('offline');
      final body = jsonDecode(request.body) as Map;
      final operations = body['operations'] as List;
      for (final op in operations) {
        submissions++;
        remote[op['key'] as String] = {'value': op['value'], 'version': 1};
      }
      return http.Response(
          jsonEncode({
            'acknowledged': operations.map((op) => op['id']).toList(),
            'conflicts': [],
            'state': remote
          }),
          200);
    });
    var store = OfflineStore(client: client);
    await store.setDouble('bl_start', 95.5);
    await store.authenticate('alice@example.test', 'long password test',
        username: 'Alice');
    await Future.wait([
      store.setString('fitquest.activities.v1', '[{"activity":"Running"}]'),
      store.setString(
          'nutrition_entries_v1', '[{"meal":"Lunch","calories":500}]'),
      store.setString('active_plan', 'Strength'),
      store.setBool('following/bob', true),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(store.pending, 5);
    store = OfflineStore(client: client);
    await store.initialize();
    expect(store.signedIn, isTrue);
    expect(store.getDouble('bl_start'), 95.5);
    expect(store.getDouble('bl_current'), isNull);
    expect(store.getBool('following/bob'), isTrue);
    expect(store.pending, 5);
    online = true;
    await store.sync();
    expect(store.pending, 0);
    expect(submissions, 5);
    await store.sync();
    expect(submissions, 5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fitquest.offline.alice'),
        isNot(contains('session-token')));
    expect(prefs.getString('fitquest.offline.alice'),
        isNot(contains('long password test')));
  });

  test('conflicts preserve local edits until explicitly resolved', () async {
    var allow = false;
    final client = MockClient((request) async {
      if (request.url.path.contains('/auth/')) {
        return http.Response(
            '{"token":"session-token","user":{"id":"alice","username":"Alice"}}',
            200);
      }
      final operations =
          (jsonDecode(request.body) as Map)['operations'] as List;
      return http.Response(
          jsonEncode({
            'acknowledged':
                allow ? operations.map((op) => op['id']).toList() : [],
            'conflicts': operations.isEmpty || allow ? [] : ['bl_start'],
            'state': {
              'bl_start': {
                'value': allow ? 95.0 : 94.0,
                'version': allow ? 3 : 2
              }
            },
          }),
          200);
    });
    final store = OfflineStore(client: client);
    await store.setDouble('bl_start', 95);
    await store.authenticate('alice@example.test', 'a long password',
        username: 'Alice');
    expect(store.getDouble('bl_start'), 95);
    expect(store.conflicts, ['bl_start']);
    expect(store.pending, 1);
    allow = true;
    await store.resolve('bl_start', keepLocal: true);
    expect(store.pending, 0);
    expect(store.getDouble('bl_start'), 95);
  });

  test('signing into another account never loads another user’s data',
      () async {
    var user = 'alice';
    final client = MockClient((request) async {
      if (request.url.path == '/v2/auth/login') {
        return http.Response(
            jsonEncode({
              'token': 'token-$user',
              'user': {'id': user, 'username': user}
            }),
            200);
      }
      if (request.url.path == '/v2/auth/logout') {
        return http.Response('{"ok":true}', 200);
      }
      throw http.ClientException('offline');
    });
    final store = OfflineStore(client: client);
    await store.authenticate('alice@example.test', 'a long password');
    await store.setDouble('bl_start', 95);
    await store.signOut();
    user = 'bob';
    await store.authenticate('bob@example.test', 'a long password');
    expect(store.getDouble('bl_start'), isNull);
    await store.signOut();
    user = 'alice';
    await store.authenticate('alice@example.test', 'a long password');
    expect(store.getDouble('bl_start'), 95);
    expect(store.pending, 1);
  });
}
