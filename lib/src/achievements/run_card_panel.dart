import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowAchievementTokens;
const _condensed = 'Barlow Condensed';

/// Thẻ của một buổi chạy của chính mình: chưa lật thì úp thẻ kèm tỉ lệ và nút
/// lật; lật rồi thì hiện thẻ, chọn mặt để khoe.
class RunCardPanel extends ConsumerStatefulWidget {
  const RunCardPanel({super.key, required this.activity, required this.owner});

  final ActivitySummary activity;

  /// Tên in trên thẻ.
  final String owner;

  @override
  ConsumerState<RunCardPanel> createState() => _RunCardPanelState();
}

class _RunCardPanelState extends ConsumerState<RunCardPanel> {
  final _captureKey = GlobalKey();
  bool _rolling = false;
  bool _sharing = false;
  bool _back = false;

  /// Thẻ vừa lật trong phiên này thì chạy hiệu ứng lật mặt; mở lại thẻ cũ thì
  /// hiện thẳng.
  bool _justRolled = false;

  String get _id => widget.activity.id;

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(runCardProvider(_id));
    return card.when(
      data: (card) =>
          card == null ? _unrolled(context) : _rolled(context, card),
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _Message('Không tải được thẻ: $error'),
    );
  }

  Widget _unrolled(BuildContext context) {
    final view = ref.watch(runCardViewProvider(_id));
    final km = (widget.activity.distanceMeters / 100).round() / 10;
    final faceDown = _CardFrame(
      child: _FaceDown(km: km, title: widget.activity.name),
    );
    return view.when(
      loading: () => Column(
        children: [
          faceDown,
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
        ],
      ),
      error: (error, _) => Column(
        children: [
          faceDown,
          _Message('Không tải được tỉ lệ: $error'),
          TextButton(
            onPressed: () => ref.invalidate(runCardViewProvider(_id)),
            child: const Text('Thử lại'),
          ),
        ],
      ),
      data: (view) {
        // Thẻ vừa có ở chỗ khác (máy khác lật) thì stream sẽ tự đổi.
        if (view.card != null) return faceDown;
        if (view.reason case final reason?) {
          return Column(
            children: [faceDown, _Message(runCardReasonText(reason))],
          );
        }
        return Column(
          children: [
            faceDown,
            const SizedBox(height: 16),
            _OddsTable(km: km, odds: view.odds),
            const SizedBox(height: 8),
            const _Message(
              'Mỗi buổi chạy chỉ lật một lần, không lật lại được.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _rolling ? null : _roll,
              icon: _rolling
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flip_rounded),
              label: Text(_rolling ? 'Đang lật...' : 'Lật thẻ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _roll() async {
    setState(() => _rolling = true);
    try {
      await ref.read(runNowApiClientProvider).rollRunCard(_id);
      // Thẻ hiện khi stream doc báo về, thường ngay sau đó.
      if (mounted) setState(() => _justRolled = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không lật được thẻ: $error')));
      ref.invalidate(runCardViewProvider(_id));
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  Widget _rolled(BuildContext context, RunCard card) {
    final data = runCardData(card, owner: widget.owner);
    final km = card.km;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final shown = Semantics(
      button: true,
      label: 'Xem thẻ 3D',
      child: GestureDetector(
        onTap: () => _openViewer(card, data),
        child: RepaintBoundary(
          key: _captureKey,
          child: _CardFrame(
            child: AchievementCard(data: data, back: _back),
          ),
        ),
      ),
    );
    return Column(
      children: [
        if (_justRolled)
          _FlipReveal(
            from: _CardFrame(
              child: _FaceDown(km: km, title: card.snapshot.name),
            ),
            to: shown,
          )
        else
          shown,
        const SizedBox(height: 10),
        Text(
          '${gameCardTiers[card.tier]!.label} · ${runCardKm(km)} km · '
          'chạm thẻ để xem 3D',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          'Đã lưu vào Bộ thẻ trong Hồ sơ.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Mặt trước')),
            ButtonSegment(value: true, label: Text('Mặt sau')),
          ],
          selected: {_back},
          onSelectionChanged: _sharing
              ? null
              : (value) => setState(() => _back = value.single),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (origin) => FilledButton.icon(
            onPressed: _sharing ? null : () => _share(origin, card),
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            label: Text(_sharing ? 'Đang tạo thẻ...' : 'Khoe thẻ'),
          ),
        ),
      ],
    );
  }

  void _openViewer(RunCard card, AchievementCardData data) {
    showCardViewer(
      context,
      front: (pose) => AchievementCard(data: data, pose: pose),
      back: (pose) => AchievementCard(data: data, pose: pose, back: true),
      chips: [gameCardTiers[card.tier]!.label, '${runCardKm(card.km)} km'],
      cardSize: achievementCardSize,
      onShare: (cardKey, origin) => shareRunCard(
        cardKey: cardKey,
        shareOriginContext: origin,
        card: card,
      ),
    );
  }

  Future<void> _share(BuildContext origin, RunCard card) async {
    setState(() => _sharing = true);
    try {
      await shareRunCard(
        cardKey: _captureKey,
        shareOriginContext: origin,
        card: card,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể chia sẻ thẻ: $error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// Câu cho người dùng ứng với mã lý do backend trả khi không lật được.
String runCardReasonText(String reason) => switch (reason) {
  'card_duplicate' =>
    'Buổi này trùng một buổi khác đã có thẻ (cùng lần chạy ghi ở hai nguồn), '
        'nên không lật thêm được.',
  _ => 'Chỉ buổi chạy bộ từ 500 m mới lật được thẻ.',
};

/// Thẻ vẽ ở kích thước gốc rồi thu theo bề ngang chỗ đặt, tối đa 300.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GameCardScaled(
        width: math.min(achievementCardSize.width, constraints.maxWidth),
        size: achievementCardSize,
        child: child,
      ),
    );
  }
}

/// Thẻ úp: chưa biết bậc nên khung than chì trơn, dấu hỏi ở giữa.
class _FaceDown extends StatelessWidget {
  const _FaceDown({required this.km, required this.title});

  final double km;
  final String title;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.8,
      color: _T.accentCommon,
    );
    return SizedBox.fromSize(
      size: achievementCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_T.graphite1, _T.graphite2, _T.graphite3, _T.graphite4],
            stops: [0, 0.38, 0.66, 1],
          ),
          boxShadow: const [
            BoxShadow(color: _T.drop, blurRadius: 44, offset: Offset(0, 22)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 0.9,
                  colors: [_T.backTop, _T.backBottom],
                  stops: [0, 0.72],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BUỔI CHẠY', style: label),
                    const Spacer(),
                    const Center(
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontFamily: _condensed,
                          fontWeight: FontWeight.w800,
                          fontSize: 120,
                          height: 1,
                          color: _T.accentCommon,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('LẬT ĐỂ XEM ĐỘ HIẾM', style: label),
                    ),
                    const Spacer(),
                    Text(
                      '${runCardKm(km)} KM',
                      style: const TextStyle(
                        fontFamily: _condensed,
                        fontWeight: FontWeight.w800,
                        fontSize: 30,
                        height: 1,
                        color: _T.hero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _T.hero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bảng tỉ lệ ra từng bậc cho buổi [km], bỏ các bậc 0%.
class _OddsTable extends StatelessWidget {
  const _OddsTable({required this.km, required this.odds});

  final double km;
  final List<RunCardOdd> odds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'TỈ LỆ CHO BUỔI ${runCardKm(km)} KM',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        for (final odd in odds)
          if (odd.percent > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: runCardGlow(odd.tier),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(gameCardTiers[odd.tier]!.label)),
                  Text(
                    '${odd.percent.toStringAsFixed(1).replaceAll('.', ',')}%',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Lật từ [from] sang [to] quanh trục dọc trong 0,7 giây.
class _FlipReveal extends StatelessWidget {
  const _FlipReveal({required this.from, required this.to});

  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // Nửa đầu mặt úp quay đi, nửa sau mặt thẻ quay về.
        final angle = math.pi * (1 - t);
        final faceDown = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(faceDown ? math.pi - angle : angle),
          child: faceDown ? from : to,
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
