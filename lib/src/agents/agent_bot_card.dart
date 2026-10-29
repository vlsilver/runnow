import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/agents/agent_km.dart';
import 'package:myrun/src/agents/agent_look.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Bậc thẻ bot trong ngày. Bậc đi theo số mốc ảnh chủ đã qua hôm nay; km của
/// từng mốc do backend giữ (`images.tiers`), app chỉ giữ chất liệu của bậc.
enum AgentCardTier {
  common('Thường', GameCardTier.common),
  silver('Bạc', GameCardTier.superRare),
  gold('Vàng', GameCardTier.legendary),
  foil('Foil', GameCardTier.mythic);

  const AgentCardTier(this.label, this.material);

  final String label;

  /// Kim loại đúng tên bậc, mượn từ thang của thẻ thành tích: Thường sắt,
  /// Bạc bạc, Vàng vàng, Foil kim cương. Thang chung có thêm bậc đồng nên
  /// số đá ở góc thẻ là 1, 3, 4, 5, khớp số đá của cùng kim loại ở thẻ khác.
  final GameCardTier material;
}

/// Số mốc ảnh đã qua hôm nay.
int agentTiersReached(AgentImagesToday images) =>
    images.tiers.where((t) => images.runKm >= t.km).length;

/// Bậc khi đã qua [reached] trên [total] mốc: qua mốc cuối là Foil, mốc đầu là
/// Bạc, giữa là Vàng. Backend thêm mốc thì các mốc giữa cùng là Vàng.
AgentCardTier agentCardTierAt(int reached, int total) {
  if (reached <= 0) return AgentCardTier.common;
  if (reached >= total) return AgentCardTier.foil;
  return reached == 1 ? AgentCardTier.silver : AgentCardTier.gold;
}

AgentCardTier agentCardTier(AgentImagesToday? images) {
  if (images == null) return AgentCardTier.common;
  if (images.tiers.isEmpty) {
    // Backend cũ chưa gửi bảng mốc: chỉ biết chưa mở, đang giữa hay hết mốc.
    if (images.limit == 0) return AgentCardTier.common;
    return images.nextKm == null ? AgentCardTier.foil : AgentCardTier.silver;
  }
  return agentCardTierAt(agentTiersReached(images), images.tiers.length);
}

/// Ngày theo giờ VN, cùng mốc 0h với hạn mức của backend.
DateTime _vnDate(DateTime at) {
  final vn = at.toUtc().add(const Duration(hours: 7));
  return DateTime.utc(vn.year, vn.month, vn.day);
}

String agentVnDay(DateTime at) {
  final d = _vnDate(at);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Ngày thứ mấy kể từ ngày tạo bot, ngày tạo là ngày thứ 1.
int agentDayCount(DateTime createdAt, DateTime now) =>
    _vnDate(now).difference(_vnDate(createdAt)).inDays + 1;

enum _Mood { sleepy, resting, awake, happy }

/// Những gì thẻ bot vẽ, gom từ GET me để thẻ ở tab và thẻ ở màn lên bậc là
/// một.
class AgentBotCardData {
  const AgentBotCardData({
    required this.name,
    required this.tier,
    required this.memoryCount,
    required this.memoryLimit,
    this.voice,
    this.runKm,
    this.dm,
    this.images,
    this.budgetResting = false,
    this.status,
    this.createdAt,
    this.username,
    this.now,
    this.look = AgentLook.custom,
  });

  /// Thẻ của [agent] với lượt hôm nay trong [me]; tab MyBot và màn sửa bot
  /// dựng cùng một thẻ.
  factory AgentBotCardData.fromMe(AgentMe me, AgentProfile agent) {
    final today = me.today;
    final images = today?.images;
    final telegram = me.telegram;
    // Chạm trần chi phí thì mọi bot cùng nghỉ: nói ngay ở tên bot. Hết tin
    // chat riêng thì bot vẫn nói trong phòng, nên chỉ là một chip.
    final budget = today?.resting == AgentResting.budget;
    return AgentBotCardData(
      name: agent.name,
      voice: agent.voice,
      look: AgentLook.of(agent.look, agent.persona),
      tier: agentCardTier(images),
      memoryCount: me.memories.length,
      memoryLimit: me.memoryLimit,
      runKm: today?.dmByKm?.runKm ?? images?.runKm,
      dm: today == null ? null : (used: today.dmUsed, max: today.dmMax),
      images: images == null ? null : (used: images.used, max: images.limit),
      budgetResting: budget,
      status: budget
          ? (icon: Icons.bedtime_rounded, text: 'Quay lại lúc 0h')
          : today?.resting == AgentResting.dmLimit
          ? (icon: Icons.schedule_rounded, text: 'Hết tin · mở lại 0h')
          : null,
      createdAt: agent.createdAt,
      username: telegram != null && telegram.running
          ? telegram.botUsername
          : null,
    );
  }

  final String name;

  /// Câu cửa miệng backend rút từ lời bot đã nói, không phải chữ chủ viết.
  final String? voice;

  /// Đồ robot đeo trên thẻ.
  final AgentLook look;
  final AgentCardTier tier;
  final int memoryCount;
  final int memoryLimit;

  /// Km chạy và đi bộ hôm nay; null khi backend không gửi.
  final double? runKm;
  final ({int used, int max})? dm;
  final ({int used, int max})? images;

  /// Cả hệ thống chạm trần chi phí: bot ngủ.
  final bool budgetResting;

  /// Chip trạng thái trên tranh, vd. "Quay lại lúc 0h".
  final ({IconData icon, String text})? status;
  final DateTime? createdAt;

  /// Username của bot trên Telegram khi bot đang chạy.
  final String? username;

  /// Giờ hiện tại để đếm "ngày thứ N"; null là lúc dựng.
  final DateTime? now;

  _Mood get _mood => budgetResting
      ? _Mood.sleepy
      : switch (tier) {
          AgentCardTier.common => _Mood.resting,
          AgentCardTier.silver => _Mood.awake,
          _ => _Mood.happy,
        };

  /// Chưa có tên: thẻ "chưa rèn" ở màn tạo bot.
  bool get draft => name.trim().isEmpty;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  /// Kim loại của thẻ; thẻ chưa rèn là sắt.
  GameCardTier get _material => draft ? GameCardTier.common : tier.material;
}

/// Palette tối theo hành của bộ màu thẻ (classic thì hành của app): trời đêm
/// của thẻ theo màu hành, cả khi bộ màu sáng.
RunNowPalette _cardPalette(BuildContext context, RunCardSkin skin) =>
    RunNowPalette.forSelection(
      skin.element ?? context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );

/// Thẻ bot trên khung thẻ thành tích, cùng hệ với thẻ buổi chạy, Hành trình
/// và Ma Sói: chân dung robot phủ cả thẻ, tên bot, câu cửa miệng và số liệu
/// hôm nay; mặt sau là huy hiệu khắc đầu robot.
AchievementCardData agentCardData(AgentBotCardData data) {
  final draft = data.draft;
  final createdAt = data.createdAt;
  final runKm = data.runKm;
  final voice = data.voice?.trim() ?? '';
  String count(({int used, int max}) n) => '${n.used}/${n.max}';
  return AchievementCardData(
    tier: data._material,
    tierLabel: draft ? 'Chưa rèn' : data.tier.label,
    art: AgentBotArt(data: data),
    backFace: AgentBotMedal(data: data),
    kind: data.look == AgentLook.custom
        ? 'MYBOT'
        : 'MYBOT · ${data.look.title.toUpperCase()}',
    hero: draft
        ? 'TÊN BOT'
        : data.budgetResting
        ? '${data.name} đang nghỉ'.toUpperCase()
        : data.name.toUpperCase(),
    heroUnit: '',
    title: '',
    quote: data.budgetResting
        ? 'MyBot chạm trần chi phí hôm nay.'
        : voice.isEmpty || draft
        ? null
        : '“$voice”',
    stats: [
      if (runKm != null && !draft)
        (value: formatAgentRunKm(runKm), label: 'KM HÔM NAY'),
      if (data.dm case final dm?) (value: count(dm), label: 'TIN'),
      if (data.images case final images?) (value: count(images), label: 'ẢNH'),
      if (data.memoryLimit > 0)
        (value: '${data.memoryCount}/${data.memoryLimit}', label: 'NHỚ'),
    ],
    owner: draft
        ? 'BOT MỚI'
        : createdAt == null
        ? 'MYBOT'
        : _dayLine(createdAt, data.now ?? DateTime.now()),
    serial: '',
    desc: '',
    meta: switch (data.username) {
      final username? => '@$username',
      null => '',
    },
    date: '',
  );
}

/// Thẻ bot đem khoe. Thẻ đổi theo ngày (bậc, số liệu, ngày thứ N) nên mọi
/// thứ in trên thẻ vào [CardShareSubject.printed]; mỗi chủ chỉ có một bot nên
/// một id, file của ngày cũ bị thay.
CardShareSubject agentCardShareSubject(AgentBotCardData data) {
  final card = agentCardData(data);
  return CardShareSubject(
    id: 'mybot',
    printed: [
      // Mốc thiết kế thẻ bot: đổi khi đổi cách vẽ để file khoe cũ thôi dùng.
      'portrait',
      card.tier.name,
      card.tierLabel ?? '',
      card.kind,
      card.hero,
      card.quote ?? '',
      for (final stat in card.stats ?? const <AchievementStat>[])
        '${stat.label}=${stat.value}',
      card.owner,
      card.meta,
      data.look.name,
      data._mood.name,
      data.status?.text ?? '',
    ].join('|'),
    text: data.draft
        ? 'Thẻ MyBot của mình trên 3i'
        : 'Thẻ MyBot ${data.name} của mình\nChia sẻ từ 3i',
  );
}

/// Màn khoe chung của thẻ thành tích: chọn bộ màu, gửi ảnh hai mặt hay video
/// 3D.
Future<void> showAgentCardShare(BuildContext context, AgentBotCardData data) =>
    showCardShare(
      context,
      subject: agentCardShareSubject(data),
      data: agentCardData(data),
    );

String _dayLine(DateTime createdAt, DateTime now) {
  final n = agentDayCount(createdAt, now);
  return n <= 1 ? 'NGÀY ĐẦU BÊN BẠN' : 'NGÀY THỨ $n BÊN BẠN';
}

enum _Sky { draft, night, dawn, dusk, aurora }

/// Tranh mặt trước: chân dung robot ló lên khỏi chân trời. Trời theo bậc:
/// đêm theo màu hành, Bạc bình minh, Vàng hoàng hôn với mặt trời thành quầng
/// sau đầu, Foil cực quang. Bot nghỉ là đêm, thẻ chưa rèn là nền trơn.
class AgentBotArt extends StatelessWidget {
  const AgentBotArt({super.key, required this.data});

  final AgentBotCardData data;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final p = _cardPalette(context, skin);
    final deep = p.accentDeep;
    final draft = data.draft;
    final sky = draft
        ? _Sky.draft
        : data.budgetResting
        ? _Sky.night
        : switch (data.tier) {
            AgentCardTier.common => _Sky.night,
            AgentCardTier.silver => _Sky.dawn,
            AgentCardTier.gold => _Sky.dusk,
            AgentCardTier.foil => _Sky.aurora,
          };
    final colors = switch (sky) {
      _Sky.draft => [
        Color.lerp(p.background, Colors.black, 0.35)!,
        Color.lerp(p.background, Colors.white, 0.04)!,
      ],
      _Sky.night => [
        Color.lerp(deep, Colors.black, 0.82)!,
        Color.lerp(deep, Colors.black, 0.62)!,
        Color.lerp(deep, Colors.black, 0.55)!,
      ],
      // Trời đêm đã theo hành; trời bậc cao giữ cảnh, chỉ nhuốm màu bộ thẻ.
      _Sky.dawn => [
        for (final c in const [
          RunNowBotCardTokens.dawnTop,
          RunNowBotCardTokens.dawnMid,
          RunNowBotCardTokens.dawnBottom,
        ])
          skin.tintArt(c),
      ],
      _Sky.dusk => [
        for (final c in const [
          RunNowBotCardTokens.duskTop,
          RunNowBotCardTokens.duskMid,
          RunNowBotCardTokens.duskBottom,
        ])
          skin.tintArt(c),
      ],
      _Sky.aurora => [
        for (final c in const [
          RunNowBotCardTokens.auroraTop,
          RunNowBotCardTokens.auroraMid,
          RunNowBotCardTokens.auroraBottom,
        ])
          skin.tintArt(c),
      ],
    };
    final status = data.status;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _PortraitPainter(
              sky: sky,
              colors: colors,
              mascot: _MascotPainter(
                mood: data._mood,
                look: data.look,
                accent: p.accent,
                gem: gameCardTiers[data._material]!.gem,
                initial: data.initial,
                ghost: draft,
                legs: false,
              ),
            ),
          ),
        ),
        // Tranh tràn 10 điểm mỗi bên: chip cách mép thẻ 17 như ô đá bên trái.
        if (status != null && !draft)
          Positioned(
            top: 27,
            right: 27,
            child: _ScenePill(text: status.text, icon: status.icon),
          ),
      ],
    );
  }
}

class _PortraitPainter extends CustomPainter {
  const _PortraitPainter({
    required this.sky,
    required this.colors,
    required this.mascot,
  });

  final _Sky sky;
  final List<Color> colors;
  final _MascotPainter mascot;

  // Tranh tràn 10 điểm quanh thẻ 300x420 nên vẽ trên khổ 320 ngang. Chân trời
  // ở y 232 của thẻ, ngay trên khối chữ; robot phóng 1,6 lần, đầu chiếm gần
  // nửa trên, nhích lên vừa đủ để chữ trên ngực nằm trọn trên đồi.
  static const _width = 320.0;
  static const _horizon = 242.0;
  static const _scale = 1.6;
  static const _lift = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _width;
    final h = size.height / k;
    canvas
      ..save()
      ..scale(k)
      ..drawRect(
        Rect.fromLTWH(0, 0, _width, h),
        Paint()..color = RunNowBotCardTokens.ground,
      );
    const skyRect = Rect.fromLTWH(0, 0, _width, _horizon + 10);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(skyRect),
    );
    void stars(int count) => paintStars(
      canvas,
      const Size(_width, _horizon - 60),
      count: count,
      seed: 7,
      color: Colors.white,
      maxY: 1,
    );
    switch (sky) {
      case _Sky.draft:
        break;
      case _Sky.night:
        stars(30);
        _moon(
          canvas,
          const Offset(250, 66),
          11,
          RunNowBotCardTokens.moon,
          0.08,
        );
      case _Sky.dawn:
        stars(14);
        _moon(
          canvas,
          const Offset(246, 70),
          16,
          RunNowBotCardTokens.dawnMoon,
          0.1,
        );
      case _Sky.dusk:
        const sun = Offset(_width / 2, _horizon - 70);
        canvas.drawCircle(
          sun,
          96,
          Paint()
            ..shader = RadialGradient(
              colors: [
                RunNowBotCardTokens.sunCore,
                RunNowBotCardTokens.sunHalo,
                RunNowBotCardTokens.sunHalo.withValues(alpha: 0),
              ],
              stops: const [0, 0.62, 1],
            ).createShader(Rect.fromCircle(center: sun, radius: 96)),
        );
      case _Sky.aurora:
        stars(30);
        _aurora(canvas);
    }
    canvas
      ..save()
      ..translate(_width / 2 - 64 * _scale, -_lift);
    mascot.paint(canvas, _MascotPainter.sizeFor(128 * _scale));
    canvas.restore();
    final ridge = Path()
      ..moveTo(0, _horizon + 6)
      ..cubicTo(100, _horizon - 4, 220, _horizon - 4, _width, _horizon + 6);
    canvas
      ..drawPath(
        Path.from(ridge)
          ..lineTo(_width, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = RunNowBotCardTokens.ground,
      )
      ..drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.1),
      )
      ..restore();
  }

  void _moon(Canvas canvas, Offset c, double r, Color color, double glow) {
    canvas
      ..drawCircle(c, r * 2, Paint()..color = color.withValues(alpha: glow))
      ..drawCircle(c, r, Paint()..color = color);
  }

  /// Bốn dải cực quang mờ vắt ngang trời, hai dải trên nghiêng lên, hai dải
  /// dưới nghiêng xuống.
  void _aurora(Canvas canvas) {
    void band(
      Offset c,
      double rx,
      double ry,
      Offset pivot,
      double turn,
      Color color,
    ) {
      canvas
        ..save()
        ..translate(pivot.dx, pivot.dy)
        ..rotate(turn)
        ..translate(-pivot.dx, -pivot.dy)
        ..drawOval(
          Rect.fromCenter(center: c, width: rx * 2, height: ry * 2),
          Paint()
            ..color = color
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        )
        ..restore();
    }

    const up = Offset(160, 68);
    const down = Offset(160, 118);
    const tiltUp = -8 * math.pi / 180;
    const tiltDown = 6 * math.pi / 180;
    band(
      up,
      190,
      26,
      up,
      tiltUp,
      RunNowBotCardTokens.auroraGreen.withValues(alpha: 0.38),
    );
    band(
      const Offset(210, 64),
      90,
      20,
      up,
      tiltUp,
      RunNowBotCardTokens.auroraPink.withValues(alpha: 0.34),
    );
    band(
      down,
      170,
      20,
      down,
      tiltDown,
      RunNowBotCardTokens.auroraViolet.withValues(alpha: 0.38),
    );
    band(
      const Offset(100, 120),
      80,
      16,
      down,
      tiltDown,
      RunNowBotCardTokens.auroraBlue.withValues(alpha: 0.34),
    );
  }

  @override
  bool shouldRepaint(_PortraitPainter old) =>
      old.sky != sky ||
      !listEquals(old.colors, colors) ||
      old.mascot.shouldRepaint(mascot);
}

/// Mặt sau: đầu robot khắc trên huy hiệu kim loại theo bậc, đeo đúng đồ của
/// bot, vòng chữ MYBOT · 3I RUN. Không in tính cách hay điều bot nhớ: khoe
/// thẻ chụp đúng mặt đang hiện, mà điều bot nhớ là chuyện riêng của chủ.
class AgentBotMedal extends StatelessWidget {
  const AgentBotMedal({super.key, required this.data});

  final AgentBotCardData data;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MedalPainter(
          metal: gameCardTiers[data._material]!,
          mood: data._mood,
          look: data.look,
          ghost: data.draft,
          top: skin.tintArt(RunNowBotCardTokens.backTop),
          bottom: skin.tintArt(RunNowBotCardTokens.backBottom),
        ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter({
    required this.metal,
    required this.mood,
    required this.look,
    required this.ghost,
    required this.top,
    required this.bottom,
  });

  final GameCardTierStyle metal;
  final _Mood mood;
  final AgentLook look;
  final bool ghost;

  /// Nền trên và dưới, đã nhuốm theo bộ màu thẻ.
  final Color top;
  final Color bottom;

  // Toạ độ trên thẻ 300 ngang: huy hiệu giữa thẻ, hơi lệch lên để chữ MYBOT
  // nằm dưới.
  static const _width = 300.0;
  static const _center = Offset(150, 196);
  static const _r = 84.0;
  static const _headScale = 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _width;
    final h = size.height / k;
    canvas
      ..save()
      ..scale(k);
    final rect = Rect.fromLTWH(0, 0, _width, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );
    paintStars(
      canvas,
      Size(_width, h),
      count: 46,
      seed: 3,
      color: Colors.white,
      maxY: 1,
    );
    const c = _center, r = _r;
    final glow = Rect.fromCircle(center: c, radius: r * 1.9);
    canvas.drawCircle(
      c,
      r * 1.9,
      Paint()
        ..shader = RadialGradient(
          colors: [
            metal.gem.withValues(alpha: 0.22),
            metal.gem.withValues(alpha: 0.22),
            metal.gem.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(glow),
    );
    final medal = Rect.fromCircle(center: c, radius: r);
    LinearGradient metalFrom(Alignment begin, Alignment end) => LinearGradient(
      begin: begin,
      end: end,
      colors: metal.frame,
      stops: metal.frameStops,
    );
    // Lòng huy hiệu đổ sáng ngược vành nên trông lõm xuống.
    final shine = metalFrom(Alignment.topLeft, Alignment.bottomRight);
    final dish = metalFrom(Alignment.bottomRight, Alignment.topLeft);
    final ink = Color.lerp(
      metal.frame.first,
      Colors.black,
      0.35,
    )!.withValues(alpha: 0.9);
    const field = r - 20;
    canvas
      ..drawCircle(
        c + const Offset(3, 8),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawCircle(c, r, Paint()..shader = shine.createShader(medal))
      ..drawCircle(c, r - 4, _ring(Colors.black.withValues(alpha: 0.25), 1))
      ..drawCircle(c, field, Paint()..shader = dish.createShader(medal))
      ..drawCircle(c, field, _ring(Colors.black.withValues(alpha: 0.35), 1.5));
    paintRingText(canvas, c, r - 10, 'MYBOT · 3I RUN · ', ink);
    // Đầu robot khắc: một lớp sáng lệch xuống dưới phải làm mép khắc, rồi
    // lớp mực; kính và nét ngăn đồ đeo khoét lộ lòng huy hiệu.
    const s = _headScale;
    final head = _MascotPainter.sizeFor(128 * s);
    for (final (offset, color) in [
      (
        const Offset(0.8, 0.8),
        RunNowCardSceneTokens.medalShine.withValues(alpha: 0.5),
      ),
      (Offset.zero, ink),
    ]) {
      canvas
        ..save()
        ..translate(c.dx - 64 * s + offset.dx, c.dy - 76 * s + offset.dy);
      _MascotPainter(
        mood: mood,
        look: look,
        accent: color,
        gem: color,
        initial: '',
        ghost: ghost,
        body: false,
        legs: false,
        engrave: color,
      ).paint(canvas, head);
      canvas.restore();
    }
    final word = TextPainter(
      text: TextSpan(
        text: 'MYBOT',
        style: TextStyle(
          fontFamily: 'Barlow Condensed',
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 6,
          color: metal.gem.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Khoảng chữ cuối cũng cộng letterSpacing: bù nửa để chữ đứng giữa.
    word.paint(canvas, Offset((_width - word.width + 6) / 2, 372));
    word.dispose();
    canvas.restore();
  }

  Paint _ring(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.metal != metal ||
      old.mood != mood ||
      old.look != look ||
      old.ghost != ghost ||
      old.top != top ||
      old.bottom != bottom;
}

class _ScenePill extends StatelessWidget {
  const _ScenePill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const ink = RunNowGameTokens.nightInk;
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            icon == null ? text : text.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Robot của bot, vẽ theo khung 128×184 (chừa 24 phía trên cho nón) rồi thu
/// theo size. Mắt theo tâm trạng: ngủ khi cả hệ thống nghỉ, lim dim khi chủ
/// chưa chạy, mở khi đã qua mốc đầu, cười khi lên Vàng trở lên. Không có
/// trạng thái buồn. Đồ đeo theo kiểu bot; [ghost] là thẻ chưa có tên.
/// Không [body] thì chỉ còn đầu và đồ đeo; [engrave] vẽ cả con một màu, kính
/// và nét ngăn đồ đeo khoét trong suốt để lộ nền bên dưới, như khắc.
class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.mood,
    required this.look,
    required this.accent,
    required this.gem,
    required this.initial,
    this.ghost = false,
    this.body = true,
    this.legs = true,
    this.engrave,
  });

  final _Mood mood;
  final AgentLook look;
  final Color accent;
  final Color gem;
  final String initial;
  final bool ghost;
  final bool body;
  final bool legs;
  final Color? engrave;

  static const _frame = Size(128, 184);

  /// Nét khoét của bản khắc: xoá lớp đang vẽ để nền bên dưới lộ ra.
  static final _hole = Paint()..blendMode = BlendMode.clear;

  static Size sizeFor(double width) =>
      Size(width, width * _frame.height / _frame.width);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _frame.width, size.height / _frame.height);
    canvas.translate(0, 24);
    final ink = engrave;
    // Bản khắc vẽ trên một lớp riêng để nét khoét chỉ xoá chính con robot.
    if (ink != null) canvas.saveLayer(null, Paint());
    Paint fill(Color color) => Paint()..color = ink ?? color;
    final shell = ghost ? RunNowBotTokens.ghost : RunNowBotTokens.shell;
    final eye = ink ?? Color.lerp(accent, Colors.white, 0.5)!;
    final dressed = !ghost;
    if (body) {
      if (legs) {
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(64, 152), width: 80, height: 12),
          Paint()
            ..color = RunNowBotTokens.shadow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        final leg = fill(ghost ? RunNowBotTokens.ghost : RunNowBotTokens.leg);
        for (final x in [44.0, 68.0]) {
          canvas.drawRRect(
            RRect.fromLTRBR(x, 128, x + 16, 148, const Radius.circular(5)),
            leg,
          );
        }
      }
      final arm = fill(shell)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(42, 108), const Offset(26, 126), arm);
      canvas.drawLine(const Offset(86, 108), const Offset(102, 126), arm);
      const chest = Rect.fromLTWH(38, 100, 52, 34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chest, const Radius.circular(14)),
        fill(ghost ? RunNowBotTokens.ghost : accent),
      );
      if (!ghost && ink == null) _letter(canvas, chest.center);
      if (dressed && look == AgentLook.coach) _whistle(canvas, fill);
    }
    if (ghost || (look != AgentLook.funny && look != AgentLook.coach)) {
      canvas.drawLine(
        const Offset(64, 10),
        const Offset(64, 26),
        fill(ghost ? RunNowBotTokens.ghostInk : accent)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        const Offset(64, 8),
        6,
        fill(ghost ? RunNowBotTokens.ghostInk : gem),
      );
    }
    if (dressed && look == AgentLook.chill) {
      _headphones(canvas, fill, back: true);
    }
    const head = Rect.fromLTWH(18, 24, 92, 74);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(30)),
      ink != null || ghost
          ? fill(RunNowBotTokens.ghost)
          : (Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RunNowBotTokens.shell, RunNowBotTokens.shellShade],
              ).createShader(head)),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(28, 38, 100, 80, const Radius.circular(20)),
      ink != null
          ? _hole
          : (Paint()
              ..color = ghost
                  ? RunNowBotTokens.ghostVisor
                  : RunNowBotTokens.visor),
    );
    if (ghost) {
      _text(
        canvas,
        '?',
        const Offset(64, 59),
        ink ?? RunNowBotTokens.ghostInk,
        26,
      );
    } else {
      _eyes(canvas, eye);
    }
    if (dressed) {
      switch (look) {
        case AgentLook.funny:
          _partyHat(canvas, fill);
        case AgentLook.chill:
          _headphones(canvas, fill, back: false);
        case AgentLook.coach:
          _cap(canvas, fill);
        case AgentLook.custom:
          _scarf(canvas, fill);
      }
    }
    if (ink != null) canvas.restore();
    canvas.restore();
  }

  /// Đồ đeo: tô [color], bản khắc thêm viền khoét để tách khỏi đầu.
  void _piece(Canvas canvas, Path path, Paint paint) {
    canvas.drawPath(path, paint);
    if (engrave != null) {
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  void _eyes(Canvas canvas, Color eye) {
    final line = Paint()
      ..color = eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case _Mood.happy:
        for (final x in [50.0, 78.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x - 7, 62)
              ..quadraticBezierTo(x, 51, x + 7, 62),
            line,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(54, 70)
            ..quadraticBezierTo(64, 80, 74, 70),
          line..strokeWidth = 3,
        );
      case _Mood.awake:
        for (final x in [50.0, 78.0]) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, 59), width: 14, height: 18),
            Paint()..color = eye,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(56, 71)
            ..quadraticBezierTo(64, 77, 72, 71),
          line..strokeWidth = 3,
        );
      case _Mood.resting:
        for (final x in [50.0, 78.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, 61), width: 14, height: 7),
              const Radius.circular(4),
            ),
            Paint()..color = eye,
          );
        }
      case _Mood.sleepy:
        for (final x in [50.0, 78.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x - 7, 58)
              ..quadraticBezierTo(x, 66, x + 7, 58),
            line,
          );
        }
    }
  }

  void _letter(Canvas canvas, Offset center) =>
      _text(canvas, initial, center, Colors.white, 20);

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        // TextPainter không đọc theme của app nên phải nêu font, không thì
        // chữ rơi về font mặc định của máy.
        style: TextStyle(
          fontFamily: 'Exo 2',
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  void _partyHat(Canvas canvas, Paint Function(Color) fill) {
    final hat = Path()
      ..moveTo(40, 30)
      ..lineTo(88, 30)
      ..lineTo(64, -14)
      ..close();
    _piece(canvas, hat, fill(RunNowBotTokens.partyHat));
    canvas.save();
    canvas.clipPath(hat);
    final stripe = engrave != null
        ? (Paint()
            ..blendMode = BlendMode.clear
            ..strokeWidth = 2.4)
        : (Paint()
            ..color = RunNowBotTokens.partyGold
            ..strokeWidth = 5);
    canvas.drawLine(const Offset(40, 15), const Offset(88, 15), stripe);
    canvas.drawLine(const Offset(40, 1), const Offset(88, 1), stripe);
    canvas.restore();
    canvas.drawCircle(
      const Offset(64, -15),
      6,
      fill(RunNowBotTokens.partyGold),
    );
  }

  /// Quai vẽ sau đầu, hai tai nghe vẽ đè lên mép đầu.
  void _headphones(
    Canvas canvas,
    Paint Function(Color) fill, {
    required bool back,
  }) {
    if (back) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(64, 62), radius: 50),
        math.pi,
        math.pi,
        false,
        fill(RunNowBotTokens.headband)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      return;
    }
    for (final left in [8.0, 104.0]) {
      _piece(
        canvas,
        Path()..addRRect(
          RRect.fromLTRBR(left, 46, left + 16, 78, const Radius.circular(7)),
        ),
        fill(accent),
      );
    }
  }

  void _cap(Canvas canvas, Paint Function(Color) fill) {
    _piece(
      canvas,
      Path()
        ..moveTo(20, 46)
        ..quadraticBezierTo(64, -6, 108, 46)
        ..close(),
      fill(RunNowBotTokens.cap),
    );
    _piece(
      canvas,
      Path()..addOval(
        Rect.fromCenter(center: const Offset(100, 44), width: 40, height: 10),
      ),
      fill(RunNowBotTokens.capBrim),
    );
    canvas.drawCircle(
      const Offset(64, 21),
      3,
      engrave != null ? _hole : (Paint()..color = RunNowBotTokens.capBrim),
    );
  }

  /// Còi đeo lệch sang trái để không che chữ trên ngực.
  void _whistle(Canvas canvas, Paint Function(Color) fill) {
    canvas.drawPath(
      Path()
        ..moveTo(52, 100)
        ..lineTo(40, 114),
      fill(RunNowBotTokens.lanyard)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(30, 112, 46, 122, const Radius.circular(3)),
      fill(RunNowBotTokens.whistle),
    );
  }

  void _scarf(Canvas canvas, Paint Function(Color) fill) {
    final scarf = fill(RunNowBotTokens.scarf);
    _piece(
      canvas,
      Path()
        ..moveTo(32, 93)
        ..quadraticBezierTo(64, 107, 96, 93)
        ..lineTo(96, 101)
        ..quadraticBezierTo(64, 114, 32, 101)
        ..close(),
      scarf,
    );
    _piece(
      canvas,
      Path()
        ..moveTo(80, 102)
        ..lineTo(92, 126)
        ..lineTo(78, 122)
        ..close(),
      scarf,
    );
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.mood != mood ||
      old.look != look ||
      old.accent != accent ||
      old.gem != gem ||
      old.initial != initial ||
      old.ghost != ghost ||
      old.body != body ||
      old.legs != legs ||
      old.engrave != engrave;
}

/// Robot ngoài thẻ, vd. ở ô chọn kiểu bot: mắt mở, đồ đeo theo [look].
class AgentMascot extends StatelessWidget {
  const AgentMascot({super.key, required this.look, required this.width});

  final AgentLook look;
  final double width;

  @override
  Widget build(BuildContext context) {
    final accent = context.runNowPalette.accent;
    return CustomPaint(
      size: _MascotPainter.sizeFor(width),
      painter: _MascotPainter(
        mood: _Mood.awake,
        look: look,
        accent: accent,
        gem: accent,
        initial: '',
      ),
    );
  }
}

/// Thẻ bot trên tab: vuốt ngang để nghiêng (ánh thẻ chạy theo), chạm để lật.
/// Lần đầu hiện thì một vệt sáng quét qua thẻ, rồi thẻ tự lắc nhẹ qua lại để
/// người xem thấy ánh thẻ chạy mà không phải tự vuốt. Máy bật giảm chuyển
/// động thì thẻ đứng yên.
class AgentBotCardView extends StatefulWidget {
  const AgentBotCardView({super.key, required this.data, required this.width});

  final AgentBotCardData data;
  final double width;

  @override
  State<AgentBotCardView> createState() => _AgentBotCardViewState();
}

class _AgentBotCardViewState extends State<AgentBotCardView>
    with TickerProviderStateMixin {
  late final _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// Biên độ tự lắc, cùng thang với [_tilt]: khoảng 8° mỗi bên.
  static const _idleSway = 0.45;
  bool _dragging = false;

  /// Độ nghiêng -1..1 theo ngón tay; thả tay thì về 0.
  double _tilt = 0;
  double _tiltAtRelease = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(
        () => _tilt =
            _tiltAtRelease * (1 - Curves.easeOutBack.transform(_settle.value)),
      );
    });
    _settle.addStatusListener((status) {
      if (status == AnimationStatus.completed) _startIdle();
    });
    _idle.addListener(() {
      setState(() => _tilt = math.sin(_idle.value * 2 * math.pi) * _idleSway);
    });
  }

  /// Lắc từ giữa (sin 0) nên nối liền với thẻ vừa về thẳng.
  void _startIdle() {
    if (!mounted || _dragging || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _idle.value = 0;
    unawaited(_idle.repeat());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sweep.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _sweep.value = 1;
      } else {
        _sweep.forward().whenCompleteOrCancel(_startIdle);
      }
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _settle.dispose();
    _sweep.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_flip.status
        case AnimationStatus.forward || AnimationStatus.completed) {
      unawaited(_flip.reverse());
    } else {
      unawaited(_flip.forward());
    }
  }

  @override
  Widget build(BuildContext context) {
    final height =
        widget.width * achievementCardSize.height / achievementCardSize.width;
    final card = agentCardData(widget.data);
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: 'Lật thẻ bot',
      child: GestureDetector(
        onTap: _toggle,
        onHorizontalDragStart: (_) {
          _dragging = true;
          _idle.stop();
          _settle.stop();
        },
        onHorizontalDragUpdate: (d) => setState(
          () => _tilt = (_tilt + d.delta.dx / (widget.width / 2)).clamp(-1, 1),
        ),
        onHorizontalDragEnd: (_) {
          _dragging = false;
          _tiltAtRelease = _tilt;
          unawaited(_settle.forward(from: 0));
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_flip, _sweep]),
          builder: (context, _) {
            final flip = Curves.easeInOutCubic.transform(_flip.value);
            final back = flip > 0.5;
            final sweep = Curves.easeOutCubic.transform(_sweep.value);
            // Vệt sáng đi từ ngoài mép trái vào theo độ nghiêng. Chặn ở -1,4
            // vì tranh lệch 7 điểm mỗi đơn vị nghiêng mà chỉ tràn 10 điểm.
            final pose = Offset(
              (_tilt * 0.9 - 2.4 * (1 - sweep)).clamp(-1.4, 1.0),
              -_tilt.abs() * 0.3,
            );
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(flip * math.pi + _tilt * 0.32)
                ..rotateX(-_tilt.abs() * 0.04),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(back ? math.pi : 0),
                child: SizedBox(
                  width: widget.width,
                  height: height,
                  child: FittedBox(
                    child: AchievementCard(
                      data: card,
                      pose: pose,
                      back: back,
                      animate: animate,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bậc thẻ đã khoe trong ngày, giữ trên máy để màn lên bậc chỉ hiện một lần
/// cho mỗi bậc mỗi ngày.
class AgentTierSeen {
  AgentTierSeen({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String uid) => 'mybot_tier_seen_v1_$uid';

  /// Hôm nay ([day], giờ VN) đã thấy bậc thấp hơn [reached] thì hiện. Đọc lỗi
  /// thì không hiện, để lỗi máy không biến thành màn chúc mừng lặp lại.
  Future<bool> shouldReveal(String uid, String day, int reached) async {
    if (reached <= 0) return false;
    try {
      final saved = await _storage.read(key: _key(uid));
      final (savedDay, savedReached) = switch (saved?.split(':')) {
        [final d, final r] => (d, int.tryParse(r) ?? 0),
        _ => ('', 0),
      };
      return savedDay != day || savedReached < reached;
    } catch (error) {
      debugPrint('MyBot: đọc bậc thẻ đã khoe lỗi: $error');
      return false;
    }
  }

  Future<void> markSeen(String uid, String day, int reached) =>
      _storage.write(key: _key(uid), value: '$day:$reached');
}

final agentTierSeenProvider = Provider<AgentTierSeen>((ref) => AgentTierSeen());

/// Màn lên bậc: thẻ mới giữa tia sáng màu bậc, mở được bao nhiêu tin và ảnh,
/// chat ngay hay khoe thẻ.
Future<void> showAgentTierReveal(
  BuildContext context, {
  required AgentBotCardData data,
  required double milestoneKm,
  required List<String> unlocked,
  String? next,
  required VoidCallback onChat,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (context, _, _) => _TierReveal(
      data: data,
      milestoneKm: milestoneKm,
      unlocked: unlocked,
      next: next,
      onChat: onChat,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.86, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _TierReveal extends StatefulWidget {
  const _TierReveal({
    required this.data,
    required this.milestoneKm,
    required this.unlocked,
    required this.next,
    required this.onChat,
  });

  final AgentBotCardData data;
  final double milestoneKm;
  final List<String> unlocked;
  final String? next;
  final VoidCallback onChat;

  @override
  State<_TierReveal> createState() => _TierRevealState();
}

class _TierRevealState extends State<_TierReveal> {
  void _share() => unawaited(showAgentCardShare(context, widget.data));

  @override
  Widget build(BuildContext context) {
    final t = gameCardTiers[widget.data.tier.material]!;
    const ink = RunNowGameTokens.nightInk;
    final label = Theme.of(context).textTheme.labelLarge;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Nền đặc: tab phía sau lộ ra qua lớp mờ thì rối mắt và tranh
          // phần chú ý với thẻ.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 0.86,
                  colors: [
                    RunNowBotCardTokens.revealGlow,
                    RunNowBotCardTokens.revealEdge,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _RaysPainter(t.gem))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: ink),
                    ),
                  ),
                  Text(
                    'BẠN VỪA QUA ${formatAgentKm(widget.milestoneKm)} KM',
                    style: TextStyle(
                      color: t.gem,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Tên bot một dòng, bậc mới một dòng; tên dài thì còn một
                  // dòng để xuống mà vẫn thấy bậc.
                  Text(
                    'Thẻ ${widget.data.name}\nlên ${widget.data.tier.label}!',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 34,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.035,
                        child: FittedBox(
                          child: AchievementCard(
                            data: agentCardData(widget.data),
                            pose: const Offset(0.24, -0.1),
                            animate: !MediaQuery.disableAnimationsOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final text in widget.unlocked)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: t.gem.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: t.gem.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              color: t.gem,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (widget.next case final next?) ...[
                    const SizedBox(height: 10),
                    Text(
                      next,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onChat();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: t.gem,
                      foregroundColor: RunNowGameTokens.onGold,
                      minimumSize: const Size.fromHeight(54),
                      textStyle: label?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      'Chat với ${widget.data.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _share,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(color: ink.withValues(alpha: 0.24)),
                      textStyle: label?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 19),
                    label: const Text('Khoe thẻ'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tia sáng màu bậc toả từ sau thẻ.
class _RaysPainter extends CustomPainter {
  const _RaysPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final radius = size.longestSide;
    canvas.drawCircle(
      center,
      radius * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.42), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.5)),
    );
    final ray = Paint()..color = color.withValues(alpha: 0.13);
    const count = 20;
    for (var i = 0; i < count; i++) {
      final a = i * 2 * math.pi / count;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + radius * math.cos(a),
            center.dy + radius * math.sin(a),
          )
          ..lineTo(
            center.dx + radius * math.cos(a + 0.1),
            center.dy + radius * math.sin(a + 0.1),
          )
          ..close(),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}
