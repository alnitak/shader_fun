---
name: shader-fun-viewport
version: 1
description: Embedding ShaderViewport, handling iMouse pointer interactions, keyboard capture, and on-screen controls. Use when adding shader rendering to Flutter widget trees, handling touch/mouse input, or customizing viewport controls.
---

# shader_fun viewport

`ShaderViewport` is the primary Flutter widget used to display the rendered output of a `ShaderController`. It provides interactive touch and mouse tracking for the `iMouse` uniform, routes keyboard input, forwards gestures into interactive `WidgetChannel` subtrees, and renders an optional playback HUD.

---

## 1. Embedding in the Widget Tree

Place `ShaderViewport` inside any layout container (e.g. `AspectRatio`, `Expanded`, `Container`):

```dart
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

class ShaderCanvas extends StatelessWidget {
  const ShaderCanvas({super.key, required this.controller});

  final ShaderController controller;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ShaderViewport(
        controller: controller,
        showControls: true, // Display on-screen playback HUD
        isFullscreen: false,
        onToggleFullscreen: () {
          // Handle full screen presentation
        },
      ),
    );
  }
}
```

---

## 2. Pointer Tracking & the `iMouse` Uniform

In Shadertoy GLSL, `vec4 iMouse` tracks cursor/touch interaction:
- `iMouse.xy`: Current cursor position in pixels while holding down a touch or mouse button.
- `iMouse.zw`: The position in pixels where the touch or click *started*.

### Shadertoy Coordinate Conventions
- Flutter's coordinate system has `(0, 0)` at the **top-left**.
- Shadertoy's coordinate system has `(0, 0)` at the **bottom-left**.
- `ShaderViewport` automatically flips the vertical axis: `(0, 0)` is at the bottom-left corner of the viewport, exactly matching Shadertoy's native convention.

### GLSL Usage Pattern

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Check if the user is currently pressing down:
    bool isPressed = iMouse.z > 0.0;

    // Normalized mouse position (0.0 to 1.0)
    vec2 mouseUv = iMouse.xy / iResolution.xy;

    // Draw a glowing circle around the cursor
    float dist = distance(uv, mouseUv);
    float circle = smoothstep(0.05, 0.04, dist);

    vec3 col = isPressed ? vec3(1.0, 0.2, 0.4) : vec3(0.2, 0.6, 1.0);
    fragColor = vec4(col * circle, 1.0);
}
```

---

## 3. Built-in On-Screen HUD Controls

When `showControls: true` is set, `ShaderViewport` overlays a modern floating control toolbar:

- **Play / Pause**: Toggles animation playback.
- **Rewind**: Resets time `t = 0.0s` and frame index to 0.
- **Step Forward**: Advances playback by a single frame.
- **Timecode & Frame**: Displays elapsed time (`mm:ss.ms`) and frame index.
- **FPS Counter**: Real-time performance monitor.
- **Resolution Scale**: Slider to scale offscreen render target resolution for performance tuning.
- **Fullscreen Toggle**: Invokes the `onToggleFullscreen` callback.

To build custom UI instead, set `showControls: false` and control playback via `ShaderController` directly.

---

## 4. Error Surfacing

When a shader fails to compile (e.g. syntax error or undefined variable in GLSL), `ShaderViewport` displays an error panel directly over the viewport:
- Highlights the problematic line number.
- Displays the compiler error message.
- Prevents app crashes while live-editing shader code.

---

## 5. Keyboard & Widget Interaction

`ShaderViewport` acts as an interactive bridge:
- If any pass in the project contains a `KeyboardChannel`, `ShaderViewport` requests focus and dispatches raw key events to `ShaderKeyboardState`.
- If any pass contains a `WidgetChannel`, pointer events (down, move, up, wheel, hover) are mapped from screen UVs into the child widget tree's coordinate space.
