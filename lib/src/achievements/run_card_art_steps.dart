import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_stage.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/storage_image.dart';

typedef _T = RunNowAchievementTokens;

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

/// Phong cách vẽ theo ảnh mẫu người dùng tải lên. Backend không gửi nó trong
/// danh sách mà chỉ bật cờ [ArtStyleList.custom]; ảnh mẫu nằm ở `style.jpg`
/// của thẻ nên lệnh vẽ chỉ mang key.
const _customStyle = ArtStyle(
  key: 'custom',
  name: 'Style từ Ảnh',
  family: 'custom',
  swatch: [],
);

/// Key dùng thẳng ảnh làm nền, không qua model; backend báo bằng cờ
/// [ArtStyleList.plain].
const _plainKey = 'plain';
const _plainName = 'Không style';

/// Chip các phong cách đã dùng, xếp theo số lần dùng.
const _usedFamily = ArtStyleFamily(key: 'used', label: 'Hay dùng');

/// Số tranh đã vẽ xong theo từng phong cách trong danh sách, để đưa phong cách
/// hay dùng lên đầu. Đếm từ chính bộ thẻ nên đổi máy vẫn còn. Không đếm dùng
/// thẳng ảnh và ảnh mẫu vì hai ô đó luôn đứng đầu.
Map<String, int> runCardStyleUsage(Iterable<RunCard> cards) {
  final usage = <String, int>{};
  for (final card in cards) {
    final art = card.art;
    if (art?.status != RunCardArtStatus.done) continue;
    if (art!.style == _plainKey || art.style == _customStyle.key) continue;
    usage[art.style] = (usage[art.style] ?? 0) + 1;
  }
  return usage;
}

/// Số ký tự tối đa của mô tả thêm, đếm theo rune như runCardArtNoteMax ở
/// backend. maxLength của TextField đếm theo grapheme nên chữ có dấu tổ hợp
/// hay emoji sẽ lọt quá giới hạn của backend.
const runCardArtNoteMax = 200;

/// Câu cho người dùng khi gửi lệnh vẽ bị từ chối.
String runCardArtErrorText(RunNowApiException error) => switch (error.code) {
  'art_fixed' => 'Thẻ này đã có tranh, không vẽ lại được.',
  'art_drawing' => 'Thẻ đang vẽ một phong cách khác. Đợi vẽ xong đã.',
  'invalid_style' => 'Phong cách này vừa bị tắt. Chọn phong cách khác.',
  _ => error.message,
};

/// Các bước làm tranh nền ngay trên màn lật: chọn ảnh gốc, chọn phong cách
/// trên chính ảnh đó (không chọn cũng được), rồi xác nhận. [photos] là ảnh chụp
/// trong buổi chạy.
class RunCardArtSteps extends ConsumerStatefulWidget {
  const RunCardArtSteps({
    super.key,
    required this.card,
    required this.photos,
    required this.owner,
    required this.onClose,
  });

  final RunCard card;
  final List<ActivityPhoto> photos;
  final String owner;

  /// Về màn kết quả: bấm quay lại ở bước đầu, hay đã gửi lệnh vẽ.
  final VoidCallback onClose;

  @override
  ConsumerState<RunCardArtSteps> createState() => _RunCardArtStepsState();
}

class _RunCardArtStepsState extends ConsumerState<RunCardArtSteps> {
  static const _lastPage = 2;

  int _page = 0;

  String? _family;

  /// Phong cách đang chọn; null là chưa chọn, tức dùng thẳng ảnh nếu có ảnh.
  String? _style;

  /// Ảnh gốc đã nằm trên Storage: ảnh buổi chạy, hoặc ảnh tải lên lần hỏng
  /// trước.
  String? _photoPath;

  /// Ảnh vừa chọn trên máy, tải lên lúc gửi.
  Uint8List? _upload;

  /// Chỗ người dùng kéo ảnh tới trong khung thẻ.
  Alignment _focus = Alignment.center;

  /// Ảnh mẫu vừa chọn trên máy, tải lên `style.jpg` lúc gửi.
  Uint8List? _styleUpload;
  String? _styleUploadType;

  /// Lần vẽ theo ảnh mẫu trước hỏng mà ảnh mẫu còn trên Storage, vẽ lại được
  /// không cần tải lại.
  bool _styleKept = false;
  bool _consent = false;
  bool _sending = false;
  String? _error;
  final _note = TextEditingController();

  bool get _hasPhoto => _photoPath != null || _upload != null;
  bool get _hasStyleRef => _styleUpload != null || _styleKept;

  @override
  void initState() {
    super.initState();
    final art = widget.card.art;
    if (art?.status != RunCardArtStatus.failed) {
      _photoPath = widget.photos.firstOrNull?.storagePath;
      return;
    }
    // Vẽ hỏng thì mở lại với lựa chọn cũ; ảnh mất hay hỏng thì bỏ ảnh.
    if (art!.style != _plainKey) _style = art.style;
    if (art.reason != 'photo_missing' && art.reason != 'photo_invalid') {
      _photoPath = art.photoPath;
    }
    _styleKept =
        art.style == _customStyle.key && art.reason != 'style_photo_missing';
    _note.text = art.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final styles = ref.watch(runCardStylesProvider);
    // Các bước nằm trên màn tối nên ô nhập, ô tích cũng mặc tối.
    return Theme(
      data: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: _T.titleGold2,
          onPrimary: _T.shade,
          surface: _T.field,
          onSurface: _T.hero,
        ),
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: _T.hero, displayColor: _T.hero),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _T.hero),
        child: styles.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _T.titleGold2,
            ),
          ),
          error: (error, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Không tải được phong cách: $error',
                textAlign: TextAlign.center,
                style: stageHint,
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: stagePrimaryButton,
                onPressed: () => ref.invalidate(runCardStylesProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
          data: _body,
        ),
      ),
    );
  }

  Widget _body(ArtStyleList list) {
    final selected = _selected(list);
    return switch (_page) {
      0 => _photoStep(),
      1 => _styleStep(list, selected),
      _ => _confirmStep(selected),
    };
  }

  /// Phong cách đang chọn mà còn dùng được; backend vừa tắt hay mất ảnh mẫu
  /// thì coi như chưa chọn.
  ArtStyle? _selected(ArtStyleList list) {
    if (_style == _customStyle.key) {
      return list.custom && _hasStyleRef ? _customStyle : null;
    }
    return list.styles.where((s) => s.key == _style).firstOrNull;
  }

  void _go(int page) => setState(() {
    _page = page;
    _error = null;
    // Câu đồng ý đổi theo phong cách nên mỗi lần vào bước xác nhận phải tích lại.
    if (page == _lastPage) _consent = false;
  });

  void _back() => _page == 0 ? widget.onClose() : _go(_page - 1);

  Widget _cardView({Widget? art}) {
    return RunCardFrame(
      child: AchievementCard(
        data: runCardData(widget.card, owner: widget.owner, previewArt: art),
      ),
    );
  }

  /// Ảnh gốc đặt vào khung thẻ, đúng chỗ đã kéo; null khi không dùng ảnh.
  Widget? _photoArt({required int cacheWidth}) {
    if (_upload case final bytes?) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: _focus,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (_photoPath case final path?) {
      return StorageImage(
        path: path,
        alignment: _focus,
        cacheWidth: cacheWidth,
      );
    }
    return null;
  }

  /// Thẻ ở giữa màn, phần chọn và nav dồn xuống đáy nên nút ở nguyên một chỗ
  /// giữa các bước.
  Widget _stepLayout({
    required Widget card,
    required String title,
    required VoidCallback? onNext,
    List<Widget> below = const [],
    IconData nextIcon = Icons.chevron_right_rounded,
    String nextLabel = 'Tiếp',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Center(child: card)),
        const SizedBox(height: 12),
        ...below,
        ..._errorLine(),
        const SizedBox(height: 12),
        _nav(
          title: title,
          onNext: onNext,
          nextIcon: nextIcon,
          nextLabel: nextLabel,
        ),
      ],
    );
  }

  List<Widget> _errorLine() => [
    if (_error case final error?) ...[
      const SizedBox(height: 8),
      Text(error, textAlign: TextAlign.center, style: stageHint),
    ],
  ];

  /// Quay lại, tên bước hay tên phong cách ở giữa, đi tiếp.
  Widget _nav({
    required String title,
    required VoidCallback? onNext,
    IconData nextIcon = Icons.chevron_right_rounded,
    String nextLabel = 'Tiếp',
  }) {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Quay lại',
          constraints: const BoxConstraints.tightFor(width: 54, height: 54),
          style: IconButton.styleFrom(
            foregroundColor: _T.hero,
            side: BorderSide(color: stageLine),
          ),
          onPressed: _sending ? null : _back,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _T.hero,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i <= _lastPage; i++)
                    Container(
                      width: 18,
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == _page ? _T.titleGold2 : stageLine,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        IconButton.filled(
          tooltip: nextLabel,
          constraints: const BoxConstraints.tightFor(width: 54, height: 54),
          style: IconButton.styleFrom(
            backgroundColor: _T.titleGold2,
            foregroundColor: _T.shade,
            disabledBackgroundColor: _T.titleGold2.withValues(alpha: 0.35),
            disabledForegroundColor: _T.shade.withValues(alpha: 0.7),
          ),
          onPressed: onNext,
          icon: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _T.shade,
                  ),
                )
              : Icon(nextIcon),
        ),
      ],
    );
  }

  /// Bước chọn ảnh gốc: chạm ảnh nào thì nền thẻ đổi theo ảnh đó.
  Widget _photoStep() {
    // Ảnh tải lên lần hỏng trước không thuộc ảnh buổi chạy nhưng vẫn chọn lại
    // được.
    final runPaths = [for (final p in widget.photos) p.storagePath];
    final earlier = _photoPath != null && !runPaths.contains(_photoPath)
        ? _photoPath
        : null;
    return _stepLayout(
      card: _cardView(art: _photoArt(cacheWidth: 960)),
      title: 'Chọn ảnh gốc',
      onNext: () => _go(1),
      below: [
        SizedBox(
          height: _PhotoTile.height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _PhotoTile(
                label: 'Tải ảnh',
                selected: _upload != null,
                onTap: _pick,
                child: switch (_upload) {
                  final bytes? => Image.memory(bytes, fit: BoxFit.cover),
                  null => const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: _T.titleGold2,
                  ),
                },
              ),
              _PhotoTile(
                label: 'Không ảnh',
                selected: !_hasPhoto,
                onTap: () => _setPhoto(null),
                child: Icon(
                  Icons.hide_image_outlined,
                  color: _T.hero.withValues(alpha: 0.66),
                ),
              ),
              for (final path in [?earlier, ...runPaths])
                _PhotoTile(
                  label: path == earlier ? 'Ảnh trước' : 'Ảnh buổi chạy',
                  selected: _photoPath == path,
                  onTap: () => _setPhoto(path),
                  child: StorageImage(path: path, cacheWidth: 200),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bước chọn phong cách: ảnh gốc đã là nền thẻ và kéo chỉnh được khung ở
  /// đây. Không chọn gì thì dùng thẳng ảnh.
  Widget _styleStep(ArtStyleList list, ArtStyle? selected) {
    final usage = runCardStyleUsage(
      ref.watch(runCardsProvider).asData?.value ?? const [],
    );
    final used =
        [
          for (final s in list.styles)
            if ((usage[s.key] ?? 0) > 0) s,
        ]..sort((a, b) {
          final byUses = usage[b.key]!.compareTo(usage[a.key]!);
          return byUses != 0 ? byUses : a.name.compareTo(b.name);
        });
    final families = [
      if (used.isNotEmpty) _usedFamily,
      for (final f in list.families)
        if (list.styles.any((s) => s.family == f.key)) f,
    ];
    final selectedFamily = selected == _customStyle ? null : selected?.family;
    final family = _family ?? selectedFamily ?? families.firstOrNull?.key ?? '';
    final shown = family == _usedFamily.key
        ? used
        : [
            for (final s in list.styles)
              if (s.family == family) s,
          ];
    final canPlain = list.plain && _hasPhoto;
    return _stepLayout(
      card: GestureDetector(
        onPanUpdate: _hasPhoto ? _dragPhoto : null,
        child: _cardView(art: _stylePreview(selected)),
      ),
      title: selected?.name ?? (canPlain ? _plainName : 'Chọn style'),
      onNext: selected != null || canPlain ? () => _go(_lastPage) : null,
      below: [
        if (families.length > 1) ...[
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in families)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      showCheckmark: false,
                      selected: f.key == family,
                      onSelected: (_) => setState(() => _family = f.key),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                      backgroundColor: Colors.transparent,
                      selectedColor: _T.titleGold2,
                      side: BorderSide(
                        color: f.key == family ? _T.titleGold2 : stageLine,
                      ),
                      labelStyle: TextStyle(
                        color: f.key == family ? _T.shade : _T.hero,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: _stripHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (list.custom)
                _StripItem(
                  name: _customStyle.name,
                  selected: selected == _customStyle,
                  onTap: () => _hasStyleRef && selected != _customStyle
                      ? _chooseStyle(_customStyle.key, family)
                      : _pickStyleRef(family),
                  child: switch (_styleUpload) {
                    final bytes? => Image.memory(bytes, fit: BoxFit.cover),
                    null when _styleKept => const Icon(
                      Icons.image_outlined,
                      color: _T.titleGold2,
                    ),
                    null => const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: _T.titleGold2,
                    ),
                  },
                ),
              if (canPlain)
                _StripItem(
                  name: _plainName,
                  selected: selected == null,
                  onTap: () => _chooseStyle(null, family),
                  child: _photoArt(cacheWidth: 240)!,
                ),
              for (final style in shown)
                _StripItem(
                  name: style.name,
                  selected: style == selected,
                  uses: usage[style.key],
                  onTap: () => _chooseStyle(style.key, family),
                  child: _StyleArt(style: style, cacheWidth: 240),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _chooseStyle(String? key, String family) => setState(() {
    _style = key;
    _family = family;
    _error = null;
  });

  /// Một ngón kéo nửa thẻ là đi từ giữa ra sát mép ảnh. Ảnh cover chỉ dư một
  /// chiều nên chiều còn lại kéo không có tác dụng.
  void _dragPhoto(DragUpdateDetails details) {
    final size = context.size;
    if (size == null) return;
    setState(() {
      _focus = Alignment(
        (_focus.x - details.delta.dx / (size.width / 4)).clamp(-1.0, 1.0),
        (_focus.y - details.delta.dy / (size.height / 4)).clamp(-1.0, 1.0),
      );
    });
  }

  /// Nền xem thử. Có ảnh thì ảnh là nền, ví dụ của phong cách nằm nhỏ ở góc;
  /// không ảnh thì ví dụ của phong cách là nền.
  Widget? _stylePreview(ArtStyle? style) {
    final sample = _styleSample(style);
    final photo = _photoArt(cacheWidth: 960);
    if (photo == null) return sample;
    if (sample == null) return photo;
    return Stack(
      fit: StackFit.expand,
      children: [
        photo,
        Positioned(
          left: 14,
          top: 104,
          width: 64,
          height: 96,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _T.hero, width: 2),
            ),
            child: sample,
          ),
        ),
      ],
    );
  }

  Widget? _styleSample(ArtStyle? style) {
    if (style == null) return null;
    if (style == _customStyle) {
      return switch (_styleUpload) {
        final bytes? => Image.memory(bytes, fit: BoxFit.cover),
        null => null,
      };
    }
    return _StyleArt(style: style, cacheWidth: 480);
  }

  /// Bước xác nhận. Dùng thẳng ảnh thì không có gì gửi cho model, nên chỉ cần
  /// đồng ý về quyền dùng ảnh.
  Widget _confirmStep(ArtStyle? style) {
    final custom = style == _customStyle;
    final sendsImage = _hasPhoto || custom;
    final ready = (!sendsImage || _consent) && !_sending;
    final next = ready ? () => _send(style) : null;
    final consent = CheckboxListTile(
      value: _consent,
      onChanged: _sending
          ? null
          : (value) => setState(() => _consent = value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(
        style == null
            ? 'Tôi có quyền dùng ảnh này và người trong ảnh đồng ý.'
            : 'Tôi có quyền dùng ${_hasPhoto && custom ? 'các ảnh' : 'ảnh'} '
                  'này và người trong ảnh đồng ý. Ảnh được gửi cho Google '
                  'Gemini để vẽ tranh.',
        style: stageHint,
      ),
    );
    if (style == null) {
      return _stepLayout(
        card: _cardView(art: _photoArt(cacheWidth: 960)),
        title: _plainName,
        onNext: next,
        nextIcon: Icons.check_rounded,
        nextLabel: 'Dùng ảnh này',
        below: [consent],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final recipe = (constraints.maxHeight * 0.34).clamp(100.0, 250.0);
        final tile = Size((recipe - 22) * 2 / 3, recipe - 22);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    height: recipe,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RecipeTile(
                          size: tile,
                          label: _hasPhoto ? 'Ảnh của bạn' : '3i tự nghĩ cảnh',
                          child:
                              _photoArt(cacheWidth: 360) ??
                              const Icon(
                                Icons.auto_awesome_outlined,
                                color: _T.titleGold2,
                              ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 0, 14, 22),
                          child: Icon(Icons.add_rounded, color: _T.titleGold2),
                        ),
                        _RecipeTile(
                          size: tile,
                          label: style.name,
                          child:
                              _styleSample(style) ??
                              const Icon(
                                Icons.image_outlined,
                                color: _T.titleGold2,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (sendsImage) consent,
                  const SizedBox(height: 14),
                  TextField(
                    controller: _note,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: _T.hero),
                    inputFormatters: const [_RuneLimit(runCardArtNoteMax)],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Mô tả thêm',
                      hintText: 'VD: áo đỏ, chạy cùng chú chó, trời mưa',
                      counterText:
                          '${_note.text.runes.length}/$runCardArtNoteMax',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            ..._errorLine(),
            const SizedBox(height: 12),
            _nav(
              title: style.name,
              onNext: next,
              nextIcon: Icons.auto_awesome_rounded,
              nextLabel: 'Vẽ',
            ),
          ],
        );
      },
    );
  }

  void _setPhoto(String? path) {
    if (_sending) return;
    setState(() {
      _photoPath = path;
      _upload = null;
      _focus = Alignment.center;
      _error = null;
    });
  }

  /// Ảnh chọn trong thư viện, đã kiểm loại và cỡ; null khi huỷ hay ảnh không
  /// dùng được (lý do nằm ở [_error]).
  Future<({Uint8List bytes, String type})?> _pickImage() async {
    if (_sending) return null;
    final Uint8List? bytes;
    try {
      bytes = await ref.read(runCardPhotosProvider).pick();
    } catch (error) {
      if (!mounted) return null;
      setState(() => _error = 'Không mở được thư viện ảnh: $error');
      return null;
    }
    if (bytes == null || !mounted) return null;
    final type = runCardPhotoType(bytes);
    final error = type == null
        ? 'Chỉ dùng được ảnh JPEG hoặc PNG.'
        : bytes.length >= _maxPhotoBytes
        ? 'Ảnh quá lớn, chọn ảnh dưới 8 MB.'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return null;
    }
    return (bytes: bytes, type: type!);
  }

  Future<void> _pick() async {
    final image = await _pickImage();
    if (image == null) return;
    setState(() {
      _photoPath = null;
      _upload = image.bytes;
      _focus = Alignment.center;
      _error = null;
    });
  }

  Future<void> _pickStyleRef(String family) async {
    final image = await _pickImage();
    if (image == null) return;
    setState(() {
      _style = _customStyle.key;
      _family = family;
      _styleUpload = image.bytes;
      _styleUploadType = image.type;
      _error = null;
    });
  }

  /// Ảnh gốc được cắt đúng khung người dùng vừa xem rồi mới tải lên, nên cả
  /// model lẫn lúc dùng thẳng ảnh đều nhận cùng một khung.
  Future<String?> _uploadPhoto() async {
    if (!_hasPhoto) return null;
    final photos = ref.read(runCardPhotosProvider);
    final source = _upload ?? await photos.download(_photoPath!);
    final framed = await photos.cropToCard(source, _focus);
    return photos.upload(widget.card.id, framed, 'image/png');
  }

  Future<void> _send(ArtStyle? style) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final path = await _uploadPhoto();
      if (style == _customStyle) {
        if (_styleUpload case final bytes?) {
          await ref
              .read(runCardPhotosProvider)
              .upload(
                widget.card.id,
                bytes,
                _styleUploadType!,
                file: 'style.jpg',
              );
        }
      }
      final note = _note.text.trim();
      await ref
          .read(runNowApiClientProvider)
          .requestRunCardArt(
            widget.card.id,
            style: style?.key ?? _plainKey,
            photoPath: path,
            note: style == null || note.isEmpty ? null : note,
          );
      if (mounted) widget.onClose();
    } on RunNowApiException catch (error) {
      if (mounted) setState(() => _error = runCardArtErrorText(error));
    } catch (error) {
      if (mounted) setState(() => _error = 'Không gửi được: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// Cắt chữ gõ vào ở [max] rune. Đang gõ dở (IME tiếng Việt còn vùng
/// composing) thì để yên, gõ xong mới cắt.
class _RuneLimit extends TextInputFormatter {
  const _RuneLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid || newValue.text.runes.length <= max) {
      return newValue;
    }
    // Đã đầy mà gõ thêm thì giữ nguyên, không cắt mất đuôi chữ cũ.
    if (oldValue.text.runes.length >= max) return oldValue;
    final text = String.fromCharCodes(newValue.text.runes.take(max));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Chiều cao hàng ví dụ: ô 2:3 ngang 76 cộng tên.
const _stripHeight = 138.0;

/// Một ô trong hàng ví dụ: ảnh dáng thẻ và tên.
class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.name,
    required this.selected,
    required this.onTap,
    required this.child,
    this.uses,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Số lần đã dùng phong cách này, hiện ở góc ô.
  final int? uses;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 114,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _T.field,
                    borderRadius: radius,
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: selected ? _T.titleGold2 : stageLine,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: child),
                      if (uses case final uses?)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: _T.shade.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$uses',
                              style: const TextStyle(
                                color: _T.hero,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? _T.titleGold2 : _T.hero,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một vế của phép cộng ảnh + phong cách ở bước chọn ảnh nền.
class _RecipeTile extends StatelessWidget {
  const _RecipeTile({
    required this.size,
    required this.label,
    required this.child,
  });

  final Size size;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      child: Column(
        children: [
          Container(
            width: size.width,
            height: size.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _T.field,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: stageLine),
            ),
            child: child,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: stageHint.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Ảnh ví dụ của phong cách phủ lên nền màu đại diện, nên lúc ảnh đang tải hay
/// tải hỏng vẫn thấy màu.
class _StyleArt extends StatelessWidget {
  const _StyleArt({required this.style, required this.cacheWidth});

  final ArtStyle style;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _swatch(style),
        ),
      ),
      child: switch (style.example) {
        final path? => StorageImage(
          path: path,
          cacheWidth: cacheWidth,
          placeholder: const SizedBox.expand(),
        ),
        null => const SizedBox.expand(),
      },
    );
  }
}

/// Màu đại diện server gửi dạng `#rrggbb`; thiếu hay sai thì dùng màu nền màn.
List<Color> _swatch(ArtStyle style) {
  final colors = [
    for (final hex in style.swatch)
      if (int.tryParse(hex.replaceFirst('#', ''), radix: 16) case final v?)
        Color(0xFF000000 | v),
  ];
  return colors.length >= 2 ? colors : const [_T.graphite2, _T.field];
}

/// Một ô ảnh dáng thẻ ở bước chọn ảnh gốc. Ô không có chữ, tên chỉ cho trình
/// đọc màn hình.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  static const height = 96.0;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: height * 2 / 3,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: _T.field, borderRadius: radius),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? _T.titleGold2 : stageLine,
                width: selected ? 3 : 1,
              ),
            ),
            child: SizedBox.expand(child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
