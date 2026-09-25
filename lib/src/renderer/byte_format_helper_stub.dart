import 'dart:typed_data';
import 'dart:ui' as ui;

/// Extracts sound pass PCM bytes from a rendered [uiImage] on web platforms.
///
/// NOTE: On Flutter Web (`dart:ui`), [ui.ImageByteFormat.rawExtendedRgba128]
/// is not available yet. As a result, [ui.ImageByteFormat.rawStraightRgba] (8-bit UNorm)
/// is used as a fallback to extract audio data. Because 8-bit quantization only provides
/// 256 discrete levels (~48 dB dynamic range), some background rustle/noise or distortion
/// is expected on Web compared to native 32-bit floating-point execution until Flutter Web
/// adds support for floating-point pixel buffer readouts.
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
