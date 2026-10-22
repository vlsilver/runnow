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

/// Điều bot tự học được từ tin trong phòng bot và group Telegram.
class AgentLearnedFact {
  const AgentLearnedFact({
    required this.id,
    required this.text,
    required this.source,
    this.updatedAt,
  });

  factory AgentLearnedFact.fromJson(Map<String, dynamic> json) =>
      AgentLearnedFact(
        id: _string(json['id']),
        text: _string(json['text']),
        source: _string(json['source']),
        updatedAt: _date(json['updatedAt']),
      );

  final String id;
  final String text;

  /// `learned`: bot tự học; `migrated`: chuyển từ trí nhớ cũ của 3i.
  final String source;
  final DateTime? updatedAt;

  bool get migrated => source == 'migrated';
}

/// Điều bot biết về cả nhóm; chỉ admin xoá được.
class AgentGroupFacts {
  const AgentGroupFacts({required this.facts, required this.canDelete});

  factory AgentGroupFacts.fromJson(Map<String, dynamic> json) =>
      AgentGroupFacts(
        facts: _list(json['facts'], AgentLearnedFact.fromJson),
        canDelete: json['canDelete'] == true,
      );

  final List<AgentLearnedFact> facts;
  final bool canDelete;
}

class AgentMe {
  const AgentMe({
    required this.enabled,
    required this.agent,
    required this.memories,
    required this.memoryLimit,
    required this.learned,
    this.noLearn = false,
    this.consentRequired = false,
    this.consentVersion = 0,
    this.today,
    this.telegram,
  });

  factory AgentMe.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'];
    final today = json['today'];
    final telegram = json['telegram'];
    return AgentMe(
      enabled: json['enabled'] == true,
      agent: agent is Map<String, dynamic>
          ? AgentProfile.fromJson(agent)
          : null,
      memories: _list(json['memories'], AgentMemory.fromJson),
      memoryLimit: _int(json['memoryLimit']),
      learned: _list(json['learned'], AgentLearnedFact.fromJson),
      noLearn: json['noLearn'] == true,
      consentRequired: json['consentRequired'] == true,
      consentVersion: _int(json['consentVersion']),
      today: today is Map<String, dynamic> ? AgentToday.fromJson(today) : null,
      telegram: telegram is Map<String, dynamic>
          ? AgentTelegram.fromJson(telegram)
          : null,
    );
  }

  /// false: người này chưa được mời thử nghiệm, app ẩn mục bot.
  final bool enabled;
  final AgentProfile? agent;
  final List<AgentMemory> memories;
  final int memoryLimit;

  /// Điều bot tự học về người này, có cả khi chưa tạo bot.
  final List<AgentLearnedFact> learned;

  /// Đã tắt "Cho bot tự học về bạn". Backend cũ chưa có field thì là false.
  final bool noLearn;

  /// Phải đồng ý gửi dữ liệu cho AI trước khi tạo bot, chat riêng hay nhắn
  /// phòng. Người trong allowlist và backend cũ luôn là false.
  final bool consentRequired;

  /// Bản điều khoản AI đang bắt buộc, gửi lại khi đồng ý.
  final int consentVersion;

  /// Lượt đã dùng hôm nay. Backend cũ chưa có field thì null, app ẩn phần này.
  final AgentToday? today;

  /// Bot trên Telegram. Chỉ có khi backend bật tính năng và chủ đã tạo bot;
  /// null thì app ẩn cả mục.
  final AgentTelegram? telegram;
}

/// MyBot thành bot Telegram thật của chủ. Telegram tạo bot qua [createUrl],
/// rồi báo backend; backend nối bot với chủ vài giây sau đó.
class AgentTelegram {
  const AgentTelegram({
    required this.createUrl,
    required this.linked,
    this.botUsername,
    this.setupError,
    this.pscJoinUrl,
    this.inPsc = false,
  });

  factory AgentTelegram.fromJson(Map<String, dynamic> json) => AgentTelegram(
    createUrl: _string(json['createUrl']),
    linked: json['linked'] == true,
    botUsername: _optString(json['botUsername']),
    setupError: _optString(json['setupError']),
    pscJoinUrl: _optString(json['pscJoinUrl']),
    inPsc: json['inPsc'] == true,
  );

  /// Màn tạo bot của Telegram, điền sẵn username và tên.
  final String createUrl;

  /// Backend đã nối một bot Telegram với chủ.
  final bool linked;
  final String? botUsername;

  /// Bot có rồi mà cài không được, thường do chủ đã xoá bot bên Telegram.
  final String? setupError;

  /// Màn chọn group của Telegram để thêm bot vào PSC. Backend chỉ trả khi
  /// Phòng bot (một topic của PSC) đang bật.
  final String? pscJoinUrl;

  /// Bot đang ở group PSC nên được nói trong topic Phòng bot.
  final bool inPsc;

  /// Bot đang chạy trên Telegram, không còn gì phải đợi.
  bool get running => linked && setupError == null;

  /// Bot chạy rồi, Phòng bot đang bật mà bot chưa vào PSC.
  bool get canJoinPsc => running && pscJoinUrl != null && !inPsc;
}

/// Vì sao bot đang trả câu nghỉ thay cho câu trả lời thật.
enum AgentResting {
  /// Cả hệ thống chạm trần tiền AI hôm nay, mọi bot cùng nghỉ.
  budget,

  /// Người này hết lượt chat riêng hôm nay.
  dmLimit,
}

/// Lượt chat riêng và tin phòng bot đã dùng hôm nay (giờ VN), 0h đếm lại.
class AgentToday {
  const AgentToday({
    required this.dmUsed,
    required this.dmMax,
    required this.roomUsed,
    required this.roomMax,
    this.resting,
  });

  factory AgentToday.fromJson(Map<String, dynamic> json) => AgentToday(
    dmUsed: _int(json['dmUsed']),
    dmMax: _int(json['dmMax']),
    roomUsed: _int(json['roomUsed']),
    roomMax: _int(json['roomMax']),
    // Lý do lạ (backend mới hơn app) thì coi như không nghỉ, để không hiện
    // câu sai; bot vẫn trả câu nghỉ trong chat.
    resting: switch (json['resting']) {
      'budget' => AgentResting.budget,
      'dm_limit' => AgentResting.dmLimit,
      _ => null,
    },
  );

  final int dmUsed;
  final int dmMax;
  final int roomUsed;
  final int roomMax;

  /// null là bot đang trả lời bình thường.
  final AgentResting? resting;
}

/// Tin có seq, để một controller dùng chung cho chat riêng và phòng bot.
abstract interface class AgentSeqMessage {
  int get seq;

  /// Giữ trong danh sách để poll đi tiếp theo seq, nhưng không vẽ.
  bool get hidden;
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

  /// Chat riêng chỉ có chủ và bot của mình, không có gì để ẩn.
  @override
  bool get hidden => false;

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
    this.hidden = false,
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
        hidden: json['hidden'] == true,
      );

  AgentRoomMessage asHidden() => AgentRoomMessage(
    seq: seq,
    fromAgent: fromAgent,
    uid: uid,
    name: name,
    owner: owner,
    text: '',
    at: at,
    hidden: true,
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

  /// Người xem đã chặn người gửi (tin của bot thì là chủ bot); [text] rỗng.
  @override
  final bool hidden;
}

/// Một người trong danh sách chặn của phòng bot.
class AgentBlocked {
  const AgentBlocked({required this.uid, required this.name});

  factory AgentBlocked.fromJson(Map<String, dynamic> json) =>
      AgentBlocked(uid: _string(json['uid']), name: _string(json['name']));

  static List<AgentBlocked> listFromJson(Map<String, dynamic> json) =>
      _list(json['blocks'], AgentBlocked.fromJson);

  final String uid;
  final String name;
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
