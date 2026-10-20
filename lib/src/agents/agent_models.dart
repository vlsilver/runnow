/// Model của bot cá nhân (thử nghiệm), khớp JSON của /v1/agents*.
library;

String _string(Object? value) => value is String ? value : '';

String? _optString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) => [
  if (value is List)
    for (final item in value)
      if (item is Map<String, dynamic>) parse(item),
];

class AgentProfile {
  const AgentProfile({
    required this.name,
    required this.persona,
    required this.created,
  });

  factory AgentProfile.fromJson(Map<String, dynamic> json) => AgentProfile(
    name: _string(json['name']),
    persona: _string(json['persona']),
    created: json['created'] == true,
  );

  final String name;
  final String persona;

  /// false: hồ sơ mặc định, chủ chưa lưu lần nào nên bot chưa vào phòng.
  final bool created;
}

class AgentMemory {
  const AgentMemory({
    required this.id,
    required this.text,
    required this.source,
    this.updatedAt,
  });

  factory AgentMemory.fromJson(Map<String, dynamic> json) => AgentMemory(
    id: _string(json['id']),
    text: _string(json['text']),
    source: _string(json['source']),
    updatedAt: _date(json['updatedAt']),
  );

  final String id;
  final String text;

  /// `manual`: chủ tự thêm; `chat`: bot ghi khi chat riêng.
  final String source;
  final DateTime? updatedAt;

  bool get fromChat => source == 'chat';
}

class AgentMe {
  const AgentMe({
    required this.enabled,
    required this.agent,
    required this.memories,
    required this.memoryLimit,
  });

  factory AgentMe.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'];
    return AgentMe(
      enabled: json['enabled'] == true,
      agent: agent is Map<String, dynamic>
          ? AgentProfile.fromJson(agent)
          : null,
      memories: _list(json['memories'], AgentMemory.fromJson),
      memoryLimit: _int(json['memoryLimit']),
    );
  }

  /// false: người này chưa được mời thử nghiệm, app ẩn mục bot.
  final bool enabled;
  final AgentProfile? agent;
  final List<AgentMemory> memories;
  final int memoryLimit;
}

/// Tin có seq, để một controller dùng chung cho chat riêng và phòng bot.
abstract interface class AgentSeqMessage {
  int get seq;
}

class AgentMessage implements AgentSeqMessage {
  const AgentMessage({
    required this.seq,
    required this.fromAgent,
    required this.text,
    this.at,
  });

  factory AgentMessage.fromJson(Map<String, dynamic> json) => AgentMessage(
    seq: _int(json['seq']),
    fromAgent: json['role'] == 'agent',
    text: _string(json['text']),
    at: _date(json['at']),
  );

  @override
  final int seq;

  /// true là bot nói, false là chủ.
  final bool fromAgent;
  final String text;
  final DateTime? at;
}

class AgentRoomMessage implements AgentSeqMessage {
  const AgentRoomMessage({
    required this.seq,
    required this.fromAgent,
    required this.uid,
    required this.name,
    required this.owner,
    required this.text,
    this.at,
  });

  factory AgentRoomMessage.fromJson(Map<String, dynamic> json) =>
      AgentRoomMessage(
        seq: _int(json['seq']),
        fromAgent: json['kind'] == 'agent',
        uid: _string(json['uid']),
        name: _string(json['name']),
        owner: _optString(json['owner']),
        text: _string(json['text']),
        at: _date(json['at']),
      );

  @override
  final int seq;
  final bool fromAgent;

  /// Người gửi; tin của bot thì là uid chủ bot.
  final String uid;

  /// Tên người, hoặc tên bot lúc nói.
  final String name;

  /// Tên chủ bot; null với tin của người.
  final String? owner;
  final String text;
  final DateTime? at;
}

class AgentRoomMember {
  const AgentRoomMember({
    required this.uid,
    required this.name,
    required this.botName,
  });

  factory AgentRoomMember.fromJson(Map<String, dynamic> json) =>
      AgentRoomMember(
        uid: _string(json['uid']),
        name: _string(json['name']),
        botName: _optString(json['botName']),
      );

  final String uid;
  final String name;

  /// null khi người này chưa tạo bot.
  final String? botName;
}

/// Một trang chat theo seq, tin mới trước. Dùng chung cho chat riêng (có
/// [waiting]) và phòng bot (có [members]).
class AgentChatPage<M extends AgentSeqMessage> {
  const AgentChatPage({
    required this.messages,
    this.cursor,
    this.hasNewer = false,
    this.waiting = false,
    this.members = const [],
  });

  static AgentChatPage<AgentMessage> dmFromJson(Map<String, dynamic> json) =>
      AgentChatPage(
        messages: _list(json['messages'], AgentMessage.fromJson),
        cursor: _optString(json['cursor']),
        hasNewer: json['hasNewer'] == true,
        waiting: json['waiting'] == true,
      );

  static AgentChatPage<AgentRoomMessage> roomFromJson(
    Map<String, dynamic> json,
  ) => AgentChatPage(
    messages: _list(json['messages'], AgentRoomMessage.fromJson),
    cursor: _optString(json['cursor']),
    hasNewer: json['hasNewer'] == true,
    members: _list(json['members'], AgentRoomMember.fromJson),
  );

  final List<M> messages;

  /// Có khi còn tin cũ hơn; null là đã hết.
  final String? cursor;

  /// Trang đọc bằng `after` còn tin mới hơn.
  final bool hasNewer;

  /// Chat riêng: tin cuối của chủ chưa được bot trả lời.
  final bool waiting;

  /// Phòng bot: thành viên và bot của họ. Rỗng khi poll không có tin mới.
  final List<AgentRoomMember> members;
}
