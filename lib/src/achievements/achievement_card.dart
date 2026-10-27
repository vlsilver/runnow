import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  /// Huy hiệu tròn dưới số đá, ví dụ đường chạy thu nhỏ khi nền là tranh.
  final Widget? stamp;

  /// Ruột mặt sau thay cho huy hiệu 3I RUN; khung và vệt sáng vẫn do thẻ vẽ.
  final Widget? backFace;
}

/// Ánh tự chạy của hai bậc trên cùng: quầng sáng thở, kim tuyến, và riêng kim
/// cương có đốm sáng chạy quanh viền cùng sao nhấp nháy.
enum _Shine { none, gold, diamond }

/// Chất liệu từng bậc: sắt, đồng, bạc, vàng, kim cương. Bậc càng cao thì viền
/// càng dày và càng nhiều lớp sáng, để nhìn thoáng là biết thẻ hiếm cỡ nào,
/// nhưng mọi bậc chỉ dùng tông của kim loại đó, không có cầu vồng.
class _Look {
  const _Look({
    required this.frameWidth,
    required this.frame,
    required this.frameStops,
    this.faceted = false,
    this.sheen,
    this.brushed = false,
    this.aura,
    this.corner,
    this.shine = _Shine.none,
  });

  final double frameWidth;
  final List<Color> frame;
  final List<double>? frameStops;

  /// Viền là các mặt cắt xếp quanh tâm thẻ (kim cương) thay vì dải chéo.
  final bool faceted;

  /// Vệt sáng quét qua ảnh khi nghiêng; null thì ảnh để nguyên.
  final Color? sheen;

  /// Vân xước trên viền, như kim loại đánh xước.
  final bool brushed;
  final Color? aura;
  final List<Color>? corner;
  final _Shine shine;
}

/// Mặt cắt kim cương: mỗi màu chiếm một cung, ranh giới sắc như cạnh đá.
const _diamondFacets = [
  (_T.diamond1, 0.08),
  (_T.diamond2, 0.16),
  (_T.diamond3, 0.22),
  (_T.diamond4, 0.31),
  (_T.diamond5, 0.38),
  (_T.diamond6, 0.47),
  (_T.diamond8, 0.55),
  (_T.diamond3, 0.61),
  (_T.diamond7, 0.70),
  (_T.diamond9, 0.79),
  (_T.diamond10, 0.87),
  (_T.diamond11, 0.94),
  (_T.diamond12, 1.0),
];

final _diamondFrame = [
  for (final (color, _) in _diamondFacets) ...[color, color],
];

final _diamondStops = [
  for (var i = 0; i < _diamondFacets.length; i++) ...[
    i == 0 ? 0.0 : _diamondFacets[i - 1].$2,
    _diamondFacets[i].$2,
  ],
];

final _looks = {
  GameCardTier.common: const _Look(
    frameWidth: 6,
    frame: [_T.graphite1, _T.graphite2, _T.graphite3, _T.graphite4],
    frameStops: [0, 0.38, 0.66, 1],
  ),
  GameCardTier.rare: const _Look(
    frameWidth: 7,
    frame: [_T.bronze1, _T.bronze4, _T.bronze3, _T.bronze2, _T.bronze5],
    frameStops: [0, 0.26, 0.5, 0.72, 1],
    sheen: _T.sheenBronze,
    brushed: true,
    aura: _T.auraBronze,
  ),
  GameCardTier.superRare: const _Look(
    frameWidth: 8,
    frame: [_T.silver1, _T.silver2, _T.silver3, _T.silver4, _T.silver5],
    frameStops: [0, 0.26, 0.48, 0.7, 1],
    sheen: _T.sheen,
    brushed: true,
    aura: _T.auraRare,
  ),
  GameCardTier.legendary: const _Look(
    frameWidth: 9,
    frame: [_T.gold1, _T.gold2, _T.gold3, _T.gold4, _T.gold5],
    frameStops: [0, 0.24, 0.47, 0.69, 1],
    sheen: _T.sheenGold,
    aura: _T.auraEpic,
    corner: [_T.cornerGoldLight, _T.cornerGoldDeep],
    shine: _Shine.gold,
  ),
  GameCardTier.mythic: _Look(
    frameWidth: 10,
    frame: _diamondFrame,
    frameStops: _diamondStops,
    faceted: true,
    sheen: _T.sheenDiamond,
    aura: _T.auraDiamond,
    corner: const [_T.cornerDiamondLight, _T.cornerDiamondDeep],
    shine: _Shine.diamond,
  ),
};

/// Thẻ thành tích vẽ ở [achievementCardSize]. [pose] là độ nghiêng (-1..1 mỗi
/// chiều) mà viền, vệt sáng và ảnh chạy theo. Thẻ Huyền thoại và Thần thoại tự
/// chạy quầng sáng và sao nhấp nháy khi [animate]; tắt đi thì vẽ một khung
/// hình đứng yên, dùng cho test và ảnh tĩnh.
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

  /// Giây đã chạy, cho các lớp tự chuyển động của bậc có ánh.
  double _seconds = 0;

  bool get _animates =>
      widget.animate && _looks[widget.data.tier]!.shine != _Shine.none;

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
    final skin = RunCardSkin.of(context);
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
                  ? _Back(data: data, skin: skin, pose: pose)
                  : _Front(
                      data: data,
                      look: look,
                      skin: skin,
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
                  border: Border.all(color: skin.hairline),
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
Offset _lightAt(Offset pose) =>
    Offset(0.5 + pose.dx * 0.5, 0.5 + pose.dy * 0.5);

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
    final shine = look.shine;
    final Gradient gradient = look.faceted
        // Mặt cắt chỉ xoay theo độ nghiêng: đá thật không tự quay.
        ? SweepGradient(
            colors: look.frame,
            stops: look.frameStops,
            transform: GradientRotation(_deg(20 + tiltDeg * 6)),
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: look.frame,
            stops: look.frameStops,
            transform: GradientRotation(_deg(tiltDeg * 4)),
          );
    // Quầng của hai bậc trên cùng thở chậm, chu kỳ khoảng 3,6 giây.
    final breath = 0.775 + math.sin(seconds * 1.75) * 0.225;
    final aura = switch (look.aura) {
      final aura? when shine != _Shine.none => aura.withValues(
        alpha: aura.a * breath,
      ),
      final aura => aura,
    };
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
                BoxShadow(
                  color: aura,
                  blurRadius: switch (shine) {
                    _Shine.diamond => 46,
                    _Shine.gold => 40,
                    _Shine.none => 34,
                  },
                ),
              if (shine == _Shine.diamond)
                const BoxShadow(color: _T.auraDiamondOuter, blurRadius: 90),
            ],
          ),
        ),
        if (shine == _Shine.diamond)
          // Đốm sáng trắng chạy vòng quanh viền, như ánh đèn lướt qua mặt đá.
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    math.sin(seconds * 1.3) * 0.8,
                    math.cos(seconds * 1.1) * 0.8,
                  ),
                  radius: 0.3,
                  colors: [
                    _T.diamondFlare,
                    _T.diamondFlare.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        if (look.brushed)
          // Vân xước của đồng và bạc: vạch sáng tối 3px lặp lại.
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
        if (look.sheen != null)
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
    required this.skin,
    required this.pose,
    required this.seconds,
  });

  final AchievementCardData data;
  final _Look look;
  final RunCardSkin skin;
  final Offset pose;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final light = _lightAt(pose);
    final shine = look.shine;
    final accent = skin.accent(data.tier);
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
            child: data.art,
          ),
        ),
        if (look.sheen case final sheen?) _Sheen(light: light, color: sheen),
        if (shine != _Shine.none)
          IgnorePointer(
            child: CustomPaint(
              painter: _GlitterPainter(
                light,
                shine == _Shine.diamond ? _T.glitterDiamond : _T.glitterWarm,
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _Scrim.top(
            skin: skin,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 12, 0),
              // Khối km quyết định lớp phủ cao bao nhiêu; nhãn bậc nằm đè góc
              // phải như trước, chữ dài không đẩy nhau.
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.kind, style: label(accent, 11)),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // Hero có thể là tên vai backend gửi, dài bao nhiêu
                          // không biết trước: quá bề ngang thì thu nhỏ chứ không
                          // tràn.
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
                    ],
                  ),
                  Positioned(
                    top: 1,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            for (
                              var i = 0;
                              i < gameCardTiers[data.tier]!.gems;
                              i++
                            )
                              Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: _Gem(color: accent),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gameCardTiers[data.tier]!.label.toUpperCase(),
                          style: label(accent, 9.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Scrim.bottom(
            skin: skin,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 11),
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
                          style: TextStyle(color: ink.withValues(alpha: 0.62)),
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
                  _Title(text: data.title, tier: data.tier, skin: skin),
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
                  _Foot(
                    left: data.meta,
                    right: '3I RUN',
                    accent: accent,
                    ink: ink,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (data.stamp case final stamp?)
          Positioned(
            top: 58,
            right: 12,
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
        if (shine == _Shine.diamond)
          IgnorePointer(
            child: CustomPaint(
              painter: _StarPainter(seconds, count: 8, color: _T.starDiamond),
            ),
          ),
        GameCardGlare(at: light, strength: 0.38),
      ],
    );
  }
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

/// Lớp tối chỉ nằm sau khối chữ để chữ đọc được trên mọi tranh: đậm nhất ở
/// mép thẻ, nhạt dần qua vùng chữ, rồi tan hết ngay ngoài chữ. Cao theo khối
/// chữ (tên hai dòng thì phủ cao hơn), phần tranh không có chữ để nguyên.
class _Scrim extends StatelessWidget {
  _Scrim.top({required RunCardSkin skin, required this.child})
    : _fromTop = true,
      color = skin.shade,
      _edge = skin.scrimTop.$1,
      _inner = skin.scrimTop.$2,
      _fade = 40;

  _Scrim.bottom({required RunCardSkin skin, required this.child})
    : _fromTop = false,
      color = skin.shade,
      _edge = skin.scrimBottom.$1,
      _inner = skin.scrimBottom.$2,
      _fade = 48;

  final Color color;
  final Widget child;
  final bool _fromTop;

  /// Độ đậm ở mép thẻ và ở mép trong của khối chữ.
  final double _edge;
  final double _inner;

  /// Dải tan từ mép trong của khối chữ về trong suốt.
  final double _fade;

  @override
  Widget build(BuildContext context) {
    final outward = _fromTop ? Alignment.topCenter : Alignment.bottomCenter;
    final inward = _fromTop ? Alignment.bottomCenter : Alignment.topCenter;
    final text = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: outward,
          end: inward,
          colors: [
            color.withValues(alpha: _edge),
            color.withValues(alpha: _inner),
          ],
        ),
      ),
      child: child,
    );
    final fade = SizedBox(
      height: _fade,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: outward,
              end: inward,
              colors: [
                color.withValues(alpha: _inner),
                color.withValues(alpha: _inner * 0.4),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _fromTop ? [text, fade] : [fade, text],
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

/// Kim tuyến: hai lưới chấm nhỏ trôi ngược chiều nhau theo điểm sáng.
class _GlitterPainter extends CustomPainter {
  const _GlitterPainter(this.light, this.tint);

  final Offset light;

  /// Màu lưới chấm thứ hai: vàng ấm ở Huyền thoại, trắng băng ở Thần thoại.
  final Color tint;

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
    grid(29, 25, -light.dx * 50, light.dy * 80, 0.8, tint);
  }

  @override
  bool shouldRepaint(_GlitterPainter old) =>
      old.light != light || old.tint != tint;
}

/// Sao bốn cánh nhấp nháy lệch nhịp nhau, chu kỳ 2,4 giây.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.seconds, {this.count = 6, this.color = _T.star});

  final double seconds;
  final int count;
  final Color color;

  static const _spots = [
    (0.18, 0.22, 0.0),
    (0.78, 0.14, 0.7),
    (0.64, 0.46, 1.4),
    (0.30, 0.58, 2.1),
    (0.86, 0.66, 0.35),
    (0.12, 0.40, 1.05),
    (0.50, 0.30, 1.7),
    (0.70, 0.60, 2.4),
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
    for (final (x, y, delay) in _spots.take(count)) {
      final phase = ((seconds - delay) / 2.4) % 1;
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
  bool shouldRepaint(_StarPainter old) => old.seconds != seconds;
}

/// Mặt sau: huy hiệu 3I RUN, ngày nhận và bậc.
class _Back extends StatelessWidget {
  const _Back({required this.data, required this.skin, required this.pose});

  final AchievementCardData data;
  final RunCardSkin skin;
  final Offset pose;

  @override
  Widget build(BuildContext context) {
    if (data.backFace case final face?) {
      return Stack(
        fit: StackFit.expand,
        children: [
          face,
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
        GameCardGlare(at: _lightAt(pose), strength: 0.38),
      ],
    );
  }
}
