import 'package:latlong2/latlong.dart';

/// 1 địa danh dọc theo 1 cung đường "Hành Trình" — toạ độ thật, đặt tại vị
/// trí đúng của địa danh đó (không phải điểm suy diễn trên polyline).
/// [cumulativeMeters] là khoảng cách đi đường thật (OSRM) từ điểm xuất phát
/// tới địa danh này, tính sẵn lúc dựng dữ liệu (xem
/// `assets/journey/*.json` + script tạo dữ liệu).
class JourneyMilestone {
  const JourneyMilestone({
    required this.name,
    required this.location,
    required this.cumulativeMeters,
    required this.fact,
    this.storagePath,
  });

  factory JourneyMilestone.fromMap(Map<String, dynamic> map) {
    return JourneyMilestone(
      name: map['name'] as String,
      location: LatLng(
        (map['lat'] as num).toDouble(),
        (map['lon'] as num).toDouble(),
      ),
      cumulativeMeters: (map['cumulativeMeters'] as num).toDouble(),
      fact: map['fact'] as String? ?? '',
      storagePath: map['storagePath'] as String?,
    );
  }

  final String name;
  final LatLng location;
  final double cumulativeMeters;
  final String fact;

  /// Ảnh minh hoạ địa danh trên Firebase Storage (`journey/photos/…`, lấy 1
  /// lần từ Wikimedia Commons lúc dựng dữ liệu rồi upload lên — không bundle
  /// vào app để app không phình to khi thêm nhiều hành trình/mốc sau này,
  /// cũng không hotlink CDN ngoài vốn dễ bị rate-limit). Đọc qua
  /// `StorageImage` (`widgets/storage_image.dart`) — cùng cơ chế
  /// `getDownloadURL()` + cache app đã dùng cho avatar/ảnh hoạt động. Null
  /// với vài mốc nhỏ chưa có ảnh phù hợp.
  final String? storagePath;
}

/// 1 cung đường "Hành Trình" — dữ liệu đường đi thật (không phải hình vẽ
/// tượng trưng), cùng danh sách mốc dừng dọc đường. Đọc từ Firestore
/// (`journeyRoutes/{routeId}` + subcollection `detail`, xem
/// `MemberRepository.getJourneyRouteDetail`) — nội dung tĩnh dùng chung cho
/// mọi user, không có logic ghi từ client (`firestore.rules`).
class JourneyRoute {
  const JourneyRoute({
    required this.id,
    required this.name,
    required this.tagline,
    required this.totalLengthMeters,
    required this.points,
    required this.milestones,
  });

  factory JourneyRoute.fromMap(Map<String, dynamic> map) {
    final rawPoints = map['points'] as List<dynamic>;
    final rawMilestones = map['milestones'] as List<dynamic>;
    return JourneyRoute(
      id: map['id'] as String,
      name: map['name'] as String,
      tagline: map['tagline'] as String,
      totalLengthMeters: (map['totalLengthMeters'] as num).toDouble(),
      // Firestore không cho mảng lồng mảng, nên points lưu dạng list các
      // map {lat, lon} thay vì list các cặp [lat, lon].
      points: [
        for (final point in rawPoints)
          LatLng(
            ((point as Map<String, dynamic>)['lat'] as num).toDouble(),
            (point['lon'] as num).toDouble(),
          ),
      ],
      milestones: [
        for (final milestone in rawMilestones)
          JourneyMilestone.fromMap(milestone as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String name;
  final String tagline;
  final double totalLengthMeters;
  final List<LatLng> points;
  final List<JourneyMilestone> milestones;
}

/// Bản tóm tắt nhẹ của 1 route — chỉ 3 field màn Journey Hub cần
/// (tên/tagline/tổng km) để hiện danh sách level, không kéo theo
/// points/milestones nặng (có route hàng ngàn điểm). Đọc từ đúng doc
/// `journeyRoutes/{routeId}` nhưng KHÔNG đọc subcollection `detail` — xem
/// `MemberRepository.getJourneyRouteSummary`.
class JourneyRouteSummary {
  const JourneyRouteSummary({
    required this.id,
    required this.name,
    required this.tagline,
    required this.totalLengthMeters,
  });

  factory JourneyRouteSummary.fromMap(Map<String, dynamic> map) {
    return JourneyRouteSummary(
      id: map['id'] as String,
      name: map['name'] as String,
      tagline: map['tagline'] as String,
      totalLengthMeters: (map['totalLengthMeters'] as num).toDouble(),
    );
  }

  final String id;
  final String name;
  final String tagline;
  final double totalLengthMeters;
}

enum JourneyRouteId { athensMarathon, tourDuMontBlanc, coastal, hcmTrail, dongNamA }

extension JourneyRouteIdInfo on JourneyRouteId {
  /// Trùng với document id trong collection `journeyRoutes` trên Firestore.
  String get value => switch (this) {
    JourneyRouteId.athensMarathon => 'athens_marathon',
    JourneyRouteId.tourDuMontBlanc => 'tour_du_mont_blanc',
    JourneyRouteId.coastal => 'coastal',
    JourneyRouteId.hcmTrail => 'hcm_trail',
    JourneyRouteId.dongNamA => 'dong_nam_a',
  };
}

JourneyRouteId? parseJourneyRouteId(String? value) => switch (value) {
  'athens_marathon' => JourneyRouteId.athensMarathon,
  'tour_du_mont_blanc' => JourneyRouteId.tourDuMontBlanc,
  'coastal' => JourneyRouteId.coastal,
  'hcm_trail' => JourneyRouteId.hcmTrail,
  'dong_nam_a' => JourneyRouteId.dongNamA,
  _ => null,
};

/// 3 chiến dịch "Hành Trình", mở khoá tuần tự theo cự ly tăng dần — level
/// sau chỉ mở khi đã xong level trước (xem
/// [JourneyCampaignInfo.priorCampaigns] + cách dùng ở
/// `journeyCampaignOffsetProvider`, `providers.dart`). Chỉ giữ các chiến
/// dịch đã có đủ cả ảnh đại diện thật lẫn cung đường thật.
enum JourneyCampaignId { marathon, montBlanc, xuyenViet, dongNamA }

/// Thứ tự cố định của các chiến dịch, xếp theo cự ly tăng dần — nguồn sự
/// thật duy nhất cho "level" và cho việc tính offset km dồn từ (các) chiến
/// dịch trước.
const journeyCampaignOrder = [
  JourneyCampaignId.marathon,
  JourneyCampaignId.montBlanc,
  JourneyCampaignId.xuyenViet,
  JourneyCampaignId.dongNamA,
];

extension JourneyCampaignInfo on JourneyCampaignId {
  /// 1-indexed, chỉ để hiển thị ("Level 1", "Level 2"...).
  int get level => journeyCampaignOrder.indexOf(this) + 1;

  String get name => switch (this) {
    JourneyCampaignId.marathon => 'Marathon Athens',
    JourneyCampaignId.montBlanc => 'Tour du Mont Blanc',
    JourneyCampaignId.xuyenViet => 'Hành Trình Xuyên Việt',
    JourneyCampaignId.dongNamA => 'Đông Nam Á',
  };

  String get value => switch (this) {
    JourneyCampaignId.marathon => 'marathon',
    JourneyCampaignId.montBlanc => 'mont_blanc',
    JourneyCampaignId.xuyenViet => 'xuyen_viet',
    JourneyCampaignId.dongNamA => 'dong_nam_a',
  };

  /// Cung đường trong chiến dịch. Chỉ Xuyên Việt có 2 lựa chọn (coastal/hcm
  /// trail); các chiến dịch khác chỉ có 1 cung duy nhất, không cần màn chọn.
  List<JourneyRouteId> get routeChoices => switch (this) {
    JourneyCampaignId.marathon => const [JourneyRouteId.athensMarathon],
    JourneyCampaignId.montBlanc => const [JourneyRouteId.tourDuMontBlanc],
    JourneyCampaignId.xuyenViet => const [
      JourneyRouteId.coastal,
      JourneyRouteId.hcmTrail,
    ],
    JourneyCampaignId.dongNamA => const [JourneyRouteId.dongNamA],
  };

  /// Các chiến dịch đứng trước, theo đúng thứ tự — dùng để cộng dồn km làm
  /// offset mở khoá (xem `journeyCampaignOffsetProvider`).
  List<JourneyCampaignId> get priorCampaigns =>
      journeyCampaignOrder.sublist(0, journeyCampaignOrder.indexOf(this));

  /// Chiến dịch kế tiếp, null nếu đã là chiến dịch cuối cùng.
  JourneyCampaignId? get next {
    final index = journeyCampaignOrder.indexOf(this);
    return index + 1 < journeyCampaignOrder.length
        ? journeyCampaignOrder[index + 1]
        : null;
  }
}

JourneyCampaignId? parseJourneyCampaignId(String? value) => switch (value) {
  'marathon' => JourneyCampaignId.marathon,
  'mont_blanc' => JourneyCampaignId.montBlanc,
  'xuyen_viet' => JourneyCampaignId.xuyenViet,
  'dong_nam_a' => JourneyCampaignId.dongNamA,
  _ => null,
};

/// Vị trí hiện tại của 1 user trên 1 [JourneyRoute], suy ra thuần từ tổng
/// km trọn đời — không có state riêng nào khác cần lưu.
class JourneyProgress {
  const JourneyProgress({
    required this.route,
    required this.totalDistanceMeters,
  });

  final JourneyRoute route;
  final double totalDistanceMeters;

  double get distanceIntoRouteMeters =>
      totalDistanceMeters.clamp(0, route.totalLengthMeters);

  double get remainingMeters =>
      (route.totalLengthMeters - distanceIntoRouteMeters).clamp(
        0,
        route.totalLengthMeters,
      );

  bool get isComplete => totalDistanceMeters >= route.totalLengthMeters;

  bool isMilestoneReached(JourneyMilestone milestone) =>
      totalDistanceMeters >= milestone.cumulativeMeters;

  /// Mốc kế tiếp chưa đạt được theo thứ tự dọc đường, null nếu đã xong hết.
  JourneyMilestone? get nextMilestone {
    for (final milestone in route.milestones) {
      if (!isMilestoneReached(milestone)) return milestone;
    }
    return null;
  }

  double? get remainingToNextMilestoneMeters {
    final next = nextMilestone;
    if (next == null) return null;
    return (next.cumulativeMeters - totalDistanceMeters).clamp(
      0,
      route.totalLengthMeters,
    );
  }
}

/// Số km rút gọn — không cần độ chính xác 2 chữ số thập phân, chỉ cần đủ
/// đọc nhanh ("2.596 km" thay vì "2595.69 km"), có dấu chấm ngăn nghìn theo
/// cách đọc số tiếng Việt.
String formatCompactKm(double meters) {
  final km = (meters / 1000).round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < km.length; i++) {
    if (i > 0 && (km.length - i) % 3 == 0) buffer.write('.');
    buffer.write(km[i]);
  }
  return buffer.toString();
}
