## 1.0.3 (unreleased)
- update dependencies and improve GPU resource management for the new 0.24.5 flutter_scene

## 1.0.2
- feat: added mobile build hook (`package:shader_fun/build_hooks.dart`) to pre-compile `.shaderbundle` assets via `impellerc` on iOS and Android builds and load them at runtime without requiring `impellerc` on device
- feat: made the studio example code editor read-only on mobile and added a full-screen mobile shader viewer example (`example/lib/studio_example/main_mobile.dart`)
- updated Android Gradle Plugin, Kotlin, and Gradle versions in the example app

## 1.0.0
- feat: added reactive GPU Sound pass support (`SoundPassEngine.detectReactivePass`) with low-latency `256x8` frame-synced chunks aligned to `iTime` / `currentBlockOffset`
- feat: added `example/shaders/colliding_balls.json` multi-pass 2D elastic collision physics and reactive stereo GPU collision sound example
- fix: fixed initial `Buffer A` Frame 0 rendering, ping-pong buffer zero-initialization, single-pass pipeline assignment, SoLoud stream play order, Web `samp` rounding, and native `ui.Image` disposal in audio readback
- chore: updated dependencies of `flutter_soloud` and `flutter_recorder`

## 0.2.2
- feat: added math sound shaders
- update flutter_scene to 0.24.3 and fixed WebGL texture casting
- updated flutter_soloud dep

## 0.2.1
- fix: regression of float32 render target support

## 0.2.0
- added custom shader pass to use vertex and fragment shaders
- added `lib/custom_shader` examples
- added SoundPassEngine for real-time GPU procedural audio synthesis
- added 3 GPU sound examples

## 0.1.0
- Initial release!
