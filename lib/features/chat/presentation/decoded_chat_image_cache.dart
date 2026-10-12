import 'package:flutter/painting.dart';

/// Owns decoded thumbnails independently of the scrolling widget lifecycle.
/// Visible widgets own separate handles; evicting an idle entry cannot invalidate
/// a currently painted image. The byte limit covers cache-owned decoded pixels.
class DecodedChatImageCache {
  DecodedChatImageCache({
    this.maxEntries = 30,
    this.maxBytes = 32 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxBytes;
  final _entries = <(String, String), ImageInfo>{};
  final _generations = <String, int>{};
  int _bytes = 0;
  bool _disposed = false;

  int get length => _entries.length;
  int get sizeBytes => _bytes;
  int generation(String userId) => _generations[userId] ?? 0;

  ImageInfo? acquire(String userId, String source) {
    final key = (userId, source);
    final image = _entries.remove(key);
    if (image == null) return null;
    _entries[key] = image;
    return image.clone();
  }

  void store(String userId, String source, ImageInfo image, int generation) {
    if (_disposed || generation != this.generation(userId)) return;
    final bytes = image.image.width * image.image.height * 4;
    if (bytes > maxBytes || maxEntries <= 0) return;
    final key = (userId, source);
    _remove(key);
    _entries[key] = image.clone();
    _bytes += bytes;
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      _remove(_entries.keys.first);
    }
  }

  void clearUser(String userId) {
    _generations[userId] = generation(userId) + 1;
    for (final key in _entries.keys.where((key) => key.$1 == userId).toList()) {
      _remove(key);
    }
  }

  void _remove((String, String) key) {
    final image = _entries.remove(key);
    if (image == null) return;
    _bytes -= image.image.width * image.image.height * 4;
    image.dispose();
  }

  void dispose() {
    _disposed = true;
    for (final key in _entries.keys.toList()) {
      _remove(key);
    }
  }
}
