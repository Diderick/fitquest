import 'dart:convert';
import 'package:fitquest/nutrition_log.dart';
import 'package:fitquest/offline_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
      'daily allowance credits only selected-day activity and subtracts food and drink',
      () async {
    final store = OfflineStore();
    await store.initialize();
    final repo = NutritionRepository(store);
    await repo.setGoal('2026-11-02', 2000);
    await repo.save(const NutritionEntry(
        id: 'food',
        name: 'Oats',
        kind: 'food',
        calories: 400,
        date: '2026-11-02',
        time: '08:00'));
    await repo.save(const NutritionEntry(
        id: 'drink',
        name: 'Milk',
        kind: 'drink',
        calories: 100,
        date: '2026-11-02',
        time: '08:10'));
    await repo.save(const NutritionEntry(
        id: 'yesterday',
        name: 'Dinner',
        kind: 'food',
        calories: 900,
        date: '2026-11-01',
        time: '19:00'));
    final totals = repo.totals('2026-11-02', [
      ActivityCalorieCredit(DateTime(2026, 11, 2), 180),
      ActivityCalorieCredit(DateTime(2026, 11, 1), 1000)
    ]);
    expect(totals.allowance, 2180);
    expect(totals.consumed, 500);
    expect(totals.remaining, 1680);
    expect(totals.netIntake, 320);
    expect(repo.goal('2026-11-01'), 2200);
  });
  test(
      'old undated records are preserved, excluded from totals, and deletions do not resurrect',
      () async {
    SharedPreferences.setMockInitialValues({
      'nutrition_entries_v1': jsonEncode([
        {'meal': 'Breakfast', 'calories': 450}
      ])
    });
    var store = OfflineStore();
    await store.initialize();
    var repo = NutritionRepository(store);
    final old = repo.entries.single;
    expect(old.undated, isTrue);
    expect(repo.totals('2026-11-02', []).consumed, 0);
    await repo.remove(old);
    expect(repo.entries, isEmpty);
    store = OfflineStore();
    await store.initialize();
    repo = NutritionRepository(store);
    expect(repo.entries, isEmpty);
    expect(store.pending, 1);
  });
  test(
      'dated entries edit independently, retain zero-calorie drinks and survive restart',
      () async {
    var store = OfflineStore();
    await store.initialize();
    var repo = NutritionRepository(store);
    await Future.wait([
      repo.save(const NutritionEntry(
          id: 'one',
          name: 'Toast',
          kind: 'food',
          calories: 300,
          date: '2026-11-02',
          time: '07:00')),
      repo.save(const NutritionEntry(
          id: 'two',
          name: 'Water',
          kind: 'drink',
          calories: 0,
          portion: '250 ml',
          date: '2026-11-02',
          time: '07:10')),
    ]);
    await repo.save(const NutritionEntry(
        id: 'one',
        name: 'Toast',
        kind: 'food',
        calories: 350,
        date: '2026-11-01',
        time: '07:00'));
    store = OfflineStore();
    await store.initialize();
    repo = NutritionRepository(store);
    expect(repo.forDay('2026-11-02').single.name, 'Water');
    expect(repo.forDay('2026-11-02').single.calories, 0);
    expect(repo.forDay('2026-11-02').single.portion, '250 ml');
    expect(repo.forDay('2026-11-02').single.servings, 1);
    expect(repo.forDay('2026-11-02').single.proteinG, 0);
    expect(repo.forDay('2026-11-01').single.calories, 350);
  });

  test('macro and servings values persist across restart', () async {
    var store = OfflineStore();
    await store.initialize();
    var repo = NutritionRepository(store);
    await repo.save(const NutritionEntry(
        id: 'macro',
        name: 'Protein shake',
        kind: 'drink',
        calories: 180,
        servings: 1.5,
        proteinG: 36,
        carbsG: 4.5,
        fatG: 2.3,
        date: '2026-11-03',
        time: '09:15'));

    store = OfflineStore();
    await store.initialize();
    repo = NutritionRepository(store);
    final entry = repo.forDay('2026-11-03').single;
    expect(entry.servings, 1.5);
    expect(entry.proteinG, 36);
    expect(entry.carbsG, 4.5);
    expect(entry.fatG, 2.3);
  });
}
