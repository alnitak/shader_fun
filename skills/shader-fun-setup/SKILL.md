---
name: shader-fun-setup
version: 1
description: Setup, dependencies, platform permissions, and web configuration for shader_fun. Use when adding shader_fun to a project, configuring microphone permissions, setting up WebGL2/WASM web builds, or troubleshooting platform graphics requirements.
---

# shader_fun setup

This guide covers installing `shader_fun`, configuring required platform permissions for audio/microphone channels, and setting up web support for WebGL2 and WebAssembly.

---

## 1. Installation

Add `shader_fun` to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  shader_fun: ^0.1.0
```

Run:
```bash
flutter pub get
```

---

## 2. Mobile Setup (iOS & Android Build Hook)

Mobile targets (iOS and Android) cannot invoke Flutter's `impellerc` compiler binary at runtime on-device. Instead, `shader_fun` provides a build hook (`package:shader_fun/build_hooks.dart`) that runs **only on mobile builds (`ios` and `android`)** to pre-compile shaders into `.shaderbundle` assets on your host machine during `flutter build` / `flutter run`. On desktop and web, the hook is a no-op.

1. Add `hooks` to your app's `dev_dependencies` and declare the generated directory under `flutter: assets:` in `pubspec.yaml`:

```yaml
dev_dependencies:
  hooks: ^2.0.0

flutter:
  assets:
    - flutter_scene_generated/
```

2. Create `hook/build.dart` in your app package:

```dart
import 'package:hooks/hooks.dart';
import 'package:shader_fun/build_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderFunBundles(buildInput: input, buildOutput: output);
  });
}
```

During mobile builds, `buildShaderFunBundles` scans `shaders/`, `assets/`, default starter passes, and inline shaders in `lib/**/*.dart` and compiles them into `flutter_scene_generated/sf_<hash>.shaderbundle`, which `shader_fun` loads automatically from `rootBundle` at runtime on iOS and Android.

---

## 3. Web Configuration

On the web platform, `shader_fun` relies on WebGL2 and WebAssembly. If you use audio playback (`SoLoudAudioChannel`), live microphone capture (`MicAudioChannel`), or procedural sound (`PassType.sound`), you must include the companion JS loaders in `web/index.html`.

### `web/index.html` Loader Scripts

Add these script tags immediately before `flutter_bootstrap.js`:

```html
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <title>Shader Fun App</title>
</head>
<body>
  <!-- Helper loaders for flutter_soloud and flutter_recorder WebAssembly modules -->
  <script src="assets/packages/flutter_soloud/web/init_soloud.js" defer></script>
  <script src="assets/packages/flutter_recorder/web/init_recorder_module.dart.js" defer></script>

  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
```

### Cross-Origin Isolation Headers (Web)

For multi-threaded WebAssembly audio processing (e.g. real-time FFT frequency transforms and continuous buffer streams), web servers must return Cross-Origin Opener Policy (COOP) and Cross-Origin Embedder Policy (COEP) headers:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

When testing locally with `flutter run -d chrome`, Flutter dev tools handles local server headers automatically. For production deployments (e.g. Firebase Hosting or GitHub Pages), ensure your hosting config or CDN provides these HTTP response headers.

---

## 4. Platform Microphone Permissions

If your shaders utilize live microphone input (`MicAudioChannel` / `MicChannel`) to drive audio-reactive visuals, configure microphone access permissions for each platform:

### macOS

1. Add `NSMicrophoneUsageDescription` to `macos/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to visualize live audio in shaders.</string>
```

2. Enable the audio input entitlement in both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### iOS

Add `NSMicrophoneUsageDescription` to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to visualize live audio in shaders.</string>
```

### Android

Add `RECORD_AUDIO` to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## 5. Graphics & GPU Requirements

`shader_fun` compiles shaders on desktop via `impellerc`, pre-compiles `.shaderbundle` assets at build time via `hook/build.dart` on mobile (`ios` / `android`), and compiles GLSL ES 3.00 in-browser via WebGL2 on web:

| Platform | Rendering Backend | Notes |
|---|---|---|
| **macOS** | Metal | Impeller enabled by default. |
| **iOS** | Metal | Requires iOS 12+ (Metal supported device). |
| **Android** | Vulkan (fallback to OpenGLES 3) | Impeller Vulkan backend supported on Android 10+ (API 29+). |
| **Linux** | Vulkan | Requires a Vulkan 1.1+ capable GPU driver. |
| **Windows** | Vulkan | Requires a Vulkan 1.1+ capable GPU driver. |
| **Web** | WebGL 2.0 | Works in all modern browsers (Chrome, Edge, Firefox, Safari 15+). |

---

## 6. Verification Checklist

Before running your first shader:
1. `flutter pub get` completed without version conflicts.
2. If targeting iOS or Android, `hook/build.dart` calls `buildShaderFunBundles` and `pubspec.yaml` lists `flutter_scene_generated/` under `flutter: assets:`.
3. If using microphone input, `Info.plist` / `AndroidManifest.xml` has permission entries.
4. If building for web, `init_soloud.js` and `init_recorder_module.dart.js` are linked in `web/index.html`.
5. Test with a minimal shader in `ShaderViewport` to verify GPU quad rendering.
