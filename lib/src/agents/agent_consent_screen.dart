import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mở màn xin phép gửi dữ liệu cho AI. true khi người dùng đồng ý và backend
/// đã ghi; "Để sau" hay quay lại là false.
Future<bool> openAgentConsent(
  BuildContext context, {
  required int version,
  required String botName,
  required String title,
  required String action,
}) async {
  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AgentConsentScreen(
        version: version,
        botName: botName,
        title: title,
        action: action,
      ),
    ),
  );
  return agreed ?? false;
}

/// Gọi [call]. Backend đòi đồng ý AI (`consent_required`, vd. điều khoản vừa
/// lên bản mới) thì mở màn xin phép rồi gọi lại một lần. Không đồng ý thì ném
/// lỗi cũ để màn gọi báo như mọi lỗi khác.
Future<T> withAgentConsent<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function() call,
) async {
  try {
    return await call();
  } on RunNowApiException catch (error) {
    if (error.code != 'consent_required' || !context.mounted) rethrow;
    final me = ref.read(agentMeProvider).value;
    final version = error.body['consentVersion'];
    final agreed = await openAgentConsent(
      context,
      version: version is num ? version.toInt() : me?.consentVersion ?? 0,
      botName: me?.agent?.name ?? 'Bot',
      title: 'MyBot',
      action: 'Đồng ý',
    );
    if (!agreed) rethrow;
    return call();
  }
}

/// Màn xin phép trước khi bot gửi tin, tính cách, bộ nhớ, số chạy và kèo của
/// chủ cho Gemini.
/// Ghi đồng ý bằng [version] backend trả, không tự đặt số.
class AgentConsentScreen extends ConsumerStatefulWidget {
  const AgentConsentScreen({
    required this.version,
    required this.botName,
    required this.title,
    required this.action,
    super.key,
  });

  final int version;
  final String botName;
  final String title;

  /// Chữ trên nút đồng ý, vd. "Đồng ý và tạo bot".
  final String action;

  @override
  ConsumerState<AgentConsentScreen> createState() => _AgentConsentScreenState();
}

class _AgentConsentScreenState extends ConsumerState<AgentConsentScreen> {
  late int _version = widget.version;
  late bool _learn = !(ref.read(agentMeProvider).value?.noLearn ?? false);
  bool _busy = false;

  Future<void> _agree() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(runNowApiClientProvider);
    try {
      await api.recordAgentConsent(_version);
      // Sau đồng ý mới đổi tự học: lỗi ở bước này thì bấm lại, đồng ý gửi
      // lại lần hai vẫn 200 nên không sao.
      final noLearn = !_learn;
      if (noLearn != (ref.read(agentMeProvider).value?.noLearn ?? false)) {
        await api.setAgentNoLearn(noLearn);
      }
      ref.invalidate(agentMeProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on RunNowApiException catch (error) {
      if (error.code == 'consent_version_mismatch') {
        await _reloadVersion();
      } else {
        _showError(error.message);
      }
    } catch (error) {
      _showError('Không lưu được, thử lại sau.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Điều khoản lên bản mới trong lúc màn đang mở: đọc lại bản đang bắt buộc
  /// rồi để người dùng bấm lại.
  Future<void> _reloadVersion() async {
    try {
      final me = await ref.refresh(agentMeProvider.future);
      if (!mounted || me == null) return;
      if (!me.consentRequired) {
        Navigator.of(context).pop(true);
        return;
      }
      _version = me.consentVersion;
      _showError('Điều khoản vừa đổi. Đọc lại rồi bấm đồng ý.');
    } catch (error) {
      _showError('Không tải được điều khoản mới, thử lại sau.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    // Giữ hồ sơ sống trong lúc màn mở, để đọc lại được bản điều khoản.
    ref.watch(agentMeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  const Text(
                    'Trước khi bắt đầu',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.botName} chạy bằng AI.',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: palette.glassStart,
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _Point(
                            icon: Icons.send_outlined,
                            bold:
                                'Tin bạn nhắn, tính cách và bộ nhớ của bot, '
                                'số chạy và kèo của bạn được gửi tới Gemini '
                                'của Google',
                            rest:
                                ' để bot trả lời. Google không dùng dữ liệu '
                                'này để huấn luyện model.',
                          ),
                          Divider(height: 1),
                          _Point(
                            icon: Icons.groups_outlined,
                            bold: 'Trong phòng bot, mọi thành viên đọc được',
                            rest:
                                ' câu bot nói, kể cả điều bot nhớ về bạn, và '
                                'số chạy nếu hồ sơ của bạn công khai. Đừng kể '
                                'chuyện riêng tư.',
                          ),
                          Divider(height: 1),
                          _Point(
                            icon: Icons.shield_outlined,
                            bold: 'Bạn xem, sửa và xoá được mọi thứ bot nhớ.',
                            rest:
                                ' Xoá tài khoản thì bot và bộ nhớ bị xoá theo.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: palette.glassStart,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      value: _learn,
                      onChanged: _busy
                          ? null
                          : (on) => setState(() => _learn = on),
                      title: const Text(
                        'Cho bot tự học về tôi',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Bot rút ra điều đáng nhớ từ tin bạn nói trong phòng '
                        'bot và group Telegram.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('${AppConfig.webBaseUrl}/privacy.html'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Đọc chính sách quyền riêng tư'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _agree,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: Text(widget.action),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textMuted,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Để sau'),
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

/// Một ý trên màn xin phép: phần đầu in đậm, phần sau chữ thường.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.bold, required this.rest});

  final IconData icon;
  final String bold;
  final String rest;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: palette.accentDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: bold,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: rest),
                ],
              ),
              style: const TextStyle(fontSize: 14.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
