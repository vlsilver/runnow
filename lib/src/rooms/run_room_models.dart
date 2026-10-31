import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';

/// Ai vào được phòng: public vào thẳng, private chờ chủ duyệt, password cần
/// mật khẩu. Backend kiểm, app chỉ hiển thị.
enum RunRoomPrivacy {
  public('public', 'Công khai'),
  private('private', 'Chủ duyệt'),
  password('password', 'Mật khẩu');

  const RunRoomPrivacy(this.value, this.label);

  final String value;
  final String label;

  static RunRoomPrivacy fromValue(String? value) => RunRoomPrivacy.values
      .firstWhere((p) => p.value == value, orElse: () => RunRoomPrivacy.public);
}

/// group là phòng mở để rủ nhau chạy; solo là phòng ngầm của một buổi chạy
/// riêng, mở lúc bắt đầu chạy để người khác xin chạy cùng. Phòng thiếu field
/// này là group.
enum RunRoomKind {
  group,
  solo;

  static RunRoomKind fromValue(String? value) =>
      value == 'solo' ? RunRoomKind.solo : RunRoomKind.group;
}

/// Buổi chạy riêng có nhận người chạy cùng không, chọn trước khi bắt đầu.
/// Nhận thì lúc bắt đầu chạy app mở một phòng solo với quyền vào tương ứng.
enum LiveJoinPolicy {
  open('Tự vào'),
  approve('Đợi duyệt'),
  off('Không cho');

  const LiveJoinPolicy(this.label);

  final String label;

  /// Quyền vào của phòng solo; null là không mở phòng.
  RunRoomPrivacy? get roomPrivacy => switch (this) {
    LiveJoinPolicy.open => RunRoomPrivacy.public,
    LiveJoinPolicy.approve => RunRoomPrivacy.private,
    LiveJoinPolicy.off => null,
  };
}

/// Buổi live chỉ người trong phòng xem: chạy trong phòng group không công
/// khai, hoặc chưa đọc được phòng. Phòng solo là buổi chạy riêng đang nhận
/// người chạy cùng, nên buổi live vẫn hiện cho cả club.
bool runRoomLiveRoomOnly({
  required String? roomId,
  required RunRoomKind? kind,
  required RunRoomPrivacy? privacy,
}) =>
    roomId != null &&
    kind != RunRoomKind.solo &&
    privacy != RunRoomPrivacy.public;

/// Buổi chạy bộ không vào phòng nào và đang bật Live thì được nhận người chạy
/// cùng. Tắt Live thì không mở phòng và không hỏi quyền vào.
bool runRoomCanHostRunTogether({
  required String? roomId,
  required bool isRun,
  required bool liveEnabled,
}) => roomId == null && isRun && liveEnabled;

/// Số điểm tối đa của tuyến gửi lên phòng. Backend nhận tới 200; tuyến nằm
/// trong doc phòng mà list phòng đọc cả doc, nên app gửi ít hơn.
const runRoomRouteMaxPoints = 120;

/// Rút tuyến vẽ hay nhập GPX về [runRoomRouteMaxPoints] điểm cách đều theo
/// thứ tự, giữ điểm đầu, điểm cuối và quãng của tuyến gốc.
RunContractRoute runRoomRoutePreview(RunContractRoute route) {
  final points = route.points;
  if (points.length <= runRoomRouteMaxPoints) return route;
  final last = points.length - 1;
  return RunContractRoute(
    points: [
      for (var i = 0; i < runRoomRouteMaxPoints; i++)
        points[(i * last / (runRoomRouteMaxPoints - 1)).round()],
    ],
    distanceMeters: route.distanceMeters,
  );
}

const runRoomWeekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Ngày hẹn so với hôm nay theo giờ máy: "Hôm nay", "Mai", rồi thứ ("T7").
String runRoomDayLabel(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  return switch (day.difference(today).inDays) {
    0 => 'Hôm nay',
    1 => 'Mai',
    _ => runRoomWeekdayShort[day.weekday - 1],
  };
}

/// Ai vào được, nói theo phía người xem danh sách phòng.
String runRoomAccessLabel(RunRoomPrivacy privacy) => switch (privacy) {
  RunRoomPrivacy.public => 'Tự vào',
  RunRoomPrivacy.private => 'Chủ duyệt',
  RunRoomPrivacy.password => 'Mật khẩu',
};

/// State của một người trong phòng, khớp `members/{uid}.state` backend ghi.
enum RunRoomMemberState {
  requested,
  joined,
  left,
  kicked,
  denied;

  static RunRoomMemberState fromValue(String? value) =>
      RunRoomMemberState.values.firstWhere(
        (s) => s.name == value,
        orElse: () => RunRoomMemberState.left,
      );
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  _ => null,
};

class RunRoom {
  const RunRoom({
    required this.id,
    required this.hostUid,
    required this.hostName,
    required this.title,
    required this.privacy,
    required this.maxRunners,
    required this.runnerCount,
    required this.ended,
    required this.startsAt,
    required this.closesAt,
    this.kind = RunRoomKind.group,
    this.route,
  });

  factory RunRoom.fromMap(String id, Map<String, dynamic> map) => RunRoom(
    id: id,
    hostUid: map['hostUid'] as String? ?? '',
    hostName: map['hostName'] as String? ?? 'Thành viên',
    title: map['title'] as String? ?? '',
    privacy: RunRoomPrivacy.fromValue(map['privacy'] as String?),
    maxRunners: (map['maxRunners'] as num?)?.toInt() ?? 0,
    runnerCount: (map['runnerCount'] as num?)?.toInt() ?? 0,
    ended: map['status'] != 'open',
    startsAt: _date(map['startsAt']),
    closesAt: _date(map['closesAt']),
    kind: RunRoomKind.fromValue(map['kind'] as String?),
    route: switch (map['route']) {
      final Map<String, dynamic> route => RunContractRoute.fromMap(route),
      _ => null,
    },
  );

  final String id;
  final String hostUid;
  final String hostName;
  final String title;
  final RunRoomPrivacy privacy;
  final int maxRunners;
  final int runnerCount;
  final bool ended;
  final DateTime? startsAt;
  final DateTime? closesAt;
  final RunRoomKind kind;

  /// Tuyến chủ phòng vẽ hay nhập GPX, bản rút gọn để vẽ lên map.
  final RunContractRoute? route;

  /// Còn vào được không: chưa kết thúc và chưa quá giờ đóng (backend tự đóng
  /// phòng 6 tiếng sau giờ hẹn).
  bool isOpen(DateTime now) {
    final closes = closesAt;
    return !ended && closes != null && now.isBefore(closes);
  }

  bool get full => runnerCount >= maxRunners;
}

class RunRoomMember {
  const RunRoomMember({
    required this.uid,
    required this.name,
    required this.host,
    required this.state,
  });

  factory RunRoomMember.fromMap(String uid, Map<String, dynamic> map) =>
      RunRoomMember(
        uid: uid,
        name: map['name'] as String? ?? 'Thành viên',
        host: map['role'] == 'host',
        state: RunRoomMemberState.fromValue(map['state'] as String?),
      );

  final String uid;
  final String name;
  final bool host;
  final RunRoomMemberState state;
}

/// Một lần cổ vũ trong phòng: emoji hoặc một câu ngắn (tối đa 120 ký tự).
class RunRoomMessage {
  const RunRoomMessage({
    required this.id,
    required this.uid,
    required this.emoji,
    required this.text,
    required this.at,
  });

  factory RunRoomMessage.fromMap(String id, Map<String, dynamic> map) =>
      RunRoomMessage(
        id: id,
        uid: map['uid'] as String? ?? '',
        emoji: map['kind'] == 'emoji',
        text: map['text'] as String? ?? '',
        at: _date(map['at']),
      );

  final String id;
  final String uid;
  final bool emoji;
  final String text;

  /// Null khi tin vừa gửi chưa có giờ server.
  final DateTime? at;
}

/// Một phòng mình đang ở hay đang xin vào, đọc từ collection group members.
class RunRoomMembership {
  const RunRoomMembership({required this.roomId, required this.state});

  final String roomId;
  final RunRoomMemberState state;
}
