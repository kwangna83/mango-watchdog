import 'dart:typed_data';

class ImageDimensions {
  const ImageDimensions({required this.width, required this.height})
    : assert(width > 0),
      assert(height > 0);

  final int width;
  final int height;

  double get aspectRatio => width / height;
}

Future<ImageDimensions> readImageDimensions(Uint8List bytes) async {
  final dimensions =
      _readPngDimensions(bytes) ??
      _readJpegDimensions(bytes) ??
      _readWebpDimensions(bytes);
  if (dimensions == null || dimensions.width <= 0 || dimensions.height <= 0) {
    throw const FormatException('이미지 크기를 확인할 수 없습니다.');
  }
  return dimensions;
}

ImageDimensions? _readPngDimensions(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) return null;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return null;
  }
  if (!_matchesAscii(bytes, 12, 'IHDR')) return null;
  return ImageDimensions(
    width: _uint32BigEndian(bytes, 16),
    height: _uint32BigEndian(bytes, 20),
  );
}

ImageDimensions? _readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return null;
  }
  var offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset] != 0xff) {
      offset++;
      continue;
    }
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) break;
    final marker = bytes[offset++];
    if (marker == 0xd9 || marker == 0xda) break;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) break;
    final segmentLength = _uint16BigEndian(bytes, offset);
    if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
    if (_isJpegStartOfFrame(marker) && segmentLength >= 7) {
      return ImageDimensions(
        width: _uint16BigEndian(bytes, offset + 5),
        height: _uint16BigEndian(bytes, offset + 3),
      );
    }
    offset += segmentLength;
  }
  return null;
}

bool _isJpegStartOfFrame(int marker) =>
    marker >= 0xc0 &&
    marker <= 0xcf &&
    marker != 0xc4 &&
    marker != 0xc8 &&
    marker != 0xcc;

ImageDimensions? _readWebpDimensions(Uint8List bytes) {
  if (bytes.length < 20 ||
      !_matchesAscii(bytes, 0, 'RIFF') ||
      !_matchesAscii(bytes, 8, 'WEBP')) {
    return null;
  }
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkSize = _uint32LittleEndian(bytes, offset + 4);
    final dataOffset = offset + 8;
    final dataEnd = dataOffset + chunkSize;
    if (dataEnd > bytes.length) return null;
    if (_matchesAscii(bytes, offset, 'VP8X') && chunkSize >= 10) {
      return ImageDimensions(
        width: 1 + _uint24LittleEndian(bytes, dataOffset + 4),
        height: 1 + _uint24LittleEndian(bytes, dataOffset + 7),
      );
    }
    if (_matchesAscii(bytes, offset, 'VP8L') &&
        chunkSize >= 5 &&
        bytes[dataOffset] == 0x2f) {
      final bits = _uint32LittleEndian(bytes, dataOffset + 1);
      return ImageDimensions(
        width: 1 + (bits & 0x3fff),
        height: 1 + ((bits >> 14) & 0x3fff),
      );
    }
    if (_matchesAscii(bytes, offset, 'VP8 ') &&
        chunkSize >= 10 &&
        bytes[dataOffset + 3] == 0x9d &&
        bytes[dataOffset + 4] == 0x01 &&
        bytes[dataOffset + 5] == 0x2a) {
      return ImageDimensions(
        width: _uint16LittleEndian(bytes, dataOffset + 6) & 0x3fff,
        height: _uint16LittleEndian(bytes, dataOffset + 8) & 0x3fff,
      );
    }
    offset = dataEnd + (chunkSize.isOdd ? 1 : 0);
  }
  return null;
}

bool _matchesAscii(Uint8List bytes, int offset, String value) {
  if (offset < 0 || offset + value.length > bytes.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) return false;
  }
  return true;
}

int _uint16BigEndian(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _uint16LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint24LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

int _uint32BigEndian(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _uint32LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
