import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/rank/reward_photo.dart';
import 'package:myrun/src/run_contracts/contract_gift.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// Tải ảnh mới chọn lên Storage rồi lưu quà qua API. Ảnh nằm dưới
/// contractGifts/{creatorUid}/{contractId}/ vì backend chỉ nhận đường dẫn đó.
Future<void> saveContractGifts(
  RunNowApiClient api, {
  required String contractId,
  required String creatorUid,
  required ContractGiftDraft draft,
}) async {
  final items = <Map<String, dynamic>>[];
  for (final item in draft.items) {
    final photos = <String>[];
    for (final photo in item.photos) {
      if (photo.path case final path?) {
        photos.add(path);
        continue;
      }
      final path = 'contractGifts/$creatorUid/$contractId/${rewardPhotoName()}';
      await FirebaseStorage.instance
          .ref(path)
          .putData(photo.bytes!, SettableMetadata(contentType: 'image/jpeg'));
      photos.add(path);
    }
    items.add({
      if (item.id.isNotEmpty) 'id': item.id,
      'name': item.name,
      'icon': item.icon,
      'slots': item.slots,
      'photos': photos,
    });
  }
  await api.setContractGifts(contractId, kind: draft.kind.value, items: items);
}

/// Sheet treo quà: chọn kiểu rồi danh sách món. Null khi đóng sheet; bản nháp
/// không món là bỏ quà. [lockedIds] là món đã treo của kèo có người tham gia:
/// giữ nguyên tên, suất, chỗ đứng, và không đổi kiểu được nữa.
Future<ContractGiftDraft?> showContractGiftEditor(
  BuildContext context, {
  ContractGiftDraft? initial,
  Set<String> lockedIds = const {},
}) {
  return showModalBottomSheet<ContractGiftDraft>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GiftEditorSheet(initial: initial, lockedIds: lockedIds),
  );
}

class _GiftEditorSheet extends StatefulWidget {
  const _GiftEditorSheet({required this.initial, required this.lockedIds});

  final ContractGiftDraft? initial;
  final Set<String> lockedIds;

  @override
  State<_GiftEditorSheet> createState() => _GiftEditorSheetState();
}

class _GiftEditorSheetState extends State<_GiftEditorSheet> {
  late ContractGiftKind? _kind = widget.initial?.kind;
  late final _locked = [
    for (final it in widget.initial?.items ?? const <ContractGiftDraftItem>[])
      if (widget.lockedIds.contains(it.id)) it,
  ];
  late final _free = [
    for (final it in widget.initial?.items ?? const <ContractGiftDraftItem>[])
      if (!widget.lockedIds.contains(it.id)) it,
  ];
  late var _page = widget.lockedIds.isEmpty ? 0 : 1;

  List<ContractGiftDraftItem> get _items => [..._locked, ..._free];

  Future<void> _editItem(int? freeIndex) async {
    final item = freeIndex == null
        ? const ContractGiftDraftItem()
        : _free[freeIndex];
    final saved = await _showItemEditor(context, item, locked: false);
    if (saved == null || !mounted) return;
    setState(() {
      if (freeIndex == null) {
        _free.add(saved);
      } else {
        _free[freeIndex] = saved;
      }
    });
  }

  Future<void> _editLocked(int index) async {
    final saved = await _showItemEditor(context, _locked[index], locked: true);
    if (saved != null && mounted) setState(() => _locked[index] = saved);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _page == 0 ? _kindPage(context) : _itemsPage(context),
      ),
    );
  }

  Widget _kindPage(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Quà cho ai?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        RadioGroup<ContractGiftKind>(
          groupValue: _kind,
          onChanged: (v) => setState(() => _kind = v),
          child: Column(
            children: [
              for (final kind in ContractGiftKind.values)
                RadioListTile<ContractGiftKind>(
                  value: kind,
                  title: Text(kind.label),
                  subtitle: Text(kind.hint),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  const ContractGiftDraft(
                    kind: ContractGiftKind.draw,
                    items: [],
                  ),
                ),
                child: const Text('Bỏ quà'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _kind == null
                    ? null
                    : () => setState(() => _page = 1),
                child: const Text('Tiếp tục'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemsPage(BuildContext context) {
    final palette = context.runNowPalette;
    final kind = _kind!;
    final slots = _items.fold(0, (sum, it) => sum + it.slots);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Quà ${kind.label.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 8),
            Text('$slots suất', style: TextStyle(color: palette.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _locked.length; i++)
          _GiftItemTile(
            item: _locked[i],
            leading: Icon(
              Icons.lock_outline,
              size: 18,
              color: palette.textMuted,
            ),
            onTap: () => _editLocked(i),
          ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) =>
              setState(() => _free.insert(to, _free.removeAt(from))),
          children: [
            for (var i = 0; i < _free.length; i++)
              Dismissible(
                key: ObjectKey(_free[i]),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => setState(() => _free.removeAt(i)),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: palette.danger,
                  child: Icon(Icons.delete_outline, color: palette.onAccent),
                ),
                child: _GiftItemTile(
                  item: _free[i],
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_indicator, color: palette.textMuted),
                  ),
                  onTap: () => _editItem(i),
                ),
              ),
          ],
        ),
        if (_items.length < contractGiftMaxItems) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _editItem(null),
            icon: const Icon(Icons.add),
            label: const Text('Thêm món'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          kind == ContractGiftKind.draw
              ? 'Bốc lần lượt theo thứ tự trên. Mỗi người trúng tối đa 1 quà.'
              : 'Hạng cao nhận món trên cùng. Mỗi người tối đa 1 quà.',
          style: TextStyle(color: palette.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _items.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(ContractGiftDraft(kind: kind, items: _items)),
          child: const Text('Xong'),
        ),
      ],
    );
  }
}

class _GiftItemTile extends StatelessWidget {
  const _GiftItemTile({
    required this.item,
    required this.leading,
    required this.onTap,
  });

  final ContractGiftDraftItem item;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          ContractGiftPhotoThumb(
            icon: item.icon,
            photo: item.photos.firstOrNull,
            size: 48,
          ),
        ],
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        item.photos.isEmpty ? 'chưa có ảnh' : '${item.photos.length} ảnh',
        style: TextStyle(color: palette.textMuted, fontSize: 12),
      ),
      trailing: Text(
        '× ${item.slots}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Ô ảnh của một món đang sửa: ảnh trên Storage, ảnh vừa chọn, hay biểu tượng.
class ContractGiftPhotoThumb extends StatelessWidget {
  const ContractGiftPhotoThumb({
    required this.icon,
    required this.photo,
    this.size = 56,
    super.key,
  });

  final String icon;
  final ContractGiftPhoto? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final placeholder = Center(
      child: Icon(
        rankRewardIcon(icon),
        size: size * 0.5,
        color: palette.accentDeep,
      ),
    );
    final photo = this.photo;
    return ClipRRect(
      borderRadius: palette.radius(12),
      child: Container(
        width: size,
        height: size,
        color: palette.wash(palette.accent, 0.12),
        child: switch (photo) {
          null => placeholder,
          ContractGiftPhoto(path: final path?) => StorageImage(
            path: path,
            cacheWidth: (size * 3).round(),
            placeholder: placeholder,
          ),
          ContractGiftPhoto(bytes: final bytes?) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
          ),
          _ => placeholder,
        },
      ),
    );
  }
}

Future<ContractGiftDraftItem?> _showItemEditor(
  BuildContext context,
  ContractGiftDraftItem item, {
  required bool locked,
}) {
  return showModalBottomSheet<ContractGiftDraftItem>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GiftItemEditor(item: item, locked: locked),
  );
}

class _GiftItemEditor extends StatefulWidget {
  const _GiftItemEditor({required this.item, required this.locked});

  final ContractGiftDraftItem item;

  /// Món đã treo của kèo có người tham gia: chỉ đổi biểu tượng và ảnh.
  final bool locked;

  @override
  State<_GiftItemEditor> createState() => _GiftItemEditorState();
}

class _GiftItemEditorState extends State<_GiftItemEditor> {
  late final _name = TextEditingController(text: widget.item.name);
  late var _item = widget.item;
  bool _picking = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    setState(() => _picking = true);
    try {
      final bytes = await pickRewardPhoto();
      if (bytes != null && mounted) {
        setState(
          () => _item = _item.copyWith(
            photos: [..._item.photos, ContractGiftPhoto.picked(bytes)],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không mở được ảnh: $error')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final locked = widget.locked;
    final name = _name.text.trim();
    final valid =
        name.isNotEmpty && name.runes.length <= rankRewardNameMaxRunes;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !locked,
              maxLength: rankRewardNameMaxRunes,
              decoration: const InputDecoration(labelText: 'Tên quà'),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in rankRewardIcons.entries)
                  ChoiceChip(
                    label: Icon(e.value, size: 20),
                    selected: _item.icon == e.key,
                    onSelected: (_) =>
                        setState(() => _item = _item.copyWith(icon: e.key)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in _item.photos)
                  Stack(
                    children: [
                      ContractGiftPhotoThumb(icon: _item.icon, photo: photo),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _item = _item.copyWith(
                              photos: [
                                for (final p in _item.photos)
                                  if (!identical(p, photo)) p,
                              ],
                            ),
                          ),
                          child: Icon(Icons.cancel, color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                if (_item.photos.length < rankRewardMaxPhotos)
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _picking ? null : _addPhoto,
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Số suất')),
                IconButton(
                  onPressed: locked || _item.slots <= 1
                      ? null
                      : () => setState(
                          () => _item = _item.copyWith(slots: _item.slots - 1),
                        ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '${_item.slots}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: locked || _item.slots >= contractGiftMaxSlots
                      ? null
                      : () => setState(
                          () => _item = _item.copyWith(slots: _item.slots + 1),
                        ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: valid && !_picking
                  ? () => Navigator.of(context).pop(_item.copyWith(name: name))
                  : null,
              child: Text(widget.item.name.isEmpty ? 'Thêm' : 'Xong'),
            ),
          ],
        ),
      ),
    );
  }
}
