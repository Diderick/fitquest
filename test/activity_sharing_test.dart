import 'dart:ui' as ui;
import 'dart:io';
import 'package:fitquest/activity_sharing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final activity = ActivityShareData(
      activity: 'Running',
      minutes: 32,
      distanceKm: 5.2,
      date: DateTime(2026, 11, 2),
      notes: 'Private training note',
      route: const [
        (latitude: -26, longitude: 28),
        (latitude: -26.01, longitude: 28.02)
      ]);
  test('share summaries omit private notes and route coordinates by default',
      () {
    expect(activity.summary(), contains('5.20 km'));
    expect(activity.summary(), contains('32 minutes'));
    expect(activity.summary(), isNot(contains('Private training note')));
    expect(activity.summary(), isNot(contains('-26')));
    expect(activity.summary(includeNotes: true),
        contains('Private training note'));
  });
  test('share image is a real offline PNG with an opt-in route preview',
      () async {
    const previewFont = String.fromEnvironment('FITQUEST_PREVIEW_FONT');
    if (previewFont.isNotEmpty) {
      final font = FontLoader('Roboto')
        ..addFont(Future.value(
            ByteData.sublistView(await File(previewFont).readAsBytes())));
      await font.load();
    }
    final plain = await activityCard(activity);
    if (const bool.fromEnvironment('FITQUEST_WRITE_SHARE_PREVIEW')) {
      await File('build/fitquest-sharing-preview.png').writeAsBytes(plain);
    }
    final withRoute = await activityCard(activity, includeRoute: true);
    expect(plain.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(plain);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, 1350);
    expect(withRoute, isNot(plain));
    frame.image.dispose();
    codec.dispose();
  });
}
