import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'map_tile_source.dart';
import 'saved_destination.dart';

/// A lightweight OSM raster map for one saved destination.
///
/// It deliberately stays provider-neutral at the widget boundary: tests and
/// future deployments can inject another [MapTileSource] without touching the
/// delivery screen.  The map never geocodes an address and never adds a store
/// marker.  It only places the server-saved destination pin.
class SavedDestinationMap extends StatefulWidget {
  const SavedDestinationMap({
    required this.destination,
    required this.tileSource,
    this.recenterToken = 0,
    this.onTileError,
    this.height = 320,
    super.key,
  });

  final SavedDestination destination;
  final MapTileSource tileSource;
  final int recenterToken;
  final ValueChanged<Object>? onTileError;
  final double height;

  @override
  State<SavedDestinationMap> createState() => _SavedDestinationMapState();
}

class _SavedDestinationMapState extends State<SavedDestinationMap> {
  static const _tileSize = 256.0;
  static const _zoom = 14;
  static const _maxLatitude = 85.05112878;

  Offset _pan = Offset.zero;
  double _scale = 1;
  Offset? _gestureFocalPoint;
  Offset _gesturePan = Offset.zero;
  double _gestureScale = 1;
  final Set<Uri> _reportedTileErrors = <Uri>{};

  @override
  void didUpdateWidget(covariant SavedDestinationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterToken != widget.recenterToken ||
        oldWidget.destination != widget.destination) {
      _resetViewport();
    }
    if (oldWidget.tileSource != widget.tileSource) {
      _reportedTileErrors.clear();
    }
  }

  void _resetViewport() {
    _pan = Offset.zero;
    _scale = 1;
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    if (!destination.isRenderableOnWebMercator) {
      return _MapFallback(
        message: 'Tọa độ điểm đến không hỗ trợ hiển thị trên bản đồ.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final height = widget.height.isFinite ? widget.height : 320.0;
        final center = _webMercatorTilePoint(destination, _zoom);
        final centerTileX = center.dx.floor();
        final centerTileY = center.dy.floor();
        final tiles = <Widget>[];
        // A 3x3 viewport is enough for the initial destination view and does
        // not silently prefetch a region beyond what the user can see.
        for (var tileY = centerTileY - 1; tileY <= centerTileY + 1; tileY++) {
          for (var tileX = centerTileX - 1; tileX <= centerTileX + 1; tileX++) {
            final safeY = tileY.clamp(0, (1 << _zoom) - 1);
            final uri = _tileUri(tileX, safeY);
            final left =
                width / 2 + (tileX - center.dx) * _tileSize * _scale + _pan.dx;
            final top =
                height / 2 + (tileY - center.dy) * _tileSize * _scale + _pan.dy;
            tiles.add(
              Positioned(
                left: left,
                top: top,
                width: _tileSize * _scale,
                height: _tileSize * _scale,
                child: _TileImage(
                  uri: uri,
                  tileSource: widget.tileSource,
                  onError: (error) {
                    if (_reportedTileErrors.add(uri)) {
                      widget.onTileError?.call(error);
                    }
                  },
                ),
              ),
            );
          }
        }

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => setState(_resetViewport),
            onScaleStart: (details) {
              _gestureFocalPoint = details.focalPoint;
              _gesturePan = _pan;
              _gestureScale = _scale;
            },
            onScaleUpdate: (details) {
              final start = _gestureFocalPoint;
              if (start == null) return;
              final nextScale = (_gestureScale * details.scale).clamp(1.0, 1.6);
              setState(() {
                _scale = nextScale;
                _pan = _gesturePan + (details.focalPoint - start);
              });
            },
            onScaleEnd: (_) => _gestureFocalPoint = null,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xfff5f5f5)),
                  ),
                  ...tiles,
                  const Positioned.fill(
                    child: IgnorePointer(child: SizedBox.shrink()),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Transform.translate(
                        offset: _pan,
                        child: const Center(child: _DestinationPin()),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: InkWell(
                          key: const ValueKey('map-attribution'),
                          onTap: widget.tileSource is MapTileAttribution
                              ? () async {
                                  final uri =
                                      (widget.tileSource as MapTileAttribution)
                                          .attributionUri;
                                  try {
                                    final opened = await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                    if (!opened && context.mounted) {
                                      ScaffoldMessenger.maybeOf(context)
                                          ?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Không mở được thông tin bản quyền.',
                                              ),
                                            ),
                                          );
                                    }
                                  } on Object {
                                    if (context.mounted) {
                                      ScaffoldMessenger.maybeOf(context)
                                          ?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Không mở được thông tin bản quyền.',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                }
                              : null,
                          child: Text(
                            widget.tileSource.attribution,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Uri _tileUri(int x, int y) {
    final side = 1 << _zoom;
    final wrappedX = ((x % side) + side) % side;
    return widget.tileSource.tileUri(zoom: _zoom, x: wrappedX, y: y);
  }

  Offset _webMercatorTilePoint(SavedDestination destination, int zoom) {
    final scale = 1 << zoom;
    final longitude = destination.longitude.clamp(-180.0, 180.0);
    final latitude = destination.latitude.clamp(-_maxLatitude, _maxLatitude);
    final x = (longitude + 180) / 360 * scale;
    final latitudeRadians = latitude * math.pi / 180;
    final y =
        (1 -
            math.log(
                  math.tan(latitudeRadians) + 1 / math.cos(latitudeRadians),
                ) /
                math.pi) /
        2 *
        scale;
    return Offset(x, y);
  }
}

class _TileImage extends StatefulWidget {
  const _TileImage({
    required this.uri,
    required this.tileSource,
    required this.onError,
  });

  final Uri uri;
  final MapTileSource tileSource;
  final ValueChanged<Object> onError;

  @override
  State<_TileImage> createState() => _TileImageState();
}

class _TileImageState extends State<_TileImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.tileSource.loadTile(widget.uri);
  }

  @override
  void didUpdateWidget(covariant _TileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.tileSource != widget.tileSource) {
      _bytes = widget.tileSource.loadTile(widget.uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          scheduleMicrotask(() => widget.onError(snapshot.error!));
          return const _TileFallback();
        }
        if (!snapshot.hasData) return const _TileFallback(loading: true);
        return Image.memory(
          snapshot.requireData,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            scheduleMicrotask(() => widget.onError(error));
            return const _TileFallback();
          },
        );
      },
    );
  }
}

class _TileFallback extends StatelessWidget {
  const _TileFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xfff5f5f5),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Center(
              child: Icon(Icons.cloud_off_outlined, color: Color(0xff707072)),
            ),
    );
  }
}

class _MapFallback extends StatelessWidget {
  const _MapFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      color: const Color(0xfff5f5f5),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffd30005),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: const SizedBox(
        key: ValueKey('map-destination-marker'),
        width: 26,
        height: 26,
      ),
    );
  }
}
