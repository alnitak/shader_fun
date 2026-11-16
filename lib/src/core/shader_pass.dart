// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';

import 'package:listen/listen.dart' as listen;

import '../channels/shader_channel.dart';
import 'shader_types.dart';

export 'shader_types.dart';

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
