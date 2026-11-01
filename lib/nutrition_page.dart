import 'package:flutter/material.dart';
import 'nutrition_log.dart';
import 'offline_store.dart';

class DailyNutritionPage extends StatefulWidget {
  final List<ActivityCalorieCredit> Function() activityCredits;
  const DailyNutritionPage({super.key, required this.activityCredits});
  @override
  State<DailyNutritionPage> createState() => _DailyNutritionPageState();
}

class _DailyNutritionPageState extends State<DailyNutritionPage> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  OfflineStore get store => OfflineStore.instance;
  NutritionRepository get repo => NutritionRepository(store);
  String? message;
  @override
  void initState() {
    super.initState();
    OfflineStore.getInstance().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> edit({NutritionEntry? entry, String kind = 'food'}) async {
    final saved = await showDialog<NutritionEntry>(
        context: context,
        builder: (_) => NutritionEntryEditor(
            entry: entry, initialDate: selected, kind: kind));
    if (saved != null && mounted) {
      setState(() {
        selected = DateTime.parse(saved.date!);
        message = 'Entry saved. Changes sync when connected.';
      });
    }
  }

  Future<void> chooseDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: selected,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() => selected = picked);
  }

  Widget entryTile(NutritionEntry entry) => Card(
      child: ListTile(
          leading: Icon(entry.kind == 'drink'
              ? Icons.local_drink_outlined
              : Icons.restaurant_outlined),
          title: Text(entry.name),
          subtitle: Text(
              '${entry.calories} kcal${entry.portion.isEmpty ? '' : ' · ${entry.portion}'}\n${entry.undated ? 'Date not recorded — tap to assign' : '${entry.date} ${entry.time}'}'),
          isThreeLine: true,
          onTap: () => edit(entry: entry),
          trailing: IconButton(
              tooltip: 'Delete ${entry.name}',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await repo.remove(entry);
                } catch (_) {
                  if (mounted) {
                    setState(() =>
                        message = 'Could not remove this entry. Please retry.');
                  }
                }
              })));
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final date = nutritionDate(selected);
        final totals = repo.totals(date, widget.activityCredits());
        final entries = repo.forDay(date);
        final undated = repo.entries.where((e) => e.undated).toList();
        final goals = {1600, 1800, 2000, 2200, 2400, 2800, totals.baseGoal}
            .toList()
          ..sort();
        Widget stat(String label, int value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(label)),
              Text('$value kcal',
                  style: const TextStyle(fontWeight: FontWeight.w600))
            ]));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Daily nutrition',
              style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            IconButton(
                tooltip: 'Previous date',
                onPressed: () => setState(() =>
                    selected = selected.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: chooseDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(date))),
            IconButton(
                tooltip: 'Next date',
                onPressed: () => setState(
                    () => selected = selected.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right)),
            TextButton(
                onPressed: () => setState(
                    () => selected = DateUtils.dateOnly(DateTime.now())),
                child: const Text('Today')),
          ]),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        stat('Base goal', totals.baseGoal),
                        stat('Activity credit (estimated)',
                            totals.exerciseCredit),
                        const Divider(),
                        stat('Daily allowance', totals.allowance),
                        stat('Food & drinks consumed', totals.consumed),
                        const SizedBox(height: 8),
                        Text(
                            totals.remaining >= 0
                                ? '${totals.remaining} kcal remaining'
                                : '${totals.remaining.abs()} kcal over allowance',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                            value: (totals.consumed / totals.allowance)
                                .clamp(0, 1)
                                .toDouble()),
                        const SizedBox(height: 10),
                        Text(
                            'Base goal + activity credit − food and drinks = remaining. Only logged activities on $date count; steps are not added again.',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                            key: ValueKey('$date:${totals.baseGoal}'),
                            initialValue: totals.baseGoal,
                            decoration: const InputDecoration(
                                labelText: 'Base goal for selected date'),
                            items: goals
                                .map((g) => DropdownMenuItem(
                                    value: g, child: Text('$g kcal')))
                                .toList(),
                            onChanged: (value) async {
                              if (value != null) {
                                try {
                                  await repo.setGoal(date, value);
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => message =
                                        'Could not save the goal. Please retry.');
                                  }
                                }
                              }
                            }),
                      ]))),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: () => edit(kind: 'food'),
                icon: const Icon(Icons.restaurant),
                label: const Text('Log food')),
            OutlinedButton.icon(
                onPressed: () => edit(kind: 'drink'),
                icon: const Icon(Icons.local_drink),
                label: const Text('Log drink')),
          ]),
          if (message != null) Text(message!),
          const SizedBox(height: 20),
          Text('Log for $date', style: Theme.of(context).textTheme.titleMedium),
          if (entries.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    'Nothing logged for this date. Record what you ate or drank.')),
          ...entries.map(entryTile),
          if (undated.isNotEmpty)
            ExpansionTile(
                title: Text('${undated.length} older entries need a date'),
                subtitle: const Text(
                    'Preserved from the old log. Not counted until you assign a date and time.'),
                children: undated.map(entryTile).toList()),
        ]);
      });
}

class NutritionEntryEditor extends StatefulWidget {
  final NutritionEntry? entry;
  final DateTime initialDate;
  final String kind;
  const NutritionEntryEditor(
      {super.key, this.entry, required this.initialDate, this.kind = 'food'});
  @override
  State<NutritionEntryEditor> createState() => _NutritionEntryEditorState();
}

class _NutritionEntryEditorState extends State<NutritionEntryEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.entry?.name ?? '');
  late final portion = TextEditingController(text: widget.entry?.portion ?? '');
  late final calories =
      TextEditingController(text: widget.entry?.calories.toString() ?? '');
  late String kind = widget.entry?.kind ?? widget.kind;
  late DateTime date = widget.entry?.date == null
      ? widget.initialDate
      : DateTime.parse(widget.entry!.date!);
  late TimeOfDay time = widget.entry?.time == null
      ? TimeOfDay.now()
      : TimeOfDay(
          hour: int.parse(widget.entry!.time!.split(':')[0]),
          minute: int.parse(widget.entry!.time!.split(':')[1]));
  late final String scope;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    scope = OfflineStore.instance.scope;
  }

  @override
  void dispose() {
    name.dispose();
    portion.dispose();
    calories.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final entry = NutritionEntry(
          id: widget.entry?.id ?? operationId(),
          name: name.text.trim(),
          kind: kind,
          calories: int.parse(calories.text.trim()),
          portion: portion.text.trim(),
          date: nutritionDate(date),
          time:
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          legacy: widget.entry?.legacy ?? false);
      await NutritionRepository(await OfflineStore.getInstance())
          .save(entry, expectedScope: scope);
      if (mounted) Navigator.pop(context, entry);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save on this device. Please retry.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.entry == null
              ? 'Log ${kind == 'food' ? 'food' : 'drink'}'
              : 'Edit food or drink'),
          content: SizedBox(
              width: 440,
              child: Form(
                  key: form,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                        initialValue: kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'food', child: Text('Food')),
                          DropdownMenuItem(value: 'drink', child: Text('Drink'))
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() => kind = value!)),
                    TextFormField(
                        controller: name,
                        maxLength: 120,
                        decoration: const InputDecoration(
                            labelText: 'What did you eat or drink?'),
                        validator: (value) => value!.trim().isEmpty
                            ? 'Enter the food or drink.'
                            : null),
                    TextFormField(
                        controller: portion,
                        maxLength: 120,
                        decoration: const InputDecoration(
                            labelText: 'Portion / amount (optional)',
                            hintText: '2 slices, 250 ml, 1 bowl')),
                    TextFormField(
                        controller: calories,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Calories (kcal)',
                            helperText:
                                'For the whole portion. Enter 0 for a zero-calorie item.'),
                        validator: (value) {
                          final n = int.tryParse(value!.trim());
                          return n == null || n < 0 || n > 100000
                              ? 'Enter a whole number from 0 to 100000.'
                              : null;
                        }),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                    context: context,
                                    initialDate: date,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100));
                                if (picked != null && mounted) {
                                  setState(() => date = picked);
                                }
                              },
                        icon: const Icon(Icons.calendar_today),
                        label: Text('Date: ${nutritionDate(date)}')),
                    OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                    context: context, initialTime: time);
                                if (picked != null && mounted) {
                                  setState(() => time = picked);
                                }
                              },
                        icon: const Icon(Icons.schedule),
                        label: Text(
                            'Time: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')),
                    if (error != null) Text(error!),
                  ])))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save entry'))
          ]);
}
