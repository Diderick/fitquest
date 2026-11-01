import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'offline_store.dart';
import 'step_tracker.dart';
import 'social_auth.dart';

String jsonEncodeSocial(Map<String, dynamic> value) => jsonEncode(value);
Map<String, dynamic> decodeSocial(String value) =>
    jsonDecode(value) as Map<String, dynamic>;

String syncItemLabel(String key) =>
    {
      'fitquest.activities.v1': 'Activities',
      'weekly_goal': 'Weekly goal',
      'appearance_mode': 'Appearance',
      'active_plan': 'Training plan',
      'community_posts': 'Community posts',
      'community_joined': 'Challenges',
      'community_liked': 'Reactions',
      'bl_start': 'Starting weight',
      'bl_current': 'Latest weigh-in',
      'bl_joined': 'Competition entry',
      'body_fat': 'Body fat',
      'ads_hidden': 'Sponsor preference',
    }[key] ??
    (key.startsWith('challenge_result.')
        ? 'Fitness test result'
        : key.startsWith('challenge_join.')
            ? 'Challenge participation'
            : key.startsWith('challenge.')
                ? 'Fitness challenge'
                : key.startsWith('nutrition')
                    ? 'Nutrition'
                    : key.startsWith('steps.')
                        ? 'Daily steps'
                        : 'Following');

String syncValueSummary(Object? value) {
  if (value == null) return 'Not recorded';
  if (value is List) return '${value.length} saved items';
  if (value is String && value.startsWith('[')) {
    try {
      return '${(jsonDecode(value) as List).length} saved entries';
    } catch (_) {}
  }
  return value.toString();
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();
  bool register = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    username.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await OfflineStore.instance.authenticate(email.text.trim(), password.text,
          username: register ? username.text.trim() : null);
      password.clear();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is StateError
            ? e.message.toString()
            : 'Cannot connect. Your offline data is safe. Try again when online.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) {
        final store = OfflineStore.instance;
        return Scaffold(
            appBar: AppBar(title: const Text('Account & sync')),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              if (store.signedIn) ...[
                Text('@${store.user!['username']}',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(store.status),
                Text('${store.pending} changes pending'),
                const SocialSignInButtons(linkAccount: true),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: store.syncing ? null : store.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now')),
                OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const FriendsPage())),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Find friends & following')),
                for (final key in store.conflicts)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Changes on two devices: ${syncItemLabel(key)}'),
                                Text(
                                    'This phone: ${syncValueSummary(store.get(key))}'),
                                Text(
                                    'Server: ${syncValueSummary(store.serverValue(key))}'),
                                const Text(
                                    'Both versions are kept until you choose which to sync.'),
                                Wrap(spacing: 12, children: [
                                  TextButton(
                                      onPressed: () =>
                                          store.resolve(key, keepLocal: true),
                                      child: const Text('Keep this device')),
                                  TextButton(
                                      onPressed: () =>
                                          store.resolve(key, keepLocal: false),
                                      child: const Text('Use server version')),
                                ]),
                              ]))),
                const Divider(),
                const Text(
                    'Your personal weights, routes and nutrition are private. Only your username and community posts are shared with followers.'),
                TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await store.signOut();
                            } catch (_) {
                              if (mounted) {
                                setState(() => error =
                                    'Could not sign out. Please retry.');
                              }
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text('Sign out')),
              ] else ...[
                Text(register ? 'Create your FitQuest account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                    'Keep using FitQuest offline. Connect once to create an account or sign in on a new phone; future changes sync automatically.'),
                const SocialSignInButtons(),
                const Divider(),
                if (register)
                  TextField(
                      controller: username,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                          labelText: 'Public username',
                          helperText: '3–30 letters, numbers or underscores')),
                TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email')),
                TextField(
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 12 characters')),
                if (register)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'Creating an account uploads this device’s guest activities and other saved data to your private account.')),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy
                        ? 'Connecting…'
                        : register
                            ? 'Create account'
                            : 'Sign in')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              register = !register;
                              error = null;
                            }),
                    child: Text(register
                        ? 'Already have an account? Sign in'
                        : 'Create an account')),
              ],
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 24),
              const StepTrackingCard(),
              const AdPreferences(),
            ]));
      });
}

class SocialSignInButtons extends StatefulWidget {
  final bool linkAccount;
  const SocialSignInButtons({super.key, this.linkAccount = false});
  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  @override
  void initState() {
    super.initState();
    unawaited(SocialAuth.instance.refresh());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: SocialAuth.instance,
      builder: (context, _) {
        final auth = SocialAuth.instance;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              for (final provider in ['google', 'facebook'])
                OutlinedButton.icon(
                    onPressed: auth.waiting ||
                            auth.providers[provider] != true ||
                            (widget.linkAccount &&
                                auth.linked.contains(provider))
                        ? null
                        : () => auth.start(provider),
                    icon: Icon(provider == 'google'
                        ? Icons.account_circle_outlined
                        : Icons.facebook),
                    label: Text(
                        '${widget.linkAccount ? auth.linked.contains(provider) ? 'Linked to' : 'Link' : 'Continue with'} ${provider == 'google' ? 'Google' : 'Facebook'}')),
              if (!auth.providers.values.any((available) => available))
                const Text(
                    'Google and Facebook sign-in will be available once connected. Email sign-in works now.'),
              if (!widget.linkAccount)
                const Text(
                    'New social accounts receive a public FitQuest username. Guest data is imported only when a new account is created.'),
              if (auth.message != null) Text(auth.message!),
              if (auth.waiting)
                TextButton(
                    onPressed: auth.cancel,
                    child: const Text('Cancel browser sign-in')),
            ]);
      });
}

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final query = TextEditingController();
  List<Map<String, dynamic>> people = [],
      following = [],
      followers = [],
      posts = [];
  String? message;
  bool loading = false;
  OfflineStore get store => OfflineStore.instance;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> rows(Object? value) => (value as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  Future<void> load() async {
    final cache = store.getString('_social_cache');
    if (cache != null) applyCache(cache);
    if (!store.signedIn) return;
    try {
      final data = await store.request('/v2/social');
      final raw = jsonEncodeSocial(data);
      await store.setString('_social_cache', raw);
      if (mounted) applyCache(raw);
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Offline: showing saved friends. Follow changes will sync later.');
      }
    }
  }

  void applyCache(String raw) {
    final data = decodeSocial(raw);
    setState(() {
      following = rows(data['following']);
      followers = rows(data['followers']);
      posts = rows(data['posts']);
      people = rows(data['people']);
    });
  }

  Future<void> search() async {
    if (loading) return;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final result = await store.request(
          '/v2/people?q=${Uri.encodeQueryComponent(query.text.trim())}');
      if (mounted) setState(() => people = rows(result['people']));
      await store.setString(
          '_social_cache',
          jsonEncodeSocial({
            'following': following,
            'followers': followers,
            'posts': posts,
            'people': people
          }));
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Search needs a connection. You can still follow saved people below.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool isFollowing(Map<String, dynamic> person) =>
      store.getBool('following/${person['id']}') ??
      following.any((u) => u['id'] == person['id']);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Friends & following'), actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh))
      ]),
      body: AnimatedBuilder(
          animation: store,
          builder: (context, _) =>
              ListView(padding: const EdgeInsets.all(16), children: [
                if (!store.signedIn) ...[
                  const Text('Create an account to find and follow friends.'),
                  FilledButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const AccountPage())),
                      child: const Text('Account & sync')),
                ] else ...[
                  const Text(
                      'Search by public username. Following is one-way; follow each other to become friends.'),
                  TextField(
                      controller: query,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                          labelText: 'Find a friend',
                          suffixIcon: IconButton(
                              onPressed: loading ? null : search,
                              icon: const Icon(Icons.search)))),
                  if (message != null) Text(message!),
                  for (final group in [
                    ('Search results', people),
                    ('Following', following),
                    ('Followers', followers)
                  ]) ...[
                    Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(group.$1,
                            style: Theme.of(context).textTheme.titleMedium)),
                    if (group.$2.isEmpty) const Text('No people yet'),
                    for (final person in group.$2)
                      ListTile(
                          title: Text('@${person['username']}'),
                          subtitle:
                              followers.any((u) => u['id'] == person['id'])
                                  ? Text(isFollowing(person)
                                      ? 'Friends · follow each other'
                                      : 'Follows you')
                                  : null,
                          trailing: OutlinedButton(
                              onPressed: () async {
                                await store.setBool('following/${person['id']}',
                                    !isFollowing(person));
                              },
                              child: Text(isFollowing(person)
                                  ? 'Following'
                                  : 'Follow'))),
                  ],
                  const Divider(),
                  Text('From people you follow',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final post in posts)
                    Card(
                        child: ListTile(
                            title: Text('@${post['username']}'),
                            subtitle: Text(post['text'] as String))),
                ],
              ])));
}

class StepTrackingCard extends StatelessWidget {
  const StepTrackingCard({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: StepTracker.instance,
      builder: (context, _) {
        final tracker = StepTracker.instance;
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phone step sensor',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('${tracker.today} steps today'),
                      Text(tracker.status),
                      const Text(
                          'Counted from the phone sensor, without adding estimated workout steps. Keep your phone with you.'),
                      TextButton(
                          onPressed: tracker.enabled
                              ? tracker.disable
                              : tracker.enable,
                          child: Text(tracker.enabled
                              ? 'Pause step counting'
                              : 'Enable step counting')),
                    ])));
      });
}

class AdPreferences extends StatelessWidget {
  const AdPreferences({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) => SwitchListTile(
          title: const Text('Hide sponsor placements'),
          subtitle: const Text(
              'Free during preview. Live ads and a store purchase option will be configured later.'),
          value: OfflineStore.instance.getBool('ads_hidden') ?? false,
          onChanged: (hide) =>
              OfflineStore.instance.setBool('ads_hidden', hide)));
}

class SponsorPlacement extends StatelessWidget {
  const SponsorPlacement({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) =>
          OfflineStore.instance.getBool('ads_hidden') == true
              ? const SizedBox.shrink()
              : Card(
                  child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('Sponsor placement · preview'),
                      subtitle: const Text('No live ads yet'),
                      trailing: TextButton(
                          onPressed: () =>
                              OfflineStore.instance.setBool('ads_hidden', true),
                          child: const Text('Hide')))));
}
