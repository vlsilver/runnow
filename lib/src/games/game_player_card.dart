import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart' show RunNowElement;

const _teamLabels = {
  'village': 'Phe Dân',
  'wolves': 'Phe Sói',
  'lovers': 'Cặp đôi',
};

const _winnerTitles = {
  'village': 'Dân làng thắng',
  'wolves': 'Bầy sói thắng',
  'lovers': 'Cặp đôi thắng',
};

/// Thẻ Ma Sói của một người trong một ván. Bậc bốc lúc chia bài; ván kết thúc
/// thì phe thắng giữ thẻ ở users/{uid}/gameCards/{gameId} (backend ghi), còn
/// màn ván dựng cùng thẻ từ /me để người chơi thấy thẻ mình từ đầu.
class GamePlayerCard {
  const GamePlayerCard({
    required this.gameId,
    required this.tier,
    required this.role,
    required this.team,
    required this.alive,
    required this.round,
    required this.playerCount,
    required this.owned,
    this.roleLabel,
    this.winner,
    this.deathRound,
    this.endedAt,
    this.testMode = false,
    this.secret,
  });

  /// Doc gameCards chỉ có ở người phe thắng nên luôn là thẻ đã sở hữu.
  /// Đọc từ Firestore thì provider đổi Timestamp sang DateTime trước.
  factory GamePlayerCard.fromJson(String gameId, Map<String, dynamic> json) {
    final deathRound = json['deathRound'];
    final endedAt = json['endedAt'];
    return GamePlayerCard(
      gameId: gameId,
      tier: runCardTierFromKey(json['tier'] as String?),
      role: json['role'] as String? ?? '',
      team: json['team'] as String? ?? '',
      winner: json['winner'] as String?,
      alive: json['alive'] == true,
      round: (json['rounds'] as num?)?.toInt() ?? 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      deathRound: deathRound is num ? deathRound.toInt() : null,
      endedAt: endedAt is DateTime ? endedAt : null,
      testMode: json['testMode'] == true,
      owned: true,
      secret: runCardSecretFromKey(json['variant'] as String?),
    );
  }

  /// Thẻ của người xem trong màn ván, từ /me và chi tiết ván. Thẻ đã thuộc về
  /// mình thì phe mình chính là phe thắng (cả cặp đôi phe ba); còn lại lấy
  /// phe theo vai, vì /me không nói ai đang trong cặp Sói–Dân.
  factory GamePlayerCard.fromMe({
    required GameDetail detail,
    required GameMe me,
    GamePlayer? player,
  }) {
    final ended = detail.status == 'ended';
    final role = me.role ?? '';
    return GamePlayerCard(
      gameId: detail.id,
      tier: runCardTierFromKey(me.cardTier),
      role: role,
      roleLabel: me.roleLabel,
      team: me.cardOwned && detail.winner != null
          ? detail.winner!
          : role == 'wolf'
          ? 'wolves'
          : 'village',
      winner: ended ? detail.winner : null,
      alive: me.alive,
      round: ended ? me.cardRounds : gameRoundOf(detail.phase?.key),
      playerCount: detail.playerCount,
      deathRound: player?.deathRound,
      testMode: detail.testMode,
      owned: me.cardOwned,
      secret: runCardSecretFromKey(me.cardVariant),
    );
  }

  final String gameId;
  final GameCardTier tier;

  /// Khoá vai của backend: wolf, seer, …
  final String role;

  /// Tên vai backend gửi; null thì lấy tên mặc định của app.
  final String? roleLabel;

  /// Phe lúc xét thắng thua: village, wolves, lovers.
  final String team;

  /// Phe thắng; null khi ván chưa xong.
  final String? winner;
  final bool alive;

  /// Vòng hiện tại khi ván đang chạy, số vòng đã chơi khi ván xong.
  final int round;
  final int playerCount;
  final int? deathRound;
  final DateTime? endedAt;
  final bool testMode;

  /// Hành của bản Ẩn, null là thẻ thường.
  final RunNowElement? secret;

  /// Người phe thắng, ván đã xong: được khoe và nằm trong bộ thẻ.
  final bool owned;

  bool get ended => winner != null;
  String get label => roleLabel ?? gameRoleStyle(role).label;
  String get teamLabel => _teamLabels[team] ?? gameRoleStyle(role).team;

  String get result => owned
      ? 'Thắng'
      : ended
      ? 'Thua'
      : 'Đang chơi';
  String get fate => alive
      ? (ended ? 'Sống sót' : 'Còn sống')
      : deathRound == null
      ? 'Bị loại'
      : 'Ngã vòng $deathRound';
}

/// Số vòng trong khoá phase của backend ("r3/day" là 3); khoá lạ thì 0.
int gameRoundOf(String? phaseKey) {
  final match = RegExp(r'^r(\d+)/').firstMatch(phaseKey ?? '');
  return match == null ? 0 : int.parse(match.group(1)!);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal();
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

/// Dữ liệu thẻ khuôn thẻ thành tích: mặt trước là tranh của phe và số liệu
/// ván, mặt sau chỉ có sói hú trong vầng trăng màu phe.
AchievementCardData gameCardData(GamePlayerCard card, {required String owner}) {
  final title = card.ended
      ? _winnerTitles[card.winner] ?? 'Ván đã xong'
      : 'Ván đang chơi';
  final date = _date(card.endedAt);
  return AchievementCardData(
    tier: card.tier,
    secret: card.secret,
    art: GameTeamArt(team: card.team),
    backFace: GameCardEmblem(team: card.team, tier: card.tier),
    kind: 'MA SÓI · ${card.teamLabel.toUpperCase()}',
    hero: card.label.toUpperCase(),
    heroUnit: '',
    title: '$title · ${card.playerCount} người',
    stats: [
      (value: card.result, label: 'KẾT QUẢ'),
      (value: '${card.round}', label: card.ended ? 'SỐ VÒNG' : 'VÒNG'),
      (value: card.fate, label: 'BẢN THÂN'),
    ],
    owner: owner.toUpperCase(),
    serial: '',
    desc: '',
    meta: date,
    date: date,
  );
}

/// Thẻ Ma Sói đem khoe. Chỉ thẻ đã sở hữu mới khoe được, lúc đó ván đã xong
/// nên vai không còn bí mật.
CardShareSubject gameCardShareSubject(
  GamePlayerCard card, {
  required String owner,
}) => CardShareSubject(
  id: 'masoi-${card.gameId}',
  printed: [
    // Mốc thiết kế thẻ Ma Sói: đổi khi đổi cách vẽ để file khoe cũ không dùng
    // lại, mà file của thẻ chạy vẫn giữ.
    'panel',
    card.tier.name,
    card.role,
    card.label,
    card.team,
    card.winner ?? '',
    card.alive,
    card.deathRound ?? '',
    card.round,
    card.playerCount,
    card.owned,
    _date(card.endedAt),
    owner,
  ].join('|'),
  text:
      '${card.label} · ${_winnerTitles[card.winner] ?? 'Ma Sói'}\nChia sẻ từ 3i',
);
