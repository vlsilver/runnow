import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// Giới hạn file của storage rule cho ảnh gốc.
const _maxPhotoBytes = 8 * 1024 * 1024;

/// Loại ảnh theo vài byte đầu: backend và storage rule chỉ nhận JPEG, PNG.
String? runCardPhotoType(Uint8List bytes) {
  if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes.length > 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

/// Câu cho người dùng khi gửi lệnh vẽ bị từ chối.
String runCardArtErrorText(RunNowApiException error) => switch (error.code) {
  'art_fixed' => 'Thẻ này đã có tranh, không vẽ lại được.',
  'art_drawing' => 'Thẻ đang vẽ một phong cách khác. Đợi vẽ xong đã.',
  'invalid_style' => 'Phong cách này vừa bị tắt. Chọn phong cách khác.',
  _ => error.message,
};

/// Bảng chọn phong cách và ảnh gốc rồi gửi lệnh vẽ tranh nền cho [card].
/// [photos] là ảnh chụp trong buổi chạy, chọn làm ảnh gốc được.
Future<void> showRunCardArtSheet(
  BuildContext context, {
  required RunCard card,
  required List<ActivityPhoto> photos,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => RunCardArtSheet(card: card, photos: photos),
);

class RunCardArtSheet extends ConsumerStatefulWidget {
  const RunCardArtSheet({super.key, required this.card, required this.photos});

  final RunCard card;
  final List<ActivityPhoto> photos;

  @override
  ConsumerState<RunCardArtSheet> createState() => _RunCardArtSheetState();
}

class _RunCardArtSheetState extends ConsumerState<RunCardArtSheet> {
  String? _family;
  String? _style;

  /// Ảnh gốc đã nằm trên Storage: ảnh buổi chạy, hoặc ảnh tải lên lần vẽ hỏng
  /// trước.
  String? _photoPath;

  /// Ảnh vừa chọn trên máy, tải lên lúc bấm Vẽ.
  Uint8List? _upload;
  String? _uploadType;
  bool _consent = false;
  bool _sending = false;
  String? _error;

  bool get _hasPhoto => _photoPath != null || _upload != null;

  @override
  void initState() {
    super.initState();
    // Vẽ hỏng thì mở lại với lựa chọn cũ; ảnh mất thì bỏ ảnh.
    final art = widget.card.art;
    if (art?.status == RunCardArtStatus.failed) {
      _style = art!.style;
      if (art.reason != 'photo_missing') _photoPath = art.photoPath;
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = ref.watch(runCardStylesProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: styles.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Không tải được phong cách: $error'),
              TextButton(
                onPressed: () => ref.invalidate(runCardStylesProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(ArtStyleList list) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final families = [
      for (final f in list.families)
        if (list.styles.any((s) => s.family == f.key)) f,
    ];
    final selected = list.styles.where((s) => s.key == _style).firstOrNull;
    final family =
        _family ?? selected?.family ?? families.firstOrNull?.key ?? '';
    final shown = [
      for (final s in list.styles)
        if (s.family == family) s,
    ];
    final ready = selected != null && (!_hasPhoto || _consent) && !_sending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chọn phong cách', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Thẻ ${gameCardTiers[widget.card.tier]!.label} · vẽ một lần, '
                'xong là cố định',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in families)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: f.key == family,
                    onSelected: (_) => setState(() => _family = f.key),
                  ),
                ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              _StyleGrid(
                styles: shown,
                selected: _style,
                onTap: (key) => setState(() => _style = key),
              ),
              const SizedBox(height: 20),
              Text(
                'ẢNH GỐC (KHÔNG BẮT BUỘC)',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: muted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              _photoRow(),
              if (_hasPhoto)
                CheckboxListTile(
                  value: _consent,
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _consent = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Tôi có quyền dùng ảnh này và người trong ảnh đồng ý. '
                    'Ảnh được gửi cho Google Gemini để vẽ tranh.',
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              FilledButton.icon(
                onPressed: ready ? () => _confirm(selected) : null,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.brush_outlined),
                label: Text(
                  _sending
                      ? 'Đang gửi...'
                      : selected == null
                      ? 'Chọn một phong cách'
                      : 'Vẽ bằng ${selected.name}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _photoRow() {
    // Ảnh tải lên lần hỏng trước không thuộc ảnh buổi chạy nhưng vẫn chọn lại
    // được.
    final runPaths = [for (final p in widget.photos) p.storagePath];
    final earlier = _photoPath != null && !runPaths.contains(_photoPath)
        ? _photoPath
        : null;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _PhotoTile(
            label: 'Không ảnh',
            selected: !_hasPhoto,
            onTap: () => _setPhoto(null),
            child: const _TileHint(Icons.hide_image_outlined, 'Không ảnh'),
          ),
          for (final path in [?earlier, ...runPaths])
            _PhotoTile(
              label: path == earlier ? 'Ảnh trước' : 'Ảnh buổi chạy',
              selected: _photoPath == path,
              onTap: () => _setPhoto(path),
              child: StoragePhoto(path: path, cacheWidth: 200),
            ),
          _PhotoTile(
            label: 'Tải ảnh',
            selected: _upload != null,
            onTap: _pick,
            child: switch (_upload) {
              final bytes? => Image.memory(bytes, fit: BoxFit.cover),
              null => const _TileHint(
                Icons.add_photo_alternate_outlined,
                'Tải ảnh',
              ),
            },
          ),
        ],
      ),
    );
  }

  void _setPhoto(String? path) {
    if (_sending) return;
    setState(() {
      _photoPath = path;
      _upload = null;
      _uploadType = null;
      _consent = false;
      _error = null;
    });
  }

  Future<void> _pick() async {
    if (_sending) return;
    final Uint8List? bytes;
    try {
      bytes = await ref.read(runCardPhotosProvider).pick();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Không mở được thư viện ảnh: $error');
      return;
    }
    if (bytes == null || !mounted) return;
    final type = runCardPhotoType(bytes);
    setState(() {
      if (type == null) {
        _error = 'Chỉ dùng được ảnh JPEG hoặc PNG.';
      } else if (bytes!.length >= _maxPhotoBytes) {
        _error = 'Ảnh quá lớn, chọn ảnh dưới 8 MB.';
      } else {
        _photoPath = null;
        _upload = bytes;
        _uploadType = type;
        _consent = false;
        _error = null;
      }
    });
  }

  Future<void> _confirm(ArtStyle style) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Vẽ bằng ${style.name}?'),
        content: const Text(
          'Vẽ xong thì phong cách và tranh cố định, không đổi được nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Chọn lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Vẽ'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _send(style);
  }

  Future<void> _send(ArtStyle style) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      var path = _photoPath;
      if (_upload case final bytes?) {
        path = await ref
            .read(runCardPhotosProvider)
            .upload(widget.card.id, bytes, _uploadType!);
      }
      await ref
          .read(runNowApiClientProvider)
          .requestRunCardArt(widget.card.id, style: style.key, photoPath: path);
      if (mounted) Navigator.pop(context);
    } on RunNowApiException catch (error) {
      if (mounted) setState(() => _error = runCardArtErrorText(error));
    } catch (error) {
      if (mounted) setState(() => _error = 'Không gửi được lệnh vẽ: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// Lưới phong cách ba cột: ô dáng thẻ 2:3 (ảnh mẫu, chưa có thì màu đại
/// diện) và tên.
class _StyleGrid extends StatelessWidget {
  const _StyleGrid({
    required this.styles,
    required this.selected,
    required this.onTap,
  });

  final List<ArtStyle> styles;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - 2 * gap) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final style in styles)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  selected: style.key == selected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onTap(style.key),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: _StyleTile(
                            style: style,
                            selected: style.key == selected,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          style.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ô một phong cách: ảnh mẫu phủ lên nền màu đại diện, nên lúc ảnh đang tải
/// hay tải hỏng vẫn thấy màu.
class _StyleTile extends StatelessWidget {
  const _StyleTile({required this.style, required this.selected});

  final ArtStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _swatch(style, scheme),
            ),
          ),
          child: switch (style.example) {
            final path? => StorageImage(
              path: path,
              cacheWidth: 360,
              placeholder: const SizedBox.expand(),
            ),
            null => const SizedBox.expand(),
          },
        ),
      ),
    );
  }
}

/// Màu đại diện server gửi dạng `#rrggbb`; thiếu hay sai thì dùng màu theme.
List<Color> _swatch(ArtStyle style, ColorScheme scheme) {
  final colors = [
    for (final hex in style.swatch)
      if (int.tryParse(hex.replaceFirst('#', ''), radix: 16) case final v?)
        Color(0xFF000000 | v),
  ];
  return colors.length >= 2
      ? colors
      : [scheme.surfaceContainerHighest, scheme.surfaceContainerLow];
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TileHint extends StatelessWidget {
  const _TileHint(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
