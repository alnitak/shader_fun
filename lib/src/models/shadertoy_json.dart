// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:flutter/services.dart';

import '../channels/audio_texture_provider.dart';
import '../channels/shader_channel.dart';
import '../core/shader_pass.dart';

/// Represents a complete ShaderToy project containing metadata and passes.
class ShaderToyProject {
  ShaderToyProject({
    String id = '',
    String name = 'New Shader',
    String author = 'Anonymous',
    String description = '',
    String url = '',
    List<String> tags = const [],
    List<ShaderPass>? passes,
  })  : _id = id,
        _name = name,
        _author = author,
        _description = description,
        _url = url,
        _tags = tags,
        passes = passes ?? [];

  /// Creates a default starter ShaderToy project with a single Image pass.
  factory ShaderToyProject.empty() {
    return ShaderToyProject(
      id: 'new',
      name: 'New Shader',
      url: '',
      passes: [
        ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: '''void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord/iResolution.xy;

    // Time varying pixel color
    vec3 col = 0.5 + 0.5*cos(iTime+uv.xyx+vec3(0,2,4));

    // Output to screen
    fragColor = vec4(col,1.0);
}
''',
        ),
      ],
    );
  }

  String? _id;
  String get id => _id ?? '';
  set id(String value) => _id = value;

  String? _name;
  String get name => _name ?? 'New Shader';
  set name(String value) => _name = value;

  String? _author;
  String get author => _author ?? 'Anonymous';
  set author(String value) => _author = value;

  String? _description;
  String get description => _description ?? '';
  set description(String value) => _description = value;

  String? _url;
  String get url => _url ?? '';
  set url(String value) => _url = value;

  List<String>? _tags;
  List<String> get tags => _tags ?? const [];
  set tags(List<String> value) => _tags = value;

  List<ShaderPass> passes;

  /// Built-in preset example asset filenames located in `assets/examples/`.
  static const List<String> exampleAssets = [
    'mouse_paint_eroded_mountains.json',
    'raymarching_primitives.json',
    'audio_reactive_tunnel.json',
    'temporal_feedback.json',
    'cosine_palette_fractal.json',
  ];

  /// Loads a [ShaderToyProject] from a Flutter asset using [rootBundle] or a provided [bundle].
  ///
  /// [assetPathOrName] can be a simple file name (e.g. `'raymarching_primitives.json'`)
  /// or a full asset path (e.g. `'assets/examples/raymarching_primitives.json'`).
  static Future<ShaderToyProject> loadFromAsset(
    String assetPathOrName, {
    AssetBundle? bundle,
  }) async {
    final path = assetPathOrName.startsWith('assets/')
        ? assetPathOrName
        : 'assets/examples/$assetPathOrName';
    final effectiveBundle = bundle ?? rootBundle;
    final jsonString = await effectiveBundle.loadString(path);
    return ShaderToyProject.parseJsonString(jsonString);
  }

  ShaderPass? getPass(PassType type) {
    for (final pass in passes) {
      if (pass.type == type) return pass;
    }
    return null;
  }

  ShaderPass? get imagePass => getPass(PassType.image);
  ShaderPass? get commonPass => getPass(PassType.common);

  bool hasPass(PassType type) => getPass(type) != null;

  /// Whether any pass references `iMouse` in its shader code.
  bool get usesMouse {
    final mouseRegex = RegExp(r'\biMouse\b');
    return passes.any((p) => mouseRegex.hasMatch(p.code));
  }

  /// Whether the project uses audio (audio/music channel, excluding mic).
  bool get usesAudio {
    return passes.any(
      (p) => p.channels.any(
        (c) =>
            c is SoLoudAudioChannel ||
            (c is AudioChannel && c is! MicAudioChannel),
      ),
    );
  }

  /// Whether any pass uses a microphone audio channel.
  bool get usesMic {
    return passes.any((p) => p.channels.any((c) => c is MicAudioChannel));
  }

  /// Whether any pass uses a keyboard input channel.
  bool get usesKeys {
    return passes.any((p) => p.channels.any((c) => c is KeyboardChannel));
  }

  /// Whether any pass uses 2D image textures or cubemap channels.
  bool get usesTextures {
    return passes.any(
      (p) => p.channels.any(
        (c) => c is TextureChannel || c is CubeMapChannel,
      ),
    );
  }

  /// Default starter GLSL template for each pass type.
  static String defaultCodeForPass(PassType type) {
    switch (type) {
      case PassType.common:
        return '''// Common code shared across all passes
// Place shared constants, structs, and helper functions here.

#define PI 3.14159265359

vec2 rot(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c) * p;
}
''';
      case PassType.image:
        return '''void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord/iResolution.xy;

    // Time varying pixel color
    vec3 col = 0.5 + 0.5*cos(iTime+uv.xyx+vec3(0,2,4));

    // Output to screen
    fragColor = vec4(col,1.0);
}
''';
      case PassType.bufferA:
      case PassType.bufferB:
      case PassType.bufferC:
      case PassType.bufferD:
        return '''void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
''';
    }
  }

  /// Adds a new pass of [type] if not already present, preserving logical tab order:
  /// Common -> Buffer A -> Buffer B -> Buffer C -> Buffer D -> Image -> Sound.
  ShaderPass? addPass(PassType type, {String? code}) {
    if (hasPass(type)) return getPass(type);

    final newPass = ShaderPass(
      type: type,
      name: type.displayName,
      code: code ?? defaultCodeForPass(type),
    );

    passes.add(newPass);
    _sortPasses();
    return newPass;
  }

  /// Removes the pass of [type]. The Image pass cannot be removed.
  bool removePass(PassType type) {
    if (type == PassType.image) return false;
    final idx = passes.indexWhere((p) => p.type == type);
    if (idx != -1) {
      final removed = passes.removeAt(idx);
      removed.dispose();
      return true;
    }
    return false;
  }

  void _sortPasses() {
    int passOrder(PassType t) {
      switch (t) {
        case PassType.common:
          return 0;
        case PassType.bufferA:
          return 1;
        case PassType.bufferB:
          return 2;
        case PassType.bufferC:
          return 3;
        case PassType.bufferD:
          return 4;
        case PassType.image:
          return 5;
      }
    }

    passes.sort((a, b) => passOrder(a.type).compareTo(passOrder(b.type)));
  }

  /// Deserializes a ShaderToy JSON string or object into a [ShaderToyProject].
  factory ShaderToyProject.fromJson(Map<String, dynamic> rootJson) {
    final shaderMap = rootJson.containsKey('Shader')
        ? rootJson['Shader'] as Map<String, dynamic>
        : rootJson;

    final info = shaderMap['info'] as Map<String, dynamic>? ?? {};
    final id = info['id']?.toString() ?? '';
    final name = info['name']?.toString() ?? 'Untitled Shader';
    final username = info['username']?.toString() ?? 'Anonymous';
    final description = info['description']?.toString() ?? '';
    final url = info['url']?.toString() ?? '';
    final rawTags = info['tags'];
    final tags = rawTags is List
        ? rawTags.map((t) => t.toString()).toList()
        : <String>[];

    final rawPasses = shaderMap['renderpass'] as List<dynamic>? ?? [];
    final passes = <ShaderPass>[];

    for (final rawPass in rawPasses) {
      if (rawPass is! Map<String, dynamic>) continue;
      final passName = rawPass['name']?.toString() ?? 'Image';
      final passTypeStr = rawPass['type']?.toString().toLowerCase() ?? 'image';
      final code = rawPass['code']?.toString() ?? '';

      if (passTypeStr == 'sound') {
        // Sound passes are ignored/unsupported without GPU audio
        continue;
      }

      PassType type;
      switch (passTypeStr) {
        case 'buffer':
          final upper = passName.toUpperCase();
          if (upper.contains('BUFFER B') || upper.endsWith(' B') || upper == 'B') {
            type = PassType.bufferB;
          } else if (upper.contains('BUFFER C') || upper.endsWith(' C') || upper == 'C') {
            type = PassType.bufferC;
          } else if (upper.contains('BUFFER D') || upper.endsWith(' D') || upper == 'D') {
            type = PassType.bufferD;
          } else {
            type = PassType.bufferA;
          }
          break;
        case 'common':
          type = PassType.common;
          break;
        case 'image':
        default:
          type = PassType.image;
          break;
      }

      final pass = ShaderPass(
        type: type,
        name: passName,
        code: code,
      );

      // Parse iChannel inputs
      final rawInputs = rawPass['inputs'] as List<dynamic>? ?? [];
      for (final rawInput in rawInputs) {
        if (rawInput is! Map<String, dynamic>) continue;
        final channelIndex = rawInput['channel'] as int? ?? 0;
        final ctype = rawInput['ctype']?.toString().toLowerCase() ?? 'texture';
        final src = rawInput['src']?.toString() ?? '';
        final sampler = rawInput['sampler'] as Map<String, dynamic>? ?? {};

        final defaultFilterStr = ctype == 'keyboard' ? 'nearest' : 'mipmap';
        final filterStr = sampler['filter']?.toString().toLowerCase() ?? defaultFilterStr;
        final wrapStr = sampler['wrap']?.toString().toLowerCase() ?? 'clamp';
        final vflipStr = sampler['vflip']?.toString().toLowerCase() ?? 'true';

        final filter = filterStr == 'nearest'
            ? ChannelFilter.nearest
            : filterStr == 'linear'
                ? ChannelFilter.linear
                : ChannelFilter.mipmap;

        final wrap = wrapStr == 'repeat'
            ? ChannelWrap.repeat
            : ChannelWrap.clamp;

        final vflip = vflipStr == 'true';

        ShaderChannel? channel;
        switch (ctype) {
          case 'buffer':
            int bufferIdx = 0;
            final rawId = rawInput['id'];
            if (rawId is int) {
              if (rawId >= 257 && rawId <= 260) {
                bufferIdx = rawId - 257;
              } else {
                bufferIdx = rawId % 4;
              }
            }
            final srcLower = (rawInput['src'] ?? rawInput['filepath'] ?? '').toString().toLowerCase();
            if (srcLower.contains('buffer00') || srcLower.contains('buffera')) {
              bufferIdx = 0;
            } else if (srcLower.contains('buffer01') || srcLower.contains('bufferb')) {
              bufferIdx = 1;
            } else if (srcLower.contains('buffer02') || srcLower.contains('bufferc')) {
              bufferIdx = 2;
            } else if (srcLower.contains('buffer03') || srcLower.contains('bufferd')) {
              bufferIdx = 3;
            }
            channel = BufferChannel(
              bufferIndex: bufferIdx,
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
          case 'music':
          case 'audio':
            channel = SoLoudAudioChannel(
              src: src.isNotEmpty ? src : null,
              audioName: src.isNotEmpty ? src.split('/').last : 'Music Track',
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
          case 'mic':
            channel = MicAudioChannel(
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
          case 'cubemap':
            channel = CubeMapChannel(
              name: 'CubeMap',
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
          case 'keyboard':
            channel = KeyboardChannel(
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
          case 'texture':
          default:
            channel = TextureChannel(
              src: src.isNotEmpty ? src : null,
              name: src.isNotEmpty ? src.split('/').last : 'Texture ${rawInput['id'] ?? ''}',
              filter: filter,
              wrap: wrap,
              vflip: vflip,
            );
            break;
        }

        pass.setChannel(channelIndex, channel);
      }

      passes.add(pass);
    }

    return ShaderToyProject(
      id: id,
      name: name,
      author: username,
      description: description,
      url: url,
      tags: tags,
      passes: passes,
    );
  }

  /// Parses a concise settings JSON object into a [ShaderToyProject].
  factory ShaderToyProject.fromSettingsJson(Map<String, dynamic> jsonMap) {
    final name = jsonMap['name']?.toString() ?? 'Custom Shader';
    final imageCode = jsonMap['imageCode']?.toString() ??
        'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }';

    final passes = <ShaderPass>[];
    final imagePass = ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: imageCode,
    );
    passes.add(imagePass);

    // Buffer passes
    final buffers = jsonMap['buffers'] as Map<String, dynamic>?;
    if (buffers != null) {
      buffers.forEach((key, val) {
        final code = val?.toString() ?? '';
        final upperKey = key.toUpperCase();
        PassType type = PassType.bufferA;
        if (upperKey == 'B' || upperKey.contains('BUFFER B')) {
          type = PassType.bufferB;
        } else if (upperKey == 'C' || upperKey.contains('BUFFER C')) {
          type = PassType.bufferC;
        } else if (upperKey == 'D' || upperKey.contains('BUFFER D')) {
          type = PassType.bufferD;
        }
        passes.add(ShaderPass(
          type: type,
          name: 'Buffer $upperKey',
          code: code,
        ));
      });
    }

    // Channels
    final channels = jsonMap['channels'] as Map<String, dynamic>?;
    if (channels != null) {
      channels.forEach((key, val) {
        final chIdx = int.tryParse(key) ?? 0;
        if (val is Map<String, dynamic>) {
          final type = val['type']?.toString().toLowerCase() ?? 'texture';
          final src = val['src']?.toString();
          if (type == 'audio' || type == 'music') {
            imagePass.setChannel(chIdx, SoLoudAudioChannel(src: src));
          } else if (type == 'mic') {
            imagePass.setChannel(chIdx, MicAudioChannel());
          } else if (type == 'texture') {
            imagePass.setChannel(chIdx, TextureChannel(src: src));
          } else if (type == 'buffer') {
            final bufStr = val['buffer']?.toString().toUpperCase() ?? 'A';
            final bufIdx = bufStr == 'B' ? 1 : bufStr == 'C' ? 2 : bufStr == 'D' ? 3 : 0;
            imagePass.setChannel(chIdx, BufferChannel(bufferIndex: bufIdx));
          }
        }
      });
    }

    final url = jsonMap['url']?.toString() ?? '';

    return ShaderToyProject(
      name: name,
      url: url,
      passes: passes,
    );
  }

  /// Parses a raw JSON string into a [ShaderToyProject].
  static ShaderToyProject parseJsonString(String jsonString) {
    final map = json.decode(jsonString) as Map<String, dynamic>;
    if (map.containsKey('imageCode') || (map.containsKey('buffers') && !map.containsKey('Shader'))) {
      return ShaderToyProject.fromSettingsJson(map);
    }
    return ShaderToyProject.fromJson(map);
  }

  /// Serializes the project into a standard ShaderToy JSON structure.
  Map<String, dynamic> toJson() {
    final renderpassList = <Map<String, dynamic>>[];

    for (final pass in passes) {
      final inputs = <Map<String, dynamic>>[];
      for (int i = 0; i < pass.channels.length; i++) {
        final ch = pass.channels[i];
        if (ch == null) continue;

        String ctype = 'texture';
        int id = 257 + i;
        String src = '';

        if (ch is BufferChannel) {
          ctype = 'buffer';
          id = 257 + ch.bufferIndex;
        } else if (ch is SoLoudAudioChannel) {
          ctype = 'music';
          src = ch.src ?? '';
        } else if (ch is MicAudioChannel) {
          ctype = 'mic';
        } else if (ch is TextureChannel) {
          ctype = 'texture';
          src = ch.src ?? '';
        } else if (ch.type == ChannelType.audio) {
          ctype = 'music';
        } else if (ch.type == ChannelType.mic) {
          ctype = 'mic';
        } else if (ch is CubeMapChannel) {
          ctype = 'cubemap';
        } else if (ch is KeyboardChannel || ch.type == ChannelType.keyboard) {
          ctype = 'keyboard';
          id = 33;
        }

        inputs.add({
          'id': id,
          'src': src,
          'ctype': ctype,
          'channel': i,
          'sampler': {
            'filter': ch.filter.name,
            'wrap': ch.wrap.name,
            'vflip': ch.vflip.toString(),
            'srgb': 'false',
            'internal': 'byte',
          },
        });
      }

      String passTypeStr = 'image';
      if (pass.type.isBuffer) {
        passTypeStr = 'buffer';
      } else if (pass.type == PassType.common) {
        passTypeStr = 'common';
      }

      renderpassList.add({
        'inputs': inputs,
        'outputs': [
          {'id': 37, 'channel': 0}
        ],
        'code': pass.code,
        'name': pass.name,
        'description': '',
        'type': passTypeStr,
      });
    }

    return {
      'Shader': {
        'info': {
          'id': id,
          'name': name,
          'username': author,
          'description': description,
          'url': url,
          'tags': tags,
        },
        'renderpass': renderpassList,
      },
    };
  }

  /// Converts the project to a JSON string.
  String toJsonString({bool pretty = true}) {
    final map = toJson();
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return json.encode(map);
  }
}
