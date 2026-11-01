import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitquest/main.dart';

void main() {
  test('activity serialization preserves its GPS route', () {
    final workout = Workout(
      'Running',
      32,
      DateTime(2026, 10, 30),
      distanceKm: 5.2,
      notes: 'Easy morning run',
      route: const [
        (latitude: 51.5, longitude: -0.12),
        (latitude: 51.501, longitude: -0.121),
      ],
    );

    final restored = Workout.fromJson(
      jsonDecode(jsonEncode(workout.toJson())) as Map<String, dynamic>,
    );

    expect(restored.distanceKm, 5.2);
    expect(restored.notes, 'Easy morning run');
    expect(restored.route, workout.route);
  });

  test('ranks are assigned from XP thresholds', () {
    String rankAt(int xp) => ranks[rankIndexFor(xp)].name;
    expect(rankAt(0), 'Noob');
    expect(rankAt(499), 'Noob');
    expect(rankAt(500), 'Rookie');
    expect(rankAt(3500), 'Pro');
    expect(rankAt(1000000), 'Legend');
  });

  test('achievements add one-off bonus XP and streaks need consecutive days',
      () {
    final run = Workout('Running', 30, DateTime(2026, 10, 1), distanceKm: 12);
    // 150 workout XP + First Steps (50) + Long Hauler (150).
    expect(totalXpFor([run]), 350);

    final streak = [
      for (var d = 1; d <= 3; d++) Workout('Yoga', 20, DateTime(2026, 10, d)),
    ];
    final gap = [
      Workout('Yoga', 20, DateTime(2026, 10, 1)),
      Workout('Yoga', 20, DateTime(2026, 10, 2)),
      Workout('Yoga', 20, DateTime(2026, 10, 5)),
    ];
    final streakStarter =
        achievements.firstWhere((a) => a.title == 'Streak Starter');
    expect(streakStarter.earned(streak), isTrue);
    expect(streakStarter.earned(gap), isFalse);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the FitQuest dashboard and weekly progress',
      (tester) async {
    await tester.pumpWidget(const FitQuestApp());
    await tester.pumpAndSettle();

    expect(find.text('FITQUEST'), findsOneWidget);
    expect(find.text('steps'), findsOneWidget);
    for (final tab in [
      'Home',
      'Activities',
      'Train',
      'Community',
      'Quests',
      'Profile'
    ]) {
      expect(find.byTooltip(tab), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Weekly goal'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Weekly goal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recent activities'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent activities'), findsOneWidget);
  });

  testWidgets('records and persists an activity with distance and notes',
      (tester) async {
    await tester.pumpWidget(const FitQuestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activities'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add activity'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '5.2');
    await tester.enterText(fields.at(2), 'Easy morning run');
    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Easy morning run'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const FitQuestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Activities'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Easy morning run'), findsOneWidget);
  });
}
