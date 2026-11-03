import 'package:fitquest/challenges.dart';
import 'package:fitquest/offline_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const time = TestEvent(
      id: 'run',
      name: 'Run',
      metric: ChallengeMetric.seconds,
      higherWins: false,
      target: 900);
  const reps = TestEvent(
      id: 'pushups',
      name: 'Push-ups',
      metric: ChallengeMetric.reps,
      higherWins: true,
      target: 40);
  test('join codes are 8 safe characters and survive JSON', () {
    final code = newJoinCode();
    expect(RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code), isTrue);
    final challenge = FitnessChallenge(
        id: 'c1',
        title: 'T',
        category: 'Custom',
        instructions: '',
        startDate: '2026-01-01',
        endDate: '2026-02-01',
        visibility: 'private',
        joinCode: code,
        events: const [reps]);
    expect(FitnessChallenge.fromJson(challenge.toJson()).joinCode, code);
  });
  test('time parsing, directions and targets keep each exercise unit intact',
      () {
    expect(time.parse('14:30'), 870);
    expect(time.format(870), '14:30');
    expect(time.parse('14:75'), isNull);
    expect(time.parse('0'), isNull);
    expect(time.parse('NaN'), isNull);
    expect(time.parse('999999999999999999999999999:00'), isNull);
    expect(reps.parse('10.5'), isNull);
    expect(reps.parse('0'), 0);
    expect(time.passes(870), isTrue);
    expect(time.passes(901), isFalse);
    expect(reps.passes(40), isTrue);
    expect(reps.passes(39), isFalse);
  });
  test(
      'rankings use best result per person, keep divisions apart and exclude DNF',
      () {
    ChallengeResult attempt(String id, String user, double value,
            {String division = 'As prescribed', bool completed = true}) =>
        ChallengeResult(
            id: id,
            challengeId: 'test',
            date: '2026-11-02',
            division: division,
            notes: '',
            scores: {'run': value},
            userId: user,
            completed: completed);
    final ranking = rankResults([
      attempt('1', 'Alice', 900),
      attempt('2', 'Alice', 850),
      attempt('3', 'Bob', 870),
      attempt('4', 'Charlie', 600, division: 'Scaled'),
      attempt('5', 'Dave', 500, completed: false),
    ], time, 'As prescribed');
    expect(ranking.map((r) => r.id), ['2', '3']);
    expect(
        rankResults([attempt('4', 'Charlie', 600, division: 'Scaled')], time,
            'As prescribed'),
        isEmpty);
  });
  test(
      'custom challenge and partial results survive offline restart with pending uploads',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var store = OfflineStore();
    await store.initialize();
    var repo = ChallengeRepository(store);
    final challenge = FitnessChallenge(
        id: 'fitness-test',
        title: 'Unit test day',
        category: 'Military',
        instructions: 'Use consistent form.',
        startDate: '2026-11-02',
        endDate: '2026-11-30',
        visibility: 'private',
        events: [reps, time]);
    await repo.create(challenge);
    await repo.record(const ChallengeResult(
        id: 'attempt',
        challengeId: 'fitness-test',
        date: '2026-11-03',
        division: 'As prescribed',
        notes: 'Run will be tested later.',
        scores: {'pushups': 42}));
    store = OfflineStore();
    await store.initialize();
    repo = ChallengeRepository(store);
    expect(repo.mine.single.events.length, 2);
    expect(repo.results('fitness-test').single.scores, {'pushups': 42});
    expect(repo.mine.single.acceptsDate('2026-11-01'), isFalse);
    expect(repo.mine.single.acceptsDate('2026-11-30'), isTrue);
    expect(store.pending, 2);
  });
}
