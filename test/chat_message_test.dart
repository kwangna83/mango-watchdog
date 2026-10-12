import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/domain/chat_message.dart';

void main() {
  const baseJson = <String, dynamic>{
    'id': 'message-id',
    'room_id': 'room-id',
    'sender_id': 'sender-id',
    'sender_nickname': '망고',
    'sender_avatar_url': 'https://example.com/avatar.png',
    'client_message_id': 'client-id',
    'body': '안녕하세요',
    'created_at': '2026-07-16T00:00:00Z',
  };

  test('텍스트 메시지를 기본 타입으로 변환한다', () {
    final message = ChatMessage.fromJson(baseJson);

    expect(message.type, ChatMessageType.text);
    expect(message.imageUrl, isNull);
    expect(message.body, '안녕하세요');
    expect(message.senderAvatarUrl, 'https://example.com/avatar.png');
  });

  test('이미지 메시지와 signed URL을 변환한다', () {
    final message = ChatMessage.fromJson({
      ...baseJson,
      'message_type': 'image',
      'body': '이미지',
      'image_url': 'https://example.com/signed-image',
      'attachment_mime_type': 'image/png',
      'attachment_id': 'attachment-id',
      'attachment_bucket': 'chat-images',
      'attachment_path': 'room/user/message/image.png',
      'attachment_width': 1200,
      'attachment_height': 800,
    });

    expect(message.type, ChatMessageType.image);
    expect(message.imageUrl, 'https://example.com/signed-image');
    expect(message.imageMimeType, 'image/png');
    expect(message.attachmentId, 'attachment-id');
    expect(message.attachmentPath, 'room/user/message/image.png');
    expect(message.imageWidth, 1200);
    expect(message.imageHeight, 800);
  });

  test('기존 이미지의 누락된 크기 메타데이터를 허용한다', () {
    final message = ChatMessage.fromJson({
      ...baseJson,
      'message_type': 'image',
      'body': '이미지',
      'attachment_path': 'legacy/image.png',
    });

    expect(message.imageWidth, isNull);
    expect(message.imageHeight, isNull);
  });
}
