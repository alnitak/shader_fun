import 'dart:typed_data';
import 'dart:ui' as ui;

/// Extracts sound pass PCM bytes from a rendered [uiImage] on IO (native) platforms.
Future<Uint8List?> extractSoundPassPcmBytes(
  ui.Image uiImage,
  int width,
  int height,
) async {
  try {
    final byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    );
    if (byteData != null) {
      final floatData = byteData.buffer.asFloat32List(
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 4,
      );
      final stereoFloats = Float32List(width * height * 2);
      for (
        int p = 0, s = 0;
        p < floatData.length && s < stereoFloats.length;
        p += 4, s += 2
      ) {
        stereoFloats[s] = floatData[p];
        stereoFloats[s + 1] = floatData[p + 1];
      }
      return stereoFloats.buffer.asUint8List();
    }
  } catch (_) {}

  // Fallback if rawExtendedRgba128 is not supported
  final byteData8 = await uiImage.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (byteData8 != null) {
    final u8Data = byteData8.buffer.asUint8List(
      byteData8.offsetInBytes,
      byteData8.lengthInBytes,
    );
    final stereoFloats = Float32List(width * height * 2);
    for (
      int p = 0, s = 0;
      p < u8Data.length && s < stereoFloats.length;
      p += 4, s += 2
    ) {
      stereoFloats[s] = (u8Data[p] / 127.5) - 1.0;
      stereoFloats[s + 1] = (u8Data[p + 1] / 127.5) - 1.0;
    }
    return stereoFloats.buffer.asUint8List();
  }
  return null;
}
