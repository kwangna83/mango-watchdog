import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import 'chat_image_cache_types.dart';

class ChatImageResolver {
  ChatImageResolver({required this.cache, required this.repository});

  final PersistentChatImageCache cache;
  final ChatRepository repository;
  final Map<String, Future<CachedChatImage>> _inFlight = {};

  CachedChatImage? getSession({
    required ChatMessage message,
    required String userId,
  }) => cache.getSession(
    key: chatImageCacheKey(
      attachmentId: message.attachmentId,
      bucket: message.attachmentBucket,
      path: message.attachmentPath,
    ),
    userId: userId,
  );

  Future<CachedChatImage> resolve({
    required ChatMessage message,
    required String userId,
  }) {
    final key = chatImageCacheKey(
      attachmentId: message.attachmentId,
      bucket: message.attachmentBucket,
      path: message.attachmentPath,
    );
    final operationKey = '$userId:$key';
    final existing = _inFlight[operationKey];
    if (existing != null) {
      return existing.then((image) {
        cache.retain(image);
        return image;
      });
    }
    final operation = _resolve(
      key: key,
      message: message,
      userId: userId,
    ).whenComplete(() {
      _inFlight.remove(operationKey);
    });
    _inFlight[operationKey] = operation;
    return operation;
  }

  Future<CachedChatImage> _resolve({
    required String key,
    required ChatMessage message,
    required String userId,
  }) async {
    try {
      final cached = await cache.get(key: key, userId: userId);
      if (cached != null) return cached;
    } catch (_) {
      // A cache failure must not prevent the private network fallback.
    }

    final url = await repository.createImageUrl(message);
    if (url == null || url.isEmpty) {
      throw StateError('이미지 다운로드 URL을 만들 수 없습니다.');
    }
    try {
      return await cache.downloadAndStore(
        key: key,
        userId: userId,
        url: url,
        mimeType: message.imageMimeType ?? 'image/jpeg',
        width: message.imageWidth,
        height: message.imageHeight,
      );
    } catch (_) {
      return CachedChatImage(
        source: url,
        isObjectUrl: false,
        width: message.imageWidth,
        height: message.imageHeight,
      );
    }
  }

  void release(CachedChatImage image) => cache.release(image);
}
