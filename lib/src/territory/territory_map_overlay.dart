import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

/// Ba chỗ có bản đồ tuyến mà người dùng tự bật lớp ô lãnh địa. Màn Lãnh địa
/// thì luôn có ô, không theo công tắc.
enum TerritoryMapPlace {
  live('Khi chạy'),
  detail('Chi tiết buổi'),
  share('Ảnh khoe');

  const TerritoryMapPlace(this.label);

  final String label;
}

/// Công tắc lớp ô cho từng chỗ, lưu trên máy này. Mặc định bật.
class TerritoryMapPrefs extends ChangeNotifier {
  TerritoryMapPrefs({
    FlutterSecureStorage? storage,
    bool loadFromStorage = true,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    loaded = loadFromStorage ? _load() : Future.value();
  }

  /// Xong khi đã đọc công tắc trên máy; chỗ cần chốt giá trị (khoá cache ảnh
  /// khoe) chờ cái này. Không bao giờ lỗi: đọc lỗi thì giữ mặc định.
  late final Future<void> loaded;

  static String _key(TerritoryMapPlace place) =>
      'runnow_territory_map_${place.name}';

  final FlutterSecureStorage _storage;
  final _off = <TerritoryMapPlace>{};

  /// Chỗ người dùng đã bấm trong phiên này: giá trị đọc muộn từ máy không đè.
  final _chosen = <TerritoryMapPlace>{};

  bool shows(TerritoryMapPlace place) => !_off.contains(place);

  Future<void> setShows(TerritoryMapPlace place, bool on) async {
    _chosen.add(place);
    if (shows(place) == on) return;
    on ? _off.remove(place) : _off.add(place);
    notifyListeners();
    // Ghi lỗi thì công tắc vẫn đúng trong phiên này, lần mở app sau về mặc định.
    try {
      await _storage.write(key: _key(place), value: on ? '1' : '0');
    } catch (error) {
      debugPrint('lãnh địa: lưu công tắc ${place.name} lỗi: $error');
    }
  }

  Future<void> _load() async {
    var changed = false;
    for (final place in TerritoryMapPlace.values) {
      final String? stored;
      try {
        stored = await _storage.read(key: _key(place));
      } catch (error) {
        // Đọc lỗi thì giữ mặc định (bật) cho chỗ đó.
        debugPrint('lãnh địa: đọc công tắc ${place.name} lỗi: $error');
        continue;
      }
      if (_chosen.contains(place) || stored == null) continue;
      final on = stored != '0';
      if (on == shows(place)) continue;
      on ? _off.remove(place) : _off.add(place);
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

final territoryMapPrefsProvider = ChangeNotifierProvider<TerritoryMapPrefs>(
  (ref) => TerritoryMapPrefs(),
);

/// Bước đi dọc một đoạn tuyến: nhỏ hơn nhiều cạnh ô (~150 m) nên không sót
/// ô, mà tuyến thưa (thẻ chạy chỉ giữ 80 điểm) vẫn rẻ.
const _routeWalkMeters = 20.0;

/// Đoạn dài hơn thì coi là nhảy do mất tín hiệu, không đi dọc; như
/// `MaxSegmentMeters` của backend.
const _routeMaxSegmentMeters = 2000.0;

/// Các ô z18 tuyến đi qua: đi dọc từng đoạn như backend tính ô, bỏ điểm toạ
/// độ hỏng (tuyến do client gửi lên).
Set<TileXY> territoryRouteCells(List<LatLng> route) {
  // Haversine: đủ chính xác cho bước 20 m, rẻ hơn Vincenty mặc định nhiều
  // (màn chạy tính lại mỗi giây).
  const distance = Distance(calculator: Haversine());
  final cells = <TileXY>{};
  LatLng? previous;
  for (final point in route) {
    if (!point.isValid) continue;
    cells.add(tileAt(point, territoryCellZoom));
    final from = previous;
    previous = point;
    if (from == null) continue;
    final meters = distance.distance(from, point);
    if (meters <= _routeWalkMeters || meters > _routeMaxSegmentMeters) {
      continue;
    }
    final steps = (meters / _routeWalkMeters).ceil();
    for (var k = 1; k < steps; k++) {
      final t = k / steps;
      cells.add(
        tileAt(
          LatLng(
            from.latitude + t * (point.latitude - from.latitude),
            from.longitude + t * (point.longitude - from.longitude),
          ),
          territoryCellZoom,
        ),
      );
    }
  }
  return cells;
}

/// Các chunk cần đọc cho [cells], nhiều ô nhất trước; tuyến rất dài chỉ đọc
/// tối đa [territoryMaxChunks] chunk.
List<TileXY> territoryRouteChunks(Set<TileXY> cells) {
  final perChunk = <TileXY, int>{};
  for (final cell in cells) {
    perChunk.update(chunkOfCell(cell), (n) => n + 1, ifAbsent: () => 1);
  }
  return (perChunk.keys.toList()
        ..sort((a, b) => perChunk[b]!.compareTo(perChunk[a]!)))
      .take(territoryMaxChunks)
      .toList();
}

/// Lớp ô lãnh địa dưới đường chạy: các ô tuyến đi qua mà đang có chủ, tô
/// như màn Lãnh địa (của mình màu chính, người khác xanh, đậm theo km). Chỉ
/// hiện khi lãnh địa đã mở và người dùng bật cho [place]. Đặt trong
/// `FlutterMap.children`, trước lớp đường chạy.
class TerritoryRouteLayer extends ConsumerStatefulWidget {
  const TerritoryRouteLayer({
    required this.points,
    required this.place,
    this.decided = false,
    super.key,
  });

  final List<LatLng> points;
  final TerritoryMapPlace place;

  /// Nơi gọi đã chốt là vẽ (màn khoe chốt một lần cho mỗi lượt ghi): bỏ qua
  /// cờ và công tắc, để ảnh khớp khoá cache dù chúng đổi giữa chừng.
  final bool decided;

  @override
  ConsumerState<TerritoryRouteLayer> createState() =>
      _TerritoryRouteLayerState();
}

class _TerritoryRouteLayerState extends ConsumerState<TerritoryRouteLayer> {
  // Tuyến khi chạy dài thêm mỗi giây; chỉ tính lại khi tuyến đổi.
  List<LatLng>? _seen;
  int _seenLength = -1;
  LatLng? _seenLast;
  Set<TileXY> _cells = const {};
  List<TileXY> _chunks = const [];

  void _refresh(List<LatLng> points) {
    final last = points.isEmpty ? null : points.last;
    if (identical(points, _seen) ||
        (points.length == _seenLength && last == _seenLast)) {
      return;
    }
    _seen = points;
    _seenLength = points.length;
    _seenLast = last;
    _cells = territoryRouteCells(points);
    _chunks = territoryRouteChunks(_cells);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.decided) {
      // Cờ trước: lãnh địa tắt (prod) thì không tạo công tắc, không đọc máy.
      if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
        return const SizedBox.shrink();
      }
      final shows = ref.watch(
        territoryMapPrefsProvider.select((p) => p.shows(widget.place)),
      );
      if (!shows) return const SizedBox.shrink();
    }
    _refresh(widget.points);
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final mine = context.runNowPalette.accent;
    final polygons = <Polygon>[];
    for (final chunk in _chunks) {
      final cells = ref.watch(territoryChunkProvider(chunk)).value;
      for (final cell in cells ?? const <TerritoryCell>[]) {
        if (!_cells.contains(cell.tile)) continue;
        polygons.add(territoryCellPolygon(cell, myUid: myUid, mine: mine));
      }
    }
    if (polygons.isEmpty) return const SizedBox.shrink();
    return PolygonLayer(polygons: polygons);
  }
}

/// Bảng ba công tắc lớp ô, mở từ Cài đặt.
Future<void> showTerritoryMapPrefsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(territoryMapPrefsProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Ô lãnh địa',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final place in TerritoryMapPlace.values)
                  RunNowSwitchListTile(
                    title: Text(place.label),
                    value: prefs.shows(place),
                    onChanged: (on) => prefs.setShows(place, on),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );

/// Nút bật tắt lớp ô ngay trên bản đồ của [place]; cùng công tắc với Cài đặt.
/// Lãnh địa chưa mở thì không hiện. [floating] là kiểu nút sáng nổi của màn
/// chạy; mặc định là ô tối như nút phóng to ở bản đồ chi tiết buổi.
class TerritoryMapToggle extends ConsumerWidget {
  const TerritoryMapToggle({
    required this.place,
    this.floating = false,
    super.key,
  });

  final TerritoryMapPlace place;
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final prefs = ref.watch(territoryMapPrefsProvider);
    final on = prefs.shows(place);
    final palette = context.runNowPalette;
    final icon = on ? Icons.grid_view_rounded : Icons.grid_off_rounded;
    void toggle() => prefs.setShows(place, !on);
    final Widget button;
    if (floating) {
      final scheme = Theme.of(context).colorScheme;
      button = Material(
        color: scheme.surface.withValues(alpha: 0.92),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: palette.roundBorder,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: on
                  ? palette.accent
                  : scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
      );
    } else {
      button = Material(
        color: Colors.transparent,
        shape: palette.roundBorder,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: toggle,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: palette.round,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      toggled: on,
      label: 'Ô lãnh địa',
      // Một nút một câu đọc; bỏ phần đọc riêng của Tooltip và InkWell.
      excludeSemantics: true,
      child: Tooltip(
        message: on ? 'Ẩn ô' : 'Hiện ô',
        child: button,
      ),
    );
  }
}
