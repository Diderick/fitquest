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

/// Re-renders pixels into a small PNG, excluding the source's location/EXIF metadata.
Future<Uint8List> prepareProfilePhoto(Uint8List input) async {
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
        final side = math.min(image.width, image.height).toDouble();
        canvas.drawImageRect(
            image,
            Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2,
                side, side),
            const Rect.fromLTWH(0, 0, 256, 256),
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
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 80,
          requestFullMetadata: false);
      final bytes = selected == null
          ? null
          : await prepareProfilePhoto(await selected.readAsBytes());
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
                        value: 'gallery', child: Text('Choose photo')),
                    if (!kIsWeb &&
                        [TargetPlatform.android, TargetPlatform.iOS]
                            .contains(defaultTargetPlatform))
                      const PopupMenuItem(
                          value: 'camera', child: Text('Take photo')),
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

class ProfileGenderSelector extends StatelessWidget {
  const ProfileGenderSelector({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: OfflineStore.instance,
      builder: (context, _) {
        final store = OfflineStore.instance;
        final scope = store.scope;
        final gender = store.getString('profile_gender') ?? '';
        return DropdownButtonFormField<String>(
            key: ValueKey('$scope:$gender'),
            initialValue: gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not set')),
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(value: 'female', child: Text('Female')),
              DropdownMenuItem(value: 'other', child: Text('Other'))
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
