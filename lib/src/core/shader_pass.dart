// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';

import 'package:listen/listen.dart' as listen;

import '../channels/shader_channel.dart';

/// Supported render pass types.
enum PassType { image, bufferA, bufferB, bufferC, bufferD, common, sound }

/// The rendering and authoring mode for a [ShaderPass].
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

/// Represents an individual rendering pass in a project.
/// Implements [listen.ChangeNotifier] to dispatch notifications upon code or channel changes.
class ShaderPass with listen.ChangeNotifier {
  ShaderPass({
    required this.type,
    required this.name,
    required String code,
    String? vertexCode,
    ShaderPassMode mode = ShaderPassMode.shaderToy,
    int? vertexCount,
    Float32List? customVertices,
    List<ShaderChannel?>? channels,
    bool enabled = true,
  }) : _code = code,
       _vertexCode = vertexCode,
       _mode = mode,
       _vertexCount =
           vertexCount ??
           (customVertices != null ? customVertices.length ~/ 2 : 6),
       _customVertices = customVertices,
       _enabled = enabled,
       channels = channels ?? List<ShaderChannel?>.filled(4, null);

  final PassType type;
  String name;
  String _code;
  String? _vertexCode;
  ShaderPassMode _mode;
  int _vertexCount;
  Float32List? _customVertices;
  bool _enabled;

  String get code => _code;
  set code(String value) {
    if (_code != value) {
      _code = value;
      notifyListeners();
    }
  }

  /// Custom vertex shader GLSL code.
  /// Used when [mode] is [ShaderPassMode.custom] or when providing a custom vertex stage.
  String? get vertexCode => _vertexCode;
  set vertexCode(String? value) {
    if (_vertexCode != value) {
      _vertexCode = value;
      notifyListeners();
    }
  }

  /// The rendering mode for this pass. Defaults to [ShaderPassMode.shaderToy].
  ShaderPassMode get mode => _mode;
  set mode(ShaderPassMode value) {
    if (_mode != value) {
      _mode = value;
      notifyListeners();
    }
  }

  /// The number of vertices to draw for this pass (defaults to 6 for standard quads).
  int get vertexCount => _vertexCount;
  set vertexCount(int value) {
    if (_vertexCount != value) {
      _vertexCount = value;
      notifyListeners();
    }
  }

  /// Optional custom vertex buffer data.
  /// If provided, this data is uploaded to a GPU device buffer and bound for draw calls.
  /// If null, the standard full-screen quad vertex buffer is used.
  Float32List? get customVertices => _customVertices;
  set customVertices(Float32List? value) {
    if (_customVertices != value) {
      _customVertices = value;
      if (value != null && _vertexCount == 6) {
        _vertexCount = value.length ~/ 2;
      }
      notifyListeners();
    }
  }

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;
      notifyListeners();
    }
  }

  /// The 4 iChannel slots for this pass (iChannel0..iChannel3)
  final List<ShaderChannel?> channels;

  ShaderChannel? getChannel(int index) {
    if (index >= 0 && index < channels.length) {
      return channels[index];
    }
    return null;
  }

  void setChannel(int index, ShaderChannel? channel) {
    if (index >= 0 && index < channels.length) {
      if (channels[index] != null && channels[index] != channel) {
        channels[index]?.dispose();
      }
      channels[index] = channel;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final ch in channels) {
      ch?.dispose();
    }
    super.dispose();
  }
}
