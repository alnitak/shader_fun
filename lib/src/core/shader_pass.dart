import 'package:listen/listen.dart' as listen;

import '../channels/shader_channel.dart';

/// Supported render pass types.
enum PassType { image, bufferA, bufferB, bufferC, bufferD, common, sound }

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
    List<ShaderChannel?>? channels,
    bool enabled = true,
  }) : //
       // ignore: prefer_initializing_formals
       _code = code,
       // ignore: prefer_initializing_formals
       _enabled = enabled,
       channels = channels ?? List<ShaderChannel?>.filled(4, null);

  final PassType type;
  String name;
  String _code;
  bool _enabled;

  String get code => _code;
  set code(String value) {
    if (_code != value) {
      _code = value;
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
