import 'package:fitquest/nutrition_log.dart';
import 'package:fitquest/nutrition_page.dart';
import 'package:fitquest/offline_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    OfflineStore.instance = OfflineStore();
    await OfflineStore.instance.initialize();
  });
  testWidgets('nutrition date navigation separates entries and workout credit',
      (tester) async {
    final now = DateTime.now(),
        yesterday = DateTime.now().subtract(const Duration(days: 1));
    final repo = NutritionRepository(OfflineStore.instance);
    await tester.runAsync(() async {
      await repo.save(NutritionEntry(
          id: 'today',
          name: 'Toast',
          kind: 'food',
          calories: 400,
          date: nutritionDate(now),
          time: '08:00'));
      await repo.save(NutritionEntry(
          id: 'yesterday',
          name: 'Dinner',
          kind: 'food',
          calories: 900,
          date: nutritionDate(yesterday),
          time: '19:00'));
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyNutritionPage(
                activityCredits: () => [
                      ActivityCalorieCredit(now, 180),
                      ActivityCalorieCredit(yesterday, 1000)
                    ]))));
    await tester.pumpAndSettle();
    expect(find.text('1980 kcal remaining'), findsOneWidget);
    expect(find.text('180 kcal'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous date'));
    await tester.pumpAndSettle();
    expect(find.text('2300 kcal remaining'), findsOneWidget);
    expect(find.text('1000 kcal'), findsOneWidget);
  });
  testWidgets(
      'drink capture defaults to today and current time and accepts zero calories',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DailyNutritionPage(activityCredits: () => []))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Log drink'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log drink'));
    await tester.pumpAndSettle();
    expect(find.text('Date: ${nutritionDate(DateTime.now())}'), findsOneWidget);
    final nowTime = nutritionTime(DateTime.now());
    expect(find.text('Time: $nowTime'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'What did you eat or drink?'),
        'Water');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Portion / amount (optional)'),
        '250 ml');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'), '0');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    final entry = NutritionRepository(OfflineStore.instance).entries.single;
    expect(entry.kind, 'drink');
    expect(entry.name, 'Water');
    expect(entry.calories, 0);
    expect(entry.date, nutritionDate(DateTime.now()));
    expect(entry.time, nowTime);
  });
}
