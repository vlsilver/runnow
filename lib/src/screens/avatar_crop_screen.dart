import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/avatar_crop.dart';

/// Chọn phần ảnh làm avatar: kéo để dời, chụm hai ngón để phóng, nút xoay
/// 90°. Trả JPEG vuông, hoặc null khi huỷ.
///
/// Màn giữ [photo] và giải phóng nó khi đóng.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({required this.photo, super.key});

  final ui.Image photo;

  /// Giải mã [bytes] rồi mở màn che cả thanh tab.
  static Future<Uint8List?> open(BuildContext context, Uint8List bytes) async {
    final photo = await decodeImageFromList(bytes);
    if (!context.mounted) {
      photo.dispose();
      return null;
    }
    return Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AvatarCropScreen(photo: photo),
      ),
    );
  }

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  int _turns = 0;
  bool _saving = false;
  TransformationController? _transform;

  /// Khung và số lần xoay mà [_transform] đang căn theo.
  (double, int)? _framedFor;

  Size get _turnedSize => rotatedSize(
    Size(widget.photo.width.toDouble(), widget.photo.height.toDouble()),
    _turns,
  );

  @override
  void dispose() {
    _transform?.dispose();
    widget.photo.dispose();
    super.dispose();
  }

  /// Đổi khung hay xoay thì dựng controller mới đặt ảnh giữa khung. Không đổi
  /// giá trị controller cũ ngay trong lúc build.
  TransformationController _controllerFor(double viewport, Size child) {
    final key = (viewport, _turns);
    if (_framedFor != key) {
      final old = _transform;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _framedFor = key;
      _transform = TransformationController(
        Matrix4.translationValues(
          -(child.width - viewport) / 2,
          -(child.height - viewport) / 2,
          0,
        ),
      );
    }
    return _transform!;
  }

  Future<void> _save() async {
    final turned = _turnedSize;
    final crop = avatarCropRect(
      imageSize: turned,
      viewport: _framedFor!.$1,
      transform: _transform!.value,
    ).intersect(Offset.zero & turned);
    setState(() => _saving = true);
    try {
      final jpeg = await encodeAvatarJpeg(
        widget.photo,
        quarterTurns: _turns,
        crop: crop,
      );
      if (mounted) Navigator.of(context).pop(jpeg);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không cắt được ảnh: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Chỉnh avatar'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Xong'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = (constraints.biggest.shortestSide - 32)
                      .clamp(120.0, 480.0);
                  final turned = _turnedSize;
                  final fit = viewport / turned.shortestSide;
                  final child = turned * fit;
                  final transform = _controllerFor(viewport, child);
                  return Center(
                    child: SizedBox.square(
                      dimension: viewport,
                      child: Stack(
                        children: [
                          InteractiveViewer(
                            key: ValueKey(_framedFor),
                            transformationController: transform,
                            constrained: false,
                            minScale: 1,
                            maxScale: 6,
                            child: SizedBox.fromSize(
                              size: child,
                              child: RotatedBox(
                                quarterTurns: _turns,
                                child: RawImage(
                                  image: widget.photo,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _CircleMask()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kéo để chọn vị trí, chụm hai ngón để phóng to.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xoay',
                    color: Colors.white,
                    onPressed: _saving
                        ? null
                        : () => setState(() => _turns = (_turns + 1) % 4),
                    icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tô tối bốn góc ngoài vòng tròn: avatar hiện tròn nên user thấy đúng phần
/// sẽ hiện.
class _CircleMask extends CustomPainter {
  const _CircleMask();

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Path()..addOval(Offset.zero & size);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      circle,
    );
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawPath(
      circle,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CircleMask oldDelegate) => false;
}
