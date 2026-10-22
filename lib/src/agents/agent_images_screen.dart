import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Mọi ảnh bot đã vẽ, mới trước. Kéo gần cuối thì tải trang kế.
class AgentImagesScreen extends ConsumerStatefulWidget {
  const AgentImagesScreen({super.key});

  @override
  ConsumerState<AgentImagesScreen> createState() => _AgentImagesScreenState();
}

class _AgentImagesScreenState extends ConsumerState<AgentImagesScreen> {
  final _images = <AgentImage>[];
  String? _cursor;
  bool _loading = false;
  bool _failed = false;

  /// Đã tải trang đầu chưa; chưa thì chưa biết hết ảnh hay còn.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || (_started && _cursor == null)) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(runNowApiClientProvider)
          .getAgentImages(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _images.addAll(page.images);
        _cursor = page.cursor;
        _started = true;
      });
    } catch (error) {
      debugPrint('Bot: tải ảnh bot vẽ lỗi: $error');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final image = ref.watch(agentImageBuilderProvider);
    final muted = TextStyle(color: palette.textMuted, fontSize: 14);
    final Widget footer;
    if (_failed) {
      footer = TextButton(
        onPressed: _load,
        child: const Text('Không tải được ảnh. Chạm để thử lại.'),
      );
    } else if (_loading) {
      footer = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_images.isEmpty) {
      footer = Center(child: Text('Bot chưa vẽ ảnh nào.', style: muted));
    } else {
      footer = const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh bot đã vẽ')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                // Gần cuối thì tải trước trang kế, cho kéo không bị khựng.
                if (index >= _images.length - 6 && _cursor != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_failed) _load();
                  });
                }
                final img = _images[index];
                return AgentImageTile(
                  onTap: () => showAgentImageViewer(context, ref, img),
                  child: image(img.path, full: false),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(child: footer),
          ),
        ],
      ),
    );
  }
}

/// Một ô ảnh vuông bo góc, chạm được.
class AgentImageTile extends StatelessWidget {
  const AgentImageTile({required this.child, required this.onTap, super.key});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: context.runNowPalette.ink.withValues(alpha: 0.06),
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

/// Xem một ảnh cả màn hình, phóng to được, kèm giờ bot vẽ.
Future<void> showAgentImageViewer(
  BuildContext context,
  WidgetRef ref,
  AgentImage img,
) {
  final image = ref.read(agentImageBuilderProvider);
  final at = img.at?.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: image(img.path, full: true)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (at != null)
              Positioned(
                left: 20,
                bottom: 20,
                child: Text(
                  '${two(at.day)}/${two(at.month)} '
                  '${two(at.hour)}:${two(at.minute)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
