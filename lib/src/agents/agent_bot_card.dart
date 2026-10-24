import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/agents/agent_km.dart';
import 'package:myrun/src/agents/agent_look.dart';
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
      persona: agent.persona,
      look: AgentLook.of(agent.look, agent.persona),
      tier: agentCardTier(images),
      memoryCount: me.memories.length,
      memoryLimit: me.memoryLimit,
      memories: [for (final m in me.memories.take(3)) m.text],
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
      inPsc: telegram?.inPsc ?? false,
      learning: !me.noLearn,
    );
  }

  final String name;
  final String persona;

  /// Đồ robot đeo trên thẻ.
  final AgentLook look;
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

  /// Chưa có tên: thẻ "chưa rèn" ở màn tạo bot.
  bool get draft => name.trim().isEmpty;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
}

/// Palette tối của hành đang chọn: thẻ luôn là vật thể tối, cả khi app sáng.
RunNowPalette _cardPalette(BuildContext context) => RunNowPalette.forSelection(
  context.runNowPalette.element,
  appearance: RunNowAppearance.dark,
);

/// Mặt trước thẻ bot, vẽ ở [gameCardSize]. Tranh chiếm nửa trên: trời theo
/// bậc, robot đứng trên đường chạy, đồ đeo theo kiểu bot. Thẻ chưa có tên là
/// thẻ "chưa rèn": robot chỉ là một bóng tối có dấu hỏi.
class AgentBotCardFront extends StatelessWidget {
  const AgentBotCardFront({
    super.key,
    required this.data,
    this.holo = const Offset(0.4, 0.3),
  });

  final AgentBotCardData data;
  final Offset holo;

  /// Mép dưới của tranh, tính trong lòng khung.
  static const _artHeight = 222.0;

  @override
  Widget build(BuildContext context) {
    final p = _cardPalette(context);
    final t = gameCardTiers[data.tier.material]!;
    final ink = p.ink;
    final muted = ink.withValues(alpha: 0.6);
    final draft = data.draft;
    final createdAt = data.createdAt;
    final runKm = data.runKm;
    final status = data.status;
    final frame = draft
        ? const [RunNowBotTokens.ghost, RunNowBotTokens.ghostVisor]
        : t.frame;
    final frameStops = draft ? null : t.frameStops;
    final quote = data.budgetResting
        ? 'MyBot chạm trần chi phí hôm nay.'
        : draft && data.persona.trim().isEmpty
        ? 'Chọn kiểu bot, thẻ hiện lời bot nói ở đây.'
        : _quote(data.persona);
    return GameCardFrame(
      colors: frame,
      stops: frameStops,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Field(palette: p),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _artHeight,
            child: _Scene(data: data, palette: p, gem: t.gem),
          ),
          Positioned(
            left: 9,
            right: 9,
            top: 8,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (runKm != null && !draft)
                        Flexible(
                          child: _ScenePill(
                            text: status == null
                                ? '${formatAgentRunKm(runKm)} km hôm nay'
                                : '${formatAgentRunKm(runKm)} km',
                          ),
                        ),
                      if (status != null) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: _ScenePill(
                            text: status.text,
                            icon: status.icon,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                _TierChip(
                  label: draft ? 'Chưa rèn' : data.tier.label,
                  gems: draft ? 0 : t.gems,
                  color: draft ? muted : t.gem,
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: _artHeight - 18,
            child: Center(
              child: _NamePlaque(
                text: draft
                    ? 'Tên bot'
                    : data.budgetResting
                    ? '${data.name} đang nghỉ'
                    : data.name,
                color: draft ? muted : ink,
                glow: draft ? Colors.transparent : t.gem,
                frame: frame,
                stops: frameStops,
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: _artHeight + 22,
            child: Column(
              children: [
                if (!draft)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(6, 8),
                        painter: GameCardGemPainter(t.gem),
                      ),
                      const SizedBox(width: 5),
                      Flexible(child: _CardCaps(data.look.title, color: t.gem)),
                      const SizedBox(width: 5),
                      CustomPaint(
                        size: const Size(6, 8),
                        painter: GameCardGemPainter(t.gem),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  quote,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                    color: draft ? muted : ink.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 25,
            child: Row(
              children: [
                if (data.dm case final dm?) ...[
                  Expanded(
                    child: _CardStat(
                      label: 'Tin',
                      used: dm.used,
                      max: dm.max,
                      color: t.gem,
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
                if (data.images case final images?) ...[
                  Expanded(
                    child: _CardStat(
                      label: 'Ảnh',
                      used: images.used,
                      max: images.max,
                      color: t.gem,
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: _CardStat(
                    label: 'Nhớ',
                    used: data.memoryCount,
                    max: data.memoryLimit,
                    color: t.gem,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 9,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    draft
                        ? 'Bot mới'
                        : createdAt == null
                        ? '3I RUN · MYBOT'
                        : _dayLine(createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: ink.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                // Expanded cạnh Expanded chia đôi hàng; chữ căn phải để
                // username nằm sát mép phải thay vì giữa thẻ.
                if (data.username case final username?)
                  Expanded(
                    child: Text(
                      '@$username',
                      textAlign: TextAlign.right,
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
          ),
          if (!draft && t.holo > 0) GameCardHolo(strength: t.holo, at: holo),
          if (!draft && t.sparkle)
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

  /// Mặt trước chỉ trích câu đầu của tính cách như lời thoại; đủ cả đoạn ở
  /// mặt sau.
  static String _quote(String persona) {
    final text = persona.trim();
    if (text.isEmpty) return '';
    return '“${text.substring(0, agentQuoteEnd(text))}”';
  }
}

/// Độ dài câu đầu của [persona] (hết câu ở . ! ? …), cả đoạn khi không có dấu
/// hết câu. Thẻ lấy câu này làm lời thoại; màn sửa bot tô sáng đúng câu đó.
int agentQuoteEnd(String persona) =>
    RegExp(r'[.!?…](?=\s|$)').firstMatch(persona)?.end ?? persona.length;

/// Bậc thẻ trên tranh: tên bậc và số đá.
class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.gems,
    required this.color,
  });

  final String label;
  final int gems;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 6, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardCaps(label, color: color),
          for (var i = 0; i < gems; i++)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: CustomPaint(
                size: const Size(7, 9),
                painter: GameCardGemPainter(color),
              ),
            ),
        ],
      ),
    );
  }
}

/// Biển tên đè lên mép dưới tranh, viền cùng chất liệu với khung thẻ.
class _NamePlaque extends StatelessWidget {
  const _NamePlaque({
    required this.text,
    required this.color,
    required this.glow,
    required this.frame,
    required this.stops,
  });

  final String text;
  final Color color;
  final Color glow;
  final List<Color> frame;
  final List<double>? stops;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 206),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: frame,
          stops: stops,
        ),
        boxShadow: const [
          BoxShadow(color: RunNowBotTokens.shadow, blurRadius: 10),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 3, 14, 4),
        decoration: BoxDecoration(
          color: RunNowBotCardTokens.plaque,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: color,
            shadows: [
              Shadow(color: glow.withValues(alpha: 0.45), blurRadius: 16),
            ],
          ),
        ),
      ),
    );
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
                const SizedBox(height: 5),
                if (data.memories.isEmpty)
                  Text('Chưa nhớ gì.', style: body.copyWith(color: muted))
                else
                  for (final memory in data.memories.take(3))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        memory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body.copyWith(fontSize: 10, height: 1.3),
                      ),
                    ),
                if (places.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final place in places)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            place,
                            style: TextStyle(
                              fontSize: 8.6,
                              fontWeight: FontWeight.w800,
                              color: Color.lerp(p.accent, Colors.white, 0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                Text(
                  createdAt == null
                      ? 'Chạm để lật lại'
                      : 'Tạo ngày ${_date(createdAt)} · chạm để lật lại',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 8.6, color: muted),
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
  const _CardStat({
    required this.label,
    required this.used,
    required this.max,
    required this.color,
  });

  final String label;
  final int used;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const ink = RunNowGameTokens.nightInk;
    final muted = ink.withValues(alpha: 0.62);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: _CardCaps(label, color: muted)),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$used'),
                  TextSpan(
                    text: '/$max',
                    style: TextStyle(fontSize: 8.5, color: muted),
                  ),
                ],
              ),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.white.withValues(alpha: 0.1)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: max <= 0 ? 0 : (used / max).clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tranh nửa trên thẻ: trời theo bậc (đêm theo màu hành, Bạc bình minh,
/// Vàng hoàng hôn, Foil cực quang), đường chạy, robot đứng giữa. Bot nghỉ
/// hay thẻ chưa rèn thì luôn là đêm.
class _Scene extends StatelessWidget {
  const _Scene({required this.data, required this.palette, required this.gem});

  final AgentBotCardData data;
  final RunNowPalette palette;
  final Color gem;

  @override
  Widget build(BuildContext context) {
    final draft = data.draft;
    final tier = draft || data.budgetResting ? AgentCardTier.common : data.tier;
    final deep = palette.accentDeep;
    final sky = switch (tier) {
      _ when draft => [
        Color.lerp(palette.background, Colors.black, 0.35)!,
        Color.lerp(palette.background, Colors.white, 0.04)!,
      ],
      AgentCardTier.common => [
        Color.lerp(deep, Colors.black, 0.82)!,
        Color.lerp(deep, Colors.black, 0.62)!,
        Color.lerp(deep, Colors.black, 0.55)!,
      ],
      AgentCardTier.silver => const [
        RunNowBotCardTokens.dawnTop,
        RunNowBotCardTokens.dawnMid,
        RunNowBotCardTokens.dawnBottom,
      ],
      AgentCardTier.gold => const [
        RunNowBotCardTokens.duskTop,
        RunNowBotCardTokens.duskMid,
        RunNowBotCardTokens.duskBottom,
      ],
      AgentCardTier.foil => const [
        RunNowBotCardTokens.auroraTop,
        RunNowBotCardTokens.auroraMid,
        RunNowBotCardTokens.auroraBottom,
      ],
    };
    final under = Color.lerp(palette.background, Colors.black, 0.2)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: sky,
            ),
          ),
        ),
        if (!draft) ...[
          if (tier == AgentCardTier.foil)
            const CustomPaint(painter: _AuroraPainter()),
          if (tier != AgentCardTier.gold)
            const CustomPaint(painter: _StarsPainter()),
          if (tier == AgentCardTier.common)
            const Positioned(
              right: 24,
              top: 36,
              child: GameMoon(size: 20, glow: 16),
            ),
          if (tier == AgentCardTier.silver)
            const Positioned(
              right: 26,
              top: 34,
              child: GameMoon(size: 32, glow: 28),
            ),
          if (tier == AgentCardTier.gold)
            const Positioned(
              left: 0,
              right: 0,
              top: 70,
              child: Center(child: _SunsetSun(size: 150)),
            ),
        ],
        CustomPaint(
          painter: _TrackPainter(
            draft
                ? Colors.white.withValues(alpha: 0.08)
                : gem.withValues(alpha: 0.5),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: CustomPaint(
              size: _MascotPainter.sizeFor(112),
              painter: _MascotPainter(
                mood: data._mood,
                look: data.look,
                accent: palette.accent,
                gem: gem,
                initial: data.initial,
                ghost: draft,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [under.withValues(alpha: 0), under],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sao bốn cánh rải cố định trên trời đêm, bình minh và cực quang.
class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  /// (x, y, cỡ, độ đậm), x và y theo tỉ lệ khung tranh.
  static const _stars = [
    (0.09, 0.17, 6.0, 0.8),
    (0.22, 0.09, 4.0, 0.55),
    (0.79, 0.12, 7.0, 0.85),
    (0.88, 0.31, 4.0, 0.5),
    (0.15, 0.40, 4.0, 0.45),
    (0.66, 0.24, 3.0, 0.55),
    (0.50, 0.06, 4.0, 0.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (fx, fy, s, alpha) in _stars) {
      final c = Offset(size.width * fx, size.height * fy);
      final r = s / 2;
      final w = r * 0.22;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + w, c.dy - w)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx + w, c.dy + w)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - w, c.dy + w)
          ..lineTo(c.dx - r, c.dy)
          ..lineTo(c.dx - w, c.dy - w)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

/// Hai dải cực quang mờ vắt ngang trời của bậc Foil.
class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void band(double top, double height, double turn, List<Color> colors) {
      final rect = Rect.fromLTWH(-30, top, size.width + 60, height);
      canvas.save();
      canvas.translate(size.width / 2, top + height / 2);
      canvas.rotate(turn);
      canvas.translate(-size.width / 2, -(top + height / 2));
      canvas.drawOval(
        rect,
        Paint()
          ..shader = LinearGradient(colors: colors).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.restore();
    }

    band(14, 64, -0.14, [
      RunNowBotCardTokens.auroraGreen.withValues(alpha: 0),
      RunNowBotCardTokens.auroraGreen.withValues(alpha: 0.55),
      RunNowBotCardTokens.auroraPink.withValues(alpha: 0.5),
      RunNowBotCardTokens.auroraPink.withValues(alpha: 0),
    ]);
    band(58, 44, 0.1, [
      RunNowBotCardTokens.auroraViolet.withValues(alpha: 0),
      RunNowBotCardTokens.auroraViolet.withValues(alpha: 0.55),
      RunNowBotCardTokens.auroraBlue.withValues(alpha: 0.45),
      RunNowBotCardTokens.auroraBlue.withValues(alpha: 0),
    ]);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}

/// Đường chạy nhìn xa dần về chân trời, nằm ở đáy tranh dưới chân robot.
class _TrackPainter extends CustomPainter {
  const _TrackPainter(this.lane);

  final Color lane;

  static const _depth = 62.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bottom = size.height;
    final top = bottom - _depth;
    final cx = w / 2;
    canvas.drawPath(
      Path()
        ..moveTo(-w / 3, bottom)
        ..lineTo(w * 4 / 3, bottom)
        ..lineTo(cx + w * 0.06, top)
        ..lineTo(cx - w * 0.06, top)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    final line = Paint()
      ..color = lane
      ..strokeWidth = 1.4;
    for (final f in const [-0.25, 0.0, 0.25, 0.75, 1.0, 1.25]) {
      final x = w * f;
      canvas.drawLine(
        Offset(x, bottom),
        Offset(cx + (x - cx) * 0.12, top),
        line,
      );
    }
    canvas.drawLine(
      Offset(0, top),
      Offset(w, top),
      Paint()..color = Colors.white.withValues(alpha: 0.1),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.lane != lane;
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

/// Mặt trời hoàng hôn của bậc Vàng trở lên: quầng tròn mờ dần ra mép, không
/// có viền như mặt trời nhỏ.
class _SunsetSun extends StatelessWidget {
  const _SunsetSun({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            RunNowBotCardTokens.sunCore,
            RunNowBotCardTokens.sunHalo,
            RunNowBotCardTokens.sunHalo.withValues(alpha: 0),
          ],
          stops: const [0, 0.78, 1],
        ),
      ),
    );
  }
}

/// Robot của bot, vẽ theo khung 128×184 (chừa 24 phía trên cho nón) rồi thu
/// theo size. Mắt theo tâm trạng: ngủ khi cả hệ thống nghỉ, lim dim khi chủ
/// chưa chạy, mở khi đã qua mốc đầu, cười khi lên Vàng trở lên. Không có
/// trạng thái buồn. Đồ đeo theo kiểu bot; [ghost] là thẻ chưa có tên.
class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.mood,
    required this.look,
    required this.accent,
    required this.gem,
    required this.initial,
    this.ghost = false,
  });

  final _Mood mood;
  final AgentLook look;
  final Color accent;
  final Color gem;
  final String initial;
  final bool ghost;

  static const _frame = Size(128, 184);

  static Size sizeFor(double width) =>
      Size(width, width * _frame.height / _frame.width);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _frame.width, size.height / _frame.height);
    canvas.translate(0, 24);
    final shell = ghost ? RunNowBotTokens.ghost : RunNowBotTokens.shell;
    final eye = Color.lerp(accent, Colors.white, 0.5)!;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(64, 152), width: 80, height: 12),
      Paint()
        ..color = RunNowBotTokens.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final leg = Paint()
      ..color = ghost ? RunNowBotTokens.ghost : RunNowBotTokens.leg;
    for (final x in [44.0, 68.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(x, 128, x + 16, 148, const Radius.circular(5)),
        leg,
      );
    }
    final arm = Paint()
      ..color = shell
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(42, 108), const Offset(26, 126), arm);
    canvas.drawLine(const Offset(86, 108), const Offset(102, 126), arm);
    const body = Rect.fromLTWH(38, 100, 52, 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(14)),
      Paint()..color = ghost ? RunNowBotTokens.ghost : accent,
    );
    if (!ghost) _letter(canvas, body.center);
    final dressed = !ghost;
    if (dressed && look == AgentLook.coach) _whistle(canvas);
    if (ghost || (look != AgentLook.funny && look != AgentLook.coach)) {
      canvas.drawLine(
        const Offset(64, 10),
        const Offset(64, 26),
        Paint()
          ..color = ghost ? RunNowBotTokens.ghostInk : accent
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        const Offset(64, 8),
        6,
        Paint()..color = ghost ? RunNowBotTokens.ghostInk : gem,
      );
    }
    if (dressed && look == AgentLook.chill) _headphones(canvas, back: true);
    const head = Rect.fromLTWH(18, 24, 92, 74);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(30)),
      ghost
          ? (Paint()..color = RunNowBotTokens.ghost)
          : (Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RunNowBotTokens.shell, RunNowBotTokens.shellShade],
              ).createShader(head)),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(28, 38, 100, 80, const Radius.circular(20)),
      Paint()
        ..color = ghost ? RunNowBotTokens.ghostVisor : RunNowBotTokens.visor,
    );
    if (ghost) {
      _text(canvas, '?', const Offset(64, 59), RunNowBotTokens.ghostInk, 26);
    } else {
      _eyes(canvas, eye);
    }
    if (dressed) {
      switch (look) {
        case AgentLook.funny:
          _partyHat(canvas);
        case AgentLook.chill:
          _headphones(canvas, back: false);
        case AgentLook.coach:
          _cap(canvas);
        case AgentLook.custom:
          _scarf(canvas);
      }
    }
    canvas.restore();
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

  void _partyHat(Canvas canvas) {
    final hat = Path()
      ..moveTo(40, 30)
      ..lineTo(88, 30)
      ..lineTo(64, -14)
      ..close();
    canvas.drawPath(hat, Paint()..color = RunNowBotTokens.partyHat);
    canvas.save();
    canvas.clipPath(hat);
    final stripe = Paint()
      ..color = RunNowBotTokens.partyGold
      ..strokeWidth = 5;
    canvas.drawLine(const Offset(40, 15), const Offset(88, 15), stripe);
    canvas.drawLine(const Offset(40, 1), const Offset(88, 1), stripe);
    canvas.restore();
    canvas.drawCircle(
      const Offset(64, -15),
      6,
      Paint()..color = RunNowBotTokens.partyGold,
    );
  }

  /// Quai vẽ sau đầu, hai tai nghe vẽ đè lên mép đầu.
  void _headphones(Canvas canvas, {required bool back}) {
    if (back) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(64, 62), radius: 50),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = RunNowBotTokens.headband
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      return;
    }
    final cup = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromLTRBR(8, 46, 24, 78, const Radius.circular(7)),
      cup,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(104, 46, 120, 78, const Radius.circular(7)),
      cup,
    );
  }

  void _cap(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(20, 46)
        ..quadraticBezierTo(64, -6, 108, 46)
        ..close(),
      Paint()..color = RunNowBotTokens.cap,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 44), width: 40, height: 10),
      Paint()..color = RunNowBotTokens.capBrim,
    );
    canvas.drawCircle(
      const Offset(64, 21),
      3,
      Paint()..color = RunNowBotTokens.capBrim,
    );
  }

  /// Còi đeo lệch sang trái để không che chữ trên ngực.
  void _whistle(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(52, 100)
        ..lineTo(40, 114),
      Paint()
        ..color = RunNowBotTokens.lanyard
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(30, 112, 46, 122, const Radius.circular(3)),
      Paint()..color = RunNowBotTokens.whistle,
    );
  }

  void _scarf(Canvas canvas) {
    final scarf = Paint()..color = RunNowBotTokens.scarf;
    canvas.drawPath(
      Path()
        ..moveTo(32, 93)
        ..quadraticBezierTo(64, 107, 96, 93)
        ..lineTo(96, 101)
        ..quadraticBezierTo(64, 114, 32, 101)
        ..close(),
      scarf,
    );
    canvas.drawPath(
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
      old.ghost != ghost;
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
/// Lần đầu hiện thì một vệt sáng quét qua thẻ, rồi đứng yên: không có
/// animation chạy mãi.
class AgentBotCardView extends StatefulWidget {
  const AgentBotCardView({
    super.key,
    required this.data,
    required this.width,
    this.captureKey,
  });

  final AgentBotCardData data;
  final double width;

  /// Gắn vào lớp vẽ mặt thẻ, nằm trong phép nghiêng/lật, nên chụp ra là mặt
  /// thẻ phẳng đang hiện.
  final GlobalKey? captureKey;

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
                child: RepaintBoundary(
                  key: widget.captureKey,
                  child: SizedBox(
                    width: widget.width,
                    height: height,
                    child: FittedBox(child: face),
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
