import 'chat_image_cache_types.dart';

PersistentChatImageCache createPersistentChatImageCache() =>
    _NetworkChatImageCache();

class _NetworkChatImageCache implements PersistentChatImageCache {
  @override
  CachedChatImage? getSession({required String key, required String userId}) =>
      null;

  @override
  Future<CachedChatImage?> get({
    required String key,
    required String userId,
  }) async => null;

  @override
  Future<CachedChatImage> downloadAndStore({
    required String key,
    required String userId,
    required String url,
    required String mimeType,
    int? width,
    int? height,
  }) async => CachedChatImage(
    source: url,
    isObjectUrl: false,
    width: width,
    height: height,
  );

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> clearUser(String userId) async {}

  @override
  void retain(CachedChatImage image) {}

  @override
  void release(CachedChatImage image) {}
}
