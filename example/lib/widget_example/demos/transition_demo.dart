import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class TransitionDemo {
  TransitionDemo({required this.vsync, required this.onStateChanged}) {
    pageTransitionAnimation = CurvedAnimation(
      parent: pageTransitionController,
      curve: Curves.easeInOutCubic,
    )..addListener(_onTransitionTick);
  }

  final TickerProvider vsync;
  final VoidCallback onStateChanged;

  int transitionPageIndex = 0; // 0: Page 1 (A), 1: Page 2 (B)
  double sliderPercentage = 0.65;

  WidgetChannel? dashboardChannel;
  WidgetChannel? playerChannel;
  ShaderToyController? _controller;

  late final AnimationController pageTransitionController = AnimationController(
    vsync: vsync,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> pageTransitionAnimation;

  void attachController(ShaderToyController controller) {
    _controller = controller;
    _controller?.setUniform('progress', 0.0);
  }

  void _onTransitionTick() {
    _controller?.setUniform('progress', pageTransitionAnimation.value);
    dashboardChannel?.interactive = pageTransitionAnimation.value < 0.5;
    playerChannel?.interactive = pageTransitionAnimation.value >= 0.5;
  }

  void nextTransitionPage() {
    if (transitionPageIndex >= 1) return;
    transitionPageIndex = 1;
    onStateChanged();
    pageTransitionController.forward();
  }

  void previousTransitionPage() {
    if (transitionPageIndex <= 0) return;
    transitionPageIndex = 0;
    onStateChanged();
    pageTransitionController.reverse();
  }

  ShaderToyProject createProject() {
    transitionPageIndex = 0;
    pageTransitionController.value = 0.0;

    dashboardChannel = WidgetChannel(
      name: 'DashboardA',
      width: 500,
      height: 380,
      pixelRatio: 2.0,
      autoRender: false,
      interactive: true,
      child: buildPageA(),
    );

    playerChannel = WidgetChannel(
      name: 'PlayerB',
      width: 500,
      height: 380,
      pixelRatio: 2.0,
      autoRender: false,
      interactive: false,
      child: buildPageB(),
    );

    final pass = ShaderPass(
      name: 'Image',
      type: PassType.image,
      code: getShaderCode(),
      channels: [dashboardChannel!, playerChannel!],
    );

    return ShaderToyProject(name: 'Widget Transition', passes: [pass]);
  }

  Widget buildPageA() {
    return StatefulBuilder(
      builder: (context, setPageState) {
        return Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Page A',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: 50,
                  itemBuilder: (context, index) {
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.folder,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      title: Text(
                        'Item ${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Description for item ${index + 1}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Full interactive Flutter widget rendered into GPU iChannel0',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: nextTransitionPage,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Page 2'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildPageB() {
    return StatefulBuilder(
      builder: (context, setPageState) {
        return Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Page B',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(sliderPercentage * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 320,
                      child: Slider(
                        value: sliderPercentage,
                        onChanged: (val) {
                          setPageState(() {
                            sliderPercentage = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Text(
                    'Full interactive Flutter widget rendered into GPU iChannel1',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: previousTransitionPage,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Page 1'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildBannerActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: transitionPageIndex == 0 ? null : previousTransitionPage,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text(
            'Back Arrow',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            transitionPageIndex == 0 ? 'Page 1 of 2' : 'Page 2 of 2',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEC4899),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: transitionPageIndex == 1 ? null : nextTransitionPage,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text(
            'Right Arrow',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }

  String getShaderCode() {
    return '''
uniform float progress;

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    
    // User-controlled transition progress from 0.0 (Page A) to 1.0 (Page B)
    // driven directly via controller.setUniform('progress', value)
    float p = clamp(progress, 0.0, 1.0);
    
    // Clean static render when idle on either page
    if (p <= 0.0) {
        fragColor = texture(iChannel0, uv);
        return;
    }
    if (p >= 1.0) {
        fragColor = texture(iChannel1, uv);
        return;
    }
    
    // During transition: digital block displacement & glowing wipe
    vec2 block = floor(uv * vec2(30.0, 15.0));
    float noise = hash2(block);
    float threshold = smoothstep(0.0, 1.0, p);
    float edge = smoothstep(threshold - 0.1, threshold + 0.1, noise + uv.x * 0.2);
    
    float disp = sin(uv.y * 20.0 + iTime * 5.0) * 0.03 * (1.0 - abs(p - 0.5) * 2.0);
    vec2 uvA = uv + vec2(disp * (1.0 - p), 0.0);
    vec2 uvB = uv - vec2(disp * p, 0.0);
    
    vec4 colA = texture(iChannel0, clamp(uvA, 0.0, 1.0));
    vec4 colB = texture(iChannel1, clamp(uvB, 0.0, 1.0));
    
    float glow = 1.0 - abs(edge - 0.5) * 2.0;
    glow = pow(max(0.0, glow), 3.0) * (1.0 - abs(progress - 0.5) * 2.0);
    vec3 glowCol = vec3(0.0, 0.9, 1.0) * glow * 2.5;
    
    vec4 finalCol = mix(colA, colB, edge);
    finalCol.rgb += glowCol;
    fragColor = finalCol;
}
''';
  }

  void dispose() {
    pageTransitionAnimation.removeListener(_onTransitionTick);
    pageTransitionController.dispose();
  }
}
