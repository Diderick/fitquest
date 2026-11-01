import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'offline_store.dart';

class SocialAuth extends ChangeNotifier {
  static final instance = SocialAuth();
  final AppLinks links = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool waiting = false, _completing = false;
  String? message;
  Map<String, bool> providers = {'google': false, 'facebook': false};
  List<String> linked = [];
  bool get supported =>
      !kIsWeb &&
      [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform);
  OfflineStore get store => OfflineStore.instance;
  Future<void> initialize() async {
    if (!supported) return;
    if (_subscription != null) return;
    try {
      _subscription = links.uriLinkStream
          .listen((uri) => unawaited(complete(uri)), onError: (_) {});
      final initial = await links.getInitialLink();
      if (initial != null) await complete(initial);
    } catch (_) {
      /* Email and offline use remain available on unsupported platforms. */
    }
  }

  Future<void> refresh() async {
    if (!supported) {
      providers = {'google': false, 'facebook': false};
      message =
          'Social sign-in is available in the Android and iPhone apps. Use email sign-in on this platform.';
      notifyListeners();
      return;
    }
    await store.initialize();
    try {
      final response = await store.request('/v2/oauth/providers');
      providers = Map<String, bool>.from(response['providers'] as Map);
      linked = (response['linked'] as List).cast<String>();
    } catch (_) {
      message = 'Connect to check Google and Facebook sign-in availability.';
    }
    notifyListeners();
  }

  Future<void> start(String provider) async {
    if (waiting || !providers.containsKey(provider)) return;
    waiting = true;
    message = null;
    notifyListeners();
    try {
      await initialize();
      final verifier = operationId() + operationId();
      final state = operationId();
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      await store.secure.write(
          key: 'fitquest.oauth.pending',
          value: jsonEncode({
            'verifier': verifier,
            'state': state,
            'expires': DateTime.now()
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
          }));
      final response = await store.request('/v2/oauth/$provider/start',
          body: {'challenge': challenge, 'appState': state});
      final uri = Uri.parse(response['authorizationUrl'] as String);
      if (uri.scheme != 'https' ||
          !['accounts.google.com', 'www.facebook.com'].contains(uri.host)) {
        throw StateError('Invalid sign-in address.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the sign-in browser.');
      }
      message = 'Finish sign-in in your browser, then return to FitQuest.';
    } catch (error) {
      await cancel();
      message = error is StateError
          ? error.message.toString()
          : 'Could not start social sign-in. Please try again when connected.';
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    try {
      await store.secure.delete(key: 'fitquest.oauth.pending');
    } catch (_) {}
    waiting = false;
    notifyListeners();
  }

  Future<void> complete(Uri uri) async {
    if (uri.scheme != 'fitquest-auth' ||
        uri.host != 'callback' ||
        _completing) {
      return;
    }
    _completing = true;
    try {
      await store.initialize();
      final raw = await store.secure.read(key: 'fitquest.oauth.pending');
      if (raw == null) return;
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      if (pending['state'] != uri.queryParameters['state'] ||
          (pending['expires'] as int) < DateTime.now().millisecondsSinceEpoch) {
        return;
      }
      if (uri.queryParameters['error'] != null) {
        message = switch (uri.queryParameters['error']) {
          'cancelled' => 'Sign-in was cancelled.',
          'link_required' =>
            'That identity or email belongs to an existing account. Sign in to that account first, then link the provider in Account & sync.',
          _ => 'The provider could not verify sign-in. Please retry.',
        };
        await cancel();
        return;
      }
      final code = uri.queryParameters['code'];
      if (code == null) return;
      final session = await store.request('/v2/oauth/exchange',
          auth: false,
          body: {
            'code': code,
            'verifier': pending['verifier'],
            'appState': pending['state']
          });
      await store.acceptSession(session,
          importGuest: session['created'] == true);
      await cancel();
      message = 'Account connected.';
      await refresh();
    } catch (_) {
      message =
          'Could not finish sign-in. Return to Account & sync and try again.';
      await cancel();
    } finally {
      _completing = false;
      notifyListeners();
    }
  }
}
