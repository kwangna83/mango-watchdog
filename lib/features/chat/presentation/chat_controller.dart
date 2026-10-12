import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/chat_constants.dart';
import '../../../core/platform/app_badge.dart';
import '../../../core/providers/repository_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/image_dimensions.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.roomId,
    this.loadingOlder = false,
    this.hasMore = true,
    this.firstUnreadMessageId,
    this.unreadCount = 0,
  });

  final List<ChatMessage> messages;
  final String? roomId;
  final bool loadingOlder;
  final bool hasMore;
  final String? firstUnreadMessageId;
  final int unreadCount;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? roomId,
    bool? loadingOlder,
    bool? hasMore,
    String? firstUnreadMessageId,
    int? unreadCount,
  }) => ChatState(
    messages: messages ?? this.messages,
    roomId: roomId ?? this.roomId,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    hasMore: hasMore ?? this.hasMore,
    firstUnreadMessageId: firstUnreadMessageId ?? this.firstUnreadMessageId,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

final chatControllerProvider = AsyncNotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends AsyncNotifier<ChatState> {
  ChatRepository get _repository => ref.read(chatRepositoryProvider);
  ChatSubscription? _subscription;

  @override
  Future<ChatState> build() async {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    final roomId = await _repository.joinPublicRoom();
    final results = await Future.wait([
      _repository.fetchMessages(roomId: roomId),
      _repository.fetchReadPosition(roomId: roomId),
    ]);
    final messages = _sortedUnique(results[0] as List<ChatMessage>);
    final readPosition = results[1] as MessageCursor?;
    final userId = ref.read(authControllerProvider).value?.id;
    final unread =
        readPosition == null
            ? const <ChatMessage>[]
            : messages
                .where(
                  (message) =>
                      message.senderId != userId &&
                      _isAfter(message, readPosition),
                )
                .toList();
    _subscription = await _repository.subscribe(
      roomId: roomId,
      onMessage: _onRealtimeMessage,
      onConnected: () => unawaited(_catchUp(roomId)),
    );
    final latest = messages.lastOrNull;
    if (latest != null) unawaited(_markRead(roomId, latest));
    return ChatState(
      roomId: roomId,
      messages: messages,
      hasMore: messages.length == ChatConstants.pageSize,
      firstUnreadMessageId: unread.firstOrNull?.id,
      unreadCount: unread.length,
    );
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || current.loadingOlder || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final oldest = current.messages.firstOrNull;
      final older = await _repository.fetchMessages(
        roomId: current.roomId!,
        before: oldest == null ? null : MessageCursor.fromMessage(oldest),
      );
      state = AsyncData(
        current.copyWith(
          messages: _sortedUnique([...older, ...current.messages]),
          loadingOlder: false,
          hasMore: older.length == ChatConstants.pageSize,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingOlder: false));
      rethrow;
    }
  }

  Future<void> send(
    String body, {
    String? clientMessageId,
    ChatMessage? replyTo,
  }) async {
    final current = state.value;
    final user = ref.read(authControllerProvider).value;
    final trimmed = body.trim();
    if (current?.roomId == null || user == null || trimmed.isEmpty) return;
    final clientId = clientMessageId ?? const Uuid().v4();
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      roomId: current!.roomId!,
      senderId: user.id,
      senderNickname: user.nickname,
      senderAvatarUrl: user.avatarUrl,
      clientMessageId: clientId,
      body: trimmed,
      createdAt: DateTime.now(),
      status: MessageSendStatus.sending,
      replyToMessageId: replyTo?.id,
      replySenderNickname: replyTo?.senderNickname,
      replyBody:
          replyTo == null
              ? null
              : replyTo.type == ChatMessageType.image
              ? '사진'
              : replyTo.body.length <= 160
              ? replyTo.body
              : replyTo.body.substring(0, 160),
      replyMessageType: replyTo?.type,
    );
    _merge(optimistic);
    try {
      _merge(
        await _repository.sendMessage(
          roomId: current.roomId!,
          clientMessageId: clientId,
          body: trimmed,
          replyToMessageId: replyTo?.id,
        ),
      );
    } catch (_) {
      _replaceStatus(clientId, MessageSendStatus.failed);
    }
  }

  Future<void> retry(ChatMessage message) =>
      message.type == ChatMessageType.image && message.localImageBytes != null
          ? sendImage(
            bytes: message.localImageBytes!,
            fileName: 'retry-image',
            mimeType: message.imageMimeType!,
            clientMessageId: message.clientMessageId,
          )
          : send(
            message.body,
            clientMessageId: message.clientMessageId,
            replyTo:
                message.isReply
                    ? ChatMessage(
                      id: message.replyToMessageId ?? '',
                      roomId: message.roomId,
                      senderId: '',
                      senderNickname: message.replySenderNickname!,
                      clientMessageId: '',
                      body: message.replyBody!,
                      createdAt: message.createdAt,
                      type: message.replyMessageType ?? ChatMessageType.text,
                    )
                    : null,
          );

  Future<void> sendImage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? clientMessageId,
  }) async {
    final current = state.value;
    final user = ref.read(authControllerProvider).value;
    if (current?.roomId == null || user == null) return;
    final dimensions = await readImageDimensions(bytes);
    final clientId = clientMessageId ?? const Uuid().v4();
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      roomId: current!.roomId!,
      senderId: user.id,
      senderNickname: user.nickname,
      senderAvatarUrl: user.avatarUrl,
      clientMessageId: clientId,
      body: '이미지',
      createdAt: DateTime.now(),
      type: ChatMessageType.image,
      localImageBytes: bytes,
      imageMimeType: mimeType,
      imageWidth: dimensions.width,
      imageHeight: dimensions.height,
      status: MessageSendStatus.sending,
    );
    _merge(optimistic);
    try {
      _merge(
        await _repository.sendImage(
          roomId: current.roomId!,
          clientMessageId: clientId,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          dimensions: dimensions,
        ),
      );
    } catch (_) {
      _replaceStatus(clientId, MessageSendStatus.failed);
    }
  }

  void _merge(ChatMessage message) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(messages: _sortedUnique([...current.messages, message])),
    );
  }

  void _onRealtimeMessage(ChatMessage message) {
    _merge(message);
    if (!message.id.startsWith('local:')) {
      unawaited(_markRead(message.roomId, message));
    }
  }

  Future<void> _markRead(String roomId, ChatMessage message) async {
    try {
      await _repository.markRead(
        roomId: roomId,
        position: MessageCursor.fromMessage(message),
      );
      await clearAppBadge();
    } catch (_) {
      // Reading messages must still work if persisting the position fails.
    }
  }

  void _replaceStatus(String clientId, MessageSendStatus status) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages:
            current.messages
                .map(
                  (m) =>
                      m.clientMessageId == clientId
                          ? m.copyWith(status: status)
                          : m,
                )
                .toList(),
      ),
    );
  }

  Future<void> _catchUp(String roomId) async {
    final current = state.value;
    final latest = current?.messages.lastOrNull;
    if (current == null || latest == null) return;
    final missed = await _repository.fetchMessagesAfter(
      roomId: roomId,
      after: MessageCursor.fromMessage(latest),
    );
    for (final message in missed) {
      _merge(message);
    }
  }

  List<ChatMessage> _sortedUnique(Iterable<ChatMessage> values) {
    final byClientId = <String, ChatMessage>{};
    for (final message in values) {
      final previous = byClientId[message.clientMessageId];
      if (previous == null || message.status == MessageSendStatus.sent) {
        byClientId[message.clientMessageId] = message;
      }
    }
    final result = byClientId.values.toList();
    result.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return result;
  }

  bool _isAfter(ChatMessage message, MessageCursor cursor) {
    final byTime = message.createdAt.compareTo(cursor.createdAt);
    return byTime > 0 || (byTime == 0 && message.id.compareTo(cursor.id) > 0);
  }
}
