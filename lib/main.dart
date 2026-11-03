import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import 'offline_store.dart';
import 'exercise_guide.dart';
import 'account_ui.dart';
import 'step_tracker.dart';
import 'challenge_ui.dart';
import 'activity_sharing.dart';
import 'social_auth.dart';
import 'friend_links.dart';
import 'nutrition_log.dart';
import 'nutrition_page.dart';
import 'profile_identity.dart';
import 'marketplace_page.dart';

void main() => runApp(const FitQuestApp());

// Brand colours from the FitQuest style guide.
const northstar = Color(0xFF1689F8);
const aurora = Color(0xFF20BBAE);
const midnight = Color(0xFF0B1424);
const iceWhite = Color(0xFFF5F8FC);

const _darkCard = Color(0xFF111D31);
const _darkNav = Color(0xFF0A1322);
const _flameRed = Color(0xFFFF5B4D);
const _questPurple = Color(0xFF4B2FB8);
const _questPurpleDark = Color(0xFF22174F);
const _gold = Color(0xFFFFC53D);

const pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 24);
const dailyStepGoal = 10000;

const selectableActivities = [
  'Swimming',
  'Cycling',
  'Running',
  'Walking',
  'Hiking',
  'Strength',
  'Rowing',
  'Yoga',
  'HIIT',
  'Tennis',
];

const gpsActivities = [
  'Running',
  'Cycling',
  'Walking',
  'Hiking',
  'Rowing',
];

const _gpsDraftKey = 'fitquest.gps_draft.v1';
const _sosWhatsappNumberKey = 'fitquest.sos.whatsapp_number.v1';
const _customPlaylistKey = 'fitquest.custom_playlist.v1';

class _InAppTrack {
  final String title;
  final String url;
  const _InAppTrack(this.title, this.url);
}

const _inAppPlaylist = [
  _InAppTrack('Run Mix 01',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
  _InAppTrack('Run Mix 02',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3'),
  _InAppTrack('Run Mix 03',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3'),
];

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
Color surfaceOf(BuildContext context) =>
    _isDark(context) ? _darkCard : Colors.white;
Color mutedOf(BuildContext context) =>
    _isDark(context) ? const Color(0xFF93A4BF) : const Color(0xFF5B6B84);
Color lineOf(BuildContext context) =>
    _isDark(context) ? const Color(0xFF1E2E47) : const Color(0xFFE1E8F2);

double? _positiveNumber(String raw) {
  final value = double.tryParse(raw.replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

class _WeightGuidance {
  final double? bmi;
  final String? bmiBand;
  final String rangeText;
  final String goalText;
  final String reinforcementText;
  const _WeightGuidance({
    required this.bmi,
    required this.bmiBand,
    required this.rangeText,
    required this.goalText,
    required this.reinforcementText,
  });
}

String? _bmiBand(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Healthy range';
  if (bmi < 30) return 'Overweight';
  return 'Obesity';
}

_WeightGuidance _buildWeightGuidance(
    {required double? startWeight,
    required double? currentWeight,
    required double? heightCm}) {
  final effectiveWeight = currentWeight ?? startWeight;
  final safeHeightCm = heightCm;
  double? bmi;
  String? bmiBand;
  var rangeText = 'Add your height to calculate your recommended weight range.';
  var goalText =
      'Set small weekly goals and update your weigh-in consistently.';

  if (effectiveWeight != null &&
      safeHeightCm != null &&
      safeHeightCm >= 100 &&
      safeHeightCm <= 250) {
    final heightM = safeHeightCm / 100;
    bmi = effectiveWeight / (heightM * heightM);
    bmiBand = _bmiBand(bmi);
    final healthyMin = 18.5 * heightM * heightM;
    final healthyMax = 24.9 * heightM * heightM;
    rangeText =
        'Recommended healthy range for ${safeHeightCm.toStringAsFixed(0)} cm: ${healthyMin.toStringAsFixed(1)}-${healthyMax.toStringAsFixed(1)} kg.';
    if (effectiveWeight > healthyMax) {
      final milestone = math.max(healthyMax, effectiveWeight * 0.95);
      goalText =
          'Suggested next goal: ${milestone.toStringAsFixed(1)} kg (about 5% from current), then build toward ${healthyMax.toStringAsFixed(1)} kg.';
    } else if (effectiveWeight < healthyMin) {
      goalText =
          'Suggested next goal: build gradually toward at least ${healthyMin.toStringAsFixed(1)} kg with strength and nutrition support.';
    } else {
      goalText =
          'You are inside the recommended range. Focus on maintenance and performance goals.';
    }
  }

  String reinforcementText;
  if (startWeight == null || currentWeight == null) {
    reinforcementText =
        'Great start. Log at least two weigh-ins to unlock progress reinforcement.';
  } else {
    final delta = currentWeight - startWeight;
    final percent = (startWeight - currentWeight) / startWeight * 100;
    if (delta <= -0.5) {
      final caution = percent >= 10
          ? ' Keep it steady and prioritize hydration, sleep and recovery.'
          : '';
      reinforcementText =
          'Nice progress: ${delta.abs().toStringAsFixed(1)} kg down (${percent.toStringAsFixed(1)}%). Consistency wins.$caution';
    } else if (delta < 0.5) {
      reinforcementText =
          'You are maintaining well. Stable habits now make long-term progress easier.';
    } else {
      reinforcementText =
          'Progress is not linear. Reset this week with short workouts, meal prep and daily hydration targets.';
    }
  }

  return _WeightGuidance(
    bmi: bmi,
    bmiBand: bmiBand,
    rangeText: rangeText,
    goalText: goalText,
    reinforcementText: reinforcementText,
  );
}

class Workout {
  final String activity;
  final int minutes;
  final DateTime date;
  final double? distanceKm;
  final String notes;
  final String? photoBase64;
  final bool showStartPoint;
  final bool showEndPoint;
  final List<({double latitude, double longitude})> route;
  const Workout(
    this.activity,
    this.minutes,
    this.date, {
    this.distanceKm,
    this.notes = '',
    this.photoBase64,
    this.showStartPoint = true,
    this.showEndPoint = true,
    this.route = const [],
  });
  int get xp => minutes * 5;
  int get kcal => minutes * 6;

  Map<String, Object?> toJson() => {
        'activity': activity,
        'minutes': minutes,
        'date': date.toIso8601String(),
        'distanceKm': distanceKm,
        'notes': notes,
        'photoBase64': photoBase64,
        'showStartPoint': showStartPoint,
        'showEndPoint': showEndPoint,
        'route':
            route.map((point) => [point.latitude, point.longitude]).toList(),
      };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
        json['activity'] as String,
        json['minutes'] as int,
        DateTime.parse(json['date'] as String),
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        notes: json['notes'] as String? ?? '',
        photoBase64: (json['photoBase64'] as String?)?.trim().isNotEmpty == true
            ? json['photoBase64'] as String
            : null,
        showStartPoint: json['showStartPoint'] as bool? ?? true,
        showEndPoint: json['showEndPoint'] as bool? ?? true,
        route: ((json['route'] as List?) ?? const []).map((point) {
          final coordinates = point as List;
          return (
            latitude: (coordinates[0] as num).toDouble(),
            longitude: (coordinates[1] as num).toDouble(),
          );
        }).toList(),
      );
}

Uint8List? decodeActivityPhoto(Object? raw) {
  if (raw is! String || raw.length > 2100000) return null;
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

abstract interface class ActivityRepository {
  Future<List<Workout>?> load();
  Future<void> save(List<Workout> workouts);
}

class LocalActivityRepository implements ActivityRepository {
  static const _key = 'fitquest.activities.v1';

  @override
  Future<List<Workout>?> load() async {
    final prefs = await OfflineStore.getInstance();
    final stored = prefs.getString(_key);
    if (stored == null) return null;
    final json = jsonDecode(stored) as List<dynamic>;
    return json
        .map((item) => Workout.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> save(List<Workout> workouts) async {
    final prefs = await OfflineStore.getInstance();
    final saved = await prefs.setString(
      _key,
      jsonEncode(workouts.map((workout) => workout.toJson()).toList()),
    );
    if (!saved) throw StateError('Could not save activities on this device.');
  }
}

const fitquestApiUrl = String.fromEnvironment('FITQUEST_API_URL');
const fitquestApiToken = String.fromEnvironment('FITQUEST_API_TOKEN');

/// A single-user server repository. Revision checks prevent silent overwrites.
class RemoteActivityRepository implements ActivityRepository {
  final Uri endpoint;
  final String token;
  final http.Client client;
  int? _revision;

  RemoteActivityRepository(String baseUrl, this.token, {http.Client? client})
      : endpoint = Uri.parse(
            '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/activities'),
        client = client ?? http.Client() {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty || token.isEmpty) {
      throw ArgumentError('Configure an HTTPS API URL and an API token.');
    }
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 409) {
      throw StateError(
          'Activities changed on another device. Restart the app before saving.');
    }
    if (response.statusCode != 200) {
      throw StateError('Activity server returned ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<Workout>> load() async {
    final body = _decode(await client
        .get(endpoint, headers: _headers)
        .timeout(const Duration(seconds: 20)));
    final workouts = (body['workouts'] as List)
        .map((item) => Workout.fromJson(item as Map<String, dynamic>))
        .toList();
    _revision = body['revision'] as int;
    return workouts;
  }

  @override
  Future<void> save(List<Workout> workouts) async {
    if (_revision == null) {
      throw StateError(
          'Activities have not loaded. Restart the app to reconnect.');
    }
    final body = _decode(await client
        .put(endpoint,
            headers: _headers,
            body: jsonEncode({
              'revision': _revision,
              'workouts': workouts.map((w) => w.toJson()).toList()
            }))
        .timeout(const Duration(seconds: 20)));
    _revision = body['revision'] as int;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String fmtInt(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return value < 0 ? '-$out' : '$out';
}

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

String _dayLabel(DateTime date) {
  if (_isToday(date)) return 'Today';
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  }
  return '${date.day}/${date.month}/${date.year}';
}

IconData activityIcon(String activity) => switch (activity) {
      'Swimming' => Icons.pool,
      'Cycling' => Icons.directions_bike,
      'Running' => Icons.directions_run,
      'Walking' => Icons.directions_walk,
      'Hiking' => Icons.terrain,
      'Strength' => Icons.fitness_center,
      'Rowing' => Icons.rowing,
      'Yoga' => Icons.self_improvement,
      'HIIT' => Icons.bolt,
      'Tennis' => Icons.sports_tennis,
      _ => Icons.fitness_center,
    };

DateTime _startOfWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));

int _currentStreak(List<Workout> workouts) {
  final days = workouts
      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
      .toSet();
  var cursor = DateTime.now();
  final today = DateTime(cursor.year, cursor.month, cursor.day);
  if (!days.contains(today)) cursor = today.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(DateTime(cursor.year, cursor.month, cursor.day))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

List<({double latitude, double longitude})> _privacySafeRoute(
  List<({double latitude, double longitude})> points, {
  required bool hideStart,
  required bool hideEnd,
  double bufferMeters = 250,
}) {
  if (points.length <= 2 || (!hideStart && !hideEnd)) {
    return List.of(points, growable: false);
  }

  var startIndex = 0;
  if (hideStart) {
    var covered = 0.0;
    while (startIndex < points.length - 1 && covered < bufferMeters) {
      final next = startIndex + 1;
      covered += Geolocator.distanceBetween(
        points[startIndex].latitude,
        points[startIndex].longitude,
        points[next].latitude,
        points[next].longitude,
      );
      startIndex = next;
    }
  }

  var endIndex = points.length - 1;
  if (hideEnd) {
    var covered = 0.0;
    while (endIndex > startIndex && covered < bufferMeters) {
      final previous = endIndex - 1;
      covered += Geolocator.distanceBetween(
        points[endIndex].latitude,
        points[endIndex].longitude,
        points[previous].latitude,
        points[previous].longitude,
      );
      endIndex = previous;
    }
  }

  if (endIndex - startIndex < 1) return const [];
  return points.sublist(startIndex, endIndex + 1);
}

String? workoutPace(Workout workout) {
  final distance = workout.distanceKm;
  if (distance == null || !distance.isFinite || distance <= 0) return null;
  if (workout.minutes <= 0) return null;
  if (workout.activity == 'Cycling') {
    return '${(distance * 60 / workout.minutes).toStringAsFixed(1)} km/h';
  }
  if (workout.activity != 'Running' && workout.activity != 'Walking') {
    return null;
  }
  final secondsPerKm = (workout.minutes * 60 / distance).round();
  return '${secondsPerKm ~/ 60}:${(secondsPerKm % 60).toString().padLeft(2, '0')} min/km';
}

const _xpPerLevel = 2000;
int _levelFor(int xp) => xp ~/ _xpPerLevel + 1;

// ---------------------------------------------------------------------------
// Gamification: ranks, achievements and XP
// ---------------------------------------------------------------------------

class Rank {
  final String name;
  final int minXp;
  final Color color;
  final IconData icon;
  const Rank(this.name, this.minXp, this.color, this.icon);
}

const ranks = [
  Rank('Noob', 0, Color(0xFF8E9BB0), Icons.egg_alt),
  Rank('Rookie', 500, Color(0xFF4CD08A), Icons.directions_walk),
  Rank('Amateur', 1500, northstar, Icons.directions_run),
  Rank('Pro', 3500, aurora, Icons.bolt),
  Rank('Elite', 7000, Color(0xFF9B6BFF), Icons.military_tech),
  Rank('Champion', 12000, _gold, Icons.emoji_events),
  Rank('Legend', 20000, Color(0xFFFF6B6B), Icons.workspace_premium),
];

int rankIndexFor(int xp) {
  var index = 0;
  for (var i = 0; i < ranks.length; i++) {
    if (xp >= ranks[i].minXp) index = i;
  }
  return index;
}

class Achievement {
  final String title;
  final String description;
  final IconData icon;
  final int xp;
  final int goal;
  final int Function(List<Workout>) progress;
  const Achievement(this.title, this.description, this.icon, this.xp, this.goal,
      this.progress);

  int current(List<Workout> workouts) =>
      math.min(progress(workouts), goal).toInt();
  bool earned(List<Workout> workouts) => progress(workouts) >= goal;
}

int _longestStreak(List<Workout> workouts) {
  final days = workouts
      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
      .toSet()
      .toList()
    ..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && day.difference(previous).inHours <= 36
        ? run + 1
        : 1;
    if (run > best) best = run;
    previous = day;
  }
  return best;
}

double _totalKm(List<Workout> workouts) =>
    workouts.fold<double>(0, (sum, w) => sum + (w.distanceKm ?? 0));

final achievements = <Achievement>[
  Achievement('First Steps', 'Record your first activity', Icons.flag_outlined,
      50, 1, (w) => w.length),
  Achievement('Getting Warm', 'Record 5 activities',
      Icons.local_fire_department, 100, 5, (w) => w.length),
  Achievement('Consistency Hero', 'Record 10 activities',
      Icons.event_available_outlined, 250, 10, (w) => w.length),
  Achievement('Dedicated', 'Record 25 activities', Icons.verified_outlined, 500,
      25, (w) => w.length),
  Achievement('Streak Starter', 'Train 3 days in a row',
      Icons.local_fire_department_outlined, 100, 3, _longestStreak),
  Achievement('Week Warrior', 'Train 7 days in a row', Icons.bolt, 300, 7,
      _longestStreak),
  Achievement('Ocean Warrior', 'Complete 5 swim sessions', Icons.pool, 200, 5,
      (w) => w.where((x) => x.activity == 'Swimming').length),
  Achievement(
      'Iron Builder',
      'Complete 3 strength sessions',
      Icons.fitness_center,
      150,
      3,
      (w) => w.where((x) => x.activity == 'Strength').length),
  Achievement(
      'Triple Threat',
      'Try 3 different activities',
      Icons.category_outlined,
      100,
      3,
      (w) => w.map((x) => x.activity).toSet().length),
  Achievement(
      'Long Hauler',
      'Cover 10 km in one activity',
      Icons.route_outlined,
      150,
      10,
      (w) => w
          .fold<double>(0, (best, x) => math.max(best, x.distanceKm ?? 0))
          .floor()),
  Achievement('Century Club', 'Cover 100 km in total', Icons.public, 400, 100,
      (w) => _totalKm(w).floor()),
  Achievement(
      'Time Keeper',
      'Train for 10 hours in total',
      Icons.timer_outlined,
      300,
      600,
      (w) => w.fold<int>(0, (sum, x) => sum + x.minutes)),
];

int achievementBonusXp(List<Workout> workouts) => achievements
    .where((a) => a.earned(workouts))
    .fold<int>(0, (sum, a) => sum + a.xp);

/// Workout XP plus the one-off bonus for every unlocked achievement.
int totalXpFor(List<Workout> workouts) =>
    workouts.fold<int>(0, (sum, w) => sum + w.xp) +
    achievementBonusXp(workouts);

// ---------------------------------------------------------------------------
// App shell
// ---------------------------------------------------------------------------

class FitQuestApp extends StatefulWidget {
  const FitQuestApp({super.key});
  @override
  State<FitQuestApp> createState() => _FitQuestAppState();
}

class _FitQuestAppState extends State<FitQuestApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ThemeMode mode = ThemeMode.dark;
  int tab = 0;
  final ActivityRepository _activities = LocalActivityRepository();
  int weeklyGoalMinutes = 180;
  bool _isRecording = false;
  bool _openingInvitation = false;
  final List<Workout> workouts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FriendLinkRouter.instance.addListener(_openInvitation);
    unawaited(FriendLinkRouter.instance.restore());
    unawaited(SocialAuth.instance.initialize());
    OfflineStore.instance.addListener(_refreshStore);
    StepTracker.instance.addListener(_refreshSteps);
    OfflineStore.getInstance().then((store) {
      if (mounted) {
        store.start();
        unawaited(ProfilePhotoService.recover());
        _refreshStore();
      }
    });
    unawaited(StepTracker.instance.start());
    _loadActivities();
    _loadWeeklyGoal();
  }

  void _refreshStore() {
    unawaited(_loadActivities());
    unawaited(_loadWeeklyGoal());
    if (mounted) setState(() {});
  }

  void _refreshSteps() {
    if (mounted) setState(() {});
  }

  void _openInvitation() {
    if (!mounted ||
        _openingInvitation ||
        FriendLinkRouter.instance.pending == null) {
      return;
    }
    _openingInvitation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingInvitation = false;
      if (!mounted) return;
      final invitation = FriendLinkRouter.instance.takePending();
      if (invitation == null) return;
      unawaited(_navigatorKey.currentState!
          .push<void>(MaterialPageRoute(
              builder: (_) => FriendInvitePage(invitation: invitation)))
          .whenComplete(() => FriendLinkRouter.instance.finish(invitation)));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(OfflineStore.instance.sync());
      unawaited(StepTracker.instance.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FriendLinkRouter.instance.removeListener(_openInvitation);
    OfflineStore.instance.removeListener(_refreshStore);
    StepTracker.instance.removeListener(_refreshSteps);
    OfflineStore.instance.stop();
    StepTracker.instance.stop();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    try {
      final scope = OfflineStore.instance.scope;
      final saved = await _activities.load();
      if (mounted && scope == OfflineStore.instance.scope) {
        setState(() {
          workouts
            ..clear()
            ..addAll(saved ?? []);
        });
      }
    } catch (error) {
      _showMessage('Could not load saved activities: $error');
    }
  }

  Future<void> _loadWeeklyGoal() async {
    try {
      final prefs = await OfflineStore.getInstance();
      if (mounted) {
        setState(() {
          weeklyGoalMinutes = prefs.getInt('weekly_goal') ?? 180;
          mode = ThemeMode.values.firstWhere(
              (value) => value.name == prefs.getString('appearance_mode'),
              orElse: () => ThemeMode.dark);
        });
      }
    } catch (error) {
      _showMessage('Could not load your weekly goal: $error');
    }
  }

  Future<void> _setWeeklyGoal(int minutes) async {
    try {
      final prefs = await OfflineStore.getInstance();
      final saved = await prefs.setInt('weekly_goal', minutes);
      if (!saved) throw StateError('Could not save your weekly goal.');
      if (mounted) setState(() => weeklyGoalMinutes = minutes);
    } catch (error) {
      _showMessage('Could not save your weekly goal: $error');
    }
  }

  void _showMessage(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final onSurface = dark ? iceWhite : midnight;
    final scheme = ColorScheme.fromSeed(
      seedColor: northstar,
      brightness: brightness,
    ).copyWith(
      primary: aurora,
      onPrimary: midnight,
      secondary: northstar,
      surface: dark ? _darkCard : Colors.white,
      onSurface: onSurface,
    );
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
          color: dark ? const Color(0xFF1E2E47) : const Color(0xFFD5DCEC)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? midnight : iceWhite,
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: dark ? midnight : iceWhite,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF0F1B2F) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF0F1B2F) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF1B2B44) : midnight,
        contentTextStyle: const TextStyle(color: iceWhite),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side:
            BorderSide(color: dark ? const Color(0xFF1E2E47) : Colors.black12),
        backgroundColor: dark ? _darkCard : Colors.white,
        labelStyle: TextStyle(
          color: onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF0D182A) : Colors.white,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: aurora, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: aurora,
          foregroundColor: midnight,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: aurora,
          side: const BorderSide(color: aurora, width: 1.2),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: aurora),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: aurora,
        linearTrackColor: Color(0x33808FA8),
      ),
    );
  }

  Future<void> addWorkout(Workout workout) async {
    final updated = [workout, ...workouts];
    try {
      await _activities.save(updated);
      if (!mounted) return;
      final before = workouts.toList();
      final rankBefore = rankIndexFor(totalXpFor(before));
      setState(() {
        workouts
          ..clear()
          ..addAll(updated);
      });
      final unlocked = achievements
          .where((a) => a.earned(updated) && !a.earned(before))
          .toList();
      final bonus = unlocked.fold<int>(0, (sum, a) => sum + a.xp);
      _showMessage([
        '${workout.activity} saved! +${workout.xp + bonus} XP',
        for (final a in unlocked)
          'Achievement unlocked: ${a.title} (+${a.xp} XP)',
      ].join('\n'));
      if (unlocked.isNotEmpty) _showAchievementCongrats(unlocked);
      final rankAfter = rankIndexFor(totalXpFor(updated));
      if (rankAfter > rankBefore) _showRankUp(ranks[rankAfter]);
    } catch (error) {
      _showMessage('Could not save this activity: $error');
    }
  }

  Future<void> updateWorkout(Workout original, Workout updatedWorkout) async {
    final index = workouts.indexOf(original);
    if (index < 0) {
      _showMessage('Could not find this activity to update.');
      return;
    }
    final before = workouts.toList(growable: false);
    final updated = before.toList(growable: true);
    updated[index] = updatedWorkout;
    try {
      await _activities.save(updated);
      if (!mounted) return;
      final rankBefore = rankIndexFor(totalXpFor(before));
      setState(() {
        workouts
          ..clear()
          ..addAll(updated);
      });
      final unlocked = achievements
          .where((a) => a.earned(updated) && !a.earned(before))
          .toList();
      if (unlocked.isNotEmpty) _showAchievementCongrats(unlocked);
      _showMessage('${updatedWorkout.activity} updated successfully.');
      final rankAfter = rankIndexFor(totalXpFor(updated));
      if (rankAfter > rankBefore) _showRankUp(ranks[rankAfter]);
    } catch (error) {
      _showMessage('Could not update this activity: $error');
    }
  }

  void _showAchievementCongrats(List<Achievement> unlocked) {
    final context = _navigatorKey.currentContext;
    if (context == null || unlocked.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Congratulations!', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.celebration_rounded, color: aurora, size: 48),
          const SizedBox(height: 10),
          const Text('You unlocked a new achievement',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final achievement in unlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${achievement.title} (+${achievement.xp} XP)',
                  textAlign: TextAlign.center),
            ),
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep going')),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
  }

  void _showRankUp(Rank rank) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rank up!', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RankBadge(rank: rank, size: 84),
          const SizedBox(height: 14),
          Text('You are now ${rank.name}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Keep training to reach the next rank.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedOf(context))),
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Awesome')),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
  }

  void openLogger({String? initialActivity}) => showModalBottomSheet<void>(
        context: _navigatorKey.currentContext!,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => WorkoutLogger(
            initialActivity: initialActivity,
            onSave: (workout) {
              Navigator.pop(sheetContext);
              unawaited(addWorkout(workout));
            }),
      );

  Future<void> _openRecorder() async {
    if (_isRecording) return;
    setState(() => _isRecording = true);
    try {
      final workout = await showModalBottomSheet<Workout>(
        context: _navigatorKey.currentContext!,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const GpsRecorder(),
      );
      if (workout != null) await addWorkout(workout);
    } catch (error) {
      _showMessage('GPS recorder failed: $error');
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void goTab(int i) => setState(() => tab = i);
    final pages = [
      HomePage(
          workouts: workouts,
          weeklyGoalMinutes: weeklyGoalMinutes,
          onRecord: (activity) => openLogger(initialActivity: activity),
          onLog: openLogger,
          onUpdateWorkout: updateWorkout,
          onTab: goTab),
      ActivitiesPage(
          workouts: workouts,
          onBack: () => goTab(0),
          onAdd: openLogger,
          onUpdateWorkout: updateWorkout,
          onGpsRecord: _openRecorder),
      TrainPage(
          workouts: workouts,
          onRecord: (activity) => openLogger(initialActivity: activity),
          onLog: openLogger),
      CommunityPage(workouts: workouts, onBack: () => goTab(0)),
      QuestsPage(workouts: workouts),
      const MarketplacePage(),
      ProfilePage(
          workouts: workouts,
          mode: mode,
          weeklyGoalMinutes: weeklyGoalMinutes,
          onMode: (m) {
            setState(() => mode = m);
            unawaited(
                OfflineStore.instance.setString('appearance_mode', m.name));
          },
          onWeeklyGoal: _setWeeklyGoal),
    ];
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'FitQuest',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      home: Scaffold(
        body: SafeArea(
            bottom: true,
            child: Column(children: [
              ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: Text(OfflineStore.instance.signedIn
                      ? '@${OfflineStore.instance.user!['username']}'
                      : 'Guest · saved offline'),
                  subtitle: Text(OfflineStore.instance.status,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(_navigatorKey.currentContext!).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const AccountPage()))),
              Expanded(
                  child: KeyedSubtree(
                      key: ValueKey(
                          '${OfflineStore.instance.scope}:${OfflineStore.instance.generation}'),
                      child: pages[tab])),
            ])),
        bottomNavigationBar: FitNavBar(index: tab, onSelect: goTab),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class FitNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const FitNavBar({super.key, required this.index, required this.onSelect});

  static const items = <(IconData, String)>[
    (Icons.home_outlined, 'Home'),
    (Icons.speed_outlined, 'Activities'),
    (Icons.fitness_center, 'Train'),
    (Icons.groups_outlined, 'Community'),
    (Icons.emoji_events_outlined, 'Quests'),
    (Icons.storefront_outlined, 'Market'),
    (Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _isDark(context) ? _darkNav : Colors.white,
          border: Border(top: BorderSide(color: lineOf(context))),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 64,
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Tooltip(
                    message: items[i].$2,
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      child: InkResponse(
                        radius: 28,
                        onTap: () => onSelect(i),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == index ? aurora : Colors.transparent,
                            ),
                            child: Icon(items[i].$1,
                                size: 23,
                                color:
                                    i == index ? midnight : mutedOf(context)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? surfaceOf(context) : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? lineOf(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  const PageHeader(
      {super.key, required this.title, this.onBack, this.actions = const []});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          ...actions,
        ]),
      );
}

class SubPage extends StatelessWidget {
  final String title;
  final Widget child;
  const SubPage({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: child),
      );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionTitle(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: TextStyle(color: mutedOf(context), fontSize: 13)),
          ],
        ]),
      );
}

class PillTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const PillTabs(
      {super.key,
      required this.labels,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: lineOf(context)),
        ),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: i == selected ? aurora : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(labels[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: i == selected ? midnight : mutedOf(context),
                        )),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class RingProgress extends StatelessWidget {
  final double progress;
  final double size;
  final double stroke;
  final Widget child;
  const RingProgress(
      {super.key,
      required this.progress,
      required this.child,
      this.size = 190,
      this.stroke = 14});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress.clamp(0, 1).toDouble(),
            stroke,
            lineOf(context),
          ),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color track;
  const _RingPainter(this.progress, this.stroke, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (progress <= 0) return;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 2);
    canvas.translate(-size.width / 2, -size.height / 2);
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(
        rect,
        0,
        sweep,
        false,
        Paint()
          ..color = aurora.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawArc(
        rect,
        0,
        sweep,
        false,
        Paint()
          ..shader = const SweepGradient(
            colors: [northstar, aurora],
            endAngle: math.pi * 2,
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.stroke != stroke || old.track != track;
}

class ActivityTile extends StatelessWidget {
  final Workout workout;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  const ActivityTile(this.workout, {super.key, this.onTap, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final distance = workout.distanceKm;
    final summary = [
      if (distance != null) '${distance.toStringAsFixed(1)} km',
      '${workout.minutes} min',
      if (workoutPace(workout) != null) workoutPace(workout)!,
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: aurora.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(activityIcon(workout.activity), color: aurora, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(workout.activity,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(summary,
                style: TextStyle(color: mutedOf(context), fontSize: 13)),
            if (workout.notes.isNotEmpty)
              Text(workout.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mutedOf(context), fontSize: 12)),
          ]),
        ),
        Text(_dayLabel(workout.date),
            style: TextStyle(color: mutedOf(context), fontSize: 12)),
        IconButton(
            tooltip: 'Edit activity',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20)),
        IconButton(
            tooltip: 'Share activity',
            onPressed: () => _openActivityShare(context, workout),
            icon: const Icon(Icons.ios_share, size: 20)),
      ]),
    );
  }
}

Future<Workout?> _showEditWorkoutSheet(BuildContext context, Workout workout) {
  final durationController =
      TextEditingController(text: workout.minutes > 0 ? '' : '');
  final distanceController = TextEditingController(
      text: workout.distanceKm == null
          ? ''
          : workout.distanceKm!.toStringAsFixed(2));
  final notesController = TextEditingController(text: workout.notes);
  var selectedActivity = workout.activity;
  return showModalBottomSheet<Workout>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Edit activity',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedActivity,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: selectableActivities
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedActivity = value);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: durationController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Duration (minutes)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: distanceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Distance (km, optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                    onPressed: () {
                      final duration =
                          int.tryParse(durationController.text.trim());
                      final km = distanceController.text.trim().isEmpty
                          ? null
                          : _positiveNumber(distanceController.text.trim());
                      if (duration == null ||
                          duration <= 0 ||
                          duration > 1440 ||
                          (distanceController.text.trim().isNotEmpty &&
                              (km == null ||
                                  !km.isFinite ||
                                  km <= 0 ||
                                  km > 5000))) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Enter a duration from 1 to 1440 minutes and a valid optional distance.')));
                        return;
                      }
                      Navigator.pop(
                          context,
                          Workout(
                            selectedActivity,
                            duration,
                            workout.date,
                            distanceKm: km,
                            notes: notesController.text.trim(),
                            photoBase64: workout.photoBase64,
                            showStartPoint: workout.showStartPoint,
                            showEndPoint: workout.showEndPoint,
                            route: workout.route,
                          ));
                    },
                    child: const Text('Save changes')),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}

void _showWorkoutDetails(BuildContext context, Workout workout,
    {Future<void> Function(Workout updated)? onUpdate}) {
  final rootContext = context;
  final photo = decodeActivityPhoto(workout.photoBase64);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(workout.activity,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                '${workout.minutes} min${workout.distanceKm == null ? '' : ' · ${workout.distanceKm!.toStringAsFixed(2)} km'}${workoutPace(workout) == null ? '' : ' · ${workoutPace(workout)}'} · +${workout.xp} XP'),
            if (workout.route.length > 1) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 170,
                child: CustomPaint(
                  painter: _RoutePainter(workout.route, aurora,
                      showStartPoint: workout.showStartPoint,
                      showEndPoint: workout.showEndPoint),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
            if (photo != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(photo,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ],
            if (workout.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(workout.notes),
            ],
            const SizedBox(height: 12),
            if (onUpdate != null) ...[
              OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final edited =
                        await _showEditWorkoutSheet(rootContext, workout);
                    if (edited != null) {
                      await onUpdate(edited);
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit activity')),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
                onPressed: () => _openActivityShare(context, workout),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share activity')),
          ]),
    ),
  );
}

void _openActivityShare(BuildContext context, Workout workout) =>
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => ActivitySharePage(
                activity: ActivityShareData(
                    activity: workout.activity,
                    minutes: workout.minutes,
                    date: workout.date,
                    distanceKm: workout.distanceKm,
                    notes: workout.notes,
                    route: workout.route,
                    photoBase64: workout.photoBase64,
                    showStartPoint: workout.showStartPoint,
                    showEndPoint: workout.showEndPoint))));

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatelessWidget {
  final List<Workout> workouts;
  final int weeklyGoalMinutes;
  final ValueChanged<String> onRecord;
  final VoidCallback onLog;
  final Future<void> Function(Workout original, Workout updatedWorkout)
      onUpdateWorkout;
  final ValueChanged<int> onTab;
  const HomePage(
      {super.key,
      required this.workouts,
      required this.weeklyGoalMinutes,
      required this.onRecord,
      required this.onLog,
      required this.onUpdateWorkout,
      required this.onTab});

  @override
  Widget build(BuildContext context) {
    final today = workouts.where((w) => _isToday(w.date)).toList();
    final steps = StepTracker.instance.today;
    final kcal = today.fold<int>(0, (sum, w) => sum + w.kcal);
    final km = today.fold<double>(0, (sum, w) => sum + (w.distanceKm ?? 0));
    final minutes = today.fold<int>(0, (sum, w) => sum + w.minutes);
    final totalXp = totalXpFor(workouts);
    final rankIndex = rankIndexFor(totalXp);
    final rank = ranks[rankIndex];
    final nextRank = rankIndex + 1 < ranks.length ? ranks[rankIndex + 1] : null;
    final rankProgress = nextRank == null
        ? 1.0
        : (totalXp - rank.minXp) / (nextRank.minXp - rank.minXp);
    final weekStart = _startOfWeek(DateTime.now());
    final weeklyMinutes = workouts
        .where((w) => !w.date.isBefore(weekStart))
        .fold<int>(0, (sum, w) => sum + w.minutes);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning!'
        : hour < 18
            ? 'Good afternoon!'
            : 'Good evening!';

    return ListView(padding: pagePadding, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          const Expanded(child: _Wordmark()),
          const _CurrentUserAvatar(),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Open profile tab',
            onPressed: () => onTab(6),
            icon: const Icon(Icons.person_outline, color: aurora),
          ),
          IconButton(
            tooltip: 'Record workout',
            onPressed: onLog,
            icon: const Icon(Icons.add_circle_outline, color: aurora),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Text(greeting,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      Text('Keep going!',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: mutedOf(context))),
      const SizedBox(height: 20),
      Center(
        child: RingProgress(
          progress: steps / dailyStepGoal,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.directions_walk, color: aurora, size: 22),
            const SizedBox(height: 2),
            Text(fmtInt(steps),
                style: const TextStyle(
                    fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
            Text('steps',
                style: TextStyle(color: mutedOf(context), fontSize: 14)),
          ]),
        ),
      ),
      AnimatedBuilder(
        animation: StepTracker.instance,
        builder: (context, _) {
          final tracker = StepTracker.instance;
          return SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            secondary: const Icon(Icons.directions_walk, color: aurora),
            title: const Text('Phone step sensor'),
            subtitle: Text('${fmtInt(tracker.today)} steps today · '
                '${tracker.status}'),
            value: tracker.enabled,
            onChanged: (enabled) {
              if (enabled) {
                unawaited(tracker.enable());
              } else {
                unawaited(tracker.disable());
              }
            },
          );
        },
      ),
      const SizedBox(height: 22),
      Row(children: [
        _HomeStat(Icons.local_fire_department, _flameRed, fmtInt(kcal), 'kcal'),
        _HomeStat(Icons.place_outlined, aurora, km.toStringAsFixed(1), 'km'),
        _HomeStat(
            Icons.timer_outlined, const Color(0xFF3DDC84), '$minutes', 'min'),
      ]),
      const SizedBox(height: 22),
      AppCard(
        onTap: () => openRanks(context, workouts),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          RankBadge(rank: rank, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${rank.name} · Level ${_levelFor(totalXp)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text(
                    nextRank == null
                        ? '${fmtInt(totalXp)} XP'
                        : '${fmtInt(totalXp)} / ${fmtInt(nextRank.minXp)} XP',
                    style: TextStyle(color: mutedOf(context), fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    minHeight: 8,
                    color: rank.color,
                    value: rankProgress.clamp(0, 1).toDouble()),
              ),
              const SizedBox(height: 6),
              Text(
                  nextRank == null
                      ? 'Top rank reached'
                      : '${fmtInt(nextRank.minXp - totalXp)} XP to ${nextRank.name}',
                  style: TextStyle(color: mutedOf(context), fontSize: 11)),
            ]),
          ),
          Icon(Icons.chevron_right, color: mutedOf(context)),
        ]),
      ),
      AppCard(
        onTap: () => onTab(4),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weekly goal',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                  '$weeklyMinutes of $weeklyGoalMinutes min · ${_currentStreak(workouts)} day streak',
                  style: TextStyle(color: mutedOf(context), fontSize: 13)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    minHeight: 8,
                    value: (weeklyMinutes / weeklyGoalMinutes)
                        .clamp(0, 1)
                        .toDouble()),
              ),
            ]),
          ),
        ]),
      ),
      const SectionTitle('Start a workout'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in [
          'Running',
          'Cycling',
          'Swimming',
          'Strength',
          'Rowing',
          'Yoga'
        ])
          ActionChip(
              avatar: Icon(activityIcon(a), color: aurora, size: 18),
              label: Text(a),
              onPressed: () => onRecord(a)),
      ]),
      const SectionTitle('Recent activities'),
      ...workouts.take(3).map((w) => ActivityTile(w,
          onTap: () => _showWorkoutDetails(context, w,
              onUpdate: (edited) => onUpdateWorkout(w, edited)),
          onEdit: () async {
            final edited = await _showEditWorkoutSheet(context, w);
            if (edited != null) {
              await onUpdateWorkout(w, edited);
            }
          })),
    ]);
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => const Text.rich(
        TextSpan(children: [
          TextSpan(text: 'FIT'),
          TextSpan(text: 'QUEST', style: TextStyle(color: aurora)),
        ]),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: .5,
        ),
      );
}

class _CurrentUserAvatar extends StatelessWidget {
  const _CurrentUserAvatar();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) {
        final photo =
            decodeProfilePhoto(OfflineStore.instance.get('profile_photo_v1'));
        return CircleAvatar(
          radius: 16,
          backgroundColor: aurora.withValues(alpha: .2),
          backgroundImage: photo == null ? null : MemoryImage(photo),
          child: photo == null
              ? const Icon(Icons.person_outline, color: aurora, size: 18)
              : null,
        );
      });
}

class _HomeStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  const _HomeStat(this.icon, this.color, this.value, this.unit);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(unit, style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Activities
// ---------------------------------------------------------------------------

class ActivitiesPage extends StatelessWidget {
  final List<Workout> workouts;
  final VoidCallback onBack;
  final VoidCallback onAdd;
  final VoidCallback onGpsRecord;
  final Future<void> Function(Workout original, Workout updatedWorkout)
      onUpdateWorkout;
  const ActivitiesPage(
      {super.key,
      required this.workouts,
      required this.onBack,
      required this.onAdd,
      required this.onUpdateWorkout,
      required this.onGpsRecord});

  @override
  Widget build(BuildContext context) => Stack(children: [
        Column(children: [
          PageHeader(title: 'Activities', onBack: onBack, actions: [
            IconButton(
              tooltip: 'Record with GPS',
              onPressed: onGpsRecord,
              icon: const Icon(Icons.gps_fixed, color: aurora),
            ),
          ]),
          Expanded(
            child: workouts.isEmpty
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                            'No activities yet. Tap + to record your first workout.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: mutedOf(context)))))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      for (final w in workouts)
                        ActivityTile(w,
                            onTap: () => _showWorkoutDetails(context, w,
                                onUpdate: (edited) =>
                                    onUpdateWorkout(w, edited)),
                            onEdit: () async {
                              final edited =
                                  await _showEditWorkoutSheet(context, w);
                              if (edited != null) {
                                await onUpdateWorkout(w, edited);
                              }
                            }),
                    ],
                  ),
          ),
        ]),
        Positioned(
          right: 20,
          bottom: 20,
          child: Tooltip(
            message: 'Add activity',
            child: Material(
              color: aurora,
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: aurora.withValues(alpha: .5),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.add, color: midnight, size: 30),
                ),
              ),
            ),
          ),
        ),
      ]);
}

// ---------------------------------------------------------------------------
// Train
// ---------------------------------------------------------------------------

class TrainPage extends StatelessWidget {
  final List<Workout> workouts;
  final ValueChanged<String> onRecord;
  final VoidCallback onLog;
  const TrainPage(
      {super.key,
      required this.workouts,
      required this.onRecord,
      required this.onLog});

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageHeader(title: 'Train'),
        Expanded(
          child: ListView(padding: pagePadding, children: [
            _StrengthHero(onTap: () => onRecord('Strength')),
            const SizedBox(height: 14),
            _TrainRow(
              icon: Icons.event_note_outlined,
              title: 'Workout Plans',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SubPage(
                      title: 'Workout Plans',
                      child: _TrainingPlans(onRecord: onRecord)))),
            ),
            _TrainRow(
              icon: Icons.add_task_outlined,
              title: 'Log Workout',
              onTap: onLog,
            ),
            _TrainRow(
              icon: Icons.restaurant_outlined,
              title: 'Nutrition',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SubPage(
                      title: 'Nutrition',
                      child: NutritionPage(workouts: workouts)))),
            ),
          ]),
        ),
      ]);
}

class _StrengthHero extends StatelessWidget {
  final VoidCallback onTap;
  const _StrengthHero({required this.onTap});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2B3A4F), Color(0xFF0E1726)],
                ),
              ),
              child: Stack(children: [
                Positioned(
                  right: -18,
                  top: 10,
                  child: Icon(Icons.fitness_center,
                      size: 170, color: Colors.white.withValues(alpha: .10)),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          midnight.withValues(alpha: .85),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 18,
                  bottom: 16,
                  right: 18,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Strength',
                            style: TextStyle(
                                color: iceWhite,
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Build muscle and get stronger',
                            style: TextStyle(
                                color: Color(0xFFB8C4D8), fontSize: 14)),
                      ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _TrainRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _TrainRow(
      {required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: aurora.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: aurora, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right, color: mutedOf(context)),
        ]),
      );
}

class _TrainingPlans extends StatefulWidget {
  final ValueChanged<String> onRecord;
  const _TrainingPlans({required this.onRecord});
  @override
  State<_TrainingPlans> createState() => _TrainingPlansState();
}

typedef _PlanSession = (
  String title,
  String duration,
  IconData icon,
  String activity,
  String howTo,
);

class _TrainingPlansState extends State<_TrainingPlans> {
  static const _difficultyLevels = [
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  static const _planHowTo = {
    'Weight Loss Focus': [
      'Aim for 3 sessions each week with 1 rest day between hard days.',
      'Keep effort at 6-7/10 so you can complete the full session.',
      'Add 5 minutes or a small pace increase every 1-2 weeks.',
    ],
    'Strength Builder': [
      'Warm up for 5-8 minutes before every strength session.',
      'Use controlled reps: 8-12 reps x 2-4 sets per movement.',
      'Progress by adding reps first, then load when ready.',
    ],
    'Swim Endurance': [
      'Start each swim with 200 m easy warm-up.',
      'Rest 20-40 seconds between intervals and focus on form.',
      'Finish with 5 minutes easy cooldown and mobility.',
    ],
    '5K Starter': [
      'Run at conversational pace on easy and long days.',
      'Keep one full recovery day after harder sessions.',
      'Increase long run by up to 10% per week only.',
    ],
    'Ride Strong': [
      'Use cadence 85-95 rpm for steady rides.',
      'Alternate hard and easy cycling days for recovery.',
      'Add 5-10 minutes weekly if recovery feels good.',
    ],
    'Balanced Fitness': [
      'Train 3 days per week and keep at least one rest day.',
      'Mix cardio and strength to improve fat loss and fitness.',
      'Track consistency first, intensity second.',
    ],
    'Fat Loss Starter (4 weeks)': [
      'Follow this as Day 1, Day 3 and Day 5 each week.',
      'Keep intervals hard but controlled at 7-8/10 effort.',
      'Pair the plan with daily walks and steady hydration.',
    ],
    'Low Impact Weight Loss': [
      'Ideal for beginners, joint care, or return-from-break training.',
      'Stay consistent with 4 sessions weekly at moderate effort.',
      'Extend each session by 5 minutes after two stable weeks.',
    ],
  };

  static const Map<String, List<_PlanSession>> plans = {
    'Weight Loss Focus': [
      (
        'Cardio intervals',
        '30 min run or cycle',
        Icons.timelapse,
        'Running',
        '5 min warm-up, 8 x (1 min hard / 2 min easy), 5 min cool down.',
      ),
      (
        'Pool laps',
        '35 min aerobic swim',
        Icons.pool,
        'Swimming',
        'Alternate 100 m easy + 100 m moderate for 14 lengths.',
      ),
      (
        'Brisk walk',
        '30 min recovery pace',
        Icons.directions_walk,
        'Walking',
        'Maintain quick arm swing and steady breathing throughout.',
      ),
    ],
    'Strength Builder': [
      (
        'Power session',
        '35 min full body',
        Icons.fitness_center,
        'Strength',
        '3 rounds: squats, push-ups, lunges, rows, plank (45 sec each).',
      ),
      (
        'Barbell lifting day',
        '45 min lifting',
        Icons.fitness_center,
        'Strength',
        'Warm up with the empty bar, then 3 sets of 5 on each lift. Rest 2-3 min between sets.',
      ),
      (
        'Row conditioning',
        '25 min steady',
        Icons.rowing,
        'Rowing',
        'Row 5 x 4 min steady with 1 min easy recovery between.',
      ),
      (
        'Mobility flow',
        '20 min yoga',
        Icons.self_improvement,
        'Yoga',
        'Focus hips, hamstrings and thoracic spine mobility.',
      ),
    ],
    'Swim Endurance': [
      (
        'Technique drills',
        '30 min swim',
        Icons.pool,
        'Swimming',
        '6 x 50 m drill + 6 x 50 m relaxed freestyle with short rests.',
      ),
      (
        'Tempo sets',
        '40 min swim',
        Icons.waves,
        'Swimming',
        '4 x 200 m tempo with 45 sec rest between each set.',
      ),
      (
        'Dryland strength',
        '25 min bodyweight',
        Icons.fitness_center,
        'Strength',
        'Circuit: glute bridge, squat, push-up, side plank x 3 rounds.',
      ),
    ],
    '5K Starter': [
      (
        'Easy run',
        '20 min easy pace',
        Icons.directions_run,
        'Running',
        'Run easy enough to hold a conversation.',
      ),
      (
        'Recovery walk',
        '25 min relaxed',
        Icons.directions_walk,
        'Walking',
        'Walk tall with long strides to flush the legs.',
      ),
      (
        'Long run',
        '30 min comfortable',
        Icons.directions_run,
        'Running',
        'Start slow, finish steady. Avoid sprinting at the end.',
      ),
    ],
    'Ride Strong': [
      (
        'Endurance ride',
        '40 min steady',
        Icons.directions_bike,
        'Cycling',
        'Keep heart rate moderate and cadence smooth.',
      ),
      (
        'Strength day',
        '30 min full body',
        Icons.fitness_center,
        'Strength',
        '3 sets each: split squat, row, push-up, dead bug.',
      ),
      (
        'Recovery spin',
        '25 min easy',
        Icons.directions_bike,
        'Cycling',
        'Very light resistance, high cadence, easy breathing.',
      ),
    ],
    'Balanced Fitness': [
      (
        'Cardio day',
        '30 min of your choice',
        Icons.favorite_outline,
        'Running',
        'Choose run, cycle or swim at moderate effort for 30 minutes.',
      ),
      (
        'Strength day',
        '30 min full body',
        Icons.fitness_center,
        'Strength',
        'Perform 6 movements x 40 sec work / 20 sec rest, 3 rounds.',
      ),
      (
        'Active recovery',
        '25 min relaxed',
        Icons.directions_walk,
        'Walking',
        'Easy walk and gentle mobility to stay fresh.',
      ),
    ],
    'Fat Loss Starter (4 weeks)': [
      (
        'Interval walk-jog',
        '28 min',
        Icons.directions_run,
        'Running',
        '4 min brisk walk + 2 min easy jog repeated 4 times.',
      ),
      (
        'Home strength circuit',
        '25 min',
        Icons.fitness_center,
        'Strength',
        '3 rounds: squats, incline push-ups, reverse lunges, plank.',
      ),
      (
        'Steady cardio',
        '35 min',
        Icons.directions_bike,
        'Cycling',
        'Cycle or fast walk continuously at moderate effort.',
      ),
    ],
    'Low Impact Weight Loss': [
      (
        'Fast walk',
        '35 min',
        Icons.directions_walk,
        'Walking',
        'Walk at a pace where speaking is possible but not effortless.',
      ),
      (
        'Pool cardio',
        '30 min',
        Icons.pool,
        'Swimming',
        'Continuous easy-to-moderate swimming with short rests.',
      ),
      (
        'Core + mobility',
        '20 min',
        Icons.self_improvement,
        'Yoga',
        'Core stability, hip mobility and gentle stretching sequence.',
      ),
    ],
  };
  String activePlan = 'Weight Loss Focus';
  String difficulty = 'Beginner';
  late DateTime planStart = _mondayOf(DateTime.now());

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  // Day offsets from the plan start, spread evenly with rest days between.
  static List<int> _dayOffsets(int count) => switch (count) {
        1 => [0],
        2 => [0, 3],
        3 => [0, 2, 4],
        4 => [0, 1, 3, 5],
        _ => [for (var i = 0; i < count; i++) (i * 7 / count).floor()],
      };

  String _dayLabel(int offset) {
    final date = planStart.add(Duration(days: offset));
    return _weekdays[date.weekday - 1];
  }

  bool _isToday(int offset) {
    final now = DateTime.now();
    final date = planStart.add(Duration(days: offset));
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _resetWeek(DateTime start) async {
    final prefs = await OfflineStore.getInstance();
    final value = start.toIso8601String().substring(0, 10);
    if (!await prefs.setString('plan_start', value)) {
      throw StateError('Could not save your plan start.');
    }
    if (mounted) setState(() => planStart = start);
  }

  Future<void> _chooseReset() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final choice = await showDialog<DateTime>(
      context: context,
      builder: (context) =>
          SimpleDialog(title: const Text('Reset plan week'), children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _mondayOf(today)),
          child: const Text('Start from this Monday'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(
              context, _mondayOf(today).add(const Duration(days: 7))),
          child: const Text('Start from next Monday'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, today),
          child: const Text('Start today'),
        ),
      ]),
    );
    if (choice != null) await _resetWeek(choice);
  }

  @override
  void initState() {
    super.initState();
    OfflineStore.getInstance().then((prefs) {
      final storedStart =
          DateTime.tryParse(prefs.getString('plan_start') ?? '');
      if (mounted && storedStart != null) {
        setState(() => planStart = storedStart);
      }
      if (mounted && plans.containsKey(prefs.getString('active_plan'))) {
        setState(() => activePlan = prefs.getString('active_plan')!);
      }
      final storedDifficulty = prefs.getString('training_difficulty');
      if (mounted && _difficultyLevels.contains(storedDifficulty)) {
        setState(() => difficulty = storedDifficulty!);
      }
    });
  }

  Future<void> _selectPlan(String plan) async {
    final prefs = await OfflineStore.getInstance();
    final saved = await prefs.setString('active_plan', plan);
    if (!saved) throw StateError('Could not save your training plan.');
    if (mounted) setState(() => activePlan = plan);
  }

  Future<void> _selectDifficulty(String level) async {
    final prefs = await OfflineStore.getInstance();
    final saved = await prefs.setString('training_difficulty', level);
    if (!saved) throw StateError('Could not save your training level.');
    if (mounted) setState(() => difficulty = level);
  }

  _PlanSession _sessionForDifficulty(_PlanSession base) {
    final factor = switch (difficulty) {
      'Beginner' => 0.85,
      'Advanced' => 1.15,
      _ => 1.0,
    };
    final duration =
        base.$2.replaceFirstMapped(RegExp(r'(\d+)\s*min'), (match) {
      final current = int.parse(match.group(1)!);
      final scaled = math.max(10, (current * factor).round());
      return '$scaled min';
    });
    final cue = switch (difficulty) {
      'Beginner' => 'Beginner pace: keep rests generous.',
      'Advanced' => 'Advanced push: keep form tight at higher intensity.',
      _ => 'Intermediate pace: controlled effort with short rests.',
    };
    return (base.$1, duration, base.$3, base.$4, '$cue ${base.$5}');
  }

  @override
  Widget build(BuildContext context) {
    final sessions = plans[activePlan]!
        .map((session) => _sessionForDifficulty(session))
        .toList();
    final offsets = _dayOffsets(sessions.length);
    final weekEnd = planStart.add(const Duration(days: 6));
    String md(DateTime d) => '${d.day}/${d.month}';
    return ListView(padding: pagePadding, children: [
      Row(children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            key: ValueKey(activePlan),
            initialValue: activePlan,
            decoration: const InputDecoration(labelText: 'Active plan'),
            items: plans.keys
                .map((plan) => DropdownMenuItem(value: plan, child: Text(plan)))
                .toList(),
            onChanged: (plan) {
              if (plan != null) {
                _selectPlan(plan).catchError((Object error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Could not select plan: $error')));
                  }
                });
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(difficulty),
            initialValue: difficulty,
            decoration: const InputDecoration(labelText: 'Level'),
            items: _difficultyLevels
                .map((level) =>
                    DropdownMenuItem(value: level, child: Text(level)))
                .toList(),
            onChanged: (level) {
              if (level != null) {
                _selectDifficulty(level).catchError((Object error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Could not save level: $error')));
                  }
                });
              }
            },
          ),
        ),
      ]),
      SectionTitle("This week's sessions",
          subtitle:
              'Week of ${md(planStart)} - ${md(weekEnd)}. Each session has a set day.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _chooseReset().catchError((Object error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not reset week: $error')));
            }
          }),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset plan week'),
        ),
      ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How to follow this plan',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Training level: $difficulty',
                style: TextStyle(color: mutedOf(context), fontSize: 13)),
            const SizedBox(height: 6),
            for (final tip in _planHowTo[activePlan] ?? const <String>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('- $tip',
                    style: TextStyle(color: mutedOf(context), fontSize: 13)),
              ),
          ],
        ),
      ),
      for (var index = 0; index < sessions.length; index++)
        Builder(builder: (context) {
          final session = sessions[index];
          final offset = offsets[index];
          final today = _isToday(offset);
          return AppCard(
            onTap: () => widget.onRecord(session.$4),
            child: Column(children: [
              Row(children: [
                Icon(session.$3, color: aurora),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_dayLabel(offset)}${today ? ' (today)' : ''}',
                            style: TextStyle(
                                color: today ? aurora : mutedOf(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        Text(session.$1,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(session.$2,
                            style: TextStyle(
                                color: mutedOf(context), fontSize: 13)),
                        const SizedBox(height: 3),
                        Text(session.$5,
                            style: TextStyle(
                                color: mutedOf(context), fontSize: 12)),
                      ]),
                ),
                const Icon(Icons.play_circle_outline, color: aurora),
              ]),
              if (sessionExercises['$activePlan|${session.$1}']
                  case final keys?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ExerciseGuidePage(
                                    title: session.$1,
                                    exercises: [
                                      for (final k in keys) exerciseLibrary[k]!
                                    ]))),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text('How to do it (${keys.length} exercises)'),
                  ),
                ),
            ]),
          );
        }),
      Text(
          'Plans and training level are saved offline and sync when connected. Coaches and adaptive plans are not available yet.',
          style: TextStyle(color: mutedOf(context), fontSize: 12)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

class CommunityPage extends StatefulWidget {
  final List<Workout> workouts;
  final VoidCallback onBack;
  const CommunityPage(
      {super.key, required this.workouts, required this.onBack});
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static const _demoPosts = [
    ('Northstar Crew', 'Completed a 5 km run! Feeling great!', true, 24),
    ('Sam', 'Completed 1,000 m in the pool today!', false, 11),
    ('Morgan', 'Hit a new personal best on my strength session!', false, 8),
  ];

  static const _followerEvents = [
    ('liked your activity', Icons.favorite_rounded),
    ('started following your challenge', Icons.flag_rounded),
    ('commented on your route', Icons.mode_comment_outlined),
    ('shared a new run update', Icons.directions_run_rounded),
    ('gave kudos to your progress', Icons.emoji_events_outlined),
  ];

  final liked = <String>{};
  final joined = <String>{};
  final seenFollowing = <String>{};
  List<String> posts = [];
  int subTab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCommunityState());
  }

  Future<void> _loadCommunityState() async {
    try {
      final prefs = await OfflineStore.getInstance();
      if (!mounted) return;
      setState(() {
        posts = prefs.getStringList('community_posts') ?? [];
        joined.addAll(prefs.getStringList('community_joined') ?? []);
        liked.addAll(prefs.getStringList('community_liked') ?? []);
        seenFollowing
          ..clear()
          ..addAll(prefs.getStringList('community_following_seen') ?? []);
      });
    } catch (error) {
      _showCommunityError('Could not load community data: $error');
    }
  }

  void _showCommunityError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _savePosts(List<String> updated,
      {required String failureMessage}) async {
    final prefs = await OfflineStore.getInstance();
    final saved = await prefs.setStringList('community_posts', updated);
    if (!saved) throw StateError(failureMessage);
    if (mounted) {
      setState(() => posts = updated);
    }
  }

  Future<void> _toggleChallenge(String challenge) async {
    final updated = Set<String>.of(joined);
    if (!updated.add(challenge)) updated.remove(challenge);
    try {
      final prefs = await OfflineStore.getInstance();
      final saved =
          await prefs.setStringList('community_joined', updated.toList());
      if (!saved) throw StateError('Could not save challenge membership.');
      if (mounted) {
        setState(() {
          joined
            ..clear()
            ..addAll(updated);
        });
      }
    } catch (error) {
      _showCommunityError('Could not update challenge: $error');
    }
  }

  Future<void> _toggleLike(String id) async {
    final updated = Set<String>.of(liked);
    if (!updated.add(id)) updated.remove(id);
    try {
      final prefs = await OfflineStore.getInstance();
      final saved =
          await prefs.setStringList('community_liked', updated.toList());
      if (!saved) throw StateError('Could not save your reaction.');
      if (mounted) {
        setState(() {
          liked
            ..clear()
            ..addAll(updated);
        });
      }
    } catch (error) {
      _showCommunityError('Could not save your reaction: $error');
    }
  }

  Future<void> _createPost() async {
    final controller = TextEditingController();
    try {
      final store = await OfflineStore.getInstance();
      var includeBmi = store.getBool('share_bmi') ?? false;
      var includeJourney = store.getBool('share_weight_journey') ?? false;
      final startWeight = store.getDouble('bl_start');
      final currentWeight = store.getDouble('bl_current');
      final heightCm = store.getDouble('profile_height_cm');
      final guidance = _buildWeightGuidance(
          startWeight: startWeight,
          currentWeight: currentWeight,
          heightCm: heightCm);
      if (!mounted) return;

      final text = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Share an update'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 180,
                    decoration: const InputDecoration(
                        hintText: 'What did you accomplish?')),
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share BMI'),
                  value: includeBmi,
                  onChanged: (value) => setState(() => includeBmi = value),
                ),
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share weight journey'),
                  value: includeJourney,
                  onChanged: (value) => setState(() => includeJourney = value),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Post')),
            ],
          ),
        ),
      );
      if (text == null || text.isEmpty) return;
      final lines = <String>[];
      if (includeBmi && guidance.bmi != null) {
        lines.add(
            'BMI ${guidance.bmi!.toStringAsFixed(1)} (${guidance.bmiBand})');
      }
      if (includeJourney && startWeight != null && currentWeight != null) {
        final change = startWeight - currentWeight;
        final percent = change / startWeight * 100;
        lines.add(
            'Journey update: ${change.toStringAsFixed(1)} kg (${percent.toStringAsFixed(1)}%).');
        lines.add(guidance.reinforcementText);
      }
      final composed = lines.isEmpty ? text : '$text\n\n${lines.join('\n')}';
      final updated = [composed, ...posts];
      await _savePosts(updated, failureMessage: 'Could not save your post.');
    } catch (error) {
      _showCommunityError('Could not publish post: $error');
    } finally {
      controller.dispose();
    }
  }

  String _myPostSubtitle(String post, int index) {
    final isSharedActivity = post.contains('#FitQuest');
    final kind = isSharedActivity ? 'Shared activity' : 'Posted update';
    return '$kind - ${_relativeTimeLabel(index + 1)}';
  }

  void _sendSupport(String username, String id) {
    unawaited(_markFollowingSeen(id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You sent support to @$username.')));
  }

  Future<void> _editPost(int index) async {
    if (index < 0 || index >= posts.length) return;
    final controller = TextEditingController(text: posts[index]);
    try {
      final edited = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit post'),
          content: TextField(
            controller: controller,
            maxLines: 7,
            minLines: 4,
            maxLength: 600,
            decoration:
                const InputDecoration(hintText: 'Update your progress post'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save')),
          ],
        ),
      );
      if (edited == null || edited.isEmpty || edited == posts[index]) return;
      final updated = List<String>.of(posts);
      updated[index] = edited;
      await _savePosts(updated,
          failureMessage: 'Could not save your edited post.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post updated successfully.')));
      }
    } catch (error) {
      _showCommunityError('Could not edit post: $error');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deletePost(int index) async {
    if (index < 0 || index >= posts.length) return;
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete post'),
            content:
                const Text('This post will be removed from your feed updates.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) return;
    try {
      final updated = List<String>.of(posts)..removeAt(index);
      await _savePosts(updated, failureMessage: 'Could not delete your post.');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Post deleted.')));
      }
    } catch (error) {
      _showCommunityError('Could not delete post: $error');
    }
  }

  int _stableHash(String input) {
    var hash = 5381;
    for (final code in input.codeUnits) {
      hash = ((hash << 5) + hash) ^ code;
    }
    return hash.abs();
  }

  String _relativeTimeLabel(int value) {
    const labels = ['Now', '8m ago', '23m ago', '1h ago', '3h ago', 'Today'];
    return labels[value % labels.length];
  }

  Future<void> _markFollowingSeen([String? id]) async {
    final updated = Set<String>.of(seenFollowing);
    if (id == null) {
      for (final item in _followingHighlights()) {
        updated.add(item.id);
      }
    } else {
      updated.add(id);
    }
    try {
      final prefs = await OfflineStore.getInstance();
      final saved = await prefs.setStringList(
          'community_following_seen', updated.toList());
      if (!saved) throw StateError('Could not save following notifications.');
      if (!mounted) return;
      setState(() {
        seenFollowing
          ..clear()
          ..addAll(updated);
      });
    } catch (error) {
      _showCommunityError('Could not update following notifications: $error');
    }
  }

  List<
      ({
        String id,
        String username,
        String message,
        String subtitle,
        bool unread,
        IconData icon,
      })> _followingHighlights() {
    final store = OfflineStore.instance;
    final raw = store.getString('_known_people');
    if (raw == null) return const [];
    final people = (jsonDecode(raw) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((person) =>
            store.getBool('following/${person['id']}') == true &&
            (person['username'] as String?)?.isNotEmpty == true)
        .take(5)
        .toList();
    return [
      for (final person in people)
        () {
          final personId = person['id'] as String;
          final username = person['username'] as String;
          final daySeed = DateTime.now().toUtc().day;
          final index =
              _stableHash('$personId:$daySeed') % _followerEvents.length;
          final event = _followerEvents[index];
          final itemId = 'following-$personId';
          final unread = !seenFollowing.contains(itemId);
          return (
            id: itemId,
            username: username,
            message: '${event.$1}. Tap to send support.',
            subtitle: unread
                ? '${_relativeTimeLabel(_stableHash(personId))} - New'
                : '${_relativeTimeLabel(_stableHash(username))} - Seen',
            unread: unread,
            icon: event.$2,
          );
        }(),
    ];
  }

  Widget _communityQuickOverview(BuildContext context,
          {required int unreadCount}) =>
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your community',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _communityPill('${posts.length} posts', Icons.edit_note_outlined),
            _communityPill('$unreadCount new updates',
                Icons.notifications_active_outlined),
            _communityPill('${joined.length} challenges', Icons.flag_outlined),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: _createPost,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Share update')),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const FriendsPage())),
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('Friends')),
          ]),
        ]),
      );

  Widget _communityPill(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: aurora.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: aurora),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      );
  @override
  Widget build(BuildContext context) => Column(children: [
        PageHeader(title: 'Community', onBack: widget.onBack, actions: [
          IconButton(
            tooltip: 'Share an update',
            onPressed: _createPost,
            icon: const Icon(Icons.edit_outlined, color: aurora),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: PillTabs(
              labels: const ['Feed', 'My posts', 'Friends', 'Groups'],
              selected: subTab,
              onChanged: (i) => setState(() => subTab = i)),
        ),
        Expanded(
          child: ListView(
              padding: pagePadding,
              children: switch (subTab) {
                0 => _feed(context),
                1 => _myPosts(context),
                2 => [
                    AppCard(
                        child: Column(children: [
                      const Text(
                          'Find friends by username and follow their community updates.'),
                      FilledButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => const FriendsPage())),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Find friends & following')),
                    ]))
                  ],
                3 => [
                    _emptyState(
                        context,
                        Icons.groups_outlined,
                        'Groups coming soon',
                        'Clubs and group challenges need a server. Local challenges are available in the Feed tab.')
                  ],
                _ => const [],
              }),
        ),
      ]);

  List<Widget> _feed(BuildContext context) {
    final following = _followingHighlights();
    final unreadCount = following.where((item) => item.unread).length;
    return [
      _communityQuickOverview(context, unreadCount: unreadCount),
      ListTile(
          title: const Text("Friends' updates"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const FriendsPage()))),
      if (following.isNotEmpty) ...[
        SectionTitle('Following notifications',
            subtitle: unreadCount == 0
                ? 'All caught up'
                : '$unreadCount new update${unreadCount == 1 ? '' : 's'}'),
        if (unreadCount > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: () => _markFollowingSeen(),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Mark all as seen')),
          ),
        for (final item in following)
          _postCard(context,
              id: item.id,
              author: item.username,
              subtitle: item.subtitle,
              message: item.message,
              baseLikes: 0,
              leadingIcon: item.icon,
              unread: item.unread,
              onMarkSeen: item.unread
                  ? () => _sendSupport(item.username, item.id)
                  : null,
              secondaryActionLabel: item.unread ? 'Support' : null),
      ],
      const SectionTitle('Community feed'),
      for (var i = 0; i < _demoPosts.length; i++)
        _postCard(context,
            id: 'demo-$i',
            author: _demoPosts[i].$1,
            subtitle: 'Demo post',
            message: _demoPosts[i].$2,
            withImage: _demoPosts[i].$3,
            baseLikes: _demoPosts[i].$4),
      const SectionTitle('Community challenges'),
      AppCard(
          child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Create a fitness challenge'),
              subtitle: const Text(
                  'Military tests, CrossFit-style workouts and your own rules'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openChallenges(context))),
      for (final challenge in [
        ('Move 150 minutes', 'A week of movement, at your pace.'),
        ('Weekend explorer', 'Record an outdoor activity this weekend.'),
        ('5 km builder', 'Run or walk 5 km with steady pacing.'),
        ('10 km push', 'Build endurance and complete 10 km.'),
        ('Half marathon prep', 'Progress to 21.1 km with smart recovery.'),
        (
          'Comrades build-up',
          'Long-run consistency challenge toward ultra endurance.'
        ),
      ])
        AppCard(
          child: Row(children: [
            const Icon(Icons.flag_outlined, color: aurora),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.$1,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(challenge.$2,
                        style:
                            TextStyle(color: mutedOf(context), fontSize: 13)),
                  ]),
            ),
            TextButton(
              onPressed: () => _toggleChallenge(challenge.$1),
              child: Text(joined.contains(challenge.$1) ? 'Joined' : 'Join'),
            ),
          ]),
        ),
      Text(
          'Demo posts are fictional. Your own posts sync when connected and are visible to followers. Find real friends in Friends & following.',
          style: TextStyle(color: mutedOf(context), fontSize: 12)),
    ];
  }

  List<Widget> _myPosts(BuildContext context) {
    if (posts.isEmpty) {
      return [
        _emptyState(context, Icons.edit_note_rounded, 'No posts yet',
            'Share your first progress update to build your story and motivate your followers.'),
        const SizedBox(height: 8),
        AppCard(
            child: FilledButton.icon(
                onPressed: _createPost,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Create my first post'))),
      ];
    }
    return [
      AppCard(
          child: Row(children: [
        Expanded(
            child: Text(
                'You have ${posts.length} post${posts.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14))),
        FilledButton.icon(
            onPressed: _createPost,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New post')),
      ])),
      SectionTitle('My posts',
          subtitle: '${posts.length} update${posts.length == 1 ? '' : 's'}'),
      for (var i = 0; i < posts.length; i++)
        _postCard(context,
            id: 'you-${posts[i]}-$i',
            author: 'You',
            subtitle: _myPostSubtitle(posts[i], i),
            message: posts[i],
            useCurrentUserPhoto: true,
            baseLikes: 0,
            onEdit: () => _editPost(i),
            onDelete: () => _deletePost(i)),
    ];
  }

  Widget _emptyState(
          BuildContext context, IconData icon, String title, String body) =>
      AppCard(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(icon, size: 40, color: aurora),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedOf(context), fontSize: 13)),
        ]),
      );

  Widget _communityInitialOrIcon({
    required String author,
    required IconData? leadingIcon,
  }) {
    if (leadingIcon != null) {
      return Icon(leadingIcon, color: aurora, size: 20);
    }
    return Text(author.characters.first,
        style: const TextStyle(color: aurora, fontWeight: FontWeight.w800));
  }

  Widget _communityAvatar({
    required String author,
    required IconData? leadingIcon,
    required bool useCurrentUserPhoto,
  }) =>
      AnimatedBuilder(
          animation: OfflineStore.instance,
          builder: (context, _) {
            final photo = useCurrentUserPhoto
                ? decodeProfilePhoto(
                    OfflineStore.instance.get('profile_photo_v1'))
                : null;
            return CircleAvatar(
              radius: 20,
              backgroundColor: aurora.withValues(alpha: .2),
              backgroundImage: photo == null ? null : MemoryImage(photo),
              child: photo == null
                  ? _communityInitialOrIcon(
                      author: author, leadingIcon: leadingIcon)
                  : null,
            );
          });

  Widget _postCard(BuildContext context,
      {required String id,
      required String author,
      required String subtitle,
      required String message,
      required int baseLikes,
      bool withImage = false,
      bool useCurrentUserPhoto = false,
      IconData? leadingIcon,
      bool unread = false,
      VoidCallback? onMarkSeen,
      String? secondaryActionLabel,
      VoidCallback? onEdit,
      VoidCallback? onDelete}) {
    final isLiked = liked.contains(id);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _communityAvatar(
              author: author,
              leadingIcon: leadingIcon,
              useCurrentUserPhoto: useCurrentUserPhoto),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(author,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              Text(subtitle,
                  style: TextStyle(color: mutedOf(context), fontSize: 12)),
            ]),
          ),
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: aurora.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('NEW',
                  style: TextStyle(
                      color: aurora,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          if (onEdit != null || onDelete != null)
            PopupMenuButton<String>(
              tooltip: 'Post actions',
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit post'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete post'),
                  ),
              ],
            ),
        ]),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(fontSize: 15)),
        if (withImage) ...[
          const SizedBox(height: 12),
          Container(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFB067),
                  Color(0xFF3B6B88),
                  Color(0xFF14283D)
                ],
              ),
            ),
            child: Center(
              child: Icon(Icons.directions_run,
                  size: 64, color: Colors.white.withValues(alpha: .85)),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _toggleLike(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(children: [
                Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 20, color: isLiked ? _flameRed : mutedOf(context)),
                const SizedBox(width: 6),
                Text('${baseLikes + (isLiked ? 1 : 0)}',
                    style: TextStyle(color: mutedOf(context))),
              ]),
            ),
          ),
          const Spacer(),
          if (onMarkSeen != null)
            TextButton.icon(
                onPressed: onMarkSeen,
                icon: Icon(
                    (secondaryActionLabel ?? 'Seen') == 'Support'
                        ? Icons.thumb_up_alt_outlined
                        : Icons.check_rounded,
                    size: 16),
                label: Text(secondaryActionLabel ?? 'Seen')),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Nutrition (opened from Train)
// ---------------------------------------------------------------------------

class NutritionPage extends StatelessWidget {
  final List<Workout> workouts;
  const NutritionPage({super.key, required this.workouts});
  @override
  Widget build(BuildContext context) => DailyNutritionPage(
      activityCredits: () =>
          workouts.map((w) => ActivityCalorieCredit(w.date, w.kcal)).toList());
}

// ---------------------------------------------------------------------------
// Quests
// ---------------------------------------------------------------------------
class QuestsPage extends StatefulWidget {
  final List<Workout> workouts;
  const QuestsPage({super.key, required this.workouts});
  @override
  State<QuestsPage> createState() => _QuestsPageState();
}

class _QuestsPageState extends State<QuestsPage> {
  int subTab = 1;

  @override
  Widget build(BuildContext context) {
    final workouts = widget.workouts;
    final steps = StepTracker.instance.today;
    final dailyQuest = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Daily Quest',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text('${fmtInt(dailyStepGoal)} steps',
                style: const TextStyle(fontSize: 14)),
          ),
          Text('${fmtInt(steps)} / ${fmtInt(dailyStepGoal)}',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              minHeight: 8,
              value: (steps / dailyStepGoal).clamp(0, 1).toDouble()),
        ),
      ]),
    );

    return Column(children: [
      const PageHeader(title: 'Quests'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: PillTabs(
            labels: const ['Challenges', 'Progress'],
            selected: subTab,
            onChanged: (i) => setState(() => subTab = i)),
      ),
      Expanded(
        child: ListView(padding: pagePadding, children: [
          if (subTab == 0) ...[
            AppCard(
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Fitness challenges'),
                    subtitle: const Text('Create and track custom tests'),
                    onTap: () => openChallenges(context))),
          ] else ...[
            dailyQuest,
            _BiggestLoserCard(
              onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SubPage(
                      title: 'Biggest Loser',
                      child: ListView(
                          padding: pagePadding,
                          children: const [BiggestLoserCompetition()])))),
            ),
            ...achievementCards(workouts),
          ],
        ]),
      ),
    ]);
  }
}

class RankBadge extends StatelessWidget {
  final Rank rank;
  final double size;
  const RankBadge({super.key, required this.rank, this.size = 44});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${rank.name} rank',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [rank.color, Color.lerp(rank.color, midnight, .5)!],
            ),
            boxShadow: [
              BoxShadow(
                  color: rank.color.withValues(alpha: .35),
                  blurRadius: size * .3),
            ],
          ),
          child: Icon(rank.icon, color: Colors.white, size: size * .55),
        ),
      );
}

class RankChip extends StatelessWidget {
  final Rank rank;
  final String? label;
  const RankChip({super.key, required this.rank, this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: rank.color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: rank.color.withValues(alpha: .55)),
        ),
        child: Text(label ?? rank.name,
            style: TextStyle(
                color: rank.color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

void openRanks(BuildContext context, List<Workout> workouts) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            SubPage(title: 'Ranks', child: RanksPage(workouts: workouts))));

class RanksPage extends StatelessWidget {
  final List<Workout> workouts;
  const RanksPage({super.key, required this.workouts});

  static const _demoAthletes = [
    ('Alex', 5200),
    ('Sam', 3100),
    ('Morgan', 1800),
    ('Riley', 900),
    ('Jordan', 300),
  ];

  @override
  Widget build(BuildContext context) {
    final xp = totalXpFor(workouts);
    final index = rankIndexFor(xp);
    final rank = ranks[index];
    final next = index + 1 < ranks.length ? ranks[index + 1] : null;
    final board = <(String, int, bool)>[
      for (final a in _demoAthletes) (a.$1, a.$2, false),
      ('You', xp, true),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return ListView(padding: pagePadding, children: [
      AppCard(
        padding: const EdgeInsets.all(20),
        borderColor: rank.color.withValues(alpha: .5),
        child: Column(children: [
          RankBadge(rank: rank, size: 88),
          const SizedBox(height: 12),
          Text(rank.name,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text('${fmtInt(xp)} XP · Level ${_levelFor(xp)}',
              style: TextStyle(color: mutedOf(context))),
          const SizedBox(height: 16),
          if (next != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  minHeight: 10,
                  color: rank.color,
                  value: ((xp - rank.minXp) / (next.minXp - rank.minXp))
                      .clamp(0, 1)
                      .toDouble()),
            ),
            const SizedBox(height: 8),
            Text('${fmtInt(next.minXp - xp)} XP to ${next.name}',
                style: TextStyle(color: mutedOf(context), fontSize: 13)),
          ] else
            Text('You have reached the top rank!',
                style:
                    TextStyle(color: rank.color, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SectionTitle('Rank ladder',
          subtitle: 'Earn XP from workouts and achievements to climb.'),
      for (var i = 0; i < ranks.length; i++)
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          borderColor: i == index ? ranks[i].color.withValues(alpha: .7) : null,
          child: Row(children: [
            Opacity(
                opacity: i > index ? .4 : 1,
                child: RankBadge(rank: ranks[i], size: 40)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ranks[i].name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: i > index ? mutedOf(context) : null)),
                    Text(
                        i == 0
                            ? 'Starting rank'
                            : '${fmtInt(ranks[i].minXp)} XP',
                        style:
                            TextStyle(color: mutedOf(context), fontSize: 12)),
                  ]),
            ),
            if (i == index)
              RankChip(rank: ranks[i], label: 'Current')
            else if (i < index)
              const Icon(Icons.check_circle, color: aurora)
            else
              Icon(Icons.lock_outline, color: mutedOf(context)),
          ]),
        ),
      const SectionTitle('Leaderboard',
          subtitle:
              'Demo athletes are fictional. Real rankings need a server.'),
      for (var i = 0; i < board.length; i++)
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderColor: board[i].$3 ? aurora : null,
          child: Row(children: [
            SizedBox(
              width: 30,
              child: Text('#${i + 1}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: mutedOf(context))),
            ),
            RankBadge(rank: ranks[rankIndexFor(board[i].$2)], size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(board[i].$1,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: board[i].$3
                                ? FontWeight.w800
                                : FontWeight.w600)),
                    Text(ranks[rankIndexFor(board[i].$2)].name,
                        style:
                            TextStyle(color: mutedOf(context), fontSize: 12)),
                  ]),
            ),
            Text('${fmtInt(board[i].$2)} XP',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}

List<Widget> achievementCards(List<Workout> workouts) {
  final sorted = [...achievements]..sort((a, b) {
      final doneA = a.earned(workouts);
      final doneB = b.earned(workouts);
      if (doneA != doneB) return doneA ? 1 : -1;
      return (b.current(workouts) / b.goal)
          .compareTo(a.current(workouts) / a.goal);
    });
  final unlocked = achievements.where((a) => a.earned(workouts)).length;
  return [
    SectionTitle('Achievements',
        subtitle:
            '$unlocked of ${achievements.length} unlocked · +${fmtInt(achievementBonusXp(workouts))} bonus XP earned'),
    for (final a in sorted) AchievementCard(achievement: a, workouts: workouts),
  ];
}

class AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final List<Workout> workouts;
  const AchievementCard(
      {super.key, required this.achievement, required this.workouts});

  @override
  Widget build(BuildContext context) {
    final done = achievement.earned(workouts);
    final current = achievement.current(workouts);
    final accent = done ? _gold : aurora;
    return AppCard(
      borderColor: done ? _gold.withValues(alpha: .5) : null,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(done ? Icons.check_circle : achievement.icon,
              color: accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(achievement.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text('+${achievement.xp} XP',
                  style: TextStyle(
                      color: done ? mutedOf(context) : aurora,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
            Text(achievement.description,
                style: TextStyle(color: mutedOf(context), fontSize: 13)),
            const SizedBox(height: 8),
            if (done)
              const Text('Unlocked',
                  style: TextStyle(
                      color: _gold, fontWeight: FontWeight.w700, fontSize: 12))
            else
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        minHeight: 6, value: current / achievement.goal),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${fmtInt(current)} / ${fmtInt(achievement.goal)}',
                    style: TextStyle(color: mutedOf(context), fontSize: 12)),
              ]),
          ]),
        ),
      ]),
    );
  }
}

class _BiggestLoserCard extends StatelessWidget {
  final VoidCallback onOpen;
  const _BiggestLoserCard({required this.onOpen});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(18),
        borderColor: const Color(0xFF6D55E0).withValues(alpha: .6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_questPurple, _questPurpleDark],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.emoji_events, color: _gold, size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Biggest Loser\nCompetition',
                  style: TextStyle(
                      color: iceWhite,
                      fontSize: 18,
                      height: 1.15,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          const Text('Lose the highest % of body weight.',
              style: TextStyle(color: Color(0xFFD3CCF5), fontSize: 14)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onOpen,
            child: const Text('View Competition'),
          ),
        ]),
      );
}

/// Local demonstration of a private Biggest Loser competition.
/// Other competitors are sample data until a backend is connected.
class BiggestLoserCompetition extends StatefulWidget {
  const BiggestLoserCompetition({super.key});
  @override
  State<BiggestLoserCompetition> createState() =>
      _BiggestLoserCompetitionState();
}

class _BiggestLoserCompetitionState extends State<BiggestLoserCompetition> {
  static const _weightHistoryKey = 'bl_weight_history_v1';
  double? startingWeight;
  double? currentWeight;
  double? heightCm;
  bool joined = false;
  int historyRangeDays = 30;
  List<_WeightHistoryEntry> weightHistory = const [];
  final start = TextEditingController();
  final current = TextEditingController();
  final height = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await OfflineStore.getInstance();
    if (!mounted) return;
    setState(() {
      joined = prefs.getBool('bl_joined') ?? false;
      startingWeight = prefs.getDouble('bl_start');
      currentWeight = prefs.getDouble('bl_current');
      heightCm = prefs.getDouble('profile_height_cm');
      weightHistory = _readWeightHistory(prefs);
      if (startingWeight != null) {
        start.text = startingWeight!.toStringAsFixed(1);
      }
      if (currentWeight != null) {
        current.text = currentWeight!.toStringAsFixed(1);
      }
      if (heightCm != null) {
        height.text = heightCm!.toStringAsFixed(0);
      }
    });
  }

  List<_WeightHistoryEntry> _readWeightHistory(OfflineStore prefs) {
    final raw = prefs.getStringList(_weightHistoryKey) ?? const <String>[];
    final parsed = <_WeightHistoryEntry>[];
    for (final line in raw) {
      final parts = line.split('|');
      if (parts.length != 2) continue;
      final date = DateTime.tryParse(parts[0]);
      final weight = double.tryParse(parts[1]);
      if (date == null || weight == null || weight <= 0) continue;
      parsed.add(_WeightHistoryEntry(date: date, weightKg: weight));
    }
    parsed.sort((a, b) => a.date.compareTo(b.date));
    return parsed;
  }

  Future<void> _appendWeightHistory(OfflineStore prefs, double weightKg) async {
    final currentHistory = _readWeightHistory(prefs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalized = weightKg.clamp(1, 500).toDouble();
    final updated = List<_WeightHistoryEntry>.of(currentHistory);
    final todayIndex = updated.indexWhere((entry) {
      final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
      return date == today;
    });
    if (todayIndex >= 0) {
      updated[todayIndex] =
          _WeightHistoryEntry(date: now, weightKg: normalized);
    } else {
      updated.add(_WeightHistoryEntry(date: now, weightKg: normalized));
    }
    final encoded = updated
        .map((entry) =>
            '${entry.date.toIso8601String()}|${entry.weightKg.toStringAsFixed(2)}')
        .toList();
    await prefs.setStringList(_weightHistoryKey, encoded);
  }

  List<_WeightHistoryEntry> _visibleHistory() {
    if (weightHistory.isEmpty || historyRangeDays <= 0) {
      return weightHistory;
    }
    final cutoff = DateTime.now().subtract(Duration(days: historyRangeDays));
    final visible =
        weightHistory.where((entry) => entry.date.isAfter(cutoff)).toList();
    return visible.isEmpty ? weightHistory : visible;
  }

  List<_WeightHistoryEntry> _fallbackHistoryFromSummary() {
    final now = DateTime.now();
    if (startingWeight != null && currentWeight != null) {
      return [
        _WeightHistoryEntry(
            date: now.subtract(const Duration(days: 7)),
            weightKg: startingWeight!),
        _WeightHistoryEntry(date: now, weightKg: currentWeight!),
      ];
    }
    if (startingWeight != null) {
      return [_WeightHistoryEntry(date: now, weightKg: startingWeight!)];
    }
    if (currentWeight != null) {
      return [_WeightHistoryEntry(date: now, weightKg: currentWeight!)];
    }
    return const [];
  }

  String _rangeLabel(int days) => switch (days) {
        7 => '7D',
        30 => '30D',
        90 => '90D',
        _ => 'All',
      };

  double? _targetWeightForGraph() {
    if (heightCm == null || !heightCm!.isFinite) return null;
    final clampedHeightCm = heightCm!.clamp(100, 250).toDouble();
    final heightMeters = clampedHeightCm / 100;
    final healthyMin = 18.5 * heightMeters * heightMeters;
    final healthyMax = 24.9 * heightMeters * heightMeters;
    final baseline = currentWeight ?? startingWeight;
    if (baseline == null || !baseline.isFinite) {
      return (healthyMin + healthyMax) / 2;
    }
    if (baseline > healthyMax) return healthyMax;
    if (baseline < healthyMin) return healthyMin;
    return baseline;
  }

  Future<void> _save() async {
    final a = _positiveNumber(start.text);
    final b =
        current.text.trim().isEmpty ? null : _positiveNumber(current.text);
    final h = height.text.trim().isEmpty ? null : _positiveNumber(height.text);
    if (a == null ||
        a > 500 ||
        (b != null && b > 500) ||
        (h != null && (h < 100 || h > 250))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter valid weights and an optional height in cm.')));
      return;
    }
    final prefs = await OfflineStore.getInstance();
    await prefs.putAll({
      'bl_joined': true,
      'bl_start': a,
      'bl_current': b,
      'profile_height_cm': h,
    });
    await _appendWeightHistory(prefs, b ?? a);
    final refreshedHistory = _readWeightHistory(prefs);
    if (!mounted) return;
    setState(() {
      joined = true;
      startingWeight = a;
      currentWeight = b;
      heightCm = h;
      weightHistory = refreshedHistory;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weigh-in saved on this device.')));
  }

  @override
  void dispose() {
    start.dispose();
    current.dispose();
    height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = _buildWeightGuidance(
        startWeight: startingWeight,
        currentWeight: currentWeight,
        heightCm: heightCm);
    final percent = (startingWeight != null && currentWeight != null)
        ? (startingWeight! - currentWeight!) / startingWeight! * 100
        : 0.0;
    final standings = <(String, double)>[
      ('Alex (demo)', 5.4),
      ('Sam (demo)', 3.8),
      if (joined && currentWeight != null) ('You', percent),
      ('Morgan (demo)', 1.9),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final visibleHistory = _visibleHistory();
    final historyForChart =
        visibleHistory.isEmpty ? _fallbackHistoryFromSummary() : visibleHistory;
    final targetWeightKg = _targetWeightForGraph();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Compete by percentage of starting body weight lost, not kilograms. Local preview with example competitors.'),
          const SizedBox(height: 14),
          TextField(
              controller: start,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Starting weight (kg)')),
          const SizedBox(height: 10),
          TextField(
              controller: current,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Latest weigh-in (kg)',
                  helperText: 'Optional - add your next weigh-in later')),
          const SizedBox(height: 10),
          TextField(
              controller: height,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Height (cm)',
                  helperText: 'Optional - used for BMI and goal guidance')),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(joined ? 'Update weigh-in' : 'Join & save weigh-in')),
          if (joined && currentWeight == null) ...[
            const SizedBox(height: 14),
            Text(
                'Starting weight saved: ${startingWeight!.toStringAsFixed(1)} kg'),
            const Text('Add your next weigh-in later to see your progress.'),
          ],
          if (joined && currentWeight != null) ...[
            const SizedBox(height: 14),
            Text('Your progress: ${percent.toStringAsFixed(2)}%',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: aurora)),
            Text(
                '${(startingWeight! - currentWeight!).toStringAsFixed(1)} kg change'),
          ],
          if (historyForChart.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Weight history',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [7, 30, 90, 0]
                  .map((days) => ChoiceChip(
                        label: Text(_rangeLabel(days)),
                        selected: historyRangeDays == days,
                        onSelected: (_) =>
                            setState(() => historyRangeDays = days),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 170,
              child: CustomPaint(
                painter: _WeightHistoryPainter(
                    entries: historyForChart,
                    lineColor: aurora,
                    textColor: mutedOf(context),
                    targetWeightKg: targetWeightKg),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              historyForChart.length < 2
                  ? 'Add more weigh-ins to see your trend line.'
                  : 'Showing ${visibleHistory.length} weigh-ins in selected range.',
              style: TextStyle(color: mutedOf(context), fontSize: 12),
            ),
            if (targetWeightKg != null)
              Text(
                'Goal line targets about ${targetWeightKg.toStringAsFixed(1)} kg.',
                style: TextStyle(color: mutedOf(context), fontSize: 12),
              ),
          ],
          const SizedBox(height: 12),
          if (guidance.bmi != null)
            Text(
                'BMI: ${guidance.bmi!.toStringAsFixed(1)} (${guidance.bmiBand})',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: aurora)),
          Text(guidance.rangeText),
          const SizedBox(height: 4),
          Text(guidance.goalText),
          const SizedBox(height: 4),
          Text(guidance.reinforcementText,
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
          const SizedBox(height: 16),
          const Text('Leaderboard - demo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          for (var i = 0; i < standings.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 15, child: Text('${i + 1}')),
              title: Text(standings[i].$1),
              trailing: Text('${standings[i].$2.toStringAsFixed(2)}%'),
            ),
          Text(
              'Private groups, dates, verified weigh-ins and live rankings need a server. Weight data is private by default. Avoid rapid or unsafe weight loss.',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ],
      ),
    );
  }
}

class _WeightHistoryEntry {
  final DateTime date;
  final double weightKg;
  const _WeightHistoryEntry({required this.date, required this.weightKg});
}

class _WeightHistoryPainter extends CustomPainter {
  final List<_WeightHistoryEntry> entries;
  final Color lineColor;
  final Color textColor;
  final double? targetWeightKg;
  const _WeightHistoryPainter(
      {required this.entries,
      required this.lineColor,
      required this.textColor,
      this.targetWeightKg});

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
      {double dash = 6, double gap = 4}) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance <= 0) return;
    final direction = delta / distance;
    var traveled = 0.0;
    while (traveled < distance) {
      final start = from + direction * traveled;
      final end = from + direction * math.min(traveled + dash, distance);
      canvas.drawLine(start, end, paint);
      traveled += dash + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = textColor.withValues(alpha: .35)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trendPaint = Paint()
      ..color = const Color(0xFF7A6AF0).withValues(alpha: .85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final goalPaint = Paint()
      ..color = const Color(0xFFFFB067).withValues(alpha: .95)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const leftPadding = 12.0;
    const rightPadding = 12.0;
    const topPadding = 12.0;
    const bottomPadding = 28.0;
    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    canvas.drawLine(Offset(leftPadding, topPadding + chartHeight),
        Offset(size.width - rightPadding, topPadding + chartHeight), axisPaint);

    if (entries.isEmpty || chartWidth <= 0 || chartHeight <= 0) {
      final textPainter = TextPainter(
          text: TextSpan(
              text: 'Add your first weigh-in',
              style: TextStyle(color: textColor, fontSize: 12)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 16);
      textPainter.paint(canvas,
          Offset((size.width - textPainter.width) / 2, (size.height - 16) / 2));
      return;
    }

    final sorted = List<_WeightHistoryEntry>.of(entries)
      ..sort((a, b) => a.date.compareTo(b.date));
    final minWeight = sorted.map((e) => e.weightKg).reduce(math.min);
    final maxWeight = sorted.map((e) => e.weightKg).reduce(math.max);
    final spread = (maxWeight - minWeight).abs();
    final yPad = math.max(0.6, spread * 0.12);
    final minY = minWeight - yPad;
    final maxY = maxWeight + yPad;

    double yFor(double value) {
      final ratio = ((value - minY) / (maxY - minY)).clamp(0.0, 1.0);
      return topPadding + chartHeight - chartHeight * ratio;
    }

    final startDate = sorted.first.date;
    final endDate = sorted.last.date;
    final totalMinutes =
        math.max(1, endDate.difference(startDate).inMinutes.abs());

    double xFor(DateTime date) {
      if (sorted.length == 1) return leftPadding + chartWidth / 2;
      final offsetMinutes = date.difference(startDate).inMinutes;
      final ratio = offsetMinutes / totalMinutes;
      return leftPadding + chartWidth * ratio;
    }

    if (targetWeightKg != null && targetWeightKg!.isFinite) {
      final targetY = yFor(targetWeightKg!);
      _drawDashedLine(canvas, Offset(leftPadding, targetY),
          Offset(size.width - rightPadding, targetY), goalPaint);
      final goalLabel = TextPainter(
          text: TextSpan(
              text: 'Goal ${targetWeightKg!.toStringAsFixed(1)} kg',
              style: const TextStyle(color: Color(0xFFFFB067), fontSize: 11)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: chartWidth - 8);
      goalLabel.paint(
          canvas, Offset(leftPadding + 4, math.max(0, targetY - 16)));
    }

    final spanDays =
        math.max(1.0, endDate.difference(startDate).inMinutes / 1440.0);
    final points = sorted
        .map((entry) => (
              x: entry.date.difference(startDate).inMinutes / 1440.0,
              y: entry.weightKg
            ))
        .toList();
    final n = points.length.toDouble();
    final sumX = points.fold<double>(0, (sum, item) => sum + item.x);
    final sumY = points.fold<double>(0, (sum, item) => sum + item.y);
    final sumXY = points.fold<double>(0, (sum, item) => sum + item.x * item.y);
    final sumXX = points.fold<double>(0, (sum, item) => sum + item.x * item.x);
    final denom = n * sumXX - sumX * sumX;
    if (sorted.length >= 2 && denom.abs() > 0.00001) {
      final slope = (n * sumXY - sumX * sumY) / denom;
      final intercept = (sumY - slope * sumX) / n;
      final trendStartY = yFor(intercept);
      final trendEndY = yFor(intercept + slope * spanDays);
      _drawDashedLine(canvas, Offset(leftPadding, trendStartY),
          Offset(size.width - rightPadding, trendEndY), trendPaint,
          dash: 5, gap: 5);
      final trendWeekly = slope * 7;
      final trendLabel = TextPainter(
          text: TextSpan(
              text:
                  'Trend ${trendWeekly >= 0 ? '+' : ''}${trendWeekly.toStringAsFixed(2)} kg/wk',
              style: const TextStyle(color: Color(0xFF7A6AF0), fontSize: 11)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: chartWidth - 8);
      trendLabel.paint(canvas,
          Offset(size.width - rightPadding - trendLabel.width, topPadding + 2));
    }

    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final point = Offset(xFor(sorted[i].date), yFor(sorted[i].weightKg));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3.4, Paint()..color = lineColor);
    }
    canvas.drawPath(path, linePaint);

    String dateLabel(DateTime date) =>
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

    final firstLabel = TextPainter(
        text: TextSpan(
            text: dateLabel(startDate),
            style: TextStyle(color: textColor, fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    final lastLabel = TextPainter(
        text: TextSpan(
            text: dateLabel(endDate),
            style: TextStyle(color: textColor, fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    firstLabel.paint(canvas, Offset(leftPadding, size.height - 20));
    lastLabel.paint(canvas,
        Offset(size.width - rightPadding - lastLabel.width, size.height - 20));

    final minLabel = TextPainter(
        text: TextSpan(
            text: '${minWeight.toStringAsFixed(1)} kg',
            style: TextStyle(color: textColor, fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    final maxLabel = TextPainter(
        text: TextSpan(
            text: '${maxWeight.toStringAsFixed(1)} kg',
            style: TextStyle(color: textColor, fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    maxLabel.paint(canvas, Offset(leftPadding, 0));
    minLabel.paint(canvas, Offset(leftPadding, topPadding + chartHeight - 12));
  }

  @override
  bool shouldRepaint(covariant _WeightHistoryPainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.targetWeightKg != targetWeightKg;
}

// ---------------------------------------------------------------------------
// Profile & settings
// ---------------------------------------------------------------------------

class ProfilePage extends StatefulWidget {
  final List<Workout> workouts;
  final ThemeMode mode;
  final int weeklyGoalMinutes;
  final ValueChanged<ThemeMode> onMode;
  final ValueChanged<int> onWeeklyGoal;
  const ProfilePage(
      {super.key,
      required this.workouts,
      required this.mode,
      required this.weeklyGoalMinutes,
      required this.onMode,
      required this.onWeeklyGoal});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  double? startWeight;
  double? currentWeight;
  double? bodyFat;
  double? heightCm;
  String? dateOfBirth;
  bool shareBmi = false;
  bool shareWeightJourney = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await OfflineStore.getInstance();
    if (!mounted) return;
    setState(() {
      startWeight = prefs.getDouble('bl_start');
      currentWeight = prefs.getDouble('bl_current');
      bodyFat = prefs.getDouble('body_fat');
      heightCm = prefs.getDouble('profile_height_cm');
      dateOfBirth = prefs.getString('profile_dob');
      shareBmi = prefs.getBool('share_bmi') ?? false;
      shareWeightJourney = prefs.getBool('share_weight_journey') ?? false;
    });
  }

  Future<void> _editBodyFat() async {
    final controller =
        TextEditingController(text: bodyFat?.toStringAsFixed(1) ?? '');
    try {
      final value = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Body fat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Body fat (%)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context,
                    double.tryParse(controller.text.replaceAll(',', '.'))),
                child: const Text('Save')),
          ],
        ),
      );
      if (value == null || !value.isFinite || value < 2 || value > 70) return;
      final prefs = await OfflineStore.getInstance();
      await prefs.setDouble('body_fat', value);
      if (mounted) setState(() => bodyFat = value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editHeight() async {
    final controller =
        TextEditingController(text: heightCm?.toStringAsFixed(0) ?? '');
    try {
      final value = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Height'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Height (cm)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context,
                    double.tryParse(controller.text.replaceAll(',', '.'))),
                child: const Text('Save')),
          ],
        ),
      );
      if (value == null || !value.isFinite || value < 100 || value > 250) {
        return;
      }
      final prefs = await OfflineStore.getInstance();
      await prefs.setDouble('profile_height_cm', value);
      if (mounted) setState(() => heightCm = value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editDateOfBirth() async {
    final initial = dateOfBirth == null
        ? DateTime(2000, 1, 1)
        : DateTime.tryParse(dateOfBirth!) ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: DateTime.now());
    if (picked == null || !mounted) return;
    final value = picked.toIso8601String().substring(0, 10);
    final prefs = await OfflineStore.getInstance();
    await prefs.setString('profile_dob', value);
    if (mounted) setState(() => dateOfBirth = value);
  }

  Future<void> _setWeightPrivacy(
      {required bool? shareBmiNext,
      required bool? shareWeightJourneyNext}) async {
    final prefs = await OfflineStore.getInstance();
    await prefs.putAll({
      if (shareBmiNext != null) 'share_bmi': shareBmiNext,
      if (shareWeightJourneyNext != null)
        'share_weight_journey': shareWeightJourneyNext,
    });
    if (!mounted) return;
    setState(() {
      if (shareBmiNext != null) shareBmi = shareBmiNext;
      if (shareWeightJourneyNext != null) {
        shareWeightJourney = shareWeightJourneyNext;
      }
    });
  }

  Future<void> _openWeight() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SubPage(
            title: 'Biggest Loser',
            child: ListView(
                padding: pagePadding,
                children: const [BiggestLoserCompetition()]))));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final workouts = widget.workouts;
    final totalXp = totalXpFor(workouts);
    final rank = ranks[rankIndexFor(totalXp)];
    final minutes = workouts.fold<int>(0, (sum, w) => sum + w.minutes);
    final distance =
        workouts.fold<double>(0, (sum, w) => sum + (w.distanceKm ?? 0));
    final delta = (startWeight != null && currentWeight != null)
        ? currentWeight! - startWeight!
        : null;
    final guidance = _buildWeightGuidance(
        startWeight: startWeight,
        currentWeight: currentWeight,
        heightCm: heightCm);

    return Column(children: [
      const PageHeader(title: 'Profile'),
      Expanded(
        child: ListView(padding: pagePadding, children: [
          ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Account, friends & sync'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const AccountPage()))),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const ProfilePhotoButton(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          OfflineStore.instance.user?['username'] as String? ??
                              'FitQuest Explorer',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      Row(children: [
                        Text('Level ${_levelFor(totalXp)}',
                            style: TextStyle(
                                color: mutedOf(context), fontSize: 14)),
                        const SizedBox(width: 8),
                        RankChip(rank: rank),
                      ]),
                    ]),
              ),
            ]),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              const Padding(
                  padding: EdgeInsets.all(14), child: ProfileGenderSelector()),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                      'Your profile photo and gender save privately and sync to your account.')),
              _StatRow(
                label: 'Weight',
                value: currentWeight == null
                    ? startWeight == null
                        ? 'Not set'
                        : '${startWeight!.toStringAsFixed(1)} kg (start)'
                    : '${currentWeight!.toStringAsFixed(1)} kg',
                extra: delta == null
                    ? null
                    : '${delta <= 0 ? 'Down' : 'Up'} ${delta.abs().toStringAsFixed(1)} kg',
                extraColor: delta != null && delta <= 0 ? aurora : null,
                onTap: _openWeight,
              ),
              Divider(height: 1, color: lineOf(context)),
              _StatRow(
                label: 'Height',
                value: heightCm == null
                    ? 'Not set'
                    : '${heightCm!.toStringAsFixed(0)} cm',
                onTap: _editHeight,
              ),
              Divider(height: 1, color: lineOf(context)),
              _StatRow(
                label: 'Date of birth',
                value: dateOfBirth == null ? 'Not set' : dateOfBirth!,
                onTap: _editDateOfBirth,
              ),
              Divider(height: 1, color: lineOf(context)),
              _StatRow(
                label: 'BMI',
                value: guidance.bmi == null
                    ? 'Add height'
                    : '${guidance.bmi!.toStringAsFixed(1)} (${guidance.bmiBand})',
              ),
              Divider(height: 1, color: lineOf(context)),
              _StatRow(
                label: 'Body Fat',
                value: bodyFat == null
                    ? 'Not set'
                    : '${bodyFat!.toStringAsFixed(1)} %',
                onTap: _editBodyFat,
              ),
              Divider(height: 1, color: lineOf(context)),
              _StatRow(label: 'XP', value: fmtInt(totalXp)),
            ]),
          ),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(guidance.rangeText,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(guidance.goalText),
                const SizedBox(height: 6),
                Text(guidance.reinforcementText,
                    style: TextStyle(color: mutedOf(context), fontSize: 12)),
              ])),
          AppCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share BMI in my posts'),
                  subtitle:
                      const Text('You decide per post, default is private.'),
                  value: shareBmi,
                  onChanged: (value) => _setWeightPrivacy(
                      shareBmiNext: value, shareWeightJourneyNext: null),
                ),
                Divider(height: 1, color: lineOf(context)),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share weight-loss journey in my posts'),
                  subtitle:
                      const Text('Adds progress summary only when you choose.'),
                  value: shareWeightJourney,
                  onChanged: (value) => _setWeightPrivacy(
                      shareBmiNext: null, shareWeightJourneyNext: value),
                ),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              _ProfileInsight('${workouts.length}', 'Activities'),
              _ProfileInsight('${minutes}m', 'Active time'),
              _ProfileInsight('${distance.toStringAsFixed(1)} km', 'Distance'),
              _ProfileInsight('${_currentStreak(workouts)}', 'Day streak'),
            ]),
          ),
          _TrainRow(
            icon: Icons.leaderboard_outlined,
            title: 'Ranks & Leaderboard',
            onTap: () => openRanks(context, workouts),
          ),
          _TrainRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Achievements',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SubPage(
                    title: 'Achievements',
                    child: ListView(
                        padding: pagePadding,
                        children: achievementCards(workouts))))),
          ),
          _TrainRow(
            icon: Icons.watch_outlined,
            title: 'Health devices',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceSyncPage())),
          ),
          _TrainRow(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsPage(
                    mode: widget.mode,
                    weeklyGoalMinutes: widget.weeklyGoalMinutes,
                    onMode: widget.onMode,
                    onWeeklyGoal: widget.onWeeklyGoal))),
          ),
          const SizedBox(height: 4),
          Text(
              'Your data is saved on this device first. Sign in to sync activities, goals, plans, nutrition, weigh-ins and community posts when connected.',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ]),
      ),
    ]);
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String? extra;
  final Color? extraColor;
  final VoidCallback? onTap;
  const _StatRow(
      {required this.label,
      required this.value,
      this.extra,
      this.extraColor,
      this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: mutedOf(context), fontSize: 15)),
            ),
            if (extra != null) ...[
              Text(extra!,
                  style: TextStyle(
                      color: extraColor ?? mutedOf(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
            ],
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _ProfileInsight extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileInsight(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: mutedOf(context), fontSize: 11)),
        ]),
      );
}

class DeviceSyncPage extends StatefulWidget {
  const DeviceSyncPage({super.key});

  @override
  State<DeviceSyncPage> createState() => _DeviceSyncPageState();
}

class _DeviceSyncPageState extends State<DeviceSyncPage> {
  bool garminEnabled = false;
  bool healthConnectEnabled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final store = await OfflineStore.getInstance();
    if (!mounted) return;
    setState(() {
      garminEnabled = store.getBool('health_device_pref.garmin') ?? false;
      healthConnectEnabled =
          store.getBool('health_device_pref.health_connect') ?? false;
    });
  }

  Future<void> _setDevice(String key, bool value) async {
    final store = await OfflineStore.getInstance();
    await store.setBool(key, value);
    if (!mounted) return;
    setState(() {
      if (key.endsWith('garmin')) garminEnabled = value;
      if (key.endsWith('health_connect')) healthConnectEnabled = value;
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link right now.')));
    }
  }

  @override
  Widget build(BuildContext context) => SubPage(
        title: 'Health devices',
        child: ListView(padding: pagePadding, children: [
          const SectionTitle('Connect wearables',
              subtitle:
                  'Enable device imports and connect your Garmin account in-app.'),
          AppCard(
              child: Column(children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Garmin Forerunner / Garmin Connect'),
              subtitle:
                  const Text('Import activities and heart-rate summaries.'),
              value: garminEnabled,
              onChanged: (value) =>
                  _setDevice('health_device_pref.garmin', value),
            ),
            Divider(height: 1, color: lineOf(context)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Android Health Connect'),
              subtitle:
                  const Text('Read workouts and step totals on this phone.'),
              value: healthConnectEnabled,
              onChanged: (value) =>
                  _setDevice('health_device_pref.health_connect', value),
            ),
          ])),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Set up',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                    '1) Turn on Garmin above.\n2) Open Garmin Connect and authorize data sharing.\n3) Return to FitQuest and refresh sync.'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: () => _open('https://connect.garmin.com/'),
                      icon: const Icon(Icons.watch),
                      label: const Text('Open Garmin Connect')),
                  OutlinedButton.icon(
                      onPressed: () => _open(
                          'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata'),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Get Health Connect')),
                ]),
              ])),
          Text(
              'Live Garmin API syncing needs Garmin OAuth keys and backend webhooks. This screen saves your preferences and setup links now.',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ]),
      );
}

class SettingsPage extends StatelessWidget {
  final ThemeMode mode;
  final int weeklyGoalMinutes;
  final ValueChanged<ThemeMode> onMode;
  final ValueChanged<int> onWeeklyGoal;
  const SettingsPage(
      {super.key,
      required this.mode,
      required this.weeklyGoalMinutes,
      required this.onMode,
      required this.onWeeklyGoal});

  @override
  Widget build(BuildContext context) => SubPage(
        title: 'Settings',
        child: ListView(padding: pagePadding, children: [
          const SectionTitle('Weekly activity goal'),
          AppCard(
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$weeklyGoalMinutes minutes per week',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Choose a goal that works for your routine.',
                          style:
                              TextStyle(color: mutedOf(context), fontSize: 13)),
                    ]),
              ),
              DropdownButton<int>(
                value: weeklyGoalMinutes,
                items: [90, 120, 150, 180, 240, 300]
                    .map((minutes) => DropdownMenuItem(
                        value: minutes, child: Text('$minutes')))
                    .toList(),
                onChanged: (goal) {
                  if (goal != null) onWeeklyGoal(goal);
                },
              ),
            ]),
          ),
          const SectionTitle('Appearance'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (value) {
                if (value != null) onMode(value);
              },
              child: const Column(children: [
                RadioListTile<ThemeMode>(
                    title: Text('Follow system'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(
                    title: Text('Dark Northstar'), value: ThemeMode.dark),
                RadioListTile<ThemeMode>(
                    title: Text('Light Northstar'), value: ThemeMode.light),
              ]),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Recording sheets
// ---------------------------------------------------------------------------

class WorkoutLogger extends StatefulWidget {
  final ValueChanged<Workout> onSave;
  final String? initialActivity;
  const WorkoutLogger({super.key, required this.onSave, this.initialActivity});
  @override
  State<WorkoutLogger> createState() => _WorkoutLoggerState();
}

class _WorkoutLoggerState extends State<WorkoutLogger> {
  String activity = 'Swimming';
  final minutes = TextEditingController(text: '30');
  final distance = TextEditingController();
  final notes = TextEditingController();
  @override
  void initState() {
    super.initState();
    if (widget.initialActivity != null) activity = widget.initialActivity!;
  }

  @override
  void dispose() {
    minutes.dispose();
    distance.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.viewPaddingOf(context).bottom +
                24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Record workout',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                  initialValue: activity,
                  decoration: const InputDecoration(labelText: 'Activity'),
                  items: selectableActivities
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => activity = v);
                  }),
              const SizedBox(height: 12),
              TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Duration (minutes)')),
              const SizedBox(height: 12),
              TextField(
                  controller: distance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Distance (km, optional)')),
              const SizedBox(height: 12),
              TextField(
                  controller: notes,
                  maxLength: 180,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () {
                    final duration = int.tryParse(minutes.text);
                    final km =
                        double.tryParse(distance.text.replaceAll(',', '.'));
                    if (duration == null ||
                        duration <= 0 ||
                        duration > 1440 ||
                        (distance.text.trim().isNotEmpty &&
                            (km == null ||
                                !km.isFinite ||
                                km <= 0 ||
                                km > 5000))) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Enter a duration from 1 to 1440 minutes and a valid optional distance.')));
                      return;
                    }
                    widget.onSave(Workout(activity, duration, DateTime.now(),
                        distanceKm: km, notes: notes.text.trim()));
                  },
                  child: const Text('Save workout')),
            ]),
      );
}

class GpsRecorder extends StatefulWidget {
  const GpsRecorder({super.key});
  @override
  State<GpsRecorder> createState() => _GpsRecorderState();
}

class _GpsRecorderState extends State<GpsRecorder> {
  String activity = 'Running';
  bool starting = false;
  bool recording = false;
  bool paused = false;
  bool selectingPhoto = false;
  bool showStartPoint = true;
  bool showEndPoint = true;
  String? locationMessage;
  String? activityPhotoBase64;
  bool voiceMilestonesEnabled = true;
  int playlistIndex = 0;
  List<_InAppTrack> playlist = List<_InAppTrack>.of(_inAppPlaylist);
  double nextDistanceMilestoneKm = 1;
  int nextTimeMilestoneMinutes = 10;
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MapController _mapController = MapController();
  bool followLiveLocation = true;
  ll.LatLng? _lastMapCenter;
  StreamSubscription<Position>? subscription;
  Timer? timer;
  final stopwatch = Stopwatch();
  Duration carriedElapsed = Duration.zero;
  final route = <({double latitude, double longitude})>[];
  double distanceMeters = 0;
  DateTime? startedAt;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_nextTrack(autoStart: true));
      }
    });
    unawaited(_configureTts());
    unawaited(_initializeRecorderData());
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(subscription?.cancel());
    unawaited(_playerStateSub?.cancel());
    unawaited(_audioPlayer.dispose());
    stopwatch.stop();
    unawaited(_tts.stop());
    if (recording || route.isNotEmpty || carriedElapsed > Duration.zero) {
      unawaited(_saveDraft());
    }
    super.dispose();
  }

  Duration get _elapsedDuration => carriedElapsed + stopwatch.elapsed;

  Future<void> _configureTts() async {
    try {
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
    } catch (_) {
      // Ignore voice setup errors.
    }
  }

  Future<void> _initializeRecorderData() async {
    await _loadCustomPlaylist();
    await _restoreDraft();
  }

  Future<void> _loadCustomPlaylist() async {
    try {
      final store = await OfflineStore.getInstance();
      final raw = store.getString(_customPlaylistKey);
      if (raw == null || raw.trim().isEmpty) return;
      final json = jsonDecode(raw) as List<dynamic>;
      final imported = json
          .map((item) => item as Map<String, dynamic>)
          .map((item) => _InAppTrack(
              (item['title'] as String?)?.trim().isNotEmpty == true
                  ? item['title'] as String
                  : 'Custom track',
              (item['url'] as String?)?.trim() ?? ''))
          .where((track) => track.url.startsWith('http'))
          .toList(growable: false);
      if (imported.isEmpty || !mounted) return;
      setState(() {
        playlist = imported;
        playlistIndex = playlistIndex.clamp(0, playlist.length - 1);
      });
    } catch (_) {
      // Ignore invalid imported playlist payloads.
    }
  }

  Future<void> _saveCustomPlaylist() async {
    final store = await OfflineStore.getInstance();
    final payload = playlist
        .map((track) => {'title': track.title, 'url': track.url})
        .toList();
    await store.setString(_customPlaylistKey, jsonEncode(payload));
  }

  Future<void> _importPlaylist() async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<List<_InAppTrack>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import playlist'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'One track per line',
              helperText:
                  'Use URL only, or Title|URL. Example: Warmup|https://...mp3',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final parsed = controller.text
                      .split('\n')
                      .map((line) => line.trim())
                      .where((line) => line.isNotEmpty)
                      .map((line) {
                    final divider = line.indexOf('|');
                    final title =
                        divider > 0 ? line.substring(0, divider).trim() : '';
                    final url =
                        divider > 0 ? line.substring(divider + 1).trim() : line;
                    return _InAppTrack(
                        title.isEmpty
                            ? 'Track ${line.hashCode.abs().toString().substring(0, 4)}'
                            : title,
                        url);
                  }).where((track) {
                    final uri = Uri.tryParse(track.url);
                    return uri != null &&
                        (uri.scheme == 'http' || uri.scheme == 'https') &&
                        uri.host.isNotEmpty;
                  }).toList(growable: false);
                  Navigator.pop(context, parsed);
                },
                child: const Text('Import')),
          ],
        ),
      );
      if (result == null || result.isEmpty || !mounted) return;
      setState(() {
        playlist = result;
        playlistIndex = 0;
      });
      await _saveCustomPlaylist();
      await _saveDraft();
      setState(() {
        locationMessage = 'Imported ${result.length} playlist tracks.';
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _resetPlaylistToDefault() async {
    if (!mounted) return;
    setState(() {
      playlist = List<_InAppTrack>.of(_inAppPlaylist);
      playlistIndex = 0;
      locationMessage = 'Playlist reset to FitQuest defaults.';
    });
    await _saveCustomPlaylist();
    await _saveDraft();
  }

  Future<void> _speakMilestone(String text) async {
    if (!voiceMilestonesEnabled) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Ignore runtime voice errors.
    }
  }

  void _resetMilestones() {
    nextDistanceMilestoneKm = 1;
    nextTimeMilestoneMinutes = 10;
  }

  void _checkMilestones() {
    if (!recording || paused) return;
    final distanceKm = distanceMeters / 1000;
    if (distanceKm >= nextDistanceMilestoneKm) {
      final reached = distanceKm.floor();
      if (reached >= 1) {
        nextDistanceMilestoneKm = reached + 1.0;
        unawaited(
            _speakMilestone('Great work. You reached $reached kilometers.'));
      }
    }
    final minutes = _elapsedDuration.inMinutes;
    if (minutes >= nextTimeMilestoneMinutes) {
      final reached = (minutes ~/ 10) * 10;
      if (reached >= 10) {
        nextTimeMilestoneMinutes = reached + 10;
        unawaited(
            _speakMilestone('Nice pace. You have completed $reached minutes.'));
      }
    }
  }

  ll.LatLng? get _currentLatLng {
    if (route.isEmpty) return null;
    final point = route.last;
    return ll.LatLng(point.latitude, point.longitude);
  }

  List<ll.LatLng> get _routeLatLngs => route
      .map((p) => ll.LatLng(p.latitude, p.longitude))
      .toList(growable: false);

  String get _recorderPace {
    final distanceKm = distanceMeters / 1000;
    if (distanceKm <= 0 || _elapsedDuration.inSeconds <= 0) return '--';
    if (activity != 'Running' && activity != 'Walking') return '--';
    final secondsPerKm = (_elapsedDuration.inSeconds / distanceKm).round();
    return '${secondsPerKm ~/ 60}:${(secondsPerKm % 60).toString().padLeft(2, '0')} /km';
  }

  void _recenterMap() {
    final point = _currentLatLng;
    if (point == null) return;
    _mapController.move(point, 17);
    _lastMapCenter = point;
  }

  void _updateMapFollow() {
    if (!followLiveLocation) return;
    final point = _currentLatLng;
    if (point == null) return;
    final previous = _lastMapCenter;
    if (previous == null ||
        const ll.Distance().as(ll.LengthUnit.Meter, previous, point) >= 5) {
      _mapController.move(point, 17);
      _lastMapCenter = point;
    }
  }

  _InAppTrack? get _selectedTrack => playlist.isEmpty
      ? null
      : playlist[playlistIndex.clamp(0, playlist.length - 1)];

  Future<void> _loadTrack(int index, {bool autoStart = false}) async {
    if (playlist.isEmpty) {
      if (mounted) {
        setState(() => locationMessage =
            'No playlist tracks yet. Import your own list first.');
      }
      return;
    }
    final safeIndex = index.clamp(0, playlist.length - 1);
    final track = playlist[safeIndex];
    try {
      await _audioPlayer.setUrl(track.url);
      if (autoStart) await _audioPlayer.play();
      if (!mounted) return;
      setState(() {
        playlistIndex = safeIndex;
        locationMessage = autoStart
            ? 'Playing ${track.title} inside FitQuest.'
            : 'Loaded ${track.title}. Tap play when ready.';
      });
      await _saveDraft();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        locationMessage =
            'Could not load this track. Check your internet connection.';
      });
    }
  }

  Future<void> _toggleTrackPlayback() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
      if (mounted) {
        setState(() => locationMessage = 'Music paused.');
      }
      await _saveDraft();
      return;
    }
    if (_audioPlayer.audioSource == null) {
      await _loadTrack(playlistIndex, autoStart: true);
      return;
    }
    await _audioPlayer.play();
    if (mounted) {
      setState(() => locationMessage = 'Music resumed.');
    }
    await _saveDraft();
  }

  Future<void> _nextTrack({bool autoStart = true}) async {
    if (playlist.isEmpty) return;
    final next = (playlistIndex + 1) % playlist.length;
    await _loadTrack(next, autoStart: autoStart);
  }

  Future<void> _previousTrack() async {
    final previous = (playlistIndex - 1 + playlist.length) % playlist.length;
    await _loadTrack(previous, autoStart: true);
  }

  Future<void> _callEmergency() async {
    final launched = await launchUrl(Uri(scheme: 'tel', path: '112'),
        mode: LaunchMode.externalApplication);
    if (mounted && !launched) {
      setState(() {
        locationMessage =
            'Could not open your phone dialer. Call 112 or your local emergency number.';
      });
    }
  }

  String _mapsLocationUrl() {
    final point = _currentLatLng;
    if (point == null) return '';
    return 'https://maps.google.com/?q=${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
  }

  Future<void> _sendSafetySms() async {
    final locationUrl = _mapsLocationUrl();
    final message = locationUrl.isEmpty
        ? 'Safety alert from FitQuest. Please contact me.'
        : 'Safety alert from FitQuest. My location: $locationUrl';
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted && !launched) {
      setState(() {
        locationMessage = 'Could not open SMS on this device.';
      });
    }
  }

  Future<String?> _getWhatsappContact() async {
    final store = await OfflineStore.getInstance();
    final raw = store.getString(_sosWhatsappNumberKey)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : digits;
  }

  Future<String?> _promptWhatsappContact({String? initialValue}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency WhatsApp contact'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
              labelText: 'WhatsApp number',
              helperText: 'Use country code, e.g. 27821234567'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (number == null) return null;
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) {
      if (mounted) {
        setState(() {
          locationMessage = 'Enter a valid WhatsApp number with country code.';
        });
      }
      return null;
    }
    final store = await OfflineStore.getInstance();
    await store.setString(_sosWhatsappNumberKey, digits);
    if (mounted) {
      setState(() {
        locationMessage = 'Emergency WhatsApp contact saved.';
      });
    }
    return digits;
  }

  Future<void> _sendSafetyWhatsapp() async {
    var contact = await _getWhatsappContact();
    contact ??= await _promptWhatsappContact();
    if (contact == null) return;
    final locationUrl = _mapsLocationUrl();
    final message = locationUrl.isEmpty
        ? 'Safety alert from FitQuest. Please contact me.'
        : 'Safety alert from FitQuest. My location: $locationUrl';
    final encoded = Uri.encodeComponent(message);
    final appUri = Uri.parse('whatsapp://send?phone=$contact&text=$encoded');
    final webUri = Uri.parse('https://wa.me/$contact?text=$encoded');
    final launched =
        await launchUrl(appUri, mode: LaunchMode.externalApplication) ||
            await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (mounted && !launched) {
      setState(() {
        locationMessage =
            'Could not open WhatsApp. Make sure it is installed and contact is valid.';
      });
    }
  }

  Future<void> _copySafetyLocation() async {
    final locationUrl = _mapsLocationUrl();
    if (locationUrl.isEmpty) {
      if (mounted) {
        setState(() {
          locationMessage =
              'No GPS point yet. Start moving first, then copy location.';
        });
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: locationUrl));
    if (mounted) {
      setState(() {
        locationMessage =
            'Location link copied. Share it with a trusted contact.';
      });
    }
  }

  Future<void> _openSosActions() async {
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ListTile(
                  title: Text('Safety SOS'),
                  subtitle:
                      Text('Call, message, or copy your current location.'),
                ),
                ListTile(
                    leading: const Icon(Icons.call_outlined, color: _flameRed),
                    title: const Text('Call emergency (112)'),
                    onTap: () => Navigator.pop(context, 'call')),
                ListTile(
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('Send location SMS'),
                    onTap: () => Navigator.pop(context, 'sms')),
                ListTile(
                    leading: const Icon(Icons.chat_outlined,
                        color: Color(0xFF25D366)),
                    title: const Text('Send location on WhatsApp'),
                    subtitle: const Text(
                        'Uses your saved emergency WhatsApp contact.'),
                    onTap: () => Navigator.pop(context, 'whatsapp')),
                ListTile(
                    leading: const Icon(Icons.settings_phone_outlined),
                    title: const Text('Set WhatsApp emergency contact'),
                    onTap: () => Navigator.pop(context, 'set_whatsapp')),
                ListTile(
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('Copy live location link'),
                    onTap: () => Navigator.pop(context, 'copy')),
                const SizedBox(height: 8),
              ]),
            ));
    switch (action) {
      case 'call':
        await _callEmergency();
        return;
      case 'sms':
        await _sendSafetySms();
        return;
      case 'whatsapp':
        await _sendSafetyWhatsapp();
        return;
      case 'set_whatsapp':
        await _promptWhatsappContact(initialValue: await _getWhatsappContact());
        return;
      case 'copy':
        await _copySafetyLocation();
        return;
      default:
        return;
    }
  }

  void _ensureTimer() {
    timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && recording && !paused) {
        _checkMilestones();
        setState(() {});
      }
    });
  }

  Future<void> _clearDraft() async {
    final store = await OfflineStore.getInstance();
    await store.remove(_gpsDraftKey);
  }

  Future<void> _saveDraft() async {
    final store = await OfflineStore.getInstance();
    if (!recording && route.isEmpty && _elapsedDuration == Duration.zero) {
      await store.remove(_gpsDraftKey);
      return;
    }
    await store.setString(
      _gpsDraftKey,
      jsonEncode({
        'activity': activity,
        'recording': recording,
        'paused': paused,
        'startedAt': startedAt?.toIso8601String(),
        'distanceMeters': distanceMeters,
        'elapsedMs': _elapsedDuration.inMilliseconds,
        'activityPhotoBase64': activityPhotoBase64,
        'showStartPoint': showStartPoint,
        'showEndPoint': showEndPoint,
        'followLiveLocation': followLiveLocation,
        'voiceMilestonesEnabled': voiceMilestonesEnabled,
        'playlistIndex': playlistIndex,
        'musicPlaying': _audioPlayer.playing,
        'nextDistanceMilestoneKm': nextDistanceMilestoneKm,
        'nextTimeMilestoneMinutes': nextTimeMilestoneMinutes,
        'route': route.map((p) => [p.latitude, p.longitude]).toList(),
      }),
    );
  }

  Future<void> _restoreDraft() async {
    try {
      final store = await OfflineStore.getInstance();
      final raw = store.getString(_gpsDraftKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final recoveredRoute =
          ((json['route'] as List?) ?? const []).map((point) {
        final coords = point as List;
        return (
          latitude: (coords[0] as num).toDouble(),
          longitude: (coords[1] as num).toDouble(),
        );
      }).toList();
      final recoveredElapsed =
          Duration(milliseconds: (json['elapsedMs'] as num?)?.toInt() ?? 0);
      final restoredPlaylistIndex = (json['playlistIndex'] as num?)?.toInt();
      setState(() {
        activity = (json['activity'] as String?) ?? activity;
        route
          ..clear()
          ..addAll(recoveredRoute);
        distanceMeters = (json['distanceMeters'] as num?)?.toDouble() ?? 0;
        startedAt = json['startedAt'] == null
            ? null
            : DateTime.tryParse(json['startedAt'] as String);
        carriedElapsed = recoveredElapsed;
        activityPhotoBase64 =
            (json['activityPhotoBase64'] as String?)?.trim().isNotEmpty == true
                ? json['activityPhotoBase64'] as String
                : null;
        showStartPoint = json['showStartPoint'] as bool? ?? true;
        showEndPoint = json['showEndPoint'] as bool? ?? true;
        followLiveLocation = json['followLiveLocation'] as bool? ?? true;
        voiceMilestonesEnabled =
            json['voiceMilestonesEnabled'] as bool? ?? true;
        if (restoredPlaylistIndex != null && playlist.isNotEmpty) {
          playlistIndex = restoredPlaylistIndex.clamp(0, playlist.length - 1);
        }
        nextDistanceMilestoneKm =
            (json['nextDistanceMilestoneKm'] as num?)?.toDouble() ?? 1;
        nextTimeMilestoneMinutes =
            (json['nextTimeMilestoneMinutes'] as num?)?.toInt() ?? 10;
        recording = json['recording'] == true;
        paused = json['paused'] == true;
        locationMessage = recording
            ? 'Recovered previous activity. Resume when ready.'
            : null;
      });
      if (route.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recenterMap());
      }
      if (recording) {
        _ensureTimer();
        unawaited(_loadTrack(playlistIndex,
            autoStart: json['musicPlaying'] as bool? ?? false));
        if (!paused) {
          stopwatch
            ..reset()
            ..start();
          await _startStream();
          if (mounted) {
            setState(() {
              locationMessage = 'Recording resumed from saved draft.';
            });
          }
        }
      }
    } catch (_) {
      // Ignore unreadable drafts.
    }
  }

  Future<void> _startStream() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services to record a route.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(permission == LocationPermission.deniedForever
          ? 'Location access is blocked. Enable it in system settings to record GPS.'
          : 'Location permission is needed to record your route.');
    }
    await subscription?.cancel();
    subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen(_onPosition, onError: (Object error) {
      if (mounted) {
        setState(() => locationMessage = 'GPS update failed: $error');
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      starting = true;
      locationMessage = null;
    });
    try {
      await _clearDraft();
      route.clear();
      distanceMeters = 0;
      startedAt = DateTime.now();
      carriedElapsed = Duration.zero;
      activityPhotoBase64 = null;
      showStartPoint = true;
      showEndPoint = true;
      _resetMilestones();
      _lastMapCenter = null;
      paused = false;
      recording = true;
      stopwatch
        ..reset()
        ..start();
      _ensureTimer();
      await _startStream();
      await _saveDraft();
      if (mounted) {
        setState(() {
          starting = false;
          locationMessage = 'Recording started.';
        });
        unawaited(_speakMilestone(
            'GPS tracking started. I will announce milestones.'));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          starting = false;
          recording = false;
          paused = false;
          locationMessage = 'Could not start GPS recording: $error';
        });
      }
    }
  }

  Future<void> _pause() async {
    if (!recording || paused) return;
    await subscription?.cancel();
    subscription = null;
    stopwatch.stop();
    carriedElapsed += stopwatch.elapsed;
    stopwatch.reset();
    setState(() {
      paused = true;
      locationMessage = 'Paused. Resume to continue tracking.';
    });
    unawaited(_speakMilestone('Workout paused.'));
    await _saveDraft();
  }

  Future<void> _resume() async {
    if (!recording || !paused) return;
    setState(() {
      starting = true;
      locationMessage = null;
    });
    try {
      await _startStream();
      stopwatch
        ..reset()
        ..start();
      setState(() {
        paused = false;
        starting = false;
        locationMessage = 'Recording resumed.';
      });
      unawaited(_speakMilestone('Workout resumed.'));
      await _saveDraft();
    } catch (error) {
      if (mounted) {
        setState(() {
          starting = false;
          locationMessage = '$error';
        });
      }
    }
  }

  Future<void> _discard() async {
    timer?.cancel();
    timer = null;
    await subscription?.cancel();
    subscription = null;
    await _audioPlayer.pause();
    stopwatch.stop();
    recording = false;
    paused = false;
    activityPhotoBase64 = null;
    await _clearDraft();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickActivityPhoto(ImageSource source) async {
    if (selectingPhoto) return;
    setState(() => selectingPhoto = true);
    try {
      final selected = await ImagePicker().pickImage(
          source: source,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 86,
          requestFullMetadata: false);
      if (selected == null) return;
      final prepared = await prepareActivityPhoto(await selected.readAsBytes());
      if (!mounted) return;
      setState(() {
        activityPhotoBase64 = base64Encode(prepared);
        locationMessage = 'Activity photo added.';
      });
      await _saveDraft();
    } catch (error) {
      if (mounted) {
        setState(() {
          locationMessage = error is StateError
              ? error.message.toString()
              : 'Could not use this activity photo.';
        });
      }
    } finally {
      if (mounted) setState(() => selectingPhoto = false);
    }
  }

  Future<void> _clearActivityPhoto() async {
    setState(() => activityPhotoBase64 = null);
    await _saveDraft();
  }

  void _onPosition(Position position) {
    if (position.accuracy > 30 || !position.accuracy.isFinite) return;
    final point = (latitude: position.latitude, longitude: position.longitude);
    if (route.isNotEmpty) {
      final previous = route.last;
      final segment = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
      if (segment > 1 && segment < 100) distanceMeters += segment;
    }
    route.add(point);
    _checkMilestones();
    _updateMapFollow();
    unawaited(_saveDraft());
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!recording) return;
    await _audioPlayer.pause();
    if (!paused) {
      stopwatch.stop();
      carriedElapsed += stopwatch.elapsed;
      stopwatch.reset();
    }
    timer?.cancel();
    timer = null;
    await subscription?.cancel();
    subscription = null;
    final total = carriedElapsed;
    if (total < const Duration(seconds: 5)) {
      setState(() {
        locationMessage = 'Record for a few seconds before saving.';
      });
      return;
    }
    final workout = Workout(
      activity,
      (total.inSeconds / 60).ceil().clamp(1, 1440),
      startedAt ?? DateTime.now(),
      distanceKm: distanceMeters > 0 ? distanceMeters / 1000 : null,
      photoBase64: activityPhotoBase64,
      showStartPoint: showStartPoint,
      showEndPoint: showEndPoint,
      route: _privacySafeRoute(route,
          hideStart: !showStartPoint, hideEnd: !showEndPoint),
    );
    recording = false;
    paused = false;
    activityPhotoBase64 = null;
    await _clearDraft();
    unawaited(_tts.stop());
    unawaited(_speakMilestone('Workout saved. Great session.'));
    if (mounted) Navigator.of(context).pop(workout);
  }

  String get elapsed {
    final duration = _elapsedDuration;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.viewPaddingOf(context).bottom +
                24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('GPS activity',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: activity,
                decoration: const InputDecoration(labelText: 'Activity'),
                items: gpsActivities
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: recording
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => activity = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Voice milestones'),
                  subtitle: const Text(
                      'Audio updates every kilometer and every 10 minutes.'),
                  value: voiceMilestonesEnabled,
                  onChanged: (value) {
                    setState(() => voiceMilestonesEnabled = value);
                    unawaited(_saveDraft());
                  }),
              const SizedBox(height: 6),
              Text('In-app playlist',
                  style: TextStyle(color: mutedOf(context), fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: Text(_selectedTrack?.title ?? 'No tracks imported',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Previous track',
                    onPressed: _previousTrack,
                    icon: const Icon(Icons.skip_previous_rounded)),
                IconButton(
                    tooltip: _audioPlayer.playing ? 'Pause' : 'Play',
                    onPressed: _toggleTrackPlayback,
                    icon: Icon(_audioPlayer.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill)),
                IconButton(
                    tooltip: 'Next track',
                    onPressed: _nextTrack,
                    icon: const Icon(Icons.skip_next_rounded)),
              ]),
              const SizedBox(height: 2),
              Text(
                  '${playlist.length} track${playlist.length == 1 ? '' : 's'} loaded',
                  style: TextStyle(color: mutedOf(context), fontSize: 12)),
              Row(children: [
                TextButton.icon(
                    onPressed: _importPlaylist,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Import playlist')),
                TextButton.icon(
                    onPressed: _resetPlaylistToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset default')),
              ]),
              const SizedBox(height: 6),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show start point'),
                  subtitle: const Text('Control start marker visibility.'),
                  value: showStartPoint,
                  onChanged: (value) {
                    setState(() => showStartPoint = value);
                    unawaited(_saveDraft());
                  }),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show end point'),
                  subtitle: const Text('Control end marker visibility.'),
                  value: showEndPoint,
                  onChanged: (value) {
                    setState(() => showEndPoint = value);
                    unawaited(_saveDraft());
                  }),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Follow my location'),
                  subtitle:
                      const Text('Keep the live map centered while moving.'),
                  value: followLiveLocation,
                  onChanged: (value) {
                    setState(() => followLiveLocation = value);
                    if (value) _recenterMap();
                    unawaited(_saveDraft());
                  }),
              const SizedBox(height: 6),
              FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      foregroundColor: _flameRed,
                      backgroundColor: _flameRed.withValues(alpha: .12)),
                  onPressed: _openSosActions,
                  icon: const Icon(Icons.sos_rounded),
                  label: const Text('Safety SOS')),
              const SizedBox(height: 8),
              Container(
                height: 230,
                decoration: BoxDecoration(
                    color: surfaceOf(context),
                    border: Border.all(color: lineOf(context)),
                    borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _currentLatLng ?? const ll.LatLng(-26.2041, 28.0473),
                      initialZoom: route.isEmpty ? 12 : 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.northstar.fitquest',
                      ),
                      if (_routeLatLngs.length > 1)
                        PolylineLayer(polylines: [
                          Polyline(
                            points: _routeLatLngs,
                            strokeWidth: 5,
                            color: aurora,
                          ),
                        ]),
                      if (showStartPoint && _routeLatLngs.isNotEmpty)
                        MarkerLayer(markers: [
                          Marker(
                            point: _routeLatLngs.first,
                            width: 24,
                            height: 24,
                            child: const _RecorderMapPin(
                                color: Color(0xFF35E082),
                                icon: Icons.play_arrow),
                          )
                        ]),
                      if (showEndPoint && _routeLatLngs.isNotEmpty)
                        MarkerLayer(markers: [
                          Marker(
                            point: _routeLatLngs.last,
                            width: 24,
                            height: 24,
                            child: const _RecorderMapPin(
                                color: Color(0xFFFF5B4D), icon: Icons.flag),
                          )
                        ]),
                    ],
                  ),
                  if (_routeLatLngs.isEmpty)
                    const Center(
                        child: Text('Live map appears when GPS connects')),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: IconButton(
                        tooltip: 'Recenter map',
                        onPressed: route.isEmpty ? null : _recenterMap,
                        icon:
                            const Icon(Icons.my_location, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (activityPhotoBase64 != null)
                Builder(builder: (context) {
                  final bytes = decodeActivityPhoto(activityPhotoBase64);
                  if (bytes == null) return const SizedBox.shrink();
                  return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(bytes,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()));
                }),
              Wrap(spacing: 10, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                    onPressed: selectingPhoto
                        ? null
                        : () => _pickActivityPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(activityPhotoBase64 == null
                        ? 'Add activity photo'
                        : 'Change photo')),
                if (!kIsWeb)
                  FilledButton.tonalIcon(
                      onPressed: selectingPhoto
                          ? null
                          : () => _pickActivityPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo')),
                if (activityPhotoBase64 != null)
                  TextButton.icon(
                      onPressed: selectingPhoto ? null : _clearActivityPhoto,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo')),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _RecorderMetric(elapsed, 'TIME'),
                _RecorderMetric(
                    '${(distanceMeters / 1000).toStringAsFixed(2)} km',
                    'DISTANCE'),
                _RecorderMetric(_recorderPace, 'PACE'),
              ]),
              if (locationMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(locationMessage!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 14),
              if (recording)
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _discard,
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed:
                            starting ? null : (paused ? _resume : _pause),
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                        label: Text(paused ? 'Resume' : 'Pause')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop')),
                  ),
                ])
              else
                FilledButton.icon(
                    onPressed: starting ? null : _start,
                    icon: starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.gps_fixed),
                    label: Text(
                        starting ? 'Connecting to GPS...' : 'Start recording')),
              const SizedBox(height: 6),
              Text(
                  'You can pause, resume and stop like Strava. If this sheet closes, your in-progress GPS session is restored next time.',
                  style: TextStyle(color: mutedOf(context), fontSize: 12)),
            ]),
      );
}

class _RecorderMetric extends StatelessWidget {
  final String value;
  final String label;
  const _RecorderMetric(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]);
}

class _RecorderMapPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _RecorderMapPin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      );
}

class _RoutePainter extends CustomPainter {
  final List<({double latitude, double longitude})> points;
  final Color color;
  final bool showStartPoint;
  final bool showEndPoint;
  const _RoutePainter(this.points, this.color,
      {this.showStartPoint = true, this.showEndPoint = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minLat =
        points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat =
        points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLon =
        points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLon =
        points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    final centerLat = (minLat + maxLat) / 2;
    final latRange = (maxLat - minLat).abs();
    final lonRange =
        (maxLon - minLon).abs() * math.cos(centerLat * math.pi / 180);
    final scale = (latRange > lonRange ? latRange : lonRange);
    Offset project(({double latitude, double longitude}) point) => Offset(
        size.width *
            (0.12 +
                (point.longitude - minLon) *
                    math.cos(centerLat * math.pi / 180) /
                    (scale == 0 ? 1 : scale) *
                    0.76),
        size.height *
            (0.88 -
                (point.latitude - minLat) / (scale == 0 ? 1 : scale) * 0.76));
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final position = project(points[i]);
      if (i == 0) {
        path.moveTo(position.dx, position.dy);
      } else {
        path.lineTo(position.dx, position.dy);
      }
    }
    if (points.length > 1) {
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke);
    }
    if (showStartPoint) {
      final start = project(points.first);
      canvas.drawCircle(start, 7, Paint()..color = const Color(0xFF35E082));
      canvas.drawCircle(
          start,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
    if (showEndPoint) {
      final end = project(points.last);
      canvas.drawCircle(end, 7, Paint()..color = const Color(0xFFFF5B4D));
      canvas.drawCircle(
          end,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      oldDelegate.color != color ||
      oldDelegate.showStartPoint != showStartPoint ||
      oldDelegate.showEndPoint != showEndPoint;
}
