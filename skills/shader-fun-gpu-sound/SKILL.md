---
name: shader-fun-gpu-sound
version: 1
description: Real-time procedural GPU audio synthesis with PassType.sound and SoundPassEngine in shader_fun. Use when generating audio directly from GLSL (mainSound), creating algorithmic music or sound effects on the GPU, or streaming raw PCM to SoLoud.
---

# shader_fun gpu sound

`shader_fun` supports Shadertoy's **Sound Pass** (`PassType.sound`), enabling complete real-time procedural audio synthesis directly on the GPU. Instead of playing back audio files, the GPU computes audio waveforms algorithmically in GLSL and streams them continuously to the speakers.

---

## 1. The `mainSound` GLSL Signature

In a Sound pass, the shader entrypoint is `mainSound`:

```glsl
vec2 mainSound( int samp, float time ) {
    // samp: integer sample index (0, 1, 2, ...)
    // time: playback time in seconds (samp / iSampleRate)
    // returns: vec2(left_channel, right_channel) in range [-1.0 .. 1.0]

    // 440 Hz Sine wave (A4 note) with exponential decay every second:
    float wave = sin(6.2831853 * 440.0 * time) * exp(-3.0 * fract(time));

    return vec2(wave, wave); // Stereo output
}
```

- **Output**: `vec2` containing Left (`x`) and Right (`y`) channels.
- **Sample Range**: Normalized audio amplitudes between `-1.0` and `1.0`.
- **Sample Rate**: Exposed in the uniform `float iSampleRate` (typically 44100.0 Hz).

---

## 2. How the GPU Audio Pipeline Works

1. **256x256 Render Chunks**: The `SoundPassEngine` invokes the GPU to render a 256x256 offscreen texture chunk. Each pixel computes one stereo sample ($256 \times 256 = 65,536$ audio samples $\approx 1.486$ seconds at 44.1 kHz).
2. **Float PCM Extraction**: The GPU converts the texture pixels to stereo 32-bit floating-point PCM bytes (512 KB per chunk).
3. **Low-Latency Streaming**: The PCM bytes are pushed into a `flutter_soloud` buffer stream (`SoLoud.instance.setBufferStream` with `BufferingType.released`).
4. **Autonomous Jitter Buffer**: A background maintenance timer monitors buffer depth and pre-renders chunks ahead of the DAC, guaranteeing seamless, glitch-free audio playback.

---

## 3. Creating a Sound Pass in Dart

```dart
final project = ShaderProject(name: 'GPU Synth');

// 1. Create Sound Pass
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

## 4. Playback Synchronization

The `SoundPassEngine` is coupled directly to `ShaderController`:
- **`controller.play()`**: Begins visual animation and launches the audio stream.
- **`controller.pause()`**: Pauses the audio stream immediately.
- **`controller.rewind()`**: Resets the audio stream back to $t = 0.0\text{s}$ and pre-buffers chunk 0.
- **`controller.dispose()`**: Immediately stops audio synthesis and releases all native resources.

---

## 5. Practical GLSL Sound Recipes

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
