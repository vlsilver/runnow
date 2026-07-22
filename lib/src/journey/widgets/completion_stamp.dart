import 'package:flutter/material.dart';

/// Con dấu "đóng dấu pass" khi hoàn thành 1 hành trình — 2 vòng tròn lệch
/// nhẹ như dấu mộc thật, kèm dấu check. Dùng chung ở nút góc bản đồ (nhỏ)
/// và sheet thông tin hành trình (to) — 1 hình ảnh duy nhất cho "đã xong",
/// không lặp lại bằng 2 kiểu khác nhau ở 2 chỗ.
class CompletionStamp extends StatelessWidget {
  const CompletionStamp({required this.accent, this.size = 64, super.key});

  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = size / 64;
    return Transform.rotate(
      angle: -0.14,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(4 * scale),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 2.5 * scale),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 1 * scale),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, color: accent, size: 20 * scale),
              Text(
                'HOÀN\nTHÀNH',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 8 * scale,
                  height: 1.05,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
