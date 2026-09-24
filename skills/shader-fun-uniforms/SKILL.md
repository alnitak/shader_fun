---
name: shader-fun-uniforms
version: 1
description: Declaring and updating custom GLSL uniforms with zero recompilation overhead in shader_fun. Use when animating parameters at 60/120 FPS, linking Flutter sliders/gestures/colors to shaders, or expanding GPU uniform buffer capacity.
---

# shader_fun uniforms

`shader_fun` allows declaring arbitrary custom GLSL uniforms in shader code and updating their values dynamically from Dart with **zero recompilation overhead**. Updates write directly to GPU Uniform Buffer Objects (UBOs) in the render loop at 60 or 120 FPS.

---

## 1. Declaring Uniforms in GLSL

Declare uniforms at the top of your shader pass (`image` or `bufferA..D`) using standard GLSL syntax:

```glsl
// Custom parameters controllable from Flutter
uniform float progress;      // 0.0 to 1.0 transition slider
uniform vec2 focusPoint;     // Interaction center in UV space
uniform vec4 glowColor;      // Highlight tint (RGBA normalized 0.0..1.0)
uniform float intensity;     // Wave or distortion magnitude

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float dist = distance(uv, focusPoint);
    float mask = smoothstep(progress, progress - 0.1, dist);

    vec3 baseColor = vec3(0.1, 0.1, 0.15);
    vec3 result = mix(baseColor, glowColor.rgb * intensity, mask);

    fragColor = vec4(result, 1.0);
}
```

---

## 2. Setting Uniforms in Dart

Use `controller.setUniform(name, value)`:

```dart
// 1. Scalar floats and ints (double or int)
controller.setUniform('progress', animationController.value);
controller.setUniform('intensity', 2.5);

// 2. 2D vectors (Offset or Size)
controller.setUniform('focusPoint', const Offset(0.5, 0.5));
controller.setUniform('viewportScale', const Size(1920, 1080));

// 3. 4D color vectors (Color) -> maps to normalized vec4(r, g, b, a)
controller.setUniform('glowColor', Colors.cyanAccent);

// 4. Raw numerical lists (List<num>)
controller.setUniform('customVec3', [1.0, 0.5, 0.2]); // vec3
controller.setUniform('customVec4', [1.0, 0.0, 0.0, 1.0]); // vec4
```

### Auto-Repaint Behavior
If shader playback is paused (`isPlaying == false`), calling `controller.setUniform(...)` automatically calls `renderSingleFrame()`. The updated uniform value is rendered immediately to the screen without requiring the user to resume playback.

---

## 3. Reading Uniform Values

```dart
// Read a single uniform value:
final Object? progress = controller.getUniform('progress');

// Inspect all current custom uniforms:
final Map<String, Object> allUniforms = controller.customUniforms;
print(allUniforms); // {'progress': 0.75, 'glowColor': Color(0xff18ffff)}
```

---

## 4. Flutter Widget / Slider Integration

Connect Flutter inputs (e.g. `Slider`, `GestureDetector`) directly to shader uniforms:

```dart
class InteractiveSliderOverlay extends StatelessWidget {
  const InteractiveSliderOverlay({super.key, required this.controller});

  final ShaderController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Slider(
        value: (controller.getUniform('progress') as double?) ?? 0.5,
        min: 0.0,
        max: 1.0,
        onChanged: (val) {
          controller.setUniform('progress', val);
        },
      ),
    );
  }
}
```

---

## 5. Memory Pagination & Capacity Scaling

### Default Capacity
By default, `CommonUniforms.maxCustomUniformSlots = 16` generic `vec4` registers are allocated. Each slot holds 4 32-bit floats (16 bytes), totaling **256 bytes** of custom uniform data.

### Hardware Alignment & Pagination
Sizing custom uniform storage to 256 bytes aligns with standard GPU driver suballocation pagination (for example, `minUniformBufferOffsetAlignment` on Vulkan and Metal is typically 256 bytes). Allocating anything in a UBO consumes a 256-byte or 4-KB physical page in GPU VRAM.

### Scaling Capacity
If your shader needs more custom uniforms (e.g. 30 distinct uniforms), update the slot count once before initializing shaders:

```dart
// Expand from default 16 slots (256 B) to 32 slots (512 B):
CommonUniforms.maxCustomUniformSlots = 32;
```

All GLSL layout wrappers, native Impeller uniform buffers, WebGL structures, and memory offsets scale together automatically across all platforms without any other code changes.
