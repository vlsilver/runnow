import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/run_now_empty.dart';
import 'package:myrun/src/widgets/section_card.dart';

/// Tab Hồ sơ: châm ngôn, danh tính và bộ thẻ. Số liệu, nhật ký và hành
/// trình nằm ở tab Hoạt động. Cài đặt ở `/me/settings`, MyBot ở `/me/mybot`.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Trang hoặc kệ thẻ đang cuộn. Thẻ mới nhất ngừng đung đưa lúc này để
  /// mỗi khung cuộn không phải vẽ lại cả thẻ 3D.
  final _scrolling = ValueNotifier(false);
  var _scrollActive = false;

  @override
  void dispose() {
    _scrolling.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _scrollActive = true;
    } else if (n is ScrollEndNotification) {
      _scrollActive = false;
    } else {
      return false;
    }
    // Nội dung đổi cỡ thì list tự trôi về mép ngay giữa lúc layout, khi đó
    // chưa được rebuild nên đợi hết frame mới báo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrolling.value = _scrollActive;
    });
    WidgetsBinding.instance.scheduleFrame();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final element = ref.watch(themeControllerProvider).element;
    final stats = ref.watch(profileStatsProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(profileStatsProvider.future),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  children: [
                    _Header(
                      onSettings: () => context.push('/me/settings'),
                      onMyBot: myBotVisible(ref)
                          ? () {
                              // Đọc lại hồ sơ bot: chạy xong mở là thấy km
                              // và số tin mới.
                              ref.invalidate(agentMeProvider);
                              context.push('/me/mybot');
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    const _DailyQuoteCard(),
                    const SizedBox(height: 14),
                    _Identity(
                      profile: profile,
                      subtitle: _identitySubtitle(element, stats),
                    ),
                    const SizedBox(height: 16),
                    _CardShelfSection(scrolling: _scrolling),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _identitySubtitle(RunNowElement element, ProfileStatsData? stats) {
    final first = stats?.firstMonthKey;
    if (stats == null) return 'Hành ${element.label}';
    if (first == null) return 'Hành ${element.label} · mới vào 3i';
    return 'Hành ${element.label} · chạy cùng 3i từ '
        '${profileMonthLabel(first)}';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.onMyBot});

  final VoidCallback onSettings;

  /// Null khi user chưa được bật bot: ẩn nút.
  final VoidCallback? onMyBot;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final style = IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      side: BorderSide(color: palette.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            'Hồ sơ',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: palette.foreground,
            ),
          ),
        ),
        if (onMyBot != null) ...[
          IconButton.outlined(
            tooltip: 'MyBot',
            onPressed: onMyBot,
            style: style,
            icon: const Icon(Icons.smart_toy_outlined, size: 20),
          ),
          const SizedBox(width: 8),
        ],
        IconButton.outlined(
          tooltip: 'Cài đặt',
          onPressed: onSettings,
          style: style,
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.subtitle});

  final UserProfile? profile;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = profile?.displayName ?? '';
    final avatarUrl = profile?.avatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: palette.accent.withValues(alpha: 0.22),
          backgroundImage: avatarUrl == null
              ? null
              : cachedAvatarImage(context, avatarUrl, 64),
          child: avatarUrl != null
              ? null
              : Text(
                  name.isEmpty ? '' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: palette.accent,
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Số thẻ hiện trong Hồ sơ, kể cả thẻ mới nhất; còn lại xem ở màn Bộ thẻ.
const _shelfCardCount = 10;

/// Bộ thẻ (buổi chạy và Ma Sói), đặt đầu Hồ sơ: thẻ mới nhất to và 3D, kèm số thẻ theo
/// bậc, rồi hàng ngang các thẻ trước đó.
class _CardShelfSection extends ConsumerWidget {
  const _CardShelfSection({required this.scrolling});

  final ValueListenable<bool> scrolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(collectedCardsProvider);
    final count = cards.value?.length ?? 0;
    final Widget body = cards.when(
      loading: () =>
          const RunNowLoading(compact: true, label: 'Đang mở bộ thẻ'),
      error: (error, _) => SectionMuted('Không tải được bộ thẻ: $error'),
      data: (cards) {
        if (cards.isEmpty) {
          return const RunNowEmpty(
            compact: true,
            message: collectedCardsEmpty,
            hint: collectedCardsEmptyHint,
          );
        }
        final owner = runCardOwnerName(ref);
        final rest = cards.skip(1).take(_shelfCardCount - 1).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FeaturedCard(
              card: cards.first,
              owner: owner,
              all: cards,
              scrolling: scrolling,
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height:
                    96 * achievementCardSize.height / achievementCardSize.width,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rest.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => CollectedCardThumb(
                    card: rest[i],
                    owner: owner,
                    width: 96,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
    return SectionCard(
      children: [
        Row(
          children: [
            const Expanded(child: SectionCaption('Bộ thẻ')),
            if (count > 0)
              Text(
                '$count thẻ',
                style: TextStyle(
                  fontSize: 12,
                  color: context.runNowPalette.textMuted,
                ),
              ),
            TextButton(
              onPressed: () => context.push('/me/cards'),
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

/// Thẻ mới nhất dựng 3D, cạnh đó là số thẻ đã có của từng bậc.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.card,
    required this.owner,
    required this.all,
    required this.scrolling,
  });

  final CollectedCard card;
  final String owner;
  final List<CollectedCard> all;
  final ValueListenable<bool> scrolling;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final data = card.data(owner);
    final counts = <GameCardTier, int>{};
    for (final c in all) {
      counts[c.tier] = (counts[c.tier] ?? 0) + 1;
    }
    return Row(
      children: [
        ValueListenableBuilder(
          valueListenable: scrolling,
          builder: (context, scrolling, _) => TiltFlipCard(
            front: (pose) => AchievementCard(data: data, pose: pose),
            back: (pose) => AchievementCard(data: data, pose: pose, back: true),
            width: 150,
            cardSize: achievementCardSize,
            sway: !scrolling,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MỚI NHẤT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                card.subtitle,
                style: TextStyle(fontSize: 13, color: palette.textMuted),
              ),
              const SizedBox(height: 14),
              for (final tier in GameCardTier.values.reversed)
                if (counts[tier] case final n?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.diamond,
                          size: 13,
                          color: gameCardTiers[tier]!.gem,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            gameCardTiers[tier]!.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '×$n',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 6),
              Text(
                'Chạm thẻ để lật',
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card "Châm ngôn hôm nay" — tách riêng, nền vàng nhạt, đúng nguyên bản
/// thiết kế (không lồng vào trong card hero tối như bản trước).
class _DailyQuoteCard extends StatelessWidget {
  const _DailyQuoteCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"',
            style: TextStyle(
              color: palette.accentDeep,
              fontSize: 20,
              height: 0.7,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHÂM NGÔN HÔM NAY',
                  style: TextStyle(
                    color: palette.accentDeep,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mỗi kilomet là một dấu chân đặt lên bản đồ. Đi đủ lâu, '
                  'đường xa cũng thành câu chuyện của mình.',
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
