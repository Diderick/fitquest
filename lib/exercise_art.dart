import 'package:flutter/material.dart';

/// Side-view stick figure joints on a 120 x 90 canvas (floor at y = 70).
class Pose {
  final Offset head, shoulder, hip, elbow, hand, knee, foot;
  final Offset? knee2, foot2;
  const Pose(this.head, this.shoulder, this.hip, this.elbow, this.hand,
      this.knee, this.foot,
      {this.knee2, this.foot2});

  static Pose lerp(Pose a, Pose b, double t) {
    Offset l(Offset x, Offset y) => Offset.lerp(x, y, t)!;
    return Pose(
      l(a.head, b.head),
      l(a.shoulder, b.shoulder),
      l(a.hip, b.hip),
      l(a.elbow, b.elbow),
      l(a.hand, b.hand),
      l(a.knee, b.knee),
      l(a.foot, b.foot),
      knee2: l(a.knee2 ?? a.knee, b.knee2 ?? b.knee),
      foot2: l(a.foot2 ?? a.foot, b.foot2 ?? b.foot),
    );
  }
}

class ExerciseArt {
  final Pose start, end;
  final List<(Offset, Offset)> props;
  final bool weight;
  const ExerciseArt(this.start, this.end,
      {this.props = const [], this.weight = false});
}

Offset o(double x, double y) => Offset(x, y);

final _standing = Pose(
    o(60, 9), o(60, 16), o(60, 38), o(62, 28), o(64, 40), o(60, 54), o(60, 70));

final _benchProps = [
  (o(18, 58), o(96, 58)),
  (o(24, 58), o(24, 70)),
  (o(90, 58), o(90, 70)),
];

final exerciseArt = <String, ExerciseArt>{
  'Bodyweight squat': ExerciseArt(
    Pose(o(60, 9), o(60, 16), o(60, 38), o(66, 22), o(76, 20), o(60, 54),
        o(60, 70)),
    Pose(o(60, 27), o(56, 34), o(42, 54), o(66, 36), o(76, 34), o(70, 54),
        o(62, 70)),
  ),
  'Push-up': ExerciseArt(
    Pose(o(88, 35), o(80, 38), o(52, 50), o(80, 54), o(80, 70), o(32, 59),
        o(12, 68)),
    Pose(o(88, 58), o(80, 60), o(52, 63), o(68, 65), o(80, 70), o(32, 66),
        o(12, 68)),
  ),
  'Incline push-up': ExerciseArt(
    Pose(o(86, 25), o(78, 28), o(52, 44), o(84, 40), o(84, 50), o(32, 56),
        o(12, 68)),
    Pose(o(88, 37), o(80, 40), o(52, 52), o(72, 48), o(84, 50), o(32, 60),
        o(12, 68)),
    props: [(o(82, 50), o(112, 50)), (o(108, 50), o(108, 70))],
  ),
  'Forward lunge': ExerciseArt(
    _standing,
    Pose(o(58, 19), o(58, 26), o(58, 48), o(66, 34), o(58, 42), o(80, 50),
        o(80, 70),
        knee2: o(40, 62), foot2: o(28, 70)),
  ),
  'Reverse lunge': ExerciseArt(
    _standing,
    Pose(o(58, 19), o(58, 26), o(58, 48), o(66, 34), o(58, 42), o(78, 50),
        o(78, 70),
        knee2: o(40, 62), foot2: o(30, 70)),
  ),
  'Split squat': ExerciseArt(
    Pose(o(56, 9), o(56, 16), o(56, 36), o(64, 26), o(56, 34), o(68, 52),
        o(72, 70),
        knee2: o(46, 54), foot2: o(34, 70)),
    Pose(o(56, 25), o(56, 32), o(56, 52), o(64, 40), o(56, 48), o(74, 54),
        o(72, 70),
        knee2: o(46, 64), foot2: o(34, 70)),
  ),
  'Dumbbell row': ExerciseArt(
    Pose(o(70, 28), o(62, 30), o(30, 34), o(62, 44), o(62, 56), o(30, 52),
        o(28, 70)),
    Pose(o(70, 28), o(62, 30), o(30, 34), o(44, 30), o(52, 38), o(30, 52),
        o(28, 70)),
    weight: true,
  ),
  'Inverted row': ExerciseArt(
    Pose(o(88, 54), o(80, 55), o(46, 61), o(82, 46), o(84, 36), o(30, 64),
        o(12, 68)),
    Pose(o(88, 38), o(80, 40), o(46, 54), o(76, 46), o(84, 36), o(30, 61),
        o(12, 68)),
    props: [(o(76, 36), o(98, 36)), (o(98, 36), o(98, 70))],
  ),
  'Plank': ExerciseArt(
    Pose(o(86, 45), o(78, 48), o(52, 58), o(78, 66), o(92, 68), o(32, 63),
        o(12, 68)),
    Pose(o(86, 45), o(78, 48), o(52, 56), o(78, 66), o(92, 68), o(32, 62),
        o(12, 68)),
  ),
  'Side plank': ExerciseArt(
    Pose(o(86, 38), o(78, 42), o(52, 58), o(78, 62), o(88, 68), o(32, 64),
        o(12, 68)),
    Pose(o(86, 36), o(78, 40), o(52, 52), o(78, 62), o(88, 68), o(32, 60),
        o(12, 68)),
  ),
  'Glute bridge': ExerciseArt(
    Pose(o(96, 66), o(86, 66), o(58, 66), o(76, 67), o(66, 68), o(42, 48),
        o(30, 70)),
    Pose(o(96, 66), o(86, 66), o(58, 50), o(76, 67), o(66, 68), o(38, 48),
        o(30, 70)),
  ),
  'Dead bug': ExerciseArt(
    Pose(o(88, 66), o(80, 66), o(50, 66), o(80, 50), o(80, 34), o(50, 44),
        o(28, 44),
        knee2: o(50, 44), foot2: o(28, 44)),
    Pose(o(88, 66), o(80, 66), o(50, 66), o(94, 58), o(106, 64), o(30, 58),
        o(12, 64),
        knee2: o(50, 44), foot2: o(28, 44)),
  ),
  'Barbell deadlift': ExerciseArt(
    Pose(o(76, 32), o(68, 36), o(44, 48), o(66, 50), o(63, 63), o(66, 54),
        o(60, 70)),
    Pose(o(60, 9), o(60, 16), o(58, 38), o(58, 28), o(59, 42), o(60, 54),
        o(60, 70)),
    weight: true,
  ),
  'Barbell back squat': ExerciseArt(
    Pose(o(60, 9), o(60, 16), o(60, 38), o(50, 24), o(58, 15), o(60, 54),
        o(60, 70)),
    Pose(o(62, 26), o(56, 32), o(40, 54), o(46, 40), o(54, 30), o(68, 54),
        o(60, 70)),
    weight: true,
  ),
  'Barbell bench press': ExerciseArt(
    Pose(o(82, 52), o(72, 54), o(45, 54), o(70, 40), o(70, 26), o(32, 44),
        o(28, 70)),
    Pose(o(82, 52), o(72, 54), o(45, 54), o(60, 50), o(70, 48), o(32, 44),
        o(28, 70)),
    props: _benchProps,
    weight: true,
  ),
  'Overhead press': ExerciseArt(
    Pose(o(60, 9), o(60, 16), o(60, 38), o(56, 26), o(62, 14), o(60, 54),
        o(60, 70)),
    Pose(o(60, 9), o(60, 16), o(60, 38), o(60, 6), o(60, -4), o(60, 54),
        o(60, 70)),
    weight: true,
  ),
  'Barbell bent-over row': ExerciseArt(
    Pose(o(68, 20), o(60, 24), o(44, 42), o(62, 38), o(62, 52), o(52, 54),
        o(48, 70)),
    Pose(o(68, 20), o(60, 24), o(44, 42), o(46, 34), o(56, 42), o(52, 54),
        o(48, 70)),
    weight: true,
  ),
};

/// Looping start-to-finish animation of an exercise, drawn in the app.
class ExerciseAnimation extends StatefulWidget {
  final String name;
  const ExerciseAnimation({super.key, required this.name});
  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  bool playing = true;

  @override
  void initState() {
    super.initState();
    controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void toggle() {
    setState(() => playing = !playing);
    if (playing) {
      controller.repeat(reverse: true);
    } else {
      controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final art = exerciseArt[widget.name];
    if (art == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: toggle,
      child: Semantics(
        label:
            '${widget.name} animation. Tap to ${playing ? 'pause' : 'play'}.',
        child: Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12)),
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => CustomPaint(
                    painter: _FigurePainter(
                        art,
                        Curves.easeInOut.transform(controller.value),
                        scheme.primary,
                        scheme.onSurface)),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 6,
              child: Text(playing ? 'Tap to pause' : 'Tap to play',
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  final ExerciseArt art;
  final double t;
  final Color accent, neutral;
  _FigurePainter(this.art, this.t, this.accent, this.neutral);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 120.0, h = 90.0;
    final scale =
        (size.width / w) < (size.height / h) ? size.width / w : size.height / h;
    canvas.translate(
        (size.width - w * scale) / 2, (size.height - h * scale) / 2);
    canvas.scale(scale);
    canvas.translate(0, 10);

    final soft = Paint()
      ..color = neutral.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(o(4, 70), o(116, 70), soft);
    for (final (a, b) in art.props) {
      canvas.drawLine(a, b, soft..strokeWidth = 3);
    }

    final p = Pose.lerp(art.start, art.end, t);
    final far = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final near = Paint()
      ..color = accent
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
        Path()
          ..moveTo(p.hip.dx, p.hip.dy)
          ..lineTo(p.knee2!.dx, p.knee2!.dy)
          ..lineTo(p.foot2!.dx, p.foot2!.dy),
        far);
    canvas.drawLine(p.shoulder, p.hip, near);
    canvas.drawPath(
        Path()
          ..moveTo(p.hip.dx, p.hip.dy)
          ..lineTo(p.knee.dx, p.knee.dy)
          ..lineTo(p.foot.dx, p.foot.dy),
        near);
    canvas.drawPath(
        Path()
          ..moveTo(p.shoulder.dx, p.shoulder.dy)
          ..lineTo(p.elbow.dx, p.elbow.dy)
          ..lineTo(p.hand.dx, p.hand.dy),
        near);
    canvas.drawCircle(p.head, 5.5, Paint()..color = accent);
    if (art.weight) {
      canvas.drawCircle(
          p.hand,
          6,
          Paint()
            ..color = neutral.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      canvas.drawCircle(p.hand, 2, Paint()..color = neutral);
    }
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.t != t || old.art != art;
}
