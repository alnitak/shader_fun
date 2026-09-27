import 'dart:typed_data';

import '../gpu/gpu.dart' as gpu;

/// Extracts sound pass PCM bytes from a rendered [soundTexture] on unsupported/stub platforms.
Future<Uint8List?> extractSoundPassPcmBytes(
  gpu.Texture soundTexture,
  int width,
  int height,
) async {
  return null;
}
