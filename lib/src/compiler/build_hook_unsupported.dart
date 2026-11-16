/// Stub implementation for Web builds where `dart:io` and `package:hooks`
/// are unavailable.
Future<void> buildShaderFunBundles({
  required Object buildInput,
  required Object buildOutput,
}) => throw UnsupportedError(
  'buildShaderFunBundles is only supported on native host builds.',
);
