import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:myrun/src/config.dart';
import 'package:myrun/src/providers.dart';

/// Trang chi tiết hoạt động ở dạng TỐI GIẢN cho khách CHƯA đăng nhập, mở từ
/// link chia sẻ (Telegram). Chỉ hiện vài số cơ bản (đọc từ endpoint public,
/// không cần đăng nhập) + nút đăng nhập để xem bản đầy đủ (bản đồ, biểu đồ…).
/// Khi đăng nhập xong, [ActivitySharePage] tự chuyển sang [ActivityDetailScreen].
class PublicActivityScreen extends ConsumerStatefulWidget {
  const PublicActivityScreen({
    super.key,
    required this.uid,
    required this.activityId,
  });

  final String uid;
  final String activityId;

  @override
  ConsumerState<PublicActivityScreen> createState() =>
      _PublicActivityScreenState();
}

class _PublicActivityScreenState extends ConsumerState<PublicActivityScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final uri = Uri.parse(
      '${AppConfig.runNowApiBaseUrl}/v1/public/activities/'
      '${Uri.encodeComponent(widget.uid)}/'
      '${Uri.encodeComponent(widget.activityId)}/summary',
    );
    final res = await http.get(uri);
    if (res.statusCode == 404) {
      throw 'Không tìm thấy hoạt động này.';
    }
    if (res.statusCode != 200) {
      throw 'Không tải được (mã ${res.statusCode}).';
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<Map<String, dynamic>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snap.hasError) {
                        return _MessageCard(text: '${snap.error}');
                      }
                      return _ActivityCard(data: snap.data!);
                    },
                  ),
                  const SizedBox(height: 16),
                  const _LoginPrompt(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Khối kêu gọi đăng nhập để mở bản đầy đủ. Dùng lại authController như màn
/// onboarding; đăng nhập xong luồng auth đổi → [ActivitySharePage] tự chuyển
/// sang màn chi tiết đầy đủ ngay tại URL này, không cần điều hướng.
class _LoginPrompt extends ConsumerWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.watch(authControllerProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Đăng nhập để xem đầy đủ',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bản đồ lộ trình, biểu đồ nhịp tim & pace, splits…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.loading ? null : controller.signIn,
              icon: controller.loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(
                controller.loading ? 'Đang đăng nhập…' : 'Đăng nhập',
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.data});
  final Map<String, dynamic> data;

  String _s(String key) => (data[key] as String?)?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final emoji = _s('sportEmoji');
    final verb = _s('sportVerb');
    final rows = <_Stat>[
      _Stat('Quãng đường', _s('distance')),
      _Stat('Thời gian', _s('duration')),
      _Stat(_s('paceLabel'), _s('paceValue')),
      if (_s('elevation').isNotEmpty) _Stat('Độ cao', _s('elevation')),
      if (_s('startedAtDisplay').isNotEmpty)
        _Stat('Thời điểm', _s('startedAtDisplay')),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s('displayName'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'vừa hoàn thành một buổi $verb',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _s('activityName'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          for (final r in rows) ...[
            _StatRow(stat: r),
            if (r != rows.last) const Divider(height: 20),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              '3i Run',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          stat.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          stat.value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🏃', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
