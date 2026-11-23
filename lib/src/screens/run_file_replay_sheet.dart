import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_file.dart';
import 'package:myrun/src/screens/route_replay_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

/// Cho chọn một file .gpx, .tcx hay .fit rồi mở tấm xem trước. Huỷ chọn thì thôi.
Future<void> pickRunFileForReplay(BuildContext context) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: runFileExtensions,
  );
  final picked = result?.files.single;
  if (picked == null || !context.mounted) return;
  // Kiểm cỡ trước khi đọc: đọc hết file quá lớn vào bộ nhớ là đủ làm app chết.
  if (picked.size > runFileMaxBytes) return _showUnreadable(context);
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return;
  await showRunFileReplaySheet(context, bytes);
}

/// Đọc [bytes] và mở tấm xem trước; file hỏng thì báo bằng SnackBar.
Future<void> showRunFileReplaySheet(
  BuildContext context,
  Uint8List bytes,
) async {
  final RunFile run;
  try {
    run = parseRunFile(bytes);
  } on FormatException {
    return _showUnreadable(context);
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RunFileReplaySheet(run: run),
  );
}

void _showUnreadable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Không đọc được file. Cần file .gpx, .tcx hay .fit có đường chạy, '
        'dưới 32 MB.',
      ),
    ),
  );
}

/// Tấm xem trước buổi chạy đọc từ file: tuyến, số liệu, file có những gì, và
/// nút mở replay 3D. Buổi này chỉ để xem, không lưu.
class RunFileReplaySheet extends ConsumerWidget {
  const RunFileReplaySheet({required this.run, super.key});

  final RunFile run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final theme = Theme.of(context);
    final startedAt = run.startedAt?.toLocal();
    final moving = run.movingTimeSeconds;
    final can3d = hasVectorMap && vectorMapCovers(run.points);
    final muted = TextStyle(color: palette.textMuted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        gradient: LinearGradient(
          colors: [palette.glassStart, palette.glassEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: palette.radius(14),
              child: SizedBox(height: 170, child: _RoutePreview(run: run)),
            ),
            const SizedBox(height: 14),
            Text(
              run.name ?? 'Buổi chạy từ file',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            if (startedAt != null)
              Text(
                DateFormat('dd.MM.yyyy · HH:mm').format(startedAt),
                style: muted,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(
                  value: (run.distanceMeters / 1000).toStringAsFixed(2),
                  label: 'KM',
                ),
                if (moving != null && moving > 0) ...[
                  _Stat(value: formatDuration(moving), label: 'THỜI GIAN'),
                  _Stat(
                    value: formatPace(
                      moving * 1000 / run.distanceMeters,
                    ).replaceAll(' /km', ''),
                    label: '/KM',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Has(label: 'Pace', has: run.routePoints != null),
                _Has(
                  label: 'Nhịp tim',
                  has: run.streams.containsKey('heartrate'),
                ),
                _Has(label: 'Độ cao', has: run.streams.containsKey('altitude')),
                _Has(
                  label: 'Guồng chân',
                  has: run.streams.containsKey('cadence'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              can3d
                  ? 'Chỉ để xem và khoe, không cộng km vào BXH hay kèo.'
                  : 'Bản đồ 3D mới có Việt Nam, tuyến này nằm ngoài.',
              style: muted,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: can3d ? () => _open(context, ref) : null,
              icon: const Icon(Icons.view_in_ar_rounded),
              label: const Text('Xem 3D'),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final avatar = ref.read(userProfileProvider).value?.avatarUrl;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RouteReplayScreen(
          points: run.points,
          distanceMeters: run.distanceMeters,
          movingTimeSeconds: run.movingTimeSeconds,
          startedAt: run.startedAt?.toLocal(),
          avatarUrl: avatar,
          series: replaySeries(
            routePoints: run.routePoints,
            streams: run.streams,
          ),
        ),
      ),
    );
  }
}

class _RoutePreview extends StatelessWidget {
  const _RoutePreview({required this.run});

  final RunFile run;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: routeBounds(run.points),
            padding: const EdgeInsets.all(24),
            maxZoom: 16,
          ),
          backgroundColor: palette.tint,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          mapBaseLayer(context, dark: dark, around: run.points),
          PolylineLayer(
            polylines: [
              Polyline(
                points: run.points,
                color: palette.accent,
                strokeWidth: 4,
                borderColor: dark ? palette.backgroundDeep : Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: palette.narrowFont,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Một nhãn cho biết file có loại số liệu này không.
class _Has extends StatelessWidget {
  const _Has({required this.label, required this.has});

  final String label;
  final bool has;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final color = has
        ? Theme.of(context).colorScheme.onSurface
        : palette.textMuted;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: palette.radius(8),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(has ? Icons.check : Icons.remove, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nghe file .gpx, .tcx, .fit mở từ app khác (iOS "Mở bằng", Android chia sẻ) rồi hiện tấm
/// xem trước. Native giữ file tới khi lấy, nên mở app từ đầu cũng không mất.
class RunFileInbox extends StatefulWidget {
  const RunFileInbox({required this.child, super.key});

  final Widget child;

  @override
  State<RunFileInbox> createState() => _RunFileInboxState();
}

class _RunFileInboxState extends State<RunFileInbox> {
  static const _channel = MethodChannel('runnow/run_file_inbox');

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') await _take();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _take());
  }

  @override
  void dispose() {
    if (!kIsWeb) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _take() async {
    final Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>('take');
    } on MissingPluginException {
      return;
    }
    if (bytes == null || !mounted) return;
    await showRunFileReplaySheet(context, bytes);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
