import 'dart:typed_data';

import 'app_user.dart';

abstract interface class AuthRepository {
  Future<AppUser?> restoreSession();
  Future<AppUser> signInAnonymously(String nickname);
  Future<AppUser> updateProfile({
    required String nickname,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    bool deleteAvatar = false,
  });
  Future<void> signOut();
}
