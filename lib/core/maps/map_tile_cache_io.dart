import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'map_tile_cache.dart';

MapTileCache createMapTileCache() => FileMapTileCache();

/// Public tile cache only, not offline downloads or user-scoped task storage.
/// Native writes are serialized and bounded; OS may evict temporary files.
final class FileMapTileCache implements MapTileCache {
  FileMapTileCache({
    Future<Directory> Function()? directory,
    this.maxFiles = 64,
    this.maxBytes = 16 * 1024 * 1024,
  }) : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  final int maxFiles, maxBytes;
  static Future<void> _writes = Future.value();
  static Future<Directory> _defaultDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}sports_store_public_tiles_v1',
    );
  }

  Future<File> _file(Uri uri) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File(
      '${dir.path}${Platform.pathSeparator}${base64Url.encode(utf8.encode(uri.toString()))}.tile',
    );
  }

  @override
  Future<CachedMapTile?> read(Uri tile) async {
    final file = await _file(tile);
    if (!await file.exists()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CachedMapTile(
        bytes: base64Decode(data['bytes'] as String),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          data['expires'] as int,
          isUtc: true,
        ),
        etag: data['etag'] as String?,
        lastModified: data['modified'] as String?,
        freshnessLifetime: data['ttl'] is int
            ? Duration(milliseconds: data['ttl'] as int)
            : null,
      );
    } on FormatException {
      await file.delete();
      return null;
    }
  }

  @override
  Future<void> write(Uri tile, CachedMapTile value) {
    final operation = _writes.then((_) async {
      if (maxFiles < 1 || maxBytes < 1) {
        throw ArgumentError('Invalid cache budget');
      }
      final file = await _file(tile);
      final content = jsonEncode({
        'bytes': base64Encode(value.bytes),
        'expires': value.expiresAt.millisecondsSinceEpoch,
        'etag': value.etag,
        'modified': value.lastModified,
        'ttl': value.freshnessLifetime?.inMilliseconds,
      });
      if (content.length > maxBytes) return;
      final files = await file.parent
          .list()
          .where(
            (entry) =>
                entry is File &&
                entry.path.endsWith('.tile') &&
                entry.path != file.path,
          )
          .cast<File>()
          .toList();
      final entries = <({File file, FileStat stat})>[];
      for (final item in files) {
        entries.add((file: item, stat: await item.stat()));
      }
      entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      var total =
          entries.fold<int>(0, (sum, e) => sum + e.stat.size) + content.length;
      var count = entries.length + 1;
      for (final entry in entries) {
        if (total <= maxBytes && count <= maxFiles) break;
        await entry.file.delete();
        total -= entry.stat.size;
        count--;
      }
      await file.writeAsString(content, flush: true);
    });
    _writes = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<void> remove(Uri tile) async {
    await _writes;
    final file = await _file(tile);
    if (await file.exists()) await file.delete();
  }
}
