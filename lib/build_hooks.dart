/// Build-hook helpers for `shader_fun`.
///
/// Call [buildShaderFunBundles] from your app's `hook/build.dart` so shaders
/// are pre-compiled on the host via `impellerc` when targeting mobile (`ios`
/// or `android`), where `impellerc` cannot run at runtime on-device.
library;

export 'src/compiler/build_hook.dart'
    if (dart.library.js_interop) 'src/compiler/build_hook_unsupported.dart'
    show buildShaderFunBundles;
