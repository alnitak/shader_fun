import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Example demonstrating a 3D rotating cube rendered using only a custom shader pass
/// with custom vertex and fragment shaders (no ShaderToy wrapper).
class CustomRotatingCubeExample extends StatefulWidget {
  /// Creates a [CustomRotatingCubeExample].
  const CustomRotatingCubeExample({super.key});

  @override
  State<CustomRotatingCubeExample> createState() =>
      _CustomRotatingCubeExampleState();
}

class _CustomRotatingCubeExampleState extends State<CustomRotatingCubeExample> {
  late final ShaderController _controller;

  // Vertex shader:
  // - Takes 3D vertex positions and normals
  // - Computes 3D rotation driven by iTime
  // - Transforms positions and outward face normals
  // - Applies perspective projection with camera at +Z
  static const String _customCubeVertGlsl = '''
#version 460 core

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
};

out vec3 v_normal;
out vec3 v_modelPos;
out vec3 v_modelNormal;
out vec3 v_worldPos;

void main() {
    v_modelPos = position;
    v_modelNormal = normal;

    // Time-based 3D rotations
    float t = iTime * 0.9;
    float cosY = cos(t);
    float sinY = sin(t);
    mat3 rotY = mat3(
        cosY, 0.0, sinY,
        0.0,  1.0, 0.0,
        -sinY, 0.0, cosY
    );

    float tx = t * 0.65;
    float cosX = cos(tx);
    float sinX = sin(tx);
    mat3 rotX = mat3(
        1.0, 0.0,  0.0,
        0.0, cosX, -sinX,
        0.0, sinX, cosX
    );

    float tz = t * 0.35;
    float cosZ = cos(tz);
    float sinZ = sin(tz);
    mat3 rotZ = mat3(
        cosZ, -sinZ, 0.0,
        sinZ,  cosZ, 0.0,
        0.0,   0.0,  1.0
    );

    mat3 rot = rotZ * rotX * rotY;
    vec3 rotatedPos = rot * (position * 0.7);
    v_worldPos = rotatedPos;
    v_normal = normalize(rot * normal);

    // Perspective camera projection with camera placed at (0, 0, 2.9)
    float aspect = iResolution.y > 0.0 ? (iResolution.x / iResolution.y) : 1.0;
    float cameraDistance = 2.9;
    float z = cameraDistance - rotatedPos.z;

    float fov = 2.0;
    vec2 projected = (rotatedPos.xy / max(z, 0.1)) * fov;
    projected.x /= aspect;

    gl_Position = vec4(projected, 0.5, 1.0);
}
''';

  // Fragment shader:
  // - Discards backfaces so only front-facing faces are drawn without depth buffer
  // - Directional lighting with ambient and specular highlights
  // - Distinct vibrant colors per face
  // - Clean border edge outline per face
  static const String _customCubeFragGlsl = '''
#version 460 core
precision highp float;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
};

in vec3 v_normal;
in vec3 v_modelPos;
in vec3 v_modelNormal;
in vec3 v_worldPos;

layout(location = 0) out vec4 fragColor;

void main() {
    // Vector from surface to camera (located at z = 2.4)
    vec3 viewDir = normalize(vec3(0.0, 0.0, 2.4) - v_worldPos);

    // Backface culling: discard faces pointing away from the camera.
    // For a convex shape like a cube, discarding backfaces prevents self-occlusion
    // artifacts even without a hardware depth buffer.
    if (dot(v_normal, viewDir) <= 0.0) {
        discard;
    }

    // Determine face color based on the model-space outward normal
    vec3 baseColor;
    if (abs(v_modelNormal.x) > 0.5) {
        baseColor = v_modelNormal.x > 0.0 ? vec3(0.95, 0.25, 0.35) : vec3(0.25, 0.85, 0.95); // Red (+X) / Cyan (-X)
    } else if (abs(v_modelNormal.y) > 0.5) {
        baseColor = v_modelNormal.y > 0.0 ? vec3(0.35, 0.95, 0.45) : vec3(0.95, 0.65, 0.15); // Green (+Y) / Orange (-Y)
    } else {
        baseColor = v_modelNormal.z > 0.0 ? vec3(0.35, 0.55, 0.95) : vec3(0.85, 0.35, 0.95); // Blue (+Z) / Purple (-Z)
    }

    // Directional light from top-right-front
    vec3 lightDir = normalize(vec3(0.5, 0.8, 0.9));
    vec3 normal = normalize(v_normal);

    // Diffuse lighting
    float diff = max(dot(normal, lightDir), 0.0);
    float lighting = 0.3 + 0.7 * diff;

    // Specular highlight
    vec3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.4;

    // Face border edge highlight using model position
    vec3 absPos = abs(v_modelPos);
    float isEdge = 0.0;
    if (abs(v_modelNormal.x) > 0.5) {
        if (absPos.y > 0.90 || absPos.z > 0.90) isEdge = 1.0;
    } else if (abs(v_modelNormal.y) > 0.5) {
        if (absPos.x > 0.90 || absPos.z > 0.90) isEdge = 1.0;
    } else {
        if (absPos.x > 0.90 || absPos.y > 0.90) isEdge = 1.0;
    }

    // Dynamic ambient pulse
    vec3 ambient = 0.04 * cos(iTime * 1.5 + v_modelPos);
    vec3 finalColor = baseColor * lighting + vec3(spec) + ambient;
    // Darken edge borders for a clean polyhedral look
    finalColor = mix(finalColor, vec3(0.08), isEdge * 0.75);

    fragColor = vec4(finalColor, 1.0);
}
''';

  /// Generates the 36 vertices (6 faces x 2 triangles x 3 vertices) of a cube
  /// centered at (0, 0, 0) with interleaved positions and outward face normals.
  static Float32List _buildCubeVertices() {
    const List<double> vertices = <double>[
      // Front face (+Z) - normal: (0, 0, 1)
      -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
      1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
      1.0, 1.0, 1.0, 0.0, 0.0, 1.0,
      -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
      1.0, 1.0, 1.0, 0.0, 0.0, 1.0,
      -1.0, 1.0, 1.0, 0.0, 0.0, 1.0,

      // Back face (-Z) - normal: (0, 0, -1)
      1.0, -1.0, -1.0, 0.0, 0.0, -1.0,
      -1.0, -1.0, -1.0, 0.0, 0.0, -1.0,
      -1.0, 1.0, -1.0, 0.0, 0.0, -1.0,
      1.0, -1.0, -1.0, 0.0, 0.0, -1.0,
      -1.0, 1.0, -1.0, 0.0, 0.0, -1.0,
      1.0, 1.0, -1.0, 0.0, 0.0, -1.0,

      // Top face (+Y) - normal: (0, 1, 0)
      -1.0, 1.0, 1.0, 0.0, 1.0, 0.0,
      1.0, 1.0, 1.0, 0.0, 1.0, 0.0,
      1.0, 1.0, -1.0, 0.0, 1.0, 0.0,
      -1.0, 1.0, 1.0, 0.0, 1.0, 0.0,
      1.0, 1.0, -1.0, 0.0, 1.0, 0.0,
      -1.0, 1.0, -1.0, 0.0, 1.0, 0.0,

      // Bottom face (-Y) - normal: (0, -1, 0)
      -1.0, -1.0, -1.0, 0.0, -1.0, 0.0,
      1.0, -1.0, -1.0, 0.0, -1.0, 0.0,
      1.0, -1.0, 1.0, 0.0, -1.0, 0.0,
      -1.0, -1.0, -1.0, 0.0, -1.0, 0.0,
      1.0, -1.0, 1.0, 0.0, -1.0, 0.0,
      -1.0, -1.0, 1.0, 0.0, -1.0, 0.0,

      // Right face (+X) - normal: (1, 0, 0)
      1.0, -1.0, 1.0, 1.0, 0.0, 0.0,
      1.0, -1.0, -1.0, 1.0, 0.0, 0.0,
      1.0, 1.0, -1.0, 1.0, 0.0, 0.0,
      1.0, -1.0, 1.0, 1.0, 0.0, 0.0,
      1.0, 1.0, -1.0, 1.0, 0.0, 0.0,
      1.0, 1.0, 1.0, 1.0, 0.0, 0.0,

      // Left face (-X) - normal: (-1, 0, 0)
      -1.0, -1.0, -1.0, -1.0, 0.0, 0.0,
      -1.0, -1.0, 1.0, -1.0, 0.0, 0.0,
      -1.0, 1.0, 1.0, -1.0, 0.0, 0.0,
      -1.0, -1.0, -1.0, -1.0, 0.0, 0.0,
      -1.0, 1.0, 1.0, -1.0, 0.0, 0.0,
      -1.0, 1.0, -1.0, -1.0, 0.0, 0.0,
    ];

    return Float32List.fromList(vertices);
  }

  @override
  void initState() {
    super.initState();

    final ShaderPass cubePass = ShaderPass(
      name: 'Rotating Cube',
      type: PassType.image,
      mode: ShaderPassMode.custom,
      vertexCode: _customCubeVertGlsl,
      code: _customCubeFragGlsl,
      vertexCount: 36,
      customVertices: _buildCubeVertices(),
    );

    _controller = ShaderController(
      autoPlay: true,
      initialProject: ShaderProject(passes: <ShaderPass>[cubePass]),
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
      body: Stack(children: <Widget>[ShaderViewport(controller: _controller)]),
    );
  }
}
