# Shader Fun

A high-performance Flutter package for running, writing, and experimenting with **Shadertoy GLSL** shaders across mobile, desktop, and web.

`shader_fun` brings the rich ecosystem of [Shadertoy](https://www.shadertoy.com) to Flutter: full-screen quad rendering, all classic Shadertoy uniform variables, multi-pass ping-pong buffers, and rich channel inputs including 2D textures, audio playback, microphone frequency visualizers, buffer loops, and keyboard interaction.

---

## Features

- **Interactive Viewport (`ShaderToyViewport`)**:
  - Embedded Flutter widget that renders shaders with GPU acceleration.
  - Interactive pointer/touch input handling for `iMouse` (drag, click, hold).
  - Built-in on-screen playback control toolbar (Play, Pause, Stop, Rewind, Step forward, FPS monitor, Resolution scaling, and Fullscreen toggle).
  - Clean error surfacing: compiler syntax errors are displayed directly in the viewport.
- **Cross-Platform Support**:
  - **macOS** (Metal)
  - **iOS** (Metal)
  - **Android** (Vulkan)
  - **Linux** (Vulkan)
  - **Windows** (Vulkan)
  - **Web** (WebGL2 via JavaScript & WebAssembly / WASM)
- **All Standard Shadertoy Uniforms Supported**:
  - `vec3 iResolution`: Viewport resolution in pixels (width, height, aspect ratio).
  - `float iTime`: Playback time in seconds.
  - `float iTimeDelta`: Render time between consecutive frames in seconds.
  - `float iFrameRate`: Moving average of frames per second.
  - `int iFrame`: Current animation frame count.
  - `vec4 iMouse`: Mouse coordinates: `xy` = current drag position, `zw` = click position and button state.
  - `vec4 iDate`: Current system date and time (`year`, `month`, `day`, `seconds_of_day`).
  - `float iSampleRate`: Audio playback sample rate (typically 44100 Hz).
  - `vec3 iChannelResolution[4]`: Resolution of each bound input channel.
- **Multi-Pass Pipelines & Ping-Pong Buffers**:
  - Full support for multi-stage rendering: `Common`, `Buffer A`, `Buffer B`, `Buffer C`, `Buffer D`, and `Image` passes.
  - Automatic double-buffering (ping-pong) enabling self-referential feedback loops (e.g. fluid simulations, game of life, iterative raymarching, smoke & erosion).
  - Upstream buffer passes can be piped into any downstream pass channel.
- **Dynamic Channel Types (`iChannel0` .. `iChannel3`)**:
  - **Live Interactive Widgets (`WidgetChannel`)**: Rasterize any Flutter widget subtree into a live GPU texture (`sampler2D`) on every frame with zero frame delay. Supports full bidirectional gestures (taps, drags, mouse scrolls, keyboard typing in `TextField`s). Offers `autoRender = true` (automatic placement via horizontal and vertical percentiles) and `autoRender = false` (raw sampling for custom GLSL effects, distortions, and page transitions).
  - **2D Textures**: Load PNG/JPEG images from assets or files with configurable filter options (nearest, linear, mipmap), address modes (clamp, repeat, mirror), and vertical flip (`vflip`).
  - **Audio Files**: Stream local audio files or assets via `flutter_soloud`, providing real-time 512x2 audio textures (row 0: FFT frequency spectrum, row 1: time-domain waveform).
  - **Microphone Audio**: Capture live microphone input via `flutter_recorder` and feed real-time voice/music spectrum and waveform data into the shader.
  - **Buffer Channels**: Connect another pass's output as an input texture.
  - **Keyboard**: 256-key ASCII state texture (row 0: is-down, row 1: toggle state, row 2: key-press pulse).
- **Runtime Shader Compilation**:
  - **Native**: Compiles GLSL on the fly using Flutter's offline `impellerc` compiler.
  - **Web**: Uses an in-memory FlatBuffer bundle builder and compiles GLSL ES 3.00 directly in the browser via WebGL2, returning syntax errors with accurate user line numbers.
- **JSON Import / Export**:
  - Directly load/save projects in `.json` format, preserving passes, channel bindings, and metadata.

---

## Getting Started

Add `shader_fun` to your `pubspec.yaml`:

```yaml
dependencies:
  shader_fun:
    path: ../shader_fun # or from git / pub
```

### Web Setup

`shader_fun` uses **WebAssembly** and WebGL2 on the web. Audio playback and microphone capture require helper scripts in your `web/index.html`.

In your `web/index.html`, add the following scripts before `flutter_bootstrap.js`:

```html
<!DOCTYPE html>
<html>
<head>
  ...
</head>
<body>
  <!-- Helper loaders for flutter_soloud and flutter_recorder WebAssembly modules -->
  <script src="assets/packages/flutter_soloud/web/init_soloud.js" defer></script>
  <script src="assets/packages/flutter_recorder/web/init_recorder_module.dart.js" defer></script>

  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
```

> [!NOTE]
> If your web app uses multi-threaded WebAssembly (e.g., advanced SoLoud filters or background audio processing), make sure your web server sends the following Cross-Origin Isolation headers:
> ```http
> Cross-Origin-Opener-Policy: same-origin
> Cross-Origin-Embedder-Policy: require-corp
> ```

### Microphone Permissions (for Live Audio Inputs)

If you use microphone channels (`MicChannel`) to drive audio-reactive visualizers, configure platform permissions:

- **macOS**:
  - Add `NSMicrophoneUsageDescription` to `macos/Runner/Info.plist`.
  - Enable audio recording in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
    ```xml
    <key>com.apple.security.device.audio-input</key>
    <true/>
    ```
- **iOS**:
  - Add `NSMicrophoneUsageDescription` to `ios/Runner/Info.plist`.
- **Android**:
  - Add `<uses-permission android:name="android.permission.RECORD_AUDIO" />` to `android/app/src/main/AndroidManifest.xml`.

---

## Usage

### 1. Minimal Example

Below is a complete, minimal Flutter app rendering a classic Shadertoy rainbow plasma shader:

```dart
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ShaderScreen(),
    );
  }
}

class ShaderScreen extends StatefulWidget {
  const ShaderScreen({super.key});

  @override
  State<ShaderScreen> createState() => _ShaderScreenState();
}

class _ShaderScreenState extends State<ShaderScreen> {
  late final ShaderToyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShaderToyController();

    // Compile and run a basic Shadertoy GLSL fragment shader:
    _controller.compilePass(
      null, // null targets the default 'Image' presentation pass
      codeOverride: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Normalized coordinates from 0.0 to 1.0
    vec2 uv = fragCoord / iResolution.xy;

    // Time-varying rainbow colors
    vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0.0, 2.0, 4.0));

    fragColor = vec4(col, 1.0);
}
''',
    ).then((_) => _controller.play());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ShaderToyViewport(
            controller: _controller,
            showControls: true, // Shows play/pause toolbar overlay
          ),
        ),
      ),
    );
  }
}
```

### 2. Loading a Project from JSON

You can save any shader from to a `.json` file and load it directly:

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shader_fun/shader_fun.dart';

Future<void> loadShadertoyJson(ShaderToyController controller, String assetPath) async {
  final jsonString = await rootBundle.loadString(assetPath);
  final project = ShaderToyProject.fromJson(jsonDecode(jsonString));

  await controller.loadProject(project);
  controller.play();
}
```

### 3. Binding Channels (`iChannel0` .. `iChannel3`)

Each pass supports up to 4 input channels:

```dart
final pass = project.imagePass!;

// 1. Static 2D Texture Image
pass.channels[0] = TextureChannel(
  source: 'assets/textures/wood.png',
  vflip: true, // Flips vertically to match OpenGL/Shadertoy conventions
  filter: TextureFilter.linear,
  wrap: TextureWrap.repeat,
);

// 2. Audio File (Frequency & Waveform Spectrum)
pass.channels[1] = AudioChannel(
  source: 'assets/audio/synth.mp3',
);

// 3. Live Microphone Input
pass.channels[2] = MicChannel();

// 4. Ping-Pong Buffer Loop (reads previous frame of Buffer A)
pass.channels[3] = BufferChannel(
  bufferType: PassType.bufferA,
);

// 5. Live Interactive Flutter Widget
pass.channels[0] = WidgetChannel(
  width: 500,
  height: 380,
  pixelRatio: 2.0,
  autoRender: true, // Automatically bounds widget within percentiles
  horizontalPercentile: (0.1, 0.9), // Normalized coordinates [0.0, 1.0]
  verticalPercentile: (0.05, 0.95),
  interactive: true, // Forwards taps, drags, mouse wheel, and keyboard
  child: MyInteractiveWidget(),
);

await controller.loadProject(project);
```

In your GLSL code:

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Sample 2D image texture or live Flutter widget from iChannel0:
    vec4 imageColor = texture(iChannel0, uv);

    // Sample audio spectrum from iChannel1 (x: frequency, y: 0.25 = FFT, 0.75 = Waveform):
    float frequency = texture(iChannel1, vec2(uv.x, 0.25)).r;
    float waveform  = texture(iChannel1, vec2(uv.x, 0.75)).r;

    fragColor = imageColor * (frequency + waveform);
}
```

### 4. Custom Uniforms (`setUniform`)

You can declare custom GLSL uniforms in your shaders and update them dynamically from Dart with **zero recompilation overhead**—perfect for 60/120 FPS animations, page transitions, sliders, and interactive UI state:

1. **Declare uniforms in your shader** using standard GLSL syntax:
```glsl
uniform float progress;
uniform vec2 focusPoint;
uniform vec4 glowColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 scene = texture(iChannel0, uv);
    fragColor = mix(scene, glowColor, progress);
}
```

2. **Set uniform values dynamically via `ShaderToyController`**:
```dart
// Supports double/num (float/int), Offset/Size (vec2), Color (vec4), and List<num>:
controller.setUniform('progress', animation.value);
controller.setUniform('focusPoint', const Offset(0.5, 0.5));
controller.setUniform('glowColor', Colors.cyanAccent);
```

- **Zero recompilation**: Updates the GPU uniform buffer directly every frame without recompiling the shader bundle.
- **Auto-repaint**: If playback is paused, calling `controller.setUniform(...)` automatically renders a single frame so changes are reflected on screen immediately.
- **Cross-platform**: Supported seamlessly across native Impeller (macOS, iOS, Android) and WebGL2 (Web).

#### Capacity & GPU Memory Pagination

- **Default Capacity**: By default, `ShaderToyUniforms.maxCustomUniformSlots = 16` generic `vec4` registers (64 floats = 256 bytes) are reserved for custom uniforms.
- **Hardware Alignment & Pagination**: Sizing the custom uniform space to 256 bytes aligns with standard GPU driver suballocation pagination (for example, `minUniformBufferOffsetAlignment` on Vulkan and Metal is typically 256 bytes). Even allocating a single 4-byte float still consumes a 256B/4KB physical page in GPU VRAM.
- **Single-Step Scaling**: If your project requires more custom uniforms, updating `ShaderToyUniforms.maxCustomUniformSlots` (e.g. to `32` or `64`) is the **only step required**. All GLSL wrappers, native Impeller buffers, WebGL reflection structs, and `ShaderToyUniforms.totalUniformBufferSize` dynamically scale together automatically without any code changes across renderers or compilers.

---

## Example Applications

The package includes two feature-packed example applications in the `example` folder:

### 1. Shadertoy Studio (`example/lib/studio_example/main.dart`)

An in-depth interactive GLSL workstation and IDE:

- **Live Code Editor**: Write and edit GLSL shaders in real time with immediate compilation and hot reloading.
- **Diagnostics Panel**: Compiler syntax errors with exact source lines are surfaced whenever compilation fails.
- **Pass Tabs**: Switch between `Common`, `Buffer A`, `Buffer B`, `Buffer C`, `Buffer D`, and `Image` passes.
- **Channel Setup Dialog**: Configure channels interactively (select textures, audio files, mic inputs, buffers, or keyboard).
- **Bundled Showcase**: Includes complex multi-pass and audio-reactive shaders stored in `example/shaders`:
  - *Heartfelt* (procedural rainy window with texture channels and depth blur)
  - *Mouse Paint Eroded Mountains* (multi-pass ping-pong terrain simulation)
  - *Dancing Flutter* (multi-pass audio-reactive visualizer)

To run the studio app:

```bash
cd example
flutter run -t lib/studio_example/main.dart
```

### 2. Interactive Widget Showcase (`example/lib/widget_example/main.dart`)

A dedicated showcase demonstrating live `WidgetChannel` rasterization and gesture forwarding across 4 interactive scenarios:

- **Exploding Button**: Demonstrates `autoRender = true` bounded to `[0.3, 0.7]` x `[0.45, 0.55]`. Clicking the Flutter button triggers a cellular fragment shatter explosion, shockwave blast, and sparks.
- **Liquid ListView**: Demonstrates interactive scrolling, counters, and switches rendered into a live GPU texture under refractive water caustics and mouse-following ripple waves.
- **Retro CRT Terminal**: Demonstrates live keyboard typing and focus inside Flutter `TextField`s through CRT barrel curvature distortion, phosphor bloom, and scanlines.
- **Digital Glitch Transition**: Demonstrates `autoRender = false` for seamless widget-to-widget page transitions driven by manual arrow navigation between Page A and Page B with glowing digital glitch wipe distortion.

To run the widget showcase:

```bash
cd example
flutter run -t lib/widget_example/main.dart
```

---

## Additional Information

`shader_fun` is built upon specialized low-level packages:

- [**flutter_scene**](https://pub.dev/packages/flutter_scene): Powers the GPU pipeline, vertex layout, render pipelines, uniform buffer objects (std140), and WebGL2 shims on the web.
- [**flutter_soloud**](https://pub.dev/packages/flutter_soloud): High-performance, low-latency C++ audio engine based on SoLoud, used to play audio files and compute live FFT spectrums and waveforms.
- [**flutter_recorder**](https://pub.dev/packages/flutter_recorder): Low-latency microphone capture engine with SpeexDSP/PFFFT support used for live mic audio visualizers.
- [**image**](https://pub.dev/packages/image): Pure-Dart image decoder used to load texture PNGs and JPEGs without premultiplied alpha artifacts.

### Contributing & Issues

Contributions, bug reports, and feature requests are welcome! Please open an issue or pull request on the repository.

---

## License

This project is licensed under the [MIT License](LICENSE).
