import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Result of decoding an image into raw 32-bit RGBA pixel bytes without
/// alpha premultiplication.
class DecodedImageResult {
  const DecodedImageResult({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });

  /// 32-bit RGBA un-premultiplied pixel bytes (stride = width * 4).
  final Uint8List rgbaBytes;
  final int width;
  final int height;
}

/// Image decoder that preserves un-premultiplied color and alpha channels.
///
/// Flutter's standard [ui.instantiateImageCodec] decodes images into premultiplied
/// alpha (`SkAlphaType::kPremul_SkAlphaType`), which multiplies the RGB channels
/// by `Alpha / 255`. While optimal for 2D UI rendering, this corrupts shader data
/// textures (such as 4-channel noise textures, normal maps, or lookup tables) where
/// each RGBA component represents independent floating-point data.
///
/// [RawImageDecoder] parses standard PNGs directly in Dart to retain raw
/// un-premultiplied data, and falls back to [ui.instantiateImageCodec] for other
/// formats (such as JPEG, which has no alpha channel anyway).
class RawImageDecoder {
  static const List<int> _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  /// Decodes [bytes] into raw 32-bit RGBA pixels without premultiplying alpha.
  static Future<DecodedImageResult?> decode(Uint8List bytes) async {
    if (bytes.length < 8) return null;

    // 1. Check for PNG signature
    bool isPng = true;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _pngSignature[i]) {
        isPng = false;
        break;
      }
    }

    if (isPng) {
      try {
        final pngResult = _decodePng(bytes);
        if (pngResult != null) return pngResult;
      } catch (_) {
        // Fallback to platform decoder if custom PNG parser encounters an unhandled feature
      }
    }

    // 2. Fallback to platform codec (e.g. for JPEG, WebP, or complex PNGs)
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      return DecodedImageResult(
        rgbaBytes: byteData.buffer.asUint8List(),
        width: frame.image.width,
        height: frame.image.height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses a non-interlaced 8-bit PNG (RGBA, RGB, Grayscale, Grayscale+Alpha)
  /// without premultiplying alpha.
  static DecodedImageResult? _decodePng(Uint8List bytes) {
    if (bytes.length < 33) return null;

    int offset = 8;
    int? width;
    int? height;
    int? bitDepth;
    int? colorType;
    int? compressionMethod;
    int? filterMethod;
    int? interlaceMethod;

    final idatChunks = <Uint8List>[];

    while (offset + 8 <= bytes.length) {
      final length = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;

      if (dataEnd > bytes.length) return null;

      if (type == 'IHDR') {
        if (length < 13) return null;
        width = (bytes[dataStart] << 24) |
            (bytes[dataStart + 1] << 16) |
            (bytes[dataStart + 2] << 8) |
            bytes[dataStart + 3];
        height = (bytes[dataStart + 4] << 24) |
            (bytes[dataStart + 5] << 16) |
            (bytes[dataStart + 6] << 8) |
            bytes[dataStart + 7];
        bitDepth = bytes[dataStart + 8];
        colorType = bytes[dataStart + 9];
        compressionMethod = bytes[dataStart + 10];
        filterMethod = bytes[dataStart + 11];
        interlaceMethod = bytes[dataStart + 12];
      } else if (type == 'IDAT') {
        idatChunks.add(bytes.sublist(dataStart, dataEnd));
      } else if (type == 'IEND') {
        break;
      }

      offset = dataEnd + 4; // Skip 4-byte CRC
    }

    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        bitDepth != 8 ||
        compressionMethod != 0 ||
        filterMethod != 0 ||
        interlaceMethod != 0 ||
        idatChunks.isEmpty) {
      return null;
    }

    // Determine bytes per pixel in raw scanline
    int bpp;
    switch (colorType) {
      case 0: // Grayscale
        bpp = 1;
        break;
      case 2: // Truecolor RGB
        bpp = 3;
        break;
      case 4: // Grayscale with alpha
        bpp = 2;
        break;
      case 6: // Truecolor RGBA
        bpp = 4;
        break;
      default:
        // Palette / indexed or other formats -> fallback to platform codec
        return null;
    }

    // Concatenate IDAT data
    final totalIdatLen = idatChunks.fold<int>(0, (sum, c) => sum + c.length);
    final idatBytes = Uint8List(totalIdatLen);
    int idatPos = 0;
    for (final chunk in idatChunks) {
      idatBytes.setRange(idatPos, idatPos + chunk.length, chunk);
      idatPos += chunk.length;
    }

    // Decompress scanlines with zlib
    final decompressed = Uint8List.fromList(zlib.decode(idatBytes));
    final expectedLen = (width * bpp + 1) * height;
    if (decompressed.length < expectedLen) return null;

    final scanlineStride = width * bpp;
    final uncompressedScanlines = Uint8List(width * height * bpp);

    var inOffset = 0;
    var outOffset = 0;

    for (int y = 0; y < height; y++) {
      final filterType = decompressed[inOffset++];
      for (int x = 0; x < scanlineStride; x++) {
        final val = decompressed[inOffset++];
        final a = (x >= bpp)
            ? uncompressedScanlines[outOffset + x - bpp]
            : 0;
        final b = (y > 0)
            ? uncompressedScanlines[outOffset - scanlineStride + x]
            : 0;
        final c = (x >= bpp && y > 0)
            ? uncompressedScanlines[outOffset - scanlineStride + x - bpp]
            : 0;

        int reconstructed = val;
        switch (filterType) {
          case 0: // None
            reconstructed = val;
            break;
          case 1: // Sub
            reconstructed = (val + a) & 0xFF;
            break;
          case 2: // Up
            reconstructed = (val + b) & 0xFF;
            break;
          case 3: // Average
            reconstructed = (val + ((a + b) >> 1)) & 0xFF;
            break;
          case 4: // Paeth
            final p = a + b - c;
            final pa = (p - a).abs();
            final pb = (p - b).abs();
            final pc = (p - c).abs();
            final pr = (pa <= pb && pa <= pc) ? a : ((pb <= pc) ? b : c);
            reconstructed = (val + pr) & 0xFF;
            break;
          default:
            return null;
        }
        uncompressedScanlines[outOffset + x] = reconstructed;
      }
      outOffset += scanlineStride;
    }

    // Convert to RGBA8888 if necessary
    final rgba = Uint8List(width * height * 4);
    if (colorType == 6) {
      // Already RGBA8888
      rgba.setRange(0, rgba.length, uncompressedScanlines);
    } else if (colorType == 2) {
      // RGB -> RGBA
      int srcIdx = 0;
      int dstIdx = 0;
      final totalPixels = width * height;
      for (int i = 0; i < totalPixels; i++) {
        rgba[dstIdx] = uncompressedScanlines[srcIdx];
        rgba[dstIdx + 1] = uncompressedScanlines[srcIdx + 1];
        rgba[dstIdx + 2] = uncompressedScanlines[srcIdx + 2];
        rgba[dstIdx + 3] = 255;
        srcIdx += 3;
        dstIdx += 4;
      }
    } else if (colorType == 0) {
      // Grayscale -> RGBA
      int srcIdx = 0;
      int dstIdx = 0;
      final totalPixels = width * height;
      for (int i = 0; i < totalPixels; i++) {
        final g = uncompressedScanlines[srcIdx++];
        rgba[dstIdx] = g;
        rgba[dstIdx + 1] = g;
        rgba[dstIdx + 2] = g;
        rgba[dstIdx + 3] = 255;
        dstIdx += 4;
      }
    } else if (colorType == 4) {
      // Grayscale + Alpha -> RGBA
      int srcIdx = 0;
      int dstIdx = 0;
      final totalPixels = width * height;
      for (int i = 0; i < totalPixels; i++) {
        final g = uncompressedScanlines[srcIdx];
        final a = uncompressedScanlines[srcIdx + 1];
        rgba[dstIdx] = g;
        rgba[dstIdx + 1] = g;
        rgba[dstIdx + 2] = g;
        rgba[dstIdx + 3] = a;
        srcIdx += 2;
        dstIdx += 4;
      }
    }

    return DecodedImageResult(
      rgbaBytes: rgba,
      width: width,
      height: height,
    );
  }
}
