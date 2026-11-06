import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/settings_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// Tab Hồ sơ: danh tính, lối vào MyBot (`/me/mybot`), rồi các mục cài đặt.
/// Châm ngôn, bộ thẻ, số liệu, nhật ký và hành trình nằm ở tab Hoạt động.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final element = ref.watch(themeControllerProvider).element;
    final stats = ref.watch(profileStatsProvider).value;
    return SettingsScreen(
      header: [
        _Header(
          onMyBot: myBotVisible(ref)
              ? () {
                  // Đọc lại hồ sơ bot: chạy xong mở là thấy km và số tin mới.
                  ref.invalidate(agentMeProvider);
                  context.push('/me/mybot');
                }
              : null,
        ),
        const SizedBox(height: 14),
        _Identity(
          profile: profile,
          subtitle: _identitySubtitle(element, stats),
        ),
        const SizedBox(height: 18),
      ],
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
  const _Header({required this.onMyBot});

  /// Null khi user chưa được bật bot: ẩn nút.
  final VoidCallback? onMyBot;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
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
        if (onMyBot != null)
          IconButton.outlined(
            tooltip: 'MyBot',
            onPressed: onMyBot,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              side: BorderSide(color: palette.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.smart_toy_outlined, size: 20),
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
