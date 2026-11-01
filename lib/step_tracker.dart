import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'offline_store.dart';

class StepTracker extends ChangeNotifier {
  static final instance = StepTracker();
  static const channel = MethodChannel('fitquest/steps');
  int today = 0;
  bool enabled = false;
  String status = 'Enable your phone’s step sensor';
  Timer? _timer;
  Future<void> start() async {
    await refresh();
    _timer ??= Timer.periodic(
        const Duration(seconds: 10), (_) => unawaited(refresh()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> enable() async {
    try {
      await channel.invokeMethod<void>('enable');
      await refresh();
    } on PlatformException catch (error) {
      status = error.message ?? 'Step sensor permission was not granted.';
      notifyListeners();
    } on MissingPluginException {
      status =
          'Step counting is available on supported Android and iOS phones.';
      notifyListeners();
    }
  }

  Future<void> disable() async {
    try {
      await channel.invokeMethod<void>('disable');
    } catch (_) {}
    enabled = false;
    status = 'Step sensor paused';
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('read');
      today = (data?['steps'] as num?)?.toInt() ?? 0;
      enabled = data?['enabled'] == true;
      status = data?['status'] as String? ?? 'Phone step sensor';
      if (enabled) {
        final store = await OfflineStore.getInstance();
        final device = store.getString('_device_id') ?? operationId();
        if (store.getString('_device_id') == null) {
          await store.setString('_device_id', device);
        }
        final date = DateTime.now().toIso8601String().substring(0, 10);
        await store.setInt('steps.$device.$date', today);
      }
    } catch (_) {
      status = 'Step sensor unavailable on this device';
    }
    notifyListeners();
  }
}
