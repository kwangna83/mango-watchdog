import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class InstallationIdStore {
  InstallationIdStore(this._preferences);

  static const _key = 'push_installation_id';
  static const _notificationsEnabledKey = 'push_notifications_enabled';
  final SharedPreferencesAsync _preferences;

  Future<String> getOrCreate() async {
    final existing = await _preferences.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _preferences.setString(_key, created);
    return created;
  }

  Future<bool?> notificationsEnabled() =>
      _preferences.getBool(_notificationsEnabledKey);

  Future<void> setNotificationsEnabled(bool enabled) =>
      _preferences.setBool(_notificationsEnabledKey, enabled);
}
