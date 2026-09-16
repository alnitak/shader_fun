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
      channels: [
        SoLoudAudioChannel(src: 'assets/audio/most_geometric_person.mp3'),
      ],
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

    // Image: Pinch effect reacting to bass, mid, and high frequencies
    final passImage = ShaderPass(
      name: 'Image',
      type: PassType.image,
      channels: [
        BufferChannel(bufferIndex: 0), // Buffer A (Audio)
        BufferChannel(bufferIndex: 1), // Buffer B (Widget list)
      ],
      code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = texture(iChannel0, vec2(0.005, 0.25)).r;

    // Pinch effect reacting to frequencies
    vec2 c = uv - 0.5;
    float d = length(c);
    float pinch = bass * (1.0 - smoothstep(0.0, 0.3, d));

    vec2 distortedUv = clamp(0.5 + c * (1.0 + pinch), 0.0, 1.0);
    fragColor = texture(iChannel1, distortedUv);
}
''',
    );

    final project = ShaderProject(
      name: 'Audio Pinch Demo',
      passes: [passA, passB, passImage],
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
