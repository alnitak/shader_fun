---
name: shader-fun-multipass
version: 1
description: Multi-pass rendering pipelines, ping-pong double buffering, persistent feedback loops, and common code sharing in shader_fun. Use when implementing fluid simulations, cellular automata, temporal blur, raymarching pipelines, or multi-buffer shaders.
---

# shader_fun multipass

`shader_fun` supports full Shadertoy-style multi-pass rendering pipelines consisting of **Common**, **Buffer A** through **Buffer D**, and the **Image** presentation pass.

---

## 1. The Multi-Pass Architecture

```
┌────────────────────────────────────────────────────────┐
│                   PassType.common                      │
│        Shared GLSL structs, constants, helpers         │
└───────────────────────────┬────────────────────────────┘
                            │ (Prepended automatically)
      ┌─────────────────────┼─────────────────────┐
      ▼                     ▼                     ▼
┌───────────┐         ┌───────────┐         ┌───────────┐
│ Buffer A  │ ──────> │ Buffer B  │ ──────> │   Image   │
│ (Offscreen│         │ (Offscreen│         │  (Screen  │
│ Ping-Pong)│         │ Ping-Pong)│         │  Output)  │
└─────┬─────┘         └───────────┘         └───────────┘
      │                      ▲
      └──────────────────────┘
```

1. **`PassType.common`**: Code defined here is prepended automatically to all passes before compiling. Put shared `#define`s, struct definitions, noise functions, and rotation matrices here.
2. **`PassType.bufferA` .. `PassType.bufferD`**: Offscreen render buffers rendered in alphabetical order each frame.
3. **`PassType.image`**: The final presentation pass rendered to the screen.

---

## 2. Ping-Pong Double Buffering (Feedback Loops)

Each buffer pass (`bufferA`..`D`) maintains two GPU texture attachments (front and back buffers). When a buffer references itself via `BufferChannel`:
- During frame $N$, the shader reads from texture $A$ (which contains frame $N-1$).
- The shader writes its output into texture $B$.
- At the end of the frame, the textures swap (ping-pong).

This enables persistent state across frames, essential for:
- Fluid dynamics and smoke simulations
- Particle systems and cellular automata (Game of Life)
- Temporal accumulation and motion blur
- Mouse-drawn canvas / paint tools

### Dart Configuration

```dart
final project = ShaderProject(name: 'Simulation');

// 1. Create Buffer A pass
final bufferA = ShaderPass(
  type: PassType.bufferA,
  name: 'Buffer A',
  code: bufferACode,
);

// 2. Connect Buffer A's previous frame output into its own iChannel0
bufferA.setChannel(0, BufferChannel(bufferIndex: 0)); // 0 = Buffer A

// 3. Create Image pass that displays Buffer A
final imagePass = ShaderPass(
  type: PassType.image,
  name: 'Image',
  code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);
}
''',
);
imagePass.setChannel(0, BufferChannel(bufferIndex: 0));

project.passes.addAll([bufferA, imagePass]);
await controller.loadProject(project);
```

---

## 3. Frame 0 State Initialization in GLSL

In ping-pong simulations, frame 0 is used to populate initial conditions:

```glsl
// Buffer A GLSL code
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Initialization on frame 0 or upon rewind:
    if (iFrame == 0) {
        // Initial state: random seed or black background
        float seed = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
        fragColor = vec4(vec3(step(0.85, seed)), 1.0);
        return;
    }

    // Read previous frame state from iChannel0:
    vec4 prevState = texture(iChannel0, uv);

    // Fade over time (trail effect):
    vec4 newState = prevState * 0.98;

    // Draw with mouse if dragging:
    if (iMouse.z > 0.0) {
        vec2 mouseUv = iMouse.xy / iResolution.xy;
        if (distance(uv, mouseUv) < 0.02) {
            newState = vec4(1.0, 0.4, 0.2, 1.0);
        }
    }

    fragColor = newState;
}
```

---

## 4. Multi-Stage Pipeline Example

Piping Buffer A into Buffer B, and Buffer B into Image:

```dart
// Buffer A: Computes raymarched depth
final passA = ShaderPass(type: PassType.bufferA, name: 'Depth', code: passACode);

// Buffer B: Reads Buffer A (iChannel0) to compute screen-space ambient occlusion (SSAO)
final passB = ShaderPass(type: PassType.bufferB, name: 'SSAO', code: passBCode);
passB.setChannel(0, BufferChannel(bufferIndex: 0)); // Reads Buffer A

// Image: Combines Buffer A (depth) and Buffer B (SSAO) to render final lit scene
final imagePass = ShaderPass(type: PassType.image, name: 'Image', code: imageCode);
imagePass.setChannel(0, BufferChannel(bufferIndex: 0)); // iChannel0 = Buffer A
imagePass.setChannel(1, BufferChannel(bufferIndex: 1)); // iChannel1 = Buffer B
```

---

## 5. Pass Resolution & Scaling

By default, buffer passes match the controller's main viewport resolution (`iResolution`). When the viewport resizes, all offscreen ping-pong buffers resize automatically, preserving aspect ratios and pixel alignment across all passes.
