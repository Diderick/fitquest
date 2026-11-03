import 'package:flutter/material.dart';
import 'nutrition_log.dart';
import 'offline_store.dart';

class _FoodPreset {
  final String name;
  final String portion;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String kind;
  const _FoodPreset(this.name, this.portion, this.calories,
      {this.proteinG = 0, this.carbsG = 0, this.fatG = 0, this.kind = 'food'});
}

const _foodPresets = <_FoodPreset>[
  _FoodPreset('Egg', '1 large', 78, proteinG: 6.3, carbsG: 0.6, fatG: 5.3),
  _FoodPreset('Boiled egg', '2 large', 156,
      proteinG: 12.6, carbsG: 1.2, fatG: 10.6),
  _FoodPreset('Brown bread', '1 slice (about 35 g)', 82,
      proteinG: 3.6, carbsG: 13.8, fatG: 1.2),
  _FoodPreset('White bread', '1 slice (about 30 g)', 80,
      proteinG: 2.7, carbsG: 14.7, fatG: 1.0),
  _FoodPreset('Banana', '1 medium', 105,
      proteinG: 1.3, carbsG: 27.0, fatG: 0.4),
  _FoodPreset('Apple', '1 medium', 95, proteinG: 0.5, carbsG: 25.1, fatG: 0.3),
  _FoodPreset('Chicken breast', '100 g cooked', 165,
      proteinG: 31.0, carbsG: 0.0, fatG: 3.6),
  _FoodPreset('Rice', '1 cup cooked', 206,
      proteinG: 4.3, carbsG: 45.0, fatG: 0.4),
  _FoodPreset('Oats', '40 g dry', 156, proteinG: 6.8, carbsG: 26.5, fatG: 2.8),
  _FoodPreset('Peanut butter', '1 tablespoon', 95,
      proteinG: 3.5, carbsG: 3.5, fatG: 8.0),
  _FoodPreset('Milk', '250 ml', 155,
      proteinG: 8.0, carbsG: 12.0, fatG: 8.4, kind: 'drink'),
  _FoodPreset('Greek yogurt', '170 g tub', 120,
      proteinG: 17.0, carbsG: 6.0, fatG: 1.0),
  _FoodPreset('Soda', '330 ml can', 139,
      proteinG: 0.0, carbsG: 35.0, fatG: 0.0, kind: 'drink'),
  _FoodPreset('Coffee (black)', '250 ml', 2,
      proteinG: 0.3, carbsG: 0.0, fatG: 0.0, kind: 'drink'),
  _FoodPreset('Protein shake', '1 scoop in water', 120,
      proteinG: 24.0, carbsG: 3.0, fatG: 1.5, kind: 'drink'),
];

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

  Future<void> _quickRelog(NutritionEntry source) async {
    final now = DateTime.now();
    try {
      await repo.save(NutritionEntry(
          id: operationId(),
          name: source.name,
          kind: source.kind,
          calories: source.calories,
          portion: source.portion,
          servings: source.servings,
          proteinG: source.proteinG,
          carbsG: source.carbsG,
          fatG: source.fatG,
          date: nutritionDate(selected),
          time: nutritionTime(now)));
      if (mounted) {
        setState(() =>
            message = '${source.name} added to ${nutritionDate(selected)}.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            message = 'Could not add quick item right now. Please retry.');
      }
    }
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
        final proteinTotal =
            entries.fold<double>(0, (sum, e) => sum + e.proteinG);
        final carbsTotal = entries.fold<double>(0, (sum, e) => sum + e.carbsG);
        final fatTotal = entries.fold<double>(0, (sum, e) => sum + e.fatG);
        final undated = repo.entries.where((e) => e.undated).toList();
        final recentTemplates = <NutritionEntry>[];
        final seenTemplateKeys = <String>{};
        for (final entry in repo.entries.where((e) => !e.undated)) {
          final key =
              '${entry.kind}:${entry.name}:${entry.portion}:${entry.calories}:${entry.servings}';
          if (seenTemplateKeys.add(key)) {
            recentTemplates.add(entry);
          }
          if (recentTemplates.length == 6) break;
        }
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
                        stat('Base target', totals.baseGoal),
                        stat(
                            'Workout credit (estimate)', totals.exerciseCredit),
                        const Divider(),
                        stat('Available today', totals.allowance),
                        stat('Food and drinks logged', totals.consumed),
                        const SizedBox(height: 8),
                        Text(
                            'Macros: P ${proteinTotal.toStringAsFixed(1)} g · C ${carbsTotal.toStringAsFixed(1)} g · F ${fatTotal.toStringAsFixed(1)} g',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Text(
                            totals.remaining >= 0
                                ? '${totals.remaining} kcal remaining'
                                : '${totals.remaining.abs()} kcal over allowance',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (totals.remaining < 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: .35)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You are ${totals.remaining.abs()} kcal over your current allowance. Consider adjusting portions or adding activity.',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                            value: (totals.consumed / totals.allowance)
                                .clamp(0, 1)
                                .toDouble()),
                        const SizedBox(height: 10),
                        Text(
                            'Available = base target + workout credit. Remaining = available − logged calories. Credit is estimated from workouts logged on this date; steps are not added.',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                            key: ValueKey('$date:${totals.baseGoal}'),
                            initialValue: totals.baseGoal,
                            decoration: const InputDecoration(
                                labelText: 'Base target for this date',
                                helperText:
                                    'Tracking setting, not a personalized recommendation.'),
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
          if (recentTemplates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Quick re-log',
                    style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in recentTemplates)
                  ActionChip(
                      avatar: Icon(
                          item.kind == 'drink'
                              ? Icons.local_drink_outlined
                              : Icons.restaurant_outlined,
                          size: 18),
                      label: Text('${item.name} (${item.calories} kcal)'),
                      onPressed: () => _quickRelog(item)),
              ],
            ),
          ],
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
  late final servings = TextEditingController(
      text: (widget.entry?.servings ?? 1).toStringAsFixed(1));
  late final calories =
      TextEditingController(text: widget.entry?.calories.toString() ?? '');
  late final proteinG = TextEditingController(
      text: (widget.entry?.proteinG ?? 0).toStringAsFixed(1));
  late final carbsG = TextEditingController(
      text: (widget.entry?.carbsG ?? 0).toStringAsFixed(1));
  late final fatG =
      TextEditingController(text: (widget.entry?.fatG ?? 0).toStringAsFixed(1));
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
  String? selectedPreset;
  bool saving = false;
  String? error;

  String _fmtValue(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  _FoodPreset? get _preset {
    final index = int.tryParse(selectedPreset ?? '');
    if (index == null || index < 0 || index >= _foodPresets.length) {
      return null;
    }
    return _foodPresets[index];
  }

  void _applyPresetNutrition({bool updateAll = false}) {
    final preset = _preset;
    if (preset == null) return;
    final servingCount =
        (double.tryParse(servings.text.trim().replaceAll(',', '.')) ?? 1)
            .clamp(0.1, 100.0);
    if (updateAll) {
      name.text = preset.name;
      portion.text = preset.portion;
      kind = preset.kind;
    }
    calories.text = (preset.calories * servingCount).round().toString();
    proteinG.text = _fmtValue(preset.proteinG * servingCount);
    carbsG.text = _fmtValue(preset.carbsG * servingCount);
    fatG.text = _fmtValue(preset.fatG * servingCount);
  }

  void _applyPreset(String presetValue) {
    final index = int.tryParse(presetValue);
    if (index == null || index < 0 || index >= _foodPresets.length) return;
    setState(() {
      selectedPreset = presetValue;
      if (servings.text.trim().isEmpty) {
        servings.text = '1.0';
      }
      _applyPresetNutrition(updateAll: true);
      error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    scope = OfflineStore.instance.scope;
  }

  @override
  void dispose() {
    name.dispose();
    portion.dispose();
    servings.dispose();
    calories.dispose();
    proteinG.dispose();
    carbsG.dispose();
    fatG.dispose();
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
          servings: double.parse(servings.text.trim().replaceAll(',', '.')),
          proteinG: double.parse(proteinG.text.trim().replaceAll(',', '.')),
          carbsG: double.parse(carbsG.text.trim().replaceAll(',', '.')),
          fatG: double.parse(fatG.text.trim().replaceAll(',', '.')),
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
                        key: ValueKey('nutrition-kind:$kind'),
                        initialValue: kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'food', child: Text('Food')),
                          DropdownMenuItem(value: 'drink', child: Text('Drink'))
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() {
                                  kind = value!;
                                  selectedPreset = null;
                                })),
                    DropdownButtonFormField<String>(
                        initialValue: selectedPreset,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration: const InputDecoration(
                            labelText: 'Start with a preset (optional)'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('Select item')),
                          for (var i = 0; i < _foodPresets.length; i++)
                            if (_foodPresets[i].kind == kind)
                              DropdownMenuItem<String>(
                                  value: '$i',
                                  child: Text(_foodPresets[i].name,
                                      overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  _applyPreset(value);
                                }
                              }),
                    if (selectedPreset != null)
                      TextFormField(
                          controller: servings,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Preset servings',
                              helperText:
                                  'Calories and macros update to this total.'),
                          onChanged: (_) {
                            if (_preset != null) {
                              setState(() => _applyPresetNutrition());
                            }
                          },
                          validator: (value) {
                            final n = double.tryParse(
                                value!.trim().replaceAll(',', '.'));
                            return n == null || n < 0.1 || n > 100
                                ? 'Enter a number from 0.1 to 100.'
                                : null;
                          }),
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
                                'Total for this entry. Use 0 if needed.'),
                        validator: (value) {
                          final n = int.tryParse(value!.trim());
                          return n == null || n < 0 || n > 10000
                              ? 'Enter a whole number from 0 to 10000.'
                              : null;
                        }),
                    const SizedBox(height: 8),
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: const Text('Macros (optional)'),
                        subtitle: const Text('Totals for this entry, in grams'),
                        children: [
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                  controller: proteinG,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Protein (g)'),
                                  validator: (value) {
                                    final n = double.tryParse(
                                        value!.trim().replaceAll(',', '.'));
                                    return n == null || n < 0 || n > 1000
                                        ? 'Enter 0–1000 g.'
                                        : null;
                                  }),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                  controller: carbsG,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Carbs (g)'),
                                  validator: (value) {
                                    final n = double.tryParse(
                                        value!.trim().replaceAll(',', '.'));
                                    return n == null || n < 0 || n > 1000
                                        ? 'Enter 0–1000 g.'
                                        : null;
                                  }),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                  controller: fatG,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Fat (g)'),
                                  validator: (value) {
                                    final n = double.tryParse(
                                        value!.trim().replaceAll(',', '.'));
                                    return n == null || n < 0 || n > 1000
                                        ? 'Enter 0–1000 g.'
                                        : null;
                                  }),
                            ),
                          ]),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
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
                child: Text(saving ? 'Saving...' : 'Save entry'))
          ]);
}
