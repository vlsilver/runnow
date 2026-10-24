import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

/// Kích thước gốc của thẻ thành tích; nơi dùng bọc trong [GameCardScaled].
const achievementCardSize = Size(300, 420);

typedef _T = RunNowAchievementTokens;
const _ink = RunNowGameTokens.nightInk;
const _condensed = 'Barlow Condensed';

/// Dữ liệu một thẻ thành tích. Ảnh full-art phủ cả thẻ, chữ và số do app vẽ
/// đè lên, nên ảnh không bao giờ chứa chữ.
class AchievementCardData {
  const AchievementCardData({
    required this.tier,
    required this.art,
    required this.kind,
    required this.hero,
    required this.title,
    required this.owner,
    required this.serial,
    required this.desc,
    required this.meta,
    required this.date,
    this.heroUnit = 'KM',
  });

  final GameCardTier tier;

  /// Nền phủ cả thẻ: ảnh, hay hình vẽ như đường chạy. Thẻ tự cho nó tràn
  /// viền và lệch theo độ nghiêng.
  final Widget art;

  /// Loại thành tích, ví dụ "KÈO HOÀN THÀNH".
  final String kind;

  /// Con số chính, đã định dạng ("52,3").
  final String hero;
  final String heroUnit;
  final String title;
  final String owner;

  /// Số thứ tự của thẻ trong kèo, ví dụ "Nº 03/05".
  final String serial;
  final String desc;
  final String meta;
  final String date;
}

enum _Holo { none, sheen, prism }

/// Chất liệu từng bậc. Bậc càng cao thì viền càng dày và càng nhiều lớp
/// sáng, để nhìn thoáng là biết thẻ hiếm cỡ nào.
class _Look {
  const _Look({
    required this.accent,
    required this.frameWidth,
    required this.frame,
    required this.frameStops,
    required this.holo,
    this.aura,
    this.corner,
    this.title,
    this.holoStrength = 0,
    this.rainbow = false,
  });

  final Color accent;
  final double frameWidth;
  final List<Color> frame;
  final List<double>? frameStops;
  final _Holo holo;
  final double holoStrength;
  final Color? aura;
  final List<Color>? corner;
  final List<Color>? title;

  /// Viền cầu vồng xoay, chữ ánh chạy: chỉ bậc Huyền thoại.
  final bool rainbow;
}

const _prism = [
  _T.prismPink,
  _T.prismAmber,
  _T.prismMint,
  _T.prismSky,
  _T.prismViolet,
  _T.prismPink,
];

const _looks = {
  GameCardTier.common: _Look(
    accent: _T.accentCommon,
    frameWidth: 6,
    frame: [_T.graphite1, _T.graphite2, _T.graphite3, _T.graphite4],
    frameStops: [0, 0.38, 0.66, 1],
    holo: _Holo.none,
  ),
  GameCardTier.rare: _Look(
    accent: _T.accentRare,
    frameWidth: 7,
    frame: [_T.silver1, _T.silver2, _T.silver3, _T.silver4, _T.silver5],
    frameStops: [0, 0.26, 0.48, 0.7, 1],
    holo: _Holo.sheen,
    aura: _T.auraRare,
    title: [_T.titleSilver1, _T.titleSilver2, _T.titleSilver3],
  ),
  GameCardTier.superRare: _Look(
    accent: _T.accentEpic,
    frameWidth: 8,
    frame: [_T.gold1, _T.gold2, _T.gold3, _T.gold4, _T.gold5],
    frameStops: [0, 0.24, 0.47, 0.69, 1],
    holo: _Holo.prism,
    holoStrength: 0.24,
    aura: _T.auraEpic,
    corner: [_T.cornerGoldLight, _T.cornerGoldDeep],
    title: [_T.titleGold1, _T.titleGold2, _T.titleGold3],
  ),
  GameCardTier.legendary: _Look(
    accent: _T.accentLegendary,
    frameWidth: 9,
    frame: _prism,
    frameStops: null,
    holo: _Holo.prism,
    holoStrength: 0.34,
    corner: [_T.cornerPrismLight, _T.cornerPrismDeep],
    rainbow: true,
  ),
};

/// Thẻ thành tích vẽ ở [achievementCardSize]. [pose] là độ nghiêng (-1..1 mỗi
/// chiều) mà viền, holo, ảnh và vệt sáng chạy theo. Thẻ Huyền thoại tự chạy
/// viền cầu vồng, chữ ánh và sao nhấp nháy khi [animate]; tắt đi thì vẽ một
/// khung hình đứng yên, dùng cho test và ảnh tĩnh.
class AchievementCard extends StatefulWidget {
  const AchievementCard({
    super.key,
    required this.data,
    this.pose = Offset.zero,
    this.back = false,
    this.animate = true,
  });

  final AchievementCardData data;
  final Offset pose;
  final bool back;
  final bool animate;

  @override
  State<AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<AchievementCard>
    with SingleTickerProviderStateMixin {
  /// Chỉ tạo khi thẻ cần chạy, để thẻ đứng yên không giữ ticker.
  Ticker? _ticker;

  /// Giây đã chạy, cho các lớp tự chuyển động của thẻ Huyền thoại.
  double _seconds = 0;

  bool get _animates =>
      widget.animate && widget.data.tier == GameCardTier.legendary;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(AchievementCard old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (_animates) {
      final ticker = _ticker ??= createTicker(_onTick);
      if (!ticker.isActive) ticker.start();
    } else if (_ticker?.isActive ?? false) {
      _ticker!.stop();
    }
  }

  void _onTick(Duration elapsed) {
    setState(() => _seconds = elapsed.inMicroseconds / 1e6);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final look = _looks[data.tier]!;
    final pose = widget.pose;
    final w = look.frameWidth;
    return SizedBox.fromSize(
      size: achievementCardSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Frame(look: look, pose: pose, seconds: _seconds),
          Padding(
            padding: EdgeInsets.all(w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21 - w),
              child: widget.back
                  ? _Back(data: data, look: look, pose: pose)
                  : _Front(
                      data: data,
                      look: look,
                      pose: pose,
                      seconds: _seconds,
                    ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(w),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21 - w),
                  border: Border.all(color: _T.hairline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Điểm sáng (0..1 mỗi chiều) theo độ nghiêng.
Offset _lightAt(Offset pose) => Offset(0.5 + pose.dx * 0.5, 0.5 + pose.dy * 0.5);

double _deg(double d) => d * math.pi / 180;

class _Frame extends StatelessWidget {
  const _Frame({required this.look, required this.pose, required this.seconds});

  final _Look look;
  final Offset pose;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    // Nghiêng thẻ thì ánh kim trên viền trượt theo, như kim loại thật.
    final tiltDeg = pose.dx * 14;
    final legendary = look.rainbow;
    final Gradient gradient = legendary
        ? SweepGradient(
            colors: look.frame,
            transform: GradientRotation(_deg(seconds * 50 + tiltDeg * 6)),
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: look.frame,
            stops: look.frameStops,
            transform: GradientRotation(_deg(tiltDeg * 4)),
          );
    final aura = legendary
        ? HSLColor.fromAHSL(0.42, (seconds * 40) % 360, 0.9, 0.72).toColor()
        : look.aura;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: gradient,
            boxShadow: [
              const BoxShadow(
                color: _T.drop,
                blurRadius: 44,
                offset: Offset(0, 22),
              ),
              if (aura != null)
                BoxShadow(color: aura, blurRadius: legendary ? 52 : 34),
            ],
          ),
        ),
        if (look.holo == _Holo.sheen)
          // Vân xước của bạc: vạch sáng tối 3px lặp lại.
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1, 0),
                  end: Alignment(-0.98, 0),
                  tileMode: TileMode.repeated,
                  colors: [
                    _T.brushLight,
                    _T.brushLight,
                    _T.brushDark,
                    _T.brushDark,
                  ],
                  stops: [0, 1 / 3, 1 / 3, 1],
                ),
              ),
            ),
          ),
        if (look.holo != _Holo.none)
          Padding(
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: _T.etch),
              ),
            ),
          ),
        if (look.corner case final corner?) ...[
          for (final align in const [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ])
            Align(
              alignment: align,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: corner,
                      ),
                      boxShadow: const [
                        BoxShadow(color: _T.cornerGlow, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({
    required this.data,
    required this.look,
    required this.pose,
    required this.seconds,
  });

  final AchievementCardData data;
  final _Look look;
  final Offset pose;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final light = _lightAt(pose);
    final legendary = data.tier == GameCardTier.legendary;
    final accent = look.accent;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _T.field),
        // Ảnh tràn ra 10px mỗi bên và lệch nhẹ theo độ nghiêng, tạo chiều sâu.
        Positioned(
          left: -10,
          top: -10,
          right: -10,
          bottom: -10,
          child: Transform.translate(
            offset: Offset(-pose.dx * 7, -pose.dy * 7),
            child: data.art,
          ),
        ),
        if (look.holo == _Holo.sheen) _Sheen(light: light),
        if (look.holo == _Holo.prism)
          _Prism(light: light, strength: look.holoStrength),
        if (legendary)
          IgnorePointer(child: CustomPaint(painter: _GlitterPainter(light))),
        const _Shade(),
        Positioned(
          top: 12,
          left: 13,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.kind, style: _label(accent, 11)),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    data.hero,
                    style: const TextStyle(
                      fontFamily: _condensed,
                      fontWeight: FontWeight.w800,
                      fontSize: 38,
                      height: 0.9,
                      color: _T.hero,
                      shadows: [
                        Shadow(
                          color: _T.textShadow,
                          offset: Offset(0, 2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    data.heroUnit,
                    style: TextStyle(
                      fontFamily: _condensed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1.04,
                      color: _T.hero.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 13,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  for (var i = 0; i < gameCardTiers[data.tier]!.gems; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: _Gem(color: accent),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                gameCardTiers[data.tier]!.label.toUpperCase(),
                style: _label(accent, 9.5),
              ),
            ],
          ),
        ),
        Positioned(
          left: 13,
          right: 13,
          bottom: 11,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: data.owner,
                      style: TextStyle(color: accent),
                    ),
                    TextSpan(
                      text: ' · ${data.serial}',
                      style: TextStyle(color: _ink.withValues(alpha: 0.62)),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _condensed,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.54,
                ),
              ),
              const SizedBox(height: 3),
              _Title(text: data.title, look: look, seconds: seconds),
              const SizedBox(height: 4),
              Text(
                data.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.38,
                  fontStyle: FontStyle.italic,
                  color: _ink.withValues(alpha: 0.84),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Opacity(
                  opacity: 0.7,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
              _Foot(left: data.meta, right: '3I RUN', accent: accent),
            ],
          ),
        ),
        if (legendary)
          IgnorePointer(child: CustomPaint(painter: _StarPainter(seconds))),
        GameCardGlare(at: light, strength: 0.38),
      ],
    );
  }
}

TextStyle _label(Color color, double size) => TextStyle(
  fontFamily: _condensed,
  fontWeight: FontWeight.w700,
  fontSize: size,
  letterSpacing: size * 0.16,
  color: color,
  shadows: const [
    Shadow(color: _T.textShadow, offset: Offset(0, 1), blurRadius: 4),
  ],
);

class _Foot extends StatelessWidget {
  const _Foot({required this.left, required this.right, required this.accent});

  final String left;
  final String right;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w600,
      fontSize: 10,
      letterSpacing: 1.2,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: _ink.withValues(alpha: 0.66)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          right,
          style: style.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
            color: accent,
          ),
        ),
      ],
    );
  }
}

/// Tên thẻ: trắng ở bậc Thường, ánh bạc, ánh vàng, rồi cầu vồng chạy ở bậc
/// Huyền thoại. Bóng đổ vẽ riêng bên dưới để không bị nhuộm màu gradient.
class _Title extends StatelessWidget {
  const _Title({required this.text, required this.look, required this.seconds});

  final String text;
  final _Look look;
  final double seconds;

  static const _style = TextStyle(
    fontSize: 21,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.21,
  );

  @override
  Widget build(BuildContext context) {
    Text line(Color color, {List<Shadow>? shadows}) => Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _style.copyWith(color: color, shadows: shadows),
    );

    final shadow = line(
      Colors.transparent,
      shadows: const [
        Shadow(color: _T.textShadow, offset: Offset(0, 2), blurRadius: 6),
      ],
    );
    final legendary = look.rainbow;
    final colors = look.title;
    if (colors == null && !legendary) {
      return Stack(children: [shadow, line(_ink)]);
    }
    return Stack(
      children: [
        shadow,
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            if (legendary) {
              // Dải màu dài 2,2 lần chữ, trượt hết một vòng sau 5 giây.
              final span = bounds.width * 2.2;
              final x = -(seconds / 5 % 1) * span;
              return ui.Gradient.linear(
                Offset(x, 0),
                Offset(x + span, 0),
                const [
                  _T.titlePink,
                  _T.titleAmber,
                  _T.titleMint,
                  _T.titleSky,
                  _T.titleViolet,
                  _T.titlePink,
                ],
                const [0, 0.2, 0.4, 0.6, 0.8, 1],
                TileMode.repeated,
              );
            }
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors!,
              stops: const [0, 0.45, 1],
            ).createShader(bounds);
          },
          child: line(Colors.white),
        ),
      ],
    );
  }
}

class _Gem extends StatelessWidget {
  const _Gem({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, color],
          ),
          boxShadow: [BoxShadow(color: color, blurRadius: 6)],
        ),
      ),
    );
  }
}

/// Lớp tối trên và dưới để chữ đọc được trên mọi ảnh.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        // Không stretch thì DecoratedBox không con co về rộng 0, không vẽ gì.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ảnh sáng (tranh lụa, giấy) làm nhãn bạc chìm, nên phía trên
          // tối đậm hơn bản thiết kế web một chút.
          Expanded(
            flex: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _T.shade.withValues(alpha: 0.78),
                    _T.shade.withValues(alpha: 0.45),
                    _T.shade.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
          const Spacer(flex: 18),
          Expanded(
            flex: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    _T.shade.withValues(alpha: 0.96),
                    _T.shade.withValues(alpha: 0.84),
                    _T.shade.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bậc Hiếm: một vệt sáng chéo quét qua khi nghiêng.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.light});

  final Offset light;

  @override
  Widget build(BuildContext context) {
    // Tâm vệt chạy từ mép phải sang mép trái khi điểm sáng đi 0 → 1.
    final cx = 2 * (1.25 - 1.6 * light.dx) - 1;
    final cy = 2 * (1.25 - 1.6 * light.dy) - 1;
    const half = Offset(2.36, 1.1);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          backgroundBlendMode: BlendMode.overlay,
          gradient: LinearGradient(
            begin: Alignment(cx - half.dx, cy - half.dy),
            end: Alignment(cx + half.dx, cy + half.dy),
            colors: const [
              Colors.transparent,
              _T.sheen,
              _T.sheenTail,
              Colors.transparent,
            ],
            stops: const [0.38, 0.48, 0.54, 0.64],
          ),
        ),
      ),
    );
  }
}

/// Siêu hiếm và Huyền thoại: dải cầu vồng lặp lại, color-dodge lên ảnh, trôi
/// theo điểm sáng.
class _Prism extends StatelessWidget {
  const _Prism({required this.light, required this.strength});

  final Offset light;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final bx = -1 - 4.4 * light.dx;
    final by = -1 - 4.4 * light.dy;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          backgroundBlendMode: BlendMode.colorDodge,
          gradient: LinearGradient(
            begin: Alignment(bx, by),
            end: Alignment(bx + 2.55, by + 1.28),
            tileMode: TileMode.repeated,
            colors: [
              for (final c in const [
                _T.holoPink,
                _T.holoAmber,
                _T.holoMint,
                _T.holoSky,
                _T.holoViolet,
                _T.holoPink,
              ])
                c.withValues(alpha: strength),
            ],
            stops: const [0, 0.2, 0.4, 0.6, 0.8, 1],
          ),
        ),
      ),
    );
  }
}

/// Kim tuyến: hai lưới chấm nhỏ trôi ngược chiều nhau theo điểm sáng.
class _GlitterPainter extends CustomPainter {
  const _GlitterPainter(this.light);

  final Offset light;

  @override
  void paint(Canvas canvas, Size size) {
    // Mỗi lưới là một lệnh vẽ: vài trăm drawCircle riêng, mỗi cái một lần
    // blend screen, làm GPU iPhone mất ~50 ms mỗi khung hình.
    void grid(double w, double h, double ox, double oy, double r, Color c) {
      final points = <double>[];
      for (var x = ox % w - w; x < size.width + w; x += w) {
        for (var y = oy % h - h; y < size.height + h; y += h) {
          points
            ..add(x + w / 2)
            ..add(y + h / 2);
        }
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(points),
        Paint()
          ..color = c
          ..blendMode = BlendMode.screen
          ..strokeWidth = r * 2
          ..strokeCap = StrokeCap.round,
      );
    }

    grid(17, 21, light.dx * 70, light.dy * 50, 0.9, _T.glitterWhite);
    grid(29, 25, -light.dx * 50, light.dy * 80, 0.8, _T.glitterWarm);
  }

  @override
  bool shouldRepaint(_GlitterPainter old) => old.light != light;
}

/// Sáu ngôi sao bốn cánh nhấp nháy lệch nhịp nhau, chu kỳ 2,4 giây.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.seconds);

  final double seconds;

  static const _spots = [
    (0.18, 0.22, 0.0),
    (0.78, 0.14, 0.7),
    (0.64, 0.46, 1.4),
    (0.30, 0.58, 2.1),
    (0.86, 0.66, 0.35),
    (0.12, 0.40, 1.05),
  ];

  static final _star = Path()
    ..moveTo(0, -6)
    ..lineTo(1.2, -1.2)
    ..lineTo(6, 0)
    ..lineTo(1.2, 1.2)
    ..lineTo(0, 6)
    ..lineTo(-1.2, 1.2)
    ..lineTo(-6, 0)
    ..lineTo(-1.2, -1.2)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, y, delay) in _spots) {
      final phase = ((seconds - delay) / 2.4) % 1;
      final k = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
      if (k < 0.02) continue;
      canvas
        ..save()
        ..translate(x * size.width, y * size.height)
        ..rotate(math.pi / 4 * k)
        ..scale(0.4 + 0.6 * k);
      canvas.drawPath(_star, Paint()..color = _T.star.withValues(alpha: k));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.seconds != seconds;
}

/// Mặt sau: huy hiệu 3I RUN, ngày nhận và bậc.
class _Back extends StatelessWidget {
  const _Back({required this.data, required this.look, required this.pose});

  final AchievementCardData data;
  final _Look look;
  final Offset pose;

  @override
  Widget build(BuildContext context) {
    final accent = look.accent;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [_T.backTop, _T.backBottom],
              stops: [0, 0.72],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              center: Alignment(0, -0.16),
              endAngle: 12 * math.pi / 180,
              tileMode: TileMode.repeated,
              colors: [_T.backRay, _T.backRay, Colors.transparent],
              stops: [0, 0.5, 0.5],
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 122,
              height: 122,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 40,
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: 0.33),
                    spreadRadius: 7,
                  ),
                  // Bóng Flutter vẽ cả dưới hộp, nên lấp nền trước để vòng
                  // nhấn chỉ còn 1px ở mép ngoài như bản thiết kế.
                  const BoxShadow(color: _T.backTop, spreadRadius: 6),
                  const BoxShadow(color: _T.emblemRing, spreadRadius: 6),
                  const BoxShadow(color: _T.backTop),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '3I',
                    style: TextStyle(
                      fontFamily: _condensed,
                      fontWeight: FontWeight.w800,
                      fontSize: 54,
                      height: 0.9,
                      color: accent,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4.8),
                    child: Text(
                      'RUN',
                      style: TextStyle(
                        fontFamily: _condensed,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 4.8,
                        color: _ink.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'THẺ THÀNH TÍCH',
              style: _label(_ink.withValues(alpha: 0.7), 11),
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: _Foot(
            left: data.date,
            right: gameCardTiers[data.tier]!.label.toUpperCase(),
            accent: accent,
          ),
        ),
        GameCardGlare(at: _lightAt(pose), strength: 0.38),
      ],
    );
  }
}
