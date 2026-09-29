import 'dart:typed_data';

/// Width and height in pixels, read from the image header.
typedef ImagePixelSize = ({int width, int height});

/// Reads pixel size from PNG, JPEG, GIF, or WebP bytes.
/// Returns null when the format is unrecognized.
ImagePixelSize? imagePixelSize(Uint8List bytes) {
  final png = _pngSize(bytes);
  if (png != null) return png;
  final gif = _gifSize(bytes);
  if (gif != null) return gif;
  final jpeg = _jpegSize(bytes);
  if (jpeg != null) return jpeg;
  return _webpSize(bytes);
}

ImagePixelSize? _pngSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  if (bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47) {
    return null;
  }
  final width = _u32be(bytes, 16);
  final height = _u32be(bytes, 20);
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

ImagePixelSize? _gifSize(Uint8List bytes) {
  if (bytes.length < 10) return null;
  if (bytes[0] != 0x47 || bytes[1] != 0x49 || bytes[2] != 0x46) return null;
  final width = bytes[6] | (bytes[7] << 8);
  final height = bytes[8] | (bytes[9] << 8);
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

ImagePixelSize? _jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    final isStartOfFrame =
        marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3 ||
        marker == 0xC5 ||
        marker == 0xC6 ||
        marker == 0xC7 ||
        marker == 0xC9 ||
        marker == 0xCA ||
        marker == 0xCB ||
        marker == 0xCD ||
        marker == 0xCE ||
        marker == 0xCF;
    if (isStartOfFrame) {
      final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
      if (width <= 0 || height <= 0) return null;
      return (width: width, height: height);
    }
    if (marker == 0xD9 || marker == 0xDA) return null;
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2) return null;
    offset += 2 + length;
  }
  return null;
}

ImagePixelSize? _webpSize(Uint8List bytes) {
  if (bytes.length < 30) return null;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46 ||
      bytes[8] != 0x57 ||
      bytes[9] != 0x45 ||
      bytes[10] != 0x42 ||
      bytes[11] != 0x50) {
    return null;
  }

  final chunk = String.fromCharCodes(bytes.sublist(12, 16));
  if (chunk == 'VP8X' && bytes.length >= 30) {
    final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
    final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }
  if (chunk == 'VP8 ' && bytes.length >= 30) {
    final width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
    final height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }
  if (chunk == 'VP8L' && bytes.length >= 25 && bytes[20] == 0x2F) {
    final bits =
        bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    final width = (bits & 0x3FFF) + 1;
    final height = ((bits >> 14) & 0x3FFF) + 1;
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }
  return null;
}

int _u32be(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
