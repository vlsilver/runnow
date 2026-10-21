import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:myrun/src/widgets/map_attribution.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/route_import.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_session.dart' show haversineDistanceMeters;
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';

/// Khoảng cách tối thiểu (mét) giữa 2 điểm liên tiếp khi vẽ tự do (kéo tay) —
/// đủ mượt để bám sát đường cong nhưng không tạo quá nhiều điểm trùng lặp.
const _freehandMinPointDistanceMeters = 20.0;

/// Mặc định trung tâm bản đồ khi chưa lấy được vị trí hiện tại (Hà Nội) —
/// chỉ là điểm khởi đầu để người dùng tự kéo tới nơi muốn vẽ tuyến.
const _fallbackMapCenter = LatLng(21.0285, 105.8542);

/// Pace giả định chỉ để ước tính "phút chạy" hiển thị lúc vẽ tuyến — không
/// ảnh hưởng tới việc tính tiến độ thật.
const _assumedPaceSecondsPerKm = 370;

enum _ImportKind { gpx, svg }

class RunContractRouteCreateScreen extends ConsumerStatefulWidget {
  const RunContractRouteCreateScreen({super.key, this.journey = false});

  /// true = tạo KÈO HÀNH TRÌNH (tích luỹ km để phủ hết chiều dài cung tự vẽ),
  /// false = "Theo tuyến" (phải chạy đúng tuyến N lần). Dùng chung công cụ vẽ.
  final bool journey;

  @override
  ConsumerState<RunContractRouteCreateScreen> createState() =>
      _RunContractRouteCreateScreenState();
}

class _RunContractRouteCreateScreenState
    extends ConsumerState<RunContractRouteCreateScreen> {
  final _points = <LatLng>[];
  final _titleController = TextEditingController();
  final _mapController = MapController();
  var _step = 0;
  var _targetValue = 1.0;
  var _unlimited = false;
  var _titleEdited = false;
  var _working = false;
  var _freehand = false;
  // Hành trình: không hạn (mặc định) hoặc chọn deadline.
  var _openEnded = true;
  DateTime? _deadline;
  // Hành trình: cá nhân (mỗi người tự chinh phục) hoặc tập thể (cả nhóm gộp km).
  var _mode = RunContractMode.individual;
  String? _error;
  LatLng? _initialCenter;

  bool get _journey => widget.journey;

  @override
  void initState() {
    super.initState();
    _loadInitialCenter();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialCenter() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null || !mounted) return;

      final center = LatLng(position.latitude, position.longitude);
      setState(() => _initialCenter = center);
      // Chỉ tự bay bản đồ nếu người dùng chưa bắt đầu vẽ/di chuyển bản đồ —
      // tránh giật bản đồ ra khỏi chỗ họ đang thao tác.
      if (_points.isEmpty) {
        try {
          _mapController.move(center, 15);
        } catch (_) {
          // Map chưa attach kịp — bỏ qua, initialCenter vẫn đúng cho lần build sau.
        }
      }
    } catch (_) {
      // Best-effort: không có vị trí thì dùng mặc định, không chặn màn vẽ.
    }
  }

  void _moveTo(LatLng point) {
    try {
      _mapController.move(point, 15);
    } catch (_) {
      // Map chưa sẵn sàng — bỏ qua.
    }
  }

  double get _distanceMeters => routeLengthMeters(_points);

  bool get _canContinue => _points.length >= 2 && _distanceMeters >= 200;

  void _addPoint(LatLng point) => setState(() => _points.add(point));

  void _removePointAt(int index) => setState(() => _points.removeAt(index));

  LatLng? _offsetToLatLng(Offset localPosition) {
    try {
      return _mapController.camera.screenOffsetToLatLng(localPosition);
    } catch (_) {
      return null;
    }
  }

  /// Kéo tay để vẽ liên tục — chỉ thêm điểm mới khi đã cách điểm gần nhất
  /// tối thiểu [_freehandMinPointDistanceMeters] để tránh dồn quá nhiều điểm
  /// trùng lặp lúc kéo chậm.
  void _appendFreehandPoint(Offset localPosition) {
    final point = _offsetToLatLng(localPosition);
    if (point == null) return;
    if (_points.isNotEmpty) {
      final distance = haversineDistanceMeters(
        _points.last.latitude,
        _points.last.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < _freehandMinPointDistanceMeters) return;
    }
    setState(() => _points.add(point));
  }

  void _tapToAddFreehandPoint(Offset localPosition) {
    final point = _offsetToLatLng(localPosition);
    if (point != null) setState(() => _points.add(point));
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(_points.removeLast);
  }

  void _clear() => setState(_points.clear);

  void _fitToPoints() {
    if (_points.length < 2) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: routeBounds(_points),
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (_) {
      // Map chưa attach kịp — bỏ qua, người dùng vẫn thấy điểm vừa nạp.
    }
  }

  void _showImportError(Object error) {
    if (!mounted) return;
    final message = error is TimeoutException
        ? 'Bộ chọn file không phản hồi sau 1 phút — thử mở lại màn này '
              '(có thể do quyền truy cập file bị chặn trên máy).'
        : 'Không nhập được file: $error';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showImportMenu() async {
    final choice = await showModalBottomSheet<_ImportKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route_rounded),
              title: const Text('Nhập từ GPX'),
              subtitle: const Text('Lấy đúng track thật từ file .gpx đã có'),
              onTap: () => Navigator.of(context).pop(_ImportKind.gpx),
            ),
            ListTile(
              leading: const Icon(Icons.draw_rounded),
              title: const Text('Nhập từ SVG (vẽ theo hình)'),
              subtitle: const Text(
                'Đặt 1 hình (logo, chữ...) lên bản đồ, tự chuyển nét vẽ thành tuyến',
              ),
              onTap: () => Navigator.of(context).pop(_ImportKind.svg),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    // Đợi animation đóng bottom sheet chạy xong hẳn rồi mới mở picker native
    // — gọi ngay lúc sheet còn đang dismiss có thể khiến picker native
    // (UIDocumentPickerViewController/Intent) không trồi lên được, đứng im
    // như treo.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    if (choice == _ImportKind.gpx) await _importGpx();
    if (choice == _ImportKind.svg) await _importSvg();
  }

  Future<void> _importGpx() async {
    setState(() => _working = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      ).timeout(const Duration(seconds: 60));
      final picked = result?.files.single;
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final points = parseGpxTrack(utf8.decode(bytes));
      setState(() {
        _points
          ..clear()
          ..addAll(points);
      });
      _fitToPoints();
    } catch (error) {
      _showImportError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importSvg() async {
    setState(() => _working = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg'],
      ).timeout(const Duration(seconds: 60));
      final picked = result?.files.single;
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final shape = parseSvgPathPoints(utf8.decode(bytes));
      if (!mounted) return;
      final widthKm = await _askShapeWidthKm();
      if (widthKm == null) return;
      final center = _currentMapCenter();
      final points = projectShapeOntoMap(
        shape,
        center: center,
        targetWidthMeters: widthKm * 1000,
      );
      setState(() {
        _points
          ..clear()
          ..addAll(points);
      });
      _fitToPoints();
    } catch (error) {
      _showImportError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  LatLng _currentMapCenter() {
    try {
      return _mapController.camera.center;
    } catch (_) {
      return _initialCenter ?? _fallbackMapCenter;
    }
  }

  Future<double?> _askShapeWidthKm() async {
    final controller = TextEditingController(text: '1');
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chiều rộng thật của hình'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: 'km',
            helperText: 'Hình sẽ được đặt vào giữa bản đồ đang xem',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              Navigator.of(context).pop(parsed);
            },
            child: const Text('Đặt hình lên bản đồ'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return null;
    return value;
  }

  int _estimatedMinutes() {
    final km = _distanceMeters / 1000;
    return (km * _assumedPaceSecondsPerKm / 60).round();
  }

  void _goToConfirm() {
    if (!_canContinue) return;
    if (!_titleEdited) {
      final km = (_distanceMeters / 1000).toStringAsFixed(1);
      _titleController.text = _journey ? 'Hành trình $km km' : 'Route $km km';
    }
    setState(() => _step = 1);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(
        () => _deadline = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _journey
              ? (_step == 0 ? 'Vẽ hành trình' : 'Xác nhận hành trình')
              : (_step == 0 ? 'Vẽ tuyến đường' : 'Xác nhận tuyến'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _step == 0 ? _drawStep() : _confirmStep(),
        ),
      ),
    );
  }

  Widget _drawStep() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _RouteDrawingMap(
                  controller: _mapController,
                  points: _points,
                  initialCenter: _initialCenter ?? _fallbackMapCenter,
                  interactive: !_freehand,
                  onTap: _addPoint,
                  onLongPressPoint: _removePointAt,
                ),
              ),
              if (_freehand)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _appendFreehandPoint(details.localPosition),
                    onPanUpdate: (details) =>
                        _appendFreehandPoint(details.localPosition),
                    onTapUp: (details) =>
                        _tapToAddFreehandPoint(details.localPosition),
                  ),
                ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlaceSearchField(onSelected: _moveTo),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DrawModeToggle(
                          freehand: _freehand,
                          onChanged: (value) =>
                              setState(() => _freehand = value),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GlassPanel(
                            borderRadius: 999,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              _freehand
                                  ? 'Kéo tay để vẽ tuyến · chạm để thêm điểm lẻ'
                                  : _points.isEmpty
                                  ? 'Chạm vào bản đồ để đặt điểm mốc đầu tiên'
                                  : 'Chạm tiếp để nối điểm · giữ điểm để xoá',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: const Icon(Icons.upload_file_rounded),
                          tooltip: _journey
                              ? 'Nhập từ file GPX'
                              : 'Nhập từ file GPX/SVG',
                          // Hành trình chỉ cần cung thật → nhập GPX thẳng, bỏ SVG.
                          onPressed: _working
                              ? null
                              : (_journey ? _importGpx : _showImportMenu),
                        ),
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: const Icon(Icons.undo_rounded),
                          tooltip: 'Hoàn tác',
                          onPressed: _points.isEmpty ? null : _undo,
                        ),
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: 'Xoá hết',
                          onPressed: _points.isEmpty ? null : _clear,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GlassPanel(
                  borderRadius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RouteStat(
                          label: 'KM',
                          value: (_distanceMeters / 1000).toStringAsFixed(1),
                        ),
                      ),
                      Expanded(
                        child: _RouteStat(
                          label: 'ĐIỂM MỐC',
                          value: '${_points.length}',
                        ),
                      ),
                      Expanded(
                        child: _RouteStat(
                          label: '~PHÚT CHẠY',
                          value: '${_estimatedMinutes()}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canContinue ? _goToConfirm : null,
                    child: const Text('Tiếp tục'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _confirmStep() {
    final palette = context.runNowPalette;
    final routePoints = [
      for (final point in _points)
        RoutePoint(
          latitude: point.latitude,
          longitude: point.longitude,
          timestamp: DateTime.now(),
        ),
    ];
    final label = _unlimited ? 'không giới hạn' : '${_targetValue.toInt()} lần';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: RouteMap.fromRoutePoints(points: routePoints, height: 220),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _titleController,
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            hintText: 'Tên tuyến',
          ),
          onChanged: (_) => _titleEdited = true,
        ),
        const SizedBox(height: 4),
        Text(
          '${_points.length} điểm mốc',
          style: TextStyle(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        if (_journey)
          ..._journeyOptions(palette)
        else
          ..._routeCompletionOptions(palette, label),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _working ? null : _create,
            child: _working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_journey ? 'Chốt kèo hành trình' : 'Tạo kèo'),
          ),
        ),
      ],
    );
  }

  /// Lựa chọn cho "Theo tuyến" (routeCompletion): số lần chạy đúng tuyến.
  List<Widget> _routeCompletionOptions(RunNowPalette palette, String label) => [
    Text(
      'SỐ LẦN CẦN HOÀN THÀNH',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: 0.8,
        color: palette.textMuted,
      ),
    ),
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: _TargetChip(
            label: '1 lần',
            selected: !_unlimited && _targetValue == 1,
            onTap: () => setState(() {
              _unlimited = false;
              _targetValue = 1;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TargetChip(
            label: '3 lần',
            selected: !_unlimited && _targetValue == 3,
            onTap: () => setState(() {
              _unlimited = false;
              _targetValue = 3;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TargetChip(
            label: 'Không giới hạn',
            selected: _unlimited,
            onTap: () => setState(() {
              _unlimited = true;
              _targetValue = 1;
            }),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 18, color: palette.accentDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hoàn thành đúng tuyến ${_titleController.text.trim().isEmpty ? 'này' : _titleController.text.trim()}, '
              '$label trong tuần này để được cứu.',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  ];

  /// Lựa chọn cho KÈO HÀNH TRÌNH: mục tiêu = độ dài cung (tự động), + thời hạn
  /// (không hạn hoặc chọn ngày). Tích luỹ km để phủ hết cung.
  List<Widget> _journeyOptions(RunNowPalette palette) {
    final km = (_distanceMeters / 1000);
    return [
      GlassPanel(
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.straighten_rounded, color: palette.accentDeep),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Mục tiêu tích luỹ',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${km.toStringAsFixed(km >= 100 ? 0 : 1)} km',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: palette.accentDeep,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'CHẾ ĐỘ',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.8,
          color: palette.textMuted,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _TargetChip(
              label: 'Cá nhân',
              selected: _mode == RunContractMode.individual,
              onTap: () =>
                  setState(() => _mode = RunContractMode.individual),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TargetChip(
              label: 'Tập thể',
              selected: _mode == RunContractMode.team,
              onTap: () => setState(() => _mode = RunContractMode.team),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        _mode == RunContractMode.team
            ? 'Cả nhóm gộp km cùng chinh phục cung — hiện % đóng góp từng người.'
            : 'Mỗi người tự tích luỹ chinh phục cung của mình.',
        style: TextStyle(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'THỜI HẠN',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.8,
          color: palette.textMuted,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _TargetChip(
              label: 'Không hạn',
              selected: _openEnded,
              onTap: () => setState(() => _openEnded = true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TargetChip(
              label: 'Có hạn',
              selected: !_openEnded,
              onTap: () => setState(() {
                _openEnded = false;
                _deadline ??= DateTime.now().add(const Duration(days: 30));
              }),
            ),
          ),
        ],
      ),
      if (!_openEnded) ...[
        const SizedBox(height: 10),
        GlassPanel(
          borderRadius: 14,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.event_rounded, color: palette.accentDeep),
            title: const Text('Về đích trước ngày'),
            subtitle: Text(
              _deadline == null
                  ? 'Chọn ngày'
                  : DateFormat('dd/MM/yyyy').format(_deadline!),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickDeadline,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.tint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.directions_run_rounded, size: 18, color: palette.accentDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _openEnded
                    ? 'Mỗi buổi chạy cộng dồn km, đi dần tới đích — không giới hạn thời gian.'
                    : 'Tích luỹ đủ km trước hạn để chinh phục trọn cung đường.',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _create() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final title = _titleController.text.trim();
      final route = RunContractRoute(
        points: [
          for (final point in _points)
            RunContractRoutePoint(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
        ],
        distanceMeters: _distanceMeters,
      );
      final now = DateTime.now();
      final draft = _journey
          ? RunContractDraft(
              template: RunContractTemplate.custom,
              // Hành trình: đếm theo km tích luỹ tới khi phủ hết độ dài cung.
              metric: RunContractMetric.distance,
              targetValue: _distanceMeters / 1000,
              period: RunContractPeriodType.custom,
              visibility: RunContractVisibility.club,
              title: title.isEmpty ? null : title,
              route: route,
              customStart: now,
              customEnd: _openEnded ? null : _deadline,
              openEnded: _openEnded,
              mode: _mode,
            )
          : RunContractDraft(
              template: RunContractTemplate.custom,
              metric: RunContractMetric.routeCompletion,
              targetValue: _targetValue,
              period: RunContractPeriodType.weekly,
              visibility: RunContractVisibility.club,
              title: title.isEmpty ? null : title,
              route: route,
              unlimitedRepeat: _unlimited,
            );
      ref
          .read(runContractAnalyticsProvider)
          .log(
            _journey ? 'contract_journey_created' : 'contract_route_created',
            draft: draft,
          )
          .ignore();
      final id = await ref.read(runContractControllerProvider).create(draft);
      // Kèo công khai → 3i bot báo group rủ tham gia (fire-and-forget).
      if (draft.visibility == RunContractVisibility.club) {
        ref
            .read(runNowApiClientProvider)
            .announceNewContract(contractId: id)
            .ignore();
      }
      if (mounted) context.go('/contracts/$id');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _RouteDrawingMap extends StatelessWidget {
  const _RouteDrawingMap({
    required this.controller,
    required this.points,
    required this.initialCenter,
    required this.onTap,
    required this.onLongPressPoint,
    this.interactive = true,
  });

  final MapController controller;
  final List<LatLng> points;
  final LatLng initialCenter;
  final ValueChanged<LatLng> onTap;
  final ValueChanged<int> onLongPressPoint;

  /// Tắt khi đang vẽ tự do — nhường toàn bộ gesture kéo cho lớp vẽ phía
  /// trên, tránh xung đột với việc bản đồ tự pan theo ngón tay.
  final bool interactive;

  static const _lightTileTemplate =
      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const _darkTileTemplate =
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileTemplate = isDark ? _darkTileTemplate : _lightTileTemplate;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: points.isNotEmpty ? points.last : initialCenter,
        initialZoom: 15,
        onTap: (_, point) => onTap(point),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          key: ValueKey(tileTemplate),
          urlTemplate: tileTemplate,
          userAgentPackageName: 'com.threei.run',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        const MapAttribution(),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: palette.secondary,
                strokeWidth: 4.5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (var index = 0; index < points.length; index++)
              if (index == 0)
                Marker(
                  point: points[index],
                  width: 26,
                  height: 26,
                  child: GestureDetector(
                    onLongPress: () => onLongPressPoint(index),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.secondary,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: palette.secondary.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                )
              else
                Marker(
                  point: points[index],
                  width: 5,
                  height: 5,
                  child: GestureDetector(
                    onLongPress: () => onLongPressPoint(index),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.secondary,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _RouteStat extends StatelessWidget {
  const _RouteStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.glassStart,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected
                ? palette.glassStart
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Ô tìm địa điểm để bay bản đồ tới đó trước khi vẽ tuyến — không tự thêm
/// điểm mốc, chỉ đổi vị trí camera. Dùng Nominatim (OpenStreetMap, miễn phí,
/// không cần API key) để nhất quán với tile CARTO/OSM app đang dùng, thay vì
/// Google Places (cần key + billing).
/// Tìm gần đây trong phiên hiện tại — cố ý không lưu ổn định qua lần mở app
/// mới (tránh thêm dependency `shared_preferences` chỉ cho vài mục gợi ý).
final _recentPlaceSearches = <_GeocodingResult>[];

/// Thanh tìm địa điểm theo đúng 6 trạng thái trong
/// `features/design_handoff_search_bar/search-bar-states.html`: rỗng → tap
/// (gợi ý gần đây/GPS) → đang gõ (loading) → có kết quả → không tìm thấy →
/// đã chọn xong.
class _PlaceSearchField extends StatefulWidget {
  const _PlaceSearchField({required this.onSelected});

  final ValueChanged<LatLng> onSelected;

  @override
  State<_PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<_PlaceSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  var _results = const <_GeocodingResult>[];
  var _loading = false;
  var _searchedOnce = false;
  var _selected = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _showSuggestions =>
      _focusNode.hasFocus && _controller.text.trim().isEmpty && !_selected;

  bool get _showDropdown =>
      _showSuggestions ||
      _loading ||
      (_searchedOnce && _focusNode.hasFocus && !_selected);

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _selected = false);
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _searchedOnce = false;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(trimmed),
    );
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    setState(() => _loading = true);
    try {
      final results = await _searchPlace(query);
      if (mounted) {
        setState(() {
          _results = results;
          _searchedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = const [];
          _searchedOnce = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectResult(_GeocodingResult result) {
    _recentPlaceSearches.removeWhere(
      (item) => item.displayName == result.displayName,
    );
    _recentPlaceSearches.insert(0, result);
    if (_recentPlaceSearches.length > 3) {
      _recentPlaceSearches.removeRange(3, _recentPlaceSearches.length);
    }
    widget.onSelected(LatLng(result.latitude, result.longitude));
    _focusNode.unfocus();
    setState(() {
      _controller.text = result.title;
      _results = const [];
      _selected = true;
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      widget.onSelected(LatLng(position.latitude, position.longitude));
      if (!mounted) return;
      _focusNode.unfocus();
      setState(() {
        _controller.text = 'Vị trí hiện tại của tôi';
        _results = const [];
        _selected = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không lấy được vị trí hiện tại.')),
        );
      }
    }
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _results = const [];
      _searchedOnce = false;
      _selected = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: palette.textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _onChanged,
                  onSubmitted: _search,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: onSurface,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    hintText: 'Tìm địa điểm để bắt đầu vẽ…',
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: GestureDetector(
                    onTap: _clear,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.textMuted.withValues(alpha: 0.16),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_showDropdown) ...[
          const SizedBox(height: 8),
          _buildDropdown(context),
        ],
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final Widget content;
    if (_loading) {
      content = const _SearchEmptyState(
        title: 'Đang tìm…',
        subtitle: 'Chờ chút xíu',
      );
    } else if (_showSuggestions) {
      content = _buildSuggestions(context);
    } else if (_searchedOnce && _results.isEmpty) {
      content = const _SearchEmptyState(
        title: 'Không tìm thấy địa điểm',
        subtitle: 'Thử tên khác hoặc chấm điểm trực tiếp trên bản đồ',
      );
    } else {
      content = _buildResultsList(context);
    }
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recentPlaceSearches.isNotEmpty) ...[
          const _SectionHeader('Tìm gần đây'),
          for (final item in _recentPlaceSearches)
            _SearchResultTile(
              icon: Icons.history_rounded,
              muted: true,
              title: item.title,
              subtitle: item.subtitle,
              onTap: () => _selectResult(item),
            ),
        ],
        const _SectionHeader('Dùng vị trí'),
        _SearchResultTile(
          icon: Icons.my_location_rounded,
          muted: false,
          title: 'Vị trí hiện tại của tôi',
          subtitle: 'Dùng GPS để bắt đầu ngay tại đây',
          onTap: _useCurrentLocation,
        ),
      ],
    );
  }

  Widget _buildResultsList(BuildContext context) {
    final palette = context.runNowPalette;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _results.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: palette.border),
        itemBuilder: (context, index) {
          final result = _results[index];
          return _SearchResultTile(
            icon: Icons.location_on_rounded,
            muted: false,
            active: index == 0,
            title: result.title,
            subtitle: result.subtitle,
            onTap: () => _selectResult(result),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 5),
      color: palette.tint,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.icon,
    required this.muted,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final bool muted;
  final bool active;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? palette.secondary.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: muted
                    ? palette.textMuted.withValues(alpha: 0.14)
                    : palette.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 15,
                color: muted ? palette.textMuted : palette.secondary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: palette.textMuted,
                      ),
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

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeocodingResult {
  const _GeocodingResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;

  String get title {
    final index = displayName.indexOf(',');
    return index == -1 ? displayName : displayName.substring(0, index).trim();
  }

  String get subtitle {
    final index = displayName.indexOf(',');
    return index == -1 ? '' : displayName.substring(index + 1).trim();
  }
}

/// Geocoding qua Nominatim (OpenStreetMap) — yêu cầu User-Agent định danh app
/// theo chính sách sử dụng của Nominatim (không dùng UA mặc định của HTTP
/// client), tối đa 5 kết quả.
Future<List<_GeocodingResult>> _searchPlace(String query) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'json',
    'q': query,
    'limit': '5',
  });
  final response = await http
      .get(uri, headers: {'User-Agent': '3i-app (com.threei.run)'})
      .timeout(const Duration(seconds: 8));
  if (response.statusCode != 200) return const [];
  final decoded = jsonDecode(response.body);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => _GeocodingResult(
          displayName: item['display_name'] as String? ?? query,
          latitude: double.tryParse('${item['lat']}') ?? 0,
          longitude: double.tryParse('${item['lon']}') ?? 0,
        ),
      )
      .toList();
}

/// Chuyển giữa vẽ tự do (kéo tay liên tục) và di chuyển bản đồ bình thường
/// (chạm để thêm từng điểm mốc) — kéo tay nhanh hơn nhiều so với chấm từng
/// điểm cho tuyến dài/nhiều khúc cua, nhưng chấm từng điểm vẫn cần cho lúc
/// muốn chỉnh chính xác hoặc di chuyển/zoom bản đồ.
class _DrawModeToggle extends StatelessWidget {
  const _DrawModeToggle({required this.freehand, required this.onChanged});

  final bool freehand;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 999,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            icon: Icons.edit_rounded,
            tooltip: 'Vẽ tự do (kéo tay)',
            selected: freehand,
            onTap: () => onChanged(true),
          ),
          _ModeButton(
            icon: Icons.pan_tool_alt_rounded,
            tooltip: 'Di chuyển bản đồ · chạm để thêm điểm',
            selected: !freehand,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? palette.glassStart
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
