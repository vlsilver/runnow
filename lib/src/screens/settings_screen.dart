import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:url_launcher/url_launcher.dart';

/// Trạng thái liên kết Telegram cho dòng Telegram. Sheet liên kết có controller
/// riêng (poll lúc chờ Start), nên đóng sheet thì đọc lại dòng này.
final _telegramStatusProvider = FutureProvider.autoDispose<TelegramLinkStatus>(
  retry: (_, _) => null,
  (ref) => ref.watch(runNowApiClientProvider).getTelegramLink(),
);

/// Mỗi mục một dòng có trạng thái; bấm vào mở sheet chứa các thao tác của mục
/// đó (kết nối, đồng bộ, ngắt).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(userProfileProvider);
    final themeController = ref.watch(themeControllerProvider);
    final strava = ref.watch(stravaAuthProvider);
    final stravaConnected = ref.watch(stravaConnectionProvider);
    final integrationConfig = ref.watch(integrationConfigProvider).value;
    // Ẩn Strava khi RC strava_enabled=false (app Strava đang Inactive).
    final stravaEnabled = ref.watch(stravaEnabledProvider).value ?? false;
    final health = ref.watch(healthSyncProvider);
    final garmin = ref.watch(garminAuthProvider);
    // Đang nối thì vẫn hiện dù cờ tắt, để user còn ngắt được.
    final garminVisible =
        (ref.watch(garminEnabledProvider).value ?? false) || garmin.connected;
    final telegram = ref.watch(_telegramStatusProvider);
    final googleAuth = ref.watch(authControllerProvider);
    final lastSynced = profile.value?.lastSyncedAt;
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
                data: (user) => user == null
                    ? const SizedBox.shrink()
                    : _AccountSection(profile: user),
                loading: () => const _SettingsSection(
                  title: 'Tài khoản',
                  children: [
                    _SettingsRow(
                      icon: Icons.badge_outlined,
                      title: 'Tên hiển thị',
                      value: 'Đang tải',
                    ),
                  ],
                ),
                error: (error, stack) => _SettingsSection(
                  title: 'Tài khoản',
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
                title: 'Kết nối',
                children: [
                  if (stravaEnabled)
                    _SettingsRow(
                      icon: Icons.link,
                      title: 'Strava',
                      subtitle: sync.message ?? strava.errorMessage,
                      value: strava.statusLoading
                          ? 'Đang kiểm tra'
                          : sync.syncing
                          ? 'Đang đồng bộ'
                          : stravaConnected
                          ? (lastSynced == null
                                ? 'Đã kết nối'
                                : 'Đồng bộ ${_syncedLabel(lastSynced)}')
                          : (integrationConfig?.stravaFull ?? false)
                          ? 'Hết chỗ'
                          : 'Chưa kết nối',
                      onTap: () => _showSettingsSheet(
                        context,
                        title: 'Strava',
                        child: const _StravaSheet(),
                      ),
                    ),
                  if (health.available)
                    _SettingsRow(
                      icon: Icons.favorite_rounded,
                      title: health.providerName,
                      subtitle: health.error,
                      value: health.busy
                          ? 'Đang xử lý'
                          : health.connected
                          ? 'Đã kết nối'
                          : 'Chưa kết nối',
                      onTap: () => _showSettingsSheet(
                        context,
                        title: health.providerName,
                        child: const _HealthSheet(),
                      ),
                    ),
                  if (garminVisible)
                    _SettingsRow(
                      icon: Icons.watch_rounded,
                      title: 'Garmin Connect',
                      subtitle: garmin.errorMessage,
                      value: garmin.statusLoading
                          ? 'Đang kiểm tra'
                          : garmin.loading
                          ? 'Đang xử lý'
                          : garmin.connected
                          ? (garmin.lastPushAt == null
                                ? 'Đã kết nối'
                                : 'Nhận ${_syncedLabel(garmin.lastPushAt!)}')
                          : 'Chưa kết nối',
                      onTap: () => _showSettingsSheet(
                        context,
                        title: 'Garmin Connect',
                        child: const _GarminSheet(),
                      ),
                    ),
                  _SettingsRow(
                    icon: Icons.send_rounded,
                    title: 'Telegram',
                    value: telegram.when(
                      data: (status) => !status.linked
                          ? 'Chưa liên kết'
                          : status.tgUsername != null
                          ? '@${status.tgUsername}'
                          : status.displayName ?? 'Đã liên kết',
                      loading: () => 'Đang kiểm tra',
                      error: (error, stack) => 'Chưa đọc được',
                    ),
                    onTap: () async {
                      await _showSettingsSheet(
                        context,
                        title: 'Telegram',
                        child: const TelegramLinkSettings(),
                      );
                      if (context.mounted) {
                        ref.invalidate(_telegramStatusProvider);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: 'Hiển thị',
                children: [
                  _SettingsRow(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Ngũ hành',
                    value:
                        '${themeController.element.label} · '
                        '${themeController.appearance.label}',
                    onTap: () => _editElement(context, ref, themeController),
                  ),
                  _SettingsRow(
                    icon: Icons.palette_outlined,
                    title: 'Bộ màu thẻ',
                    value: runCardSkinLabel(
                      ref.watch(runCardSkinControllerProvider).choice,
                    ),
                    onTap: () => showRunCardSkinSheet(context),
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
                  _SettingsRow(
                    icon: Icons.gavel_rounded,
                    title: 'Điều khoản sử dụng',
                    onTap: () => _openWebDocument('terms.html'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                children: [
                  _SettingsRow(
                    icon: Icons.logout,
                    title: 'Đăng xuất',
                    value: googleAuth.loading ? 'Đang xử lý' : null,
                    destructive: true,
                    onTap: googleAuth.loading ? null : googleAuth.signOut,
                  ),
                  if (googleAuth.errorMessage != null)
                    _SettingsMessage(message: googleAuth.errorMessage!),
                ],
              ),
              const SizedBox(height: 18),
              const _DeleteAccountSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// `10:12` nếu là hôm nay, không thì `24/10`.
String _syncedLabel(DateTime at) {
  final now = DateTime.now();
  final today =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return today
      ? DateFormat('HH:mm').format(at)
      : DateFormat('dd/MM').format(at);
}

Future<void> _showSettingsSheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Padding(
    padding: EdgeInsets.fromLTRB(
      14,
      0,
      14,
      MediaQuery.viewInsetsOf(context).bottom + 12,
    ),
    child: GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            child,
          ],
        ),
      ),
    ),
  ),
);

/// Thao tác Strava. Chưa kết nối thì phải dùng đúng nút "Connect with Strava"
/// chính thức; đã kết nối thì là đồng bộ và ngắt.
class _StravaSheet extends ConsumerWidget {
  const _StravaSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final strava = ref.watch(stravaAuthProvider);
    final connected = ref.watch(stravaConnectionProvider);
    final config = ref.watch(integrationConfigProvider).value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strava.statusLoading)
          const _SettingsRow(
            icon: Icons.link,
            title: 'Strava',
            value: 'Đang kiểm tra',
          )
        else if (connected) ...[
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
          _SettingsRow(
            icon: Icons.history,
            title: 'Đồng bộ toàn bộ lịch sử',
            value: sync.syncing ? 'Đang chạy' : null,
            onTap: sync.syncing
                ? null
                : () => ref
                      .read(syncControllerProvider)
                      .startBackgroundSync(force: true, fullResync: true),
          ),
          _SettingsRow(
            icon: Icons.link_off,
            title: 'Ngắt kết nối Strava',
            value: strava.loading ? 'Đang xử lý' : null,
            destructive: true,
            onTap: strava.loading ? null : strava.disconnect,
          ),
        ] else if (config?.stravaFull ?? false)
          // Đủ chỗ (app chưa được Strava review) → không nhận kết nối mới.
          _SettingsRow(
            icon: Icons.lock_clock_outlined,
            title: 'Strava',
            subtitle:
                'Đã đủ ${config!.stravaCount}/${config.stravaMax} chỗ. '
                '3i đang chờ Strava duyệt để mở thêm — tạm thời chưa nhận kết nối mới.',
          )
        else
          _ConnectWithStravaButton(
            onTap: strava.loading ? null : strava.connect,
          ),
        if (strava.errorMessage != null)
          _SettingsMessage(message: strava.errorMessage!),
        if (sync.message != null) _SettingsMessage(message: sync.message!),
        const _PoweredByStrava(),
      ],
    );
  }
}

/// Thao tác Garmin Connect. Garmin tự đẩy buổi mới về nên không có nút đồng bộ.
/// Câu đồng ý nêu rõ 3i bot (Gemini) đọc số liệu Garmin: bấm nối là đồng ý,
/// ngắt kết nối là rút lại.
class _GarminSheet extends ConsumerWidget {
  const _GarminSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final garmin = ref.watch(garminAuthProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (garmin.statusLoading)
          const _SettingsRow(
            icon: Icons.watch_rounded,
            title: 'Garmin Connect',
            value: 'Đang kiểm tra',
          )
        else if (garmin.connected) ...[
          const _SettingsMessage(
            message:
                'Buổi chạy, đi bộ mới trên Garmin Connect tự về 3i sau khi '
                'đồng hồ đồng bộ, không cần bấm gì.',
          ),
          _SettingsRow(
            icon: Icons.link_off,
            title: 'Ngắt kết nối Garmin',
            value: garmin.loading ? 'Đang xử lý' : null,
            destructive: true,
            onTap: garmin.loading ? null : garmin.disconnect,
          ),
        ] else ...[
          const _SettingsMessage(
            message:
                '3i nhận buổi chạy, đi bộ từ Garmin Connect: giờ bắt đầu, '
                'quãng đường, thời gian, nhịp tim, cadence và tên đồng hồ. '
                'Số liệu này được tính vào bảng xếp hạng, kèo, và 3i bot '
                '(chạy trên Google Gemini) dùng nó để trả lời, nhận xét buổi '
                'chạy. Ngắt kết nối lúc nào cũng được.',
          ),
          _SettingsRow(
            icon: Icons.watch_rounded,
            title: 'Đồng ý và nối Garmin',
            value: garmin.loading ? 'Đang xử lý' : null,
            onTap: garmin.loading ? null : garmin.connect,
          ),
        ],
        if (garmin.errorMessage != null)
          _SettingsMessage(message: garmin.errorMessage!),
      ],
    );
  }
}

/// Thao tác Apple Health (iOS) / Health Connect (Android).
class _HealthSheet extends ConsumerWidget {
  const _HealthSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthSyncProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!health.connected)
          _SettingsRow(
            icon: Icons.favorite_rounded,
            title: 'Kết nối ${health.providerName}',
            subtitle: 'Đồng bộ buổi chạy từ app Sức khoẻ',
            value: health.busy ? 'Đang xử lý' : null,
            onTap: health.busy
                ? null
                : () => ref.read(healthSyncProvider).connect(),
          )
        else ...[
          _SettingsRow(
            icon: Icons.sync,
            title: 'Đồng bộ ${health.providerName}',
            value: health.busy ? 'Đang chạy' : null,
            onTap: health.busy
                ? null
                : () => ref.read(healthSyncProvider).sync(),
          ),
          _SettingsRow(
            icon: Icons.link_off,
            title: 'Ngắt ${health.providerName}',
            destructive: true,
            onTap: health.busy
                ? null
                : () => ref.read(healthSyncProvider).disconnect(),
          ),
        ],
        _SettingsRow(
          icon: Icons.help_outline_rounded,
          title: 'Hướng dẫn kết nối',
          subtitle: 'Các bước cấp quyền ${health.providerName}',
          onTap: () => _openWebDocument(
            'connect-health?platform='
            '${defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'}',
          ),
        ),
        if (health.error != null) _SettingsMessage(message: health.error!),
      ],
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
                      icon: element.icon,
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

/// Tài khoản: tên, ảnh và có hiện hồ sơ trong Club không, mỗi mục một dòng.
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _uploadingAvatar = false;
  bool _updatingVisibility = false;

  String get _nickname => widget.profile.nickname?.trim().isNotEmpty == true
      ? widget.profile.nickname!.trim()
      : widget.profile.displayName;

  Future<void> _pickAvatar() async {
    final profile = widget.profile;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await ref.read(avatarRepositoryProvider).pickAndUpload();
      if (url == null) return;
      await ref
          .read(memberRepositoryProvider)
          .updateCurrentProfile(
            nickname: _nickname,
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

  Future<void> _setVisibility(ProfileVisibility visibility) async {
    final profile = widget.profile;
    if (visibility == profile.visibility) return;
    setState(() => _updatingVisibility = true);
    try {
      await ref
          .read(memberRepositoryProvider)
          .updateCurrentProfile(
            nickname: _nickname,
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
    final profile = widget.profile;
    final palette = context.runNowPalette;
    final avatarUrl = profile.avatarUrl;
    return _SettingsSection(
      title: 'Tài khoản',
      children: [
        _SettingsRow(
          icon: Icons.badge_outlined,
          title: 'Tên hiển thị',
          value: _nickname,
          onTap: () => _editNickname(context, ref, profile),
        ),
        ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          minLeadingWidth: 28,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: palette.secondary.withValues(alpha: 0.18),
            backgroundImage: avatarUrl == null
                ? null
                : cachedAvatarImage(context, avatarUrl, 30),
            child: avatarUrl == null
                ? Icon(Icons.person, size: 16, color: palette.secondary)
                : null,
          ),
          title: const Text('Ảnh đại diện'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _uploadingAvatar ? 'Đang tải lên' : 'Đổi ảnh',
                style: TextStyle(color: palette.textMuted, fontSize: 15),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
          onTap: _uploadingAvatar ? null : _pickAvatar,
        ),
        SwitchListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          secondary: _SettingsIcon(
            icon: Icons.public_rounded,
            color: Theme.of(context).colorScheme.secondary,
          ),
          title: const Text('Hiện hồ sơ trong Club'),
          subtitle: const Text('Tắt thì chỉ mình bạn xem được buổi chạy'),
          value: profile.visibility == ProfileVisibility.public,
          onChanged: _updatingVisibility
              ? null
              : (on) => _setVisibility(
                  on ? ProfileVisibility.public : ProfileVisibility.private,
                ),
        ),
      ],
    );
  }
}

/// Liên kết Telegram trong Cài đặt, để liên kết được cả khi chưa có ván Ma Sói
/// nào (màn ván chỉ hiện lúc đang đăng ký). Admin cũng cần liên kết thì mới
/// nhận được báo cáo chat và cảnh báo của ván.
class TelegramLinkSettings extends ConsumerStatefulWidget {
  const TelegramLinkSettings({super.key, this.openUrl});

  /// Thay cho launchUrl trong test.
  final UrlOpener? openUrl;

  @override
  ConsumerState<TelegramLinkSettings> createState() =>
      _TelegramLinkSettingsState();
}

class _TelegramLinkSettingsState extends ConsumerState<TelegramLinkSettings>
    with WidgetsBindingObserver {
  late final TelegramLinkController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TelegramLinkController(
      api: ref.read(runNowApiClientProvider),
      openUrl: widget.openUrl,
    );
    WidgetsBinding.instance.addObserver(this);
    _controller.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Bấm Start bên Telegram rồi quay lại, kể cả sau khi hết 2 phút poll.
    if (state == AppLifecycleState.resumed) _controller.onResume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final message = error is RunNowApiException
          ? error.message
          : error is StateError
          ? error.message
          : 'Không kết nối được, thử lại sau.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final status = _controller.status;
        final busy = _controller.busy;
        if (status == null) {
          return _controller.error == null
              ? const _SettingsRow(
                  icon: Icons.send_rounded,
                  title: 'Telegram',
                  value: 'Đang kiểm tra',
                )
              : _SettingsRow(
                  icon: Icons.send_rounded,
                  title: 'Telegram',
                  subtitle: 'Chưa đọc được trạng thái. Chạm để thử lại.',
                  onTap: _controller.load,
                );
        }
        if (!status.linked) {
          return _SettingsRow(
            icon: Icons.send_rounded,
            title: 'Liên kết Telegram',
            subtitle: _controller.waiting
                ? 'Bấm Start trong Telegram rồi quay lại đây.'
                : 'Nhận lá bài và lượt chơi Ma Sói qua bot 3i',
            value: busy ? 'Đang xử lý' : null,
            onTap: busy ? null : () => _guard(_controller.link),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SettingsRow(
              icon: Icons.send_rounded,
              title: 'Telegram',
              value: status.tgUsername != null
                  ? '@${status.tgUsername}'
                  : status.displayName ?? 'Đã liên kết',
            ),
            _SettingsDivider(),
            _SettingsRow(
              icon: Icons.link_off,
              title: 'Huỷ liên kết Telegram',
              destructive: true,
              onTap: busy ? null : () => _guard(_controller.unlink),
            ),
          ],
        );
      },
    );
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

/// Mục xoá tài khoản vĩnh viễn.
///
/// Google Play và App Store đều bắt buộc app cho tạo tài khoản phải có
/// đường xoá tài khoản ngay trong app, và trang
/// threei.run/delete-account mô tả đúng các bước dưới đây — sửa chỗ này
/// thì phải sửa cả trang đó.
class _DeleteAccountSection extends ConsumerStatefulWidget {
  const _DeleteAccountSection();

  @override
  ConsumerState<_DeleteAccountSection> createState() =>
      _DeleteAccountSectionState();
}

class _DeleteAccountSectionState extends ConsumerState<_DeleteAccountSection> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Vùng nguy hiểm',
      children: [
        _SettingsRow(
          icon: Icons.delete_forever_outlined,
          title: 'Xoá tài khoản',
          subtitle: 'Xoá vĩnh viễn tài khoản và toàn bộ dữ liệu của bạn',
          value: _busy ? 'Đang xoá' : null,
          destructive: true,
          onTap: _busy ? null : _confirmAndDelete,
        ),
        if (_error != null) _SettingsMessage(message: _error!),
      ],
    );
  }

  Future<void> _confirmAndDelete() async {
    // Hai bước xác nhận vì thao tác này không hoàn tác được: bước một giải
    // thích hậu quả, bước hai buộc bấm thêm lần nữa.
    final understood = await _showWarning();
    if (!understood || !mounted) return;
    final confirmed = await _showFinalConfirm();
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(runNowApiClientProvider).deleteAccount();
      if (!mounted) return;
      // Đăng xuất để _AuthGate đưa về màn hình đăng nhập. Tài khoản Firebase
      // đã bị xoá nên phiên hiện tại không dùng được nữa.
      await ref.read(authControllerProvider).signOut();
    } catch (error) {
      debugPrint('Xoá tài khoản thất bại: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Không xoá được tài khoản. Kiểm tra kết nối mạng rồi thử lại, '
            'hoặc gửi yêu cầu tới ${AppConfig.webBaseUrl}/delete-account';
      });
    }
  }

  Future<bool> _showWarning() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tài khoản?'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Những dữ liệu sau sẽ bị xoá vĩnh viễn:'),
              SizedBox(height: 10),
              Text('• Toàn bộ buổi chạy, tuyến đường GPS và ảnh đính kèm'),
              Text('• Thống kê, tiến độ hành trình và bảng xếp hạng'),
              Text('• Kèo chạy bạn đã tạo hoặc tham gia'),
              Text('• Liên kết Strava (token sẽ bị thu hồi)'),
              Text('• Tài khoản đăng nhập của bạn'),
              SizedBox(height: 12),
              Text('Dữ liệu trên tài khoản Strava của bạn không bị ảnh hưởng.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showFinalConfirm() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận lần cuối'),
        content: const Text(
          'Thao tác này không thể hoàn tác. Dữ liệu đã xoá không khôi phục '
          'lại được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ tài khoản'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
