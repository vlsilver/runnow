import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/journey/widgets/round_icon_button.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';

/// Artwork nền chỉ có cho Xuyên Việt (do team tự thiết kế riêng) — các
/// chiến dịch khác (Marathon Athens, Tour du Mont Blanc) chưa có bản đồ
/// minh hoạ riêng, dùng nền gradient chung thay thế, xem [_ShareCard].
const _vietnamMapAsset = 'assets/journey/map-xuyen-viet.svg';

/// Tỉ lệ khung gốc của [_vietnamMapAsset] (xem viewBox trong file SVG) —
/// căn theo đúng tỉ lệ này để không méo hình, phần margin trên/dưới trong
/// file vốn đã được thiết kế chừa sẵn cho tiêu đề + số liệu đè lên. Card
/// nền gradient chung cũng dùng chung tỉ lệ này để đồng bộ layout.
const _cardAspectRatio = 328 / 560;

/// Màn xem trước + chia sẻ thành tích hoàn thành 1 chiến dịch "Hành Trình"
/// — nền bản đồ là artwork tĩnh do team tự thiết kế riêng cho Xuyên Việt
/// (`map-xuyen-viet.svg`: viền đất nước, tuyến Lũng Cú → Đất Mũi, cả Hoàng
/// Sa/Trường Sa), bundle sẵn trong app nên chụp/chia sẻ được ngay, không
/// cần chờ tải mạng; các chiến dịch khác dùng nền gradient chung. Mở qua
/// `Navigator.push` trực tiếp (không qua go_router) — cùng cách các màn
/// xem toàn màn hình khác trong app (`route_map.dart`), vì đây là thao tác
/// tạm thời, không cần URL riêng.
class JourneyShareScreen extends StatefulWidget {
  const JourneyShareScreen({
    required this.campaignName,
    required this.route,
    super.key,
  });

  final String campaignName;
  final JourneyRoute route;

  @override
  State<JourneyShareScreen> createState() => _JourneyShareScreenState();
}

class _JourneyShareScreenState extends State<JourneyShareScreen> {
  final _cardKey = GlobalKey();
  var _sharing = false;

  Future<void> _share(BuildContext buttonContext) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await shareJourneyCompletion(
        cardKey: _cardKey,
        shareOriginContext: buttonContext,
        campaignName: widget.campaignName,
        routeName: widget.route.name,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không chia sẻ được: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Chia sẻ thành tích'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: _ShareCard(
                    campaignName: widget.campaignName,
                    route: widget.route,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Builder(
                builder: (buttonContext) => _sharing
                    ? const _SharingSpinner()
                    : RoundIconButton(
                        icon: Icons.share_rounded,
                        tooltip: 'Chia sẻ',
                        size: 48,
                        iconSize: 22,
                        onTap: () => _share(buttonContext),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spinner nhỏ dạng nút tròn, thay chỗ [RoundIconButton] trong lúc đang
/// dựng + chia sẻ ảnh, giữ đúng kích thước để không giật layout.
class _SharingSpinner extends StatelessWidget {
  const _SharingSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(14),
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white,
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.campaignName, required this.route});

  final String campaignName;
  final JourneyRoute route;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final isXuyenViet = campaignName == 'Hành Trình Xuyên Việt';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AspectRatio(
        aspectRatio: _cardAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isXuyenViet)
                  SvgPicture.asset(_vietnamMapAsset, fit: BoxFit.contain)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.1,
                        colors: [
                          Color.lerp(palette.accent, Colors.black, 0.65)!,
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 20,
                  top: 18,
                  right: 20,
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/brand/3i-mark-transparent.png',
                        width: 20,
                        height: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          campaignName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Center(child: _AchievementBadge(accent: palette.accent)),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${formatCompactKm(route.totalLengthMeters)} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Tích luỹ của bạn đã đủ cho trọn vẹn $campaignName.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Huy hiệu thành tích hiển thị trên card chia sẻ — hào quang mờ + tia nắng
/// toả xung quanh + vòng gradient + icon huy chương, nổi bật hơn hẳn con dấu
/// tick đơn giản dùng ở các màn khác trong tính năng Hành Trình.
class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.accent});

  final Color accent;
  static const double size = 132;

  @override
  Widget build(BuildContext context) {
    final rayColor = Colors.white.withValues(alpha: 0.85);
    return SizedBox(
      width: size,
      height: size + 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.55),
                        blurRadius: size * 0.5,
                        spreadRadius: size * 0.08,
                      ),
                    ],
                  ),
                ),
                CustomPaint(
                  size: Size.square(size),
                  painter: _SunburstPainter(color: rayColor),
                ),
                Container(
                  width: size * 0.72,
                  height: size * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        accent,
                        Color.lerp(accent, Colors.white, 0.55)!,
                        accent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color.lerp(accent, Colors.white, 0.25)!,
                          accent,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'HOÀN THÀNH',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vẽ các tia sáng toả tròn phía sau vòng huy hiệu bằng `dart:math` để chia
/// đều góc quanh tâm — tạo cảm giác "sống động" thay vì một khối tĩnh.
class _SunburstPainter extends CustomPainter {
  const _SunburstPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.width * 0.34;
    final outerRadiusLong = size.width * 0.5;
    final outerRadiusShort = size.width * 0.42;
    const rayCount = 16;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;

    for (var i = 0; i < rayCount; i++) {
      final angle = (2 * math.pi / rayCount) * i;
      final outerRadius = i.isEven ? outerRadiusLong : outerRadiusShort;
      final start =
          center + Offset(math.cos(angle), math.sin(angle)) * innerRadius;
      final end =
          center + Offset(math.cos(angle), math.sin(angle)) * outerRadius;
      paint.color = color.withValues(alpha: i.isEven ? 0.55 : 0.3);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) =>
      oldDelegate.color != color;
}
