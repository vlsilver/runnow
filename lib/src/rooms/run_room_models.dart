import 'package:cloud_firestore/cloud_firestore.dart';

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
