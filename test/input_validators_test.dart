import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/core/validation/input_validators.dart';

void main() {
  group('nickname validation', () {
    test('trims and accepts a valid nickname', () {
      expect(InputValidators.normalizeNickname('  망고  '), '망고');
      expect(InputValidators.nickname('  망고  '), isNull);
    });

    test('rejects invalid nicknames', () {
      expect(InputValidators.nickname('  '), isNotNull);
      expect(InputValidators.nickname('a'), isNotNull);
      expect(InputValidators.nickname('a' * 21), isNotNull);
    });
  });

  test('message validation rejects blank and overly long values', () {
    expect(InputValidators.message('  '), isNotNull);
    expect(InputValidators.message('a' * 2001), isNotNull);
    expect(InputValidators.message('안녕하세요'), isNull);
  });
}
