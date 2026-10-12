class CachedChatImage {
  const CachedChatImage({
    required this.source,
    required this.isObjectUrl,
    this.width,
    this.height,
    this.previewSource,
  });

  final String source;
  final bool isObjectUrl;
  final int? width;
  final int? height;
  final String? previewSource;
}

abstract interface class PersistentChatImageCache {
  CachedChatImage? getSession({required String key, required String userId});

  Future<CachedChatImage?> get({required String key, required String userId});

  Future<CachedChatImage> downloadAndStore({
    required String key,
    required String userId,
    required String url,
    required String mimeType,
    int? width,
    int? height,
  });

  Future<void> remove(String key);

  Future<void> clearUser(String userId);

  void retain(CachedChatImage image);

  void release(CachedChatImage image);
}

String chatImageCacheKey({String? attachmentId, String? bucket, String? path}) {
  const version = 'v1';
  if (attachmentId != null && attachmentId.isNotEmpty) {
    return '$version:attachment:$attachmentId';
  }
  if (path == null || path.isEmpty) {
    throw ArgumentError('attachmentId 또는 path가 필요합니다.');
  }
  return '$version:path:${bucket ?? 'chat-images'}:$path';
}
