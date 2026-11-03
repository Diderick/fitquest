import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'offline_store.dart';

String nutritionDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String nutritionTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class NutritionEntry {
  final String id, name, kind, portion;
  final int calories;
  final double servings;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String? date, time;
  final bool legacy;
  const NutritionEntry(
      {required this.id,
      required this.name,
      required this.kind,
      required this.calories,
      this.date,
      this.time,
      this.portion = '',
      this.servings = 1,
      this.proteinG = 0,
      this.carbsG = 0,
      this.fatG = 0,
      this.legacy = false});
  bool get undated => date == null;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'calories': calories,
        'date': date,
        'time': time,
        'portion': portion,
        'servings': servings,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'legacy': legacy
      };
  factory NutritionEntry.fromJson(Map<String, dynamic> json) => NutritionEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: json['kind'] as String,
      calories: json['calories'] as int,
      date: json['date'] as String?,
      time: json['time'] as String?,
      portion: json['portion'] as String? ?? '',
      servings: (json['servings'] as num?)?.toDouble() ?? 1,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      legacy: json['legacy'] == true);
}

class ActivityCalorieCredit {
  final DateTime date;
  final int calories;
  const ActivityCalorieCredit(this.date, this.calories);
}

class NutritionTotals {
  final int baseGoal, consumed, exerciseCredit;
  const NutritionTotals(this.baseGoal, this.consumed, this.exerciseCredit);
  int get allowance => baseGoal + exerciseCredit;
  int get remaining => allowance - consumed;
  int get netIntake => consumed - exerciseCredit;
}

class NutritionRepository {
  final OfflineStore store;
  NutritionRepository(this.store);
  List<NutritionEntry> get entries {
    final keys = store.keys.toSet();
    final result = <NutritionEntry>[];
    for (final key in keys.where((key) => key.startsWith('nutrition_entry.'))) {
      final raw = store.getString(key);
      if (raw != null) {
        result.add(
            NutritionEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      }
    }
    final old = store.getString('nutrition_entries_v1');
    if (old != null) {
      final rows = jsonDecode(old) as List;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] as Map;
        final name = row['meal'] as String;
        final calories = row['calories'] as int;
        final id = 'legacy-${sha256.convert(utf8.encode(jsonEncode([
                  i,
                  name,
                  calories
                ]))).toString().substring(0, 32)}';
        if (!keys.contains('nutrition_entry.$id')) {
          result.add(NutritionEntry(
              id: id,
              name: name,
              kind: 'food',
              calories: calories,
              legacy: true));
        }
      }
    }
    return result;
  }

  List<NutritionEntry> forDay(String date) =>
      entries.where((e) => e.date == date).toList()
        ..sort((a, b) => (b.time ?? '').compareTo(a.time ?? ''));
  int goal(String date) =>
      store.getInt('nutrition_goal.$date') ??
      store.getInt('nutrition_goal_kcal') ??
      2200;
  NutritionTotals totals(String date, List<ActivityCalorieCredit> activities) =>
      NutritionTotals(
          goal(date),
          forDay(date).fold(0, (sum, e) => sum + e.calories),
          activities
              .where((a) => nutritionDate(a.date.toLocal()) == date)
              .fold(0, (sum, a) => sum + a.calories.clamp(0, 1000000)));
  Future<void> save(NutritionEntry entry, {String? expectedScope}) async {
    final changes = <String, Object?>{
      'nutrition_entry.${entry.id}': jsonEncode(entry.toJson())
    };
    if (entry.date != null &&
        store.getInt('nutrition_goal.${entry.date}') == null) {
      changes['nutrition_goal.${entry.date}'] = goal(entry.date!);
    }
    await store.putAll(changes, expectedScope: expectedScope);
  }

  Future<void> remove(NutritionEntry entry) async {
    await store.remove('nutrition_entry.${entry.id}');
  }

  Future<void> setGoal(String date, int calories) async {
    await store.setInt('nutrition_goal.$date', calories);
  }
}
