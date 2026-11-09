import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_tile_source.dart';

/// Adapts the shared tile source, including its cache and HTTP identification,
/// to flutter_map. The caller retains ownership of [source].
class FlutterMapTileProvider extends TileProvider {
  FlutterMapTileProvider({
    required this.source,
    this.onTileLoaded,
    this.onTileLoadedUri,
    this.onTileError,
    this.generation = 0,
  });

  final MapTileSource source;
  final VoidCallback? onTileLoaded;
  final ValueChanged<Uri>? onTileLoadedUri;
  final ValueChanged<Object>? onTileError;

  /// Increment when explicitly retrying to avoid reusing a failed image stream.
  final int generation;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _MapTileImageProvider(
        source: source,
        uri: source.tileUri(
          zoom: coordinates.z,
          x: coordinates.x,
          y: coordinates.y,
        ),
        generation: generation,
        onTileLoaded: onTileLoaded,
        onTileLoadedUri: onTileLoadedUri,
        onTileError: onTileError,
      );

  // TileLayer owns this adapter, but Riverpod owns the shared tile source.
  @override
  void dispose() {}
}

@immutable
class _MapTileImageProvider extends ImageProvider<_MapTileImageProvider> {
  const _MapTileImageProvider({
    required this.source,
    required this.uri,
    required this.generation,
    this.onTileLoaded,
    this.onTileLoadedUri,
    this.onTileError,
  });

  final MapTileSource source;
  final Uri uri;
  final int generation;
  final VoidCallback? onTileLoaded;
  final ValueChanged<Uri>? onTileLoadedUri;
  final ValueChanged<Object>? onTileError;

  @override
  SynchronousFuture<_MapTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _MapTileImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'Shared map tile',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await source.loadTile(uri);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } on Object {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _MapTileImageProvider key,
    ImageErrorListener handleError,
  ) {
    super.resolveStreamForKey(configuration, stream, key, handleError);
    if (onTileLoaded == null &&
        onTileLoadedUri == null &&
        onTileError == null) {
      return;
    }

    // Observe each resolution, including image-cache hits. Merely notifying
    // from loadImage would leave a newly opened map loading forever on a hit.
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        image.dispose();
        stream.removeListener(listener);
        scheduleMicrotask(() {
          onTileLoaded?.call();
          onTileLoadedUri?.call(uri);
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        scheduleMicrotask(() => onTileError?.call(error));
      },
    );
    stream.addListener(listener);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MapTileImageProvider &&
          identical(source, other.source) &&
          uri == other.uri &&
          generation == other.generation;

  @override
  int get hashCode => Object.hash(identityHashCode(source), uri, generation);
}
