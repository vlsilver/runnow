import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/agents/agent_km.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';

/// Bậc thẻ bot trong ngày. Bậc đi theo số mốc ảnh chủ đã qua hôm nay; km của
/// từng mốc do backend giữ (`images.tiers`), app chỉ giữ chất liệu của bậc.
enum AgentCardTier {
  common('Thường', GameCardTier.common),
  silver('Bạc', GameCardTier.rare),
  gold('Vàng', GameCardTier.superRare),
  foil('Foil', GameCardTier.legendary);

  const AgentCardTier(this.label, this.material);

  final String label;

  /// Thẻ bot dùng chung khung, ánh xà cừ và đá với lá bài Ma Sói.
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
    required this.persona,
    required this.tier,
    required this.memoryCount,
    required this.memoryLimit,
    this.memories = const [],
    this.runKm,
    this.dm,
    this.images,
    this.budgetResting = false,
    this.status,
    this.createdAt,
    this.username,
    this.inPsc = false,
    this.learning = false,
    this.now,
  });

  final String name;
  final String persona;
  final AgentCardTier tier;
  final int memoryCount;
  final int memoryLimit;

  /// Vài mục nhớ đầu cho mặt sau.
  final List<String> memories;

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
  final bool inPsc;
  final bool learning;

  /// Giờ hiện tại để đếm "ngày thứ N"; null là lúc dựng.
  final DateTime? now;

  _Mood get _mood => budgetResting
      ? _Mood.sleepy
      : switch (tier) {
          AgentCardTier.common => _Mood.resting,
          AgentCardTier.silver => _Mood.awake,
          _ => _Mood.happy,
        };

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
}

/// Palette tối của hành đang chọn: thẻ luôn là vật thể tối, cả khi app sáng.
RunNowPalette _cardPalette(BuildContext context) => RunNowPalette.forSelection(
  context.runNowPalette.element,
  appearance: RunNowAppearance.dark,
);

/// Mặt trước thẻ bot, vẽ ở [gameCardSize].
class AgentBotCardFront extends StatelessWidget {
  const AgentBotCardFront({
    super.key,
    required this.data,
    this.holo = const Offset(0.4, 0.3),
  });

  final AgentBotCardData data;
  final Offset holo;

  @override
  Widget build(BuildContext context) {
    final p = _cardPalette(context);
    final t = gameCardTiers[data.tier.material]!;
    final ink = p.ink;
    final createdAt = data.createdAt;
    final runKm = data.runKm;
    return GameCardFrame(
      colors: t.frame,
      stops: t.frameStops,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Field(palette: p),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _CardCaps('MyBot', color: p.accent)),
                    _CardCaps(data.tier.label, color: t.gem),
                    for (var i = 0; i < t.gems; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: CustomPaint(
                          size: const Size(8, 10),
                          painter: GameCardGemPainter(t.gem),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  data.budgetResting ? '${data.name} đang nghỉ' : data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: ink,
                    shadows: [
                      const Shadow(
                        color: RunNowGameTokens.cardTextShadow,
                        offset: Offset(0, 2),
                      ),
                      Shadow(
                        color: p.accent.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                _Scene(data: data, palette: p, gem: t.gem),
                const SizedBox(height: 7),
                Text(
                  data.budgetResting
                      ? 'MyBot chạm trần chi phí hôm nay.'
                      : data.persona,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                    color: ink.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    if (data.dm case final dm?) ...[
                      Expanded(
                        child: _CardStat(
                          label: 'Tin',
                          used: dm.used,
                          max: dm.max,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    if (data.images case final images?) ...[
                      Expanded(
                        child: _CardStat(
                          label: 'Ảnh',
                          used: images.used,
                          max: images.max,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: _CardStat(
                        label: 'Nhớ',
                        used: data.memoryCount,
                        max: data.memoryLimit,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        createdAt == null
                            ? (runKm == null
                                  ? '3I RUN · MYBOT'
                                  : '${formatAgentKm(runKm)} km hôm nay')
                            : _dayLine(createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: ink.withValues(alpha: 0.66),
                        ),
                      ),
                    ),
                    if (data.username case final username?)
                      Flexible(
                        child: Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: p.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (t.holo > 0) GameCardHolo(strength: t.holo, at: holo),
          if (t.sparkle)
            IgnorePointer(
              child: CustomPaint(painter: GameCardSparklePainter(holo)),
            ),
          GameCardGlare(at: holo, strength: 0.4),
        ],
      ),
    );
  }

  String _dayLine(DateTime createdAt) {
    final n = agentDayCount(createdAt, data.now ?? DateTime.now());
    return n <= 1 ? 'Ngày đầu bên bạn' : 'Ngày thứ $n bên bạn';
  }
}

/// Mặt sau: tính cách, vài điều bot nhớ, bot đang ở đâu.
class AgentBotCardBack extends StatelessWidget {
  const AgentBotCardBack({
    super.key,
    required this.data,
    this.holo = const Offset(0.4, 0.3),
  });

  final AgentBotCardData data;
  final Offset holo;

  @override
  Widget build(BuildContext context) {
    final p = _cardPalette(context);
    final t = gameCardTiers[data.tier.material]!;
    final ink = p.ink;
    final body = TextStyle(fontSize: 11, height: 1.4, color: ink);
    final muted = ink.withValues(alpha: 0.62);
    final createdAt = data.createdAt;
    final places = [
      if (data.username != null) 'Trên Telegram',
      if (data.inPsc) 'Ở group PSC',
      if (data.learning) 'Đang tự học',
    ];
    return GameCardFrame(
      colors: t.frame,
      stops: t.frameStops,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Field(palette: p),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardCaps('Mặt sau · ${data.name}', color: p.accent),
                const SizedBox(height: 12),
                _CardCaps('Tính cách', color: muted),
                const SizedBox(height: 4),
                Text(
                  data.persona.isEmpty
                      ? 'Chưa có tính cách. Sửa bot để thêm.'
                      : data.persona,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: body,
                ),
                const SizedBox(height: 12),
                _CardCaps('Bot biết về bạn', color: muted),
                const SizedBox(height: 4),
                if (data.memories.isEmpty)
                  Text('Chưa nhớ gì.', style: body.copyWith(color: muted))
                else
                  for (final memory in data.memories.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· $memory',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body,
                      ),
                    ),
                if (places.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final place in places)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            place,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        createdAt == null
                            ? '3I RUN · MYBOT'
                            : 'Tạo ngày ${_date(createdAt)}',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ),
                    Text(
                      'Chạm để lật lại',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GameCardGlare(at: holo, strength: 0.4),
        ],
      ),
    );
  }

  static String _date(DateTime at) {
    final d = _vnDate(at);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/// Nền trong khung: ánh màu hành ở góc trên chìm dần vào nền tối.
class _Field extends StatelessWidget {
  const _Field({required this.palette});

  final RunNowPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.accentDeep, Colors.black, 0.68)!,
            Color.lerp(palette.background, Colors.black, 0.2)!,
            palette.background,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
    );
  }
}

class _CardCaps extends StatelessWidget {
  const _CardCaps(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: color,
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({required this.label, required this.used, required this.max});

  final String label;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    const ink = RunNowGameTokens.nightInk;
    final muted = ink.withValues(alpha: 0.62);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardCaps(label, color: muted),
          const SizedBox(height: 1),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$used'),
                TextSpan(
                  text: '/$max',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tranh giữa thẻ: trời theo màu hành, mặt trời khi đã chạy (trăng khi chưa),
/// đồi có đường chạy, robot đứng giữa.
class _Scene extends StatelessWidget {
  const _Scene({required this.data, required this.palette, required this.gem});

  final AgentBotCardData data;
  final RunNowPalette palette;
  final Color gem;

  @override
  Widget build(BuildContext context) {
    final runKm = data.runKm;
    final status = data.status;
    final day = data.tier != AgentCardTier.common && !data.budgetResting;
    return Container(
      height: 136,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(palette.accentDeep, Colors.black, day ? 0.45 : 0.72)!,
            Color.lerp(palette.accentDeep, Colors.black, 0.78)!,
            RunNowGameTokens.cardArt,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Stack(
        children: [
          // Có trạng thái thì pill trạng thái chiếm góc phải thay mặt trời,
          // để không đè lên ăng-ten bot ở giữa.
          if (status == null)
            Positioned(
              right: 18,
              top: 12,
              child: day
                  ? const _Sun(size: 22)
                  : const GameMoon(size: 22, glow: 18),
            ),
          Positioned.fill(
            child: CustomPaint(painter: GameCardHillsPainter(palette.accent)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CustomPaint(
                size: const Size(80, 88),
                painter: _MascotPainter(
                  mood: data._mood,
                  accent: palette.accent,
                  gem: gem,
                  initial: data.initial,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            right: status == null ? 50 : 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (runKm != null)
                  _ScenePill(
                    text: status == null
                        ? '${formatAgentKm(runKm)} km hôm nay'
                        : '${formatAgentKm(runKm)} km',
                  ),
                if (status != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: _ScenePill(text: status.text, icon: status.icon),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: ink),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              icon == null ? text : text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sun extends StatelessWidget {
  const _Sun({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [RunNowGameTokens.sunLight, RunNowGameTokens.sunMid],
          stops: [0, 0.7],
        ),
        boxShadow: [
          BoxShadow(
            color: RunNowGameTokens.sunMid.withValues(alpha: 0.6),
            blurRadius: 18,
          ),
        ],
      ),
    );
  }
}

/// Robot của bot, vẽ theo khung 128×140 rồi thu theo [size]. Mắt theo tâm
/// trạng: ngủ khi cả hệ thống nghỉ, lim dim khi chủ chưa chạy, mở khi đã qua
/// mốc đầu, cười khi lên Vàng trở lên. Không có trạng thái buồn.
class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.mood,
    required this.accent,
    required this.gem,
    required this.initial,
  });

  final _Mood mood;
  final Color accent;
  final Color gem;
  final String initial;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 140);
    final eye = Color.lerp(accent, Colors.white, 0.5)!;
    canvas.drawRRect(
      RRect.fromLTRBR(26, 106, 102, 140, const Radius.circular(17)),
      Paint()
        ..color = RunNowBotTokens.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(
      const Offset(64, 10),
      const Offset(64, 26),
      Paint()
        ..color = accent
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(64, 8), 6, Paint()..color = gem);
    const head = Rect.fromLTWH(18, 24, 92, 74);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(30)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RunNowBotTokens.shell, RunNowBotTokens.shellShade],
        ).createShader(head),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(28, 38, 100, 80, const Radius.circular(20)),
      Paint()..color = RunNowBotTokens.visor,
    );
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
    const body = Rect.fromLTWH(38, 100, 52, 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(14)),
      Paint()..color = accent,
    );
    final letter = TextPainter(
      text: TextSpan(
        text: initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    letter.paint(
      canvas,
      body.center - Offset(letter.width / 2, letter.height / 2),
    );
    letter.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.mood != mood ||
      old.accent != accent ||
      old.gem != gem ||
      old.initial != initial;
}

/// Thẻ bot trên tab: vuốt ngang để nghiêng (ánh thẻ chạy theo), chạm để lật.
/// Lần đầu hiện thì một vệt sáng quét qua thẻ, rồi đứng yên: không có
/// animation chạy mãi.
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sweep.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _sweep.value = 1;
      } else {
        unawaited(_sweep.forward());
      }
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _settle.dispose();
    _sweep.dispose();
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
    final height = widget.width * gameCardSize.height / gameCardSize.width;
    return Semantics(
      button: true,
      label: 'Lật thẻ bot',
      child: GestureDetector(
        onTap: _toggle,
        onHorizontalDragStart: (_) => _settle.stop(),
        onHorizontalDragUpdate: (d) => setState(
          () => _tilt = (_tilt + d.delta.dx / (widget.width / 2)).clamp(-1, 1),
        ),
        onHorizontalDragEnd: (_) {
          _tiltAtRelease = _tilt;
          unawaited(_settle.forward(from: 0));
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_flip, _sweep]),
          builder: (context, _) {
            final flip = Curves.easeInOutCubic.transform(_flip.value);
            final back = flip > 0.5;
            final sweep = Curves.easeOutCubic.transform(_sweep.value);
            final holo = Offset(
              0.5 + _tilt * 0.45 - 1.1 * (1 - sweep),
              0.3 + _tilt.abs() * 0.15,
            );
            final face = back
                ? AgentBotCardBack(data: widget.data, holo: holo)
                : AgentBotCardFront(data: widget.data, holo: holo);
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
                  child: FittedBox(child: face),
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
  final _cardKey = GlobalKey();
  final _shareKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await shareAgentCard(
        cardKey: _cardKey,
        shareOriginContext: _shareKey.currentContext ?? context,
        botName: widget.data.name,
      );
    } catch (error) {
      debugPrint('MyBot: khoe thẻ lỗi: $error');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Chưa khoe được thẻ, thử lại sau.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = gameCardTiers[widget.data.tier.material]!;
    const ink = RunNowGameTokens.nightInk;
    final label = Theme.of(context).textTheme.labelLarge;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
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
                  Text(
                    'Thẻ ${widget.data.name} lên ${widget.data.tier.label}!',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.035,
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: FittedBox(
                            child: AgentBotCardFront(
                              data: widget.data,
                              holo: const Offset(0.62, 0.32),
                            ),
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
                    key: _shareKey,
                    onPressed: _sharing ? null : _share,
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
