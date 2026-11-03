import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fitquest/profile_identity.dart';
import 'package:fitquest/offline_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    OfflineStore.instance = OfflineStore();
    await OfflineStore.instance.initialize();
  });
  test(
      'profile thumbnails become bounded PNGs and persist independently of picker cache files',
      () async {
    final bytes = await prepareProfilePhoto(
        await File('branding/logo.png').readAsBytes());
    expect(bytes.length, lessThanOrEqualTo(300 * 1024));
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 256);
    expect(frame.image.height, 256);
    frame.image.dispose();
    codec.dispose();
    await OfflineStore.instance.putAll(
        {'profile_photo_v1': base64Encode(bytes), 'profile_gender': 'other'});
    final restarted = OfflineStore();
    await restarted.initialize();
    expect(decodeProfilePhoto(restarted.get('profile_photo_v1')), bytes);
    expect(restarted.getString('profile_gender'), 'other');
  });
  testWidgets('gender offers male and female and saves the selection',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileGenderSelector())));
    for (final gender in ['Male', 'Female']) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(gender).last);
      await tester.pumpAndSettle();
      expect(OfflineStore.instance.getString('profile_gender'),
          gender.toLowerCase());
    }
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsNothing);
  });
}
