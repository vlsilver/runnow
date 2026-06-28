import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';
import 'package:myrun/src/widgets/glass.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(userProfileProvider);
    final themeController = ref.watch(themeControllerProvider);
    final strava = ref.watch(stravaAuthProvider);
    final stravaConnected = ref.watch(stravaConnectionProvider);
    final googleAuth = ref.watch(googleAuthProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          profile.when(
            data: (user) => _AccountHeader(
              profile: user,
              onEdit: user == null
                  ? null
                  : () => _editClubProfile(context, ref, user),
            ),
            loading: () => const _AccountHeader.loading(),
            error: (error, stack) => _SettingsSection(
              children: [
                _SettingsRow(
                  icon: Icons.error_outline,
                  title: 'Không thể tải tài khoản',
                  subtitle: '$error',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'Tài khoản',
            children: [
              profile.maybeWhen(
                data: (user) => _SettingsRow(
                  icon: Icons.badge_outlined,
                  title: 'Hồ sơ Club',
                  value: user?.visibility == ProfileVisibility.public
                      ? 'Public'
                      : 'Private',
                  onTap: user == null
                      ? null
                      : () => _editClubProfile(context, ref, user),
                ),
                orElse: () => const _SettingsRow(
                  icon: Icons.badge_outlined,
                  title: 'Hồ sơ Club',
                  value: 'Đang tải',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'Kết nối',
            children: [
              _SettingsRow(
                icon: stravaConnected ? Icons.link : Icons.link_off_outlined,
                title: 'Strava',
                value: strava.loading
                    ? 'Đang xử lý'
                    : stravaConnected
                    ? 'Đã kết nối'
                    : 'Chưa kết nối',
                onTap: strava.loading ? null : strava.connect,
              ),
              if (stravaConnected)
                _SettingsRow(
                  icon: Icons.sync,
                  title: 'Đồng bộ Strava',
                  value: sync.syncing ? 'Đang chạy' : null,
                  onTap: sync.syncing
                      ? null
                      : () => ref
                            .read(syncControllerProvider)
                            .startBackgroundSync(force: true),
                ),
              if (stravaConnected)
                _SettingsRow(
                  icon: Icons.link_off,
                  title: 'Ngắt kết nối Strava',
                  destructive: true,
                  onTap: strava.loading ? null : strava.disconnect,
                ),
              if (strava.errorMessage != null)
                _SettingsMessage(message: strava.errorMessage!),
              if (sync.message != null)
                _SettingsMessage(message: sync.message!),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'Hiển thị',
            children: [
              _SettingsRow(
                icon: Icons.auto_awesome_outlined,
                title: 'Ngũ hành',
                subtitle:
                    '${themeController.element.description} · '
                    '${themeController.appearance.label}'
                    '${themeController.appearance == RunNowAppearance.dark ? ' · ${themeController.darkTone.label}' : ''}',
                value: themeController.element.label,
                onTap: () => _editElement(context, ref, themeController),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            children: [
              _SettingsRow(
                icon: Icons.logout,
                title: 'Đăng xuất Google',
                value: googleAuth.loading ? 'Đang xử lý' : null,
                destructive: true,
                onTap: googleAuth.loading ? null : googleAuth.signOut,
              ),
              if (googleAuth.errorMessage != null)
                _SettingsMessage(message: googleAuth.errorMessage!),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _editElement(
  BuildContext context,
  WidgetRef ref,
  ThemeController controller,
) async {
  var selectedElement = controller.element;
  var selectedAppearance = controller.appearance;
  var selectedDarkTone = controller.darkTone;
  final result = await showModalBottomSheet<_ThemeSelection>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: GlassPanel(
          borderRadius: 22,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CHỌN NGŨ HÀNH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SegmentedButton<RunNowAppearance>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: RunNowAppearance.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Sáng'),
                        ),
                        ButtonSegment(
                          value: RunNowAppearance.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Tối'),
                        ),
                      ],
                      selected: {selectedAppearance},
                      onSelectionChanged: (values) => setModalState(
                        () => selectedAppearance = values.single,
                      ),
                    ),
                  ),
                  if (selectedAppearance == RunNowAppearance.dark) ...[
                    const SizedBox(height: 14),
                    _DarkTonePicker(
                      element: selectedElement,
                      value: selectedDarkTone,
                      onChanged: (value) =>
                          setModalState(() => selectedDarkTone = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  for (final element in RunNowElement.values) ...[
                    _ThemeChoice(
                      element: element,
                      appearance: selectedAppearance,
                      darkTone: selectedDarkTone,
                      icon: _elementIcon(element),
                      selected: selectedElement == element,
                      onTap: () =>
                          setModalState(() => selectedElement = element),
                    ),
                    if (element != RunNowElement.values.last)
                      _SettingsDivider(),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(
                          _ThemeSelection(
                            element: selectedElement,
                            appearance: selectedAppearance,
                            darkTone: selectedDarkTone,
                          ),
                        ),
                        child: const Text('Áp dụng'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (result == null) return;
  await ref
      .read(themeControllerProvider)
      .setSelection(
        element: result.element,
        appearance: result.appearance,
        darkTone: result.darkTone,
      );
}

Future<void> _editClubProfile(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  final result = await showModalBottomSheet<_ProfileEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ClubProfileEditorSheet(profile: profile),
  );
  if (result == null) return;
  await ref
      .read(memberRepositoryProvider)
      .updateCurrentProfile(
        nickname: result.nickname,
        avatarUrl: result.avatarUrl,
        visibility: result.visibility,
      );
}

class _ClubProfileEditorSheet extends StatefulWidget {
  const _ClubProfileEditorSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_ClubProfileEditorSheet> createState() =>
      _ClubProfileEditorSheetState();
}

class _ClubProfileEditorSheetState extends State<_ClubProfileEditorSheet> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _avatarController;
  late ProfileVisibility _visibility;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nicknameController = TextEditingController(
      text: profile.nickname?.trim().isNotEmpty == true
          ? profile.nickname!.trim()
          : profile.displayName,
    );
    _avatarController = TextEditingController(text: profile.avatarUrl ?? '');
    _visibility = profile.visibility;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hồ sơ Club', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'Tên hiển thị trong Club',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _avatarController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Avatar URL',
                hintText: 'https://...',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ProfileVisibility>(
                segments: const [
                  ButtonSegment(
                    value: ProfileVisibility.private,
                    icon: Icon(Icons.lock_outline),
                    label: Text('Private'),
                  ),
                  ButtonSegment(
                    value: ProfileVisibility.public,
                    icon: Icon(Icons.public),
                    label: Text('Public'),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (selection) {
                  setState(() => _visibility = selection.single);
                },
              ),
            ),
            if (_visibility == ProfileVisibility.public) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Public nghĩa là thành viên khác có thể xem dữ liệu luyện tập của bạn khi tính năng hồ sơ public được mở rộng.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _ProfileEditResult(
                        nickname: _nicknameController.text,
                        avatarUrl: _avatarController.text,
                        visibility: _visibility,
                      ),
                    ),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileEditResult {
  const _ProfileEditResult({
    required this.nickname,
    required this.avatarUrl,
    required this.visibility,
  });

  final String nickname;
  final String avatarUrl;
  final ProfileVisibility visibility;
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.profile, required this.onEdit});
  const _AccountHeader.loading() : profile = null, onEdit = null;

  final UserProfile? profile;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final user = profile;
    final avatarUrl = user?.avatarUrl;
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: palette.secondary.withValues(alpha: 0.18),
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? Icon(
                    user == null ? Icons.person_outline : Icons.person,
                    color: palette.secondary,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'Đang tải tài khoản',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  _accountSubtitle(user),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sửa hồ sơ Club',
            onPressed: onEdit,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  String _accountSubtitle(UserProfile? user) {
    if (user == null) return 'Google account';
    final parts = [
      if (user.email != null) user.email!,
      user.visibility == ProfileVisibility.public ? 'Public' : 'Private',
      if (user.lastSyncedAt != null) 'Sync ${formatDate(user.lastSyncedAt!)}',
    ];
    return parts.join('  •  ');
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 7),
            child: Text(
              title!.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
        GlassPanel(
          borderRadius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _withDividers(children),
          ),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    return [
      for (var index = 0; index < items.length; index++) ...[
        items[index],
        if (index != items.length - 1) _SettingsDivider(),
      ],
    ];
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.accent,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? accent;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedAccent =
        accent ?? (destructive ? scheme.error : scheme.secondary);
    final textColor = destructive ? scheme.error : scheme.onSurface;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.54);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _SettingsIcon(icon: icon, color: resolvedAccent),
      title: Text(title, style: TextStyle(color: textColor)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: TextStyle(color: muted, fontSize: 15)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: muted),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _SettingsMessage extends StatelessWidget {
  const _SettingsMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.68),
          ),
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.element,
    required this.appearance,
    required this.darkTone,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final RunNowElement element;
  final RunNowAppearance appearance;
  final RunNowDarkTone darkTone;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RunNowPalette.forSelection(
      element,
      appearance: appearance,
      darkTone: darkTone,
    );
    return _SettingsRow(
      icon: icon,
      title: element.label,
      subtitle: element.description,
      value: selected ? '✓' : null,
      accent: palette.accent,
      onTap: onTap,
    );
  }
}

class _ThemeSelection {
  const _ThemeSelection({
    required this.element,
    required this.appearance,
    required this.darkTone,
  });

  final RunNowElement element;
  final RunNowAppearance appearance;
  final RunNowDarkTone darkTone;
}

class _DarkTonePicker extends StatelessWidget {
  const _DarkTonePicker({
    required this.element,
    required this.value,
    required this.onChanged,
  });

  final RunNowElement element;
  final RunNowDarkTone value;
  final ValueChanged<RunNowDarkTone> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TÔNG NỀN TỐI',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.58),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final tone in RunNowDarkTone.values)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(tone),
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: tone.materialFor(element)[0],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: tone == value
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tone.label,
                            maxLines: 1,
                            style: TextStyle(
                              color: onSurface.withValues(
                                alpha: tone == value ? 0.9 : 0.5,
                              ),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _elementIcon(RunNowElement element) => switch (element) {
  RunNowElement.metal => Icons.diamond_outlined,
  RunNowElement.wood => Icons.park_outlined,
  RunNowElement.water => Icons.water_drop_outlined,
  RunNowElement.fire => Icons.local_fire_department_outlined,
  RunNowElement.earth => Icons.landscape_outlined,
};

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 58,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
    );
  }
}
