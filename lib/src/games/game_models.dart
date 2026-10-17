// DTO của API Ma Sói (/v1/games*, /v1/telegram/link*), bám theo struct JSON ở
// backend/internal/backend/game_api.go, game_start.go, telegram_link.go.
//
// Các field liệt kê như status, phase.state, action.input, action.kind giữ
// dạng String chứ không đổi sang enum: backend thêm giá trị mới thì app cũ
// vẫn parse được và vẽ theo label backend gửi.
//
// Go encode slice nil thành null, nên mọi list đọc null thành rỗng. Field
// `omitempty` vắng mặt thì đọc thành null (chuỗi) hoặc false/0.

class GameList {
  const GameList({
    required this.canCreate,
    required this.roleOptions,
    required this.items,
  });

  factory GameList.fromJson(Map<String, dynamic> json) {
    final viewer = _map(json['viewer']);
    final createOptions = _map(json['createOptions']);
    return GameList(
      canCreate: viewer['canCreate'] == true,
      roleOptions: _list(createOptions['roles'], GameRoleOption.fromJson),
      items: _list(json['items'], GameListItem.fromJson),
    );
  }

  final bool canCreate;
  final List<GameRoleOption> roleOptions;
  final List<GameListItem> items;
}

class GameRoleOption {
  const GameRoleOption({
    required this.key,
    required this.label,
    required this.defaultOn,
  });

  factory GameRoleOption.fromJson(Map<String, dynamic> json) {
    return GameRoleOption(
      key: _string(json['key']),
      label: _string(json['label']),
      defaultOn: json['default'] == true,
    );
  }

  final String key;
  final String label;
  final bool defaultOn;
}

class GameListItem {
  const GameListItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusLabel,
    required this.playerCount,
    required this.minPlayers,
    required this.maxPlayers,
    required this.hasTodo,
    required this.nextDeadline,
    required this.updatedAt,
    required this.testMode,
  });

  factory GameListItem.fromJson(Map<String, dynamic> json) {
    return GameListItem(
      id: _string(json['id']),
      title: _string(json['title']),
      subtitle: _string(json['subtitle']),
      status: _string(json['status']),
      statusLabel: _string(json['statusLabel']),
      playerCount: _int(json['playerCount']),
      minPlayers: _int(json['minPlayers']),
      maxPlayers: _int(json['maxPlayers']),
      hasTodo: json['hasTodo'] == true,
      nextDeadline: _date(json['nextDeadline']),
      updatedAt: _date(json['updatedAt']),
      testMode: json['testMode'] == true,
    );
  }

  final String id;
  final String title;
  final String subtitle;

  /// registering | starting | running | paused | ended | cancelled
  final String status;
  final String statusLabel;
  final int playerCount;
  final int minPlayers;
  final int maxPlayers;
  final bool hasTodo;
  final DateTime? nextDeadline;
  final DateTime? updatedAt;
  final bool testMode;
}

class GameDetail {
  const GameDetail({
    required this.id,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.testMode,
    required this.version,
    required this.serverNow,
    required this.refreshAfterSeconds,
    required this.rulesText,
    required this.phase,
    required this.players,
    required this.playerCount,
    required this.minPlayers,
    required this.maxPlayers,
    required this.registrationDeadline,
    required this.feed,
    required this.requirements,
    required this.isRegistered,
    required this.isAdmin,
    required this.minAppVersion,
    required this.winner,
    required this.winnerLabel,
    required this.taskKey,
    required this.startError,
  });

  factory GameDetail.fromJson(Map<String, dynamic> json) {
    return GameDetail(
      id: _string(json['id']),
      title: _string(json['title']),
      status: _string(json['status']),
      statusLabel: _string(json['statusLabel']),
      testMode: json['testMode'] == true,
      version: _int(json['version']),
      serverNow: _date(json['serverNow']),
      refreshAfterSeconds: _int(json['refreshAfterSeconds']),
      rulesText: _string(json['rulesText']),
      phase: _obj(json['phase'], GamePhase.fromJson),
      players: _list(json['players'], GamePlayer.fromJson),
      playerCount: _int(json['playerCount']),
      minPlayers: _int(json['minPlayers']),
      maxPlayers: _int(json['maxPlayers']),
      registrationDeadline: _date(json['registrationDeadline']),
      feed: GameFeed.fromJson(_map(json['feed'])),
      requirements: _list(json['requirements'], GameRequirement.fromJson),
      isRegistered: json['isRegistered'] == true,
      isAdmin: json['isAdmin'] == true,
      minAppVersion: _string(json['minAppVersion']),
      winner: _optString(json['winner']),
      winnerLabel: _optString(json['winnerLabel']),
      taskKey: _optString(json['taskKey']),
      startError: _obj(json['startError'], GameStartError.fromJson),
    );
  }

  final String id;
  final String title;
  final String status;
  final String statusLabel;
  final bool testMode;

  /// Tăng mỗi lần state ván đổi; so hai lần đọc để biết có gì mới.
  final int version;

  /// Giờ server lúc trả response; đếm ngược tính theo mốc này chứ không theo
  /// đồng hồ máy.
  final DateTime? serverNow;
  final int refreshAfterSeconds;
  final String rulesText;

  /// null khi ván chưa chạy hoặc đã kết thúc.
  final GamePhase? phase;
  final List<GamePlayer> players;
  final int playerCount;
  final int minPlayers;
  final int maxPlayers;
  final DateTime? registrationDeadline;
  final GameFeed feed;
  final List<GameRequirement> requirements;
  final bool isRegistered;
  final bool isAdmin;
  final String minAppVersion;
  final String? winner;
  final String? winnerLabel;

  /// Chỉ admin của ván thử mới có, dùng cho lệnh advance.
  final String? taskKey;

  /// Lần Start gần nhất bị trả về registering, kèm lý do.
  final GameStartError? startError;
}

class GamePhase {
  const GamePhase({
    required this.key,
    required this.label,
    required this.deadline,
    required this.state,
  });

  factory GamePhase.fromJson(Map<String, dynamic> json) {
    return GamePhase(
      key: _string(json['key']),
      label: _string(json['label']),
      deadline: _date(json['deadline']),
      state: _string(json['state']),
    );
  }

  final String key;
  final String label;
  final DateTime? deadline;

  /// open | closing. closing là đã qua hạn, đang chờ bước chốt chạy.
  final String state;

  bool get isClosing => state == 'closing';
}

class GamePlayer {
  const GamePlayer({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.alive,
    required this.revealedRoleLabel,
    required this.revealedCardUrl,
    required this.deathRound,
    required this.onTrial,
    required this.lastKm,
    required this.fake,
  });

  factory GamePlayer.fromJson(Map<String, dynamic> json) {
    final deathRound = _int(json['deathRound']);
    return GamePlayer(
      uid: _string(json['uid']),
      name: _string(json['name']),
      avatarUrl: _optString(json['avatarUrl']),
      alive: json['alive'] == true,
      revealedRoleLabel: _optString(json['revealedRoleLabel']),
      revealedCardUrl: _optString(json['revealedCardUrl']),
      deathRound: deathRound == 0 ? null : deathRound,
      onTrial: json['onTrial'] == true,
      lastKm: (json['lastKm'] as num?)?.toDouble(),
      fake: json['fake'] == true,
    );
  }

  final String uid;
  final String name;
  final String? avatarUrl;
  final bool alive;
  final String? revealedRoleLabel;
  final String? revealedCardUrl;
  final int? deathRound;
  final bool onTrial;

  /// Km của vòng gần nhất; null là chưa có số, khác với 0 km.
  final double? lastKm;
  final bool fake;
}

class GameRequirement {
  const GameRequirement({
    required this.key,
    required this.ok,
    required this.label,
    required this.action,
  });

  factory GameRequirement.fromJson(Map<String, dynamic> json) {
    return GameRequirement(
      key: _string(json['key']),
      ok: json['ok'] == true,
      label: _string(json['label']),
      action: _obj(json['action'], RequirementAction.fromJson),
    );
  }

  /// telegram_linked | in_psc | app_version
  final String key;
  final bool ok;
  final String label;
  final RequirementAction? action;
}

class RequirementAction {
  const RequirementAction({required this.type, required this.url});

  factory RequirementAction.fromJson(Map<String, dynamic> json) {
    return RequirementAction(
      type: _string(json['type']),
      url: _optString(json['url']),
    );
  }

  /// link_telegram | open_url | update_app
  final String type;
  final String? url;
}

class GameStartError {
  const GameStartError({
    required this.code,
    required this.message,
    required this.at,
  });

  factory GameStartError.fromJson(Map<String, dynamic> json) {
    return GameStartError(
      code: _string(json['code']),
      message: _string(json['message']),
      at: _date(json['at']),
    );
  }

  final String code;
  final String message;
  final DateTime? at;
}

class GameFeed {
  const GameFeed({required this.items, required this.cursor});

  factory GameFeed.fromJson(Map<String, dynamic> json) {
    return GameFeed(
      items: _list(json['items'], GameFeedItem.fromJson),
      cursor: _optString(json['cursor']),
    );
  }

  final List<GameFeedItem> items;

  /// Có khi còn trang cũ hơn; null là đã hết.
  final String? cursor;
}

class GameFeedItem {
  const GameFeedItem({
    required this.seq,
    required this.at,
    required this.title,
    required this.lines,
  });

  factory GameFeedItem.fromJson(Map<String, dynamic> json) {
    return GameFeedItem(
      seq: _int(json['seq']),
      at: _date(json['at']),
      title: _string(json['title']),
      lines: _strings(json['lines']),
    );
  }

  final int seq;
  final DateTime? at;
  final String title;
  final List<String> lines;
}

/// Phần riêng của người đang xem: vai, bình thuốc, ghi chú, hành động.
class GameMe {
  const GameMe({
    required this.status,
    required this.role,
    required this.roleLabel,
    required this.roleRules,
    required this.cardUrl,
    required this.cardBackUrl,
    required this.alive,
    required this.potions,
    required this.notes,
    required this.inviteLinks,
    required this.chats,
    required this.actions,
    required this.allRoles,
  });

  factory GameMe.fromJson(Map<String, dynamic> json) {
    return GameMe(
      status: _string(json['status']),
      role: _optString(json['role']),
      roleLabel: _optString(json['roleLabel']),
      roleRules: _optString(json['roleRules']),
      cardUrl: _optString(json['cardUrl']),
      cardBackUrl: _optString(json['cardBackUrl']),
      alive: json['alive'] == true,
      potions: _obj(json['potions'], GamePotions.fromJson),
      notes: _list(json['notes'], GameNote.fromJson),
      inviteLinks: _list(json['inviteLinks'], GameInvite.fromJson),
      chats: _list(json['chats'], GameChatLink.fromJson),
      actions: _list(json['actions'], GameAction.fromJson),
      allRoles: _list(json['allRoles'], GameRoleReveal.fromJson),
    );
  }

  final String status;

  /// null khi chưa chia vai.
  final String? role;
  final String? roleLabel;
  final String? roleRules;
  final String? cardUrl;
  final String? cardBackUrl;
  final bool alive;

  /// Chỉ phù thuỷ mới có; true là bình đó còn dùng được.
  final GamePotions? potions;
  final List<GameNote> notes;
  final List<GameInvite> inviteLinks;

  /// Chat phe người xem vào được (Phe Sói, Cặp đôi). Backend quyết có chat
  /// nào, app chỉ vẽ lối vào theo list này.
  final List<GameChatLink> chats;
  final List<GameAction> actions;

  /// Vai của cả ván, chỉ có sau khi ván kết thúc.
  final List<GameRoleReveal> allRoles;
}

class GamePotions {
  const GamePotions({required this.save, required this.poison});

  factory GamePotions.fromJson(Map<String, dynamic> json) {
    return GamePotions(
      save: json['save'] == true,
      poison: json['poison'] == true,
    );
  }

  final bool save;
  final bool poison;
}

class GameNote {
  const GameNote({required this.round, required this.text});

  factory GameNote.fromJson(Map<String, dynamic> json) {
    return GameNote(round: _int(json['round']), text: _string(json['text']));
  }

  final int round;
  final String text;
}

class GameInvite {
  const GameInvite({required this.label, required this.url});

  factory GameInvite.fromJson(Map<String, dynamic> json) {
    return GameInvite(label: _string(json['label']), url: _string(json['url']));
  }

  final String label;
  final String url;
}

class GameChatLink {
  const GameChatLink({
    required this.key,
    required this.label,
    required this.canSend,
  });

  factory GameChatLink.fromJson(Map<String, dynamic> json) {
    return GameChatLink(
      key: _string(json['key']),
      label: _string(json['label']),
      canSend: json['canSend'] == true,
    );
  }

  final String key;
  final String label;
  final bool canSend;
}

/// Một trang của chat phe, tin mới trước.
class GameChat {
  const GameChat({
    required this.key,
    required this.label,
    required this.canSend,
    required this.messages,
    required this.cursor,
  });

  factory GameChat.fromJson(Map<String, dynamic> json) {
    return GameChat(
      key: _string(json['key']),
      label: _string(json['label']),
      canSend: json['canSend'] == true,
      messages: _list(json['messages'], GameChatMessage.fromJson),
      cursor: _optString(json['cursor']),
    );
  }

  final String key;
  final String label;

  /// false khi người xem đã chết hoặc ván đã hết: chỉ đọc.
  final bool canSend;
  final List<GameChatMessage> messages;

  /// Có khi còn tin cũ hơn; null là đã hết.
  final String? cursor;
}

class GameChatMessage {
  const GameChatMessage({
    required this.seq,
    required this.uid,
    required this.name,
    required this.text,
    required this.system,
    required this.at,
  });

  factory GameChatMessage.fromJson(Map<String, dynamic> json) {
    return GameChatMessage(
      seq: _int(json['seq']),
      uid: _string(json['uid']),
      name: _string(json['name']),
      text: _string(json['text']),
      system: json['system'] == true,
      at: _date(json['at']),
    );
  }

  final int seq;
  final String uid;
  final String name;
  final String text;

  /// Tin bot ghi (vd. một sói vừa chọn cắn), không phải người chơi gõ.
  final bool system;
  final DateTime? at;
}

/// Một việc người chơi làm được lúc này. App vẽ theo [input] và [options],
/// không dựa vào [kind], để backend thêm kind mới mà app không phải sửa.
class GameAction {
  const GameAction({
    required this.kind,
    required this.label,
    required this.help,
    required this.input,
    required this.options,
    required this.selected,
    required this.opensAt,
    required this.closesAt,
    required this.enabled,
    required this.disabledReason,
    required this.confirmText,
  });

  factory GameAction.fromJson(Map<String, dynamic> json) {
    return GameAction(
      kind: _string(json['kind']),
      label: _string(json['label']),
      help: _string(json['help']),
      input: _string(json['input']),
      options: _list(json['options'], GameOption.fromJson),
      selected: _obj(json['selected'], GameSelected.fromJson),
      opensAt: _date(json['opensAt']),
      closesAt: _date(json['closesAt']),
      enabled: json['enabled'] == true,
      disabledReason: _optString(json['disabledReason']),
      confirmText: _optString(json['confirmText']),
    );
  }

  final String kind;
  final String label;
  final String help;

  /// single_target | two_targets | confirm | choice
  final String input;
  final List<GameOption> options;

  /// Lựa chọn đang lưu, null là chưa chọn.
  final GameSelected? selected;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final bool enabled;
  final String? disabledReason;

  /// Có thì hỏi lại người chơi trước khi gửi.
  final String? confirmText;
}

class GameOption {
  const GameOption({
    required this.id,
    required this.label,
    required this.avatarUrl,
  });

  factory GameOption.fromJson(Map<String, dynamic> json) {
    return GameOption(
      id: _string(json['id']),
      label: _string(json['label']),
      avatarUrl: _optString(json['avatarUrl']),
    );
  }

  final String id;
  final String label;
  final String? avatarUrl;
}

class GameSelected {
  const GameSelected({required this.targets, required this.choice});

  factory GameSelected.fromJson(Map<String, dynamic> json) {
    return GameSelected(
      targets: _strings(json['targets']),
      choice: _optString(json['choice']),
    );
  }

  final List<String> targets;
  final String? choice;
}

class GameRoleReveal {
  const GameRoleReveal({
    required this.uid,
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.cardUrl,
  });

  factory GameRoleReveal.fromJson(Map<String, dynamic> json) {
    return GameRoleReveal(
      uid: _string(json['uid']),
      name: _string(json['name']),
      role: _string(json['role']),
      roleLabel: _string(json['roleLabel']),
      cardUrl: _optString(json['cardUrl']),
    );
  }

  final String uid;
  final String name;
  final String role;
  final String roleLabel;
  final String? cardUrl;
}

class GameRegistration {
  const GameRegistration({
    required this.isRegistered,
    required this.playerCount,
  });

  factory GameRegistration.fromJson(Map<String, dynamic> json) {
    return GameRegistration(
      isRegistered: json['isRegistered'] == true,
      playerCount: _int(json['playerCount']),
    );
  }

  final bool isRegistered;
  final int playerCount;
}

/// Kết quả Start với dryRun: ai sẽ vào ván, ai bị loại và vì sao.
class GameStartPreview {
  const GameStartPreview({
    required this.willExclude,
    required this.players,
    required this.count,
    required this.minPlayers,
    required this.maxPlayers,
    required this.canStart,
    required this.balanceScore,
  });

  factory GameStartPreview.fromJson(Map<String, dynamic> json) {
    return GameStartPreview(
      willExclude: _list(json['willExclude'], GameStartExcluded.fromJson),
      players: _list(json['players'], GameStartPlayer.fromJson),
      count: _int(json['count']),
      minPlayers: _int(json['minPlayers']),
      maxPlayers: _int(json['maxPlayers']),
      canStart: json['canStart'] == true,
      balanceScore: (json['balanceScore'] as num?)?.toInt(),
    );
  }

  final List<GameStartExcluded> willExclude;
  final List<GameStartPlayer> players;
  final int count;
  final int minPlayers;
  final int maxPlayers;
  final bool canStart;
  final int? balanceScore;
}

class GameStartExcluded {
  const GameStartExcluded({
    required this.uid,
    required this.name,
    required this.reason,
    required this.reasonLabel,
  });

  factory GameStartExcluded.fromJson(Map<String, dynamic> json) {
    return GameStartExcluded(
      uid: _string(json['uid']),
      name: _string(json['name']),
      reason: _string(json['reason']),
      reasonLabel: _string(json['reasonLabel']),
    );
  }

  final String uid;
  final String name;
  final String reason;
  final String reasonLabel;
}

class GameStartPlayer {
  const GameStartPlayer({
    required this.uid,
    required this.name,
    required this.tgUsername,
    required this.fake,
  });

  factory GameStartPlayer.fromJson(Map<String, dynamic> json) {
    return GameStartPlayer(
      uid: _string(json['uid']),
      name: _string(json['name']),
      tgUsername: _optString(json['tgUsername']),
      fake: json['fake'] == true,
    );
  }

  final String uid;
  final String name;
  final String? tgUsername;
  final bool fake;
}

class TelegramLinkCode {
  const TelegramLinkCode({
    required this.code,
    required this.deepLink,
    required this.expiresAt,
  });

  factory TelegramLinkCode.fromJson(Map<String, dynamic> json) {
    return TelegramLinkCode(
      code: _string(json['code']),
      deepLink: _string(json['deepLink']),
      expiresAt: _date(json['expiresAt']),
    );
  }

  final String code;

  /// `t.me/<bot>?start=<mã>`
  final String deepLink;
  final DateTime? expiresAt;
}

class TelegramLinkStatus {
  const TelegramLinkStatus({
    required this.linked,
    required this.tgUsername,
    required this.displayName,
    required this.inPsc,
  });

  factory TelegramLinkStatus.fromJson(Map<String, dynamic> json) {
    return TelegramLinkStatus(
      linked: json['linked'] == true,
      tgUsername: _optString(json['tgUsername']),
      displayName: _optString(json['displayName']),
      inPsc: json['inPsc'] == true,
    );
  }

  final bool linked;

  /// Backend trả chuỗi rỗng khi chưa liên kết; ở đây đọc thành null.
  final String? tgUsername;
  final String? displayName;
  final bool inPsc;
}

// null hay vắng mặt thì về giá trị rỗng. Có mặt mà sai kiểu là backend lệch
// hợp đồng, nên để cast ném lỗi chứ không đổi thành rỗng.

Map<String, dynamic> _map(Object? value) =>
    value as Map<String, dynamic>? ?? const {};

T? _obj<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    value == null ? null : fromJson(value as Map<String, dynamic>);

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) fromJson) => [
  for (final item in value as List? ?? const [])
    fromJson(item as Map<String, dynamic>),
];

List<String> _strings(Object? value) => [
  for (final item in value as List? ?? const []) item as String,
];

String _string(Object? value) => value as String? ?? '';

/// Chuỗi rỗng cũng là null, vì Go `omitempty` bỏ chuỗi rỗng còn vài field
/// (tgUsername) lại trả chuỗi rỗng thay cho "không có".
String? _optString(Object? value) {
  final s = value as String?;
  return s == null || s.isEmpty ? null : s;
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

/// Giờ RFC3339 của Go. Zero time của Go (năm 1) nghĩa là "chưa có", đọc
/// thành null để không ai đếm ngược tới năm 1.
DateTime? _date(Object? value) {
  final s = value as String?;
  if (s == null || s.isEmpty) return null;
  final parsed = DateTime.parse(s);
  return parsed.year <= 1 ? null : parsed;
}
