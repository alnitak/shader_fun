import 'impeller_compiler.dart';

Future<CompileResult> runImpellerCompile({
  required String quadVertexShader,
  required String wrappedFragGlsl,
  String? customImpellercPath,
  String? rawUserGlsl,
  String? rawCommonGlsl,
}) async {
  return const CompileResult.error(
    'Runtime shader compilation is not supported on this platform. '
    'Please use pre-compiled shader bundles.',
  );
}

String? findImpellercBinary() => null;
