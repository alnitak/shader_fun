---
name: shader-fun-audio
version: 1
description: Audio-reactive shaders with SoLoudAudioChannel and MicAudioChannel in shader_fun. Use when building music visualizers, sampling FFT frequency spectrum or waveform textures in GLSL, or capturing live microphone input.
---

# shader_fun audio

`shader_fun` provides full support for Shadertoy-standard **512x2 audio textures**, allowing shaders to react to recorded music tracks or live microphone input in real time.

---

## 1. The Shadertoy Audio Texture Specification

An audio channel creates an offscreen GPU texture with dimensions **512 x 2**:

```
        0 (Bass) ───────────────────────────> 511 (Treble)
Row 0: [ FFT Frequency Spectrum (512 bins, 0.0 .. 1.0)     ] (y = 0.0 .. 0.5)
Row 1: [ Time-Domain Waveform   (512 samples, 0.0 .. 1.0)  ] (y = 0.5 .. 1.0)
```

- **Row 0 (FFT Spectrum)**: Represents frequency energy from bass (low $x$) to treble (high $x$). Values range from `0.0` (silence) to `1.0` (max power).
- **Row 1 (Waveform)**: Represents oscilloscope wave displacement. Centered at `0.5` during silence, ranging between `0.0` (negative peak) and `1.0` (positive peak).

---

## 2. Sampling Audio in GLSL

To sample without texture filtering artifacts between rows, sample near the center of each row:
- **Frequency Spectrum**: `y = 0.25`
- **Waveform**: `y = 0.75`

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // 1. Sample frequency spectrum across X axis:
    float fft = texture(iChannel0, vec2(uv.x, 0.25)).r;

    // 2. Sample waveform across X axis:
    float wave = texture(iChannel0, vec2(uv.x, 0.75)).r;

    // 3. Extract bass energy (low frequency bins near x = 0.05):
    float bass = texture(iChannel0, vec2(0.05, 0.25)).r;

    // Render frequency bar chart:
    vec3 col = vec3(0.0);
    if (uv.y < fft) {
        col = mix(vec3(0.1, 0.8, 0.3), vec3(1.0, 0.2, 0.1), uv.y);
    }

    // Overlay oscilloscope wave line:
    float waveLine = smoothstep(0.01, 0.0, abs(uv.y - wave));
    col += vec3(1.0, 1.0, 0.2) * waveLine;

    // Background bass pulse:
    col += vec3(bass * 0.2, 0.0, bass * 0.4);

    fragColor = vec4(col, 1.0);
}
```

---

## 3. Audio Channels in Dart

### A. Recorded Music / Sound Files (`SoLoudAudioChannel`)

Powered by `flutter_soloud`, this channel streams audio files, calculates FFT spectrums, and loops playback:

```dart
final pass = project.imagePass!;

// Supports Flutter assets, local files ('/path/to/song.mp3'), or URLs ('https://...')
pass.setChannel(0, SoLoudAudioChannel(
  src: 'assets/audio/electronic_track.mp3',
  audioName: 'Cyber Synth',
));

await controller.loadProject(project);
controller.play();
```

Transport controls for `SoLoudAudioChannel`:
```dart
final audioChannel = pass.getChannel(0) as SoLoudAudioChannel?;

await audioChannel?.pause();
await audioChannel?.resume();
await audioChannel?.seek(const Duration(seconds: 30));
```

### B. Live Microphone Input (`MicAudioChannel`)

Powered by `flutter_recorder`, this channel captures real-time microphone audio with zero-latency FFT and waveform analysis:

```dart
pass.setChannel(0, MicAudioChannel(
  micGain: 2.5, // Digital gain multiplier to boost quiet voice/music
));

await controller.loadProject(project);
controller.play();
```

> [!IMPORTANT]
> Ensure platform microphone permissions are configured in `Info.plist` (macOS/iOS) or `AndroidManifest.xml` (Android). Refer to the `shader-fun-setup` skill for setup instructions.

---

## 4. Audio-Reactive Best Practices

- **Bass Isolation**: Sample bins between `x = 0.01` and `x = 0.08` to drive pulse beats, kick drums, and camera shakes.
- **Mid-Range / Vocals**: Sample bins between `x = 0.2` and `x = 0.5` for melody tracking.
- **Treble / Hi-Hats**: Sample bins between `x = 0.7` and `x = 0.95` for sparkle, particle emissions, and high-frequency effects.
- **Waveform Centering**: Remember that silence is `0.5`, not `0.0`. To get signed displacement $[-1.0, 1.0]$, calculate: `(wave - 0.5) * 2.0`.
