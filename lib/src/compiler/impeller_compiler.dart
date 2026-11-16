import '../core/shader_types.dart';
import 'compile_process.dart';
import 'shader_compiler_core.dart';

export 'shader_compiler_core.dart'
    show CompileResult, CustomUniformDeclaration;

/// Compiler service that wraps shader GLSL code into modern Vulkan GLSL 4.60,
/// generates full-screen quad vertex shader geometry, and invokes `impellerc`
/// to produce Flutter GPU `.shaderbundle` binaries or extract compilation errors.
class ImpellerCompiler {
  /// Locates the `impellerc` offline compiler binary from system PATH or Flutter SDK cache.
  static String? findImpellerc() => findImpellercBinary();

  /// The full-screen quad vertex shader source.
  static const String quadVertexShader = ImpellerCompilerCore.quadVertexShader;

  /// Returns true if [code] references any FrameInfo uniform member outside of
  /// comments and the uniform block declaration itself.
  static bool shaderUsesFrameInfo(String code) =>
      ImpellerCompilerCore.shaderUsesFrameInfo(code);

  /// Returns true if [code] references `iChannel$channelIndex` outside of comments.
  static bool shaderUsesChannel(String code, int channelIndex) =>
      ImpellerCompilerCore.shaderUsesChannel(code, channelIndex);

  /// Extracts user-declared custom uniforms from GLSL code.
  /// Looks for top-level `uniform <type> <name>;` lines where type is
  /// `float`, `int`, `vec2`, `vec3`, or `vec4`.
  static List<CustomUniformDeclaration> extractCustomUniforms(
    String glsl, {
    Map<String, int>? existingSlots,
  }) => ImpellerCompilerCore.extractCustomUniforms(
    glsl,
    existingSlots: existingSlots,
  );

  /// Wraps user shader GLSL with Vulkan GLSL 4.60 headers, uniform buffers,
  /// optional samplers, macros, and standard main() entry point.
  /// If [commonGlsl] is provided, it is prepended so shared functions/structs
  /// are accessible to the pass.
  /// Uses `#line 1` so compiler error lines match the user's source lines.
  static String wrapShaderGlsl(
    String userGlsl, {
    String? commonGlsl,
    Map<String, int>? customUniformSlots,
  }) => ImpellerCompilerCore.wrapShaderGlsl(
    userGlsl,
    commonGlsl: commonGlsl,
    customUniformSlots: customUniformSlots,
  );

  /// Wraps user sound shader GLSL with Vulkan GLSL 4.60 headers, uniform buffers,
  /// optional samplers, macros, and standard main() entry point for PassType.sound.
  static String wrapSoundShaderGlsl(
    String userGlsl, {
    String? commonGlsl,
    Map<String, int>? customUniformSlots,
    int textureWidth = 256,
  }) => ImpellerCompilerCore.wrapSoundShaderGlsl(
    userGlsl,
    commonGlsl: commonGlsl,
    customUniformSlots: customUniformSlots,
    textureWidth: textureWidth,
  );

  /// Prepares the final vertex and fragment GLSL strings for compilation.
  static ({String vertexGlsl, String fragmentGlsl}) prepareShaderSources({
    required String shaderGlsl,
    String? vertexGlsl,
    String? commonGlsl,
    Map<String, int>? customUniformSlots,
    PassType passType = PassType.image,
    ShaderPassMode mode = ShaderPassMode.shaderToy,
  }) => ImpellerCompilerCore.prepareShaderSources(
    shaderGlsl: shaderGlsl,
    vertexGlsl: vertexGlsl,
    commonGlsl: commonGlsl,
    customUniformSlots: customUniformSlots,
    passType: passType,
    mode: mode,
  );

  /// Computes a deterministic 16-hex-character hash for a prepared (vertex, fragment) GLSL pair.
  static String computeBundleHash({
    required String vertexGlsl,
    required String fragmentGlsl,
  }) => ImpellerCompilerCore.computeBundleHash(
    vertexGlsl: vertexGlsl,
    fragmentGlsl: fragmentGlsl,
  );

  /// Asset key under `flutter_scene_generated/` for a pre-compiled shader bundle.
  static String bundleAssetKeyForHash(String hash) =>
      ImpellerCompilerCore.bundleAssetKeyForHash(hash);

  /// Compiles a shader GLSL code string using `impellerc`.
  /// If [commonGlsl] is specified, it is injected before [shaderGlsl].
  /// Returns [CompileResult.success] with the compiled `.shaderbundle` bytes,
  /// or [CompileResult.error] with the exact compiler diagnostics from `stderr`.
  static Future<CompileResult> compile({
    required String shaderGlsl,
    String? vertexGlsl,
    String? commonGlsl,
    String? customImpellercPath,
    Map<String, int>? customUniformSlots,
    PassType passType = PassType.image,
    ShaderPassMode mode = ShaderPassMode.shaderToy,
  }) {
    final prepared = prepareShaderSources(
      shaderGlsl: shaderGlsl,
      vertexGlsl: vertexGlsl,
      commonGlsl: commonGlsl,
      customUniformSlots: customUniformSlots,
      passType: passType,
      mode: mode,
    );
    return runImpellerCompile(
      quadVertexShader: prepared.vertexGlsl,
      wrappedFragGlsl: prepared.fragmentGlsl,
      customImpellercPath: customImpellercPath,
      rawUserGlsl: shaderGlsl,
      rawCommonGlsl: commonGlsl,
      customUniformSlots: customUniformSlots,
      passType: passType,
      mode: mode,
    );
  }

  /// Cleans and formats raw impellerc stderr for human-friendly UI display.
  static String cleanCompilerError(String raw) =>
      ImpellerCompilerCore.cleanCompilerError(raw);
}
