import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account_ui.dart' show AccountPage;
import 'challenges.dart';
import 'challenge_ui.dart' show ChallengeDetail;
import 'offline_store.dart';

const fitquestAndroidDownloadUrl = String.fromEnvironment(
    'FITQUEST_ANDROID_DOWNLOAD_URL',
    defaultValue:
        'https://play.google.com/store/apps/details?id=com.fitquest.app');
const fitquestIosDownloadUrl = String.fromEnvironment(
    'FITQUEST_IOS_DOWNLOAD_URL',
    defaultValue: 'https://apps.apple.com/');

final _inviteCodePattern = RegExp(r'^[A-Za-z0-9_-]{12,32}$');

String _withInviteCode(String baseUrl, FriendInvitation invitation) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasScheme) return baseUrl;
  final params = Map<String, String>.from(uri.queryParameters)
    ..['invite'] = invitation.code;
  if (invitation.challengeId != null) {
    params['challenge'] = invitation.challengeId!;
  }
  return uri.replace(queryParameters: params).toString();
}

String invitationShareText(FriendInvitation invitation,
    {String? challengeTitle}) {
  final lines = <String>[
    challengeTitle == null
        ? 'Join me on FitQuest! Follow my training and challenges.'
        : 'Join my FitQuest challenge: $challengeTitle',
    'Invite code: ${invitation.code}',
    invitation.url,
  ];
  final downloads = <String>[
    if (fitquestAndroidDownloadUrl.isNotEmpty)
      'Android: ${_withInviteCode(fitquestAndroidDownloadUrl, invitation)}',
    if (fitquestIosDownloadUrl.isNotEmpty)
      'iPhone: ${_withInviteCode(fitquestIosDownloadUrl, invitation)}',
  ];
  if (downloads.isNotEmpty) {
    lines
      ..add('')
      ..add(
          'No app yet? Download first, then open this invitation link or paste the invite code:')
      ..addAll(downloads);
  }
  return lines.join('\n');
}

class FriendInvitation {
  final String code;
  final String? challengeId;
  const FriendInvitation(this.code, {this.challengeId});
  String get url =>
      '$accountApiUrl/join/$code${challengeId == null ? '' : '?challenge=${Uri.encodeQueryComponent(challengeId!)}'}';
  static FriendInvitation? parse(String text) {
    final raw = text.trim();
    if (_inviteCodePattern.hasMatch(raw)) {
      return FriendInvitation(raw);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    String? code;
    if (uri.scheme == 'fitquest-auth' && uri.host == 'invite') {
      code = uri.queryParameters['code'];
    }
    if (uri.scheme == 'https' &&
        uri.host == Uri.parse(accountApiUrl).host &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'join') {
      code = uri.pathSegments.last;
    }
    final challenge = uri.queryParameters['challenge'];
    if (code == null ||
        !_inviteCodePattern.hasMatch(code) ||
        (challenge != null && !RegExp(r'^[\w-]{1,64}$').hasMatch(challenge))) {
      return null;
    }
    return FriendInvitation(code, challengeId: challenge);
  }
}

class FriendLinkRouter extends ChangeNotifier {
  static final instance = FriendLinkRouter();
  FriendInvitation? pending;
  String? _lastLink;
  DateTime? _lastAt;
  Future<void> receive(Uri uri) async {
    final invitation = FriendInvitation.parse(uri.toString());
    if (invitation == null) return;
    if (_lastLink == invitation.url &&
        _lastAt != null &&
        DateTime.now().difference(_lastAt!).inSeconds < 2) {
      return;
    }
    _lastLink = invitation.url;
    _lastAt = DateTime.now();
    pending = invitation;
    await (await SharedPreferences.getInstance())
        .setString('fitquest.pending_invite', invitation.url);
    notifyListeners();
  }

  Future<void> restore() async {
    if (pending != null) return;
    final raw = (await SharedPreferences.getInstance())
        .getString('fitquest.pending_invite');
    if (raw != null) pending = FriendInvitation.parse(raw);
    if (pending != null) notifyListeners();
  }

  FriendInvitation? takePending() {
    final value = pending;
    pending = null;
    return value;
  }

  Future<void> finish(FriendInvitation shown) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('fitquest.pending_invite') == shown.url) {
      await prefs.remove('fitquest.pending_invite');
    }
  }
}

Future<FriendInvitation> ownInvitation({String? challengeId}) async {
  final store = await OfflineStore.getInstance();
  if (!store.signedIn) throw StateError('Sign in to create an invitation.');
  final scope = store.scope;
  var code = store.getString('_friend_invite_code');
  if (code == null) {
    final result = await store.request('/v2/friends/invite', body: {});
    code = result['code'] as String;
    await store.putAll({'_friend_invite_code': code}, expectedScope: scope);
  }
  return FriendInvitation(code, challengeId: challengeId);
}

Future<void> shareFriendInvitation(BuildContext context,
    {String? challengeId, String? challengeTitle}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    final invitation = await ownInvitation(challengeId: challengeId);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
        text: invitationShareText(invitation, challengeTitle: challengeTitle),
        subject: 'FitQuest invitation',
        sharePositionOrigin: origin));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Connect once to create your invitation, then share it again. You can also copy your username.')));
    }
  }
}

Future<void> enterFriendInvitation(BuildContext context) async {
  final text = await showDialog<String>(
      context: context, builder: (_) => const _InvitationInput());
  if (text == null || !context.mounted) return;
  final invitation = FriendInvitation.parse(text);
  if (invitation == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid FitQuest invitation link or code.')));
    return;
  }
  await Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => FriendInvitePage(invitation: invitation)));
}

class _InvitationInput extends StatefulWidget {
  const _InvitationInput();
  @override
  State<_InvitationInput> createState() => _InvitationInputState();
}

class _InvitationInputState extends State<_InvitationInput> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Open an invitation'),
          content: TextField(
              controller: controller,
              decoration:
                  const InputDecoration(labelText: 'Invitation link or code')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Open'))
          ]);
}

class FriendInvitePage extends StatefulWidget {
  final FriendInvitation invitation;
  const FriendInvitePage({super.key, required this.invitation});
  @override
  State<FriendInvitePage> createState() => _FriendInvitePageState();
}

class _FriendInvitePageState extends State<FriendInvitePage> {
  Map<String, dynamic>? person;
  FitnessChallenge? challenge;
  String? message;
  bool loading = false;
  String? loadedScope;
  OfflineStore get store => OfflineStore.instance;
  String get cacheKey =>
      '_invite_cache.${widget.invitation.code}.${widget.invitation.challengeId ?? ''}';
  @override
  void initState() {
    super.initState();
    store.addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (store.signedIn && loadedScope != store.scope && !loading) {
      unawaited(load());
    }
  }

  @override
  void dispose() {
    store.removeListener(changed);
    super.dispose();
  }

  void apply(Map<String, dynamic> data) {
    person = Map<String, dynamic>.from(data['person'] as Map);
    challenge = data['challenge'] == null
        ? null
        : FitnessChallenge.fromJson(
            Map<String, dynamic>.from(data['challenge'] as Map));
  }

  Future<void> load() async {
    await store.initialize();
    if (!store.signedIn || !mounted) return;
    setState(() {
      loading = true;
      message = null;
    });
    final scope = store.scope;
    loadedScope = scope;
    final cached = store.getString(cacheKey);
    if (cached != null) {
      setState(() => apply(jsonDecode(cached) as Map<String, dynamic>));
    }
    try {
      final invite = widget.invitation;
      final data = await store.request(
          '/v2/friends/invites/${invite.code}${invite.challengeId == null ? '' : '?challenge=${Uri.encodeQueryComponent(invite.challengeId!)}'}');
      await store.putAll({cacheKey: jsonEncode(data)}, expectedScope: scope);
      if (mounted && scope == store.scope) setState(() => apply(data));
    } catch (_) {
      if (mounted && scope == store.scope) {
        setState(() => message = person == null
            ? 'Connect to open this invitation, then retry.'
            : 'Showing a saved invitation. Follow and join choices will sync when connected.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (store.signedIn && loadedScope != store.scope) unawaited(load());
      }
    }
  }

  Future<void> followAndJoin(bool join) async {
    if (person == null) return;
    try {
      final changes = <String, Object?>{'following/${person!['id']}': true};
      if (join && challenge != null) {
        changes['challenge_join.${challenge!.id}'] = true;
        final known = ChallengeRepository(store)
            .discovered
            .where((c) => c.id != challenge!.id)
            .map((c) =>
                {...c.toJson(), 'ownerId': c.ownerId, 'ownerName': c.ownerName})
            .toList();
        known.add({
          ...challenge!.toJson(),
          'ownerId': challenge!.ownerId,
          'ownerName': challenge!.ownerName
        });
        changes['_challenge_discovery'] = jsonEncode(known);
      }
      final people = (jsonDecode(store.getString('_known_people') ?? '[]')
              as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .where((p) => p['id'] != person!['id'])
          .toList()
        ..add(person!);
      changes['_known_people'] = jsonEncode(people);
      await store.putAll(changes, expectedScope: loadedScope);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(join
              ? 'Following & joined on this phone. Changes sync when connected.'
              : 'Following saved. Changes sync when connected.')));
      if (join && challenge != null) {
        await Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => ChallengeDetail(challenge: challenge!)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save your choice. Please retry.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('FitQuest invitation')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            if (!store.signedIn) ...[
              const Text(
                  'Join FitQuest or sign in to follow this friend and join their challenge.'),
              const SizedBox(height: 8),
              SelectableText('Invite code: ${widget.invitation.code}'),
              const SizedBox(height: 6),
              TextButton.icon(
                  onPressed: () async {
                    await SharePlus.instance.share(ShareParams(
                        text: invitationShareText(widget.invitation),
                        subject: 'FitQuest invitation'));
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share invite with app download links')),
              if (fitquestAndroidDownloadUrl.isNotEmpty)
                OutlinedButton.icon(
                    onPressed: () => launchUrl(
                        Uri.parse(_withInviteCode(
                            fitquestAndroidDownloadUrl, widget.invitation)),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.android),
                    label: const Text('Download for Android')),
              if (fitquestIosDownloadUrl.isNotEmpty)
                OutlinedButton.icon(
                    onPressed: () => launchUrl(
                        Uri.parse(_withInviteCode(
                            fitquestIosDownloadUrl, widget.invitation)),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.phone_iphone),
                    label: const Text('Download for iPhone')),
              FilledButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const AccountPage())),
                  child: const Text('Join FitQuest / sign in')),
            ] else ...[
              if (loading) const LinearProgressIndicator(),
              if (message != null) Text(message!),
              if (person != null && loadedScope == store.scope) ...[
                Text('@${person!['username']}',
                    style: Theme.of(context).textTheme.headlineSmall),
                if (widget.invitation.challengeId != null && challenge == null)
                  const Text(
                      'This challenge is private or unavailable. You can still follow its creator.'),
                if (person!['id'] == store.user!['id'])
                  const Text(
                      'This is your own invitation. Share it with a friend.')
                else ...[
                  FilledButton(
                      onPressed: () => followAndJoin(false),
                      child: Text(
                          store.getBool('following/${person!['id']}') == true
                              ? 'Following'
                              : 'Follow friend')),
                  if (challenge != null) ...[
                    const SizedBox(height: 20),
                    Text(challenge!.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(
                        '${challenge!.category} · ${challenge!.events.length} exercises'),
                    OutlinedButton(
                        onPressed: () => followAndJoin(true),
                        child: Text(
                            store.getBool('challenge_join.${challenge!.id}') ==
                                    true
                                ? 'Open joined challenge'
                                : 'Follow & join challenge')),
                  ],
                ],
              ],
              TextButton(
                  onPressed: load,
                  child: const Text('Retry / refresh invitation')),
            ],
            const Text(
                'Opening an invitation never follows or joins automatically.'),
          ])));
}
