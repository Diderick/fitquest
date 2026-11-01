import 'package:fitquest/challenge_ui.dart';
import 'package:fitquest/challenges.dart';
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
  testWidgets('create a custom challenge and log a test while offline',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChallengesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create challenge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Challenge name'),
        'Weekend fitness test');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save challenge'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save challenge'));
    await tester.pumpAndSettle();
    expect(find.text('Weekend fitness test'), findsOneWidget);
    await tester.tap(find.text('Weekend fitness test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log test result'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise 1'), '40');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save result'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save result'));
    await tester.pumpAndSettle();
    final repo = ChallengeRepository(OfflineStore.instance);
    expect(repo.mine.single.title, 'Weekend fitness test');
    expect(repo.results(repo.mine.single.id).single.scores.values.single, 40);
    expect(OfflineStore.instance.pending, 2);
  });
}
