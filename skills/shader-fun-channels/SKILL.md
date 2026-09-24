---
name: shader-fun-channels
version: 1
description: Configuring input channels (iChannel0..3) in shader_fun — 2D textures, buffer feeds, keyboard state, and live interactive Flutter widgets (WidgetChannel). Use when binding image textures, sampling keyboard keys in GLSL, or embedding interactive Flutter widgets into shaders.
---

# shader_fun channels

Each `ShaderPass` in `shader_fun` supports up to 4 input channels (`channels[0]` through `channels[3]`), exposed in GLSL as `sampler2D iChannel0` through `sampler2D iChannel3`.

---

## 1. Texture Configuration: Filter, Wrap, and VFlip

All channels share common sampler properties:
- `filter`: `ChannelFilter.linear` (bilinear filtering), `ChannelFilter.nearest` (pixelated/retro), or `ChannelFilter.mipmap` (trilinear filtering with mipmaps).
- `wrap`: `ChannelWrap.repeat` (tiled wrapping) or `ChannelWrap.clamp` (clamped to border).
- `vflip`: `bool` (whether to vertically invert texture coordinates to match GLSL conventions).

---

## 2. Channel Types

### 1. `TextureChannel` (2D Images)
Loads PNG, JPEG, or raw byte buffers:

```dart
pass.setChannel(0, TextureChannel(
  src: 'assets/textures/rock_diffuse.png', // Asset, local file, or URL
  filter: ChannelFilter.mipmap,
  wrap: ChannelWrap.repeat,
  vflip: true,
));
```

- **Un-premultiplied raw RGBA**: `TextureChannel` decodes images without premultiplying alpha, ensuring math, noise, normal maps, and signed-distance-field (SDF) textures maintain exact 8-bit values across all four RGBA channels.

### 2. `BufferChannel` (Multi-Pass Feeds)
Connects the output of an offscreen buffer pass (`PassType.bufferA`..`D`):

```dart
// 0 = Buffer A, 1 = Buffer B, 2 = Buffer C, 3 = Buffer D
pass.setChannel(1, BufferChannel(
  bufferIndex: 0, // Reads Buffer A
  filter: ChannelFilter.linear,
  wrap: ChannelWrap.clamp,
));
```

### 3. `KeyboardChannel` (Interactive Key State)
Provides a 256x3 texture tracking 256 ASCII key states:
- **Row 0** (`y = 0`): Key down state (`1.0` if key is currently pressed, `0.0` otherwise).
- **Row 1** (`y = 1`): Key click pulse (`1.0` on the single frame when pressed).
- **Row 2** (`y = 2`): Key toggle state (`1.0` / `0.0` toggled on each press).

```dart
pass.setChannel(2, KeyboardChannel());
```

Sampling in GLSL:

```glsl
// Standard ASCII key codes
const int KEY_SPACE = 32;
const int KEY_LEFT  = 37;
const int KEY_UP    = 38;
const int KEY_RIGHT = 39;
const int KEY_DOWN  = 40;
const int KEY_W     = 87;
const int KEY_A     = 65;
const int KEY_S     = 83;
const int KEY_D     = 68;

bool isKeyDown(int key) {
    return texelFetch(iChannel2, ivec2(key, 0), 0).r > 0.5;
}

bool isKeyToggled(int key) {
    return texelFetch(iChannel2, ivec2(key, 2), 0).r > 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 col = vec3(0.1);
    if (isKeyDown(KEY_SPACE)) {
        col = vec3(1.0, 1.0, 0.0); // Yellow when space is held
    }
    fragColor = vec4(col, 1.0);
}
```

---

## 3. `WidgetChannel` (Live Interactive Flutter Widgets)

`WidgetChannel` rasterizes an arbitrary Flutter `Widget` subtree into a live GPU texture (`sampler2D`) every frame with zero latency. Pointer events (taps, drags, mouse wheel, keyboard input into `TextField`s) are forwarded directly into the child widget tree.

### Mode A: Automatic Placement (`autoRender = true`)
The widget is positioned in a sub-rectangle of the viewport defined by normalized horizontal and vertical percentiles:

```dart
pass.setChannel(0, WidgetChannel(
  width: 500,
  height: 380,
  pixelRatio: 2.0, // Crisp rendering on HiDPI displays
  autoRender: true,
  horizontalPercentile: const (0.1, 0.9), // Centered with 10% side margins
  verticalPercentile: const (0.05, 0.95),
  interactive: true,
  child: const MyFlutterFormWidget(),
));
```

### Mode B: Custom / Freeform Mode (`autoRender = false`)
The shader controls sampling coordinates completely (e.g. liquid refraction, CRT barrel distortion, magnifying glass, page curl). 

Use `uvTransform` so pointer events land on the correct interactive elements:

```dart
pass.setChannel(0, WidgetChannel(
  width: 800,
  height: 600,
  autoRender: false,
  interactive: true,
  // If the shader renders the widget scaled down at half size:
  // GLSL: vec2 widgetUv = (uv - vec2(0.25)) * 2.0;
  // Dart uvTransform mirrors this transformation:
  uvTransform: (viewportUv) => (viewportUv - const Offset(0.25, 0.25)) * 2.0,
  child: const InteractiveDashboard(),
));
```

### Sampling `WidgetChannel` in GLSL

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Apply ripple distortion to the live Flutter UI
    vec2 offset = vec2(sin(uv.y * 20.0 + iTime * 3.0)) * 0.01;
    vec4 widgetColor = texture(iChannel0, uv + offset);

    fragColor = widgetColor;
}
```
