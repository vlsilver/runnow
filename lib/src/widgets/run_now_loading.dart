import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

const _loadingMarkAsset = 'assets/brand/3i-mark-transparent.png';

class RunNowLoading extends StatefulWidget {
  const RunNowLoading({
    this.label = 'Đang tải',
    this.compact = false,
    this.revealDelay = Duration.zero,
    super.key,
  });

  final String label;
  final bool compact;
  final Duration revealDelay;

  @override
  State<RunNowLoading> createState() => _RunNowLoadingState();
}

class _RunNowLoadingState extends State<RunNowLoading>
    with TickerProviderStateMixin {
  late final AnimationController _markController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  late final Animation<double> _markProgress = CurvedAnimation(
    parent: _markController,
    curve: Curves.easeInOutCubic,
  );

  Timer? _revealTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.revealDelay == Duration.zero) {
      _reveal();
      return;
    }
    _revealTimer = Timer(widget.revealDelay, _reveal);
  }

  void _reveal() {
    if (!mounted) return;
    setState(() => _visible = true);
    _markController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _markController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final markSize = widget.compact ? 40.0 : 76.0;
    return Center(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: _visible ? 1 : 0.94,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _markProgress,
                child: Image.asset(
                  _loadingMarkAsset,
                  width: markSize,
                  height: markSize,
                  color: palette.accent,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.medium,
                ),
                builder: (context, child) {
                  final progress = _markProgress.value;
                  return Opacity(
                    opacity: 0.72 + (progress * 0.28),
                    child: Transform.translate(
                      offset: Offset(0, 2 - (progress * 4)),
                      child: Transform.scale(
                        scale: 0.96 + (progress * 0.08),
                        child: child,
                      ),
                    ),
                  );
                },
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 14),
                Text(
                  widget.label.toUpperCase(),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
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
