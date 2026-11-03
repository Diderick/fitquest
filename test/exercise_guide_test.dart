import 'package:fitquest/exercise_art.dart';
import 'package:fitquest/exercise_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every session exercise exists in the library', () {
    for (final keys in sessionExercises.values) {
      for (final k in keys) {
        expect(exerciseLibrary[k], isNotNull, reason: k);
      }
    }
  });

  test('every exercise has an animation', () {
    for (final e in exerciseLibrary.values) {
      expect(exerciseArt[e.name], isNotNull, reason: e.name);
    }
  });

  testWidgets('guide expands to show lifting steps', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExerciseGuidePage(
          title: 'Barbell lifting day',
          exercises: [exerciseLibrary['deadlift']!]),
    ));
    expect(find.text('Barbell deadlift'), findsOneWidget);
    await tester.tap(find.text('Barbell deadlift'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('How to do it'), findsOneWidget);
    expect(find.textContaining('Rounding your lower back'), findsOneWidget);
  });
}
