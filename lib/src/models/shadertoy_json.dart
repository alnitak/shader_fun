import 'dart:convert';

import '../channels/audio_texture_provider.dart';
import '../channels/shader_channel.dart';
import '../core/shader_pass.dart';

/// Represents a complete ShaderToy project containing metadata and passes.
class ShaderToyProject {
  ShaderToyProject({
    this.id = '',
    this.name = 'New Shader',
    this.author = 'Anonymous',
    this.description = '',
    this.tags = const [],
    List<ShaderPass>? passes,
  }) : passes = passes ?? [];

  /// Creates a default starter ShaderToy project with a single Image pass.
  factory ShaderToyProject.empty() {
    return ShaderToyProject(
      id: 'new',
      name: 'New Shader',
      passes: [
        ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: '''void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0, 2, 4));
    fragColor = vec4(col, 1.0);
}
''',
        ),
      ],
    );
  }

  String id;
  String name;
  String author;
  String description;
  List<String> tags;
  List<ShaderPass> passes;

  ShaderPass? getPass(PassType type) {
    for (final pass in passes) {
      if (pass.type == type) return pass;
    }
    return null;
  }

  ShaderPass? get imagePass => getPass(PassType.image);
  ShaderPass? get commonPass => getPass(PassType.common);

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
        case 'sound':
          type = PassType.sound;
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

        final filterStr = sampler['filter']?.toString().toLowerCase() ?? 'linear';
        final wrapStr = sampler['wrap']?.toString().toLowerCase() ?? 'clamp';
        final vflipStr = sampler['vflip']?.toString().toLowerCase() ?? 'true';

        final filter = filterStr == 'nearest'
            ? ChannelFilter.nearest
            : filterStr == 'mipmap'
                ? ChannelFilter.mipmap
                : ChannelFilter.linear;

        final wrap = wrapStr == 'repeat'
            ? ChannelWrap.repeat
            : ChannelWrap.clamp;

        final vflip = vflipStr == 'true';

        ShaderChannel? channel;
        switch (ctype) {
          case 'buffer':
            final bufferIdx = (rawInput['id'] is int)
                ? (rawInput['id'] as int) % 4
                : 0;
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

    return ShaderToyProject(
      name: name,
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
          'published': 1,
        });
      }

      String passTypeStr = 'image';
      if (pass.type.isBuffer) {
        passTypeStr = 'buffer';
      } else if (pass.type == PassType.common) {
        passTypeStr = 'common';
      } else if (pass.type == PassType.sound) {
        passTypeStr = 'sound';
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
        'ver': '0.1',
        'info': {
          'id': id,
          'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'viewed': 0,
          'name': name,
          'username': author,
          'description': description,
          'likes': 0,
          'published': 3,
          'flags': 0,
          'usePreview': 0,
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
