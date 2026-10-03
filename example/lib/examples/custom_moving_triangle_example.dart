import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Example demonstrating a custom vertex & fragment shader pass layered over
/// a ShaderToy procedural background.
class CustomMovingTriangleExample extends StatefulWidget {
  /// Creates a [CustomMovingTriangleExample].
  const CustomMovingTriangleExample({super.key});

  @override
  State<CustomMovingTriangleExample> createState() =>
      _CustomMovingTriangleExampleState();
}

class _CustomMovingTriangleExampleState
    extends State<CustomMovingTriangleExample> {
  late final ShaderController _controller;

  // Inlined custom vertex shader: moves the triangle vertices in 2D space
  static const String _customTriangleVertGlsl = '''
#version 460 core

layout(location = 0) in vec2 position;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;        
    // float iTimeDelta;
    // float iFrameRate;
    // int iFrame;
    // vec4 iMouse;
    // vec4 iDate;
    // float iSampleRate;
    // vec3 iChannelResolution[4];
    // vec4 iCustom[16];
};

out vec2 v_uv;

void main() {
    v_uv = position * 0.5 + 0.5;

    vec2 offset = vec2(
        sin(iTime * 1.5) * 0.45,
        cos(iTime * 2.0) * 0.35
    );

    // Scale triangle down and translate
    vec2 pos = position * 0.4 + offset;
    gl_Position = vec4(pos, 0.0, 1.0);
}
''';

  // Inlined custom fragment shader: renders the triangle with glowing colors
  // and a black circle with radius 0.2 and stroke 0.01
  static const String _customTriangleFragGlsl = '''
#version 460 core
precision highp float;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
    // float iTimeDelta;
    // float iFrameRate;
    // int iFrame;
    // vec4 iMouse;
    // vec4 iDate;
    // float iSampleRate;
    // vec3 iChannelResolution[4];
    // vec4 iCustom[16];
};


in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main() {
    // Radiant gradient color inside triangle
    vec3 triangleCol = 0.5 + 0.5 * cos(iTime * 2.0 + v_uv.xyx + vec3(0.0, 2.0, 4.0));
    triangleCol += vec3(0.3); // Bright boost

    // Black circle with radius 0.1 and stroke of 0.01 (half-thickness 0.005)
    float d = abs(length(v_uv - vec2(0.5)) - 0.1);
    float circle = 1.0 - smoothstep(0.005, 0.005 + fwidth(d), d);
    vec3 finalCol = mix(triangleCol, vec3(0.0), circle);

    fragColor = vec4(finalCol, 1.0);
}
''';

  @override
  void initState() {
    super.initState();

    // Image: Custom pass with custom vertex & fragment shaders
    final ShaderPass trianglePass = ShaderPass(
      name: 'Moving Triangle',
      type: PassType.image,
      mode: ShaderPassMode.custom,
      vertexCode: _customTriangleVertGlsl,
      code: _customTriangleFragGlsl,
      vertexCount: 3,
      customVertices: Float32List.fromList(<double>[
        0.0, 0.8, // Top vertex
        -0.6, -0.4, // Bottom-left
        0.6, -0.4, // Bottom-right
      ]),
      channels: <ShaderChannel?>[
        BufferChannel(bufferIndex: 0), // iChannel0: Buffer A
      ],
    );

    _controller = ShaderController(
      autoPlay: true,
      initialProject: ShaderProject(passes: <ShaderPass>[trianglePass]),
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
      backgroundColor: Colors.black,
      body: ShaderViewport(controller: _controller),
    );
  }
}
