import 'package:flutter/material.dart';
import 'exercise_art.dart';

class ExerciseGuidePage extends StatelessWidget {
  final String title;
  final List<Exercise> exercises;
  const ExerciseGuidePage(
      {super.key, required this.title, required this.exercises});

  Widget _list(BuildContext context, String heading, List<String> items,
      {bool numbered = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(heading, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(numbered ? '${i + 1}. ${items[i]}' : '• ${items[i]}'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Tap an exercise for setup, step-by-step form and common mistakes. Start light, learn the movement first, and stop if anything hurts.'),
        const SizedBox(height: 12),
        for (final e in exercises)
          Card(
            child: ExpansionTile(
              leading: Icon(
                  e.lifting ? Icons.fitness_center : Icons.accessibility_new),
              title: Text(e.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${e.start}\n${e.muscles}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Equipment: ${e.equipment}'),
                const SizedBox(height: 8),
                ExerciseAnimation(name: e.name),
                _list(context, 'Setup', e.setup),
                _list(context, 'How to do it', e.steps, numbered: true),
                _list(context, 'Form cues', e.cues),
                _list(context, 'Avoid', e.mistakes),
              ],
            ),
          ),
      ]),
    );
  }
}

class Exercise {
  final String name;
  final String muscles;
  final String equipment;
  final String start;
  final List<String> setup;
  final List<String> steps;
  final List<String> cues;
  final List<String> mistakes;
  final bool lifting;
  const Exercise({
    required this.name,
    required this.muscles,
    required this.equipment,
    required this.start,
    required this.setup,
    required this.steps,
    required this.cues,
    required this.mistakes,
    this.lifting = false,
  });
}

const exerciseLibrary = <String, Exercise>{
  'squat': Exercise(
    name: 'Bodyweight squat',
    muscles: 'Quads, glutes, core',
    equipment: 'None',
    start: '3 x 10-15 reps',
    setup: [
      'Stand with feet shoulder-width apart, toes turned out slightly.',
      'Hold your arms out in front for balance.',
    ],
    steps: [
      'Brace your core and take a breath in.',
      'Push your hips back and bend your knees at the same time.',
      'Lower until your thighs are about parallel to the floor.',
      'Drive through your whole foot to stand back up and squeeze your glutes.',
    ],
    cues: [
      'Keep your chest tall and your weight over mid-foot.',
      'Knees track in line with your toes.',
    ],
    mistakes: [
      'Knees caving inward.',
      'Heels lifting off the floor.',
      'Rounding the lower back at the bottom.',
    ],
  ),
  'pushup': Exercise(
    name: 'Push-up',
    muscles: 'Chest, shoulders, triceps, core',
    equipment: 'None',
    start: '3 x 6-12 reps (use an incline if needed)',
    setup: [
      'Place hands slightly wider than your shoulders, directly under them.',
      'Extend your legs back so your body forms a straight line.',
    ],
    steps: [
      'Tighten your core and glutes.',
      'Lower your chest toward the floor with elbows about 45 degrees from your body.',
      'Stop just above the floor.',
      'Press the floor away until your arms are straight.',
    ],
    cues: [
      'Think of your body as one rigid plank.',
      'Keep your neck neutral and eyes on the floor ahead.',
    ],
    mistakes: [
      'Hips sagging or piking up.',
      'Elbows flaring straight out to the sides.',
      'Only doing half reps.',
    ],
  ),
  'incline_pushup': Exercise(
    name: 'Incline push-up',
    muscles: 'Chest, shoulders, triceps',
    equipment: 'Bench, sturdy table or wall',
    start: '3 x 8-12 reps',
    setup: [
      'Place your hands on a stable raised surface, shoulder-width apart.',
      'Step your feet back until your body is in a straight line.',
    ],
    steps: [
      'Brace your core.',
      'Bend your elbows and lower your chest to the edge.',
      'Press back up to straight arms.',
    ],
    cues: [
      'The lower the surface, the harder it gets.',
      'Keep your body straight from head to heels.',
    ],
    mistakes: [
      'Letting your hips drop.',
      'Shrugging your shoulders up to your ears.',
    ],
  ),
  'lunge': Exercise(
    name: 'Forward lunge',
    muscles: 'Quads, glutes, hamstrings',
    equipment: 'None (add dumbbells to progress)',
    start: '3 x 8-10 reps per leg',
    setup: [
      'Stand tall with feet hip-width apart and hands on your hips.',
    ],
    steps: [
      'Step forward with one foot in a long, controlled stride.',
      'Lower until both knees are bent to about 90 degrees.',
      'Push through the front heel to return to standing.',
      'Repeat on the other leg.',
    ],
    cues: [
      'Torso stays upright.',
      'Front knee stays over the middle of your foot.',
    ],
    mistakes: [
      'Taking too short a step so the knee shoots past the toes.',
      'Back knee slamming into the floor.',
    ],
  ),
  'reverse_lunge': Exercise(
    name: 'Reverse lunge',
    muscles: 'Glutes, quads, hamstrings',
    equipment: 'None (add dumbbells to progress)',
    start: '3 x 8-10 reps per leg',
    setup: [
      'Stand tall with feet hip-width apart.',
    ],
    steps: [
      'Step one foot back and lower your back knee toward the floor.',
      'Keep your front shin vertical and your weight on the front heel.',
      'Push through the front foot to return to standing.',
    ],
    cues: [
      'Easier on the knees than a forward lunge.',
      'Move slowly down and drive up with control.',
    ],
    mistakes: [
      'Leaning forward from the waist.',
      'Letting the front knee cave inward.',
    ],
  ),
  'split_squat': Exercise(
    name: 'Split squat',
    muscles: 'Quads, glutes',
    equipment: 'None (add dumbbells to progress)',
    start: '3 x 8-10 reps per leg',
    setup: [
      'Take a long staggered stance with your back heel lifted.',
      'Keep your feet planted for the whole set.',
    ],
    steps: [
      'Lower straight down until the back knee almost touches the floor.',
      'Keep your front foot flat and your torso upright.',
      'Drive up through the front foot.',
    ],
    cues: [
      'Think down and up, not forward and back.',
      'Hold onto a wall or rack if balance is a challenge.',
    ],
    mistakes: [
      'Stance too short, which pushes the knee over the toes.',
      'Pushing off the back foot instead of the front.',
    ],
  ),
  'row': Exercise(
    name: 'Dumbbell row',
    muscles: 'Lats, upper back, biceps',
    equipment: 'Dumbbell and bench',
    start: '3 x 8-12 reps per arm',
    setup: [
      'Place one hand and the same-side knee on a bench.',
      'Hold a dumbbell in the other hand with your arm hanging straight down.',
      'Keep your back flat and parallel to the floor.',
    ],
    steps: [
      'Pull the dumbbell toward your hip, leading with your elbow.',
      'Pause briefly at the top and squeeze your shoulder blade back.',
      'Lower slowly until your arm is straight.',
    ],
    cues: [
      'Pull with your back, not your arm.',
      'Keep your neck in line with your spine.',
    ],
    mistakes: [
      'Twisting your torso to heave the weight up.',
      'Shrugging the shoulder toward your ear.',
    ],
    lifting: true,
  ),
  'inverted_row': Exercise(
    name: 'Inverted row',
    muscles: 'Upper back, lats, biceps',
    equipment: 'Low bar, rings or sturdy table',
    start: '3 x 6-10 reps',
    setup: [
      'Lie under a bar set at about hip height and grip it just wider than your shoulders.',
      'Walk your feet forward so your body is straight, heels on the floor.',
    ],
    steps: [
      'Squeeze your shoulder blades together.',
      'Pull your chest toward the bar.',
      'Lower with control until your arms are straight.',
    ],
    cues: [
      'Keep your body in a straight line throughout.',
      'Bend your knees to make it easier.',
    ],
    mistakes: [
      'Hips dropping toward the floor.',
      'Leading with your chin instead of your chest.',
    ],
  ),
  'plank': Exercise(
    name: 'Plank',
    muscles: 'Abs, core, shoulders',
    equipment: 'None',
    start: '3 x 30-45 seconds',
    setup: [
      'Place your forearms on the floor with elbows directly under your shoulders.',
      'Extend your legs behind you on your toes.',
    ],
    steps: [
      'Squeeze your glutes and brace your abs.',
      'Hold a straight line from head to heels.',
      'Breathe steadily and stop when your form breaks.',
    ],
    cues: [
      'Imagine pulling your elbows toward your toes.',
      'Look at the floor between your hands.',
    ],
    mistakes: [
      'Hips sagging or rising too high.',
      'Holding your breath.',
    ],
  ),
  'side_plank': Exercise(
    name: 'Side plank',
    muscles: 'Obliques, glutes, shoulders',
    equipment: 'None',
    start: '3 x 20-30 seconds per side',
    setup: [
      'Lie on your side with your elbow under your shoulder.',
      'Stack or stagger your feet.',
    ],
    steps: [
      'Lift your hips until your body is in a straight line.',
      'Hold, breathing steadily.',
      'Lower with control and switch sides.',
    ],
    cues: [
      'Push your forearm into the floor.',
      'Keep your hips stacked, not rolling forward.',
    ],
    mistakes: [
      'Hips dropping toward the floor.',
      'Rotating your chest toward the floor.',
    ],
  ),
  'glute_bridge': Exercise(
    name: 'Glute bridge',
    muscles: 'Glutes, hamstrings',
    equipment: 'None',
    start: '3 x 12-15 reps',
    setup: [
      'Lie on your back with knees bent and feet flat, hip-width apart.',
      'Arms rest by your sides.',
    ],
    steps: [
      'Tighten your core and squeeze your glutes.',
      'Drive through your heels to lift your hips until your body forms a line from knees to shoulders.',
      'Pause for a second at the top, then lower slowly.',
    ],
    cues: [
      'Tuck your ribs down so you do not arch your back.',
      'Push through your heels.',
    ],
    mistakes: [
      'Overarching the lower back at the top.',
      'Pushing up through your toes.',
    ],
  ),
  'dead_bug': Exercise(
    name: 'Dead bug',
    muscles: 'Deep abs, hip flexors',
    equipment: 'None',
    start: '3 x 8 reps per side',
    setup: [
      'Lie on your back with arms pointing to the ceiling.',
      'Lift your knees over your hips, bent to 90 degrees.',
    ],
    steps: [
      'Press your lower back lightly into the floor.',
      'Slowly extend your opposite arm and leg away from each other.',
      'Return to the start and switch sides.',
    ],
    cues: [
      'Move slowly and exhale as you extend.',
      'Only go as far as your back stays flat.',
    ],
    mistakes: [
      'Letting the lower back arch off the floor.',
      'Rushing the reps.',
    ],
  ),
  'deadlift': Exercise(
    name: 'Barbell deadlift',
    muscles: 'Glutes, hamstrings, back, grip',
    equipment: 'Barbell and plates',
    start: '3 x 5 reps, start light and learn the hinge first',
    lifting: true,
    setup: [
      'Stand with the bar over mid-foot and feet hip-width apart.',
      'Hinge at the hips and grip the bar just outside your legs.',
      'Bring your shins to the bar, lift your chest and flatten your back.',
      'Pull the slack out of the bar so your arms are straight and your lats are tight.',
    ],
    steps: [
      'Take a big breath and brace your core hard.',
      'Push the floor away with your legs while keeping the bar close to your body.',
      'When the bar passes your knees, drive your hips forward to stand tall.',
      'Lower by pushing your hips back first, then bending your knees once the bar passes them.',
    ],
    cues: [
      'Keep the bar in contact with your legs the whole way.',
      'Neutral spine from head to hips.',
    ],
    mistakes: [
      'Rounding your lower back.',
      'Jerking the bar off the floor.',
      'Hips shooting up before the bar moves.',
    ],
  ),
  'back_squat': Exercise(
    name: 'Barbell back squat',
    muscles: 'Quads, glutes, core, back',
    equipment: 'Barbell, squat rack, plates',
    start: '3 x 5 reps with an empty bar, then add weight slowly',
    lifting: true,
    setup: [
      'Set the bar in the rack at about mid-chest height.',
      'Step under it and rest the bar across your upper back, not your neck.',
      'Grip the bar just outside your shoulders and un-rack it.',
      'Take two steps back with feet shoulder-width apart, toes slightly out.',
    ],
    steps: [
      'Breathe in and brace your core.',
      'Sit down and back, pushing your knees out over your toes.',
      'Lower until your hips are at or just below knee level.',
      'Drive up through your whole foot and exhale as you stand.',
    ],
    cues: [
      'Keep your chest up and eyes forward.',
      'Use safety bars or a spotter when going heavy.',
    ],
    mistakes: [
      'Knees collapsing inward.',
      'Rounding your back at the bottom.',
      'Lifting your heels.',
    ],
  ),
  'bench_press': Exercise(
    name: 'Barbell bench press',
    muscles: 'Chest, shoulders, triceps',
    equipment: 'Barbell, bench, rack, plates',
    start: '3 x 5-8 reps, always use a spotter or safety arms',
    lifting: true,
    setup: [
      'Lie with your eyes under the bar and feet flat on the floor.',
      'Squeeze your shoulder blades together and keep them pinned to the bench.',
      'Grip the bar slightly wider than shoulder-width with wrists stacked over your elbows.',
    ],
    steps: [
      'Un-rack the bar and hold it over your chest with straight arms.',
      'Lower it under control to touch your mid-chest, elbows about 45 degrees from your body.',
      'Press it back up and slightly toward your face until your arms are straight.',
    ],
    cues: [
      'Keep a small arch and your glutes on the bench.',
      'Control the descent, do not bounce the bar.',
    ],
    mistakes: [
      'Flaring elbows straight out.',
      'Lifting your hips off the bench.',
      'Pressing without a spotter or safeties.',
    ],
  ),
  'overhead_press': Exercise(
    name: 'Overhead press',
    muscles: 'Shoulders, triceps, upper chest, core',
    equipment: 'Barbell or dumbbells',
    start: '3 x 5-8 reps',
    lifting: true,
    setup: [
      'Hold the bar at shoulder height with your grip just outside your shoulders.',
      'Stand with feet hip-width apart, glutes and abs tight.',
      'Keep your elbows slightly in front of the bar.',
    ],
    steps: [
      'Press the bar straight up, moving your head back slightly to clear it.',
      'Lock your arms out with the bar over your mid-foot and push your head through.',
      'Lower the bar back to your shoulders with control.',
    ],
    cues: [
      'Squeeze your glutes to avoid leaning back.',
      'Bar path is a straight vertical line.',
    ],
    mistakes: [
      'Arching your lower back.',
      'Pressing the bar out in front of you.',
    ],
  ),
  'barbell_row': Exercise(
    name: 'Barbell bent-over row',
    muscles: 'Lats, upper back, biceps, lower back',
    equipment: 'Barbell and plates',
    start: '3 x 6-10 reps',
    lifting: true,
    setup: [
      'Hold the bar with an overhand grip just outside your knees.',
      'Hinge forward until your torso is about 45 degrees to the floor.',
      'Keep your back flat and knees slightly bent.',
    ],
    steps: [
      'Pull the bar toward your lower ribs, driving your elbows back.',
      'Squeeze your shoulder blades together at the top.',
      'Lower the bar slowly until your arms are straight.',
    ],
    cues: [
      'Keep your torso still. Row with your back, not your momentum.',
      'Neck stays in line with your spine.',
    ],
    mistakes: [
      'Standing up as you pull.',
      'Rounding your lower back.',
    ],
  ),
};

/// Exercises shown under each strength session, keyed by `plan|session`.
const sessionExercises = <String, List<String>>{
  'Strength Builder|Power session': [
    'squat',
    'pushup',
    'lunge',
    'inverted_row',
    'plank',
  ],
  'Strength Builder|Barbell lifting day': [
    'back_squat',
    'bench_press',
    'barbell_row',
    'overhead_press',
    'deadlift',
  ],
  'Swim Endurance|Dryland strength': [
    'glute_bridge',
    'squat',
    'pushup',
    'side_plank',
  ],
  'Ride Strong|Strength day': [
    'split_squat',
    'row',
    'pushup',
    'dead_bug',
  ],
  'Balanced Fitness|Strength day': [
    'squat',
    'pushup',
    'lunge',
    'row',
    'plank',
    'glute_bridge',
  ],
  'Fat Loss Starter (4 weeks)|Home strength circuit': [
    'squat',
    'incline_pushup',
    'reverse_lunge',
    'plank',
  ],
};
