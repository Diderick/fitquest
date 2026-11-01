import 'dart:convert';
import 'package:fitquest/offline_store.dart';
import 'package:fitquest/social_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'callbacks require matching state and exchange a one-time code without exposing sessions in URLs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final pending = {
      'state': 'a' * 48,
      'verifier': 'b' * 96,
      'expires':
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch
    };
    FlutterSecureStorage.setMockInitialValues(
        {'fitquest.oauth.pending': jsonEncode(pending)});
    var exchanges = 0;
    OfflineStore.instance = OfflineStore(client: MockClient((request) async {
      if (request.url.path == '/v2/oauth/exchange') {
        exchanges++;
        expect(request.url.query, isEmpty);
        expect(jsonDecode(request.body), {
          'code': 'one-time-code',
          'verifier': pending['verifier'],
          'appState': pending['state']
        });
        return http.Response(
            '{"token":"private-session","created":true,"user":{"id":"social-user","username":"athlete_test"}}',
            200);
      }
      if (request.url.path == '/v2/oauth/providers') {
        return http.Response(
            '{"providers":{"google":true,"facebook":false},"linked":["google"]}',
            200);
      }
      final operations =
          (jsonDecode(request.body) as Map)['operations'] as List;
      return http.Response(
          jsonEncode({
            'acknowledged': operations.map((op) => op['id']).toList(),
            'conflicts': [],
            'state': {
              for (final op in operations)
                op['key']: {'value': op['value'], 'version': 1}
            }
          }),
          200);
    }));
    await OfflineStore.instance.setDouble('bl_start', 95);
    final auth = SocialAuth();
    await auth.complete(
        Uri.parse('fitquest-auth://callback?code=one-time-code&state=wrong'));
    expect(exchanges, 0);
    expect(OfflineStore.instance.signedIn, isFalse);
    final callback = Uri(
        scheme: 'fitquest-auth',
        host: 'callback',
        queryParameters: {
          'code': 'one-time-code',
          'state': pending['state'] as String
        });
    await auth.complete(callback);
    expect(exchanges, 1);
    expect(OfflineStore.instance.user!['id'], 'social-user');
    expect(OfflineStore.instance.getDouble('bl_start'), 95);
    expect(
        await OfflineStore.instance.secure.read(key: 'fitquest.oauth.pending'),
        isNull);
    await auth.complete(callback);
    expect(exchanges, 1);
  });
}
