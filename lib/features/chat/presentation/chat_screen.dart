import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/constants/chat_constants.dart';
import '../../../core/platform/image_save.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validation/input_validators.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/domain/notification_repository.dart';
import '../../notifications/presentation/notification_controller.dart';
import '../data/chat_image_cache_types.dart';
import '../data/chat_image_resolver.dart';
import '../domain/chat_message.dart';
import 'chat_image_layout.dart';
import 'chat_thumbnail.dart';
import 'chat_controller.dart';
import 'chat_scroll_target.dart';
import 'message_copy_actions.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _maxImageBytes = 10 * 1024 * 1024;
  final _text = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  final _imagePicker = ImagePicker();
  final _initialFocusKey = GlobalKey();
  bool _positionedAfterLoad = false;
  bool _loadingOlderForScroll = false;
  String? _latestMessageId;
  double _previousKeyboardHeight = 0;
  bool _showLatestButton = false;
  ChatMessage? _replyTo;
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels < 120) {
        _loadOlderPreservingPosition();
      }
      _updateLatestButton();
    });
  }

  void _updateLatestButton() {
    if (!_scroll.hasClients) return;
    final show =
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 120;
    if (show != _showLatestButton && mounted) {
      setState(() => _showLatestButton = show);
    }
  }

  Future<void> _loadOlderPreservingPosition() async {
    if (_loadingOlderForScroll || !_scroll.hasClients) return;
    _loadingOlderForScroll = true;
    final previousPixels = _scroll.position.pixels;
    final previousMaxScrollExtent = _scroll.position.maxScrollExtent;
    try {
      await ref.read(chatControllerProvider.notifier).loadOlder();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        preserveScrollOffsetAfterPrepend(
          previousPixels: previousPixels,
          previousMaxScrollExtent: previousMaxScrollExtent,
          nextMaxScrollExtent: _scroll.position.maxScrollExtent,
          minScrollExtent: _scroll.position.minScrollExtent,
        ),
      );
    } catch (_) {
      // The controller keeps existing messages when loading older fails.
    } finally {
      _loadingOlderForScroll = false;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    if (chat.isLoading) {
      _positionedAfterLoad = false;
      _latestMessageId = null;
    }
    final me = ref.watch(authControllerProvider).value;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _followKeyboardIfNeeded(keyboardHeight);
    final loadedChat = chat.value;
    if (loadedChat != null && loadedChat.messages.isNotEmpty) {
      _scheduleInitialFocus(hasUnread: loadedChat.firstUnreadMessageId != null);
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: AnimatedPadding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            _Header(
              user: me,
              onNotifications: _showNotificationSettings,
              onEditProfile: me == null ? null : () => _editProfile(me),
              onSignOut:
                  () => ref.read(authControllerProvider.notifier).signOut(),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: chat.when(
                      loading:
                          () =>
                              const Center(child: CircularProgressIndicator()),
                      error:
                          (_, _) => Center(
                            child: FilledButton(
                              onPressed:
                                  () => ref.invalidate(chatControllerProvider),
                              child: const Text('다시 연결하기'),
                            ),
                          ),
                      data:
                          (value) =>
                              value.messages.isEmpty
                                  ? const _EmptyChat()
                                  : ListView(
                                    controller: _scroll,
                                    scrollCacheExtent:
                                        const ScrollCacheExtent.pixels(1200),
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      20,
                                      16,
                                      12,
                                    ),
                                    children: [
                                      for (final message in value.messages)
                                        _messageItem(
                                          message: message,
                                          value: value,
                                          myUserId: me?.id,
                                        ),
                                    ],
                                  ),
                    ),
                  ),
                  if (_showLatestButton)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'latest-message',
                        tooltip: '맨 아래로 이동',
                        onPressed: _scrollToLatest,
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                ],
              ),
            ),
            _Composer(
              controller: _text,
              focusNode: _composerFocus,
              onSend: _send,
              onPickImage: _pickImage,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(body, replyTo: _replyTo);
    _text.clear();
    setState(() => _replyTo = null);
    _composerFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _composerFocus.requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _followKeyboardIfNeeded(double keyboardHeight) {
    final keyboardOpened = keyboardHeight > 0 && _previousKeyboardHeight == 0;
    final wasNearBottom =
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.position.pixels <= 120;
    _previousKeyboardHeight = keyboardHeight;
    if (!keyboardOpened || !wasNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || MediaQuery.viewInsetsOf(context).bottom == 0) return;
        _scrollToLatest();
      });
    });
  }

  Widget _messageItem({
    required ChatMessage message,
    required ChatState value,
    required String? myUserId,
  }) {
    if (message.id == value.messages.last.id) {
      _handleLatestMessage(message.id, isMine: message.senderId == myUserId);
    }
    final focusMessageId = value.firstUnreadMessageId ?? value.messages.last.id;
    final isInitialFocus = message.id == focusMessageId;
    final messageKey = _messageKeys.putIfAbsent(message.id, GlobalKey.new);
    return KeyedSubtree(
      key: messageKey,
      child: KeyedSubtree(
        key: isInitialFocus ? _initialFocusKey : null,
        child: Column(
          children: [
            if (message.id == value.firstUnreadMessageId)
              _UnreadDivider(count: value.unreadCount),
            _MessageBubble(
              message: message,
              isMine: message.senderId == myUserId,
              onRetry:
                  () =>
                      ref.read(chatControllerProvider.notifier).retry(message),
              onReply:
                  message.id.startsWith('local:')
                      ? () {}
                      : () {
                        setState(() => _replyTo = message);
                        _composerFocus.requestFocus();
                      },
              onOpenReply:
                  message.replyToMessageId == null
                      ? null
                      : () => _scrollToMessage(message.replyToMessageId!),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleInitialFocus({required bool hasUnread}) {
    if (_positionedAfterLoad) return;
    _positionedAfterLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!hasUnread) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
        return;
      }
      final targetContext = _initialFocusKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: .08,
        duration: Duration.zero,
      );
    });
  }

  void _handleLatestMessage(String messageId, {required bool isMine}) {
    if (_latestMessageId == null) {
      _latestMessageId = messageId;
      return;
    }
    if (_latestMessageId == messageId) return;
    final shouldFollow = shouldFollowLatestMessage(
      isMine: isMine,
      hasScrollClients: _scroll.hasClients,
      distanceFromBottom:
          _scroll.hasClients
              ? _scroll.position.maxScrollExtent - _scroll.position.pixels
              : 0,
    );
    _latestMessageId = messageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldFollow) {
        _scrollToLatest();
      } else {
        _showNewMessageNotice();
      }
    });
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _scrollToMessage(String messageId) async {
    var current = ref.read(chatControllerProvider).value;
    var targetIndex =
        current?.messages.indexWhere((message) => message.id == messageId) ??
        -1;
    while (targetIndex < 0 && current?.hasMore == true) {
      await ref.read(chatControllerProvider.notifier).loadOlder();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      current = ref.read(chatControllerProvider).value;
      targetIndex =
          current?.messages.indexWhere((message) => message.id == messageId) ??
          -1;
    }
    if (!mounted) return;
    if (current == null || targetIndex < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('원본 메시지를 찾을 수 없어요.')));
      return;
    }
    if (!_scroll.hasClients) return;
    var target = _messageKeys[messageId]?.currentContext;
    if (target == null) {
      _scroll.jumpTo(
        estimateMessageScrollOffset(
          targetIndex: targetIndex,
          itemCount: current.messages.length,
          maxScrollExtent: _scroll.position.maxScrollExtent,
        ).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      target = _messageKeys[messageId]?.currentContext;
    }
    for (var attempt = 0; target == null && attempt < 100; attempt++) {
      final visibleIndices = <int>[];
      for (var index = 0; index < current.messages.length; index++) {
        if (_messageKeys[current.messages[index].id]?.currentContext != null) {
          visibleIndices.add(index);
        }
      }
      final direction = directionToMessage(
        targetIndex: targetIndex,
        visibleIndices: visibleIndices,
      );
      if (direction == 0) break;
      final nextOffset =
          _scroll.position.pixels +
          direction * _scroll.position.viewportDimension * .75;
      _scroll.jumpTo(
        nextOffset.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      target = _messageKeys[messageId]?.currentContext;
    }
    if (target == null || !target.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('원본 위치로 이동하지 못했어요.')));
      return;
    }
    await Scrollable.ensureVisible(
      target,
      alignment: .18,
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _showNewMessageNotice() {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('새 메시지가 도착했어요.'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: '보기', onPressed: _scrollToLatest),
        ),
      );
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final mimeType = _imageMimeType(file);
    if (mimeType == null) {
      _showImageError('JPEG, PNG, WebP 이미지만 올릴 수 있어요.');
      return;
    }
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      _showImageError('이미지는 10MB 이하만 올릴 수 있어요.');
      return;
    }
    await ref
        .read(chatControllerProvider.notifier)
        .sendImage(bytes: bytes, fileName: file.name, mimeType: mimeType);
  }

  String? _imageMimeType(XFile file) {
    final declared = file.mimeType?.toLowerCase();
    if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(declared)) {
      return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  void _showImageError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editProfile(AppUser user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ProfileDialog(user: user),
    );
    if (changed == true) ref.invalidate(chatControllerProvider);
  }

  Future<void> _showNotificationSettings() => showDialog<void>(
    context: context,
    builder: (_) => const _NotificationDialog(),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.onNotifications,
    required this.onEditProfile,
    required this.onSignOut,
  });
  final AppUser? user;
  final VoidCallback onNotifications;
  final VoidCallback? onEditProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.paddingOf(context).top + 14,
      12,
      18,
    ),
    decoration: const BoxDecoration(
      color: AppColors.mango,
      borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(220, 28)),
    ),
    child: Row(
      children: [
        _Avatar(
          nickname: user?.nickname ?? 'M',
          imageUrl: user?.avatarUrl,
          radius: 22,
          backgroundColor: Colors.white,
          onTap:
              user?.avatarUrl == null
                  ? onEditProfile
                  : () => _showAvatarViewer(
                    context,
                    user!.avatarUrl!,
                    user!.nickname,
                  ),
          tooltip: user?.avatarUrl == null ? '내 프로필 수정' : '프로필 사진 크게 보기',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MangoTalk', style: Theme.of(context).textTheme.titleLarge),
              const Text('함께 이야기하는 중', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          tooltip: '내 프로필 수정',
          onPressed: onEditProfile,
          icon: const Icon(Icons.manage_accounts_rounded),
        ),
        IconButton(
          tooltip: '알림 설정',
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_rounded),
        ),
        IconButton(
          tooltip: '로그아웃',
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
  );
}

class _NotificationDialog extends ConsumerWidget {
  const _NotificationDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(notificationControllerProvider);
    return AlertDialog(
      title: const Text('새 메시지 알림'),
      content: permission.when(
        loading:
            () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
        error:
            (error, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('알림 설정을 변경하지 못했습니다.'),
                const SizedBox(height: 8),
                SelectableText(
                  _errorDescription(error),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
        data:
            (status) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(status), color: _color(context, status)),
                const SizedBox(width: 12),
                Flexible(child: Text(_description(status))),
              ],
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        if (permission.value == PushPermissionStatus.authorized)
          OutlinedButton.icon(
            onPressed:
                permission.isLoading
                    ? null
                    : () =>
                        ref
                            .read(notificationControllerProvider.notifier)
                            .disableCurrentSubscription(),
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('이 브라우저에서 끄기'),
          ),
        if (permission.value != PushPermissionStatus.authorized &&
            permission.value != PushPermissionStatus.unsupported)
          FilledButton.icon(
            onPressed:
                permission.isLoading
                    ? null
                    : () =>
                        ref
                            .read(notificationControllerProvider.notifier)
                            .enable(),
            icon: const Icon(Icons.notifications_active_rounded),
            label: const Text('알림 허용'),
          ),
      ],
    );
  }

  String _description(PushPermissionStatus status) => switch (status) {
    PushPermissionStatus.authorized => '이 브라우저에서 새 메시지 알림을 받고 있습니다.',
    PushPermissionStatus.denied => '알림이 차단되어 있습니다. 브라우저 사이트 설정에서 알림을 허용해 주세요.',
    PushPermissionStatus.disabled => '이 브라우저의 알림을 껐습니다. 다시 켜면 새 FCM 토큰을 등록합니다.',
    PushPermissionStatus.notDetermined =>
      '알림을 허용하면 앱을 보고 있지 않을 때도 새 메시지를 알려드려요.',
    PushPermissionStatus.unsupported =>
      '현재 브라우저에서는 푸시 알림을 지원하지 않습니다. '
          'iPhone과 iPad에서는 Safari 공유 메뉴의 “홈 화면에 추가”로 설치한 MangoTalk에서 알림을 켜 주세요.',
  };

  IconData _icon(PushPermissionStatus status) => switch (status) {
    PushPermissionStatus.authorized => Icons.notifications_active_rounded,
    PushPermissionStatus.denied ||
    PushPermissionStatus.disabled => Icons.notifications_off_outlined,
    PushPermissionStatus.notDetermined => Icons.notifications_none_rounded,
    PushPermissionStatus.unsupported => Icons.info_outline_rounded,
  };

  Color _color(BuildContext context, PushPermissionStatus status) =>
      status == PushPermissionStatus.authorized
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant;

  String _errorDescription(Object error) {
    if (error is NotificationSetupException) {
      return error.toString();
    }
    if (error is FirebaseException) {
      return 'Firebase 오류: ${error.code}'
          "${error.message == null ? '' : '\n${error.message}'}";
    }
    if (error is PostgrestException) {
      return 'Supabase 오류: ${error.code ?? 'unknown'}\n${error.message}';
    }
    final message = error.toString();
    return '브라우저 오류: '
        '${message.isEmpty ? error.runtimeType : message}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.nickname,
    required this.imageUrl,
    required this.radius,
    required this.backgroundColor,
    this.onTap,
    this.tooltip,
  });

  final String nickname;
  final String? imageUrl;
  final double radius;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
      child:
          imageUrl == null
              ? Text(nickname.characters.first.toUpperCase())
              : null,
    );
    if (onTap == null) return avatar;
    final button = Semantics(
      button: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: avatar,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

Future<void> _showAvatarViewer(
  BuildContext context,
  String imageUrl,
  String nickname,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .92),
  builder:
      (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    semanticLabel: '$nickname의 프로필 사진',
                    errorBuilder: (_, _, _) => const _ImageError(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
);

class _ProfileDialog extends ConsumerStatefulWidget {
  const _ProfileDialog({required this.user});
  final AppUser user;

  @override
  ConsumerState<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends ConsumerState<_ProfileDialog> {
  static const _maxAvatarBytes = 5 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nickname;
  Uint8List? _avatarBytes;
  String? _avatarMimeType;
  bool _deleteAvatar = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.user.nickname);
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('내 프로필'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    widget.user.avatarUrl == null ? '사진 등록' : '사진 변경',
                  ),
                ),
                if (widget.user.avatarUrl != null || _avatarBytes != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _removeAvatar,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('사진 삭제'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nickname,
              maxLength: 20,
              decoration: const InputDecoration(labelText: '닉네임'),
              validator: InputValidators.nickname,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child:
            _saving
                ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Text('저장'),
      ),
    ],
  );

  Widget _preview() {
    final provider =
        _avatarBytes != null
            ? MemoryImage(_avatarBytes!) as ImageProvider
            : (!_deleteAvatar && widget.user.avatarUrl != null
                ? NetworkImage(widget.user.avatarUrl!)
                : null);
    return CircleAvatar(
      radius: 52,
      backgroundColor: AppColors.purple.withValues(alpha: .14),
      foregroundImage: provider,
      child:
          provider == null
              ? Text(
                _nickname.text.trim().isEmpty
                    ? '?'
                    : _nickname.text.trim().characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 32),
              )
              : null,
    );
  }

  Future<void> _pickAvatar() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final mimeType = _avatarMime(file);
    if (mimeType == null || bytes.isEmpty || bytes.length > _maxAvatarBytes) {
      _showError(
        mimeType == null
            ? 'JPEG, PNG, WebP 이미지만 사용할 수 있어요.'
            : '사진은 5MB 이하만 사용할 수 있어요.',
      );
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarMimeType = mimeType;
      _deleteAvatar = false;
    });
  }

  void _removeAvatar() => setState(() {
    _avatarBytes = null;
    _avatarMimeType = null;
    _deleteAvatar = true;
  });

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final success = await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          nickname: _nickname.text,
          avatarBytes: _avatarBytes,
          avatarMimeType: _avatarMimeType,
          deleteAvatar: _deleteAvatar,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      _showError('프로필을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  String? _avatarMime(XFile file) {
    final declared = file.mimeType?.toLowerCase();
    if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(declared)) {
      return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        const Expanded(child: Divider(color: AppColors.purple)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '새 메시지 $count개',
            style: const TextStyle(
              color: AppColors.purple,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.purple)),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onRetry,
    required this.onReply,
    required this.onOpenReply,
  });
  final ChatMessage message;
  final bool isMine;
  final VoidCallback onRetry;
  final VoidCallback onReply;
  final VoidCallback? onOpenReply;

  String get _sentAtLabel {
    final sentAt = message.createdAt.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${sentAt.year.toString().padLeft(4, '0')}-'
        '${twoDigits(sentAt.month)}-${twoDigits(sentAt.day)} '
        '${twoDigits(sentAt.hour)}:${twoDigits(sentAt.minute)}';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        message.type == ChatMessageType.image
            ? '${message.senderNickname}의 이미지 메시지, 전송시간 $_sentAtLabel'
            : '${message.senderNickname}의 메시지: ${message.body}, '
                '전송시간 $_sentAtLabel',
    child: GestureDetector(
      onLongPress:
          message.type == ChatMessageType.image
              ? onReply
              : () => _showTextMessageActions(context),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                _messageAvatar(context),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text(
                          message.senderNickname,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      padding:
                          message.type == ChatMessageType.image
                              ? const EdgeInsets.all(4)
                              : const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                      decoration: BoxDecoration(
                        color: isMine ? AppColors.leaf : Colors.white,
                        borderRadius: BorderRadius.circular(20).copyWith(
                          bottomRight: isMine ? const Radius.circular(5) : null,
                          bottomLeft: isMine ? null : const Radius.circular(5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.isReply) ...[
                            InkWell(
                              onTap: onOpenReply,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isMine
                                          ? Colors.white
                                          : AppColors.purple)
                                      .withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.replySenderNickname!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            isMine
                                                ? Colors.white
                                                : AppColors.purple,
                                      ),
                                    ),
                                    Text(
                                      message.replyMessageType ==
                                              ChatMessageType.image
                                          ? '사진'
                                          : message.replyBody!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            isMine
                                                ? Colors.white70
                                                : AppColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (message.type == ChatMessageType.image)
                            _MessageImage(message: message)
                          else
                            Text(
                              message.body,
                              style: TextStyle(
                                color: isMine ? Colors.white : AppColors.ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                      child: Text(
                        _sentAtLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: .62),
                        ),
                      ),
                    ),
                    if (message.status != MessageSendStatus.sent)
                      TextButton.icon(
                        onPressed:
                            message.status == MessageSendStatus.failed
                                ? onRetry
                                : null,
                        icon: Icon(
                          message.status == MessageSendStatus.failed
                              ? Icons.refresh_rounded
                              : Icons.schedule_rounded,
                        ),
                        label: Text(
                          message.status == MessageSendStatus.failed
                              ? '재시도'
                              : '전송 중',
                        ),
                      ),
                  ],
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 8),
                _messageAvatar(context),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showTextMessageActions(BuildContext context) async {
    final action = await showMessageActionMenu(context);
    if (!context.mounted || action == null) return;

    switch (action) {
      case MessageAction.copyAll:
        await copyMessageToClipboard(message.body);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('메시지를 복사했어요.')));
        return;
      case MessageAction.copyPart:
        await showPartialMessageCopyDialog(context, message: message.body);
        return;
      case MessageAction.reply:
        onReply();
        return;
    }
  }

  Widget _messageAvatar(BuildContext context) => _Avatar(
    radius: 16,
    nickname: message.senderNickname,
    imageUrl: message.senderAvatarUrl,
    backgroundColor: AppColors.purple.withValues(alpha: .14),
    onTap:
        message.senderAvatarUrl == null
            ? null
            : () => _showAvatarViewer(
              context,
              message.senderAvatarUrl!,
              message.senderNickname,
            ),
    tooltip: message.senderAvatarUrl == null ? null : '프로필 사진 크게 보기',
  );
}

class _MessageImage extends ConsumerStatefulWidget {
  const _MessageImage({required this.message});
  final ChatMessage message;

  @override
  ConsumerState<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends ConsumerState<_MessageImage> {
  late final ChatImageResolver _resolver;
  late final String? _userId;
  CachedChatImage? _resolved;
  Object? _error;
  int _resolveRequest = 0;

  ChatMessage get message => widget.message;

  @override
  void initState() {
    super.initState();
    _resolver = ref.read(chatImageResolverProvider);
    _userId = ref.read(authControllerProvider).value?.id;
    if (message.localImageBytes == null) _resolveSessionFirst();
  }

  @override
  void didUpdateWidget(covariant _MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id == message.id &&
        oldWidget.message.imageUrl == message.imageUrl &&
        oldWidget.message.attachmentId == message.attachmentId) {
      return;
    }
    _releaseResolved();
    _error = null;
    if (message.localImageBytes == null) _resolveSessionFirst();
  }

  @override
  void dispose() {
    _releaseResolved();
    super.dispose();
  }

  Future<void> _resolve() async {
    final userId = _userId;
    if (userId == null) return;
    final request = ++_resolveRequest;
    try {
      final result = await _resolver.resolve(message: message, userId: userId);
      if (!mounted || request != _resolveRequest) {
        _resolver.release(result);
        return;
      }
      setState(() => _resolved = result);
    } catch (error) {
      if (mounted && request == _resolveRequest) {
        setState(() => _error = error);
      }
    }
  }

  void _resolveSessionFirst() {
    final userId = _userId;
    if (userId == null) return;
    final session = _resolver.getSession(message: message, userId: userId);
    if (session != null) {
      _resolved = session;
      return;
    }
    unawaited(_resolve());
  }

  void _releaseResolved() {
    _resolveRequest++;
    final resolved = _resolved;
    if (resolved != null) {
      _resolver.release(resolved);
      _resolved = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '크게 보기',
      child: Semantics(
        button: true,
        label: '이미지 크게 보기',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:
              message.localImageBytes != null || _resolved != null
                  ? () => _showImageViewer(context)
                  : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ChatImageFrame(
              width: message.imageWidth ?? _resolved?.width,
              height: message.imageHeight ?? _resolved?.height,
              child:
                  _resolved != null && _userId != null
                      ? ChatThumbnail(
                        cache: ref.watch(decodedChatImageCacheProvider),
                        userId: _userId,
                        source: _resolved!.previewSource ?? _resolved!.source,
                      )
                      : _image(fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image({required BoxFit fit}) {
    final bytes = message.localImageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        cacheWidth: 780,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    final source = _resolved?.source;
    if (source != null) {
      return Image.network(
        source,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        loadingBuilder:
            (context, child, progress) =>
                progress == null
                    ? child
                    : const SizedBox(
                      child: Center(child: CircularProgressIndicator()),
                    ),
        errorBuilder:
            (_, _, _) =>
                const SizedBox(width: 240, height: 160, child: _ImageError()),
      );
    }
    return _error == null
        ? const Center(child: CircularProgressIndicator())
        : const _ImageError();
  }

  Future<void> _showImageViewer(BuildContext context) async {
    final mimeType = message.imageMimeType ?? 'image/jpeg';
    final source =
        message.localImageBytes == null
            ? _resolved!.source
            : 'data:$mimeType;base64,${base64Encode(message.localImageBytes!)}';
    final cacheKey = message.id;
    unawaited(
      prepareImageForSave(
        source: source,
        cacheKey: cacheKey,
        mimeType: mimeType,
      ).catchError((Object _) {}),
    );
    var saving = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .92),
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => Dialog.fullscreen(
                  backgroundColor: Colors.transparent,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: Center(child: _image(fit: BoxFit.contain)),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        right: 12,
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: '사진 저장',
                              onPressed:
                                  saving
                                      ? null
                                      : () async {
                                        setDialogState(() => saving = true);
                                        final result = await savePreparedImage(
                                          cacheKey: cacheKey,
                                          fileName: _downloadFileName(mimeType),
                                          mimeType: mimeType,
                                        );
                                        if (!dialogContext.mounted) return;
                                        setDialogState(() => saving = false);
                                        final notice = switch (result) {
                                          ImageSaveResult.shared =>
                                            '공유 메뉴에서 이미지 저장을 선택해 주세요.',
                                          ImageSaveResult.downloaded =>
                                            '이미지 다운로드를 시작했어요.',
                                          ImageSaveResult.failed =>
                                            '이미지를 저장하지 못했어요.',
                                          ImageSaveResult.unsupported =>
                                            '이 환경에서는 이미지 저장을 지원하지 않아요.',
                                          ImageSaveResult.cancelled => null,
                                        };
                                        if (notice != null && context.mounted) {
                                          ScaffoldMessenger.of(context)
                                            ..hideCurrentSnackBar()
                                            ..showSnackBar(
                                              SnackBar(content: Text(notice)),
                                            );
                                        }
                                      },
                              icon:
                                  saving
                                      ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.download_rounded),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: '닫기',
                              onPressed:
                                  () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  String _downloadFileName(String mimeType) {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return 'MangoTalk_${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}.$extension';
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF1ECFF),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: AppColors.purple),
          SizedBox(height: 6),
          Text('이미지를 불러올 수 없어요'),
        ],
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onPickImage,
    required this.replyTo,
    required this.onCancelReply,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${replyTo!.senderNickname}에게 답장 · '
                      '${replyTo!.type == ChatMessageType.image ? '사진' : replyTo!.body}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '답장 취소',
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '이미지 올리기',
                onPressed: onPickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: ChatConstants.maxMessageLength,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: '메시지를 입력하세요',
                    counterText: '',
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '메시지 보내기',
                onPressed: onSend,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.waving_hand_rounded, size: 48, color: AppColors.mango),
        SizedBox(height: 12),
        Text('첫 인사를 건네보세요!'),
      ],
    ),
  );
}
