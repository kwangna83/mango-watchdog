import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/data/chat_image_cache_types.dart';

void main() {
  test('attachment id is preferred over signed URL or path', () {
    final first = chatImageCacheKey(
      attachmentId: 'attachment-1',
      bucket: 'chat-images',
      path: 'room/image.png',
    );
    final second = chatImageCacheKey(
      attachmentId: 'attachment-1',
      bucket: 'other',
      path: 'changed/image.png',
    );

    expect(first, second);
    expect(first, isNot(contains('token')));
  });

  test('legacy attachments use a versioned bucket and path key', () {
    expect(
      chatImageCacheKey(bucket: 'chat-images', path: 'room/image.png'),
      'v1:path:chat-images:room/image.png',
    );
  });
}
