---
name: shader-fun-gpu-sound
version: 2
description: Real-time procedural and reactive GPU audio synthesis with PassType.sound and SoundPassEngine in shader_fun. Use when generating audio directly from GLSL (mainSound), connecting Buffer A state to Sound for event-driven collision/game SFX, creating algorithmic music on the GPU, or streaming raw PCM to SoLoud.
---

# shader_fun gpu sound

`shader_fun` supports Shadertoy's **Sound Pass** (`PassType.sound`), enabling complete real-time procedural audio synthesis directly on the GPU—for both standalone algorithmic music and **reactive, event-driven sound effects** driven by `Buffer A..D` state, inputs, or custom uniforms.

---

## 1. The `mainSound` GLSL Signature

In a Sound pass, the shader entrypoint is `mainSound`:

```glsl
vec2 mainSound( int samp, float time ) {
    // samp: integer sample index (0, 1, 2, ...)
    // time: playback time in seconds (samp / iSampleRate)
    // returns: vec2(left_channel, right_channel) in [-1.0 .. 1.0]

    // 440 Hz Sine wave (A4 note) with exponential decay every second:
    float wave = sin(6.2831853 * 440.0 * time) * exp(-3.0 * fract(time));

    return vec2(wave, wave); // Stereo output
}
```

- **Output**: `vec2` containing Left (`x`) and Right (`y`) channels.
- **Sample Range**: Normalized audio amplitudes between `-1.0` and `1.0`.
- **Sample Rate**: Exposed in `float iSampleRate` (typically `44100.0` Hz).

---

## 2. Static vs. Reactive GPU Audio Pipeline

`SoundPassEngine` automatically inspects the `Sound` pass via `SoundPassEngine.detectReactivePass(soundPass, commonCode: ...)` and selects the appropriate chunk size:

1. **Static Mode (large pre-buffered chunks)**:
   - Used when the `Sound` pass is purely a function of `samp` / `time` (no `iChannel0..3` channels bound/referenced and no custom uniforms).
   - Renders `256 x 256` offscreen chunks ($65,536$ stereo samples $\approx 1.486$ seconds at 44.1 kHz, 512 KB per chunk) ahead of the DAC.
2. **Reactive Mode (low-latency frame-synced chunks)**:
   - Enabled automatically whenever the `Sound` pass configures any channel (`iChannel0..3`), references `iChannel0..3` in GLSL (`Common` + `Sound`), or uses custom uniforms.
   - Renders `256 x 8` offscreen chunks ($2,048$ stereo samples $\approx 46.4$ ms at 44.1 kHz, 16 KB per chunk).
   - Triggered immediately after visual buffer/image rendering via `_soundPassEngine.onFrameRendered()`.
   - In reactive mode, `ShaderController` aligns visual `iTime` with `engine.currentBlockOffset` so event timestamps (`iTime`) written by `Buffer A..D` stay synchronized with the next `mainSound(samp, time)` audio block.
3. **SoLoud Streaming**:
   - Extracted 32-bit float stereo PCM chunks are pushed to `flutter_soloud` (`SoLoud.instance.setBufferStream` with `BufferingType.released`).

---

## 3. Event-Driven Reactive Sound (`Buffer A` → `Sound`)

For interactive simulations and games (see `example/shaders/colliding_balls.json` and `example/shaders/Bricks_Game.json`), store event timestamps in `Buffer A` and synthesize voices in `Sound`:

1. **Initialize timestamps negative on `iFrame == 0`** (e.g., `-10.0`) because offscreen buffers use floating-point RGBA formats (`r32g32b32a32Float` / `r16g16b16a16Float`). In `Sound`, ignore entries with `triggerTime < 0.0` so no sound fires at startup.
2. **Write `triggerTime = iTime`** (plus metadata such as impact speed or stereo pan) when a collision or event happens in `Buffer A`. Debounce re-triggers (`iTime - prevTime > 0.045`) to avoid rapid re-attack buzzing during multi-frame contacts.
3. **Bind `Buffer A` to `iChannel0` on the `Sound` pass** (using `ChannelFilter.nearest`) and read state texels with `texelFetch(iChannel0, ivec2(i, 1), 0)`.
4. **Apply click-free envelopes** over `dt = time - triggerTime` (`smoothstep` attack + tail fade-out before the max voice duration).

```glsl
// Sound pass sampling event state written by Buffer A:
// ev.x = lastHitTime (-10.0 initially), ev.y = impact, ev.z = stereoPan [-1..1]
vec2 mainSound(int samp, float time) {
    vec4 ev = texelFetch(iChannel0, ivec2(0, 1), 0);
    if (ev.x < 0.0) return vec2(0.0);

    float dt = time - ev.x;
    if (dt < 0.0 || dt >= 0.22) return vec2(0.0);

    float env = exp(-22.0 * dt)
              * smoothstep(0.0, 0.002, dt)
              * (1.0 - smoothstep(0.18, 0.22, dt));
    float tone = sin(6.2831853 * (380.0 + ev.y * 80.0) * dt);
    float pan = clamp(ev.z, -1.0, 1.0);
    vec2 gain = vec2(sqrt(0.5 * (1.0 - pan)), sqrt(0.5 * (1.0 + pan)));
    return gain * (tone * env * 0.25);
}
```

---

## 4. Creating a Sound Pass in Dart

```dart
final project = ShaderProject(name: 'GPU Synth');

// 1. Create Sound Pass (optionally bind Buffer A to iChannel0 for reactive SFX)
final soundPass = ShaderPass(
  type: PassType.sound,
  name: 'Sound',
  code: '''
vec2 mainSound(int samp, float time) {
    // Fast arpeggiator
    float note = floor(mod(time * 8.0, 4.0));
    float freq = 220.0 * pow(1.059463, note * 2.0);
    float wave = sin(6.2831853 * freq * time);
    return vec2(wave * 0.4);
}
''',
);

// 2. Create Image Pass (Visualizer)
final imagePass = ShaderPass(
  type: PassType.image,
  name: 'Image',
  code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0, 2, 4));
    fragColor = vec4(col, 1.0);
}
''',
);

project.passes.addAll([soundPass, imagePass]);

await controller.loadProject(project);
controller.play(); // Starts both visual rendering and audio synthesis
```

---

## 5. Playback Synchronization

The `SoundPassEngine` is coupled directly to `ShaderController`:
- **`controller.play()`**: Begins visual animation and launches or resumes the audio stream.
- **`controller.pause()`**: Pauses the audio stream immediately.
- **`controller.rewind()`**: Resets Frame 0 state and rewinds the audio stream back to $t = 0.0\text{s}$.
- **`controller.dispose()`**: Immediately stops audio synthesis and releases all native resources.

---

## 6. Practical GLSL Sound Recipes

### Stereo Panning
```glsl
vec2 mainSound(int samp, float time) {
    float pan = sin(time * 2.0); // Panning L <-> R
    float wave = sin(6.283185 * 330.0 * time);
    float left = wave * (0.5 - 0.5 * pan);
    float right = wave * (0.5 + 0.5 * pan);
    return vec2(left, right) * 0.3;
}
```

### 808 Kick Drum
```glsl
vec2 mainSound(int samp, float time) {
    float beatTime = fract(time * 2.0); // 120 BPM
    float pitch = 150.0 * exp(-20.0 * beatTime) + 40.0;
    float amp = exp(-4.0 * beatTime);
    float wave = sin(6.283185 * pitch * beatTime) * amp;
    return vec2(wave * 0.7);
}
```
