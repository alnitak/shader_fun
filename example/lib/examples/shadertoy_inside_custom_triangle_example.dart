import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Example demonstrating how to project and texture-map a ShaderToy procedural
/// animation from Buffer A directly inside a rotating custom triangle mesh.
class ShaderToyInsideCustomTriangleExample extends StatefulWidget {
  /// Creates a [ShaderToyInsideCustomTriangleExample].
  const ShaderToyInsideCustomTriangleExample({super.key});

  @override
  State<ShaderToyInsideCustomTriangleExample> createState() =>
      _ShaderToyInsideCustomTriangleExampleState();
}

class _ShaderToyInsideCustomTriangleExampleState
    extends State<ShaderToyInsideCustomTriangleExample> {
  late final ShaderController _controller;

  // Inlined ShaderToy procedural kaleidoscope / mandala animation in Buffer A
  static const String _kaleidoscopeFragGlsl = '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.4;

    // Polar kaleidoscope coordinates
    float r = length(p);
    float a = atan(p.y, p.x);
    float segments = 8.0;
    a = mod(a, 6.28318 / segments) - 3.14159 / segments;
    p = vec2(cos(a), sin(a)) * r;

    // Hypnotic geometric patterns
    float rings = sin(r * 20.0 - t * 4.0);
    float spokes = cos(p.x * 15.0 + t * 2.0);
    float val = smoothstep(0.1, 0.8, abs(rings * spokes));

    vec3 col = 0.5 + 0.5 * cos(vec3(0.0, 1.0, 2.0) + r * 6.0 + t);
    fragColor = vec4(col * val, 1.0);
}
''';

  // Inlined custom vertex shader: rotates the custom triangle around the center
  static const String _rotatingTriangleVertGlsl = '''
#version 460 core

layout(location = 0) in vec2 position;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
    float iTimeDelta;
    float iFrameRate;
    int iFrame;
    vec4 iMouse;
    vec4 iDate;
    float iSampleRate;
    vec3 iChannelResolution[4];
    vec4 iCustom[16];
};

out vec2 v_uv;

void main() {
    // Map triangle coordinates to UV range [0, 1]
    v_uv = position * 0.5 + 0.5;

    // Smooth continuous rotation in 2D
    float angle = iTime * 0.75;
    float c = cos(angle);
    float s = sin(angle);
    mat2 rot = mat2(c, -s, s, c);

    vec2 rotatedPos = rot * position;
    gl_Position = vec4(rotatedPos, 0.0, 1.0);
}
''';

  // Inlined custom fragment shader: samples the ShaderToy animation from Buffer A
  // and projects it directly inside the rotating triangle with edge glow
  static const String _texturedTriangleFragGlsl = '''
#version 460 core
precision highp float;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
    float iTimeDelta;
    float iFrameRate;
    int iFrame;
    vec4 iMouse;
    vec4 iDate;
    float iSampleRate;
    vec3 iChannelResolution[4];
    vec4 iCustom[16];
};

layout(set = 0, binding = 1) uniform sampler2D iChannel0;

in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main() {
    // Sample the procedural ShaderToy texture from Buffer A using the triangle's UV
    vec4 texCol = texture(iChannel0, v_uv);

    // Add bright edge highlight
    float distToCenter = length(v_uv - vec2(0.5));
    vec3 finalCol = texCol.rgb + vec3(0.15, 0.2, 0.3) * distToCenter;

    fragColor = vec4(finalCol, 1.0);
}
''';

  @override
  void initState() {
    super.initState();

    // 1. Buffer A: ShaderToy animated procedural kaleidoscope
    final ShaderPass kaleidoscopePass = ShaderPass(
      name: 'Kaleidoscope (Buffer A)',
      type: PassType.bufferA,
      mode: ShaderPassMode.shaderToy,
      code: _kaleidoscopeFragGlsl,
    );

    // 2. Image: Custom pass mapping Buffer A onto rotating triangle mesh
    final ShaderPass trianglePass = ShaderPass(
      name: 'Custom Triangle (Image)',
      type: PassType.image,
      mode: ShaderPassMode.custom,
      vertexCode: _rotatingTriangleVertGlsl,
      code: _texturedTriangleFragGlsl,
      vertexCount: 3,
      customVertices: Float32List.fromList(<double>[
        0.0, 0.8, // Top apex
        -0.7, -0.6, // Bottom-left
        0.7, -0.6, // Bottom-right
      ]),
      channels: <ShaderChannel?>[
        BufferChannel(bufferIndex: 0), // iChannel0: Buffer A
      ],
    );

    _controller = ShaderController(
      autoPlay: true,
      initialProject: ShaderProject(
        passes: <ShaderPass>[kaleidoscopePass, trianglePass],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      body: ShaderViewport(controller: _controller),
    );
  }
}
