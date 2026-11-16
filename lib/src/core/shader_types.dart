/// Pure-Dart shader pass types and uniform buffer constants shared by runtime
/// compilers and build-time hooks (which run on the standalone Dart VM without
/// `dart:ui` or `package:flutter`).
library;

/// Supported render pass types.
enum PassType { image, bufferA, bufferB, bufferC, bufferD, common, sound }

/// The rendering and authoring mode for a shader pass.
enum ShaderPassMode {
  /// Standard ShaderToy compatibility: user writes mainImage(), and shader_fun
  /// wraps it with Vulkan/WebGL2 headers, standard FrameInfo uniforms, and a full-screen quad.
  shaderToy,

  /// Raw / Custom shader: user provides custom vertex and/or fragment GLSL with standard main(),
  /// without ShaderToy boilerplate or automatic wrapping.
  custom,
}

extension PassTypeExtension on PassType {
  String get displayName {
    switch (this) {
      case PassType.image:
        return 'Image';
      case PassType.bufferA:
        return 'Buffer A';
      case PassType.bufferB:
        return 'Buffer B';
      case PassType.bufferC:
        return 'Buffer C';
      case PassType.bufferD:
        return 'Buffer D';
      case PassType.common:
        return 'Common';
      case PassType.sound:
        return 'Sound';
    }
  }

  bool get isBuffer =>
      this == PassType.bufferA ||
      this == PassType.bufferB ||
      this == PassType.bufferC ||
      this == PassType.bufferD;

  bool get isImage => this == PassType.image;
  bool get isCommon => this == PassType.common;
  bool get isSound => this == PassType.sound;
}

/// Standard uniform block size in bytes (`iResolution`, `iTime`, etc.).
const int kStandardUniformsSizeBytes = 144;

/// Maximum number of generic `vec4` custom uniform registers (16 vec4s = 64 floats = 256 bytes).
const int kMaxCustomUniformSlots = 16;

/// Byte size reserved for custom uniforms (16 bytes per `vec4` register).
const int kCustomUniformsSizeBytes = kMaxCustomUniformSlots * 16;

/// Total uniform buffer size in bytes uploaded to the GPU `FrameInfo` block.
const int kTotalUniformBufferSize =
    kStandardUniformsSizeBytes + kCustomUniformsSizeBytes;
