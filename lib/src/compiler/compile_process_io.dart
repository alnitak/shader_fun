import 'dart:convert';
import 'dart:io';

import '../core/shader_pass.dart';
import 'impeller_compiler.dart';

String? findImpellercBinary() {
  // 1. Check environment variables
  try {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final candidate = _findInFlutterRoot(flutterRoot);
      if (candidate != null) return candidate;
    }
  } catch (_) {}

  // 2. Check system PATH via 'which' or 'where'
  try {
    final whichCmd = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(whichCmd, ['flutter']);
    if (result.exitCode == 0) {
      final flutterPath = result.stdout.toString().trim().split('\n').first;
      final flutterDir = File(flutterPath).parent.parent.path;
      final candidate = _findInFlutterRoot(flutterDir);
      if (candidate != null) return candidate;
    }
  } catch (_) {}

  // 3. Fallback common developer directories on macOS / Linux / Windows
  final commonPaths = [
    '/Volumes/NVME/dev/flutter',
    Platform.environment['HOME'] != null
        ? '${Platform.environment['HOME']}/development/flutter'
        : null,
    Platform.environment['HOME'] != null
        ? '${Platform.environment['HOME']}/flutter'
        : null,
  ];

  for (final dir in commonPaths) {
    if (dir == null) continue;
    try {
      if (Directory(dir).existsSync()) {
        final candidate = _findInFlutterRoot(dir);
        if (candidate != null) return candidate;
      }
    } catch (_) {}
  }

  return null;
}

String? _findInFlutterRoot(String flutterRoot) {
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
  final hostArchs = [
    'darwin-arm64',
    'darwin-x64',
    'windows-x64',
    'linux-x64',
    'linux-arm64',
  ];

  for (final arch in hostArchs) {
    final directPath = '$flutterRoot/bin/cache/artifacts/engine/$arch/$exeName';
    try {
      if (File(directPath).existsSync()) {
        return directPath;
      }
    } catch (_) {}
  }

  // Fallback search
  try {
    final artifactsDir = Directory('$flutterRoot/bin/cache/artifacts/engine');
    if (artifactsDir.existsSync()) {
      for (final entity in artifactsDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith(exeName)) {
          return entity.path;
        }
      }
    }
  } catch (_) {}

  return null;
}

Future<CompileResult> runImpellerCompile({
  required String quadVertexShader,
  required String wrappedFragGlsl,
  String? customImpellercPath,
  String? rawUserGlsl,
  String? rawCommonGlsl,
  Map<String, int>? customUniformSlots,
  PassType passType = PassType.image,
}) async {
  final impellerc = customImpellercPath ?? ImpellerCompiler.findImpellerc();
  if (impellerc == null) {
    return const CompileResult.error(
      'Could not locate "impellerc" compiler binary in Flutter SDK. '
      'Please ensure Flutter is installed and on PATH.',
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('shader_compile_');
  try {
    final vertFile = File('${tempDir.path}/quad.vert');
    final fragFile = File('${tempDir.path}/shader.frag');
    final bundleFile = File('${tempDir.path}/output.shaderbundle');

    await vertFile.writeAsString(quadVertexShader);
    await fragFile.writeAsString(wrappedFragGlsl);

    final manifestJson = json.encode({
      'QuadVertex': {'type': 'vertex', 'file': vertFile.path},
      'ShaderFragment': {'type': 'fragment', 'file': fragFile.path},
    });

    final String platformFlag;
    if (Platform.isMacOS) {
      platformFlag = '--metal-desktop';
    } else if (Platform.isIOS) {
      platformFlag = '--metal-ios';
    } else {
      platformFlag = '--vulkan';
    }

    final result = await Process.run(impellerc, [
      platformFlag,
      '--gles-language-version=300',
      '--shader-bundle=$manifestJson',
      '--sl=${bundleFile.path}',
      '--verbose',
    ], workingDirectory: tempDir.path);

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      final rawMsg = stderr.isNotEmpty ? stderr : stdout;

      return CompileResult.error(ImpellerCompiler.cleanCompilerError(rawMsg));
    }

    if (!await bundleFile.exists()) {
      return const CompileResult.error(
        'impellerc succeeded but output.shaderbundle was not produced.',
      );
    }

    final bytes = await bundleFile.readAsBytes();
    return CompileResult.success(bytes);
  } catch (e) {
    return CompileResult.error('Compilation exception: $e');
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
