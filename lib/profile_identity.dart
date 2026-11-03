import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'offline_store.dart';

Uint8List? decodeProfilePhoto(Object? raw) {
  if (raw is! String || raw.length > 409600) return null;
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

class SquareCropAdjustments {
  final double centerX;
  final double centerY;
  final double zoom;
  const SquareCropAdjustments(
      {this.centerX = 0.5, this.centerY = 0.5, this.zoom = 1});
}

Rect _squareCropRect(
    double width, double height, SquareCropAdjustments adjustments) {
  final zoom = adjustments.zoom.clamp(1.0, 4.0);
  final side = math.max(1.0, math.min(width, height) / zoom);
  final half = side / 2;
  final centerX =
      (adjustments.centerX.clamp(0.0, 1.0) * width).clamp(half, width - half);
  final centerY =
      (adjustments.centerY.clamp(0.0, 1.0) * height).clamp(half, height - half);
  return Rect.fromLTWH(centerX - half, centerY - half, side, side);
}

/// Re-renders pixels into a small PNG, excluding the source's location/EXIF metadata.
Future<Uint8List> prepareProfilePhoto(Uint8List input,
    {SquareCropAdjustments adjustments = const SquareCropAdjustments()}) async {
  if (input.length > 20 * 1024 * 1024) {
    throw StateError('Choose a photo smaller than 20 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(input);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale =
        math.min(1.0, 512 / math.max(descriptor.width, descriptor.height));
    final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()));
    try {
      final frame = await codec.getNextFrame();
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final image = frame.image;
        final source = _squareCropRect(
            image.width.toDouble(), image.height.toDouble(), adjustments);
        canvas.drawImageRect(image, source, const Rect.fromLTWH(0, 0, 256, 256),
            Paint()..filterQuality = FilterQuality.high);
        final picture = recorder.endRecording();
        final thumbnail = await picture.toImage(256, 256);
        try {
          final data =
              await thumbnail.toByteData(format: ui.ImageByteFormat.png);
          if (data == null || data.lengthInBytes > 300 * 1024) {
            throw StateError('Could not prepare this profile photo.');
          }
          return data.buffer.asUint8List();
        } finally {
          thumbnail.dispose();
          picture.dispose();
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> prepareActivityPhoto(Uint8List input) async {
  if (input.length > 25 * 1024 * 1024) {
    throw StateError('Choose a photo smaller than 25 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(input);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale =
        math.min(1.0, 1280 / math.max(descriptor.width, descriptor.height));
    final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()));
    try {
      final frame = await codec.getNextFrame();
      try {
        final image = frame.image;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            Paint()..filterQuality = FilterQuality.high);
        final picture = recorder.endRecording();
        final cleaned = await picture.toImage(image.width, image.height);
        try {
          final data = await cleaned.toByteData(format: ui.ImageByteFormat.png);
          if (data == null || data.lengthInBytes > 1500 * 1024) {
            throw StateError('Could not prepare this activity photo.');
          }
          return data.buffer.asUint8List();
        } finally {
          cleaned.dispose();
          picture.dispose();
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) {
  final decoded = ui.instantiateImageCodec(bytes);
  return decoded.then((codec) async {
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  });
}

class ProfilePhotoService {
  static bool _recovered = false;
  static Future<void> recover() async {
    if (_recovered ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _recovered = true;
    try {
      final store = await OfflineStore.getInstance();
      final scope = store.scope;
      final pending = store.getString('_profile_photo_pending') == scope;
      final result = await ImagePicker().retrieveLostData();
      if (!pending) {
        return; // Never attach another account's abandoned selection.
      }
      final files = result.files;
      final bytes = files != null && files.isNotEmpty
          ? await prepareProfilePhoto(await files.first.readAsBytes())
          : null;
      await store.putAll({
        if (bytes != null) 'profile_photo_v1': base64Encode(bytes),
        '_profile_photo_pending': null
      }, expectedScope: scope);
    } catch (_) {/* Keep the previous photo if recovery is unavailable. */}
  }
}

class ProfilePhotoButton extends StatefulWidget {
  const ProfilePhotoButton({super.key});
  @override
  State<ProfilePhotoButton> createState() => _ProfilePhotoButtonState();
}

class _ProfilePhotoButtonState extends State<ProfilePhotoButton> {
  bool busy = false;
  Future<void> choose(String action) async {
    final store = await OfflineStore.getInstance();
    final scope = store.scope;
    if (busy) return;
    setState(() => busy = true);
    try {
      if (action == 'remove') {
        await store.putAll({'profile_photo_v1': null}, expectedScope: scope);
        return;
      }
      await store
          .putAll({'_profile_photo_pending': scope}, expectedScope: scope);
      final selected = await ImagePicker().pickImage(
          source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 86,
          requestFullMetadata: false);
      Uint8List? bytes;
      if (selected != null && mounted) {
        final raw = await selected.readAsBytes();
        if (!mounted) return;
        final adjustments = await showModalBottomSheet<SquareCropAdjustments>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _ProfilePhotoAdjustSheet(input: raw));
        if (adjustments != null) {
          bytes = await prepareProfilePhoto(raw, adjustments: adjustments);
        }
      }
      await store.putAll({
        if (bytes != null) 'profile_photo_v1': base64Encode(bytes),
        '_profile_photo_pending': null
      }, expectedScope: scope);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message.toString()
                : 'Could not use this photo. Check camera or photo permissions and try another image.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) {
        final photo =
            decodeProfilePhoto(OfflineStore.instance.get('profile_photo_v1'));
        return Column(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<String>(
              tooltip: 'Profile photo',
              enabled: !busy,
              onSelected: choose,
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'gallery',
                        child: Text('Choose and adjust photo')),
                    if (!kIsWeb &&
                        [TargetPlatform.android, TargetPlatform.iOS]
                            .contains(defaultTargetPlatform))
                      const PopupMenuItem(
                          value: 'camera',
                          child: Text('Take and adjust photo')),
                    if (photo != null)
                      const PopupMenuItem(
                          value: 'remove', child: Text('Remove photo'))
                  ],
              child: Stack(children: [
                ClipOval(
                    child: SizedBox.square(
                        dimension: 80,
                        child: photo == null
                            ? const ColoredBox(
                                color: Color(0xFF1689F8),
                                child: Icon(Icons.person,
                                    color: Colors.white, size: 42))
                            : Image.memory(photo,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.person, size: 42)))),
                if (busy)
                  const Positioned.fill(child: CircularProgressIndicator()),
                const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                        radius: 13, child: Icon(Icons.camera_alt, size: 16))),
              ])),
          const SizedBox(height: 4),
          Text(photo == null ? 'Add photo' : 'Change photo',
              style: Theme.of(context).textTheme.bodySmall),
        ]);
      });
}

class _ProfilePhotoAdjustSheet extends StatefulWidget {
  final Uint8List input;
  const _ProfilePhotoAdjustSheet({required this.input});

  @override
  State<_ProfilePhotoAdjustSheet> createState() =>
      _ProfilePhotoAdjustSheetState();
}

class _ProfilePhotoAdjustSheetState extends State<_ProfilePhotoAdjustSheet> {
  late final Future<ui.Image> _imageFuture = _decodeUiImage(widget.input);
  double zoom = 1;
  double centerX = 0.5;
  double centerY = 0.5;

  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: FutureBuilder<ui.Image>(
            future: _imageFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Could not load this image.');
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()));
              }
              final image = snapshot.data!;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Adjust profile photo',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CustomPaint(
                    painter: _ProfileCropPreviewPainter(
                        image: image,
                        adjustments: SquareCropAdjustments(
                            centerX: centerX, centerY: centerY, zoom: zoom)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const SizedBox(width: 96, child: Text('Zoom')),
                  Expanded(
                      child: Slider(
                          min: 1,
                          max: 4,
                          value: zoom,
                          onChanged: (value) => setState(() => zoom = value))),
                ]),
                Row(children: [
                  const SizedBox(width: 96, child: Text('Horizontal')),
                  Expanded(
                      child: Slider(
                          min: 0,
                          max: 1,
                          value: centerX,
                          onChanged: (value) =>
                              setState(() => centerX = value))),
                ]),
                Row(children: [
                  const SizedBox(width: 96, child: Text('Vertical')),
                  Expanded(
                      child: Slider(
                          min: 0,
                          max: 1,
                          value: centerY,
                          onChanged: (value) =>
                              setState(() => centerY = value))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton(
                          onPressed: () => Navigator.pop(
                              context,
                              SquareCropAdjustments(
                                  centerX: centerX,
                                  centerY: centerY,
                                  zoom: zoom)),
                          child: const Text('Use photo'))),
                ]),
              ]);
            }),
      ));
}

class _ProfileCropPreviewPainter extends CustomPainter {
  final ui.Image image;
  final SquareCropAdjustments adjustments;
  const _ProfileCropPreviewPainter(
      {required this.image, required this.adjustments});

  @override
  void paint(Canvas canvas, Size size) {
    final src = _squareCropRect(
        image.width.toDouble(), image.height.toDouble(), adjustments);
    final dst = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(dst, const Radius.circular(24)),
        Paint()..color = const Color(0x22000000));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, const Radius.circular(24)));
    canvas.drawImageRect(
        image, src, dst, Paint()..filterQuality = FilterQuality.high);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfileCropPreviewPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.adjustments != adjustments;
}

class ProfileGenderSelector extends StatelessWidget {
  const ProfileGenderSelector({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) {
        final store = OfflineStore.instance;
        final scope = store.scope;
        final savedGender = store.getString('profile_gender') ?? '';
        final gender =
            savedGender == 'male' || savedGender == 'female' ? savedGender : '';
        return DropdownButtonFormField<String>(
            key: ValueKey('$scope:$gender'),
            initialValue: gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not set')),
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(value: 'female', child: Text('Female'))
            ],
            onChanged: (value) async {
              try {
                await store.putAll(
                    {'profile_gender': value == '' ? null : value},
                    expectedScope: scope);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Could not save gender. Please retry.')));
                }
              }
            });
      });
}
