import 'dart:typed_data';

import 'package:image/image.dart' as img;

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
/// NOTE on Flutter's premultiplied alpha problem:
/// Flutter's standard `ui.instantiateImageCodec` decodes images into premultiplied
/// alpha (`SkAlphaType::kPremul_SkAlphaType`), which multiplies the RGB channels
/// by `Alpha / 255`. While optimal for 2D UI compositing, this corrupts shader data
/// textures (such as 4-channel noise textures, normal maps, or lookup tables) where
/// each RGBA component represents independent mathematical data (for instance, pixels
/// with Alpha = 0 have their RGB channels zeroed out by the platform decoder).
///
/// We use `package:image` here because it decodes in pure Dart and retains raw
/// un-premultiplied (straight) alpha across all channels and image formats
/// (PNG, JPEG, WebP, BMP, GIF, TIFF, etc.) without platform-specific premultiplication.
class RawImageDecoder {
  /// Decodes [bytes] into raw 32-bit RGBA pixels without premultiplying alpha.
  static Future<DecodedImageResult?> decode(Uint8List bytes) async {
    if (bytes.length < 8) return null;

    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Extract raw 8-bit per channel RGBA bytes without alpha premultiplication.
      final rgbaBytes = image.getBytes(order: img.ChannelOrder.rgba);
      return DecodedImageResult(
        rgbaBytes: rgbaBytes,
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return null;
    }
  }
}
