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
import 'package:myrun/src/run_contracts/widgets/contract_card_art.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_face.dart';

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

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String _day(DateTime day) => '${_two(day.day)}.${_two(day.month)}';
String _fullDay(DateTime day) => '${_day(day)}.${day.year}';
String _weekday(DateTime day) => _weekdays[day.weekday - 1];

typedef _Span = ({DateTime first, DateTime last, int days});

/// Ngày đầu, ngày cuối (giờ VN) và số ngày của kèo; null khi thẻ cũ thiếu mốc.
_Span? _span(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  final first = _vn(start);
  final last = _vn(end).subtract(const Duration(days: 1));
  final days =
      DateTime.utc(
        last.year,
        last.month,
        last.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays +
      1;
  return (first: first, last: last, days: days);
}

enum _Length { day, week, month, other }

_Length _lengthOf(_Span span) {
  final (first, last) = (span.first, span.last);
  if (span.days == 1) return _Length.day;
  if (span.days == 7 && first.weekday == DateTime.monday) return _Length.week;
  final nextMonth = DateTime.utc(last.year, last.month, last.day + 1);
  if (first.day == 1 && first.month == last.month && nextMonth.day == 1) {
    return _Length.month;
  }
  return _Length.other;
}

/// "19.10 → 25.10.2026"; kèo vắt qua năm thì ngày đầu kèm năm.
String _range(DateTime first, DateTime last) {
  final from = first.year == last.year ? _day(first) : _fullDay(first);
  return '$from → ${_fullDay(last)}';
}

String _meetLine(DateTime at, {String prefix = ''}) =>
    '${_weekday(at)} ${_fullDay(at)} · $prefix${_two(at.hour)}:${_two(at.minute)}';

/// Dòng ngày dưới huy hiệu mặt sau và thẻ úp: "19.10 → 25.10.2026 · 7 NGÀY",
/// kèo một ngày "CN 01.11.2026", kèo hẹn gặp kèm giờ hẹn.
String contractCardDateLine(
  DateTime? startAt,
  DateTime? endAtExclusive, {
  DateTime? meetAt,
}) {
  if (meetAt != null) return _meetLine(_vn(meetAt));
  final span = _span(startAt, endAtExclusive);
  if (span == null) return '';
  if (span.days == 1) return '${_weekday(span.first)} ${_fullDay(span.first)}';
  return '${_range(span.first, span.last)} · ${span.days} NGÀY';
}

/// Cảnh của thẻ: kèo hẹn gặp và kèo theo tuyến có cảnh riêng, kèo một ngày là
/// tờ lịch, còn lại theo cách kèo đo.
ContractCardScene _sceneOf(ContractCardSnapshot snap, {DateTime? meetAt}) {
  if (meetAt != null) return ContractCardScene.meet;
  if (snap.metric == RunContractMetric.routeCompletion) {
    return ContractCardScene.route;
  }
  if (_span(snap.startAt, snap.endAtExclusive)?.days == 1) {
    return ContractCardScene.today;
  }
  return switch (snap.metric) {
    RunContractMetric.distance => ContractCardScene.distance,
    RunContractMetric.activityCount => ContractCardScene.count,
    RunContractMetric.activeDays => ContractCardScene.days,
    RunContractMetric.longestRun => ContractCardScene.longRun,
    RunContractMetric.routeCompletion => ContractCardScene.route,
  };
}

String _metricLabel(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => 'QUÃNG ĐƯỜNG',
  RunContractMetric.activityCount => 'SỐ BUỔI',
  RunContractMetric.activeDays => 'NGÀY CHẠY',
  RunContractMetric.longestRun => 'BUỔI DÀI NHẤT',
  RunContractMetric.routeCompletion => 'THEO TUYẾN',
};

/// Mặt trước: tranh theo loại kèo, số chính là kết quả của chủ thẻ, dòng lịch
/// là thời gian diễn ra, con dấu là phần trăm mục tiêu. [meetAt] lấy từ kèo
/// khi là kèo hẹn gặp, vì ảnh chụp kèo trong thẻ không giữ giờ hẹn.
AchievementCardData contractCardData(ContractCard card, {DateTime? meetAt}) {
  final snap = card.snapshot;
  final metric = snap.metric;
  final (hero, unit) = _measure(metric, snap.progressValue);
  final span = _span(snap.startAt, snap.endAtExclusive);
  final length = span == null ? _Length.other : _lengthOf(span);
  final meet = meetAt == null ? null : _vn(meetAt);
  final title = snap.title.isEmpty ? 'Kèo chạy' : snap.title;

  final kind = switch ((meet, metric, length)) {
    (_?, _, _) => 'KÈO HẸN CHẠY',
    (_, RunContractMetric.routeCompletion, _) => 'KÈO THEO TUYẾN',
    (_, _, _Length.day) => 'KÈO TRONG NGÀY',
    (_, _, _Length.week) => 'KÈO TUẦN · ${_metricLabel(metric)}',
    (_, _, _Length.month) => 'KÈO THÁNG · ${_metricLabel(metric)}',
    _ => 'KÈO · ${_metricLabel(metric)}',
  };
  final when = switch ((meet, span)) {
    (final at?, _) => _meetLine(at, prefix: 'HẸN '),
    (_, null) => '',
    (_, final span?) when span.days == 1 =>
      '${_weekday(span.first)} ${_fullDay(span.first)}',
    (_, final span?) when length == _Length.week =>
      '${_weekday(span.first)} ${_day(span.first)} → '
          '${_weekday(span.last)} ${_fullDay(span.last)}',
    (_, final span?) => _range(span.first, span.last),
  };

  final over = snap.progressValue - snap.targetValue;
  final achievers = (
    value: '${snap.achievers}/${snap.participants}',
    label: 'NGƯỜI ĐẠT',
  );
  final stats = [
    (value: _target(metric, snap.targetValue), label: 'MỤC TIÊU'),
    if (meet != null)
      (value: '${snap.participants} người', label: 'ĐĂNG KÝ')
    else if (metric == RunContractMetric.distance && over > 0)
      (value: '+${runCardKm(over)} km', label: 'VƯỢT')
    else
      (value: runCardKm(card.km), label: 'KM TÍCH LUỸ'),
    achievers,
  ];

  return AchievementCardData(
    tier: card.tier,
    secret: card.secret,
    art: ContractCardArt(
      scene: _sceneOf(snap, meetAt: meetAt),
      day: span?.first,
    ),
    kind: kind,
    hero: hero,
    heroUnit: unit,
    title: title,
    stats: stats,
    period: when.isEmpty
        ? null
        : (text: when, span: span == null ? '' : '${span.days} NGÀY'),
    stamp: snap.targetValue > 0
        ? ContractCardStamp(
            tier: card.tier,
            pct: '${(snap.progressValue / snap.targetValue * 100).floor()}%',
          )
        : null,
    backFace: ContractCardBack(
      tier: card.tier,
      title: title,
      period: contractCardDateLine(
        snap.startAt,
        snap.endAtExclusive,
        meetAt: meetAt,
      ),
    ),
    owner: (snap.displayName.isEmpty ? '3i member' : snap.displayName)
        .toUpperCase(),
    serial: '',
    desc: '',
    meta: '',
    date: span == null ? '' : _fullDay(span.last),
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
              RunCardFrame(
                child: _faceDown(
                  km: view.km,
                  chip:
                      'CHỐT ${_two(at.hour)}:${_two(at.minute)} · '
                      '${_two(at.day)}/${_two(at.month)}',
                  locked: true,
                ),
              ),
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
                child: _faceDown(
                  chip: contractCardLockLabel(reason),
                  locked: true,
                ),
              ),
              _Hint(contractCardLockText(reason)),
            ],
          );
        }
        return Column(
          children: [
            RunCardFrame(
              child: _faceDown(km: view.km, chip: _tapToFlip, onFlip: _roll),
            ),
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

  static const _tapToFlip = 'CHẠM ĐỂ LẬT';

  Widget _faceDown({
    required String chip,
    double? km,
    bool locked = false,
    VoidCallback? onFlip,
  }) {
    final contract = widget.contract;
    return ContractCardFaceDown(
      title: contract.title,
      period: contractCardDateLine(
        contract.startAt,
        contract.endAtExclusive,
        meetAt: contract.meetAt,
      ),
      chip: chip,
      km: km,
      locked: locked,
      onFlip: onFlip,
    );
  }

  Future<void> _roll() async {
    // Chạm thẻ và nút Lật thẻ cùng gọi vào đây; đang lật thì bỏ qua.
    if (_rolling) return;
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
    final data = contractCardData(card, meetAt: widget.contract.meetAt);
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
            from: RunCardFrame(
              child: _faceDown(km: card.km, chip: _tapToFlip),
            ),
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
