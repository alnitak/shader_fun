---
name: shader-fun-idioms
version: 1
description: Core mental model for shader_fun — ShaderProject, pass types (common, image, bufferA..D, sound), Shadertoy GLSL translation, built-in uniforms, and rendering pipeline. Use when designing shader architectures, understanding execution flow, or porting Shadertoy GLSL to Flutter.
---

# shader_fun idioms

`shader_fun` brings the complete [Shadertoy](https://www.shadertoy.com) GLSL ecosystem to Flutter across mobile, desktop, and web. It uses `flutter_gpu` / `flutter_scene` under the hood to compile and execute multi-pass GLSL shaders on the GPU with full-screen quad rendering, double-buffering (ping-pong feedback loops), and rich channel inputs.

Assumptions carried over from standard Flutter `FragmentProgram` / `.frag` shaders or generic canvas painters do not apply:
- Standard Flutter `FragmentProgram` supports single-pass fragment shaders with restricted GLSL and strict uniform ordering.
- `shader_fun` supports the **full Shadertoy multi-pass pipeline**: `Common`, `Buffer A` through `Buffer D`, `Sound`, and `Image` presentation passes, ping-pong feedback loops, live Flutter widget rasterization into GPU textures, audio FFT/waveform spectrums, and dynamic custom uniforms with zero recompilation overhead.

---

## Minimal Example

```dart
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

void main() => runApp(const MaterialApp(home: SimpleShaderScreen()));

class SimpleShaderScreen extends StatefulWidget {
  const SimpleShaderScreen({super.key});

  @override
  State<SimpleShaderScreen> createState() => _SimpleShaderScreenState();
}

class _SimpleShaderScreenState extends State<SimpleShaderScreen> {
  late final ShaderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShaderController();

    // Compile and run standard Shadertoy GLSL
    _controller.compilePass(
      null, // null targets the default Image pass
      codeOverride: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
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
          child: ShaderViewport(
            controller: _controller,
            showControls: true,
          ),
        ),
      ),
    );
  }
}
```

---

## Architectural Entities

### 1. `ShaderProject`
A container holding project metadata (`id`, `name`, `author`, `description`, `url`) and a list of `ShaderPass`es. It provides feature introspection properties:
- `project.usesMouse`: detects if any pass queries `iMouse`.
- `project.usesAudio`: detects audio file channels or GPU sound pass.
- `project.hasSoundPass`: detects GPU sound synthesis (`PassType.sound`).
- `project.usesMic`: detects live microphone capture channels (`MicAudioChannel`).
- `project.usesKeys`: detects interactive keyboard input textures (`KeyboardChannel`).
- `project.usesTextures`: detects 2D image textures or cubemaps.

### 2. `ShaderPass` & `PassType`
Each pass has a `type`, `name`, `code`, and up to 4 input channels (`channels[0..3]`):
- `PassType.common`: Shared GLSL code (structs, constants, functions). It is prepended automatically to all other passes before compilation. Does not render to any target.
- `PassType.bufferA`, `PassType.bufferB`, `PassType.bufferC`, `PassType.bufferD`: Offscreen render targets. Double-buffered (ping-pong) so a buffer pass can sample its own output from the previous frame via `BufferChannel`.
- `PassType.sound`: Procedural GPU audio synthesizer. Executes `mainSound(int samp, float time)` on the GPU, outputting stereo float samples streamed to the audio device via `flutter_soloud`.
- `PassType.image`: The final presentation pass rendered to the screen/viewport.

### 3. `ShaderController`
The central engine controlling shader compilation, uniform buffer packing, frame animation loop (driven by Flutter `Ticker`), audio sync, and state notification:
- Reactive state notifiers: `isPlayingNotifier`, `isCompilingNotifier`, `lastErrorNotifier`, `currentImageNotifier`.
- Control APIs: `play()`, `pause()`, `togglePlay()`, `rewind()`, `stepForward()`, `setSpeed(double)`.
- Dynamic uniform mutation: `setUniform(name, value)` with zero recompilation.

### 4. `ShaderViewport`
The Flutter widget hosting the rendering surface:
- Renders the current frame output via GPU acceleration.
- Translates pointer interactions (hover, click, drag) into normalized `iMouse` uniforms.
- Dispatches keyboard strokes to `KeyboardChannel` textures.
- Forwards pointer gestures into `WidgetChannel` subtrees.
- Optional built-in toolbar (`showControls: true`) with play/pause, timecode, step forward, rewind, resolution scale slider, and fullscreen toggle.

---

## Built-in Shadertoy Uniforms

All passes (except `common`) automatically receive standard Shadertoy uniforms:

| Uniform | Type | Description |
|---|---|---|
| `vec3 iResolution` | `vec3` | Viewport dimensions in pixels: `x = width`, `y = height`, `z = pixel_aspect_ratio` (usually 1.0). |
| `float iTime` | `float` | Playback time in seconds. Affected by playback speed. |
| `float iTimeDelta` | `float` | Duration of the previous frame in seconds. |
| `float iFrameRate` | `float` | Moving average FPS (frames per second). |
| `int iFrame` | `int` | Integer animation frame index (starts at 0). |
| `vec4 iMouse` | `vec4` | Mouse coordinates: `xy` = current drag position, `zw` = click anchor position and button state. |
| `vec4 iDate` | `vec4` | System clock: `year`, `month` (0-based), `day`, `seconds_of_day`. |
| `float iSampleRate` | `float` | Audio output sample rate (typically 44100.0). |
| `vec3 iChannelResolution[4]` | `vec3[4]` | Width, height, aspect ratio of channels 0 through 3. |
| `float iChannelTime[4]` | `float[4]` | Current playback time for audio/video channels. |
| `sampler2D iChannel0..3` | `sampler2D` | Sampler slots for 2D textures, buffers, audio, widgets, or keyboard. |

---

## Execution Order Per Frame

During each tick of the animation loop:
1. `iTimeDelta`, `iTime`, `iFrame`, and `iFrameRate` advance.
2. If microphone or audio channels are active, FFT and waveform data update their 512x2 pixel buffers.
3. If `WidgetChannel`s are active, the Flutter widget tree renders offscreen to its texture.
4. Offscreen buffer passes execute in sequence:
   - `Buffer A` renders (ping-ponging targets if self-referenced).
   - `Buffer B` renders.
   - `Buffer C` renders.
   - `Buffer D` renders.
5. `Image` pass renders to the main framebuffer using outputs from buffers and bound channels.
6. The resulting `ui.Image` is pushed to `currentImageNotifier` and painted to the screen.

---

## Common Traps & Divergences

| Don't do this | Do this instead | Why |
|---|---|---|
| Writing `#version 300 es` or `precision highp float;` | Omit version directives in your pass code | `shader_fun` wraps your code with the platform's required preamble and uniforms automatically. |
| Calling `gl_FragColor = ...` | Use `void mainImage(out vec4 fragColor, in vec2 fragCoord)` | `shader_fun` uses the Shadertoy entrypoint signature. |
| Treating `fragCoord` as normalized `0.0 .. 1.0` | Divide by `iResolution.xy`: `vec2 uv = fragCoord / iResolution.xy;` | `fragCoord` contains pixel coordinates (`0.5` to `width - 0.5`). |
| Forgetting to call `controller.dispose()` | Always dispose controllers in `StatefulWidget.dispose()` | Avoids GPU memory leaks and lingering `Ticker` registrations. |
