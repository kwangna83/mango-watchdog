import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;
  static const _avatarBucket = 'profile-images';

  @override
  Future<AppUser?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final profile =
        await _client
            .from('profiles')
            .select('id, nickname, avatar_path')
            .eq('id', user.id)
            .maybeSingle();
    if (profile == null) return null;
    return _user(profile);
  }

  @override
  Future<AppUser> signInAnonymously(String nickname) async {
    var user = _client.auth.currentUser;
    if (user == null) {
      final response = await _client.auth.signInAnonymously();
      user = response.user;
    }
    if (user == null) throw const AuthException('익명 로그인에 실패했습니다.');

    final profile =
        await _client
            .from('profiles')
            .upsert({'id': user.id, 'nickname': nickname.trim()})
            .select('id, nickname, avatar_path')
            .single();
    return _user(profile);
  }

  @override
  Future<AppUser> updateProfile({
    required String nickname,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    bool deleteAvatar = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('로그인이 필요합니다.');
    final current =
        await _client
            .from('profiles')
            .select('avatar_path')
            .eq('id', user.id)
            .single();
    final oldPath = current['avatar_path'] as String?;
    String? newPath = oldPath;

    if (avatarBytes != null && avatarMimeType != null) {
      final extension = _extensionFor(avatarMimeType);
      newPath =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _client.storage
          .from(_avatarBucket)
          .uploadBinary(
            newPath,
            avatarBytes,
            fileOptions: FileOptions(
              contentType: avatarMimeType,
              upsert: false,
            ),
          );
    } else if (deleteAvatar) {
      newPath = null;
    }

    try {
      final profile =
          await _client
              .from('profiles')
              .update({
                'nickname': nickname.trim(),
                'avatar_path': newPath,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', user.id)
              .select('id, nickname, avatar_path')
              .single();
      if (oldPath != null && oldPath != newPath) {
        await _removeAvatar(oldPath);
      }
      return _user(profile);
    } catch (_) {
      if (newPath != null && newPath != oldPath) await _removeAvatar(newPath);
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);

  AppUser _user(Map<String, dynamic> profile) {
    final path = profile['avatar_path'] as String?;
    return AppUser.fromJson({
      ...profile,
      'avatar_url':
          path == null
              ? null
              : _client.storage.from(_avatarBucket).getPublicUrl(path),
    });
  }

  Future<void> _removeAvatar(String path) async {
    try {
      await _client.storage.from(_avatarBucket).remove([path]);
    } catch (_) {
      // The profile update must remain valid even if old-file cleanup fails.
    }
  }

  String _extensionFor(String mimeType) => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw ArgumentError.value(mimeType, 'mimeType', '지원하지 않는 이미지 형식'),
  };
}
