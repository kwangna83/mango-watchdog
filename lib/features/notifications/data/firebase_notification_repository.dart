import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/notification_repository.dart';
import 'push_context_support.dart';

class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository({required this.vapidKey});

  final String? vapidKey;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  bool get isSupported => Firebase.apps.isNotEmpty && isPushContextSupported;

  @override
  Future<PushPermissionStatus> permissionStatus() async {
    if (!isSupported) return PushPermissionStatus.unsupported;
    return _map(
      (await _messaging.getNotificationSettings()).authorizationStatus,
    );
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    if (!isSupported) return PushPermissionStatus.unsupported;
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return _map(settings.authorizationStatus);
  }

  @override
  Future<String?> token() async {
    if (!isSupported) return null;
    return _messaging.getToken(
      vapidKey: vapidKey,
      serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
    );
  }

  @override
  Stream<String> get tokenRefreshes =>
      isSupported ? _messaging.onTokenRefresh : const Stream.empty();

  @override
  Future<void> deleteToken() async {
    if (isSupported) await _messaging.deleteToken();
  }

  PushPermissionStatus _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushPermissionStatus.authorized,
    AuthorizationStatus.denied => PushPermissionStatus.denied,
    AuthorizationStatus.notDetermined => PushPermissionStatus.notDetermined,
  };
}
