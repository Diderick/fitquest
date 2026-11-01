import 'dart:convert';
import 'package:fitquest/friend_discovery.dart';
import 'package:fitquest/offline_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'imported suggestions are not followed until the user selects them',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'fitquest.session':
          '{"token":"session","user":{"id":"member","username":"Member"}}'
    });
    OfflineStore.instance = OfflineStore(client: MockClient((request) async {
      if (request.url.path == '/v2/oauth/providers') {
        return http.Response(
            '{"providers":{"google":false,"facebook":false},"linked":[]}', 200);
      }
      if (request.url.path == '/v2/friends/suggestions') {
        return http.Response(
            jsonEncode({
              'people': [
                {'id': 'friend', 'username': 'Alice', 'provider': 'google'}
              ],
              'imports': [
                {'provider': 'google', 'checked': 1, 'limited': 0}
              ],
            }),
            200);
      }
      throw http.ClientException('offline');
    }));
    await tester.runAsync(OfflineStore.instance.initialize);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: SocialFriendImportPanel()))));
    await tester.pumpAndSettle();
    expect(OfflineStore.instance.getBool('following/friend'), isNull);
    expect(OfflineStore.instance.getBool('friend_discovery'), isNull);
    await tester.scrollUntilVisible(find.text('@Alice'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('@Alice'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Follow selected (1)'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow selected (1)'));
    await tester.pumpAndSettle();
    expect(OfflineStore.instance.getBool('following/friend'), isTrue);
    expect(OfflineStore.instance.pending, 1);
  });
}
