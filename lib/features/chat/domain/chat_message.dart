import 'dart:typed_data';

enum MessageSendStatus { sending, sent, failed }

enum ChatMessageType { text, image }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderNickname,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.senderAvatarUrl,
    this.type = ChatMessageType.text,
    this.imageUrl,
    this.localImageBytes,
    this.imageMimeType,
    this.attachmentId,
    this.attachmentBucket,
    this.attachmentPath,
    this.imageWidth,
    this.imageHeight,
    this.replyToMessageId,
    this.replySenderNickname,
    this.replyBody,
    this.replyMessageType,
    this.status = MessageSendStatus.sent,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String clientMessageId;
  final String body;
  final DateTime createdAt;
  final String? senderAvatarUrl;
  final ChatMessageType type;
  final String? imageUrl;
  final Uint8List? localImageBytes;
  final String? imageMimeType;
  final String? attachmentId;
  final String? attachmentBucket;
  final String? attachmentPath;
  final int? imageWidth;
  final int? imageHeight;
  final String? replyToMessageId;
  final String? replySenderNickname;
  final String? replyBody;
  final ChatMessageType? replyMessageType;
  final MessageSendStatus status;

  bool get isReply => replySenderNickname != null && replyBody != null;

  ChatMessage copyWith({
    String? id,
    DateTime? createdAt,
    String? imageUrl,
    MessageSendStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      roomId: roomId,
      senderId: senderId,
      senderNickname: senderNickname,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: createdAt ?? this.createdAt,
      senderAvatarUrl: senderAvatarUrl,
      type: type,
      imageUrl: imageUrl ?? this.imageUrl,
      localImageBytes: localImageBytes,
      imageMimeType: imageMimeType,
      attachmentId: attachmentId,
      attachmentBucket: attachmentBucket,
      attachmentPath: attachmentPath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      replyToMessageId: replyToMessageId,
      replySenderNickname: replySenderNickname,
      replyBody: replyBody,
      replyMessageType: replyMessageType,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      roomId: (json['room_id'] ?? json['roomId']) as String,
      senderId: (json['sender_id'] ?? json['senderId']) as String,
      senderNickname:
          (json['sender_nickname'] ?? json['senderNickname'] ?? '알 수 없음')
              as String,
      senderAvatarUrl:
          (json['sender_avatar_url'] ?? json['senderAvatarUrl']) as String?,
      clientMessageId:
          (json['client_message_id'] ?? json['clientMessageId']) as String,
      body: json['body'] as String,
      type:
          json['message_type'] == 'image'
              ? ChatMessageType.image
              : ChatMessageType.text,
      imageUrl: json['image_url'] as String?,
      imageMimeType: json['attachment_mime_type'] as String?,
      attachmentId: json['attachment_id'] as String?,
      attachmentBucket: json['attachment_bucket'] as String?,
      attachmentPath: json['attachment_path'] as String?,
      imageWidth: json['attachment_width'] as int?,
      imageHeight: json['attachment_height'] as int?,
      replyToMessageId: json['reply_to_message_id'] as String?,
      replySenderNickname: json['reply_sender_nickname'] as String?,
      replyBody: json['reply_body'] as String?,
      replyMessageType:
          json['reply_message_type'] == null
              ? null
              : json['reply_message_type'] == 'image'
              ? ChatMessageType.image
              : ChatMessageType.text,
      createdAt:
          DateTime.parse(
            (json['created_at'] ?? json['createdAt']) as String,
          ).toLocal(),
    );
  }
}

class MessageCursor {
  const MessageCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;

  factory MessageCursor.fromMessage(ChatMessage message) =>
      MessageCursor(createdAt: message.createdAt, id: message.id);
}
