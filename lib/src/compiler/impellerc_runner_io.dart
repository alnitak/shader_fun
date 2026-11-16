import 'dart:convert';
import 'dart:io';

import 'shader_compiler_core.dart';

/// Locates the `impellerc` offline compiler binary from environment variables,
/// the running Dart SDK's enclosing Flutter SDK, system `PATH`, or common install paths.
String? findImpellercBinary() {
  // 1. Check FLUTTER_ROOT environment variable
  try {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final candidate = _findInFlutterRoot(flutterRoot);
      if (candidate != null) return candidate;
    }
  } catch (_) {}

  // 2. Check if the running Dart executable lives inside a Flutter SDK cache
  //    (e.g. `<flutter_root>/bin/cache/dart-sdk/bin/dart` during build hooks).
  try {
    var dir = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 6; i++) {
      final candidate = _findInFlutterRoot(dir.path);
      if (candidate != null) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  } catch (_) {}

  // 3. Check system PATH via 'which' or 'where'
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

  // 4. Fallback common developer directories on macOS / Linux / Windows
  final home = Platform.environment['HOME'];
  final commonPaths = [
    '/Volumes/NVME/dev/flutter',
    if (home != null) '$home/development/flutter',
    if (home != null) '$home/flutter',
  ];

  for (final dir in commonPaths) {
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
  const hostArchs = [
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

  // Fallback recursive search in artifacts/engine
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

/// Invokes `impellerc` in a temporary directory to compile [quadVertexShader]
/// and [wrappedFragGlsl] into a multi-backend `.shaderbundle` FlatBuffer.
Future<CompileResult> invokeImpellercProcess({
  required String quadVertexShader,
  required String wrappedFragGlsl,
  String? customImpellercPath,
  String? targetOsOverride,
}) async {
  final impellerc = customImpellercPath ?? findImpellercBinary();
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
    if (targetOsOverride != null) {
      if (targetOsOverride == 'macos') {
        platformFlag = '--metal-desktop';
      } else if (targetOsOverride == 'ios') {
        platformFlag = '--metal-ios';
      } else {
        platformFlag = '--vulkan';
      }
    } else if (Platform.isMacOS) {
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

      return CompileResult.error(
        ImpellerCompilerCore.cleanCompilerError(rawMsg),
      );
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
