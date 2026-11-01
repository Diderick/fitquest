import 'dart:async';
import 'package:flutter/material.dart';
import 'challenges.dart';
import 'offline_store.dart';

String _day(DateTime date) => date.toIso8601String().substring(0, 10);
void openChallenges(BuildContext context) => Navigator.push(
    context, MaterialPageRoute<void>(builder: (_) => const ChallengesPage()));

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});
  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  bool loading = false;
  String? message;
  OfflineStore get store => OfflineStore.instance;
  ChallengeRepository get repo => ChallengeRepository(store);
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      await OfflineStore.getInstance();
      await repo.refresh();
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Offline: your saved challenges and results remain available.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final mine = repo.mine;
        final discovered = repo.discovered
            .where((c) => !mine.any((own) => own.id == c.id))
            .toList();
        Widget tile(FitnessChallenge challenge) => Card(
            child: ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: Text(challenge.title),
                subtitle: Text(
                    '${challenge.category} · ${challenge.events.length} events\n${challenge.startDate} to ${challenge.endDate}${challenge.ownerName == null ? '' : '\nBy @${challenge.ownerName}'}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            ChallengeDetail(challenge: challenge)))));
        return Scaffold(
            appBar: AppBar(title: const Text('Fitness challenges'), actions: [
              IconButton(
                  tooltip: 'Refresh challenges',
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh)),
            ]),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const CreateChallengePage())),
                  icon: const Icon(Icons.add),
                  label: const Text('Create challenge')),
              const SizedBox(height: 12),
              const Text(
                  'Build a military-style fitness test, a CrossFit-style workout or your own challenge. Set exercise rules, pass targets and scoring.'),
              if (loading) const LinearProgressIndicator(),
              if (message != null) Text(message!),
              const SizedBox(height: 20),
              Text('My challenges',
                  style: Theme.of(context).textTheme.titleLarge),
              if (mine.isEmpty)
                const Text(
                    'Create your first challenge. It works offline too.'),
              ...mine.map(tile),
              const SizedBox(height: 20),
              Text('From people you follow',
                  style: Theme.of(context).textTheme.titleLarge),
              if (!store.signedIn)
                const Text(
                    'Sign in and follow friends to discover their shared challenges.'),
              if (store.signedIn && discovered.isEmpty)
                const Text(
                    'No shared challenges yet. Follow a creator and refresh.'),
              ...discovered.map(tile),
            ]));
      });
}

class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});
  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final instructions = TextEditingController();
  String template = 'Custom', category = 'Custom', visibility = 'private';
  DateTime start = DateUtils.dateOnly(DateTime.now());
  late DateTime end = start.add(const Duration(days: 30));
  List<TestEvent> events = challengeTemplate('Custom');
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    instructions.dispose();
    super.dispose();
  }

  Future<void> edit(TestEvent? event) async {
    final saved = await showDialog<TestEvent>(
        context: context, builder: (_) => _EventEditor(event: event));
    if (saved == null || !mounted) return;
    setState(() {
      if (event == null) {
        events.add(saved);
      } else {
        events[events.indexWhere((e) => e.id == event.id)] = saved;
      }
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || saving) return;
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one exercise.')));
      return;
    }
    setState(() => saving = true);
    try {
      final challenge = FitnessChallenge(
          id: operationId(),
          title: title.text.trim(),
          category: category,
          instructions: instructions.text.trim(),
          startDate: _day(start),
          endDate: _day(end),
          visibility: visibility,
          events: events);
      await ChallengeRepository(await OfflineStore.getInstance())
          .create(challenge);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save challenge on this device. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickDate(bool first) async {
    final picked = await showDatePicker(
        context: context,
        initialDate: first ? start : end,
        firstDate: first ? DateTime(2000) : start,
        lastDate: DateTime(2100));
    if (picked != null && mounted) {
      setState(() {
        if (first) {
          start = picked;
          if (end.isBefore(start)) end = start;
        } else {
          end = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Create challenge')),
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
                initialValue: template,
                decoration: const InputDecoration(
                    labelText: 'Start from a template',
                    helperText:
                        'Choosing a template replaces the exercise list.'),
                items: [
                  'Custom',
                  'Military-style test',
                  'CrossFit-style AMRAP',
                  'CrossFit-style for time'
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      template = value;
                      category = value.startsWith('Military')
                          ? 'Military'
                          : value.startsWith('CrossFit')
                              ? 'CrossFit'
                              : 'Custom';
                      events = challengeTemplate(value);
                    });
                  }
                }),
            const SizedBox(height: 12),
            TextFormField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Challenge name'),
                validator: (v) => (v?.trim().isEmpty ?? true)
                    ? 'Enter a challenge name.'
                    : null),
            TextFormField(
                controller: instructions,
                maxLength: 3000,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Rules, equipment and scaling',
                    hintText:
                        'Set the time cap, loads, rest periods, technique and substitutions.')),
            Wrap(spacing: 12, children: [
              OutlinedButton(
                  onPressed: () => pickDate(true),
                  child: Text('Starts ${_day(start)}')),
              OutlinedButton(
                  onPressed: () => pickDate(false),
                  child: Text('Ends ${_day(end)}')),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: visibility,
                decoration:
                    const InputDecoration(labelText: 'Who can participate?'),
                items: const [
                  DropdownMenuItem(value: 'private', child: Text('Only me')),
                  DropdownMenuItem(
                      value: 'followers', child: Text('My followers'))
                ],
                onChanged: (value) => setState(() => visibility = value!)),
            if (visibility == 'followers')
              const Text(
                  'When signed in and synced, followers can join and see participant usernames and results. No weight or route data is shared.'),
            const SizedBox(height: 20),
            Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
            for (final event in events)
              Card(
                  child: ListTile(
                      title: Text(event.name),
                      subtitle: Text(
                          '${event.metric.label} · ${event.higherWins ? 'Higher' : 'Lower'} wins${event.target == null ? '' : '\nPass target: ${event.format(event.target!)}'}'),
                      onTap: () => edit(event),
                      trailing: IconButton(
                          tooltip: 'Remove exercise',
                          onPressed: () => setState(() => events.remove(event)),
                          icon: const Icon(Icons.delete_outline)))),
            OutlinedButton.icon(
                onPressed: events.length >= 20 ? null : () => edit(null),
                icon: const Icon(Icons.add),
                label: const Text('Add exercise')),
            const Text(
                'These are customizable training templates, not official military qualification standards. Events are scored separately; different units are never added together.'),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save challenge')),
          ])));
}

class _EventEditor extends StatefulWidget {
  final TestEvent? event;
  const _EventEditor({this.event});
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name =
      TextEditingController(text: widget.event?.name ?? '');
  late final TextEditingController instructions =
      TextEditingController(text: widget.event?.instructions ?? '');
  late final TextEditingController target =
      TextEditingController(text: widget.event?.target?.toString() ?? '');
  late ChallengeMetric metric = widget.event?.metric ?? ChallengeMetric.reps;
  late bool higher = widget.event?.higherWins ?? true;
  TestEvent get event => TestEvent(
      id: widget.event?.id ?? operationId(),
      name: name.text.trim(),
      instructions: instructions.text.trim(),
      metric: metric,
      higherWins: higher);
  @override
  void dispose() {
    name.dispose();
    instructions.dispose();
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Exercise & scoring'),
          content: SizedBox(
              width: 440,
              child: Form(
                  key: form,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: name,
                        maxLength: 100,
                        decoration:
                            const InputDecoration(labelText: 'Exercise name'),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Enter an exercise name.'
                            : null),
                    TextFormField(
                        controller: instructions,
                        maxLength: 1000,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Exercise protocol')),
                    DropdownButtonFormField<ChallengeMetric>(
                        initialValue: metric,
                        decoration: const InputDecoration(labelText: 'Measure'),
                        items: ChallengeMetric.values
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(v.label)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              metric = value;
                              target.clear();
                            });
                          }
                        }),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            higher ? 'Higher score wins' : 'Lower score wins'),
                        value: higher,
                        onChanged: (value) => setState(() => higher = value)),
                    TextFormField(
                        controller: target,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                            labelText:
                                'Optional pass target · ${metric.label}'),
                        validator: (v) =>
                            v!.trim().isNotEmpty && event.parse(v) == null
                                ? 'Enter a valid target in the selected unit.'
                                : null),
                  ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(
                        context,
                        TestEvent(
                            id: event.id,
                            name: event.name,
                            instructions: event.instructions,
                            metric: metric,
                            higherWins: higher,
                            target: target.text.trim().isEmpty
                                ? null
                                : event.parse(target.text)));
                  }
                },
                child: const Text('Save exercise'))
          ]);
}

class ChallengeDetail extends StatefulWidget {
  final FitnessChallenge challenge;
  const ChallengeDetail({super.key, required this.challenge});
  @override
  State<ChallengeDetail> createState() => _ChallengeDetailState();
}

class _ChallengeDetailState extends State<ChallengeDetail> {
  String division = 'As prescribed';
  String? message;
  bool loading = false;
  OfflineStore get store => OfflineStore.instance;
  ChallengeRepository get repo => ChallengeRepository(store);
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!store.signedIn) return;
    setState(() => loading = true);
    try {
      await store.sync();
      await repo.leaderboard(widget.challenge);
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Showing saved results. Shared rankings update when connected.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final challenge = widget.challenge;
        final own = repo.isOwner(challenge);
        final joined = repo.joined(challenge.id);
        final local = repo.results(challenge.id);
        final deleted = store.keys
            .where((key) =>
                key.startsWith('challenge_result.${challenge.id}.') &&
                store.get(key) == null)
            .map((key) => key.split('.').last)
            .toSet();
        final merged = <String, ChallengeResult>{
          for (final r in repo.cachedBoard(challenge.id).where(
              (r) => r.userId != store.user?['id'] || !deleted.contains(r.id)))
            '${r.userId}:${r.id}': r
        };
        for (final r in local) {
          merged['${store.user?['id'] ?? 'this-device'}:${r.id}'] =
              ChallengeResult.fromJson({
            ...r.toJson(),
            'userId': store.user?['id'] ?? 'this-device',
            'username': store.user?['username'] ?? 'You'
          });
        }
        final history = local.toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return Scaffold(
            appBar: AppBar(title: Text(challenge.title), actions: [
              IconButton(
                  tooltip: 'Refresh results',
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh))
            ]),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                  '${challenge.category} · ${challenge.startDate} to ${challenge.endDate}'),
              Text(challenge.visibility == 'private'
                  ? 'Private challenge'
                  : 'Shared with creator’s followers · self-reported results'),
              if (challenge.instructions.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(challenge.instructions)),
              for (final event in challenge.events)
                Card(
                    child: ListTile(
                        title: Text(event.name),
                        subtitle: Text([
                          event.instructions,
                          '${event.metric.label} · ${event.higherWins ? 'Higher' : 'Lower'} wins',
                          if (event.target != null)
                            'Pass target: ${event.format(event.target!)}',
                        ].where((s) => s.isNotEmpty).join('\n')))),
              if (!own)
                OutlinedButton(
                    onPressed: () async {
                      try {
                        await repo.join(challenge.id, !joined);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Could not save participation. Please retry.')));
                        }
                      }
                    },
                    child: Text(joined ? 'Leave challenge' : 'Join challenge')),
              FilledButton.icon(
                  onPressed: own || joined
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  LogChallengeResult(challenge: challenge)))
                      : null,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Log test result')),
              if (loading) const LinearProgressIndicator(),
              if (message != null) Text(message!),
              const SizedBox(height: 20),
              Text('Results by exercise',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'Best completed result per person. As-prescribed and scaled attempts are ranked separately.'),
              DropdownButton<String>(
                  value: division,
                  isExpanded: true,
                  items: ['As prescribed', 'Scaled']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (value) => setState(() => division = value!)),
              for (final event in challenge.events) ...[
                Text(event.name,
                    style: Theme.of(context).textTheme.titleMedium),
                if (rankResults(merged.values.toList(), event, division)
                    .isEmpty)
                  const Text('No completed results in this division yet.'),
                ..._ranking(event,
                    rankResults(merged.values.toList(), event, division)),
              ],
              const SizedBox(height: 20),
              Text('My attempts',
                  style: Theme.of(context).textTheme.titleLarge),
              if (history.isEmpty)
                const Text(
                    'Log your first test, including partial tests or an unfinished workout.'),
              for (final result in history)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        '${result.date} · ${result.division}${result.completed ? '' : ' · Did not finish'}')),
                                IconButton(
                                    tooltip: 'Delete attempt',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final remove = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                                  title: const Text(
                                                      'Delete this attempt?'),
                                                  content: const Text(
                                                      'It will also be removed from shared rankings when connected.'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, false),
                                                        child: const Text(
                                                            'Cancel')),
                                                    FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child: const Text(
                                                            'Delete'))
                                                  ]));
                                      if (remove == true) {
                                        await store.remove(
                                            'challenge_result.${challenge.id}.${result.id}');
                                      }
                                    }),
                              ]),
                              for (final event in challenge.events.where(
                                  (e) => result.scores.containsKey(e.id)))
                                Text(
                                    '${event.name}: ${event.format(result.scores[event.id]!)}${event.target == null ? '' : event.passes(result.scores[event.id]!)! ? ' · Target met' : ' · Target not met'}'),
                              if (result.notes.isNotEmpty) Text(result.notes),
                            ]))),
            ]));
      });
  List<Widget> _ranking(TestEvent event, List<ChallengeResult> ranked) {
    var rank = 0;
    double? previous;
    final rows = <Widget>[];
    for (var i = 0; i < ranked.length; i++) {
      final result = ranked[i];
      final score = result.scores[event.id]!;
      if (score != previous) rank = i + 1;
      previous = score;
      rows.add(ListTile(
          leading: Text('$rank'),
          title: Text(result.username ?? 'You'),
          subtitle: Text(result.date),
          trailing: Text(event.format(score))));
    }
    return rows;
  }
}

class LogChallengeResult extends StatefulWidget {
  final FitnessChallenge challenge;
  const LogChallengeResult({super.key, required this.challenge});
  @override
  State<LogChallengeResult> createState() => _LogChallengeResultState();
}

class _LogChallengeResultState extends State<LogChallengeResult> {
  final form = GlobalKey<FormState>();
  late final scores = {
    for (final e in widget.challenge.events) e.id: TextEditingController()
  };
  final notes = TextEditingController();
  String division = 'As prescribed';
  bool completed = true, saving = false;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  String? error;
  @override
  void dispose() {
    for (final controller in scores.values) {
      controller.dispose();
    }
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || saving) return;
    final challenge = widget.challenge;
    final values = <String, double>{};
    for (final event in challenge.events) {
      if (scores[event.id]!.text.trim().isNotEmpty) {
        values[event.id] = event.parse(scores[event.id]!.text)!;
      }
    }
    if (!challenge.acceptsDate(_day(date))) {
      setState(() => error = 'Choose a date inside this challenge’s dates.');
      return;
    }
    if (completed && values.isEmpty) {
      setState(() => error = 'Enter at least one exercise result.');
      return;
    }
    if (!completed && notes.text.trim().isEmpty) {
      setState(() => error = 'Describe the work completed in your notes.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ChallengeRepository(await OfflineStore.getInstance()).record(
          ChallengeResult(
              id: operationId(),
              challengeId: challenge.id,
              date: _day(date),
              division: division,
              notes: notes.text.trim(),
              scores: values,
              completed: completed));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Could not save result on this device. Please retry.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Log test result')),
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(widget.challenge.title,
                style: Theme.of(context).textTheme.titleLarge),
            const Text(
                'Leave untested exercises blank. Time accepts mm:ss or whole seconds. Record one attempt at a time.'),
            OutlinedButton(
                onPressed: () async {
                  final challenge = widget.challenge;
                  final first = DateTime.parse(challenge.startDate),
                      last = DateTime.parse(challenge.endDate);
                  final initial = date.isBefore(first)
                      ? first
                      : date.isAfter(last)
                          ? last
                          : date;
                  final chosen = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: first,
                      lastDate: last);
                  if (chosen != null && mounted) setState(() => date = chosen);
                },
                child: Text('Test date: ${_day(date)}')),
            DropdownButtonFormField<String>(
                initialValue: division,
                decoration: const InputDecoration(labelText: 'Division'),
                items: ['As prescribed', 'Scaled']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) => setState(() => division = value!)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Completed the workout / tested events'),
                subtitle: const Text(
                    'Turn off for an unfinished attempt. It stays in history but is not ranked.'),
                value: completed,
                onChanged: (value) => setState(() => completed = value)),
            for (final event in widget.challenge.events)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextFormField(
                      controller: scores[event.id],
                      decoration: InputDecoration(
                          labelText: event.name,
                          helperText: event.metric.label),
                      validator: (value) => value!.trim().isNotEmpty &&
                              event.parse(value) == null
                          ? 'Enter a valid ${event.metric.label.toLowerCase()} result.'
                          : null)),
            TextFormField(
                controller: notes,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Notes, loads and scaling')),
            if (widget.challenge.visibility == 'followers')
              const Text(
                  'Synced results are visible to the creator and followers of this challenge. Only log what you want to share.'),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save result')),
          ])));
}
