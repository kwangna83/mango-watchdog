import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/domain/image_dimensions.dart';

void main() {
  group('readImageDimensions', () {
    test('reads PNG IHDR dimensions without dart:ui web APIs', () async {
      final bytes = Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        7,
        128,
        0,
        0,
        4,
        56,
      ]);

      final dimensions = await readImageDimensions(bytes);

      expect(dimensions.width, 1920);
      expect(dimensions.height, 1080);
    });

    test('reads JPEG start-of-frame dimensions', () async {
      final bytes = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe0,
        0x00,
        0x04,
        0x00,
        0x00,
        0xff,
        0xc0,
        0x00,
        0x0b,
        0x08,
        0x04,
        0x38,
        0x07,
        0x80,
        0x01,
        0x01,
        0x11,
        0x00,
        0xff,
        0xd9,
      ]);

      final dimensions = await readImageDimensions(bytes);

      expect(dimensions.width, 1920);
      expect(dimensions.height, 1080);
    });

    test('reads extended WebP canvas dimensions', () async {
      final bytes = Uint8List.fromList([
        82,
        73,
        70,
        70,
        22,
        0,
        0,
        0,
        87,
        69,
        66,
        80,
        86,
        80,
        56,
        88,
        10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x7f,
        0x07,
        0x00,
        0x37,
        0x04,
        0x00,
      ]);

      final dimensions = await readImageDimensions(bytes);

      expect(dimensions.width, 1920);
      expect(dimensions.height, 1080);
    });

    test('rejects unsupported or truncated image bytes', () async {
      await expectLater(
        readImageDimensions(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
