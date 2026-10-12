import 'dart:convert';
import 'dart:js_interop';

import 'chat_image_cache_types.dart';

@JS('mangoTalkChatImageCacheGet')
external JSPromise<JSString> _cacheGet(JSString key, JSString userId);

@JS('mangoTalkChatImageCachePeek')
external JSString _cachePeek(JSString key, JSString userId);

@JS('mangoTalkChatImageCacheFetch')
external JSPromise<JSString> _cacheFetch(
  JSString key,
  JSString userId,
  JSString url,
  JSString mimeType,
  JSNumber width,
  JSNumber height,
);

@JS('mangoTalkChatImageCacheRemove')
external JSPromise<JSAny?> _cacheRemove(JSString key);

@JS('mangoTalkChatImageCacheClearUser')
external JSPromise<JSAny?> _cacheClearUser(JSString userId);

@JS('mangoTalkChatImageCacheRelease')
external void _cacheRelease(JSString source);

@JS('mangoTalkChatImageCacheRetain')
external void _cacheRetain(JSString source);

PersistentChatImageCache createPersistentChatImageCache() =>
    _WebChatImageCache();

class _WebChatImageCache implements PersistentChatImageCache {
  @override
  CachedChatImage? getSession({required String key, required String userId}) {
    final value = _cachePeek(key.toJS, userId.toJS).toDart;
    return value.isEmpty ? null : _decode(value);
  }

  @override
  Future<CachedChatImage?> get({
    required String key,
    required String userId,
  }) async {
    final value = (await _cacheGet(key.toJS, userId.toJS).toDart).toDart;
    return value.isEmpty ? null : _decode(value);
  }

  @override
  Future<CachedChatImage> downloadAndStore({
    required String key,
    required String userId,
    required String url,
    required String mimeType,
    int? width,
    int? height,
  }) async {
    final value =
        (await _cacheFetch(
              key.toJS,
              userId.toJS,
              url.toJS,
              mimeType.toJS,
              (width ?? 0).toJS,
              (height ?? 0).toJS,
            ).toDart)
            .toDart;
    if (value.isEmpty) throw StateError('이미지 캐시 응답이 비어 있습니다.');
    return _decode(value);
  }

  @override
  Future<void> remove(String key) async {
    await _cacheRemove(key.toJS).toDart;
  }

  @override
  Future<void> clearUser(String userId) async {
    await _cacheClearUser(userId.toJS).toDart;
  }

  @override
  void retain(CachedChatImage image) {
    if (image.isObjectUrl) _cacheRetain(image.source.toJS);
  }

  @override
  void release(CachedChatImage image) {
    if (image.isObjectUrl) _cacheRelease(image.source.toJS);
  }

  CachedChatImage _decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return CachedChatImage(
      source: json['source'] as String,
      isObjectUrl: json['isObjectUrl'] as bool? ?? true,
      width: json['width'] as int?,
      height: json['height'] as int?,
      previewSource: json['previewSource'] as String?,
    );
  }
}
