import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Example demonstrating a custom vertex & fragment shader pass that deforms
/// and renders a live, interactive Flutter widget using [WidgetChannel].
class CustomMeshWidgetExample extends StatefulWidget {
  /// Creates a [CustomMeshWidgetExample].
  const CustomMeshWidgetExample({super.key});

  @override
  State<CustomMeshWidgetExample> createState() =>
      _CustomMeshWidgetExampleState();
}

class _CustomMeshWidgetExampleState extends State<CustomMeshWidgetExample> {
  late final ShaderController _controller;
  double _sliderValue = 0.5;

  // Inlined custom vertex shader: applies an animated sinusoidal wave deformation
  static const String _wavyVertexGlsl = '''
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
    // Map quad coordinates (-1..1) to UV texture coordinates (0..1)
    v_uv = position * 0.5 + 0.5;

    // Apply gentle undulating flag / wave deformation in vertex stage
    vec2 pos = position;
    float wave = sin(pos.x * 3.5 + iTime * 2.5) * 0.1;
    pos.y += wave;

    gl_Position = vec4(pos, 0.0, 1.0);
}
''';

  // Inlined custom fragment shader: renders the live Flutter widget texture
  // with lighting highlights based on vertex curvature
  static const String _wavyFragmentGlsl = '''
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
    // Flip Y for texture sampling from Flutter raster cache
    vec2 texCoord = vec2(v_uv.x, 1.0 - v_uv.y);
    vec4 widgetColor = texture(iChannel0, texCoord);

    // Add subtle ambient shading reacting to the wave
    float lighting = 0.9 + 0.2 * cos(v_uv.x * 7.0 + iTime * 2.5);
    vec3 shadedRgb = widgetColor.rgb * lighting;

    fragColor = vec4(shadedRgb, widgetColor.a);
}
''';

  @override
  void initState() {
    super.initState();

    final ShaderPass wavyWidgetPass = ShaderPass(
      name: 'Wavy Widget Pass',
      type: PassType.image,
      mode: ShaderPassMode.custom,
      vertexCode: _wavyVertexGlsl,
      code: _wavyFragmentGlsl,
      channels: <ShaderChannel?>[
        WidgetChannel(child: _buildInteractiveWidget()),
      ],
    );

    _controller = ShaderController(
      autoPlay: true,
      initialProject: ShaderProject(passes: <ShaderPass>[wavyWidgetPass]),
    );
  }

  Widget _buildInteractiveWidget() {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setInnerState) {
            return Container(
              width: 320,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF6A11CB), Color(0xFF2575FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.auto_awesome,
                    color: Colors.amberAccent,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Live Flutter Widget in Custom Shader',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Value: ${(_sliderValue * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _sliderValue,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    thumbColor: Colors.white,
                    onChanged: (double value) {
                      setInnerState(() {
                        _sliderValue = value;
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),
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
      backgroundColor: const Color(0xFF101018),
      body: ShaderViewport(controller: _controller),
    );
  }
}
