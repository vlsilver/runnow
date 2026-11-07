// DTO của API Ma Sói (/v1/games*, /v1/telegram/link*), bám theo struct JSON ở
// backend/internal/backend/game_api.go, game_start.go, telegram_link.go.
//
// Các field liệt kê như status, phase.state, action.input, action.kind giữ
// dạng String chứ không đổi sang enum: backend thêm giá trị mới thì app cũ
// vẫn parse được và vẽ theo label backend gửi.
//
// Go encode slice nil thành null, nên mọi list đọc null thành rỗng. Field
// `omitempty` vắng mặt thì đọc thành null (chuỗi) hoặc false/0.

import 'dart:math' as math;

class GameList {
  const GameList({
    required this.canCreate,
    required this.roleOptions,
    this.settings = const [],
    this.groups = const [],
    this.presets = const [],
    this.round,
    this.deck,
    required this.items,
  });

  factory GameList.fromJson(Map<String, dynamic> json) {
    final viewer = _map(json['viewer']);
    final createOptions = _map(json['createOptions']);
    return GameList(
      canCreate: viewer['canCreate'] == true,
      roleOptions: _list(createOptions['roles'], GameRoleOption.fromJson),
      settings: _list(createOptions['settings'], GameSetting.fromJson),
      groups: _list(createOptions['groups'], GameSettingGroup.fromJson),
      presets: _list(createOptions['presets'], GamePreset.fromJson),
      round: createOptions['round'] is Map<String, dynamic>
          ? GameRoundPlan.fromJson(createOptions['round'])
          : null,
      deck: createOptions['deck'] is Map<String, dynamic>
          ? GameDeckPlan.fromJson(createOptions['deck'])
          : null,
      items: _list(json['items'], GameListItem.fromJson),
    );
  }

  final bool canCreate;
  final List<GameRoleOption> roleOptions;

  /// Tuỳ chọn luật của màn tạo ván, theo thứ tự backend gửi.
  final List<GameSetting> settings;

  /// Tab của màn tạo ván. Backend cũ không gửi thì màn tạo ván vẽ danh sách
  /// tuỳ chọn như trước.
  final List<GameSettingGroup> groups;

  /// Kiểu ván dựng sẵn, theo thứ tự backend gửi.
  final List<GamePreset> presets;

  /// Diễn biến một vòng cho tab Vòng chơi.
  final GameRoundPlan? round;

  /// Bộ bài theo số người cho tab Vai; backend cũ không gửi.
  final GameDeckPlan? deck;
  final List<GameListItem> items;
}

/// Một tab trên màn tạo ván (`createOptions.groups`). [offNote] hiện thay cho
/// các tuỳ chọn của tab khi không tuỳ chọn nào đang có tác dụng.
class GameSettingGroup {
  const GameSettingGroup({
    required this.key,
    required this.label,
    required this.icon,
    this.offNote,
  });

  factory GameSettingGroup.fromJson(Map<String, dynamic> json) {
    return GameSettingGroup(
      key: _string(json['key']),
      label: _string(json['label']),
      icon: _string(json['icon']),
      offNote: _optString(json['offNote']),
    );
  }

  final String key;
  final String label;
  final String icon;
  final String? offNote;
}

/// Kiểu ván dựng sẵn (`createOptions.presets`): chọn kiểu thì [roles] và
/// [settings] thành giá trị của form, key vắng thì theo mặc định.
class GamePreset {
  const GamePreset({
    required this.key,
    required this.label,
    required this.icon,
    required this.summary,
    this.details = const [],
    this.isDefault = false,
    this.roles = const {},
    this.settings = const {},
  });

  factory GamePreset.fromJson(Map<String, dynamic> json) {
    return GamePreset(
      key: _string(json['key']),
      label: _string(json['label']),
      icon: _string(json['icon']),
      summary: _string(json['summary']),
      details: _strings(json['details']),
      isDefault: json['default'] == true,
      roles: {
        for (final e in _map(json['roles']).entries)
          if (e.value is bool) e.key: e.value as bool,
      },
      settings: {
        for (final e in _map(json['settings']).entries)
          if (e.value != null) e.key: e.value as Object,
      },
    );
  }

  final String key;
  final String label;
  final String icon;
  final String summary;
  final List<String> details;
  final bool isDefault;
  final Map<String, bool> roles;
  final Map<String, Object> settings;
}

/// Diễn biến một vòng. Giờ tính từ lúc mở đêm theo vòng gốc 24 tiếng; vòng
/// ngắn hơn thì co theo tỉ lệ.
/// Bộ bài của tab Vai (`createOptions.deck`). Theo số người: bot chia theo
/// [tiers] lúc đủ người. Tự chỉnh: tuỳ chọn [wolvesKey] khác 0 là số sói,
/// vai đặc biệt nào đang bật thì có đủ, Dân bù chỗ còn lại.
class GameDeckPlan {
  const GameDeckPlan({
    this.note = '',
    this.fixedNote = '',
    this.wolvesKey = '',
    this.preview = 12,
    this.tiers = const [],
  });

  factory GameDeckPlan.fromJson(Map<String, dynamic> json) => GameDeckPlan(
    note: _string(json['note']),
    fixedNote: _string(json['fixedNote']),
    wolvesKey: _string(json['wolvesKey']),
    preview: (json['preview'] as num? ?? 12).toInt(),
    tiers: [
      for (final t in json['tiers'] as List? ?? const [])
        if (t is Map<String, dynamic>)
          (
            from: (t['from'] as num? ?? 0).toInt(),
            to: (t['to'] as num? ?? 0).toInt(),
            wolves: (t['wolves'] as num? ?? 0).toInt(),
            specials: (t['specials'] as num? ?? 0).toInt(),
          ),
    ],
  );

  final String note;
  final String fixedNote;
  final String wolvesKey;
  final int preview;
  final List<({int from, int to, int wolves, int specials})> tiers;

  int get minPlayers => tiers.isEmpty ? preview : tiers.first.from;
  int get maxPlayers => tiers.isEmpty ? preview : tiers.last.to;

  ({int from, int to, int wolves, int specials})? tierOf(int n) =>
      tiers.where((t) => n >= t.from && n <= t.to).firstOrNull;

  /// Số lá từng vai khi chia cho [n] người, như werewolf.Composition: sói
  /// không quá 1/3 số người; theo số người thì chỉ [specials] đầu theo bảng,
  /// [wolves] khác 0 là tự chỉnh; vai tắt thành Dân; mỗi vai [extended] một lá
  /// thay một Dân. Có cả `wolf` và `villager`.
  Map<String, int> counts({
    required int n,
    required List<String> specials,
    required bool Function(String role) on,
    List<String> extended = const [],
    int wolves = 0,
    int extraWolves = 0,
  }) {
    final tier = tierOf(n);
    final fixed = wolves > 0;
    final w = math.min(
      fixed ? wolves : (tier?.wolves ?? 0) + extraWolves,
      n ~/ 3,
    );
    final first = fixed ? specials.length : (tier?.specials ?? 0);
    final out = <String, int>{'wolf': w};
    for (var i = 0; i < specials.length; i++) {
      out[specials[i]] = i < first && on(specials[i]) ? 1 : 0;
    }
    for (final r in extended) {
      out[r] = 1;
    }
    out['villager'] = n - out.values.fold(0, (a, b) => a + b);
    return out;
  }
}

class GameRoundPlan {
  const GameRoundPlan({
    this.phases = const [],
    this.reminders = const [],
    this.start = '',
  });

  factory GameRoundPlan.fromJson(Map<String, dynamic> json) {
    return GameRoundPlan(
      phases: _list(json['phases'], GameRoundPhase.fromJson),
      reminders: [
        for (final m in json['reminders'] as List? ?? const [])
          if (m is Map<String, dynamic>)
            (label: _string(m['label']), at: (m['at'] as num? ?? 0).toDouble()),
      ],
      start: _string(json['start']),
    );
  }

  final List<GameRoundPhase> phases;
  final List<({String label, double at})> reminders;
  final String start;
}

class GameRoundPhase {
  const GameRoundPhase({
    required this.key,
    required this.label,
    required this.description,
    required this.from,
    required this.to,
    this.settingKey,
  });

  factory GameRoundPhase.fromJson(Map<String, dynamic> json) {
    return GameRoundPhase(
      key: _string(json['key']),
      label: _string(json['label']),
      description: _string(json['description']),
      from: (json['from'] as num? ?? 0).toDouble(),
      to: (json['to'] as num? ?? 0).toDouble(),
      settingKey: _optString(json['settingKey']),
    );
  }

  final String key;
  final String label;
  final String description;
  final double from;
  final double to;

  /// Key của tuỳ chọn kiểu [GameSetting.phase] giữ độ dài pha này (phút);
  /// null là backend cũ, pha không chỉnh được.
  final String? settingKey;
}

class GameRoleOption {
  const GameRoleOption({
    required this.key,
    required this.label,
    required this.defaultOn,
    this.description = '',
  });

  factory GameRoleOption.fromJson(Map<String, dynamic> json) {
    return GameRoleOption(
      key: _string(json['key']),
      label: _string(json['label']),
      defaultOn: json['default'] == true,
      description: _string(json['description']),
    );
  }

  final String key;
  final String label;
  final bool defaultOn;
  final String description;
}

/// Một tuỳ chọn trên màn tạo ván (`createOptions.settings`). App vẽ theo
/// [type] và hiện [label], [description]; backend thêm tuỳ chọn thì app không
/// phải sửa. [type] lạ thì app bỏ qua, backend tự áp giá trị mặc định.
class GameSetting {
  const GameSetting({
    required this.key,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.choices = const [],
    this.enabledIf = const [],
    this.group,
    this.section,
    this.hint,
    this.warn,
    this.role,
    this.icon,
    this.parent,
  });

  factory GameSetting.fromJson(Map<String, dynamic> json) {
    return GameSetting(
      key: _string(json['key']),
      label: _string(json['label']),
      description: _string(json['description']),
      type: _string(json['type']),
      defaultValue: json['default'],
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      step: (json['step'] as num?)?.toDouble(),
      unit: _optString(json['unit']),
      choices: _list(json['choices'], GameSettingChoice.fromJson),
      enabledIf: [
        for (final c in json['enabledIf'] as List? ?? const [])
          (
            key: _string((c as Map<String, dynamic>)['key']),
            equals: c['equals'],
          ),
      ],
      group: _optString(json['group']),
      section: _optString(json['section']),
      hint: _optString(json['hint']),
      warn: _optString(json['warn']),
      role: _optString(json['role']),
      icon: _optString(json['icon']),
      parent: _optString(json['parent']),
    );
  }

  static const toggle = 'toggle';
  static const number = 'number';
  static const choice = 'choice';

  /// Như [number], độ dài một pha (phút); vẽ chung bốn pha thành vòng đồng hồ.
  static const phase = 'phase';

  final String key;
  final String label;
  final String description;
  final String type;

  /// bool với toggle, num với number, String với choice.
  final Object? defaultValue;
  final double? min;
  final double? max;
  final double? step;
  final String? unit;
  final List<GameSettingChoice> choices;

  /// Tuỳ chọn chỉ có tác dụng khi mọi điều kiện đúng với giá trị hiện tại.
  final List<({String key, Object? equals})> enabledIf;

  /// Key của tab chứa tuỳ chọn ([GameSettingGroup]); null thì màn tạo ván
  /// theo tab không hiện, giá trị theo kiểu ván.
  final String? group;

  /// Tên khối trong tab; các tuỳ chọn cùng khối vẽ chung, ô bật tắt thành thẻ
  /// thu gọn. null thì vẽ như thường.
  final String? section;

  /// Nhãn ngắn trên thẻ hoặc dưới tên, ví dụ số lượt.
  final String? hint;

  /// Cái giá người tạo ván cần cân, hiện khi mở thẻ.
  final String? warn;

  /// Vai mà tuỳ chọn này chỉnh; có thì chỉ hiện khi bộ bài có vai đó.
  final String? role;

  /// Có thì vẽ thành thẻ kỹ năng với icon này.
  final String? icon;

  /// Key của thẻ chứa tuỳ chọn này: vẽ thành dòng con trong thẻ đó.
  final String? parent;

  /// [values] là giá trị hiện tại theo key, đã gồm mặc định.
  bool enabledBy(Map<String, Object?> values) =>
      enabledIf.every((c) => values[c.key] == c.equals);
}

class GameSettingChoice {
  const GameSettingChoice({
    required this.value,
    required this.label,
    required this.description,
    this.hint,
    this.details = const [],
  });

  factory GameSettingChoice.fromJson(Map<String, dynamic> json) {
    return GameSettingChoice(
      value: _string(json['value']),
      label: _string(json['label']),
      description: _string(json['description']),
      hint: _optString(json['hint']),
      details: _list(json['details'], GameSettingDetail.fromJson),
    );
  }

  final String value;
  final String label;
  final String description;

  /// Một dòng ngắn dưới tên lựa chọn.
  final String? hint;

  /// Các mục giải thích hiện khi bấm "Chi tiết".
  final List<GameSettingDetail> details;
}

class GameSettingDetail {
  const GameSettingDetail({
    required this.icon,
    required this.title,
    required this.text,
  });

  factory GameSettingDetail.fromJson(Map<String, dynamic> json) {
    return GameSettingDetail(
      icon: _string(json['icon']),
      title: _string(json['title']),
      text: _string(json['text']),
    );
  }

  /// Tên biểu tượng do backend chọn; app không biết tên thì vẽ chấm.
  final String icon;
  final String title;
  final String text;
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

  bool get ended => status == 'ended';
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
    this.kmTable,
    this.setup = const [],
    this.room,
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
      kmTable: _obj(json['kmTable'], GameKmTable.fromJson),
      setup: _list(json['setup'], GameSetupSection.fromJson),
      room: _obj(json['room'], GameChatLink.fromJson),
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

  /// Đầu cột bảng km hai cột (`lastKm`, `todayKm` của người chơi); null khi
  /// ván không chạy, lúc đó app hiện km chốt như cũ.
  final GameKmTable? kmTable;

  /// Thiết lập ván đang áp, theo khối của màn tạo ván; rỗng khi backend cũ.
  final List<GameSetupSection> setup;

  /// Phòng chung của ván; null khi chưa đăng ký hay backend cũ.
  final GameChatLink? room;

  /// Ván đòi liên kết Telegram để đăng ký. Backend chưa gửi điều kiện thì
  /// coi như có, như trước giờ.
  bool get needsTelegram =>
      requirements.isEmpty ||
      requirements.any((r) => r.key == 'telegram_linked');
}

class GameKmTable {
  const GameKmTable({
    required this.lastLabel,
    required this.todayLabel,
    required this.asOf,
    required this.unitKm,
    required this.note,
    this.unitLabel,
    this.cutLabel,
  });

  factory GameKmTable.fromJson(Map<String, dynamic> json) {
    return GameKmTable(
      lastLabel: _string(json['lastLabel']),
      todayLabel: _string(json['todayLabel']),
      asOf: _date(json['asOf']),
      unitKm: (json['unitKm'] as num?)?.toDouble() ?? 1,
      note: _string(json['note']),
      unitLabel: _optString(json['unitLabel']),
      cutLabel: _optString(json['cutLabel']),
    );
  }

  /// Chữ đầu cột do server ghi, phần sau " · " xuống dòng.
  final String lastLabel;
  final String todayLabel;

  /// Lúc server tính `todayKm`; null ở ván thử.
  final DateTime? asOf;

  /// Mốc km cho một kỹ năng đêm hay một phiếu.
  final double unitKm;
  final String note;

  /// Việc mốc [unitKm] quyết với phiếu ("giữ phiếu"); null khi km không đụng
  /// tới phiếu.
  final String? unitLabel;

  /// Chữ của đường cắt ở mốc [unitKm]; null là luật phiếu không có ai mất
  /// phiếu, nên danh sách không vẽ đường cắt.
  final String? cutLabel;
}

/// Km của cả phe khi luật tính theo phe (phe Sói cắn), chỉ có trong `/me`.
class GameTeamKm {
  const GameTeamKm({
    required this.label,
    required this.last,
    required this.today,
    required this.need,
    required this.needLabel,
  });

  factory GameTeamKm.fromJson(Map<String, dynamic> json) {
    return GameTeamKm(
      label: _string(json['label']),
      last: (json['last'] as num?)?.toDouble() ?? 0,
      today: (json['today'] as num?)?.toDouble(),
      need: (json['need'] as num?)?.toDouble() ?? 0,
      needLabel: _string(json['needLabel']),
    );
  }

  final String label;
  final double last;

  /// null ở ván thử.
  final double? today;
  final double need;
  final String needLabel;
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
    this.todayKm,
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
      todayKm: (json['todayKm'] as num?)?.toDouble(),
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

  /// Km đang gom tới mốc 22h kế tiếp; null với người đã chết hay ván thử.
  final double? todayKm;
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
    this.entries = const [],
    this.night = false,
  });

  factory GameFeedItem.fromJson(Map<String, dynamic> json) {
    return GameFeedItem(
      seq: _int(json['seq']),
      at: _date(json['at']),
      title: _string(json['title']),
      lines: _strings(json['lines']),
      entries: _list(json['entries'], GameLine.fromJson),
      night: json['night'] == true,
    );
  }

  final int seq;
  final DateTime? at;
  final String title;
  final List<String> lines;

  /// [lines] kèm icon và tag, cùng câu, cùng thứ tự. Backend cũ không gửi
  /// thì rỗng, app vẽ [lines].
  final List<GameLine> entries;

  /// Mục thuộc pha đêm.
  final bool night;
}

/// Một câu có icon và tag ngắn, dùng ở nhật ký và diễn lại của tổng kết.
/// Icon là khoá (bite, guard, seer, death, vote, pick, peace…); khoá lạ thì
/// app vẽ chấm.
class GameLine {
  const GameLine({required this.icon, required this.text, this.tag});

  factory GameLine.fromJson(Map<String, dynamic> json) {
    return GameLine(
      icon: _string(json['icon']),
      text: _string(json['text']),
      tag: _optString(json['tag']),
    );
  }

  final String icon;
  final String text;
  final String? tag;
}

/// Một mốc km người xem đang nhắm tới (`me.kmGoals`): giữ phiếu, kỹ năng đêm.
class GameKmGoal {
  const GameKmGoal({
    required this.key,
    required this.label,
    required this.needKm,
    this.haveKm,
  });

  factory GameKmGoal.fromJson(Map<String, dynamic> json) {
    return GameKmGoal(
      key: _string(json['key']),
      label: _string(json['label']),
      needKm: (json['needKm'] as num?)?.toDouble() ?? 0,
      haveKm: (json['haveKm'] as num?)?.toDouble(),
    );
  }

  /// vote, vote_top, skill, team_skill.
  final String key;
  final String label;
  final double needKm;

  /// Km đang gom; null ở ván thử.
  final double? haveKm;

  /// Mốc của vai (kỹ năng đêm, km phe Sói) lộ vai nên chỉ hiện khi lá ngửa.
  /// Chỉ mốc phiếu là của mọi người; khoá lạ coi như kín để không lộ vai.
  bool get secret => key != 'vote' && key != 'vote_top';
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
    this.teamKm,
    this.kmGoals = const [],
    this.cardTier,
    this.cardVariant,
    this.cardOwned = false,
    this.cardRounds = 0,
    this.summary,
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
      teamKm: _obj(json['teamKm'], GameTeamKm.fromJson),
      kmGoals: _list(json['kmGoals'], GameKmGoal.fromJson),
      cardTier: _optString(json['cardTier']),
      cardVariant: _optString(json['cardVariant']),
      cardOwned: json['cardOwned'] == true,
      cardRounds: _int(json['cardRounds']),
      summary: _obj(json['summary'], GameSummary.fromJson),
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

  /// Km của phe, chỉ sói còn sống mới có.
  final GameTeamKm? teamKm;

  /// Mốc km người xem còn sống đang nhắm tới; ván tắt km thì rỗng.
  final List<GameKmGoal> kmGoals;

  /// Khoá bậc thẻ Ma Sói (common … mythic), có từ lúc chia bài. Backend cũ
  /// không gửi thì null.
  final String? cardTier;

  /// Bản thẻ, như "secret.fire" cho thẻ Ẩn; thẻ thường thì null.
  final String? cardVariant;

  /// Ván đã kết thúc và người xem ở phe thắng: thẻ đã nằm trong
  /// users/{uid}/gameCards, được khoe.
  final bool cardOwned;

  /// Số vòng ván đã đi, chỉ có khi ván đã kết thúc (lúc đó không còn phase).
  final int cardRounds;

  /// Tổng kết ván, có cùng lúc với [allRoles]. Backend cũ không gửi thì null.
  final GameSummary? summary;
}

/// Tổng kết ván đã xong: số liệu, danh hiệu, lật bài theo phe, diễn lại.
class GameSummary {
  const GameSummary({
    required this.winner,
    required this.winnerLabel,
    required this.stats,
    required this.titles,
    required this.teams,
    required this.replay,
  });

  factory GameSummary.fromJson(Map<String, dynamic> json) {
    return GameSummary(
      winner: _string(json['winner']),
      winnerLabel: _string(json['winnerLabel']),
      stats: _list(json['stats'], GameSummaryStat.fromJson),
      titles: _list(json['titles'], GameSummaryTitle.fromJson),
      teams: _list(json['teams'], GameSummaryTeam.fromJson),
      replay: _list(json['replay'], GameSummarySection.fromJson),
    );
  }

  final String winner;
  final String winnerLabel;
  final List<GameSummaryStat> stats;

  /// Chỉ có danh hiệu nào có người đạt.
  final List<GameSummaryTitle> titles;

  /// Phe thắng đứng đầu.
  final List<GameSummaryTeam> teams;

  /// Từng đêm, từng ngày theo thứ tự xảy ra.
  final List<GameSummarySection> replay;
}

class GameSummaryStat {
  const GameSummaryStat({required this.label, required this.value});

  factory GameSummaryStat.fromJson(Map<String, dynamic> json) {
    return GameSummaryStat(
      label: _string(json['label']),
      value: _string(json['value']),
    );
  }

  final String label;
  final String value;
}

class GameSummaryTitle {
  const GameSummaryTitle({
    required this.key,
    required this.label,
    required this.name,
    required this.value,
  });

  factory GameSummaryTitle.fromJson(Map<String, dynamic> json) {
    return GameSummaryTitle(
      key: _string(json['key']),
      label: _string(json['label']),
      name: _string(json['name']),
      value: _string(json['value']),
    );
  }

  /// runner, seer, guard; khoá lạ thì app vẽ icon mặc định.
  final String key;
  final String label;

  /// Hoà thì tên nối bằng dấu phẩy.
  final String name;
  final String value;
}

class GameSummaryTeam {
  const GameSummaryTeam({
    required this.team,
    required this.label,
    required this.won,
    required this.players,
  });

  factory GameSummaryTeam.fromJson(Map<String, dynamic> json) {
    return GameSummaryTeam(
      team: _string(json['team']),
      label: _string(json['label']),
      won: json['won'] == true,
      players: _list(json['players'], GameSummaryPlayer.fromJson),
    );
  }

  final String team;
  final String label;
  final bool won;
  final List<GameSummaryPlayer> players;
}

class GameSummaryPlayer {
  const GameSummaryPlayer({
    required this.uid,
    required this.name,
    required this.roleLabel,
    required this.alive,
    required this.fate,
    this.cardUrl,
    this.causeLabel,
    this.km,
  });

  factory GameSummaryPlayer.fromJson(Map<String, dynamic> json) {
    return GameSummaryPlayer(
      uid: _string(json['uid']),
      name: _string(json['name']),
      roleLabel: _string(json['roleLabel']),
      alive: json['alive'] == true,
      fate: _string(json['fate']),
      cardUrl: _optString(json['cardUrl']),
      causeLabel: _optString(json['causeLabel']),
      km: _optString(json['km']),
    );
  }

  final String uid;
  final String name;
  final String roleLabel;
  final bool alive;

  /// "Sống" hoặc lúc chết: "Đêm 2", "Ngày 3".
  final String fate;
  final String? cardUrl;
  final String? causeLabel;

  /// Km cả ván đã định dạng; ván tắt km thì null.
  final String? km;
}

/// Một đêm hay một ngày trong phần diễn lại.
class GameSummarySection {
  const GameSummarySection({
    required this.title,
    required this.night,
    required this.lines,
  });

  factory GameSummarySection.fromJson(Map<String, dynamic> json) {
    return GameSummarySection(
      title: _string(json['title']),
      night: json['night'] == true,
      lines: _list(json['lines'], GameLine.fromJson),
    );
  }

  final String title;
  final bool night;
  final List<GameLine> lines;
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
    this.hasNewer = false,
  });

  factory GameChat.fromJson(Map<String, dynamic> json) {
    return GameChat(
      key: _string(json['key']),
      label: _string(json['label']),
      canSend: json['canSend'] == true,
      messages: _list(json['messages'], GameChatMessage.fromJson),
      cursor: _optString(json['cursor']),
      hasNewer: json['hasNewer'] == true,
    );
  }

  final String key;
  final String label;

  /// false khi người xem đã chết hoặc ván đã hết: chỉ đọc.
  final bool canSend;
  final List<GameChatMessage> messages;

  /// Có khi còn tin cũ hơn; null là đã hết.
  final String? cursor;

  /// Trang đọc bằng `after` còn tin mới hơn: đọc tiếp từ seq lớn nhất.
  final bool hasNewer;
}

class GameChatMessage {
  const GameChatMessage({
    required this.seq,
    required this.uid,
    required this.name,
    required this.text,
    required this.system,
    required this.at,
    this.hidden = false,
  });

  factory GameChatMessage.fromJson(Map<String, dynamic> json) {
    return GameChatMessage(
      seq: _int(json['seq']),
      uid: _string(json['uid']),
      name: _string(json['name']),
      text: _string(json['text']),
      system: json['system'] == true,
      at: _date(json['at']),
      hidden: json['hidden'] == true,
    );
  }

  GameChatMessage asHidden() => GameChatMessage(
    seq: seq,
    uid: uid,
    name: name,
    text: '',
    system: system,
    at: at,
    hidden: true,
  );

  final int seq;
  final String uid;
  final String name;
  final String text;

  /// Tin bot ghi (vd. một sói vừa chọn cắn), không phải người chơi gõ.
  final bool system;
  final DateTime? at;

  /// Người xem đã chặn người gửi: không vẽ.
  final bool hidden;
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
    this.tally,
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
      tally: _obj(json['tally'], GameTally.fromJson),
    );
  }

  final String kind;
  final String label;
  final String help;

  /// single_target | two_targets | confirm | choice | dark
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

  /// Bảng kiểm phiếu của đề cử, biểu quyết, sói bầu cắn; null ở ván luật cũ.
  final GameTally? tally;
}

/// Một khối của phần xem lại thiết lập ván.
class GameSetupSection {
  const GameSetupSection({required this.title, required this.items});

  factory GameSetupSection.fromJson(Map<String, dynamic> json) {
    return GameSetupSection(
      title: _string(json['title']),
      items: _list(json['items'], GameSetupItem.fromJson),
    );
  }

  final String title;
  final List<GameSetupItem> items;
}

/// Một tuỳ chọn đang áp; [value] backend viết sẵn kèm đơn vị. [sub] là dòng
/// con của dòng có icon ngay trên.
class GameSetupItem {
  const GameSetupItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub = false,
  });

  factory GameSetupItem.fromJson(Map<String, dynamic> json) {
    return GameSetupItem(
      key: _string(json['key']),
      icon: _string(json['icon']),
      label: _string(json['label']),
      value: _string(json['value']),
      sub: json['sub'] == true,
    );
  }

  final String key;
  final String icon;
  final String label;
  final String value;
  final bool sub;
}

/// Ai chọn gì, phiếu nào được tính, bên nào đang dẫn và vì sao.
class GameTally {
  const GameTally({
    required this.rows,
    required this.seats,
    this.reason,
    this.note,
  });

  factory GameTally.fromJson(Map<String, dynamic> json) {
    return GameTally(
      rows: _list(json['rows'], GameTallyRow.fromJson),
      seats: (json['seats'] as num?)?.toInt() ?? 1,
      reason: _optString(json['reason']),
      note: _optString(json['note']),
    );
  }

  final List<GameTallyRow> rows;

  /// Số lựa chọn thắng: số suất lên giàn với đề cử, 1 với còn lại.
  final int seats;

  /// Vì sao hàng [GameTallyRow.lead] dẫn; null khi chưa có phiếu.
  final String? reason;

  /// Ai mất phiếu, ai được phiếu Top.
  final String? note;
}

class GameTallyRow {
  const GameTallyRow({
    required this.id,
    required this.label,
    required this.votes,
    required this.km,
    required this.lead,
    required this.voters,
  });

  factory GameTallyRow.fromJson(Map<String, dynamic> json) {
    return GameTallyRow(
      id: _string(json['id']),
      label: _string(json['label']),
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      km: (json['km'] as num?)?.toDouble() ?? 0,
      lead: json['lead'] == true,
      voters: _list(json['voters'], GameTallyVoter.fromJson),
    );
  }

  final String id;
  final String label;
  final int votes;
  final double km;
  final bool lead;
  final List<GameTallyVoter> voters;
}

class GameTallyVoter {
  const GameTallyVoter({
    required this.name,
    required this.km,
    this.cut = false,
    this.weight = 0,
  });

  factory GameTallyVoter.fromJson(Map<String, dynamic> json) {
    return GameTallyVoter(
      name: _string(json['name']),
      km: (json['km'] as num?)?.toDouble() ?? 0,
      cut: json['cut'] == true,
      weight: (json['weight'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final double km;

  /// Phiếu không được tính.
  final bool cut;

  /// Lớn hơn 1 là phiếu Top.
  final int weight;
}

class GameOption {
  const GameOption({
    required this.id,
    required this.label,
    required this.avatarUrl,
    this.description = '',
    this.hint = '',
    this.needsTarget = false,
    this.targets = const [],
    this.disabled = false,
  });

  factory GameOption.fromJson(Map<String, dynamic> json) {
    return GameOption(
      id: _string(json['id']),
      label: _string(json['label']),
      avatarUrl: _optString(json['avatarUrl']),
      description: _string(json['description']),
      hint: _string(json['hint']),
      needsTarget: json['needsTarget'] == true,
      targets: _list(json['targets'], GameOption.fromJson),
      disabled: json['disabled'] == true,
    );
  }

  final String id;
  final String label;
  final String? avatarUrl;

  // Các field dưới chỉ có ở input "dark": mỗi option là một đặc quyền.
  final String description;

  /// Số lượt, ví dụ "Mỗi đêm".
  final String hint;

  /// Phải chọn một người trong [targets].
  final bool needsTarget;
  final List<GameOption> targets;

  /// Hết lượt hoặc không còn ai để chọn.
  final bool disabled;
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
