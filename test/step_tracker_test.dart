import 'package:fitquest/offline_store.dart';
import 'package:fitquest/step_tracker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('phone sensor counts are stored offline without workout estimates',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    OfflineStore.instance = OfflineStore();
    var enabled = false;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(StepTracker.channel, (MethodCall call) async {
      calls.add(call.method);
      if (call.method == 'enable') {
        enabled = true;
        return null;
      }
      if (call.method == 'disable') {
        enabled = false;
        return null;
      }
      return {'steps': 1234, 'enabled': enabled, 'status': 'Sensor active'};
    });
    try {
      await StepTracker.instance.enable();
      expect(StepTracker.instance.today, 1234);
      expect(StepTracker.instance.enabled, isTrue);
      final store = OfflineStore.instance;
      final device = store.getString('_device_id');
      final date = DateTime.now().toIso8601String().substring(0, 10);
      expect(store.getInt('steps.$device.$date'), 1234);
      expect(store.pending, 1);
      await StepTracker.instance.refresh();
      expect(store.pending, 1);
      await StepTracker.instance.disable();
      expect(StepTracker.instance.enabled, isFalse);
      expect(calls, containsAll(['enable', 'read', 'disable']));
    } finally {
      StepTracker.instance.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(StepTracker.channel, null);
    }
  });
}
