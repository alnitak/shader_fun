// Internal GPU shim adapter forwarding to flutter_scene's cross-platform GPU pipeline.
// On native (Impeller), this re-exports package:flutter_gpu verbatim.
// On Web, this provides the WebGL2 implementation with synchronous Texture.asImage().
// ignore_for_file: implementation_imports
import 'dart:math' as math;
import 'package:flutter_scene/src/gpu/gpu.dart';

export 'package:flutter_scene/src/gpu/gpu.dart';

extension GpuContextExt on GpuContext {
  /// Probes whether a given [format] is supported by testing a minimal texture allocation.
  bool supportsTextureFormat(
    PixelFormat format, {
    bool renderTarget = false,
    bool shaderRead = false,
  }) {
    try {
      final tex = createTexture(
        StorageMode.devicePrivate,
        1,
        1,
        format: format,
        enableRenderTargetUsage: renderTarget,
        enableShaderReadUsage: shaderRead,
      );
      return tex.isValid;
    } catch (_) {
      return false;
    }
  }
}

extension TextureMipExt on Texture {
  /// Calculates the mip level width for 2D textures.
  int getMipLevelWidth(int level) => math.max(1, width >> level);

  /// Calculates the mip level height for 2D textures.
  int getMipLevelHeight(int level) => math.max(1, height >> level);
}
