import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_village.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _M = RunNowMoonlitTokens;

final _clockFormat = DateFormat('HH:mm');
const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Khối đầu sảnh: số chỗ, dải chỗ ngồi và các ô số. Giờ đóng đăng ký do app
/// định dạng theo giờ máy, các ô còn lại do backend gửi (`lobby.facts`).
class GameLobbyHero extends StatelessWidget {
  const GameLobbyHero({super.key, required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context) {
    final deadline = detail.registrationDeadline?.toLocal();
    final count = detail.playerCount;
    final facts = detail.lobby?.facts ?? const <GameLobbyFact>[];
    final startError = detail.startError;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _M.amberLine),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_M.heroTop, _M.heroMid, _M.heroBottom],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -6,
            top: -10,
            child: GameMoonEmblem(size: 64),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [_M.amber, _M.amberBright],
                    ),
                  ),
                  child: const Text(
                    'MỞ ĐĂNG KÝ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: _M.onAmber,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: gameTitleFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 56,
                      height: 0.85,
                      color: _M.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '/ ${detail.maxPlayers} chỗ',
                          style: const TextStyle(
                            fontFamily: gameTitleFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: _M.inkSoft,
                          ),
                        ),
                        Text(
                          count >= detail.minPlayers
                              ? 'đủ người để mở ván'
                              : 'cần ít nhất ${detail.minPlayers} để mở ván',
                          style: const TextStyle(fontSize: 12, color: _M.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Slots(
                count: count,
                min: detail.minPlayers,
                max: detail.maxPlayers,
              ),
              if (deadline != null || facts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (deadline != null)
                      _Fact(
                        value: _clockFormat.format(deadline),
                        label:
                            'đóng đăng ký · '
                            '${_weekdays[deadline.weekday - 1]}',
                      ),
                    for (final (i, fact) in facts.indexed) ...[
                      if (i > 0 || deadline != null) const SizedBox(width: 8),
                      _Fact(value: fact.value, label: fact.label),
                    ],
                  ],
                ),
              ],
              if (startError != null) ...[
                const SizedBox(height: 10),
                Text(
                  startError.message,
                  style: const TextStyle(color: _M.danger),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _M.well,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: gameTitleFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1,
                color: _M.ink,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontSize: 11, color: _M.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dải chỗ ngồi: mỗi chỗ một vạch, chỗ đã có người sáng lên, vạch số người
/// tối thiểu nhạt hơn khi chưa đủ.
class _Slots extends StatelessWidget {
  const _Slots({required this.count, required this.min, required this.max});

  final int count;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (max <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < max; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < count
                    ? null
                    : i < min
                    ? _M.amberLine
                    : _M.track,
                gradient: i < count
                    ? const LinearGradient(colors: [_M.amber, _M.amberBright])
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 1.4,
              color: _M.ink,
            ),
          ),
        ),
        if (trailing != null)
          Text(trailing, style: const TextStyle(fontSize: 12, color: _M.muted)),
      ],
    );
  }
}

/// Các vai của ván (`lobby.roles`). Vai mở rộng có viền vàng.
class GameLobbyRoles extends StatelessWidget {
  const GameLobbyRoles({super.key, required this.roles});

  final List<GameLobbyRole> roles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Head('VAI TRONG VÁN'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in roles)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: role.extended ? _M.amberTint : _M.panel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: role.extended ? _M.amberLine : _M.border,
                  ),
                ),
                child: Text(
                  role.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: role.extended ? _M.amberSoft : _M.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Khối điều kiện vào ván. Dòng liên kết Telegram có nút mở bot ngay tại dòng
/// khi [onLinkTelegram] khác null.
class GameLobbyRequirements extends StatelessWidget {
  const GameLobbyRequirements({
    super.key,
    required this.requirements,
    required this.onOpenUrl,
    this.onLinkTelegram,
    this.waitingTelegram = false,
  });

  final List<GameRequirement> requirements;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback? onLinkTelegram;
  final bool waitingTelegram;

  @override
  Widget build(BuildContext context) {
    final met = requirements.where((r) => r.ok).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _M.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ĐỦ ĐIỀU KIỆN $met/${requirements.length}',
            style: const TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 1.4,
              color: _M.inkSoft,
            ),
          ),
          for (final requirement in requirements)
            _RequirementRow(
              requirement: requirement,
              onOpenUrl: onOpenUrl,
              onLinkTelegram: requirement.key == gameTelegramRequirement
                  ? onLinkTelegram
                  : null,
            ),
          if (waitingTelegram)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Bấm Start trong Telegram rồi quay lại đây.',
                style: TextStyle(fontSize: 12, color: _M.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// `key` của điều kiện liên kết Telegram backend gửi.
const gameTelegramRequirement = 'telegram_linked';

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({
    required this.requirement,
    required this.onOpenUrl,
    this.onLinkTelegram,
  });

  final GameRequirement requirement;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback? onLinkTelegram;

  @override
  Widget build(BuildContext context) {
    final action = requirement.action;
    final url = action?.url;
    final link = onLinkTelegram;
    final Widget? trailing = !requirement.ok && link != null
        ? FilledButton(
            onPressed: link,
            style: FilledButton.styleFrom(
              backgroundColor: _M.telegram,
              foregroundColor: _M.onTelegram,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Liên kết'),
          )
        : switch (action?.type) {
            'open_url' when url != null => TextButton(
              onPressed: () => onOpenUrl(url),
              child: const Text('Mở'),
            ),
            'update_app' when url != null => TextButton(
              onPressed: () => onOpenUrl(url),
              child: const Text('Cập nhật'),
            ),
            _ => null,
          };
    final hint = action?.type == 'update_app' && url == null
        ? _updateHint()
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            requirement.ok
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 24,
            color: requirement.ok ? _M.amberSoft : _M.borderStrong,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.label,
                  style: const TextStyle(fontSize: 14, color: _M.ink),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: const TextStyle(fontSize: 12, color: _M.muted),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static String _updateHint() {
    if (kIsWeb) return 'Tải lại trang để lấy bản mới.';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'Cập nhật app trên App Store.',
      TargetPlatform.android => 'Cập nhật app trên Google Play.',
      _ => 'Cập nhật app lên bản mới.',
    };
  }
}

/// Lưới người đã vào sảnh, thêm ô "Bạn?" khi người xem chưa đăng ký.
class GameLobbyPlayers extends StatelessWidget {
  const GameLobbyPlayers({
    super.key,
    required this.players,
    required this.myUid,
    required this.showJoinSlot,
    required this.onJoin,
  });

  final List<GamePlayer> players;
  final String? myUid;
  final bool showJoinSlot;

  /// Null khi chưa vào được: ô "Bạn?" vẫn hiện nhưng không bấm được.
  final VoidCallback? onJoin;

  static const _columns = 5;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head('ĐÃ VÀO SẢNH', trailing: '${players.length} người'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width =
                (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
            return Wrap(
              spacing: _gap,
              runSpacing: 12,
              children: [
                for (final player in players)
                  SizedBox(
                    width: width,
                    child: _PlayerTile(
                      avatar: GameVillagerAvatar(
                        player: player,
                        isMe: player.uid == myUid,
                        size: 52,
                      ),
                      name: player.uid == myUid ? 'Bạn' : player.name,
                    ),
                  ),
                if (showJoinSlot)
                  SizedBox(
                    width: width,
                    child: GestureDetector(
                      onTap: onJoin,
                      child: const _PlayerTile(
                        avatar: _JoinSlot(),
                        name: 'Bạn?',
                        accent: true,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.avatar,
    required this.name,
    this.accent = false,
  });

  final Widget avatar;
  final String name;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        avatar,
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accent ? _M.amberSoft : _M.ink,
          ),
        ),
      ],
    );
  }
}

class _JoinSlot extends StatelessWidget {
  const _JoinSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _M.amberSoft, width: 1.5),
      ),
      child: const Icon(Icons.add_rounded, size: 22, color: _M.amberSoft),
    );
  }
}

/// Nút vào ván hoặc huỷ đăng ký ở cuối sảnh, kèm dòng nói còn thiếu gì.
class GameLobbyJoin extends StatelessWidget {
  const GameLobbyJoin({
    super.key,
    required this.detail,
    required this.busy,
    required this.onToggle,
  });

  final GameDetail detail;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (detail.isRegistered) {
      return OutlinedButton(
        onPressed: busy ? null : onToggle,
        child: const Text('Huỷ đăng ký'),
      );
    }
    final missing = detail.requirements.where((r) => !r.ok).firstOrNull;
    final enabled = !busy && missing == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [_M.amber, _M.amberBright],
              ),
            ),
            child: FilledButton(
              onPressed: enabled ? onToggle : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: _M.onAmber,
                disabledForegroundColor: _M.onAmber,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontFamily: gameTitleFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 2,
                ),
              ),
              child: const Text('VÀO VÁN'),
            ),
          ),
        ),
        if (missing != null) ...[
          const SizedBox(height: 8),
          Text(
            '${missing.label} xong là vào được',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _M.muted),
          ),
        ],
      ],
    );
  }
}
