import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'friend_links.dart';
import 'offline_store.dart';
import 'social_auth.dart';

List<Map<String, dynamic>> knownFriends(OfflineStore store) =>
    (jsonDecode(store.getString('_known_people') ?? '[]') as List)
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();

Future<void> rememberFriends(OfflineStore store,
    Iterable<Map<String, dynamic>> people, String scope) async {
  if (store.scope != scope) return;
  final known = {
    for (final person in knownFriends(store)) person['id'] as String: person
  };
  for (final person in people) {
    known[person['id'] as String] = {
      'id': person['id'],
      'username': person['username']
    };
  }
  await store.putAll({'_known_people': jsonEncode(known.values.toList())},
      expectedScope: scope);
}

class SocialFriendImportPanel extends StatefulWidget {
  const SocialFriendImportPanel({super.key});
  @override
  State<SocialFriendImportPanel> createState() =>
      _SocialFriendImportPanelState();
}

class _SocialFriendImportPanelState extends State<SocialFriendImportPanel> {
  final selected = <String>{};
  bool busy = false;
  String? message;
  int generation = 0;
  late final String panelScope;
  OfflineStore get store => OfflineStore.instance;
  @override
  void initState() {
    super.initState();
    panelScope = store.scope;
    generation = SocialAuth.instance.importGeneration;
    SocialAuth.instance.addListener(onAuthChange);
    unawaited(SocialAuth.instance.refresh());
    unawaited(refresh());
  }

  @override
  void dispose() {
    SocialAuth.instance.removeListener(onAuthChange);
    super.dispose();
  }

  void onAuthChange() {
    if (generation != SocialAuth.instance.importGeneration) {
      generation = SocialAuth.instance.importGeneration;
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final scope = store.scope;
    try {
      if (store.getBool('_clear_friend_imports') == true) {
        await store
            .request('/v2/friends/imports/clear', body: {'provider': 'all'});
        await store
            .putAll({'_clear_friend_imports': false}, expectedScope: scope);
      }
      final result = await store.request('/v2/friends/suggestions');
      final people = (result['people'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      await store.putAll({'_social_import_cache': jsonEncode(result)},
          expectedScope: scope);
      await rememberFriends(store, people, scope);
      if (mounted && store.scope == scope) {
        setState(() {
          final allowed = people.map((p) => p['id']).toSet();
          selected.removeWhere((id) => !allowed.contains(id));
          message = null;
        });
      }
    } catch (_) {
      if (mounted && store.scope == scope) {
        setState(() => message =
            'Offline: saved suggestions and follow choices are still available.');
      }
    }
  }

  Future<void> startImport(String provider) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (store.getBool('_clear_friend_imports') == true) await refresh();
      if (!mounted || store.scope != panelScope) return;
      if (store.getBool('_clear_friend_imports') == true) {
        setState(() => message =
            'Connect to finish clearing old suggestions before importing again.');
        return;
      }
      await SocialAuth.instance.start(provider, importFriends: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> followSelected() async {
    setState(() => busy = true);
    try {
      await store.putAll({for (final id in selected) 'following/$id': true},
          expectedScope: panelScope);
      if (mounted) {
        setState(() {
          selected.clear();
          message = 'Follow choices saved. They sync when connected.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            message = 'Could not save your follow choices. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([store, SocialAuth.instance]),
      builder: (context, _) {
        final auth = SocialAuth.instance;
        final raw = store.getString('_social_import_cache');
        final data =
            raw == null || store.getBool('_clear_friend_imports') == true
                ? <String, dynamic>{}
                : jsonDecode(raw) as Map<String, dynamic>;
        final suggestions = <String, Map<String, dynamic>>{};
        for (final row in data['people'] as List? ?? []) {
          final person = Map<String, dynamic>.from(row as Map);
          final id = person['id'] as String;
          suggestions.putIfAbsent(id, () => {...person, 'sources': <String>[]});
          (suggestions[id]!['sources'] as List<String>)
              .add(person['provider'] as String);
        }
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Find friends from social accounts',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Text(
                          'You choose each connection. Imports never follow people or send invitations automatically.'),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Let social friends discover me'),
                          subtitle: const Text(
                              'People with your verified Google email in their contacts, or eligible Facebook friends, can find your public username. Username search and invite links still work when off.'),
                          value: store.getBool('friend_discovery') ?? false,
                          onChanged: (value) =>
                              store.setBool('friend_discovery', value)),
                      OutlinedButton.icon(
                          onPressed: busy ||
                                  auth.waiting ||
                                  auth.providers['google'] != true
                              ? null
                              : () => startImport('google'),
                          icon: const Icon(Icons.contacts_outlined),
                          label:
                              const Text('Find Google Contacts on FitQuest')),
                      const Text(
                          'Requires read-only contacts consent. Matches are people with a verified linked Google account who allow discovery.'),
                      OutlinedButton.icon(
                          onPressed: busy ||
                                  auth.waiting ||
                                  auth.providers['facebook'] != true
                              ? null
                              : () => startImport('facebook'),
                          icon: const Icon(Icons.facebook),
                          label:
                              const Text('Find Facebook friends on FitQuest')),
                      const Text(
                          'Facebook returns eligible friends who also use this app and grant friend-list access. They must also allow FitQuest discovery.'),
                      if (!auth.providers.values.any((value) => value))
                        const Text(
                            'Social imports will activate after Google/Meta credentials and permissions are configured. Invite links work now.'),
                      if (auth.message != null) Text(auth.message!),
                      if (auth.waiting)
                        TextButton(
                            onPressed: auth.cancel,
                            child: const Text('Cancel connection')),
                      if (message != null) Text(message!),
                      if ((data['imports'] as List? ?? [])
                          .any((row) => (row as Map)['limited'] == 1))
                        const Text(
                            'This import reached the provider page limit. Suggestions may be incomplete.'),
                      for (final person in suggestions.values)
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('@${person['username']}'),
                            subtitle: Text((person['sources'] as List<String>)
                                .join(' · ')),
                            value: selected.contains(person['id']),
                            onChanged: busy
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        selected.add(person['id'] as String);
                                      } else {
                                        selected.remove(person['id']);
                                      }
                                    }),
                            secondary: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => store.setBool(
                                        'following/${person['id']}',
                                        !(store.getBool(
                                                'following/${person['id']}') ??
                                            false)),
                                child: Text(store.getBool(
                                            'following/${person['id']}') ==
                                        true
                                    ? 'Following'
                                    : 'Follow'))),
                      if ((data['imports'] as List? ?? []).isNotEmpty &&
                          suggestions.isEmpty)
                        const Text(
                            'No eligible matches yet. Friends may need to join, connect that provider and enable discovery.'),
                      if (suggestions.isNotEmpty)
                        FilledButton(
                            onPressed: selected.isEmpty || busy
                                ? null
                                : followSelected,
                            child:
                                Text('Follow selected (${selected.length})')),
                      Wrap(spacing: 12, children: [
                        TextButton(
                            onPressed: refresh,
                            child: const Text('Refresh suggestions')),
                        TextButton(
                            onPressed: () async {
                              await store.putAll({
                                '_clear_friend_imports': true,
                                '_social_import_cache': null
                              });
                              if (mounted) setState(selected.clear);
                              await refresh();
                            },
                            child: const Text('Clear imported suggestions'))
                      ]),
                      const Divider(),
                      Text('Invite friends to join',
                          style: Theme.of(context).textTheme.titleMedium),
                      Builder(
                          builder: (context) => FilledButton.icon(
                              onPressed: () => shareFriendInvitation(context),
                              icon: const Icon(Icons.share_outlined),
                              label: const Text(
                                  'Invite via WhatsApp, Facebook or another app'))),
                      TextButton.icon(
                          onPressed: () async {
                            try {
                              final invite = await ownInvitation();
                              await Clipboard.setData(
                                  ClipboardData(text: invite.url));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Invitation link copied.')));
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Connect once to create your invitation link.')));
                              }
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy my invitation link')),
                      TextButton(
                          onPressed: () => enterFriendInvitation(context),
                          child: const Text('Open an invitation link or code')),
                    ])));
      });
}
