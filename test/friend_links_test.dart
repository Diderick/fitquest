import 'dart:convert';
import 'package:fitquest/friend_links.dart';
import 'package:fitquest/offline_store.dart';
import 'package:fitquest/challenges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const code = 'abcdefghijklmnopqrstuvwx';
  test('invite parsing accepts only FitQuest URLs or valid codes', () {
    expect(FriendInvitation.parse(code)!.code, code);
    expect(
        FriendInvitation.parse(
                'fitquest-auth://invite?code=$code&challenge=test')!
            .challengeId,
        'test');
    expect(
        FriendInvitation.parse(
                'https://fitquest-api.northstarlabs.tech/join/$code')!
            .code,
        code);
    expect(FriendInvitation.parse('https://other.example/join/$code'), isNull);
    expect(FriendInvitation.parse('javascript:alert(1)'), isNull);
    expect(FriendInvitation.parse('too-short'), isNull);
  });
  test('pending invitations survive restart without following anyone',
      () async {
    SharedPreferences.setMockInitialValues({});
    final router = FriendLinkRouter();
    await router.receive(Uri.parse('fitquest-auth://invite?code=$code'));
    final restored = FriendLinkRouter();
    await restored.restore();
    expect(restored.pending!.code, code);
    final invitation = restored.takePending()!;
    expect(
        (await SharedPreferences.getInstance())
            .getString('fitquest.pending_invite'),
        isNotNull);
    await restored.finish(invitation);
    expect(
        (await SharedPreferences.getInstance())
            .getString('fitquest.pending_invite'),
        isNull);
  });
  testWidgets(
      'opening an invitation does not follow; explicit follow and join are saved offline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'fitquest.session':
          '{"token":"member-token","user":{"id":"member","username":"Member"}}'
    });
    final challenge = FitnessChallenge(
        id: 'test',
        title: 'Friends fitness test',
        category: 'Military',
        instructions: '',
        startDate: '2026-01-01',
        endDate: '2027-12-31',
        visibility: 'followers',
        events: const [
          TestEvent(
              id: 'pushups',
              name: 'Push-ups',
              metric: ChallengeMetric.reps,
              higherWins: true)
        ],
        ownerId: 'creator',
        ownerName: 'Creator');
    final response = {
      'person': {'id': 'creator', 'username': 'Creator'},
      'challenge': {
        ...challenge.toJson(),
        'ownerId': 'creator',
        'ownerName': 'Creator'
      }
    };
    OfflineStore.instance = OfflineStore(client: MockClient((request) async {
      if (request.url.path.startsWith('/v2/friends/invites/')) {
        return http.Response(jsonEncode(response), 200);
      }
      throw http.ClientException('offline');
    }));
    await OfflineStore.instance.initialize();
    await tester.pumpWidget(const MaterialApp(
        home: FriendInvitePage(
            invitation: FriendInvitation(code, challengeId: 'test'))));
    await tester.pumpAndSettle();
    expect(OfflineStore.instance.getBool('following/creator'), isNull);
    expect(OfflineStore.instance.getBool('challenge_join.test'), isNull);
    await tester.tap(find.text('Follow & join challenge'));
    await tester.pumpAndSettle();
    expect(OfflineStore.instance.getBool('following/creator'), isTrue);
    expect(OfflineStore.instance.getBool('challenge_join.test'), isTrue);
    expect(OfflineStore.instance.pending, 2);
    final restarted = OfflineStore(
        client: MockClient((_) async => throw http.ClientException('offline')));
    await tester.runAsync(restarted.initialize);
    expect(restarted.getBool('following/creator'), isTrue);
    expect(ChallengeRepository(restarted).discovered.single.id, 'test');
  });
  test('stale-account writes cannot leak cached friends into another workspace',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = OfflineStore();
    await store.initialize();
    await expectLater(
        store.putAll({'_known_people': '[{"id":"someone"}]'},
            expectedScope: 'other-account'),
        throwsStateError);
    expect(store.getString('_known_people'), isNull);
  });
}
