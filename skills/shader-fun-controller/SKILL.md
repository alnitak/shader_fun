---
name: shader-fun-controller
version: 1
description: Lifecycle, compilation, playback control, reactive state listening, and timing with ShaderController. Use when controlling shader playback, compiling GLSL at runtime, listening to frame or error states, or resizing the viewport.
---

# shader_fun controller

`ShaderController` coordinates the entire shader execution session: compiling GLSL passes, allocating GPU uniform buffers, driving animation ticks via Flutter's `Ticker`, and managing channel resources.

---

## 1. Instantiation & Widget Integration

A `ShaderController` can be created with an optional `vsync` provider and starter project:

```dart
class ShaderPlayerWidget extends StatefulWidget {
  const ShaderPlayerWidget({super.key});

  @override
  State<ShaderPlayerWidget> createState() => _ShaderPlayerWidgetState();
}

class _ShaderPlayerWidgetState extends State<ShaderPlayerWidget>
    with SingleTickerProviderStateMixin {
  late final ShaderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShaderController(
      initialResolution: const Size(1920, 1080),
      vsync: this, // TickerProvider to drive playback animation
      autoPlay: true,
    );

    _loadShader();
  }

  Future<void> _loadShader() async {
    // Compile GLSL code into the Image pass
    await _controller.compilePass(
      null, // null defaults to Image pass
      codeOverride: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
''',
    );
  }

  @override
  void dispose() {
    // Always dispose the controller to free GPU pipelines and stop timers
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderViewport(
      controller: _controller,
      showControls: true,
    );
  }
}
```

> [!NOTE]
> If `ShaderViewport` is used in the widget tree, it automatically calls `controller.attachTicker(this)` if the controller was initialized without a `vsync`.

---

## 2. Playback Control APIs

`ShaderController` provides explicit transport controls:

```dart
// 1. Play / Pause
_controller.play();
_controller.pause();
_controller.togglePlay();

// 2. Seek / Rewind to start (t = 0.0s, frame = 0)
await _controller.rewind();

// 3. Step forward by one frame (useful for frame-by-frame inspection)
await _controller.stepForward();

// 4. Playback Speed (1.0 = normal, 2.0 = 2x fast, 0.5 = half-speed)
_controller.setSpeed(1.5);

// 5. Force a single frame render while paused
await _controller.renderSingleFrame();
```

---

## 3. Compilation APIs

### Compile Full Project
Compiles all passes in `_controller.project` (`common`, `bufferA..D`, `sound`, `image`):
```dart
final bool success = await _controller.compile();
if (!success) {
  print('Compilation failed: ${_controller.lastError}');
}
```

### Compile Single Pass
Recompiles a specific pass without recompiling the entire project. If `codeOverride` is supplied, it replaces the pass's GLSL code:
```dart
final imagePass = _controller.project.imagePass;
final bool success = await _controller.compilePass(
  imagePass,
  codeOverride: myNewGlslString,
);
```

---

## 4. Reactive State Notifiers

`ShaderController` implements Flutter's `Listenable` and exposes dedicated `ValueNotifier` properties for granular UI updates without rebuilding the whole widget:

```dart
// 1. Is Playing / Paused
ValueListenableBuilder<bool>(
  valueListenable: _controller.isPlayingNotifier,
  builder: (context, isPlaying, _) {
    return IconButton(
      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
      onPressed: _controller.togglePlay,
    );
  },
);

// 2. Compilation in progress
ValueListenableBuilder<bool>(
  valueListenable: _controller.isCompilingNotifier,
  builder: (context, isCompiling, _) {
    if (isCompiling) return const CircularProgressIndicator();
    return const SizedBox.shrink();
  },
);

// 3. Error status & diagnostic messages
ValueListenableBuilder<String?>(
  valueListenable: _controller.lastErrorNotifier,
  builder: (context, error, _) {
    if (error == null) return const SizedBox.shrink();
    return Text('Error: $error', style: const TextStyle(color: Colors.red));
  },
);

// 4. Current rendered image output
ValueListenableBuilder<ui.Image?>(
  valueListenable: _controller.currentImageNotifier,
  builder: (context, image, _) {
    // Contains the latest ui.Image rendered by the pipeline
    return Text('Frame resolution: ${image?.width}x${image?.height}');
  },
);
```

---

## 5. Viewport Resolution & Scaling

Dynamic resolution changes scale the GPU render targets and update `iResolution`:

```dart
// Update target resolution directly:
_controller.updateResolution(const Size(1280, 720));

// Inspect current metrics:
final double currentFps = _controller.fps;
final double currentTime = _controller.time;
final int currentFrame = _controller.frame;
final Size currentResolution = _controller.resolution;
```

---

## 6. Controller Traps & Best Practices

- **Never create multiple controllers for the same viewport**: Pass a single controller reference down.
- **Dispose on unmount**: Always call `_controller.dispose()` in `State.dispose()`. This terminates audio capture, stops tickers, and frees GPU texture handles.
- **Handle compilation failure gracefully**: Inspect `controller.lastError` to display formatted syntax diagnostics to users or debug consoles.
