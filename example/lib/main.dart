import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SimpleExampleApp()));
}

class SimpleExampleApp extends StatefulWidget {
  const SimpleExampleApp({super.key});

  @override
  State<SimpleExampleApp> createState() => _SimpleExampleAppState();
}

class _SimpleExampleAppState extends State<SimpleExampleApp> {
  late final ShaderController _controller;

  @override
  void initState() {
    super.initState();

    // Buffer A: Audio track
    final passA = ShaderPass(
      name: 'Buffer A',
      type: PassType.bufferA,
      channels: [SoLoudAudioChannel(src: 'assets/audio/electro_nebulae.mp3')],
      code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
''',
    );

    // Buffer B: Simple Flutter widget list
    final passB = ShaderPass(
      name: 'Buffer B',
      type: PassType.bufferB,
      channels: [
        WidgetChannel(
          child: Material(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FlutterLogo(size: 50),
                  FlutterLogo(size: 100),
                  SizedBox(
                    width: 210,
                    child: ListView.builder(
                      itemCount: 50,
                      itemBuilder: (context, i) {
                        return ListTile(
                          title: Text('shader_fun item [$i]'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey, width: 1),
                          ),
                        );
                      },
                    ),
                  ),
                  FlutterLogo(size: 100),
                  FlutterLogo(size: 50),
                ],
              ),
            ),
          ),
        ),
      ],
      code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
''',
    );

    // Buffer C: Pinch effect reacting to bass, mid, and high frequencies
    final passC = ShaderPass(
      name: 'Buffer C',
      type: PassType.bufferC,
      channels: [
        BufferChannel(bufferIndex: 0), // Buffer A (Audio)
        BufferChannel(bufferIndex: 1), // Buffer B (Widget list)
      ],
      code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Bass, mid, and high frequencies from Buffer A (row 0 at y = 0.25)
    float bass = texture(iChannel0, vec2(0.05, 0.25)).r;
    float mid  = texture(iChannel0, vec2(0.35, 0.25)).r;
    float high = texture(iChannel0, vec2(0.75, 0.25)).r;

    // Pinch effect reacting to frequencies
    vec2 c = uv - 0.5;
    float d = length(c);
    float pinch = bass * 0.5 * (1.0 - smoothstep(0.0, 0.50, d))
                + mid  * 0.3 * (1.0 - smoothstep(0.0, 0.35, d))
                + high * 0.2 * (1.0 - smoothstep(0.0, 0.20, d));

    vec2 distortedUv = clamp(0.5 + c * (1.0 + pinch), 0.0, 1.0);
    fragColor = texture(iChannel1, distortedUv);
}
''',
    );

    // Image: Presentation pass showing Buffer C
    final passImage = ShaderPass(
      name: 'Image',
      type: PassType.image,
      channels: [
        BufferChannel(bufferIndex: 2), // Buffer C
      ],
      code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
''',
    );

    final project = ShaderProject(
      name: 'Audio Pinch Demo',
      passes: [passA, passB, passC, passImage],
    );

    _controller = ShaderController(initialProject: project, autoPlay: true);
    _controller.compileAllPasses();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: ShaderViewport(controller: _controller));
  }
}
