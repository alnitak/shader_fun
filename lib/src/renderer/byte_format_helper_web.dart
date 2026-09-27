// ignore_for_file: implementation_imports
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as web_gpu;
import 'package:web/web.dart' as web;

import '../gpu/gpu.dart' as gpu;

/// Extracts sound pass PCM bytes from a rendered [soundTexture] on Web platforms.
///
/// Bypasses `dart:ui`'s missing `rawExtendedRgba128` support on Web by reading
/// pixels directly from the WebGL2 framebuffer using `gl.readPixels`.
///
/// If [soundTexture] was created with [gpu.PixelFormat.r32g32b32a32Float],
/// this reads full 32-bit floating-point audio with zero quantization loss.
Future<Uint8List?> extractSoundPassPcmBytes(
  gpu.Texture soundTexture,
  int width,
  int height,
) async {
  try {
    final webTex = soundTexture as web_gpu.Texture;
    final gl = web_gpu.gpuContext.gl;
    final glTexture = webTex.glTexture;
    if (glTexture == null) return null;

    final fbo = gl.createFramebuffer();
    if (fbo == null) return null;

    try {
      gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);
      gl.framebufferTexture2D(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.TEXTURE_2D,
        glTexture,
        0,
      );

      final status =
          gl.checkFramebufferStatus(web.WebGL2RenderingContext.FRAMEBUFFER);
      if (status != web.WebGL2RenderingContext.FRAMEBUFFER_COMPLETE) {
        return null;
      }

      final isFloat =
          soundTexture.format == gpu.PixelFormat.r32g32b32a32Float;
      if (isFloat) {
        final jsArray = JSFloat32Array.withLength(width * height * 4);
        gl.readPixels(
          0,
          0,
          width,
          height,
          web.WebGL2RenderingContext.RGBA,
          web.WebGL2RenderingContext.FLOAT,
          jsArray,
          0,
        );

        final floatData = jsArray.toDart;
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
      } else {
        // Fallback for 8-bit unorm texture
        final jsArray = JSUint8Array.withLength(width * height * 4);
        gl.readPixels(
          0,
          0,
          width,
          height,
          web.WebGL2RenderingContext.RGBA,
          web.WebGL2RenderingContext.UNSIGNED_BYTE,
          jsArray,
          0,
        );

        final u8Data = jsArray.toDart;
        final stereoFloats = Float32List(width * height * 2);
        for (
          int p = 0, s = 0;
          p < u8Data.length && s < stereoFloats.length;
          p += 4, s += 2
        ) {
          stereoFloats[s] = (u8Data[p] / 255.0) * 2.0 - 1.0;
          stereoFloats[s + 1] = (u8Data[p + 1] / 255.0) * 2.0 - 1.0;
        }
        return stereoFloats.buffer.asUint8List();
      }
    } finally {
      gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
      gl.deleteFramebuffer(fbo);
    }
  } catch (e, st) {
    debugPrint('extractSoundPassPcmBytes web error: $e\n$st');
    return null;
  }
}
