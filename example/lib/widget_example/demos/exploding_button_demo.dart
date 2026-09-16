import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class ExplodingButtonDemo {
  ExplodingButtonDemo({required this.onStateChanged});

  final VoidCallback onStateChanged;

  int detonateCount = 0;
  bool isExploding = false;
  Timer? _resetTimer;
  ShaderController? _controller;

  void attachController(ShaderController controller) {
    _controller = controller;
    _controller?.setUniform('detonateTime', 0.0);
  }

  void triggerExplosion() {
    if (_controller == null || isExploding) return;

    final triggerTime = _controller!.time;
    detonateCount++;
    isExploding = true;
    onStateChanged();

    // Pass trigger timestamp instantly via custom uniform detonateTime
    _controller!.setUniform('detonateTime', triggerTime);

    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 3200), () {
      isExploding = false;
      _controller?.setUniform('detonateTime', 0.0);
      onStateChanged();
    });
  }

  ShaderProject createProject() {
    final buttonChannel = WidgetChannel(
      name: 'Button',
      width: 320,
      height: 70,
      pixelRatio: 2.0,
      autoRender: true,
      horizontalPercentile: (0.3, 0.7),
      verticalPercentile: (0.45, 0.55),
      interactive: true,
      child: buildChild(),
    );

    final pass = ShaderPass(
      name: 'Image',
      type: PassType.image,
      code: getShaderCode(),
      channels: [buttonChannel],
    );

    return ShaderProject(name: 'Exploding Button', passes: [pass]);
  }

  Widget buildChild() {
    return StatefulBuilder(
      builder: (context, setBtnState) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            triggerExplosion();
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isExploding
                        ? '💥 DETONATING! 💥'
                        : 'EXPLODE ME! (Detonated: $detonateCount)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildBannerAction() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: isExploding ? null : triggerExplosion,
      icon: const Icon(Icons.local_fire_department, size: 18),
      label: Text(isExploding ? 'DETONATING...' : 'DETONATE NOW 💥'),
    );
  }

  String getShaderCode() {
    return '''
uniform float detonateTime;

float hash21(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 center = vec2(0.5, 0.5);
    
    // Exact requested percentiles: [0.3, 0.7] x [0.45, 0.55]
    vec2 bMin = vec2(0.3, 0.45);
    vec2 bMax = vec2(0.7, 0.55);
    vec2 bSize = bMax - bMin;
    
    // Custom uniform detonateTime carries the detonation timestamp dynamically!
    float explodeAge = iTime - detonateTime;
    bool isExploding = detonateTime > 0.0 && explodeAge >= 0.0 && explodeAge < 3.0;
    
    vec4 col = vec4(0.04, 0.05, 0.08, 1.0);
    
    // Background sci-fi grid
    vec2 grid = abs(fract(uv * 20.0 - 0.5) - 0.5) / fwidth(uv * 20.0);
    float line = min(grid.x, grid.y);
    col.rgb += (1.0 - min(line, 1.0)) * vec3(0.08, 0.12, 0.2);
    
    if (isExploding) {
        // 1. Shockwave blast ring
        float aspect = iResolution.x / iResolution.y;
        float shockDist = length((uv - center) * vec2(aspect, 1.0));
        float shockRadius = explodeAge * 0.9;
        float ring = exp(-pow((shockDist - shockRadius) * 28.0, 2.0));
        col.rgb += ring * vec3(1.2, 0.6, 0.1) * (1.0 - explodeAge / 3.0) * 2.5;
        
        // 2. Shatter fragments inside the button
        vec2 sampleUv = uv;
        if (uv.x >= bMin.x - 0.15 && uv.x <= bMax.x + 0.15 &&
            uv.y >= bMin.y - 0.15 && uv.y <= bMax.y + 0.15) {
            
            vec2 cell = floor(uv * 32.0);
            float h = hash21(cell);
            vec2 dir = normalize(uv - center + (h - 0.5) * 0.25);
            float speed = (0.6 + h * 0.9) * explodeAge;
            sampleUv -= dir * speed * 0.35;
            
            vec2 btnUv = (sampleUv - bMin) / bSize;
            if (btnUv.x >= 0.0 && btnUv.x <= 1.0 && btnUv.y >= 0.0 && btnUv.y <= 1.0) {
                vec4 btnCol = texture(iChannel0, btnUv);
                btnCol.rgb += vec3(1.6, 0.7, 0.2) * (1.0 - explodeAge / 3.0) * h;
                btnCol.a *= clamp(1.0 - explodeAge / 2.2, 0.0, 1.0);
                col = mix(col, btnCol, btnCol.a);
            }
        }
        
        // 3. Fiery explosion sparks
        for (int i = 0; i < 16; i++) {
            float fi = float(i);
            float angle = fi * 0.392 + hash21(vec2(fi, 1.0));
            vec2 sparkDir = vec2(cos(angle), sin(angle));
            vec2 sparkPos = center + sparkDir * explodeAge * (0.35 + hash21(vec2(fi, 2.0)) * 0.6);
            float spark = 0.003 / (length((uv - sparkPos) * vec2(aspect, 1.0)) + 0.001);
            col.rgb += spark * vec3(1.0, 0.75, 0.25) * (1.0 - explodeAge / 3.0);
        }
    } else {
        // Idle button rendering
        if (uv.x >= bMin.x && uv.x <= bMax.x && uv.y >= bMin.y && uv.y <= bMax.y) {
            vec2 btnUv = (uv - bMin) / bSize;
            vec4 btnCol = texture(iChannel0, btnUv);
            col = mix(col, btnCol, btnCol.a);
        }
        
        // Ambient neon pulse ring
        vec2 d = abs(uv - center) - (bSize * 0.5);
        float edgeDist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
        if (abs(edgeDist) < 0.012) {
            float pulse = sin(iTime * 4.0) * 0.5 + 0.5;
            col.rgb += vec3(1.0, 0.25, 0.4) * (1.0 - abs(edgeDist) / 0.012) * pulse * 1.5;
        }
    }
    
    fragColor = col;
}
''';
  }

  void dispose() {
    _resetTimer?.cancel();
  }
}
