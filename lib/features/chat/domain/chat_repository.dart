import 'dart:typed_data';

import 'chat_message.dart';
import 'image_dimensions.dart';

typedef MessageListener = void Function(ChatMessage message);
typedef ConnectionListener = void Function();

abstract interface class ChatSubscription {
  Future<void> cancel();
}

abstract interface class ChatRepository {
  Future<String> joinPublicRoom();

  Future<List<ChatMessage>> fetchMessages({
    required String roomId,
    MessageCursor? before,
    int limit = 50,
  });

  Future<List<ChatMessage>> fetchMessagesAfter({
    required String roomId,
    required MessageCursor after,
  });

  Future<MessageCursor?> fetchReadPosition({required String roomId});

  Future<void> markRead({
    required String roomId,
    required MessageCursor position,
  });

  Future<ChatMessage> sendMessage({
    required String roomId,
    required String clientMessageId,
    required String body,
    String? replyToMessageId,
  });

  Future<ChatMessage> sendImage({
    required String roomId,
    required String clientMessageId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required ImageDimensions dimensions,
  });

  Future<String?> createImageUrl(ChatMessage message);

  Future<ChatSubscription> subscribe({
    required String roomId,
    required MessageListener onMessage,
    required ConnectionListener onConnected,
  });
}
