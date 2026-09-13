import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class TransitionDemo {
  TransitionDemo({required this.vsync, required this.onStateChanged}) {
    pageTransitionAnimation = CurvedAnimation(
      parent: pageTransitionController,
      curve: Curves.linear,
    )..addListener(_onTransitionTick);
  }

  final TickerProvider vsync;
  final VoidCallback onStateChanged;

  int transitionPageIndex = 0; // 0: Page 1 (A), 1: Page 2 (B)
  double sliderPercentage = 0.65;
  double logoTurns = 0.0;

  WidgetChannel? dashboardChannel;
  WidgetChannel? playerChannel;
  ShaderToyController? _controller;

  late final AnimationController pageTransitionController = AnimationController(
    vsync: vsync,
    duration: const Duration(milliseconds: 5000),
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
    logoTurns = 0.0;

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && logoTurns == 0.0) {
            setPageState(() {
              logoTurns = 1.0;
            });
          }
        });

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1E1E), Color.fromARGB(255, 148, 30, 30)],
            ),
          ),
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
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: 50,
                        itemBuilder: (context, index) {
                          return ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white24,
                              child: Icon(
                                Icons.folder,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                            title: Text('Item ${index + 1}'),
                            subtitle: Text('Description for item ${index + 1}'),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: Center(
                        child: AnimatedRotation(
                          turns: logoTurns,
                          duration: const Duration(seconds: 4),
                          curve: Curves.linear,
                          onEnd: () {
                            if (context.mounted) {
                              setPageState(() {
                                logoTurns += 1.0;
                              });
                            }
                          },
                          child: const FlutterLogo(size: 180),
                        ),
                      ),
                    ),
                  ],
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
        // At the top of buildPageB's builder:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            setPageState(() {});
          }
        });
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.fromARGB(255, 13, 2, 108), Color(0xFF1E1E1E)],
            ),
          ),
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
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(sliderPercentage * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 250,
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
                    SizedBox(
                      width: 200,
                      child: Center(
                        child: AnimatedRotation(
                          turns: logoTurns,
                          duration: const Duration(seconds: 4),
                          curve: Curves.linear,
                          onEnd: () {
                            if (context.mounted) {
                              setPageState(() {
                                logoTurns += 1.0;
                              });
                            }
                          },
                          child: const FlutterLogo(size: 120),
                        ),
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

// credits:
// https://www.shadertoy.com/view/ls3cDB
// https://github.com/alnitak/flutter_shader_fxs/blob/main/example/assets/shaders/page_curl.frag

#define pi 3.14159265359
#define radius .1

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float aspect = iResolution.x / iResolution.y;

    vec2 uv = fragCoord * vec2(aspect, 1.) / iResolution.xy;
    float p = clamp(progress, 0.0, 1.0);

    // Clean static rendering when idle on either page
    if (p <= 0.0 && iMouse.z <= 0.0) {
        fragColor = texture(iChannel0, uv * vec2(1. / aspect, 1.));
        return;
    }
    if (p >= 1.0 && iMouse.z <= 0.0) {
        fragColor = texture(iChannel1, uv * vec2(1. / aspect, 1.));
        return;
    }

    vec2 mouse;
    vec2 mouseDir;
    vec2 origin;
    float mouseDist;

    mouseDir = normalize(vec2(1.0, 0.2));
    origin = vec2(0.0);
    float projMax = aspect * mouseDir.x + 1.0 * mouseDir.y;
    mouseDist = mix(projMax + radius, -radius * (pi + 1.5), p);

    float proj = dot(uv - origin, mouseDir);
    float dist = proj - mouseDist;

    vec2 linePoint = uv - dist * mouseDir;

    if (dist > radius) {
        fragColor = texture(iChannel1, uv * vec2(1. / aspect, 1.));
        fragColor.rgb *= pow(clamp(dist - radius, 0., 1.) * 1.5, .2);
    } else if (dist >= 0.) {
        // map to cylinder point
        float theta = asin(clamp(dist / radius, 0.0, 1.0));
        vec2 p2 = linePoint + mouseDir * (pi - theta) * radius;
        vec2 p1 = linePoint + mouseDir * theta * radius;
        uv = (p2.x <= aspect && p2.y <= 1. && p2.x > 0. && p2.y > 0.) ? p2 : p1;
        fragColor = texture(iChannel0, uv * vec2(1. / aspect, 1.));
        fragColor.rgb *= pow(clamp((radius - dist) / radius, 0., 1.), .2);
    } else {
        vec2 pFold = linePoint + mouseDir * (abs(dist) + pi * radius);
        uv = (pFold.x <= aspect && pFold.y <= 1. && pFold.x > 0. && pFold.y > 0.) ? pFold : uv;
        fragColor = texture(iChannel0, uv * vec2(1. / aspect, 1.));
    }
}
''';
  }

  void dispose() {
    pageTransitionAnimation.removeListener(_onTransitionTick);
    pageTransitionController.dispose();
  }
}
