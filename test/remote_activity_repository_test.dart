import 'dart:convert';

import 'package:fitquest/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('configured live server reads and saves through the Flutter repository',
      () async {
    final repo = RemoteActivityRepository(fitquestApiUrl, fitquestApiToken);
    try {
      final workouts = await repo.load();
      await repo.save(workouts);
      final reloaded = await repo.load();
      expect(reloaded.map((w) => w.toJson()).toList(),
          workouts.map((w) => w.toJson()).toList());
    } finally {
      repo.client.close();
    }
  }, skip: !const bool.fromEnvironment('FITQUEST_RUN_LIVE_TEST'));

  test('remote repository sends credentials, routes and server revision',
      () async {
    final workout = Workout('Running', 30, DateTime.utc(2026, 11, 1),
        route: const [(latitude: -26.0, longitude: 28.0)]);
    var saves = 0;
    final repo = RemoteActivityRepository('https://example.test/', 'test-token',
        client: MockClient((request) async {
      expect(request.url.path, '/v1/activities');
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'revision': 4,
              'workouts': [workout.toJson()],
            }),
            200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['revision'], 4 + saves);
      expect(body['workouts'], [workout.toJson()]);
      saves++;
      return http.Response(jsonEncode({'revision': 4 + saves}), 200);
    }));
    final loaded = await repo.load();
    expect(loaded.single.route, workout.route);
    await repo.save(loaded);
    await repo.save(loaded);
    expect(saves, 2);
  });

  test('unloaded and conflicting saves fail instead of overwriting', () async {
    var calls = 0;
    final repo = RemoteActivityRepository('https://example.test', 'token',
        client: MockClient((request) async {
      calls++;
      return request.method == 'GET'
          ? http.Response('{"revision":0,"workouts":[]}', 200)
          : http.Response('{"error":"conflict"}', 409);
    }));
    await expectLater(repo.save([]), throwsStateError);
    expect(calls, 0);
    await repo.load();
    await expectLater(repo.save([]), throwsStateError);
  });

  test('requires HTTPS and authentication configuration', () {
    expect(() => RemoteActivityRepository('http://example.test', 'token'),
        throwsArgumentError);
    expect(() => RemoteActivityRepository('https://example.test', ''),
        throwsArgumentError);
  });
}
