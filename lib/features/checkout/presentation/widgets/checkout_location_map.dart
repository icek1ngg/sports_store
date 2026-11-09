import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/maps/flutter_map_tile_provider.dart';
import '../../../../core/maps/map_providers.dart';
import '../../../../core/maps/map_tile_source.dart';

/// Shared checkout map. A Hanoi viewport never implies a selected destination.
class CheckoutLocationMap extends ConsumerStatefulWidget {
  const CheckoutLocationMap({
    required this.latitude,
    required this.longitude,
    required this.showTiles,
    this.hasSelection = true,
    this.centerPin = false,
    this.height = 260,
    this.onPicked,
    this.onReadyChanged,
    this.mapKey = const ValueKey('checkout-destination-preview-map'),
    super.key,
  });

  final double latitude;
  final double longitude;
  final bool showTiles;
  final bool hasSelection;
  final bool centerPin;
  final double height;
  final ValueChanged<LatLng>? onPicked;
  final ValueChanged<bool>? onReadyChanged;
  final Key mapKey;

  @override
  ConsumerState<CheckoutLocationMap> createState() =>
      _CheckoutLocationMapState();
}

class _CheckoutLocationMapState extends ConsumerState<CheckoutLocationMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _failed = false;
  bool _moving = false;
  bool? _lastReportedReady;
  int _generation = 0;
  LatLng? _pendingPoint;
  MapTileSource? _tileSource;
  final Set<Uri> _decodedTiles = {};
  bool _viewportRefreshScheduled = false;

  LatLng get _point => LatLng(widget.latitude, widget.longitude);
  bool get _centerDecoded {
    if (!widget.showTiles) return true;
    final source = _tileSource;
    if (!_ready || source == null) return false;
    return _decodedTiles.contains(_centerTileUri(source));
  }

  bool get _loading => widget.showTiles && !_centerDecoded && !_failed;
  bool get _canPick => _ready && !_moving && !_failed && _centerDecoded;

  Uri _centerTileUri(MapTileSource source) {
    final camera = _controller.camera;
    // flutter_map 8.3.2 TileLayer._clampToNativeZoom rounds camera zoom.
    // TileRangeCalculator projects at that integer zoom, then tile ranges
    // floor pixel coordinates divided by the explicit 256px tile dimension.
    final zoom = camera.zoom.round().clamp(0, 19);
    final pixel = camera.projectAtZoom(camera.center, zoom.toDouble());
    return source.tileUri(
      zoom: zoom,
      x: (pixel.dx / 256).floor(),
      y: (pixel.dy / 256).floor().clamp(0, (1 << zoom) - 1),
    );
  }

  @override
  void didUpdateWidget(covariant CheckoutLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready &&
        (widget.latitude != oldWidget.latitude ||
            widget.longitude != oldWidget.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ready) return;
        final camera = _controller.camera;
        if ((camera.center.latitude - widget.latitude).abs() > 0.00000001 ||
            (camera.center.longitude - widget.longitude).abs() > 0.00000001) {
          _controller.move(_point, camera.zoom);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reportReady() {
    final ready = _canPick;
    if (_lastReportedReady == ready) return;
    _lastReportedReady = ready;
    widget.onReadyChanged?.call(ready);
  }

  void _tileResult(
    MapTileSource source,
    int generation, {
    required bool failed,
    Uri? uri,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          !identical(source, _tileSource)) {
        return;
      }
      if (!failed && (uri == null || _decodedTiles.contains(uri))) return;
      if (failed && _failed) return;
      setState(() {
        if (failed) {
          _failed = true;
        } else {
          _decodedTiles.add(uri!);
        }
      });
      _commitPending();
      _reportReady();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _commitPending() {
    final point = _pendingPoint;
    if (point == null || !_canPick) return;
    _pendingPoint = null;
    widget.onPicked?.call(point);
  }

  void _requestSelection(LatLng point) {
    if (widget.onPicked == null) return;
    final normalized = LatLng(
      point.latitude,
      ((point.longitude + 180) % 360) - 180,
    );
    if (!normalized.latitude.isFinite ||
        normalized.latitude.abs() > 85.05112878 ||
        !normalized.longitude.isFinite) {
      return;
    }
    setState(() {
      _moving = false;
      _pendingPoint = normalized;
      // Resolve the final viewport before enabling confirmation. The shared
      // source serves cached visible tiles without prefetching a region.
      if (!_failed) {
        _generation++;
        _decodedTiles.clear();
      }
    });
    _commitPending();
    _reportReady();
  }

  void _mapEvent(MapEvent event) {
    if (event is MapEventWithMove || event is MapEventMoveEnd) {
      _scheduleViewportRefresh();
    }
    if (!widget.centerPin || widget.onPicked == null) return;
    if (event is MapEventMoveStart &&
        (event.source == MapEventSource.dragStart ||
            event.source == MapEventSource.multiFingerGestureStart)) {
      _moving = true;
      _pendingPoint = null;
      _reportReady();
    } else if (event is MapEventMoveEnd &&
        (event.source == MapEventSource.dragEnd ||
            event.source == MapEventSource.multiFingerEnd)) {
      _moving = false;
      _requestSelection(event.camera.center);
      _reportReady();
    } else if (event is MapEventScrollWheelZoom) {
      _requestSelection(event.camera.center);
    }
  }

  void _scheduleViewportRefresh() {
    if (_viewportRefreshScheduled) return;
    _viewportRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportRefreshScheduled = false;
      if (!mounted) return;
      setState(() {});
      _reportReady();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.showTiles ? ref.watch(mapTileSourceProvider) : null;
    if (!identical(source, _tileSource)) {
      _tileSource = source;
      _generation++;
      _decodedTiles.clear();
      _failed = false;
      _scheduleViewportRefresh();
    }
    final generation = _generation;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              key: widget.mapKey,
              mapController: _controller,
              options: MapOptions(
                initialCenter: _point,
                initialZoom: widget.onPicked == null ? 13 : 15,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: () {
                  _ready = true;
                  _reportReady();
                },
                interactionOptions: InteractionOptions(
                  flags: widget.onPicked == null
                      ? InteractiveFlag.none
                      : InteractiveFlag.drag |
                            InteractiveFlag.pinchMove |
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.scrollWheelZoom,
                ),
                onMapEvent: _mapEvent,
                onTap: (_, point) {
                  if (!_canPick) return;
                  if (widget.centerPin) {
                    _controller.move(point, _controller.camera.zoom);
                    _requestSelection(point);
                  } else {
                    widget.onPicked?.call(point);
                  }
                },
              ),
              children: [
                if (source != null)
                  TileLayer(
                    key: ValueKey('checkout-tiles-$generation'),
                    tileProvider: FlutterMapTileProvider(
                      source: source,
                      generation: generation,
                      onTileLoadedUri: (uri) => _tileResult(
                        source,
                        generation,
                        failed: false,
                        uri: uri,
                      ),
                      onTileError: (_) =>
                          _tileResult(source, generation, failed: true),
                    ),
                    userAgentPackageName: 'com.example.sports_store',
                    panBuffer: 0,
                    maxZoom: 19,
                    minNativeZoom: 0,
                    maxNativeZoom: 19,
                    tileDimension: 256,
                    retinaMode: false,
                    errorTileCallback: (_, _, _) {},
                  ),
                if (!widget.showTiles)
                  const ColoredBox(color: Color(0xffe8eeeb)),
                if (!widget.centerPin && widget.hasSelection)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point,
                        width: 40,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const _DestinationPin(),
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (widget.centerPin && !_failed)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: FractionalTranslation(
                      translation: Offset(0, -0.5),
                      child: _DestinationPin(),
                    ),
                  ),
                ),
              ),
            if (widget.showTiles && _loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  key: ValueKey('checkout-map-loading'),
                ),
              ),
            if (_failed)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xffedf0ee),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.map_outlined, size: 32),
                            const SizedBox(height: 8),
                            const Text(
                              'Không tải được bản đồ. Kiểm tra kết nối mạng rồi thử lại.',
                              key: ValueKey('checkout-map-error'),
                              textAlign: TextAlign.center,
                            ),
                            TextButton.icon(
                              key: const ValueKey('checkout-map-retry'),
                              onPressed: () {
                                setState(() {
                                  _generation++;
                                  _decodedTiles.clear();
                                  _failed = false;
                                });
                                _reportReady();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The point of the path is at the bottom center of this exact 40x48 box.
/// Both MarkerLayer and the fixed center overlay anchor that point to the map.
class _DestinationPin extends StatelessWidget {
  const _DestinationPin();

  @override
  Widget build(BuildContext context) => const SizedBox(
    key: ValueKey('checkout-destination-pin'),
    width: 40,
    height: 48,
    child: CustomPaint(painter: _DestinationPinPainter()),
  );
}

class _DestinationPinPainter extends CustomPainter {
  const _DestinationPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(20, 48)
      ..cubicTo(15, 37, 3, 28, 3, 17)
      ..cubicTo(3, 7, 10, 0, 20, 0)
      ..cubicTo(30, 0, 37, 7, 37, 17)
      ..cubicTo(37, 28, 25, 37, 20, 48)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, true);
    canvas.drawPath(path, Paint()..color = Colors.black);
    canvas.drawCircle(const Offset(20, 17), 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DestinationPinPainter oldDelegate) => false;
}
