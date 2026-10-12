import '../constants/chat_constants.dart';

class InputValidators {
  const InputValidators._();

  static String normalizeNickname(String value) => value.trim();

  static String? nickname(String? value) {
    if (value == null) return '닉네임을 입력해주세요.';
    final normalized = normalizeNickname(value);
    if (normalized.isEmpty) return '닉네임을 입력해주세요.';
    if (normalized.length < ChatConstants.minNicknameLength ||
        normalized.length > ChatConstants.maxNicknameLength) {
      return '닉네임은 2자 이상 20자 이하로 입력해주세요.';
    }
    return null;
  }

  static String normalizeMessage(String value) => value.trim();

  static String? message(String? value) {
    if (value == null) return '메시지를 입력해주세요.';
    final normalized = normalizeMessage(value);
    if (normalized.isEmpty) return '메시지를 입력해주세요.';
    if (normalized.length > ChatConstants.maxMessageLength) {
      return '메시지는 2,000자 이하로 입력해주세요.';
    }
    return null;
  }
}
