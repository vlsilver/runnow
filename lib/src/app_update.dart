import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nhắc cập nhật app khi bản đang chạy cũ hơn bản trên store. Mọi giá trị đọc
/// từ Remote Config (tách iOS/Android bằng điều kiện device.os ở console), nên
/// ra bản mới chỉ cần sửa console, không phải build lại:
/// - `app_latest_version`: app cũ hơn thì hiện popup, có nút "Để sau".
/// - `app_min_version`: app cũ hơn thì popup không đóng được. Chỉ nâng khi bản
///   cũ không chạy được nữa, và chỉ sau khi bản mới đã lên store.
/// - `app_store_url`: link store; trống thì dùng link mặc định của platform.
/// So theo version name (`1.5.0`), bỏ build number, nên mỗi lần ra store phải
/// tăng version name. Giá trị trống hay sai dạng thì không nhắc: Remote Config
/// lỗi không được chặn ai.
class AppUpdateConfig {
  const AppUpdateConfig({this.latest = '', this.min = '', this.storeUrl = ''});

  final String latest;
  final String min;
  final String storeUrl;

  @override
  String toString() =>
      'AppUpdateConfig(latest: $latest, min: $min, storeUrl: $storeUrl)';
}

const _defaultStoreUrls = {
  TargetPlatform.iOS: 'https://apps.apple.com/app/id6793645504',
  TargetPlatform.android:
      'https://play.google.com/store/apps/details?id=com.threei.run',
};

/// So hai version theo từng số; thiếu số thì coi là 0, phần `+build` bỏ qua.
/// Trả null khi một bên sai dạng.
int? compareVersions(String a, String b) {
  List<int>? parse(String v) {
    final parts = v.trim().split('+').first.split('.');
    final out = <int>[];
    for (final p in parts) {
      if (p.isEmpty || p.contains(RegExp(r'[^0-9]'))) return null;
      out.add(int.parse(p));
    }
    return out;
  }

  final x = parse(a), y = parse(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Version name của gói app đang chạy, ví dụ `1.5.0`.
final currentAppVersionProvider = FutureProvider<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});

final appUpdateConfigProvider = StreamProvider<AppUpdateConfig>((ref) async* {
  if (kIsWeb) {
    // Web luôn chạy bản mới nhất.
    yield const AppUpdateConfig();
    return;
  }
  final rc = FirebaseRemoteConfig.instance;
  String value(String key) {
    try {
      final v = rc.getValue(key);
      return v.source == ValueSource.valueStatic ? '' : v.asString().trim();
    } catch (_) {
      return '';
    }
  }

  AppUpdateConfig read() {
    final url = value('app_store_url');
    return AppUpdateConfig(
      latest: value('app_latest_version'),
      min: value('app_min_version'),
      storeUrl: url.isNotEmpty
          ? url
          : _defaultStoreUrls[defaultTargetPlatform] ?? '',
    );
  }

  yield read();
  try {
    // main() fetch ở nền, xong cũng không báo qua onConfigUpdated. Gọi lại thì
    // còn trong minimumFetchInterval nên chỉ activate bản đã tải, không gọi mạng.
    await rc.fetchAndActivate();
    yield read();
    await for (final _ in rc.onConfigUpdated) {
      await rc.activate();
      yield read();
    }
  } catch (error) {
    debugPrint('AppUpdate: đọc Remote Config lỗi: $error');
  }
});

/// Mở app thì hiện popup cập nhật nếu bản đang chạy cũ. Mỗi lần mở app hỏi
/// một lần; bấm "Để sau" thì lần mở sau mới hỏi lại.
class AppUpdatePrompt extends ConsumerStatefulWidget {
  const AppUpdatePrompt({super.key, required this.child, this.openUrl});

  final Widget child;

  /// Thay cho launchUrl trong test.
  final Future<bool> Function(Uri uri)? openUrl;

  @override
  ConsumerState<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends ConsumerState<AppUpdatePrompt> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_asked || !mounted) return;
    final current = ref.read(currentAppVersionProvider).value;
    final config = ref.read(appUpdateConfigProvider).value;
    if (current == null || config == null || config.storeUrl.isEmpty) return;
    final forced = (compareVersions(current, config.min) ?? 0) < 0;
    if (!forced && (compareVersions(current, config.latest) ?? 0) >= 0) {
      return;
    }
    _asked = true;
    // Bắt buộc mà latest trống hay thấp hơn min thì nói bản min.
    final latest =
        forced && (compareVersions(config.latest, config.min) ?? -1) < 0
        ? config.min
        : config.latest;
    showDialog<void>(
      context: context,
      barrierDismissible: !forced,
      builder: (context) => PopScope(
        canPop: !forced,
        child: AlertDialog(
          title: const Text('Có bản mới'),
          content: Text(
            forced
                ? 'Bản $current không còn dùng được. Cập nhật lên $latest để tiếp tục.'
                : 'Bản $latest đã có trên cửa hàng. Cập nhật để dùng tính năng mới.',
          ),
          actions: [
            if (!forced)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Để sau'),
              ),
            FilledButton(
              onPressed: () => _openStore(context, config.storeUrl, forced),
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStore(
    BuildContext dialogContext,
    String url,
    bool forced,
  ) async {
    final open =
        widget.openUrl ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await open(Uri.parse(url));
    } catch (error) {
      debugPrint('AppUpdate: mở $url lỗi: $error');
    }
    if (!dialogContext.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Không mở được cửa hàng ứng dụng.')),
      );
      return;
    }
    // Bắt buộc cập nhật thì giữ popup: quay lại app vẫn phải cập nhật.
    if (!forced) Navigator.pop(dialogContext);
  }

  @override
  Widget build(BuildContext context) {
    // Version và Remote Config về sau frame đầu (fetch xong, đổi realtime).
    ref.listen(currentAppVersionProvider, (_, _) => _check());
    ref.listen(appUpdateConfigProvider, (_, _) => _check());
    return widget.child;
  }
}
