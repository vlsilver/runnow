import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';

/// Chiều cao phần ghim thấy được (thumbnail 34 + đuôi 7) — dùng để tính
/// chiều cao `Marker` khi đặt trong flutter_map (cộng thêm [photoPinAnchorGap]
/// nếu dùng [PhotoPinMarker.withAnchorStem]).
const photoPinVisibleHeight = 34.0 + 7.0;

/// Khoảng que nối mảnh giữa đuôi ghim và toạ độ thật — chỉ cần khi ghim ảnh
/// có thể trùng vị trí với marker khác (vd người chạy live) và cần tách ra
/// để không chồng lấp khó phân biệt.
const photoPinAnchorGap = 26.0;

/// Ghim ảnh trên bản đồ — hình vuông bo góc + đuôi nhọn trỏ xuống đúng điểm
/// chụp, viền vàng (`RunNowSemanticColors.warning`) để phân biệt rõ với
/// marker vị trí người chạy (tròn, viền teal/đỏ). Dùng chung cho mọi nơi
/// hiển thị route map (preview nhỏ, chi tiết hoạt động, tracking, club, xác
/// nhận tuyến, và màn xem live) — trước đây mỗi nơi tự vẽ 1 kiểu khác nhau
/// (tròn không đuôi ở bản đồ thường, vuông+đuôi ở màn live), gây lệch ngôn
/// ngữ hình ảnh.
class PhotoPinMarker extends StatefulWidget {
  const PhotoPinMarker({
    required this.storagePath,
    this.extraCount = 0,
    this.animateIn = false,
    this.withAnchorStem = false,
    super.key,
  });

  final String storagePath;

  /// Số ảnh khác gộp cùng ghim này (0 = không hiện badge số).
  final int extraCount;

  /// Hiệu ứng nảy nhẹ lúc ghim vừa xuất hiện — dùng cho ảnh live mới chụp,
  /// không cần cho ảnh cũ đã có sẵn từ đầu.
  final bool animateIn;

  /// Thêm que nối mảnh bên dưới đuôi ghim, đẩy cả ghim nổi cao hơn — dùng
  /// khi ghim có thể trùng vị trí với marker khác (màn xem live).
  final bool withAnchorStem;

  @override
  State<PhotoPinMarker> createState() => _PhotoPinMarkerState();
}

class _PhotoPinMarkerState extends State<PhotoPinMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.animateIn ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) _popController.forward();
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _popController, curve: Curves.easeOutBack),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: RunNowSemanticColors.warning,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: StoragePhoto(
                    path: widget.storagePath,
                    cacheWidth: 68,
                    cacheHeight: 68,
                  ),
                ),
              ),
              if (widget.extraCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: RunNowSemanticColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '+${widget.extraCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          CustomPaint(
            size: const Size(12, 7),
            painter: _PinTailPainter(color: RunNowSemanticColors.warning),
          ),
          if (widget.withAnchorStem)
            Container(
              width: 1.5,
              height: photoPinAnchorGap,
              color: RunNowSemanticColors.warning.withValues(alpha: 0.7),
            ),
        ],
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  const _PinTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
