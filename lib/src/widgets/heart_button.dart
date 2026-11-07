import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// Nút tim kèm số người đã thả. Bấm thì tim bay lên; đã thả mà bấm lại thì gỡ,
/// trừ khi [canUnlike] tắt (tim live, rules không cho gỡ) thì bấm bao nhiêu
/// lần cũng chỉ là cổ vũ thêm.
class HeartButton extends ConsumerStatefulWidget {
  const HeartButton({
    required this.target,
    this.canUnlike = true,
    this.size = 22,
    super.key,
  });

  final String target;
  final bool canUnlike;
  final double size;

  @override
  ConsumerState<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends ConsumerState<HeartButton> {
  final List<int> _floating = [];
  var _nextFloat = 0;

  void _tap(Hearts hearts) {
    final repository = ref.read(heartRepositoryProvider);
    final unlike = hearts.mine && widget.canUnlike;
    HapticFeedback.lightImpact();
    if (!unlike) setState(() => _floating.add(_nextFloat++));
    final write = unlike
        ? repository.unlike(widget.target)
        : repository.like(widget.target);
    write.catchError((Object error) {
      debugPrint('Không ghi được tim ${widget.target}: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Không thả tim được. Thử lại nhé.')),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(heartsProvider(widget.target));
    if (async.error case final error?) {
      debugPrint('Không tải được tim ${widget.target}: $error');
    }
    final hearts = async.value ?? Hearts.empty;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = hearts.mine
        ? RunNowDataColors.heart
        : onSurface.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      label: hearts.mine ? 'Đã thả tim' : 'Thả tim',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: async.hasError
            ? () => ref.invalidate(heartsProvider(widget.target))
            : () => _tap(hearts),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    hearts.mine
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: widget.size,
                    color: color,
                  ),
                  for (final id in _floating)
                    _FloatingHeart(
                      key: ValueKey(id),
                      seed: id,
                      size: widget.size,
                      onDone: () => setState(() => _floating.remove(id)),
                    ),
                ],
              ),
              if (hearts.count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '${hearts.count}',
                  style: TextStyle(
                    color: hearts.mine ? RunNowDataColors.heart : onSurface,
                    fontSize: widget.size * 0.72,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingHeart extends StatefulWidget {
  const _FloatingHeart({
    required this.seed,
    required this.size,
    required this.onDone,
    super.key,
  });

  final int seed;
  final double size;
  final VoidCallback onDone;

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward().whenComplete(widget.onDone);

  // Mỗi tim lệch một hướng khác nhau để bấm liên tục trông như chùm tim.
  late final _drift = (widget.seed * 37 % 5 - 2) * 6.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_controller.value);
          return Transform.translate(
            offset: Offset(
              _drift * math.sin(t * math.pi),
              -widget.size * 3 * t,
            ),
            child: Opacity(
              opacity: 1 - _controller.value,
              child: Transform.scale(scale: 0.7 + 0.6 * t, child: child),
            ),
          );
        },
        child: Icon(
          Icons.favorite_rounded,
          size: widget.size,
          color: RunNowDataColors.heart,
        ),
      ),
    );
  }
}

/// Mấy avatar người đã thả tim chồng lên nhau, kèm [label]. Chưa ai thả thì ẩn.
class HeartCheerers extends ConsumerWidget {
  const HeartCheerers({
    required this.target,
    this.label = 'đang cổ vũ',
    super.key,
  });

  final String target;
  final String label;

  static const _shown = 4;
  static const _diameter = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hearts = ref.watch(heartsProvider(target)).value ?? Hearts.empty;
    if (hearts.count == 0) return const SizedBox.shrink();
    final members = {
      for (final member in ref.watch(membersProvider).value ?? const [])
        member.uid: member,
    };
    final shown = hearts.uids.take(_shown).toList();
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      children: [
        SizedBox(
          width: _diameter + (shown.length - 1) * _diameter * 0.65,
          height: _diameter,
          child: Stack(
            children: [
              for (final (index, uid) in shown.indexed)
                Positioned(
                  left: index * _diameter * 0.65,
                  child: _MiniAvatar(member: members[uid]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${hearts.count} người $label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.member});

  final MemberProfile? member;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final url = member?.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = member?.displayName ?? '';
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.background,
      ),
      child: CircleAvatar(
        radius: HeartCheerers._diameter / 2 - 1.5,
        backgroundColor: palette.accent,
        backgroundImage: hasUrl
            ? cachedAvatarImage(context, url, HeartCheerers._diameter)
            : null,
        child: hasUrl
            ? null
            : Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }
}
