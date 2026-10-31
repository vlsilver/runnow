import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_card_art.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/providers.dart';

typedef _Campaign = ({String name, String route});

/// Tên in trên thẻ theo chặng, và đường đi ngắn gọn ở dòng loại thẻ.
const _campaigns = <String, _Campaign>{
  'marathon': (name: 'Marathon Athens', route: 'Marathon – Athens'),
  'mont_blanc': (name: 'Tour du Mont Blanc', route: 'Pháp · Ý · Thuỵ Sĩ'),
  'xuyen_viet': (name: 'Xuyên Việt', route: 'Hà Nội – Cà Mau'),
  'dong_nam_a': (name: 'Đông Nam Á', route: '7 thủ đô'),
};

/// Thẻ Hành trình của một chặng đã về đích, ở
/// users/{uid}/journeyCards/{campaign}. Backend ghi một lần lúc tổng km trọn
/// đời qua mốc về đích; bậc cố định theo chặng.
class JourneyCard {
  const JourneyCard({
    required this.campaign,
    required this.routeId,
    required this.level,
    required this.tier,
    required this.distanceMeters,
    required this.runCount,
    this.finishedAt,
    this.awardedAt,
  });

  /// Đọc từ Firestore thì provider đổi Timestamp sang DateTime trước.
  factory JourneyCard.fromJson(String campaign, Map<String, dynamic> json) {
    final finishedAt = json['finishedAt'];
    final awardedAt = json['awardedAt'];
    return JourneyCard(
      campaign: campaign,
      routeId: json['routeId'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 0,
      tier: runCardTierFromKey(json['tier'] as String?),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      runCount: (json['runCount'] as num?)?.toInt() ?? 0,
      finishedAt: finishedAt is DateTime ? finishedAt : null,
      awardedAt: awardedAt is DateTime ? awardedAt : null,
    );
  }

  /// marathon, mont_blanc, xuyen_viet, dong_nam_a.
  final String campaign;

  /// Cung đã đi; chỉ Xuyên Việt có hai cung.
  final String routeId;
  final int level;
  final GameCardTier tier;

  /// Độ dài cung của chặng.
  final double distanceMeters;

  /// Số buổi có km rơi vào chặng này.
  final int runCount;

  /// Giờ bắt đầu buổi chạy đưa tổng km qua mốc về đích.
  final DateTime? finishedAt;

  /// Lúc backend trao thẻ. Thẻ phát bù có lúc trao muộn hơn lúc về đích
  /// nhiều tháng.
  final DateTime? awardedAt;

  /// Chặng lạ (backend mới thêm) thì lấy khoá làm tên.
  String get name => _campaigns[campaign]?.name ?? campaign;
  String get km => journeyCardKm(distanceMeters);
}

/// Số km tròn, nhóm nghìn bằng dấu chấm: 2100000 m là "2.100".
String journeyCardKm(double meters) {
  final digits = (meters / 1000).round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime? at, {bool short = false}) {
  if (at == null) return '';
  final d = at.toLocal();
  final year = short ? _two(d.year % 100) : '${d.year}';
  return '${_two(d.day)}.${_two(d.month)}.$year';
}

/// Dữ liệu thẻ khuôn thẻ thành tích: mặt trước là huy chương về đích và số
/// liệu, mặt sau là bản đồ đường chạy thật của cung.
AchievementCardData journeyCardData(JourneyCard card, {required String owner}) {
  final route = _campaigns[card.campaign]?.route;
  return AchievementCardData(
    tier: card.tier,
    art: JourneyMedalArt(
      campaign: card.campaign,
      routeId: card.routeId,
      tier: card.tier,
      rim: '${card.name.toUpperCase()} · ${card.km} KM',
    ),
    backFace: JourneyRouteMap(
      campaign: card.campaign,
      routeId: card.routeId,
      title: card.name.toUpperCase(),
    ),
    kind: route == null ? 'HÀNH TRÌNH' : 'HÀNH TRÌNH · ${route.toUpperCase()}',
    hero: card.name.toUpperCase(),
    heroUnit: '',
    title: 'Đã về đích · Level ${card.level}',
    stats: [
      (value: '${card.km} km', label: 'CỰ LY'),
      (value: '${card.runCount}', label: 'BUỔI CHẠY'),
      (value: _date(card.finishedAt, short: true), label: 'VỀ ĐÍCH'),
    ],
    owner: owner.toUpperCase(),
    serial: '',
    desc: '',
    meta: 'LEVEL ${card.level}',
    date: _date(card.finishedAt),
  );
}

/// Thẻ Hành trình đem khoe.
CardShareSubject journeyCardShareSubject(
  JourneyCard card, {
  required String owner,
}) => CardShareSubject(
  id: 'journey-${card.campaign}',
  printed: [
    card.tier.name,
    card.campaign,
    card.routeId,
    card.level,
    card.km,
    card.runCount,
    _date(card.finishedAt),
    owner,
  ].join('|'),
  text: 'Về đích ${card.name} · ${card.km} km\nChia sẻ từ 3i',
);

/// Xem thẻ toàn màn hình: nghiêng, lật, khoe. Thẻ chỉ có khi đã về đích nên
/// lúc nào cũng khoe được. [faceDown] mở lá đang úp để người xem tự lật.
Future<void> showJourneyCardViewer(
  BuildContext context,
  JourneyCard card,
  AchievementCardData data, {
  bool faceDown = false,
  Widget? reaction,
}) => showCardViewer(
  context,
  front: (pose) => AchievementCard(data: data, pose: pose),
  back: (pose) => AchievementCard(data: data, pose: pose, back: true),
  chips: [gameCardTiers[card.tier]!.label, 'Hành trình · Level ${card.level}'],
  cardSize: achievementCardSize,
  startBack: faceDown,
  reaction: reaction,
  onShare: (_, origin) async {
    // Ảnh và video khoe được giữ theo khoá thẻ, nên chỉ chụp khi đường chạy
    // đã tải xong; tải lỗi thì màn xem báo khoe thất bại.
    if (parseJourneyRouteId(card.routeId) case final id?) {
      await ProviderScope.containerOf(
        origin,
        listen: false,
      ).read(journeyRouteDetailProvider(id).future);
    }
    if (!origin.mounted) return;
    await showCardShare(
      origin,
      subject: journeyCardShareSubject(card, owner: data.owner),
      data: data,
    );
  },
);

/// Lá chặng nằm úp, rộng [width]; chạm để mở màn lật thẻ.
class JourneyCardFaceDown extends StatelessWidget {
  const JourneyCardFaceDown({
    super.key,
    required this.card,
    required this.owner,
    required this.width,
  });

  final JourneyCard card;

  /// Tên in trên thẻ.
  final String owner;
  final double width;

  @override
  Widget build(BuildContext context) {
    final data = journeyCardData(card, owner: owner);
    return Semantics(
      button: true,
      label: 'Mở thẻ Hành trình ${card.name}',
      child: GestureDetector(
        onTap: () => showJourneyCardViewer(context, card, data, faceDown: true),
        child: GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(data: data, back: true),
        ),
      ),
    );
  }
}
