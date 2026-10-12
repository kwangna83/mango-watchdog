import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/data/chat_image_cache_types.dart';
import 'package:mangotalk/features/chat/data/chat_image_resolver.dart';
import 'package:mangotalk/features/chat/domain/chat_message.dart';
import 'package:mangotalk/features/chat/domain/chat_repository.dart';
import 'package:mangotalk/features/chat/domain/image_dimensions.dart';

void main() {
  final message = ChatMessage(
    id: 'message-1',
    roomId: 'room-1',
    senderId: 'sender-1',
    senderNickname: '망고',
    clientMessageId: 'client-1',
    body: '이미지',
    createdAt: DateTime(2026),
    type: ChatMessageType.image,
    attachmentId: 'attachment-1',
    attachmentPath: 'room/image.png',
    imageMimeType: 'image/png',
  );

  test('cache hit does not request a signed URL', () async {
    final cache = _FakeCache(
      hit: const CachedChatImage(source: 'blob:cached', isObjectUrl: true),
    );
    final repository = _FakeRepository();
    final resolver = ChatImageResolver(cache: cache, repository: repository);

    final result = await resolver.resolve(message: message, userId: 'user-1');

    expect(result.source, 'blob:cached');
    expect(repository.urlRequests, 0);
  });

  test('session hit is available synchronously for the first frame', () {
    final cache = _FakeCache(
      hit: const CachedChatImage(source: 'blob:session', isObjectUrl: true),
    );
    final repository = _FakeRepository();
    final resolver = ChatImageResolver(cache: cache, repository: repository);

    final result = resolver.getSession(message: message, userId: 'user-1');

    expect(result?.source, 'blob:session');
    expect(repository.urlRequests, 0);
  });

  test('simultaneous misses share one URL request and download', () async {
    final cache = _FakeCache();
    final repository = _FakeRepository();
    final resolver = ChatImageResolver(cache: cache, repository: repository);

    final results = await Future.wait([
      resolver.resolve(message: message, userId: 'user-1'),
      resolver.resolve(message: message, userId: 'user-1'),
    ]);

    expect(
      results.map((result) => result.source),
      everyElement('blob:fetched'),
    );
    expect(repository.urlRequests, 1);
    expect(cache.downloads, 1);
    expect(cache.retains, 1);
  });

  test('cache write failure falls back to the private network URL', () async {
    final cache = _FakeCache(failDownload: true);
    final repository = _FakeRepository();
    final resolver = ChatImageResolver(cache: cache, repository: repository);

    final result = await resolver.resolve(message: message, userId: 'user-1');

    expect(result.source, 'https://example.com/signed');
    expect(result.isObjectUrl, isFalse);
  });
}

class _FakeCache implements PersistentChatImageCache {
  _FakeCache({this.hit, this.failDownload = false});

  final CachedChatImage? hit;
  final bool failDownload;
  int downloads = 0;
  int retains = 0;

  @override
  CachedChatImage? getSession({required String key, required String userId}) =>
      hit;

  @override
  Future<CachedChatImage?> get({
    required String key,
    required String userId,
  }) async => hit;

  @override
  Future<CachedChatImage> downloadAndStore({
    required String key,
    required String userId,
    required String url,
    required String mimeType,
    int? width,
    int? height,
  }) async {
    downloads++;
    await Future<void>.delayed(Duration.zero);
    if (failDownload) throw StateError('quota');
    return const CachedChatImage(source: 'blob:fetched', isObjectUrl: true);
  }

  @override
  Future<void> clearUser(String userId) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  void retain(CachedChatImage image) => retains++;

  @override
  void release(CachedChatImage image) {}
}

class _FakeRepository implements ChatRepository {
  int urlRequests = 0;

  @override
  Future<String?> createImageUrl(ChatMessage message) async {
    urlRequests++;
    return 'https://example.com/signed';
  }

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String roomId,
    MessageCursor? before,
    int limit = 50,
  }) => throw UnimplementedError();

  @override
  Future<List<ChatMessage>> fetchMessagesAfter({
    required String roomId,
    required MessageCursor after,
  }) => throw UnimplementedError();

  @override
  Future<MessageCursor?> fetchReadPosition({required String roomId}) =>
      throw UnimplementedError();

  @override
  Future<String> joinPublicRoom() => throw UnimplementedError();

  @override
  Future<void> markRead({
    required String roomId,
    required MessageCursor position,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> sendImage({
    required String roomId,
    required String clientMessageId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required ImageDimensions dimensions,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> sendMessage({
    required String roomId,
    required String clientMessageId,
    required String body,
    String? replyToMessageId,
  }) => throw UnimplementedError();

  @override
  Future<ChatSubscription> subscribe({
    required String roomId,
    required MessageListener onMessage,
    required ConnectionListener onConnected,
  }) => throw UnimplementedError();
}
