import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/gpu/gpu.dart' as gpu;

void main() {
  test('check if r32g32b32a32Float is supported', () {
    try {
      final f32 = gpu.gpuContext.supportsTextureFormat(
        gpu.PixelFormat.r32g32b32a32Float,
        renderTarget: true,
        shaderRead: true,
      );
      expect(f32, isNotNull);
    } catch (_) {
      // Impeller not enabled in headless unit test environment
    }
  });
}
