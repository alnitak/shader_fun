import 'dart:typed_data';
import 'dart:ui' as ui;

/// Extracts sound pass PCM bytes from a rendered [uiImage] on web platforms.
Future<Uint8List?> extractSoundPassPcmBytes(
  ui.Image uiImage,
  int width,
  int height,
) async {
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
