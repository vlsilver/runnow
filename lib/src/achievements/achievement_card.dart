import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

/// Kích thước gốc của thẻ thành tích; nơi dùng bọc trong [GameCardScaled].
const achievementCardSize = Size(300, 420);

typedef _T = RunNowAchievementTokens;
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
    this.stamp,
    this.backFace,
    this.secret,
  });

  final GameCardTier tier;

  /// Hành của thẻ Ẩn: cả thẻ một màu theo hành đó, bỏ qua bộ màu đang chọn.
  final RunNowElement? secret;

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

  /// Huy hiệu tròn dưới số đá, ví dụ đường chạy thu nhỏ khi nền là tranh.
  final Widget? stamp;

  /// Ruột mặt sau thay cho huy hiệu 3I RUN; khung và vệt sáng vẫn do thẻ vẽ.
  final Widget? backFace;
}

/// Kim loại của bậc, mỗi thứ ba tông sáng, giữa, tối. Tranh phủ cả thẻ, kim
/// loại chỉ còn ở nét chân thẻ, ô đá và viền trong.
typedef _Metal = ({Color light, Color mid, Color dark});

const _metals = <GameCardTier, _Metal>{
  GameCardTier.common: (
    light: _T.ironLight,
    mid: _T.ironMid,
    dark: _T.ironDark,
  ),
  GameCardTier.rare: (
    light: _T.bronzeLight,
    mid: _T.bronzeMid,
    dark: _T.bronzeDark,
  ),
  GameCardTier.superRare: (
    light: _T.silverLight,
    mid: _T.silverMid,
    dark: _T.silverDark,
  ),
  GameCardTier.legendary: (
    light: _T.goldLight,
    mid: _T.goldMid,
    dark: _T.goldDark,
  ),
  GameCardTier.mythic: (
    light: _T.diamondLight,
    mid: _T.diamondMid,
    dark: _T.diamondDark,
  ),
};

/// Màu thẻ Ẩn của một hành, pha từ ramp của hành: nét và ô đá, đá, hai đầu
/// tranh một màu, chữ Hán của hành, quầng quanh thẻ, sao.
class _SecretLook {
  _SecretLook._(RunNowElement element)
    : glyph = _glyphs[element]!,
      metal = (
        light: Color.lerp(element.ramp[0], _T.secretLift, 0.45)!,
        mid: element.ramp[1],
        dark: element.ramp[3],
      ),
      gems = (
        light: Color.lerp(element.ramp[0], _T.secretLift, 0.6)!,
        mid: element.ramp[2],
        dark: element.ramp[4],
      ),
      glyphColor = Color.lerp(element.ramp[0], _T.secretLift, 0.4)!,
      halo = Color.lerp(
        element.ramp[2],
        _T.secretDeep,
        0.2,
      )!.withValues(alpha: 0.4),
      star = Color.lerp(element.ramp[0], _T.secretLift, 0.6)!,
      duotone = _duotone(
        Color.lerp(element.ramp[4], _T.secretDeep, 0.72)!,
        Color.lerp(element.ramp[0], _T.secretLift, 0.5)!,
      );

  static final _cache = <RunNowElement, _SecretLook>{};
  static _SecretLook of(RunNowElement element) =>
      _cache.putIfAbsent(element, () => _SecretLook._(element));

  static const _glyphs = {
    RunNowElement.metal: '金',
    RunNowElement.wood: '木',
    RunNowElement.water: '水',
    RunNowElement.fire: '火',
    RunNowElement.earth: '土',
  };

  final String glyph;
  final _Metal metal;
  final _Metal gems;
  final Color glyphColor;
  final Color halo;
  final Color star;

  /// Đổi tranh về một màu: độ sáng của điểm ảnh chạy từ [dark] tới [light].
  final ColorFilter duotone;

  static ColorFilter _duotone(Color dark, Color light) {
    List<double> row(double d, double l) {
      final k = l - d;
      return [k * 0.2126, k * 0.7152, k * 0.0722, 0, d * 255];
    }

    return ColorFilter.matrix([
      ...row(dark.r, light.r),
      ...row(dark.g, light.g),
      ...row(dark.b, light.b),
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}

/// Vệt sáng cùng tông kim loại quét qua tranh khi nghiêng, từ bậc Hiếm.
const _sheens = {
  GameCardTier.rare: _T.sheenBronze,
  GameCardTier.superRare: _T.sheen,
  GameCardTier.legendary: _T.sheenGold,
  GameCardTier.mythic: _T.sheenDiamond,
};

/// Bo góc ngoài của thẻ.
const _radius = 17.0;

/// Đỉnh đường cong ngăn tranh với chân thẻ; chân thẻ chiếm từ đây tới đáy.
const _footTop = 360.0;

/// Lề trái phải của chữ và ô đá.
const _inset = 17.0;

/// Thẻ thành tích vẽ ở [achievementCardSize]. [pose] là độ nghiêng (-1..1 mỗi
/// chiều) mà nét kim loại, vệt sáng và tranh chạy theo. Riêng thẻ Thần thoại
/// tự chạy vệt sáng dọc nét và sao nhấp nháy khi [animate]; tắt đi thì vẽ một
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

  /// Giây đã chạy, cho vệt sáng và sao của bậc Thần thoại.
  double _seconds = 0;

  bool get _animates =>
      widget.animate && widget.data.tier == GameCardTier.mythic;

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
    final secret = data.secret;
    final look = secret == null ? null : _SecretLook.of(secret);
    final skin = secret == null
        ? RunCardSkin.of(context)
        : RunCardSkin.secret(secret);
    final pose = widget.pose;
    final card = SizedBox.fromSize(
      size: achievementCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(_radius)),
          boxShadow: [
            const BoxShadow(
              color: _T.drop,
              blurRadius: 44,
              offset: Offset(0, 22),
            ),
            if (look != null) BoxShadow(color: look.halo, blurRadius: 31),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: widget.back
              ? _Back(
                  data: data,
                  skin: skin,
                  look: look,
                  pose: pose,
                  seconds: _seconds,
                )
              : _Front(
                  data: data,
                  skin: skin,
                  look: look,
                  pose: pose,
                  seconds: _seconds,
                ),
        ),
      ),
    );
    // Tranh, con dấu và mặt sau do nơi gọi dựng, đọc bộ màu từ context: thẻ
    // Ẩn đặt bộ màu của hành cho cả cây bên dưới.
    return secret == null ? card : RunCardSkinScope(skin: skin, child: card);
  }
}

/// Điểm sáng (0..1 mỗi chiều) theo độ nghiêng.
Offset _lightAt(Offset pose) =>
    Offset(0.5 + pose.dx * 0.5, 0.5 + pose.dy * 0.5);

/// Ánh kim chạy ngang: tối ở hai mép, sáng hai bên giữa. Nghiêng thẻ thì
/// ánh trượt theo, như kim loại thật.
Shader _metalShader(_Metal metal, Rect rect, double tilt) => LinearGradient(
  begin: Alignment(-1 + tilt * 0.5, 0),
  end: Alignment(1 + tilt * 0.5, 0),
  colors: [metal.dark, metal.light, metal.mid, metal.light, metal.dark],
  tileMode: TileMode.mirror,
).createShader(rect);

/// Đường cong chân thẻ: phẳng ở giữa, cong xuống hai mép.
Path _footArc(double width, double dy) {
  final y = _footTop + dy;
  return Path()
    ..moveTo(0, y + 26.4)
    ..cubicTo(0, y + 7.2, 8.4, y, 28.8, y)
    ..lineTo(width - 28.8, y)
    ..cubicTo(width - 8.4, y, width, y + 7.2, width, y + 26.4);
}

/// Độ dày nét kim loại chính theo bậc, Sắt mảnh nhất.
const _lineWidths = [0.96, 1.32, 1.44, 1.56, 1.68];

class _Front extends StatelessWidget {
  const _Front({
    required this.data,
    required this.skin,
    required this.look,
    required this.pose,
    required this.seconds,
  });

  final AchievementCardData data;
  final RunCardSkin skin;
  final _SecretLook? look;
  final Offset pose;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final light = _lightAt(pose);
    final tier = data.tier;
    final look = this.look;
    final metal = look?.metal ?? _metals[tier]!;
    final sheen = look != null ? _T.sheen : _sheens[tier];
    final accent = skin.accent(tier);
    final ink = skin.ink;
    TextStyle label(Color color, double size) =>
        _label(color, size, skin.textShadow);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: skin.field),
        // Ảnh tràn ra 10px mỗi bên và lệch nhẹ theo độ nghiêng, tạo chiều sâu.
        Positioned(
          left: -10,
          top: -10,
          right: -10,
          bottom: -10,
          child: Transform.translate(
            offset: Offset(-pose.dx * 7, -pose.dy * 7),
            child: look == null
                ? data.art
                : ColorFiltered(colorFilter: look.duotone, child: data.art),
          ),
        ),
        if (sheen != null) _Sheen(light: light, color: sheen),
        // Khối chữ đứng ngay trên đường cong, cùng mốc với nét kim loại.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _footTop,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _Scrim(
              skin: skin,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label(accent, 11),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        // Hero có thể là tên vai backend gửi, dài bao nhiêu không
                        // biết trước: quá bề ngang thì thu nhỏ chứ không tràn.
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              data.hero,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: _condensed,
                                fontWeight: FontWeight.w800,
                                fontSize: 38,
                                height: 0.9,
                                color: skin.hero,
                                shadows: [
                                  Shadow(
                                    color: skin.textShadow,
                                    offset: Offset(0, 2),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
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
                            color: skin.hero.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _Title(text: data.title, tier: tier, skin: skin),
                    const SizedBox(height: 4),
                    Text(
                      data.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.38,
                        fontStyle: FontStyle.italic,
                        color: ink.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _TrimPainter(
              tier: tier,
              metal: metal,
              tilt: pose.dx,
              seconds: seconds,
              shade: skin.shade,
            ),
          ),
        ),
        Positioned(
          left: _inset,
          right: _inset,
          top: _footTop + 13,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: data.owner,
                            style: TextStyle(color: ink.withValues(alpha: 0.8)),
                          ),
                          TextSpan(
                            text: ' · ${data.serial}',
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.55),
                            ),
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
                  ),
                  const SizedBox(width: 8),
                  Text(switch (data.secret) {
                    final element? => 'ẨN · ${element.label.toUpperCase()}',
                    null => gameCardTiers[tier]!.label.toUpperCase(),
                  }, style: label(accent, 11)),
                ],
              ),
              const SizedBox(height: 4),
              _Foot(left: data.meta, right: '3I RUN', accent: accent, ink: ink),
            ],
          ),
        ),
        Positioned(
          top: _inset,
          left: _inset,
          child: _Cartouche(
            tier: tier,
            metal: metal,
            gems: look?.gems ?? metal,
            tilt: pose.dx,
            glyph: look,
          ),
        ),
        if (data.stamp case final stamp?)
          Positioned(
            top: _inset,
            right: _inset,
            width: 64,
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: skin.stamp,
                border: Border.all(
                  color: accent,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: _T.stampDrop,
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ClipOval(child: stamp),
            ),
          ),
        if (tier == GameCardTier.mythic)
          IgnorePointer(
            child: CustomPaint(
              painter: _StarPainter(seconds, look?.star ?? _T.starDiamond),
            ),
          ),
        GameCardGlare(at: light, strength: 0.38),
      ],
    );
  }
}

/// Nét kim loại của bậc. Mặt trước có đường cong ngăn tranh với chân thẻ:
/// Sắt và Đồng một nét, từ Bạc thêm nét mảnh phía trên, từ Vàng thêm viền
/// trong, Kim cương có vệt sáng chạy dọc các nét. Mặt sau chỉ có viền trong.
class _TrimPainter extends CustomPainter {
  const _TrimPainter({
    required this.tier,
    required this.metal,
    required this.tilt,
    required this.seconds,
    this.shade,
  });

  final GameCardTier tier;
  final _Metal metal;
  final double tilt;
  final double seconds;

  /// Màu chân thẻ; null là mặt sau, không có chân thẻ.
  final Color? shade;

  @override
  void paint(Canvas canvas, Size size) {
    // Thứ tự enum là thứ tự bậc, Sắt là 0.
    final level = tier.index;
    final card = Offset.zero & size;
    final shader = _metalShader(metal, card, tilt);
    // Có shader thì Paint chỉ lấy độ trong của color.
    Paint line(double width, [double opacity = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = shader
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          card.deflate(4.8),
          const Radius.circular(_radius - 4.8),
        ),
      );
    final traced = <Path>[];
    if (shade case final shade?) {
      final arc = _footArc(size.width, 0);
      canvas.drawPath(
        Path.from(arc)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = shade.withValues(alpha: 0.94),
      );
      canvas.drawPath(arc, line(_lineWidths[level]));
      if (level >= 2) {
        canvas.drawPath(_footArc(size.width, -3.1), line(0.54, 0.85));
      }
      if (level >= 3) canvas.drawPath(inner, line(0.72, 0.9));
      traced.addAll([arc, inner]);
    } else {
      canvas.drawPath(inner, line(_lineWidths[level], 0.9));
      traced.add(inner);
    }
    if (tier == GameCardTier.mythic) {
      // Vệt dài 5% nét, chạy hết một vòng trong 5,5 giây. Giây 0 là ảnh tĩnh
      // đem khoe, nên vệt xuất phát từ giữa đường cong chứ không ở mép trái.
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.68
        ..strokeCap = StrokeCap.round
        ..color = _T.sweep;
      final at = (seconds / 5.5 + 0.62) % 1;
      for (final path in traced) {
        for (final metric in path.computeMetrics()) {
          final start = metric.length * at;
          canvas.drawPath(
            metric.extractPath(start, start + metric.length * 0.05),
            sweep,
          );
        }
      }
    }
    // Mép ngoài tối mảnh để tranh sáng không loang ra nền.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        card.deflate(0.7),
        const Radius.circular(_radius - 0.7),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _T.rim,
    );
  }

  @override
  bool shouldRepaint(_TrimPainter old) =>
      old.tier != tier ||
      old.metal != metal ||
      old.tilt != tilt ||
      old.seconds != seconds ||
      old.shade != shade;
}

/// Ô dọc góc trái trên, số đá bằng số bậc. Từ bậc Bạc viền ô có thêm nét
/// trong. Thẻ Ẩn có thêm ô chữ Hán của hành ở đầu, ngăn với đá bằng một nét.
class _Cartouche extends StatelessWidget {
  const _Cartouche({
    required this.tier,
    required this.metal,
    required this.gems,
    required this.tilt,
    this.glyph,
  });

  final GameCardTier tier;
  final _Metal metal;
  final _Metal gems;
  final double tilt;
  final _SecretLook? glyph;

  static const _width = 29.0;
  static const _gemPitch = 13.2;
  static const _glyphCell = 31.0;

  @override
  Widget build(BuildContext context) {
    final look = glyph;
    final head = look == null ? 0.0 : _glyphCell;
    final painted = CustomPaint(
      size: Size(_width, head + 12 + gameCardTiers[tier]!.gems * _gemPitch),
      painter: _CartouchePainter(
        tier: tier,
        metal: metal,
        gems: gems,
        tilt: tilt,
        head: head,
      ),
    );
    if (look == null) return painted;
    return Stack(
      children: [
        painted,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _glyphCell,
          child: Center(
            child: Text(
              look.glyph,
              style: TextStyle(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w600,
                color: look.glyphColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartouchePainter extends CustomPainter {
  const _CartouchePainter({
    required this.tier,
    required this.metal,
    required this.gems,
    required this.tilt,
    required this.head,
  });

  final GameCardTier tier;
  final _Metal metal;
  final _Metal gems;
  final double tilt;

  /// Cao ô chữ Hán ở đầu, 0 khi không có.
  final double head;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final shader = _metalShader(metal, box, tilt);
    final outer = RRect.fromRectAndRadius(
      box.deflate(0.65),
      const Radius.circular(7.2),
    );
    canvas
      ..drawRRect(outer, Paint()..color = _T.cartouche)
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = shader,
      );
    if (tier.index >= 2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.deflate(2.9), const Radius.circular(4.8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.54
          ..shader = shader
          ..color = const Color.fromRGBO(0, 0, 0, 0.8),
      );
    }
    if (head > 0) {
      canvas.drawLine(
        Offset(5, head),
        Offset(size.width - 5, head),
        Paint()
          ..strokeWidth = 0.72
          ..shader = shader,
      );
    }
    final cx = size.width / 2;
    for (var i = 0; i < gameCardTiers[tier]!.gems; i++) {
      final cy = head + 6 + _Cartouche._gemPitch * (i + 0.5);
      final gem = Path()
        ..moveTo(cx, cy - 5)
        ..lineTo(cx + 3.8, cy)
        ..lineTo(cx, cy + 5)
        ..lineTo(cx - 3.8, cy)
        ..close();
      canvas
        ..drawPath(
          gem,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [gems.light, gems.mid, gems.dark],
            ).createShader(gem.getBounds()),
        )
        ..drawPath(
          gem,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.36
            ..color = _T.gemEdge,
        )
        ..drawLine(
          Offset(cx - 1.7, cy - 1.4),
          Offset(cx, cy - 3.6),
          Paint()
            ..strokeWidth = 0.6
            ..strokeCap = StrokeCap.round
            ..color = _T.gemGlint,
        );
    }
  }

  @override
  bool shouldRepaint(_CartouchePainter old) =>
      old.tier != tier ||
      old.metal != metal ||
      old.gems != gems ||
      old.tilt != tilt ||
      old.head != head;
}

TextStyle _label(Color color, double size, Color shadow) => TextStyle(
  fontFamily: _condensed,
  fontWeight: FontWeight.w700,
  fontSize: size,
  letterSpacing: size * 0.16,
  color: color,
  shadows: [Shadow(color: shadow, offset: const Offset(0, 1), blurRadius: 4)],
);

class _Foot extends StatelessWidget {
  const _Foot({
    required this.left,
    required this.right,
    required this.accent,
    required this.ink,
  });

  final String left;
  final String right;
  final Color accent;
  final Color ink;

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
            style: style.copyWith(color: ink.withValues(alpha: 0.66)),
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

/// Tên thẻ: chữ trơn ở bậc Thường, từ bậc Hiếm trở lên ánh theo kim loại của
/// bậc. Bóng đổ vẽ riêng bên dưới để không bị nhuộm màu gradient.
class _Title extends StatelessWidget {
  const _Title({required this.text, required this.tier, required this.skin});

  final String text;
  final GameCardTier tier;
  final RunCardSkin skin;

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
      shadows: [
        Shadow(
          color: skin.textShadow,
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ],
    );
    final colors = skin.titles[tier];
    if (colors == null) {
      return Stack(children: [shadow, line(skin.ink)]);
    }
    return Stack(
      children: [
        shadow,
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: const [0, 0.45, 1],
          ).createShader(bounds),
          child: line(Colors.white),
        ),
      ],
    );
  }
}

/// Lớp tối chỉ nằm sau khối chữ để chữ đọc được trên mọi tranh: đậm nhất ở
/// chân thẻ, nhạt dần qua vùng chữ, rồi tan hết ngay trên chữ. Cao theo khối
/// chữ (tên hai dòng thì phủ cao hơn), phần tranh không có chữ để nguyên.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.skin, required this.child});

  final RunCardSkin skin;
  final Widget child;

  /// Dải tan từ mép trên khối chữ về trong suốt.
  static const _fade = 48.0;

  @override
  Widget build(BuildContext context) {
    final color = skin.shade;
    final (edge, inner) = skin.scrim;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _fade,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color.withValues(alpha: inner),
                    color.withValues(alpha: inner * 0.4),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                color.withValues(alpha: edge),
                color.withValues(alpha: inner),
              ],
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Từ bậc Hiếm trở lên: một vệt sáng chéo cùng tông kim loại quét qua khi
/// nghiêng.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.light, required this.color});

  final Offset light;
  final Color color;

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
            colors: [
              Colors.transparent,
              color,
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

/// Ba sao bốn cánh trên tranh Kim cương, nhấp nháy lệch nhịp, chu kỳ 2,8 giây.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.seconds, this.color);

  final double seconds;
  final Color color;

  static const _spots = [
    (0.824, 0.2, 0.0),
    (0.232, 0.429, 0.9),
    (0.888, 0.68, 1.7),
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
      final phase = ((seconds - delay) / 2.8) % 1;
      final k = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
      if (k < 0.02) continue;
      canvas
        ..save()
        ..translate(x * size.width, y * size.height)
        ..rotate(math.pi / 4 * k)
        ..scale(0.4 + 0.6 * k);
      canvas.drawPath(_star, Paint()..color = color.withValues(alpha: k));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.seconds != seconds || old.color != color;
}

/// Mặt sau: huy hiệu 3I RUN, ngày nhận và bậc, viền trong theo kim loại bậc.
class _Back extends StatelessWidget {
  const _Back({
    required this.data,
    required this.skin,
    required this.look,
    required this.pose,
    required this.seconds,
  });

  final AchievementCardData data;
  final RunCardSkin skin;
  final _SecretLook? look;
  final Offset pose;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final trim = IgnorePointer(
      child: CustomPaint(
        painter: _TrimPainter(
          tier: data.tier,
          metal: look?.metal ?? _metals[data.tier]!,
          tilt: pose.dx,
          seconds: seconds,
        ),
      ),
    );
    if (data.backFace case final face?) {
      return Stack(
        fit: StackFit.expand,
        children: [
          face,
          trim,
          GameCardGlare(at: _lightAt(pose), strength: 0.38),
        ],
      );
    }
    final accent = skin.accent(data.tier);
    final ink = skin.ink;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 0.9,
              colors: [skin.backTop, skin.backBottom],
              stops: const [0, 0.72],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              center: const Alignment(0, -0.16),
              endAngle: 12 * math.pi / 180,
              tileMode: TileMode.repeated,
              colors: [skin.backRay, skin.backRay, Colors.transparent],
              stops: const [0, 0.5, 0.5],
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
                  BoxShadow(color: skin.backTop, spreadRadius: 6),
                  BoxShadow(color: skin.emblemRing, spreadRadius: 6),
                  BoxShadow(color: skin.backTop),
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
                        color: ink.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'THẺ THÀNH TÍCH',
              style: _label(ink.withValues(alpha: 0.7), 11, skin.textShadow),
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
            ink: ink,
          ),
        ),
        trim,
        GameCardGlare(at: _lightAt(pose), strength: 0.38),
      ],
    );
  }
}
