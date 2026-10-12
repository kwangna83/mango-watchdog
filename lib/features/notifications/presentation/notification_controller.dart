import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/platform/app_badge.dart';
import '../domain/notification_repository.dart';

final notificationControllerProvider =
    AsyncNotifierProvider<NotificationController, PushPermissionStatus>(
      NotificationController.new,
    );

class NotificationSetupException implements Exception {
  const NotificationSetupException(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => '$stage 실패: $cause';
}

class NotificationController extends AsyncNotifier<PushPermissionStatus> {
  StreamSubscription<String>? _tokenSubscription;

  @override
  Future<PushPermissionStatus> build() async {
    ref.onDispose(() => _tokenSubscription?.cancel());
    final repository = ref.watch(notificationRepositoryProvider);
    final status = await repository.permissionStatus();
    if (status == PushPermissionStatus.authorized) {
      final enabled =
          await ref.read(installationIdStoreProvider).notificationsEnabled();
      if (enabled == false) return PushPermissionStatus.disabled;
      await _syncToken();
      _listenForTokenRefresh();
    }
    return status;
  }

  Future<void> enable() async {
    final repository = ref.read(notificationRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final PushPermissionStatus status;
      try {
        status = await repository.requestPermission();
      } catch (error) {
        throw NotificationSetupException('알림 권한 요청', error);
      }
      if (status == PushPermissionStatus.authorized) {
        try {
          await ref
              .read(installationIdStoreProvider)
              .setNotificationsEnabled(true);
        } catch (error) {
          throw NotificationSetupException('알림 설정 저장', error);
        }
        await _syncToken();
        _listenForTokenRefresh();
      }
      return status;
    });
  }

  Future<void> disableCurrentSubscription() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final store = ref.read(installationIdStoreProvider);
      await store.setNotificationsEnabled(false);
      _tokenSubscription?.cancel();
      _tokenSubscription = null;

      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId != null) {
        final installationId = await store.getOrCreate();
        await ref
            .read(supabaseClientProvider)
            .from('push_subscriptions')
            .update({
              'enabled': false,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('installation_id', installationId);
      }
      await ref.read(notificationRepositoryProvider).deleteToken();
      await clearAppBadge();
      return PushPermissionStatus.disabled;
    });
  }

  void _listenForTokenRefresh() {
    _tokenSubscription?.cancel();
    _tokenSubscription = ref
        .read(notificationRepositoryProvider)
        .tokenRefreshes
        .listen((token) => unawaited(_registerToken(token)));
  }

  Future<void> _syncToken() async {
    final String? token;
    try {
      token = await ref.read(notificationRepositoryProvider).token();
    } catch (error) {
      throw NotificationSetupException('FCM 토큰 발급', error);
    }
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    final String installationId;
    try {
      installationId =
          await ref.read(installationIdStoreProvider).getOrCreate();
    } catch (error) {
      throw NotificationSetupException('설치 ID 생성', error);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await ref.read(supabaseClientProvider).from('push_subscriptions').upsert({
        'user_id': userId,
        'installation_id': installationId,
        'platform': 'web',
        'token': token,
        'enabled': true,
        'last_seen_at': now,
        'updated_at': now,
      }, onConflict: 'user_id,installation_id');
    } catch (error) {
      throw NotificationSetupException('Supabase 구독 저장', error);
    }
  }
}
