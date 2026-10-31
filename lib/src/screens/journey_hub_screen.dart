import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/journey/journey_timeline.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';

class JourneyHubScreen extends StatelessWidget {
  const JourneyHubScreen({super.key, this.memberUid, this.member});

  final String? memberUid;
  final MemberProfile? member;

  @override
  Widget build(BuildContext context) {
    final uid = memberUid;
    return Scaffold(
      backgroundColor: context.runNowPalette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _JourneyHeader(
                    title: member?.displayName ?? 'Hành Trình',
                    subtitle: member == null ? null : 'Hành trình',
                    onJournalTap: () => uid == null
                        ? context.push('/journal')
                        : context.push('/club/$uid/journal'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            JourneyTimeline(memberUid: uid, member: member),
          ],
        ),
      ),
    );
  }
}

class _JourneyHeader extends StatelessWidget {
  const _JourneyHeader({
    required this.title,
    required this.subtitle,
    required this.onJournalTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onJournalTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 27,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.55),
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        Material(
          color: palette.glassStart,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          child: IconButton(
            tooltip: 'Nhật ký chạy',
            onPressed: onJournalTap,
            icon: Icon(Icons.list_alt_rounded, color: palette.ink),
          ),
        ),
      ],
    );
  }
}
