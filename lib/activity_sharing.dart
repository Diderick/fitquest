import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'offline_store.dart';

class ActivityShareData {
  final String activity, notes;
  final int minutes;
  final double? distanceKm;
  final DateTime date;
  final List<({double latitude, double longitude})> route;
  const ActivityShareData(
      {required this.activity,
      required this.minutes,
      required this.date,
      this.distanceKm,
      this.notes = '',
      this.route = const []});
  String get dateLabel =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String summary({bool includeNotes = false}) => [
        '$activity on FitQuest',
        '${distanceKm == null ? '' : '${distanceKm!.toStringAsFixed(2)} km · '}$minutes minutes · $dateLabel',
        if (includeNotes && notes.trim().isNotEmpty) notes.trim(),
        '#FitQuest',
      ].join('\n');
}

/// Renders a self-contained image offline; no remote upload or location URL.
Future<Uint8List> activityCard(ActivityShareData data,
    {bool includeRoute = false, bool includeNotes = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(1080, 1350);
  canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1424), Color(0xFF123C48), Color(0xFF0B1424)],
        ).createShader(Offset.zero & size));
  void text(String value, double x, double y, double fontSize,
      {Color color = Colors.white,
      FontWeight weight = FontWeight.w400,
      double width = 936,
      int maxLines = 2}) {
    final painter = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
                fontFamily: 'Roboto',
                color: color,
                fontSize: fontSize,
                fontWeight: weight,
                height: 1.15)),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…')
      ..layout(maxWidth: width);
    painter.paint(canvas, Offset(x, y));
  }

  text('FITQUEST', 72, 66, 44,
      color: const Color(0xFF20BBAE), weight: FontWeight.w800);
  text(data.dateLabel, 72, 135, 30, color: const Color(0xFFB8CCD2));
  text(data.activity, 72, 202, 88, weight: FontWeight.w800);
  final distance = data.distanceKm;
  text(distance == null ? '${data.minutes}' : distance.toStringAsFixed(2), 72,
      342, 116,
      weight: FontWeight.w800);
  text(distance == null ? 'MINUTES' : 'KILOMETRES', 78, 478, 28,
      color: const Color(0xFF9ED8D3));
  if (distance != null) {
    text('${data.minutes} MIN', 660, 385, 45,
        weight: FontWeight.w700, width: 350);
  }
  const box = Rect.fromLTWH(72, 568, 936, 520);
  canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(32)),
      Paint()..color = const Color(0xFF102235));
  final route = data.route
      .where((p) => p.latitude.isFinite && p.longitude.isFinite)
      .toList();
  if (includeRoute && route.length > 1) {
    final latitudes = route.map((p) => p.latitude),
        longitudes = route.map((p) => p.longitude);
    final minLat = latitudes.reduce(math.min),
        maxLat = latitudes.reduce(math.max);
    final minLon = longitudes.reduce(math.min),
        maxLon = longitudes.reduce(math.max);
    final lonScale = math
        .cos(((minLat + maxLat) / 2) * math.pi / 180)
        .abs()
        .clamp(0.01, 1.0);
    final width = (maxLon - minLon) * lonScale, height = maxLat - minLat;
    final scale = math.min(
        800 / math.max(width, 0.000001), 350 / math.max(height, 0.000001));
    final left = box.center.dx - width * scale / 2,
        top = box.center.dy - height * scale / 2;
    final path = Path();
    for (var i = 0; i < route.length; i++) {
      final x = left + (route[i].longitude - minLon) * lonScale * scale;
      final y = top + (maxLat - route[i].latitude) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF20BBAE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    text('ROUTE SKETCH', 108, 608, 24, color: const Color(0xFFB8CCD2));
  } else {
    text('EVERY\nSESSION\nCOUNTS.', 126, 668, 78,
        weight: FontWeight.w800, width: 800, maxLines: 3);
  }
  if (includeNotes && data.notes.isNotEmpty) {
    text(data.notes, 72, 1125, 30, width: 936, maxLines: 3);
  } else {
    text('Move. Train. Level up.', 72, 1150, 38, weight: FontWeight.w600);
  }
  text('Shared with FitQuest', 72, 1270, 25, color: const Color(0xFF9BB8C2));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1080, 1350);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not render activity image.');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class ActivitySharePage extends StatefulWidget {
  final ActivityShareData activity;
  const ActivitySharePage({super.key, required this.activity});
  @override
  State<ActivitySharePage> createState() => _ActivitySharePageState();
}

class _ActivitySharePageState extends State<ActivitySharePage> {
  bool includeRoute = false, includeNotes = false, busy = false;
  late Future<Uint8List> preview = activityCard(widget.activity);
  void refresh() => setState(() => preview = activityCard(widget.activity,
      includeRoute: includeRoute, includeNotes: includeNotes));
  Rect? origin(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Future<void> share(BuildContext context, bool image) async {
    if (busy) return;
    final anchor = origin(context);
    setState(() => busy = true);
    try {
      final bytes = image ? await preview : null;
      if (!mounted) return;
      final result = await SharePlus.instance.share(ShareParams(
        text:
            image ? null : widget.activity.summary(includeNotes: includeNotes),
        subject: '${widget.activity.activity} on FitQuest',
        sharePositionOrigin: anchor,
        files: image ? [XFile.fromData(bytes!, mimeType: 'image/png')] : null,
        fileNameOverrides:
            image ? ['fitquest-${widget.activity.dateLabel}.png'] : null,
      ));
      if (mounted && result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
            content: Text(
                'Sharing is unavailable here. Try Copy summary instead.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
            content: Text(
                'Could not open sharing. Try Copy summary or another installed app.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> postToFeed() async {
    setState(() => busy = true);
    try {
      final store = await OfflineStore.getInstance();
      final posts = store.getStringList('community_posts') ?? [];
      await store.setStringList('community_posts',
          [widget.activity.summary(includeNotes: includeNotes), ...posts]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(store.signedIn
                ? 'Saved to your FitQuest feed. Followers will see it after sync.'
                : 'Saved locally. Create an account to share with followers.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not save the post on this device. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Share activity')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Choose WhatsApp, Facebook or another installed app from your phone’s share sheet. Share the image card, then copy the summary if you want a caption. Facebook may not accept prefilled text.'),
        const SizedBox(height: 12),
        FutureBuilder<Uint8List>(
            future: preview,
            builder: (context, snapshot) => snapshot.hasData
                ? SizedBox(
                    height: 360,
                    child: Image.memory(snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: 'Activity share card preview'))
                : SizedBox(
                    height: 360,
                    child: Center(
                        child: snapshot.hasError
                            ? const Text(
                                'Could not render the card. Text sharing is still available.')
                            : const CircularProgressIndicator()))),
        if (widget.activity.route.length > 1)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include route sketch'),
              subtitle: const Text(
                  'Off by default. A route sketch may reveal locations you visit.'),
              value: includeRoute,
              onChanged: busy
                  ? null
                  : (value) {
                      includeRoute = value;
                      refresh();
                    }),
        if (widget.activity.notes.isNotEmpty)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include activity notes'),
              value: includeNotes,
              onChanged: busy
                  ? null
                  : (value) {
                      includeNotes = value;
                      refresh();
                    }),
        const Text(
            'Only this activity’s summary is shared. Your account details, body weight and nutrition are not included.'),
        const SizedBox(height: 12),
        Builder(
            builder: (buttonContext) => FilledButton.icon(
                onPressed: busy ? null : () => share(buttonContext, true),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share image card'))),
        Builder(
            builder: (buttonContext) => OutlinedButton.icon(
                onPressed: busy ? null : () => share(buttonContext, false),
                icon: const Icon(Icons.text_snippet_outlined),
                label: const Text('Share text summary'))),
        TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(
                        text: widget.activity
                            .summary(includeNotes: includeNotes)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Activity summary copied.')));
                    }
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy summary')),
        const Divider(),
        OutlinedButton.icon(
            onPressed: busy ? null : postToFeed,
            icon: const Icon(Icons.dynamic_feed_outlined),
            label: const Text('Post summary to FitQuest feed')),
      ]));
}
