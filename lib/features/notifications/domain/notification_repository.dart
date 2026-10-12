enum PushPermissionStatus {
  unsupported,
  notDetermined,
  denied,
  disabled,
  authorized,
}

abstract interface class NotificationRepository {
  bool get isSupported;

  Future<PushPermissionStatus> permissionStatus();

  Future<PushPermissionStatus> requestPermission();

  Future<String?> token();

  Stream<String> get tokenRefreshes;

  Future<void> deleteToken();
}
