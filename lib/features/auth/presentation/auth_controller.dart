import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/platform/app_badge.dart';
import '../domain/app_user.dart';
import '../../notifications/presentation/notification_controller.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final user = await ref.watch(authRepositoryProvider).restoreSession();
    if (user != null) _startNotifications();
    return user;
  }

  Future<void> signIn(String nickname) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInAnonymously(nickname),
    );
    if (state.value != null) _startNotifications();
  }

  void _startNotifications() {
    // Push setup must not block session restoration or entry to the chat UI.
    // Reading the future eagerly starts token sync and keeps the non-autoDispose
    // controller alive so FCM token refreshes are observed for this app session.
    unawaited(
      ref
          .read(notificationControllerProvider.future)
          .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> signOut() async {
    final userId = state.value?.id;
    await ref
        .read(notificationControllerProvider.notifier)
        .disableCurrentSubscription();
    if (userId != null) {
      ref.read(decodedChatImageCacheProvider).clearUser(userId);
      try {
        await ref.read(chatImageCacheProvider).clearUser(userId);
      } catch (_) {
        // Private cache cleanup is best-effort and must not block sign-out.
      }
    }
    await ref.read(authRepositoryProvider).signOut();
    await clearAppBadge();
    state = const AsyncData(null);
  }

  Future<bool> updateProfile({
    required String nickname,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    bool deleteAvatar = false,
  }) async {
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .updateProfile(
            nickname: nickname,
            avatarBytes: avatarBytes,
            avatarMimeType: avatarMimeType,
            deleteAvatar: deleteAvatar,
          );
      state = AsyncData(user);
      return true;
    } catch (_) {
      return false;
    }
  }
}
