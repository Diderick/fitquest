import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const accountApiUrl = String.fromEnvironment('FITQUEST_API_URL',
    defaultValue: 'https://fitquest-api.northstarlabs.tech');
String operationId() => List.generate(24, (_) => Random.secure().nextInt(256))
    .map((n) => n.toRadixString(16).padLeft(2, '0'))
    .join();

/// A durable per-account cache and outbox, committed together in one local write.
class OfflineStore extends ChangeNotifier {
  static OfflineStore instance = OfflineStore();
  static Future<OfflineStore> getInstance() {
    if (instance._ready) return SynchronousFuture(instance);
    return instance.initialize().then((_) => instance);
  }

  final FlutterSecureStorage secure;
  final http.Client client;
  OfflineStore({FlutterSecureStorage? secure, http.Client? client})
      : secure = secure ?? const FlutterSecureStorage(),
        client = client ?? http.Client();
  SharedPreferences? _prefs;
  Future<void>? _initializing;
  Future<void> _tail = SynchronousFuture(null);
  bool _ready = false;
  Map<String, dynamic> _values = {};
  Map<String, dynamic> _versions = {};
  List<Map<String, dynamic>> _outbox = [];
  Map<String, dynamic> _remote = {};
  List<String> conflicts = [];
  Map<String, dynamic>? user;
  String? _token;
  String scope = 'guest';
  bool syncing = false;
  String status = 'Saved on this device';
  Timer? _timer;
  int generation = 0;
  int get pending => _outbox.length;
  bool get signedIn => user != null;
  String get _diskKey => 'fitquest.offline.$scope';

  Future<void> initialize() =>
      _ready ? SynchronousFuture(null) : _initializing ??= _initialize();
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final stored = await secure.read(key: 'fitquest.session');
      if (stored != null) {
        final session = jsonDecode(stored) as Map<String, dynamic>;
        user = session['user'] as Map<String, dynamic>;
        _token = session['token'] as String;
        scope = user!['id'] as String;
      }
    } catch (_) {
      // Unsupported platforms can still use the local guest workspace.
    }
    _loadDisk();
    _ready = true;
  }

  void _loadDisk() {
    final raw = _prefs!.getString(_diskKey);
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    _values = Map<String, dynamic>.from(data['values'] as Map? ?? {});
    _versions = Map<String, dynamic>.from(data['versions'] as Map? ?? {});
    _outbox = (data['outbox'] as List? ?? [])
        .map((op) => Map<String, dynamic>.from(op as Map))
        .toList();
    if (raw == null && scope == 'guest') {
      for (final key in _prefs!.getKeys()) {
        if (_syncable(key)) _values[key] = _prefs!.get(key);
      }
    }
    conflicts = [];
    _remote = {};
  }

  bool _syncable(String key) => RegExp(
          r'^(fitquest\.activities\.v1|weekly_goal|appearance_mode|active_plan|community_(posts|joined|liked)|nutrition[\w.:-]*|bl_(start|current|joined)|body_fat|ads_hidden|challenge\.[\w-]+|challenge_join\.[\w-]+|challenge_result\.[\w-]+\.[\w-]+|steps\.[\w.-]+|following/[\w-]+)$')
      .hasMatch(key);
  Future<void> _persist() async {
    final saved = await _prefs!.setString(
        _diskKey,
        jsonEncode({
          'values': _values,
          'versions': _versions,
          'outbox': _outbox,
        }));
    if (!saved) {
      throw StateError('Device storage is full. Your change was not saved.');
    }
  }

  Future<void> _locked(Future<void> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.catchError((Object _) {});
    return result;
  }

  Object? get(String key) => _values[key];
  List<String> get keys => _values.keys.toList();
  Object? serverValue(String key) => (_remote[key] as Map?)?['value'];
  String? getString(String key) => _values[key] as String?;
  int? getInt(String key) => (_values[key] as num?)?.toInt();
  double? getDouble(String key) => (_values[key] as num?)?.toDouble();
  bool? getBool(String key) => _values[key] as bool?;
  List<String>? getStringList(String key) =>
      (_values[key] as List?)?.cast<String>();
  Future<bool> setString(String key, String value) => put(key, value);
  Future<bool> setInt(String key, int value) => put(key, value);
  Future<bool> setDouble(String key, double value) => put(key, value);
  Future<bool> setBool(String key, bool value) => put(key, value);
  Future<bool> setStringList(String key, List<String> value) => put(key, value);
  Future<bool> remove(String key) => put(key, null);

  Future<bool> put(String key, Object? value) async {
    return putAll({key: value});
  }

  Future<bool> putAll(Map<String, Object?> changes) async {
    await initialize();
    var changed = false;
    await _locked(() async {
      final previous = Map<String, dynamic>.from(_values);
      final previousOutbox =
          _outbox.map((op) => Map<String, dynamic>.from(op)).toList();
      for (final entry in changes.entries) {
        if (jsonEncode(_values[entry.key]) == jsonEncode(entry.value)) continue;
        changed = true;
        _values[entry.key] = entry.value;
        if (_syncable(entry.key)) {
          _outbox.removeWhere((op) => op['key'] == entry.key);
          _outbox.add({
            'id': operationId(),
            'key': entry.key,
            'value': entry.value,
            'base': _versions[entry.key] ?? 0
          });
        }
      }
      if (changed) {
        try {
          await _persist();
        } catch (_) {
          _values = previous;
          _outbox = previousOutbox;
          rethrow;
        }
      }
    });
    if (changed) {
      notifyListeners();
      unawaited(sync());
    }
    return true;
  }

  void start() {
    _timer ??=
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(sync()));
    unawaited(sync());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final endpoint = Uri.parse('$accountApiUrl$path');
    if (endpoint.scheme != 'https') {
      throw StateError('The account server requires HTTPS.');
    }
    final headers = {
      'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token'
    };
    final response = await (body == null
            ? client.get(endpoint, headers: headers)
            : client.post(endpoint, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      if (response.statusCode == 401 && auth) {
        throw StateError('Sign in again to sync. Local data is safe.');
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      throw StateError(result['error'] as String? ?? 'Server unavailable');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> authenticate(String email, String password,
      {String? username}) async {
    await initialize();
    final session = await request(
        username == null ? '/v2/auth/login' : '/v2/auth/register',
        auth: false,
        body: {
          'email': email,
          'password': password,
          if (username != null) 'username': username
        });
    await acceptSession(session, importGuest: username != null);
  }

  Future<void> acceptSession(Map<String, dynamic> session,
      {bool importGuest = false}) async {
    await initialize();
    if (session['token'] is! String ||
        session['user'] is! Map ||
        session['user']['id'] is! String ||
        session['user']['username'] is! String) {
      throw StateError('Invalid account session. Please sign in again.');
    }
    // Persist only the session token in OS-protected storage, never the password.
    await secure.write(key: 'fitquest.session', value: jsonEncode(session));
    await _locked(() async {
      final guest = scope == 'guest' && importGuest
          ? Map<String, dynamic>.from(_values)
          : <String, dynamic>{};
      user = session['user'] as Map<String, dynamic>;
      _token = session['token'] as String;
      scope = user!['id'] as String;
      _loadDisk();
      for (final entry in guest.entries) {
        if (_syncable(entry.key) && !_values.containsKey(entry.key)) {
          _values[entry.key] = entry.value;
          _outbox.add({
            'id': operationId(),
            'key': entry.key,
            'value': entry.value,
            'base': 0
          });
        }
      }
      await _persist();
      generation++;
    });
    notifyListeners();
    await sync();
  }

  Future<void> signOut() async {
    await initialize();
    // Remote revocation is best effort; local sign-out always works offline.
    try {
      await request('/v2/auth/logout', body: {});
    } catch (_) {}
    await secure.delete(key: 'fitquest.session');
    await secure.delete(key: 'fitquest.oauth.pending');
    await _locked(() async {
      user = null;
      _token = null;
      scope = 'guest';
      _loadDisk();
      generation++;
      status =
          'Signed out. Account data remains saved privately on this device.';
    });
    notifyListeners();
  }

  Future<void> sync() async {
    await initialize();
    if (syncing || !signedIn) return;
    syncing = true;
    final activeScope = scope;
    try {
      await _tail;
      final batch =
          _outbox.take(200).map((op) => Map<String, dynamic>.from(op)).toList();
      final result = await request('/v2/sync', body: {'operations': batch});
      await _locked(() async {
        if (scope != activeScope) return;
        final acknowledged =
            (result['acknowledged'] as List).cast<String>().toSet();
        _outbox.removeWhere((op) => acknowledged.contains(op['id']));
        final sent = {for (final op in batch) op['key']: op};
        _remote = Map<String, dynamic>.from(result['state'] as Map);
        conflicts = (result['conflicts'] as List).cast<String>();
        for (final entry in _remote.entries) {
          final row = entry.value as Map;
          final pending = _outbox.where((op) => op['key'] == entry.key);
          _versions[entry.key] = row['version'];
          if (pending.isEmpty) {
            if (jsonEncode(_values[entry.key]) != jsonEncode(row['value'])) {
              generation++;
            }
            _values[entry.key] = row['value'];
          } else if (sent[entry.key] != null &&
              acknowledged.contains(sent[entry.key]!['id'])) {
            // A newer local change arrived while the older operation was in flight.
            for (final op in pending) {
              op['base'] = row['version'];
            }
          }
        }
        await _persist();
        status = conflicts.isNotEmpty
            ? 'Sync needs your choice for ${conflicts.length} item(s)'
            : pending > 0
                ? '$pending changes waiting to sync'
                : 'All changes synced';
      });
    } catch (error) {
      if (scope == activeScope) {
        status =
            'Offline — changes saved on this device. ${error is StateError ? error.message : 'Will retry automatically.'}';
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> resolve(String key, {required bool keepLocal}) async {
    await _locked(() async {
      final row = _remote[key] as Map?;
      _outbox.removeWhere((op) => op['key'] == key);
      if (keepLocal) {
        _outbox.add({
          'id': operationId(),
          'key': key,
          'value': _values[key],
          'base': row?['version'] ?? 0
        });
      } else {
        _values[key] = row?['value'];
        generation++;
      }
      conflicts.remove(key);
      await _persist();
    });
    notifyListeners();
    await sync();
  }
}
