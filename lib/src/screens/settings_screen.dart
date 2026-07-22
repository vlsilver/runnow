import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(userProfileProvider);
    final themeController = ref.watch(themeControllerProvider);
    final strava = ref.watch(stravaAuthProvider);
    final stravaConnected = ref.watch(stravaConnectionProvider);
    final googleAuth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              profile.when(
                data: (user) => _AccountHeader(
                  profile: user,
                  onEdit: user == null ? null : () => context.push('/profile'),
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
                      title: 'Tên hiển thị',
                      value: user?.nickname?.trim().isNotEmpty == true
                          ? user!.nickname!.trim()
                          : user?.displayName,
                      onTap: user == null
                          ? null
                          : () => _editNickname(context, ref, user),
                    ),
                    orElse: () => const _SettingsRow(
                      icon: Icons.badge_outlined,
                      title: 'Tên hiển thị',
                      value: 'Đang tải',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: 'Kết nối',
                children: [
                  // Chưa kết nối thì phải dùng đúng nút "Connect with Strava"
                  // chính thức; đã kết nối rồi thì chỉ còn là dòng trạng
                  // thái, không cần nút nữa.
                  if (stravaConnected || strava.statusLoading)
                    _SettingsRow(
                      icon: stravaConnected
                          ? Icons.link
                          : Icons.link_off_outlined,
                      title: 'Strava',
                      value: strava.statusLoading
                          ? 'Đang kiểm tra'
                          : strava.loading
                          ? 'Đang xử lý'
                          : 'Đã kết nối',
                    )
                  else
                    _ConnectWithStravaButton(
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
                      icon: Icons.history,
                      title: 'Đồng bộ toàn bộ lịch sử',
                      value: sync.syncing ? 'Đang chạy' : null,
                      onTap: sync.syncing
                          ? null
                          : () => ref
                                .read(syncControllerProvider)
                                .startBackgroundSync(
                                  force: true,
                                  fullResync: true,
                                ),
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
                  const _PoweredByStrava(),
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
                        '${themeController.appearance.label}',
                    value: themeController.element.label,
                    onTap: () => _editElement(context, ref, themeController),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: '3i',
                children: [
                  _SettingsRow(
                    icon: Icons.help_outline_rounded,
                    title: 'Hỗ trợ',
                    onTap: () => _openWebDocument('support.html'),
                  ),
                  _SettingsRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Chính sách quyền riêng tư',
                    onTap: () => _openWebDocument('privacy.html'),
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
        ),
      ),
    );
  }
}

Future<void> _openWebDocument(String path) async {
  final uri = kIsWeb
      ? Uri.base.resolve(path)
      : Uri.parse('${AppConfig.webBaseUrl}/$path');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _editElement(
  BuildContext context,
  WidgetRef ref,
  ThemeController controller,
) async {
  var selectedElement = controller.element;
  var selectedAppearance = controller.appearance;
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
                  const SizedBox(height: 10),
                  for (final element in RunNowElement.values) ...[
                    _ThemeChoice(
                      element: element,
                      appearance: selectedAppearance,
                      darkTone: RunNowDarkTone.elemental,
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
                            darkTone: RunNowDarkTone.elemental,
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

Future<void> _editNickname(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  final initialNickname = profile.nickname?.trim().isNotEmpty == true
      ? profile.nickname!.trim()
      : profile.displayName;
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _NicknameEditorSheet(initialNickname: initialNickname),
  );
  if (result == null) return;
  await ref
      .read(memberRepositoryProvider)
      .updateCurrentProfile(
        nickname: result,
        avatarUrl: profile.avatarUrl,
        visibility: profile.visibility,
      );
}

class _NicknameEditorSheet extends StatefulWidget {
  const _NicknameEditorSheet({required this.initialNickname});

  final String initialNickname;

  @override
  State<_NicknameEditorSheet> createState() => _NicknameEditorSheetState();
}

class _NicknameEditorSheetState extends State<_NicknameEditorSheet> {
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
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
            Text('Tên hiển thị', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'Tên hiển thị trong Club',
              ),
              onSubmitted: (_) =>
                  Navigator.of(context).pop(_nicknameController.text),
            ),
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
                    onPressed: () =>
                        Navigator.of(context).pop(_nicknameController.text),
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

class _AccountHeader extends ConsumerStatefulWidget {
  const _AccountHeader({required this.profile, required this.onEdit});
  const _AccountHeader.loading() : profile = null, onEdit = null;

  final UserProfile? profile;
  final VoidCallback? onEdit;

  @override
  ConsumerState<_AccountHeader> createState() => _AccountHeaderState();
}

class _AccountHeaderState extends ConsumerState<_AccountHeader> {
  bool _uploadingAvatar = false;
  bool _updatingVisibility = false;

  Future<void> _pickAvatar() async {
    final profile = widget.profile;
    if (profile == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await ref.read(avatarRepositoryProvider).pickAndUpload();
      if (url == null) return;
      await ref
          .read(memberRepositoryProvider)
          .updateCurrentProfile(
            nickname: profile.nickname?.trim().isNotEmpty == true
                ? profile.nickname!.trim()
                : profile.displayName,
            avatarUrl: url,
            visibility: profile.visibility,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể đổi avatar: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _toggleVisibility(ProfileVisibility visibility) async {
    final profile = widget.profile;
    if (profile == null || visibility == profile.visibility) return;
    setState(() => _updatingVisibility = true);
    try {
      await ref
          .read(memberRepositoryProvider)
          .updateCurrentProfile(
            nickname: profile.nickname?.trim().isNotEmpty == true
                ? profile.nickname!.trim()
                : profile.displayName,
            avatarUrl: profile.avatarUrl,
            visibility: visibility,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể đổi chế độ hiển thị: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingVisibility = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.profile;
    final avatarUrl = user?.avatarUrl;
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: user == null || _uploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 31,
                      backgroundColor: palette.secondary.withValues(
                        alpha: 0.18,
                      ),
                      backgroundImage: avatarUrl == null
                          ? null
                          : cachedAvatarImage(context, avatarUrl, 62),
                      child: _uploadingAvatar
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : avatarUrl == null
                          ? Icon(
                              user == null
                                  ? Icons.person_outline
                                  : Icons.person,
                              color: palette.secondary,
                            )
                          : null,
                    ),
                    if (user != null && !_uploadingAvatar)
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: palette.accent,
                        child: const Icon(
                          Icons.edit,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
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
                tooltip: 'Hồ sơ & thành tích',
                onPressed: widget.onEdit,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (user != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Hiển thị Club',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
                const Spacer(),
                if (_updatingVisibility)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  SegmentedButton<ProfileVisibility>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: ProfileVisibility.private,
                        icon: Icon(Icons.lock_outline, size: 16),
                        label: Text('Private'),
                      ),
                      ButtonSegment(
                        value: ProfileVisibility.public,
                        icon: Icon(Icons.public, size: 16),
                        label: Text('Public'),
                      ),
                    ],
                    selected: {user.visibility},
                    onSelectionChanged: (selection) =>
                        _toggleVisibility(selection.single),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _accountSubtitle(UserProfile? user) {
    if (user == null) return 'Google account';
    final parts = [
      if (user.email != null) user.email!,
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

IconData _elementIcon(RunNowElement element) => switch (element) {
  RunNowElement.metal => Icons.diamond_outlined,
  RunNowElement.wood => Icons.park_outlined,
  RunNowElement.water => Icons.water_drop_outlined,
  RunNowElement.fire => Icons.local_fire_department_outlined,
  RunNowElement.earth => Icons.landscape_outlined,
};

/// Logo "Powered by Strava" chính thức, lấy nguyên từ bộ brand asset của
/// Strava (`assets/strava/`). Guideline cấm vẽ lại hay chỉnh sửa logo, nên
/// ở đây chỉ đổi giữa bản cam (nền sáng) và bản trắng (nền tối).
class _PoweredByStrava extends StatelessWidget {
  const _PoweredByStrava();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          isDark
              ? 'assets/strava/api_logo_pwrdBy_strava_horiz_white.png'
              : 'assets/strava/api_logo_pwrdBy_strava_horiz_orange.png',
          height: 20,
          semanticLabel: 'Powered by Strava',
        ),
      ),
    );
  }
}

/// Nút "Connect with Strava" chính thức — bắt buộc dùng ảnh nút do Strava
/// cấp, không được tự dựng nút tương tự.
class _ConnectWithStravaButton extends StatelessWidget {
  const _ConnectWithStravaButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'assets/strava/btn_strava_connect_with_orange.png',
              height: 48,
              semanticLabel: 'Connect with Strava',
            ),
          ),
        ),
      ),
    );
  }
}

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
