import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class LiquidListDemo {
  final Map<int, bool> switchStates = {0: true, 1: false, 2: true};
  final Map<int, int> itemCounters = {0: 12, 1: 45, 2: 8};

  void dispose() {}

  ShaderProject createProject() {
    final listChannel = WidgetChannel(
      name: 'InteractiveList',
      width: 500,
      height: 380,
      pixelRatio: 2.0,
      autoRender: true,
      horizontalPercentile: (0.1, 0.9),
      verticalPercentile: (0.05, 0.95),
      interactive: true,
      child: buildChild(),
    );

    final pass = ShaderPass(
      name: 'Image',
      type: PassType.image,
      code: getShaderCode(),
      channels: [listChannel],
    );

    return ShaderProject(name: 'Liquid ListView', passes: [pass]);
  }

  Widget buildChild() {
    return StatefulBuilder(
      builder: (context, setListState) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141824).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.water_drop,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Interactive ListView',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Scroll & Tap!',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: 50,
                  itemBuilder: (context, i) {
                    final isChecked = switchStates[i] ?? false;
                    final count = itemCounters[i] ?? (i * 3 + 7);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors
                            .primaries[i % Colors.primaries.length]
                            .withValues(alpha: 0.2),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        'Data Stream #${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Status: ${isChecked ? "ACTIVE" : "STANDBY"} | Count: $count',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: 18,
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () {
                              setListState(() {
                                itemCounters[i] = count - 1;
                              });
                            },
                          ),
                          Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.greenAccent,
                            ),
                            onPressed: () {
                              setListState(() {
                                itemCounters[i] = count + 1;
                              });
                            },
                          ),
                          Switch(
                            value: isChecked,
                            activeThumbColor: Colors.cyanAccent,
                            onChanged: (val) {
                              setListState(() {
                                switchStates[i] = val;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String getShaderCode() {
    return '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 bMin = vec2(0.1, 0.05);
    vec2 bMax = vec2(0.9, 0.95);
    vec2 bSize = bMax - bMin;
    vec4 bg = vec4(0.04, 0.06, 0.1, 1.0);
    
    if (uv.x < bMin.x || uv.x > bMax.x || uv.y < bMin.y || uv.y > bMax.y) {
        fragColor = bg;
        return;
    }
    vec2 wUv = (uv - bMin) / bSize;
    vec2 p = wUv * 12.0;
    vec2 ripple = vec2(
        sin(p.y * 2.5 + iTime * 2.0) + cos(p.x * 3.0 + iTime * 1.5),
        cos(p.x * 2.5 + iTime * 2.0) + sin(p.y * 3.0 + iTime * 1.5)
    ) * 0.005;
    
    if (iMouse.z > 0.0) {
        vec2 mUv = (iMouse.xy / iResolution.xy - bMin) / bSize;
        vec2 toMouse = wUv - mUv;
        float d = length(toMouse);
        ripple += normalize(toMouse + 0.0001) * sin(d * 40.0 - iTime * 10.0) * 0.015 * exp(-d * 5.0);
    }
    vec2 rUv = clamp(wUv + ripple, 0.0, 1.0);
    vec2 gUv = clamp(wUv + ripple * 0.8, 0.0, 1.0);
    vec2 bUv = clamp(wUv + ripple * 0.6, 0.0, 1.0);
    
    float r = texture(iChannel0, rUv).r;
    float g = texture(iChannel0, gUv).g;
    float b = texture(iChannel0, bUv).b;
    float a = texture(iChannel0, wUv).a;
    float spec = pow(max(0.0, ripple.x * 40.0 + ripple.y * 40.0), 2.0) * 0.3;
    vec3 col = vec3(r, g, b) + vec3(spec);
    fragColor = mix(bg, vec4(col, 1.0), a);
}
''';
  }
}
