import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'offline_store.dart';
import 'account_ui.dart';
import 'step_tracker.dart';
import 'challenge_ui.dart';
import 'activity_sharing.dart';
import 'social_auth.dart';
import 'friend_links.dart';
import 'nutrition_log.dart';
import 'nutrition_page.dart';
import 'profile_identity.dart';

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

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
Color surfaceOf(BuildContext context) =>
    _isDark(context) ? _darkCard : Colors.white;
Color mutedOf(BuildContext context) =>
    _isDark(context) ? const Color(0xFF93A4BF) : const Color(0xFF5B6B84);
Color lineOf(BuildContext context) =>
    _isDark(context) ? const Color(0xFF1E2E47) : const Color(0xFFE1E8F2);

class Workout {
  final String activity;
  final int minutes;
  final DateTime date;
  final double? distanceKm;
  final String notes;
  final List<({double latitude, double longitude})> route;
  const Workout(
    this.activity,
    this.minutes,
    this.date, {
    this.distanceKm,
    this.notes = '',
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
        'route':
            route.map((point) => [point.latitude, point.longitude]).toList(),
      };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
        json['activity'] as String,
        json['minutes'] as int,
        DateTime.parse(json['date'] as String),
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        notes: json['notes'] as String? ?? '',
        route: ((json['route'] as List?) ?? const []).map((point) {
          final coordinates = point as List;
          return (
            latitude: (coordinates[0] as num).toDouble(),
            longitude: (coordinates[1] as num).toDouble(),
          );
        }).toList(),
      );
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

String? workoutPace(Workout workout) {
  final distance = workout.distanceKm;
  if (distance == null || distance <= 0) return null;
  if (workout.activity == 'Cycling') {
    return '${(distance * 60 / workout.minutes).toStringAsFixed(1)} km/h';
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
      final rankAfter = rankIndexFor(totalXpFor(updated));
      if (rankAfter > rankBefore) _showRankUp(ranks[rankAfter]);
    } catch (error) {
      _showMessage('Could not save this activity: $error');
    }
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
          onTab: goTab),
      ActivitiesPage(
          workouts: workouts,
          onBack: () => goTab(0),
          onAdd: openLogger,
          onGpsRecord: _openRecorder),
      TrainPage(
          workouts: workouts,
          onRecord: (activity) => openLogger(initialActivity: activity),
          onLog: openLogger),
      CommunityPage(workouts: workouts, onBack: () => goTab(0)),
      QuestsPage(workouts: workouts),
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
            bottom: false,
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
  const ActivityTile(this.workout, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final distance = workout.distanceKm;
    final summary = [
      if (distance != null) '${distance.toStringAsFixed(1)} km',
      '${workout.minutes} min',
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
            tooltip: 'Share activity',
            onPressed: () => _openActivityShare(context, workout),
            icon: const Icon(Icons.ios_share, size: 20)),
      ]),
    );
  }
}

void _showWorkoutDetails(BuildContext context, Workout workout) {
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
                  painter: _RoutePainter(workout.route, aurora),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
            if (workout.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(workout.notes),
            ],
            const SizedBox(height: 12),
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
                    route: workout.route))));

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatelessWidget {
  final List<Workout> workouts;
  final int weeklyGoalMinutes;
  final ValueChanged<String> onRecord;
  final VoidCallback onLog;
  final ValueChanged<int> onTab;
  const HomePage(
      {super.key,
      required this.workouts,
      required this.weeklyGoalMinutes,
      required this.onRecord,
      required this.onLog,
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
      if (!StepTracker.instance.enabled)
        TextButton.icon(
            onPressed: StepTracker.instance.enable,
            icon: const Icon(Icons.directions_walk),
            label: const Text('Enable phone step counter')),
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
      const SponsorPlacement(),
      ...workouts.take(3).map((w) => ActivityTile(
            w,
            onTap: () => _showWorkoutDetails(context, w),
          )),
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
  const ActivitiesPage(
      {super.key,
      required this.workouts,
      required this.onBack,
      required this.onAdd,
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
                        ActivityTile(
                          w,
                          onTap: () => _showWorkoutDetails(context, w),
                        ),
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

class _TrainingPlansState extends State<_TrainingPlans> {
  static const plans = {
    'Weight Loss Focus': [
      ('Cardio intervals', '30 min run or cycle', Icons.timelapse, 'Running'),
      ('Pool laps', '35 min aerobic swim', Icons.pool, 'Swimming'),
      ('Brisk walk', '30 min recovery pace', Icons.directions_walk, 'Walking'),
    ],
    'Strength Builder': [
      ('Power session', '35 min full body', Icons.fitness_center, 'Strength'),
      ('Row conditioning', '25 min steady', Icons.rowing, 'Rowing'),
      ('Mobility flow', '20 min yoga', Icons.self_improvement, 'Yoga'),
    ],
    'Swim Endurance': [
      ('Technique drills', '30 min swim', Icons.pool, 'Swimming'),
      ('Tempo sets', '40 min swim', Icons.waves, 'Swimming'),
      (
        'Dryland strength',
        '25 min bodyweight',
        Icons.fitness_center,
        'Strength'
      ),
    ],
    '5K Starter': [
      ('Easy run', '20 min easy pace', Icons.directions_run, 'Running'),
      ('Recovery walk', '25 min relaxed', Icons.directions_walk, 'Walking'),
      ('Long run', '30 min comfortable', Icons.directions_run, 'Running'),
    ],
    'Ride Strong': [
      ('Endurance ride', '40 min steady', Icons.directions_bike, 'Cycling'),
      ('Strength day', '30 min full body', Icons.fitness_center, 'Strength'),
      ('Recovery spin', '25 min easy', Icons.directions_bike, 'Cycling'),
    ],
    'Balanced Fitness': [
      (
        'Cardio day',
        '30 min of your choice',
        Icons.favorite_outline,
        'Running'
      ),
      ('Strength day', '30 min full body', Icons.fitness_center, 'Strength'),
      ('Active recovery', '25 min relaxed', Icons.directions_walk, 'Walking'),
    ],
  };
  String activePlan = 'Weight Loss Focus';

  @override
  void initState() {
    super.initState();
    OfflineStore.getInstance().then((prefs) {
      if (mounted && plans.containsKey(prefs.getString('active_plan'))) {
        setState(() => activePlan = prefs.getString('active_plan')!);
      }
    });
  }

  Future<void> _selectPlan(String plan) async {
    final prefs = await OfflineStore.getInstance();
    final saved = await prefs.setString('active_plan', plan);
    if (!saved) throw StateError('Could not save your training plan.');
    if (mounted) setState(() => activePlan = plan);
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: pagePadding, children: [
        DropdownButtonFormField<String>(
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
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not select plan: $error')));
                }
              });
            }
          },
        ),
        const SectionTitle("This week's sessions",
            subtitle: 'Choose a plan, then log each session as you go.'),
        for (final session in plans[activePlan]!)
          AppCard(
            onTap: () => widget.onRecord(session.$4),
            child: Row(children: [
              Icon(session.$3, color: aurora),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(session.$2,
                          style:
                              TextStyle(color: mutedOf(context), fontSize: 13)),
                    ]),
              ),
              const Icon(Icons.play_circle_outline, color: aurora),
            ]),
          ),
        Text(
            'Plans are saved offline and sync to your account when connected. Coaches and adaptive plans are not available yet.',
            style: TextStyle(color: mutedOf(context), fontSize: 12)),
      ]);
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

  final liked = <String>{};
  final joined = <String>{};
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
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share an update'),
          content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 180,
              decoration:
                  const InputDecoration(hintText: 'What did you accomplish?')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Post')),
          ],
        ),
      );
      if (text == null || text.isEmpty) return;
      final updated = [text, ...posts];
      final prefs = await OfflineStore.getInstance();
      final saved = await prefs.setStringList('community_posts', updated);
      if (!saved) throw StateError('Could not save your post.');
      if (mounted) setState(() => posts = updated);
    } catch (error) {
      _showCommunityError('Could not publish post: $error');
    } finally {
      controller.dispose();
    }
  }

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
              labels: const ['Feed', 'Friends', 'Groups'],
              selected: subTab,
              onChanged: (i) => setState(() => subTab = i)),
        ),
        Expanded(
          child: ListView(
              padding: pagePadding,
              children: switch (subTab) {
                0 => _feed(context),
                1 => [
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
                _ => [
                    _emptyState(
                        context,
                        Icons.groups_outlined,
                        'Groups coming soon',
                        'Clubs and group challenges need a server. Local challenges are available in the Feed tab.')
                  ],
              }),
        ),
      ]);

  List<Widget> _feed(BuildContext context) => [
        ListTile(
            title: const Text('Friends’ updates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const FriendsPage()))),
        for (final post in posts)
          _postCard(context,
              id: 'you-$post',
              author: 'You',
              subtitle: 'Just now',
              message: post,
              baseLikes: 0),
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
        const SponsorPlacement(),
        for (final challenge in [
          ('Move 150 minutes', 'A week of movement, at your pace.'),
          ('Weekend explorer', 'Record an outdoor activity this weekend.'),
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

  Widget _postCard(BuildContext context,
      {required String id,
      required String author,
      required String subtitle,
      required String message,
      required int baseLikes,
      bool withImage = false}) {
    final isLiked = liked.contains(id);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: aurora.withValues(alpha: .2),
            child: Text(author.characters.first,
                style: const TextStyle(
                    color: aurora, fontWeight: FontWeight.w800)),
          ),
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
            labels: const ['Challenges', 'Competitions'],
            selected: subTab,
            onChanged: (i) => setState(() => subTab = i)),
      ),
      Expanded(
        child: ListView(padding: pagePadding, children: [
          if (subTab == 1) ...[
            AppCard(
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fitness_center),
                    title: const Text('Custom fitness challenges'),
                    subtitle: const Text(
                        'Create a test, invite followers and record results'),
                    onTap: () => openChallenges(context))),
            _BiggestLoserCard(
              onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SubPage(
                      title: 'Biggest Loser',
                      child: ListView(
                          padding: pagePadding,
                          children: const [BiggestLoserCompetition()])))),
            ),
            dailyQuest,
          ] else ...[
            AppCard(
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('My fitness challenges'),
                    subtitle: const Text(
                        'Create military, CrossFit-style or custom tests'),
                    onTap: () => openChallenges(context))),
            dailyQuest,
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
  double? startingWeight;
  double? currentWeight;
  bool joined = false;
  final start = TextEditingController();
  final current = TextEditingController();

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
      if (startingWeight != null) {
        start.text = startingWeight!.toStringAsFixed(1);
      }
      if (currentWeight != null) {
        current.text = currentWeight!.toStringAsFixed(1);
      }
    });
  }

  Future<void> _save() async {
    final a = double.tryParse(start.text.replaceAll(',', '.'));
    final b = double.tryParse(current.text.replaceAll(',', '.'));
    if (a == null ||
        !a.isFinite ||
        (current.text.trim().isNotEmpty &&
            (b == null || !b.isFinite || b <= 0 || b > 500)) ||
        a <= 0 ||
        a > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid weights in kilograms.')));
      return;
    }
    final prefs = await OfflineStore.getInstance();
    await prefs.putAll({'bl_joined': true, 'bl_start': a, 'bl_current': b});
    if (!mounted) return;
    setState(() {
      joined = true;
      startingWeight = a;
      currentWeight = b;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weigh-in saved on this device.')));
  }

  @override
  void dispose() {
    start.dispose();
    current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (startingWeight != null && currentWeight != null)
        ? (startingWeight! - currentWeight!) / startingWeight! * 100
        : 0.0;
    final standings = <(String, double)>[
      ('Alex (demo)', 5.4),
      ('Sam (demo)', 3.8),
      if (joined && currentWeight != null) ('You', percent),
      ('Morgan (demo)', 1.9),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
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
                  helperText: 'Optional — add your next weigh-in later')),
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
          const SizedBox(height: 16),
          const Text('Leaderboard • demo',
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
          const StepTrackingCard(),
          const AdPreferences(),
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
                    : '${delta <= 0 ? '▾' : '▴'} ${delta.abs().toStringAsFixed(1)} kg',
                extraColor: delta != null && delta <= 0 ? aurora : null,
                onTap: _openWeight,
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
            20, 10, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
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
  String? locationMessage;
  StreamSubscription<Position>? subscription;
  Timer? timer;
  final stopwatch = Stopwatch();
  final route = <({double latitude, double longitude})>[];
  double distanceMeters = 0;
  DateTime? startedAt;

  @override
  void dispose() {
    timer?.cancel();
    unawaited(subscription?.cancel());
    stopwatch.stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      starting = true;
      locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          starting = false;
          locationMessage = 'Turn on location services to record a route.';
        });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          starting = false;
          locationMessage = permission == LocationPermission.deniedForever
              ? 'Location access is blocked. Enable it in system settings to record GPS.'
              : 'Location permission is needed to record your route.';
        });
        return;
      }
      startedAt = DateTime.now();
      stopwatch
        ..reset()
        ..start();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_onPosition, onError: (Object error) {
        if (mounted) {
          setState(() => locationMessage = 'GPS update failed: $error');
        }
      });
      setState(() {
        starting = false;
        recording = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          starting = false;
          locationMessage = 'Could not start GPS recording: $error';
        });
      }
    }
  }

  void _onPosition(Position position) {
    if (position.accuracy > 40) return;
    final point = (latitude: position.latitude, longitude: position.longitude);
    if (route.isNotEmpty) {
      final previous = route.last;
      final segment = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
      if (segment > 0 && segment < 100) distanceMeters += segment;
    }
    route.add(point);
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (route.length < 2) {
      setState(() => locationMessage =
          'Wait for GPS to record at least two route points before saving.');
      return;
    }
    timer?.cancel();
    timer = null;
    await subscription?.cancel();
    subscription = null;
    stopwatch.stop();
    final workout = Workout(
      activity,
      (stopwatch.elapsed.inSeconds / 60).ceil().clamp(1, 1440),
      startedAt ?? DateTime.now(),
      distanceKm: distanceMeters / 1000,
      route: List.of(route),
    );
    if (mounted) Navigator.of(context).pop(workout);
  }

  String get elapsed {
    final duration = stopwatch.elapsed;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
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
              Container(
                height: 150,
                decoration: BoxDecoration(
                    color: surfaceOf(context),
                    border: Border.all(color: lineOf(context)),
                    borderRadius: BorderRadius.circular(14)),
                child: route.isEmpty
                    ? const Center(
                        child: Text('Route preview appears when GPS connects'))
                    : CustomPaint(
                        painter: _RoutePainter(route, aurora),
                        child: const SizedBox.expand()),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _RecorderMetric(elapsed, 'TIME'),
                _RecorderMetric(
                    '${(distanceMeters / 1000).toStringAsFixed(2)} km',
                    'DISTANCE'),
                _RecorderMetric('${route.length}', 'GPS POINTS'),
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('Finish')),
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
                        starting ? 'Connecting to GPS…' : 'Start recording')),
              const SizedBox(height: 6),
              Text(
                  'GPS runs only while this screen is open. Routes save offline and sync privately to your account when connected.',
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

class _RoutePainter extends CustomPainter {
  final List<({double latitude, double longitude})> points;
  final Color color;
  const _RoutePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minLat =
        points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat =
        points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLon =
        points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLon =
        points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    final latRange = (maxLat - minLat).abs();
    final lonRange = (maxLon - minLon).abs();
    final scale = (latRange > lonRange ? latRange : lonRange);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = size.width *
          (0.12 + (point.longitude - minLon) / (scale == 0 ? 1 : scale) * 0.76);
      final y = size.height *
          (0.88 - (point.latitude - minLat) / (scale == 0 ? 1 : scale) * 0.76);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points.length != points.length || oldDelegate.color != color;
}
