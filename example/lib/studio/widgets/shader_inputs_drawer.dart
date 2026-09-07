import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Shader inputs reference drawer displaying current uniform values.
class ShaderInputsDrawer extends StatelessWidget {
  const ShaderInputsDrawer({
    super.key,
    required this.uniforms,
  });

  final ShaderToyUniforms uniforms;

  @override
  Widget build(BuildContext context) {
    final vars = [
      {
        'name': 'vec3 iResolution',
        'val':
            '${uniforms.resolution.width.toInt()}x${uniforms.resolution.height.toInt()}',
      },
      {'name': 'float iTime', 'val': '${uniforms.time.toStringAsFixed(2)}s'},
      {
        'name': 'float iTimeDelta',
        'val': '${uniforms.timeDelta.toStringAsFixed(4)}s',
      },
      {
        'name': 'float iFrameRate',
        'val': '${uniforms.frameRate.toStringAsFixed(1)} fps',
      },
      {'name': 'int iFrame', 'val': '${uniforms.frame}'},
      {
        'name': 'vec4 iMouse',
        'val': '(${uniforms.mouse.x.toInt()}, ${uniforms.mouse.y.toInt()})',
      },
      {'name': 'sampler2D iChannel0..3', 'val': 'Textures / Audio'},
    ];

    return Container(
      color: const Color(0xFF101015),
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: vars.map((v) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E26),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2C2C38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v['name']!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  v['val']!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
