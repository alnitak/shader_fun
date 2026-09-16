import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class CrtTerminalDemo {
  final TextEditingController agentNameController = TextEditingController(
    text: 'CIPHER_007',
  );
  final TextEditingController passcodeController = TextEditingController(
    text: 'OMEGA-42',
  );
  final TextEditingController payloadController = TextEditingController(
    text: 'Initiating quantum handshake sequence...',
  );
  String terminalLogs = 'SYSTEM READY. AUTHENTICATED.';

  ShaderProject createProject() {
    final terminalChannel = WidgetChannel(
      name: 'CyberTerminal',
      width: 480,
      height: 360,
      pixelRatio: 2.0,
      autoRender: true,
      horizontalPercentile: (0.12, 0.88),
      verticalPercentile: (0.1, 0.9),
      interactive: true,
      child: buildChild(),
    );

    final pass = ShaderPass(
      name: 'Image',
      type: PassType.image,
      code: getShaderCode(),
      channels: [terminalChannel],
    );

    return ShaderProject(name: 'CRT Terminal', passes: [pass]);
  }

  Widget buildChild() {
    return StatefulBuilder(
      builder: (context, setTermState) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF03140C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22C55E), width: 2.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.terminal,
                    color: Color(0xFF4ADE80),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'MAINFRAME TERMINAL v4.2 [LIVE KEYBOARD INPUT]',
                    style: TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF166534), height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: agentNameController,
                      style: const TextStyle(
                        color: Color(0xFF86EFAC),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'AGENT IDENTIFIER',
                        labelStyle: TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 11,
                        ),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF166534)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4ADE80)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: passcodeController,
                      obscureText: true,
                      style: const TextStyle(
                        color: Color(0xFF86EFAC),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'SECURITY KEY',
                        labelStyle: TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 11,
                        ),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF166534)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4ADE80)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: payloadController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    color: Color(0xFF86EFAC),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'TRANSMISSION PAYLOAD (Type your message here)',
                    labelStyle: TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 11,
                    ),
                    alignLabelWithHint: true,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF166534)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4ADE80)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      terminalLogs,
                      style: const TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text(
                      'TRANSMIT',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () {
                      setTermState(() {
                        terminalLogs =
                            'SENT: [${agentNameController.text}] -> ${payloadController.text}';
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String getShaderCode() {
    return '''
vec2 crtCurve(vec2 uv) {
    uv = (uv - 0.5) * 2.0;
    vec2 offset = uv.yx / 5.0;
    uv = uv + uv * offset * offset;
    return uv * 0.5 + 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 curved = crtCurve(uv);
    if (curved.x < 0.0 || curved.x > 1.0 || curved.y < 0.0 || curved.y > 1.0) {
        fragColor = vec4(0.01, 0.02, 0.01, 1.0);
        return;
    }
    vec2 bMin = vec2(0.12, 0.1);
    vec2 bMax = vec2(0.88, 0.9);
    vec2 bSize = bMax - bMin;
    vec4 col = vec4(0.02, 0.03, 0.02, 1.0);
    
    if (curved.x >= bMin.x && curved.x <= bMax.x &&
        curved.y >= bMin.y && curved.y <= bMax.y) {
        vec2 wUv = (curved - bMin) / bSize;
        vec2 shift = vec2(0.002, 0.0);
        float r = texture(iChannel0, clamp(wUv + shift, 0.0, 1.0)).r;
        float g = texture(iChannel0, wUv).g;
        float b = texture(iChannel0, clamp(wUv - shift, 0.0, 1.0)).b;
        vec4 wCol = vec4(r, g, b, 1.0);
        col = mix(col, wCol, texture(iChannel0, wUv).a);
    }
    float scanline = sin(curved.y * iResolution.y * 1.5) * 0.15;
    col.rgb -= scanline;
    float mask = sin(fragCoord.x * 3.14159) * 0.08;
    col.rgb -= mask;
    col.rgb += sin(iTime * 20.0 + curved.y * 100.0) * 0.015;
    float vig = 16.0 * curved.x * curved.y * (1.0 - curved.x) * (1.0 - curved.y);
    vig = clamp(pow(vig, 0.35), 0.0, 1.0);
    col.rgb *= vig;
    col.rgb = mix(col.rgb, col.rgb * vec3(0.8, 1.2, 0.9), 0.4);
    fragColor = vec4(col.rgb, 1.0);
}
''';
  }

  void dispose() {
    agentNameController.dispose();
    passcodeController.dispose();
    payloadController.dispose();
  }
}
