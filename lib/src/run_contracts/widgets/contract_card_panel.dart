import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/contract_card_models.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/keo_scene.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Kèo chạy theo lịch VN, nên ngày in trên thẻ đổi sang giờ VN dù máy ở đâu.
DateTime _vn(DateTime at) => at.toUtc().add(const Duration(hours: 7));

/// "20" khi tròn, "20,5" khi lẻ.
String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1).replaceAll('.', ',');

/// Số chính và đơn vị của kèo theo cách kèo đo.
(String, String) _measure(RunContractMetric metric, double value) =>
    switch (metric) {
      RunContractMetric.distance ||
      RunContractMetric.longestRun => (runCardKm(value), 'KM'),
      RunContractMetric.activityCount => ('${value.toInt()}', 'BUỔI'),
      RunContractMetric.activeDays => ('${value.toInt()}', 'NGÀY'),
      RunContractMetric.routeCompletion => ('${value.toInt()}', 'LẦN'),
    };

String _target(RunContractMetric metric, double value) {
  final unit = _measure(metric, value).$2.toLowerCase();
  return '${_number(value)} $unit';
}

/// "19 – 25.10.2026"; kèo vắt qua tháng thì ngày đầu kèm tháng.
String _period(ContractCardSnapshot snap) {
  final (start, end) = (snap.startAt, snap.endAtExclusive);
  if (start == null || end == null) return '';
  final first = _vn(start);
  final last = _vn(end).subtract(const Duration(days: 1));
  final from = first.month == last.month
      ? _two(first.day)
      : '${_two(first.day)}.${_two(first.month)}';
  return '$from – ${_two(last.day)}.${_two(last.month)}.${last.year}';
}

/// Nền thẻ là hình của loại kèo theo hành đang chọn. Khuôn thẻ in chữ sáng
/// lên tranh, nên hình luôn vẽ bản tối dù app đang ở chế độ sáng.
class ContractSceneArt extends StatelessWidget {
  const ContractSceneArt({super.key, required this.scene, required this.seed});

  final KeoScene scene;

  /// Id kèo, chọn bố cục hình như thẻ kèo ở trang chủ.
  final String seed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: KeoScenePainter(
      scene: scene,
      variant: keoSceneVariant(seed),
      colors: KeoSceneColors.resolve(
        RunNowPalette.forSelection(context.runNowPalette.element),
        scene,
      ),
    ),
    child: const SizedBox.expand(),
  );
}

KeoScene _sceneOf(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => KeoScene.distance,
  RunContractMetric.activeDays => KeoScene.activeDays,
  RunContractMetric.activityCount => KeoScene.activityCount,
  RunContractMetric.longestRun => KeoScene.longestRun,
  RunContractMetric.routeCompletion => KeoScene.route,
};

/// Mặt trước: hình kèo làm nền, số chính là kết quả của chủ thẻ, hàng số liệu
/// là mục tiêu, km tích luỹ và số người đạt. [scene] lấy từ kèo khi có (kèo
/// hẹn gặp có hình riêng), không thì theo cách kèo đo.
AchievementCardData contractCardData(ContractCard card, {KeoScene? scene}) {
  final snap = card.snapshot;
  final (hero, unit) = _measure(snap.metric, snap.progressValue);
  final end = snap.endAtExclusive;
  final last = end == null
      ? null
      : _vn(end).subtract(const Duration(days: 1));
  return AchievementCardData(
    tier: card.tier,
    secret: card.secret,
    art: ContractSceneArt(
      scene: scene ?? _sceneOf(snap.metric),
      seed: card.contractId,
    ),
    kind: 'KÈO HOÀN THÀNH',
    hero: hero,
    heroUnit: unit,
    title: snap.title.isEmpty ? 'Kèo chạy' : snap.title,
    stats: [
      (value: _target(snap.metric, snap.targetValue), label: 'MỤC TIÊU'),
      (value: runCardKm(card.km), label: 'KM TÍCH LUỸ'),
      (value: '${snap.achievers}/${snap.participants}', label: 'NGƯỜI ĐẠT'),
    ],
    owner: (snap.displayName.isEmpty ? '3i member' : snap.displayName)
        .toUpperCase(),
    serial: '',
    desc: '',
    meta: _period(snap),
    date: last == null
        ? ''
        : '${_two(last.day)}.${_two(last.month)}.${last.year}',
  );
}

CardShareSubject contractCardShareSubject(
  ContractCard card,
  AchievementCardData data,
) => CardShareSubject(
  id: 'contract-${card.contractId}',
  printed: [
    card.tier.name,
    card.secret?.name,
    data.title,
    data.hero,
    data.heroUnit,
    for (final stat in data.stats ?? const <AchievementStat>[]) stat.value,
    data.owner,
    data.meta,
  ].join('|'),
  text:
      'Đạt kèo ${data.title} · ${data.hero} ${data.heroUnit.toLowerCase()}'
      '\nChia sẻ từ 3i',
);

/// Xem thẻ 3D, lật hai mặt, khoe từ đó.
Future<void> showContractCardViewer(
  BuildContext context,
  ContractCard card,
  AchievementCardData data,
) => showCardViewer(
  context,
  front: (pose) => AchievementCard(data: data, pose: pose),
  back: (pose) => AchievementCard(data: data, pose: pose, back: true),
  chips: [gameCardTiers[card.tier]!.label, 'Kèo · ${runCardKm(card.km)} km'],
  cardSize: achievementCardSize,
  // Mở màn khoe từ trong màn xem để nó nằm trên màn xem.
  onShare: (_, origin) => showCardShare(
    origin,
    subject: contractCardShareSubject(card, data),
    data: data,
  ),
);

/// Chữ to trên lá khoá khi không lật được.
String contractCardLockLabel(String reason) => switch (reason) {
  'card_contract_open' => 'CHƯA CHỐT',
  'card_contract_cancelled' => 'KÈO ĐÃ HUỶ',
  _ => 'CHƯA ĐẠT',
};

/// Câu cho người dùng ứng với mã lý do backend trả khi không lật được.
String contractCardLockText(String reason) => switch (reason) {
  'card_contract_open' => 'Kèo chốt xong mới lật được thẻ.',
  'card_contract_cancelled' => 'Kèo đã huỷ nên không có thẻ.',
  _ => 'Chỉ người đạt mục tiêu của chính mình mới lật được thẻ kèo.',
};

/// Màn kèo có mục thẻ không. Kèo đang chạy thì đạt mục tiêu là app đã báo
/// hoàn thành, nên hiện luôn để xem trước tỉ lệ dù chốt xong mới lật được.
/// Kèo đã chốt thì hiện cho cả người hụt để biết vì sao không có thẻ.
bool contractCardShown(RunContract contract, String? uid) =>
    switch (contract.status) {
      RunContractStatus.active => contract.completedBy(uid),
      RunContractStatus.completed || RunContractStatus.failed => true,
      RunContractStatus.cancelled => false,
    };

/// Thẻ kèo của chính mình, chỉ hỏi server khi màn kèo mở.
final contractCardViewProvider = FutureProvider.autoDispose
    .family<ContractCardView, String>(
      (ref, contractId) =>
          ref.watch(runNowApiClientProvider).getContractCard(contractId),
    );

/// Thẻ của kèo đã chốt: đạt mục tiêu thì úp thẻ kèm tỉ lệ theo km tích luỹ và
/// nút lật; lật rồi thì hiện thẻ để khoe; không đạt thì lá khoá.
class ContractCardPanel extends ConsumerStatefulWidget {
  const ContractCardPanel({super.key, required this.contract});

  final RunContract contract;

  @override
  ConsumerState<ContractCardPanel> createState() => _ContractCardPanelState();
}

class _ContractCardPanelState extends ConsumerState<ContractCardPanel> {
  bool _rolling = false;

  /// Thẻ POST vừa trả; thẻ kèo không đổi sau khi lật nên không cần nghe doc.
  ContractCard? _rolled;

  String get _id => widget.contract.id;

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(contractCardViewProvider(_id));
    if (_rolled case final card?) return _shown(context, card, flip: true);
    return view.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Column(
        children: [
          _Hint('Không tải được thẻ kèo: $error'),
          TextButton(
            onPressed: () => ref.invalidate(contractCardViewProvider(_id)),
            child: const Text('Thử lại'),
          ),
        ],
      ),
      data: (view) {
        if (view.card case final card?) {
          return _shown(context, card, flip: false);
        }
        // Kèo chưa chốt mà đã đạt: backend gửi kèm tỉ lệ theo km hiện có.
        if (view.reason != null && view.odds.isNotEmpty) {
          final at = _vn(widget.contract.finalizeAt);
          return Column(
            children: [
              RunCardFrame(child: _faceDown(view.km)),
              const SizedBox(height: 16),
              RunCardOddsTable(
                title: 'TỈ LỆ CHO ${runCardKm(view.km)} KM TÍCH LUỸ',
                odds: view.odds,
              ),
              const SizedBox(height: 8),
              _Hint(
                'Kèo chốt lúc ${_two(at.hour)}:${_two(at.minute)} '
                '${_two(at.day)}/${_two(at.month)} rồi mới lật được thẻ. '
                'Tích thêm km trước giờ đó thì tỉ lệ còn tăng.',
              ),
            ],
          );
        }
        if (view.reason case final reason?) {
          return Column(
            children: [
              RunCardFrame(
                child: RunCardFaceDown(
                  km: null,
                  kind: 'KÈO',
                  title: widget.contract.title,
                  failure: contractCardLockLabel(reason),
                ),
              ),
              _Hint(contractCardLockText(reason)),
            ],
          );
        }
        return Column(
          children: [
            RunCardFrame(child: _faceDown(view.km)),
            const SizedBox(height: 16),
            RunCardOddsTable(
              title: 'TỈ LỆ CHO ${runCardKm(view.km)} KM TÍCH LUỸ',
              odds: view.odds,
            ),
            const SizedBox(height: 8),
            const _Hint(
              'Càng tích nhiều km trong kèo, bậc cao càng dễ ra. Mỗi kèo chỉ '
              'lật một lần.',
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

  Widget _faceDown(double km) =>
      RunCardFaceDown(km: km, kind: 'KÈO', title: widget.contract.title);

  Future<void> _roll() async {
    setState(() => _rolling = true);
    try {
      final card = await ref
          .read(runNowApiClientProvider)
          .rollContractCard(_id);
      if (mounted) setState(() => _rolled = card);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không lật được thẻ: $error')));
      ref.invalidate(contractCardViewProvider(_id));
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  /// [flip] khi vừa lật trong phiên này thì chạy hiệu ứng lật mặt.
  Widget _shown(BuildContext context, ContractCard card, {required bool flip}) {
    final data = contractCardData(
      card,
      scene: KeoScene.forContract(widget.contract),
    );
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final shown = Semantics(
      button: true,
      label: 'Xem thẻ 3D',
      child: GestureDetector(
        onTap: () => showContractCardViewer(context, card, data),
        child: RunCardFrame(child: AchievementCard(data: data)),
      ),
    );
    return Column(
      children: [
        if (flip)
          CardFlipReveal(
            from: RunCardFrame(child: _faceDown(card.km)),
            to: shown,
          )
        else
          shown,
        const SizedBox(height: 10),
        Text(
          '${gameCardTiers[card.tier]!.label} · ${runCardKm(card.km)} km tích '
          'luỹ · chạm thẻ để xem 3D',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => showCardShare(
            context,
            subject: contractCardShareSubject(card, data),
            data: data,
          ),
          icon: const Icon(Icons.ios_share),
          label: const Text('Khoe thẻ'),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

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
