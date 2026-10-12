import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/core/providers/repository_providers.dart';
import 'package:mangotalk/features/auth/domain/app_user.dart';
import 'package:mangotalk/features/auth/domain/auth_repository.dart';
import 'package:mangotalk/features/auth/presentation/auth_controller.dart';
import 'package:mangotalk/features/chat/data/chat_image_cache_types.dart';
import 'package:mangotalk/features/notifications/domain/notification_repository.dart';
import 'package:mangotalk/features/notifications/presentation/notification_controller.dart';

void main() {
  const user = AppUser(id: 'user-1', nickname: '망고', isAnonymous: true);

  test(
    'restored sessions eagerly start notification synchronization',
    () async {
      final notifications = _FakeNotificationController();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
          notificationControllerProvider.overrideWith(() => notifications),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(authControllerProvider.future), user);
      await Future<void>.delayed(Duration.zero);

      expect(notifications.buildCount, 1);
    },
  );

  test(
    'notification startup failure does not fail session restoration',
    () async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
          notificationControllerProvider.overrideWith(
            _FailingNotificationController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(authControllerProvider.future), user);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authControllerProvider).value, user);
    },
  );

  test('sign out clears private image cache without blocking auth', () async {
    final auth = _FakeAuthRepository(user);
    final cache = _FakeImageCache();
    final notifications = _FakeNotificationController();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        chatImageCacheProvider.overrideWithValue(cache),
        notificationControllerProvider.overrideWith(() => notifications),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).signOut();

    expect(cache.clearedUsers, ['user-1']);
    expect(
      container.read(decodedChatImageCacheProvider).generation('user-1'),
      1,
    );
    expect(auth.signOutCount, 1);
    expect(container.read(authControllerProvider).value, isNull);
  });

  test('cache cleanup failure does not block sign out', () async {
    final auth = _FakeAuthRepository(user);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        chatImageCacheProvider.overrideWithValue(
          _FakeImageCache(failClear: true),
        ),
        notificationControllerProvider.overrideWith(
          _FakeNotificationController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).signOut();

    expect(auth.signOutCount, 1);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.restoredUser);

  final AppUser? restoredUser;
  int signOutCount = 0;

  @override
  Future<AppUser?> restoreSession() async => restoredUser;

  @override
  Future<AppUser> signInAnonymously(String nickname) async =>
      restoredUser ??
      AppUser(id: 'user-1', nickname: nickname, isAnonymous: true);

  @override
  Future<void> signOut() async => signOutCount++;

  @override
  Future<AppUser> updateProfile({
    required String nickname,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    bool deleteAvatar = false,
  }) async => AppUser(id: 'user-1', nickname: nickname, isAnonymous: true);
}

class _FakeNotificationController extends NotificationController {
  int buildCount = 0;

  @override
  Future<void> disableCurrentSubscription() async {}

  @override
  Future<PushPermissionStatus> build() async {
    buildCount++;
    return PushPermissionStatus.authorized;
  }
}

class _FailingNotificationController extends NotificationController {
  @override
  Future<PushPermissionStatus> build() async => throw StateError('FCM failed');
}

class _FakeImageCache implements PersistentChatImageCache {
  _FakeImageCache({this.failClear = false});

  final bool failClear;
  final List<String> clearedUsers = [];

  @override
  CachedChatImage? getSession({required String key, required String userId}) =>
      null;

  @override
  Future<void> clearUser(String userId) async {
    if (failClear) throw StateError('quota');
    clearedUsers.add(userId);
  }

  @override
  Future<CachedChatImage> downloadAndStore({
    required String key,
    required String userId,
    required String url,
    required String mimeType,
    int? width,
    int? height,
  }) => throw UnimplementedError();

  @override
  Future<CachedChatImage?> get({required String key, required String userId}) =>
      throw UnimplementedError();

  @override
  void retain(CachedChatImage image) {}

  @override
  void release(CachedChatImage image) {}

  @override
  Future<void> remove(String key) async {}
}
