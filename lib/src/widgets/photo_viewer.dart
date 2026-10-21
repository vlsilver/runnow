import 'package:flutter/material.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/storage_image.dart';

class StoragePhoto extends StatelessWidget {
  const StoragePhoto({
    required this.path,
    this.fit = BoxFit.cover,
    this.interactive = false,
    this.cacheWidth,
    this.cacheHeight,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final bool interactive;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final image = StorageImage(
      path: path,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
    if (!interactive) return image;
    return InteractiveViewer(minScale: 1, maxScale: 4, child: image);
  }
}

Future<void> showActivityPhotoViewer(
  BuildContext context,
  ActivityPhoto photo,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: StoragePhoto(
                path: photo.storagePath,
                fit: BoxFit.contain,
                interactive: true,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              child: Text(
                '${formatDistance(photo.distanceMeters)} · '
                '${photo.capturedAt.day.toString().padLeft(2, '0')}/'
                '${photo.capturedAt.month.toString().padLeft(2, '0')} '
                '${photo.capturedAt.hour.toString().padLeft(2, '0')}:'
                '${photo.capturedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
