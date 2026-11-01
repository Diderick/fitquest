import 'dart:convert';
import 'offline_store.dart';

enum ChallengeMetric {
  reps('Repetitions'),
  seconds('Time (mm:ss)'),
  metres('Distance (metres)'),
  kilograms('Load (kg)'),
  rounds('Rounds');

  final String label;
  const ChallengeMetric(this.label);
}

class TestEvent {
  final String id, name, instructions;
  final ChallengeMetric metric;
  final bool higherWins;
  final double? target;
  const TestEvent(
      {required this.id,
      required this.name,
      this.instructions = '',
      required this.metric,
      required this.higherWins,
      this.target});
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'instructions': instructions,
        'metric': metric.name,
        'higherWins': higherWins,
        'target': target
      };
  factory TestEvent.fromJson(Map<String, dynamic> json) => TestEvent(
      id: json['id'] as String,
      name: json['name'] as String,
      instructions: json['instructions'] as String? ?? '',
      metric: ChallengeMetric.values.byName(json['metric'] as String),
      higherWins: json['higherWins'] as bool,
      target: (json['target'] as num?)?.toDouble());
  bool? passes(double value) => target == null
      ? null
      : higherWins
          ? value >= target!
          : value <= target!;
  String format(double value) => metric == ChallengeMetric.seconds
      ? '${value ~/ 60}:${(value.round() % 60).toString().padLeft(2, '0')}'
      : '${value == value.roundToDouble() ? value.toInt() : value} ${switch (metric) {
          ChallengeMetric.reps => 'reps',
          ChallengeMetric.metres => 'm',
          ChallengeMetric.kilograms => 'kg',
          ChallengeMetric.rounds => 'rounds',
          _ => '',
        }}';
  double? parse(String input) {
    final text = input.trim().replaceAll(',', '.');
    if (metric == ChallengeMetric.seconds && text.contains(':')) {
      final parts = text.split(':');
      if (parts.length != 2 ||
          !RegExp(r'^\d+$').hasMatch(parts[0]) ||
          !RegExp(r'^\d{1,2}$').hasMatch(parts[1])) {
        return null;
      }
      final seconds = int.parse(parts[1]);
      final minutes = int.tryParse(parts[0]);
      if (seconds >= 60 || minutes == null || minutes > 16666) return null;
      return _valid((minutes * 60 + seconds).toDouble());
    }
    return _valid(double.tryParse(text));
  }

  double? _valid(double? value) {
    if (value == null || !value.isFinite || value < 0 || value > 1000000) {
      return null;
    }
    if (metric == ChallengeMetric.seconds && value <= 0) return null;
    if ([ChallengeMetric.reps, ChallengeMetric.rounds, ChallengeMetric.seconds]
            .contains(metric) &&
        value != value.roundToDouble()) {
      return null;
    }
    return value;
  }
}

class FitnessChallenge {
  final String id,
      title,
      category,
      instructions,
      startDate,
      endDate,
      visibility;
  final List<TestEvent> events;
  final String? ownerId, ownerName;
  const FitnessChallenge(
      {required this.id,
      required this.title,
      required this.category,
      required this.instructions,
      required this.startDate,
      required this.endDate,
      required this.visibility,
      required this.events,
      this.ownerId,
      this.ownerName});
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'instructions': instructions,
        'startDate': startDate,
        'endDate': endDate,
        'visibility': visibility,
        'events': events.map((e) => e.toJson()).toList()
      };
  factory FitnessChallenge.fromJson(Map<String, dynamic> json) =>
      FitnessChallenge(
          id: json['id'] as String,
          title: json['title'] as String,
          category: json['category'] as String,
          instructions: json['instructions'] as String,
          startDate: json['startDate'] as String,
          endDate: json['endDate'] as String,
          visibility: json['visibility'] as String,
          events: (json['events'] as List)
              .map((e) =>
                  TestEvent.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
          ownerId: json['ownerId'] as String?,
          ownerName: json['ownerName'] as String?);
  bool acceptsDate(String date) =>
      date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0;
}

class ChallengeResult {
  final String id, challengeId, date, division, notes;
  final Map<String, double> scores;
  final String? userId, username;
  final bool completed;
  const ChallengeResult(
      {required this.id,
      required this.challengeId,
      required this.date,
      required this.division,
      required this.notes,
      required this.scores,
      this.userId,
      this.username,
      this.completed = true});
  Map<String, dynamic> toJson() => {
        'id': id,
        'challengeId': challengeId,
        'date': date,
        'division': division,
        'notes': notes,
        'scores': scores,
        'completed': completed
      };
  factory ChallengeResult.fromJson(Map<String, dynamic> json) =>
      ChallengeResult(
          id: json['id'] as String,
          challengeId: json['challengeId'] as String,
          date: json['date'] as String,
          division: json['division'] as String,
          notes: json['notes'] as String? ?? '',
          scores: (json['scores'] as Map).map((key, value) =>
              MapEntry(key as String, (value as num).toDouble())),
          userId: json['userId'] as String?,
          username: json['username'] as String?,
          completed: json['completed'] as bool? ?? true);
}

/// One best result per participant, event and division; never adds unlike units.
List<ChallengeResult> rankResults(
    List<ChallengeResult> results, TestEvent event, String division) {
  final best = <String, ChallengeResult>{};
  for (final result in results.where((r) =>
      r.completed &&
      r.division == division &&
      r.scores.containsKey(event.id))) {
    final id = result.userId ?? 'this-device';
    final previous = best[id];
    if (previous == null ||
        (event.higherWins
            ? result.scores[event.id]! > previous.scores[event.id]!
            : result.scores[event.id]! < previous.scores[event.id]!)) {
      best[id] = result;
    }
  }
  return best.values.toList()
    ..sort((a, b) {
      final compare = a.scores[event.id]!.compareTo(b.scores[event.id]!);
      return event.higherWins ? -compare : compare;
    });
}

class ChallengeRepository {
  final OfflineStore store;
  ChallengeRepository(this.store);
  List<FitnessChallenge> get mine => store.keys
      .where((key) => key.startsWith('challenge.'))
      .where((key) => store.getString(key) != null)
      .map((key) => FitnessChallenge.fromJson(
          jsonDecode(store.getString(key)!) as Map<String, dynamic>))
      .toList();
  List<FitnessChallenge> get discovered {
    final raw = store.getString('_challenge_discovery');
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
            .map((value) => FitnessChallenge.fromJson(
                Map<String, dynamic>.from(value as Map)))
            .toList();
  }

  bool isOwner(FitnessChallenge challenge) =>
      mine.any((c) => c.id == challenge.id);
  bool joined(String id) => store.getBool('challenge_join.$id') ?? false;
  Future<void> create(FitnessChallenge challenge) async {
    await store.setString(
        'challenge.${challenge.id}', jsonEncode(challenge.toJson()));
  }

  Future<void> setVisibility(
      FitnessChallenge challenge, String visibility) async {
    if (!isOwner(challenge) || !['private', 'followers'].contains(visibility)) {
      throw StateError('Only the creator can change sharing.');
    }
    await store.setString('challenge.${challenge.id}',
        jsonEncode({...challenge.toJson(), 'visibility': visibility}));
  }

  Future<void> join(String id, bool join) async {
    await store.setBool('challenge_join.$id', join);
  }

  List<ChallengeResult> results(String id) => store.keys
      .where((key) => key.startsWith('challenge_result.$id.'))
      .where((key) => store.getString(key) != null)
      .map((key) => ChallengeResult.fromJson(
          jsonDecode(store.getString(key)!) as Map<String, dynamic>))
      .toList();
  Future<void> record(ChallengeResult result) async {
    await store.setString('challenge_result.${result.challengeId}.${result.id}',
        jsonEncode(result.toJson()));
  }

  Future<void> refresh() async {
    if (!store.signedIn) return;
    await store.sync();
    final response = await store.request('/v2/challenges');
    await store.setString(
        '_challenge_discovery', jsonEncode(response['challenges']));
  }

  Future<List<ChallengeResult>> leaderboard(FitnessChallenge challenge) async {
    final response = await store.request('/v2/challenges/${challenge.id}');
    await store.setString(
        '_challenge_board.${challenge.id}', jsonEncode(response['results']));
    return cachedBoard(challenge.id);
  }

  List<ChallengeResult> cachedBoard(String id) {
    final raw = store.getString('_challenge_board.$id');
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
            .map((value) => ChallengeResult.fromJson(
                Map<String, dynamic>.from(value as Map)))
            .toList();
  }
}

List<TestEvent> challengeTemplate(String template) {
  TestEvent event(String name, ChallengeMetric metric, bool higher,
          String instructions) =>
      TestEvent(
          id: operationId(),
          name: name,
          metric: metric,
          higherWins: higher,
          instructions: instructions);
  return switch (template) {
    'Military-style test' => [
        event('Push-ups · 2 minutes', ChallengeMetric.reps, true,
            'Count repetitions using your chosen, consistent technique standard.'),
        event('Plank hold', ChallengeMetric.seconds, true,
            'Record the duration of an uninterrupted hold.'),
        event('2.4 km run', ChallengeMetric.seconds, false,
            'Record completion time on the same measured course.'),
      ],
    'CrossFit-style AMRAP' => [
        event('20-minute AMRAP · total reps', ChallengeMetric.reps, true,
            'Repeat 5 pull-ups, 10 push-ups and 15 air squats for 20 minutes. Count total reps, including an unfinished round. Specify scaling in result notes.')
      ],
    'CrossFit-style for time' => [
        event('21–15–9 workout', ChallengeMetric.seconds, false,
            'Complete rounds of 21, 15 and 9 thrusters and pull-ups. Set and record the load and scaling before comparing results. Log completion time only; use notes for unfinished attempts.')
      ],
    _ => [event('Exercise 1', ChallengeMetric.reps, true, '')],
  };
}
