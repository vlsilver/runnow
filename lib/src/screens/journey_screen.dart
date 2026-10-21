import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/journey/widgets/completion_stamp.dart';
import 'package:myrun/src/journey/widgets/journey_map.dart';
import 'package:myrun/src/journey/widgets/round_icon_button.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/journey_share_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// "Hành Trình" gồm 3 chiến dịch mở khoá tuần tự (xem [JourneyCampaignId])
/// — mỗi chiến dịch là 1 màn hoàn toàn riêng, vị trí trên bản đồ thật suy
/// từ phần km trọn đời "tràn" xuống chiến dịch này (đã trừ hết các chiến
/// dịch trước, xem `journeyCampaignOffsetProvider`). Riêng Xuyên Việt còn
/// giữ bước chọn 1 trong 2 cung đường thật, user tự chọn 1 lần, không đổi
/// được. Hoàn thành sẽ mở khoá chiến dịch tiếp theo (`CompletionStamp`).
/// Xem `features/brief_hanh_trinh_xuyen_viet.md` + `journey_models.dart`.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({required this.campaignId, super.key, this.member});

  final JourneyCampaignId campaignId;

  /// Null = đang xem hành trình của chính mình. Khác null = xem của thành
  /// viên khác: tiến độ lấy theo uid của họ, và không được đổi cung đường
  /// hộ người ta (xem [_RoutePicker]).
  final MemberProfile? member;

  bool get _isViewingMember => member != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewedMember = member;
    final profileState = ref.watch(userProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isViewingMember
              ? '${campaignId.name} · ${viewedMember!.displayName}'
              : campaignId.name,
        ),
        actions: [
          IconButton(
            tooltip: 'Nhật ký chạy',
            onPressed: () => context.push(
              _isViewingMember
                  ? '/club/${viewedMember!.uid}/journal'
                  : '/profile/journal',
            ),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: campaignId.routeChoices.length == 1
          ? _JourneyBody(
              campaignId: campaignId,
              routeId: campaignId.routeChoices.single,
              member: viewedMember,
            )
          : viewedMember != null
          // Cung đường của thành viên đọc thẳng từ hồ sơ công khai của họ,
          // không qua userProfileProvider (vốn là hồ sơ của mình).
          ? _memberRouteBody(parseJourneyRouteId(viewedMember.journeyRouteId))
          : profileState.when(
              data: (profile) {
                final routeId = parseJourneyRouteId(profile?.journeyRouteId);
                if (routeId == null) {
                  return _RoutePicker(campaignId: campaignId);
                }
                return _JourneyBody(campaignId: campaignId, routeId: routeId);
              },
              loading: () => const Center(child: RunNowLoading()),
              error: (error, _) =>
                  Center(child: Text('Không tải được: $error')),
            ),
    );
  }

  Widget _memberRouteBody(JourneyRouteId? routeId) {
    if (routeId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Thành viên này chưa chọn cung đường cho chặng Xuyên Việt.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _JourneyBody(
      campaignId: campaignId,
      routeId: routeId,
      member: member,
    );
  }
}

/// Hành trình của 1 thành viên khác, mở từ `/club/:uid/journey/:campaignId`.
/// Tự nạp hồ sơ từ uid nên deep-link thẳng vào URL vẫn chạy, không phụ
/// thuộc object truyền qua navigation.
class MemberJourneyScreen extends ConsumerWidget {
  const MemberJourneyScreen({
    required this.uid,
    required this.campaignId,
    super.key,
  });

  final String uid;
  final JourneyCampaignId campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(memberProfileProvider(uid))
        .when(
          data: (member) {
            if (member == null) {
              return Scaffold(
                appBar: AppBar(title: Text(campaignId.name)),
                body: const Center(child: Text('Không tìm thấy thành viên.')),
              );
            }
            if (!member.isPublic) {
              return Scaffold(
                appBar: AppBar(title: Text(campaignId.name)),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Thành viên này để hồ sơ ở chế độ riêng tư.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            return JourneyScreen(campaignId: campaignId, member: member);
          },
          loading: () => const Scaffold(body: Center(child: RunNowLoading())),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: Text(campaignId.name)),
            body: Center(child: Text('Không tải được hồ sơ: $error')),
          ),
        );
  }
}

class _RoutePicker extends ConsumerWidget {
  const _RoutePicker({required this.campaignId});

  final JourneyCampaignId campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Text(
          campaignId.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Cực Bắc Lũng Cú → cực Nam Đất Mũi. Chọn 1 trong 2 cung đường thật '
          'để bắt đầu — chọn xong không đổi được, cân nhắc kỹ trước khi bấm.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final routeId in campaignId.routeChoices)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _RouteOptionCard(routeId: routeId),
          ),
      ],
    );
  }
}

class _RouteOptionCard extends ConsumerWidget {
  const _RouteOptionCard({required this.routeId});

  final JourneyRouteId routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final routeState = ref.watch(journeyRouteDetailProvider(routeId));
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: routeState.when(
        data: (route) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _choose(context, ref),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    routeId == JourneyRouteId.coastal
                        ? Icons.waves_rounded
                        : Icons.terrain_rounded,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      route.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(route.tagline),
              const SizedBox(height: 8),
              Text(
                '${formatDistance(route.totalLengthMeters)} · '
                '${route.milestones.length} mốc dừng chân',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: RunNowLoading(compact: true)),
        ),
        error: (error, _) => Text('Không tải được cung này: $error'),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận cung đường'),
        content: const Text(
          'Sau khi chọn sẽ không đổi cung được nữa. Bạn chắc chắn chứ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Chọn cung này'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(memberRepositoryProvider).setJourneyRoute(routeId.value);
  }
}

class _JourneyBody extends ConsumerStatefulWidget {
  const _JourneyBody({
    required this.campaignId,
    required this.routeId,
    this.member,
  });

  final JourneyCampaignId campaignId;
  final JourneyRouteId routeId;
  final MemberProfile? member;

  @override
  ConsumerState<_JourneyBody> createState() => _JourneyBodyState();
}

class _JourneyBodyState extends ConsumerState<_JourneyBody> {
  @override
  Widget build(BuildContext context) {
    final memberUid = widget.member?.uid;
    final routeState = ref.watch(journeyRouteDetailProvider(widget.routeId));
    // Km trọn đời phải lấy theo đúng người đang xem — dùng nhầm provider của
    // mình sẽ hiện tiến độ của mình dưới tên người ta.
    final distanceState = memberUid == null
        ? ref.watch(journeyLifetimeDistanceProvider)
        : ref.watch(memberJourneyLifetimeDistanceProvider(memberUid));
    final offsetState = ref.watch(
      journeyCampaignOffsetProvider(widget.campaignId),
    );
    final route = routeState.value;
    final lifetimeDistance = distanceState.value;
    final offset = offsetState.value;
    if (route == null || lifetimeDistance == null || offset == null) {
      final error =
          routeState.error ?? distanceState.error ?? offsetState.error;
      if (error != null) {
        return Center(child: Text('Không tải được hành trình: $error'));
      }
      return const Center(child: RunNowLoading());
    }
    final progress = JourneyProgress(
      route: route,
      totalDistanceMeters: (lifetimeDistance - offset).clamp(
        0,
        route.totalLengthMeters,
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: JourneyMap(
            progress: progress,
            onMilestoneTap: (milestone) => _openMilestone(
              context,
              progress,
              route.milestones.indexOf(milestone),
            ),
            onShowInfo: () => _openJourneyInfo(context, progress),
          ),
        ),
        if (progress.isComplete)
          Positioned(
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CompletionBanner(
                  campaignId: widget.campaignId,
                  route: route,
                  member: widget.member,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openJourneyInfo(BuildContext context, JourneyProgress progress) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _JourneyInfoSheet(campaignId: widget.campaignId, progress: progress),
    );
  }

  void _openMilestone(
    BuildContext context,
    JourneyProgress progress,
    int index,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _MilestoneDetailSheet(progress: progress, initialIndex: index),
    );
  }
}

/// Bấm marker vị trí hiện tại hoặc nút vòng tròn góc bản đồ mở ra đây —
/// toàn bộ thông tin hành trình gộp 1 chỗ, thay vì popup nổi trên bản đồ
/// (từng đè lên nhãn mốc khi đứng đúng tại 1 mốc).
class _JourneyInfoSheet extends StatelessWidget {
  const _JourneyInfoSheet({required this.campaignId, required this.progress});

  final JourneyCampaignId campaignId;
  final JourneyProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final route = progress.route;
    final ratio = route.totalLengthMeters <= 0
        ? 0.0
        : (progress.distanceIntoRouteMeters / route.totalLengthMeters).clamp(
            0.0,
            1.0,
          );
    final reachedCount = route.milestones
        .where(progress.isMilestoneReached)
        .length;
    final next = progress.nextMilestone;
    final remaining = progress.remainingToNextMilestoneMeters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: GlassPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              route.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              route.tagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDistance(progress.distanceIntoRouteMeters),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/ ${formatDistance(route.totalLengthMeters)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(ratio * 100).toStringAsFixed(0)}% hành trình · '
              '$reachedCount/${route.milestones.length} mốc đã mở khoá',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (next != null && remaining != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.flag_rounded, size: 18, color: palette.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Còn ${formatDistance(remaining)} tới ${next.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (progress.isComplete) ...[
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CompletionStamp(accent: palette.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Bạn đã hoàn thành ${campaignId.name}!',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (campaignId.next case final nextCampaign?) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        context.push('/profile/journey/${nextCampaign.value}'),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Mở khoá hành trình tiếp theo'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Banner đóng dấu hoàn thành — nổi thẳng trên bản đồ ngay khi mở màn (đã
/// từng chỉ nằm trong sheet bấm-mới-thấy, quá dễ bỏ lỡ cho 1 cột mốc lớn
/// như xong cả hành trình). Nút mở khoá tiếp theo cũng nằm ngay đây, không
/// cần đào vào popup mới thấy — ẩn hẳn khi đây đã là chiến dịch cuối cùng.
class _CompletionBanner extends StatelessWidget {
  const _CompletionBanner({
    required this.campaignId,
    required this.route,
    this.member,
  });

  final JourneyCampaignId campaignId;
  final JourneyRoute route;
  final MemberProfile? member;

  @override
  Widget build(BuildContext context) {
    final nextCampaign = campaignId.next;
    final viewedMember = member;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chia sẻ là "thành tích của tôi" — không hiện khi đang xem hành
        // trình của người khác.
        if (viewedMember == null)
          RoundIconButton(
            icon: Icons.share_rounded,
            tooltip: 'Chia sẻ thành tích',
            size: 44,
            iconSize: 22,
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                fullscreenDialog: true,
                opaque: true,
                pageBuilder: (context, _, _) => JourneyShareScreen(
                  campaignName: campaignId.name,
                  route: route,
                ),
              ),
            ),
          ),
        if (nextCampaign != null) ...[
          if (viewedMember == null) const SizedBox(height: 10),
          RoundIconButton(
            icon: Icons.lock_open_rounded,
            tooltip: viewedMember == null
                ? 'Mở khoá hành trình tiếp theo'
                : 'Xem chặng tiếp theo',
            size: 44,
            iconSize: 22,
            onTap: () => context.push(
              viewedMember == null
                  ? '/profile/journey/${nextCampaign.value}'
                  : '/club/${viewedMember.uid}/journey/${nextCampaign.value}',
            ),
          ),
        ],
      ],
    );
  }
}

/// Popup chi tiết 1 mốc — bấm marker trên bản đồ mở ra đây. Có ảnh minh
/// hoạ + mô tả ngắn (chỉ khi đã mở khoá — giữ bí ẩn cho mốc chưa tới, đúng
/// nguyên tắc thiết kế ban đầu), km/tiến độ, và nút lùi/tiếp để xem lần
/// lượt các mốc khác mà không cần đóng rồi bấm lại marker.
class _MilestoneDetailSheet extends StatefulWidget {
  const _MilestoneDetailSheet({
    required this.progress,
    required this.initialIndex,
  });

  final JourneyProgress progress;
  final int initialIndex;

  @override
  State<_MilestoneDetailSheet> createState() => _MilestoneDetailSheetState();
}

class _MilestoneDetailSheetState extends State<_MilestoneDetailSheet> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final route = widget.progress.route;
    final milestone = route.milestones[_index];
    final reached = widget.progress.isMilestoneReached(milestone);
    final remaining =
        milestone.cumulativeMeters - widget.progress.distanceIntoRouteMeters;
    final palette = context.runNowPalette;
    final ratio = (milestone.cumulativeMeters / route.totalLengthMeters).clamp(
      0.0,
      1.0,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _MilestoneImage(milestone: milestone, reached: reached),
                Positioned(
                  top: 8,
                  right: 8,
                  child: RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        '${_index + 1}/${route.milestones.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        reached
                            ? Icons.location_on_rounded
                            : Icons.lock_rounded,
                        color: reached
                            ? palette.accent
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reached ? milestone.name : 'Mốc chưa mở khoá',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (reached && milestone.fact.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      milestone.fact,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    reached
                        ? '${formatDistance(milestone.cumulativeMeters)} từ điểm xuất phát'
                        : 'Còn ${formatDistance(remaining)} nữa — chạy tiếp để mở khoá.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      color: reached
                          ? palette.accent
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _index > 0
                              ? () => setState(() => _index -= 1)
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Mốc trước'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _index < route.milestones.length - 1
                              ? () => setState(() => _index += 1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Mốc tiếp'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneImage extends StatelessWidget {
  const _MilestoneImage({required this.milestone, required this.reached});

  final JourneyMilestone milestone;
  final bool reached;

  static const _height = 170.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final path = reached ? milestone.storagePath : null;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.glassStart, palette.glassEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          reached ? Icons.photo_camera_back_rounded : Icons.lock_rounded,
          size: 36,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: path == null
            ? placeholder
            : StorageImage(path: path, fit: BoxFit.cover, cacheWidth: 700),
      ),
    );
  }
}
