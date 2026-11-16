import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';

import '../core/shader_types.dart';
import 'impellerc_runner_io.dart';
import 'shader_compiler_core.dart';

const String _defaultEmptyImageCode = '''void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord/iResolution.xy;

    // Time varying pixel color
    vec3 col = 0.5 + 0.5*cos(iTime+uv.xyx+vec3(0,2,4));

    // Output to screen
    fragColor = vec4(col,1.0);
}
''';

const String _defaultCommonCode = '''// Common code shared across all passes
// Place shared constants, structs, and helper functions here.

#define PI 3.14159265359

vec2 rot(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c) * p;
}
''';

const String _defaultBufferCode = '''void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
''';

const String _defaultSoundCode = '''// Sound Pass - Audio synthesis in stereo [-1.0 .. 1.0]
vec2 mainSound( int samp, float time ) {
    // 440 Hz Sine wave (A4) with exponential decay
    return vec2( sin(6.283185 * 440.0 * time) * exp(-3.0 * fract(time)) );
}
''';

/// Build hook entry point for `shader_fun` and consumer applications.
///
/// Only pre-compiles `.shaderbundle` assets when building for mobile (`ios` or
/// `android`), because desktop platforms compile GLSL on demand via `impellerc`
/// and Web compiles GLSL ES 3.00 in the browser via WebGL2.
Future<void> buildShaderFunBundles({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) async {
  final extensions = buildInput.config.json['extensions'];
  final codeAssets = extensions is Map ? extensions['code_assets'] : null;
  final targetOs = codeAssets is Map ? codeAssets['target_os'] : null;
  if (targetOs != 'ios' && targetOs != 'android') {
    // Only pre-compile shader bundles when building for mobile (iOS / Android).
    return;
  }

  final dependencies = <Uri>[];
  final packageRoot = Directory.fromUri(buildInput.packageRoot);

  try {
    await precompilePackageShaders(
      packageRoot: packageRoot,
      targetOs: targetOs as String,
      recordedDependencies: dependencies,
    );
  } on FileSystemException catch (e) {
    // If shader_fun itself is hosted in a read-only pub cache, skip writing
    // into the package directory; the app's own hook/build.dart handles bundling.
    if (buildInput.packageName == 'shader_fun') {
      stderr.writeln(
        'shader_fun: skipping read-only package tree precompile ($e).',
      );
      return;
    }
    rethrow;
  }

  for (final dep in dependencies) {
    buildOutput.dependencies.add(dep);
  }
}

/// Discovers and pre-compiles all shaders under [packageRoot] into
/// `<packageRoot>/flutter_scene_generated/sf_<hash>.shaderbundle`.
///
/// Returns the number of shader bundles verified or compiled.
Future<int> precompilePackageShaders({
  required Directory packageRoot,
  required String targetOs,
  List<Uri>? recordedDependencies,
  String? customImpellercPath,
}) async {
  final generatedDir = Directory('${packageRoot.path}/flutter_scene_generated');
  if (!generatedDir.existsSync()) {
    generatedDir.createSync(recursive: true);
  }
  final gitignoreFile = File('${generatedDir.path}/.gitignore');
  if (!gitignoreFile.existsSync()) {
    gitignoreFile.writeAsStringSync('*\n!*/\n!.gitignore\n');
  }

  final preparedPairs = <String, ({String vertexGlsl, String fragmentGlsl})>{};

  void addPrepared(String vertexGlsl, String fragmentGlsl) {
    final hash = ImpellerCompilerCore.computeBundleHash(
      vertexGlsl: vertexGlsl,
      fragmentGlsl: fragmentGlsl,
    );
    preparedPairs.putIfAbsent(
      hash,
      () => (vertexGlsl: vertexGlsl, fragmentGlsl: fragmentGlsl),
    );
  }

  void addPassSources({
    required String code,
    String? vertexCode,
    String? commonCode,
    Map<String, int>? customUniformSlots,
    PassType passType = PassType.image,
    ShaderPassMode mode = ShaderPassMode.shaderToy,
  }) {
    if (code.trim().isEmpty) return;
    final prepared = ImpellerCompilerCore.prepareShaderSources(
      shaderGlsl: code,
      vertexGlsl: vertexCode,
      commonGlsl: commonCode,
      customUniformSlots: customUniformSlots,
      passType: passType,
      mode: mode,
    );
    addPrepared(prepared.vertexGlsl, prepared.fragmentGlsl);
  }

  // 1. Default starter passes (standalone and paired with default Common pass)
  for (final common in <String?>[null, _defaultCommonCode]) {
    addPassSources(
      code: _defaultEmptyImageCode,
      commonCode: common,
      passType: PassType.image,
    );
    addPassSources(
      code: _defaultBufferCode,
      commonCode: common,
      passType: PassType.bufferA,
    );
    addPassSources(
      code: _defaultSoundCode,
      commonCode: common,
      passType: PassType.sound,
    );
  }

  // 2. JSON shader files under shaders/ and assets/
  for (final dirName in const ['shaders', 'assets']) {
    final dir = Directory('${packageRoot.path}/$dirName');
    if (!dir.existsSync()) continue;
    final jsonFiles =
        dir
            .listSync(recursive: true, followLinks: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in jsonFiles) {
      recordedDependencies?.add(file.uri);
      _collectShadersFromJsonFile(file, addPassSources);
    }
  }

  // 3. Inline shaders inside lib/**/*.dart
  final libDir = Directory('${packageRoot.path}/lib');
  if (libDir.existsSync()) {
    final dartFiles =
        libDir
            .listSync(recursive: true, followLinks: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in dartFiles) {
      // Skip internal compiler templates that contain GLSL wrapper snippets.
      final normalized = file.path.replaceAll('\\', '/');
      if (normalized.contains('/lib/src/compiler/')) {
        continue;
      }
      recordedDependencies?.add(file.uri);
      _collectShadersFromDartFile(file, addPassSources);
    }
  }

  // 4. Compile any missing bundles via impellerc (bounded concurrency)
  final pendingEntries =
      <MapEntry<String, ({String vertexGlsl, String fragmentGlsl})>>[];
  for (final entry in preparedPairs.entries) {
    final bundleFile = File('${generatedDir.path}/sf_${entry.key}.shaderbundle');
    if (!bundleFile.existsSync() || bundleFile.lengthSync() == 0) {
      pendingEntries.add(entry);
    }
  }

  if (pendingEntries.isNotEmpty) {
    final impellerc = customImpellercPath ?? findImpellercBinary();
    const maxConcurrency = 6;
    final workerCount = pendingEntries.length < maxConcurrency
        ? pendingEntries.length
        : maxConcurrency;
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (nextIndex < pendingEntries.length) {
        final entry = pendingEntries[nextIndex++];
        final hash = entry.key;
        final bundleFile = File('${generatedDir.path}/sf_$hash.shaderbundle');

        final compileResult = await invokeImpellercProcess(
          quadVertexShader: entry.value.vertexGlsl,
          wrappedFragGlsl: entry.value.fragmentGlsl,
          customImpellercPath: impellerc,
          targetOsOverride: targetOs,
        );
        if (!compileResult.isSuccess || compileResult.bundleBytes == null) {
          throw StateError(
            'shader_fun hook failed to compile shader bundle sf_$hash: '
            '${compileResult.errorMessage}',
          );
        }

        final tmpFile = File('${bundleFile.path}.$pid.tmp');
        tmpFile.writeAsBytesSync(compileResult.bundleBytes!);
        tmpFile.renameSync(bundleFile.path);
      }
    }

    await Future.wait(
      List.generate(workerCount, (_) => runWorker()),
      eagerError: true,
    );
  }

  return preparedPairs.length;
}

typedef _AddPassCallback =
    void Function({
      required String code,
      String? vertexCode,
      String? commonCode,
      Map<String, int>? customUniformSlots,
      PassType passType,
      ShaderPassMode mode,
    });

void _collectShadersFromJsonFile(File file, _AddPassCallback addPassSources) {
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (_) {
    return;
  }
  if (decoded is! Map<String, dynamic>) return;

  final List<
    ({PassType type, ShaderPassMode mode, String code, String? vertexCode})
  >
  parsedPasses = [];

  if (decoded.containsKey('imageCode') ||
      (decoded.containsKey('buffers') && !decoded.containsKey('Shader'))) {
    final imageCode = decoded['imageCode']?.toString();
    if (imageCode != null && imageCode.trim().isNotEmpty) {
      parsedPasses.add((
        type: PassType.image,
        mode: ShaderPassMode.shaderToy,
        code: imageCode,
        vertexCode: null,
      ));
    }
    final buffers = decoded['buffers'];
    if (buffers is Map) {
      buffers.forEach((key, val) {
        final code = val?.toString() ?? '';
        if (code.trim().isEmpty) return;
        final upperKey = key.toString().toUpperCase();
        var type = PassType.bufferA;
        if (upperKey == 'B' || upperKey.contains('BUFFER B')) {
          type = PassType.bufferB;
        } else if (upperKey == 'C' || upperKey.contains('BUFFER C')) {
          type = PassType.bufferC;
        } else if (upperKey == 'D' || upperKey.contains('BUFFER D')) {
          type = PassType.bufferD;
        }
        parsedPasses.add((
          type: type,
          mode: ShaderPassMode.shaderToy,
          code: code,
          vertexCode: null,
        ));
      });
    }
  } else {
    final shaderMap = decoded.containsKey('Shader')
        ? decoded['Shader']
        : decoded;
    if (shaderMap is! Map<String, dynamic>) return;
    final rawPasses = shaderMap['renderpass'];
    if (rawPasses is! List) return;

    for (final rawPass in rawPasses) {
      if (rawPass is! Map<String, dynamic>) continue;
      final passName = rawPass['name']?.toString() ?? 'Image';
      final passTypeStr = rawPass['type']?.toString().toLowerCase() ?? 'image';
      final code = rawPass['code']?.toString() ?? '';

      final PassType type;
      switch (passTypeStr) {
        case 'buffer':
          final upper = passName.toUpperCase();
          if (upper.contains('BUFFER B') ||
              upper.endsWith(' B') ||
              upper == 'B') {
            type = PassType.bufferB;
          } else if (upper.contains('BUFFER C') ||
              upper.endsWith(' C') ||
              upper == 'C') {
            type = PassType.bufferC;
          } else if (upper.contains('BUFFER D') ||
              upper.endsWith(' D') ||
              upper == 'D') {
            type = PassType.bufferD;
          } else {
            type = PassType.bufferA;
          }
        case 'common':
          type = PassType.common;
        case 'sound':
          type = PassType.sound;
        case 'image':
        default:
          type = PassType.image;
      }

      final modeStr = rawPass['mode']?.toString().toLowerCase();
      final mode = modeStr == 'custom'
          ? ShaderPassMode.custom
          : ShaderPassMode.shaderToy;
      final vertexCode = rawPass['vertexCode']?.toString();

      parsedPasses.add((
        type: type,
        mode: mode,
        code: code,
        vertexCode: vertexCode,
      ));
    }
  }

  String? commonCode;
  for (final pass in parsedPasses) {
    if (pass.type == PassType.common) {
      commonCode = pass.code;
      break;
    }
  }

  // Match ShaderController.compileAllPasses() accumulated customUniformSlots order,
  // and also prepare each pass in isolation for individual compilePass() calls.
  final accumulatedSlots = <String, int>{};

  void registerSlots(String glsl, Map<String, int> slots) {
    final extracted = ImpellerCompilerCore.extractCustomUniforms(
      glsl,
      existingSlots: slots,
    );
    for (final u in extracted) {
      slots[u.name] = u.slot;
    }
  }

  for (final pass in parsedPasses) {
    if (pass.type == PassType.common || pass.code.trim().isEmpty) continue;

    registerSlots(pass.code, accumulatedSlots);
    if (pass.vertexCode != null && pass.vertexCode!.isNotEmpty) {
      registerSlots(pass.vertexCode!, accumulatedSlots);
    }

    addPassSources(
      code: pass.code,
      vertexCode: pass.vertexCode,
      commonCode: commonCode,
      customUniformSlots: Map<String, int>.from(accumulatedSlots),
      passType: pass.type,
      mode: pass.mode,
    );

    final isolatedSlots = <String, int>{};
    registerSlots(pass.code, isolatedSlots);
    if (pass.vertexCode != null && pass.vertexCode!.isNotEmpty) {
      registerSlots(pass.vertexCode!, isolatedSlots);
    }
    addPassSources(
      code: pass.code,
      vertexCode: pass.vertexCode,
      commonCode: commonCode,
      customUniformSlots: isolatedSlots,
      passType: pass.type,
      mode: pass.mode,
    );
  }
}

void _collectShadersFromDartFile(File file, _AddPassCallback addPassSources) {
  final source = file.readAsStringSync();

  // 1. Collect triple-quoted string variable/getter definitions.
  final stringVars = <String, String>{};
  final varRegex = RegExp(
    r'(?:(?:const|final)\s+(?:String\s+)?|String\s+get\s+)([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|=>)\s*'
    "(r?'''[\\s\\S]*?'''|"
    r'r?"""[\s\S]*?""")',
  );
  for (final match in varRegex.allMatches(source)) {
    final name = match.group(1)!;
    final rawLiteral = match.group(2)!;
    final value = _extractTripleQuotedContent(rawLiteral);
    if (value != null && !value.contains(r'$')) {
      stringVars[name] = value;
    }
  }

  // 2. Parse ShaderPass(...) constructor calls with balanced parentheses.
  final passCallRegex = RegExp(r'\bShaderPass\s*\(');
  for (final match in passCallRegex.allMatches(source)) {
    final openParenIdx = match.end - 1;
    final closeParenIdx = _findMatchingParen(source, openParenIdx);
    if (closeParenIdx == -1) continue;

    final argsBody = source.substring(openParenIdx + 1, closeParenIdx);
    final args = _parseTopLevelNamedArgs(argsBody);

    final codeExpr = args['code']?.trim();
    if (codeExpr == null) continue;
    final code = _resolveStringExpr(codeExpr, stringVars);
    if (code == null || code.trim().isEmpty) continue;

    final vertExpr = args['vertexCode']?.trim();
    final vertexCode = vertExpr != null
        ? _resolveStringExpr(vertExpr, stringVars)
        : null;

    final modeExpr = args['mode']?.trim() ?? '';
    final mode = modeExpr.contains('ShaderPassMode.custom')
        ? ShaderPassMode.custom
        : ShaderPassMode.shaderToy;

    final typeExpr = args['type']?.trim() ?? '';
    final passType = _parsePassType(typeExpr);
    if (passType == PassType.common) continue;

    final customSlots = <String, int>{};
    for (final u in ImpellerCompilerCore.extractCustomUniforms(code)) {
      customSlots[u.name] = u.slot;
    }
    if (vertexCode != null && vertexCode.isNotEmpty) {
      for (final u in ImpellerCompilerCore.extractCustomUniforms(
        vertexCode,
        existingSlots: customSlots,
      )) {
        customSlots[u.name] = u.slot;
      }
    }

    addPassSources(
      code: code,
      vertexCode: vertexCode,
      customUniformSlots: customSlots,
      passType: passType,
      mode: mode,
    );
  }

  // 3. Fallback scan for any triple-quoted GLSL literals (e.g. returned from helper methods).
  final tripleRegex = RegExp(
    "r?'''[\\s\\S]*?'''|"
    r'r?"""[\s\S]*?"""',
  );
  final mainImageDefRegex = RegExp(r'\bvoid\s+mainImage\s*\(');
  final mainSoundDefRegex = RegExp(r'\bvec2\s+mainSound\s*\(');

  for (final match in tripleRegex.allMatches(source)) {
    final raw = match.group(0)!;
    final content = _extractTripleQuotedContent(raw);
    if (content == null || content.trim().isEmpty || content.contains(r'$')) {
      continue;
    }
    if (mainImageDefRegex.hasMatch(content)) {
      addPassSources(
        code: content,
        passType: PassType.image,
        mode: ShaderPassMode.shaderToy,
      );
    } else if (mainSoundDefRegex.hasMatch(content)) {
      addPassSources(
        code: content,
        passType: PassType.sound,
        mode: ShaderPassMode.shaderToy,
      );
    }
  }
}

String? _extractTripleQuotedContent(String literal) {
  var body = literal;
  final isRaw = body.startsWith('r');
  if (isRaw) {
    body = body.substring(1);
  }
  if ((body.startsWith("'''") && body.endsWith("'''")) ||
      (body.startsWith('"""') && body.endsWith('"""'))) {
    if (body.length < 6) return null;
    var inner = body.substring(3, body.length - 3);
    // Dart's lexer strips a single immediate newline after opening triple quotes.
    if (inner.startsWith('\r\n')) {
      inner = inner.substring(2);
    } else if (inner.startsWith('\n')) {
      inner = inner.substring(1);
    }
    return inner;
  }
  return null;
}

String? _resolveStringExpr(String expr, Map<String, String> stringVars) {
  if (stringVars.containsKey(expr)) {
    return stringVars[expr];
  }
  return _extractTripleQuotedContent(expr);
}

PassType _parsePassType(String expr) {
  if (expr.contains('PassType.bufferA')) return PassType.bufferA;
  if (expr.contains('PassType.bufferB')) return PassType.bufferB;
  if (expr.contains('PassType.bufferC')) return PassType.bufferC;
  if (expr.contains('PassType.bufferD')) return PassType.bufferD;
  if (expr.contains('PassType.common')) return PassType.common;
  if (expr.contains('PassType.sound')) return PassType.sound;
  return PassType.image;
}

int _findMatchingParen(String s, int openIdx) {
  int depth = 0;
  int i = openIdx;
  while (i < s.length) {
    final nextIdx = _skipCommentOrString(s, i);
    if (nextIdx != i) {
      i = nextIdx;
      continue;
    }
    final ch = s[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

Map<String, String> _parseTopLevelNamedArgs(String body) {
  final result = <String, String>{};
  int parenDepth = 0;
  int bracketDepth = 0;
  int braceDepth = 0;
  int start = 0;
  int i = 0;

  void recordSegment(String segment) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return;
    final colonIdx = _findTopLevelColon(trimmed);
    if (colonIdx <= 0) return;
    final key = trimmed.substring(0, colonIdx).trim();
    final value = trimmed.substring(colonIdx + 1).trim();
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      result[key] = value;
    }
  }

  while (i < body.length) {
    final nextIdx = _skipCommentOrString(body, i);
    if (nextIdx != i) {
      i = nextIdx;
      continue;
    }
    final ch = body[i];
    if (ch == '(') {
      parenDepth++;
    } else if (ch == ')') {
      parenDepth--;
    } else if (ch == '[') {
      bracketDepth++;
    } else if (ch == ']') {
      bracketDepth--;
    } else if (ch == '{') {
      braceDepth++;
    } else if (ch == '}') {
      braceDepth--;
    } else if (ch == ',' &&
        parenDepth == 0 &&
        bracketDepth == 0 &&
        braceDepth == 0) {
      recordSegment(body.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  recordSegment(body.substring(start));
  return result;
}

int _findTopLevelColon(String s) {
  int i = 0;
  while (i < s.length) {
    final nextIdx = _skipCommentOrString(s, i);
    if (nextIdx != i) {
      i = nextIdx;
      continue;
    }
    final ch = s[i];
    if (ch == ':') return i;
    if (ch == '(' || ch == '[' || ch == '{') return -1;
    i++;
  }
  return -1;
}

int _skipCommentOrString(String s, int i) {
  if (i >= s.length) return i;
  // Line comment
  if (s.startsWith('//', i)) {
    final nl = s.indexOf('\n', i + 2);
    return nl == -1 ? s.length : nl + 1;
  }
  // Block comment
  if (s.startsWith('/*', i)) {
    final end = s.indexOf('*/', i + 2);
    return end == -1 ? s.length : end + 2;
  }
  // Triple-quoted strings (optionally raw)
  for (final prefix in const ["r'''", 'r"""', "'''", '"""']) {
    if (s.startsWith(prefix, i)) {
      final quote = prefix.substring(prefix.length - 3);
      final isRaw = prefix.startsWith('r');
      int j = i + prefix.length;
      while (j < s.length) {
        if (!isRaw && s[j] == r'\') {
          j += 2;
          continue;
        }
        if (s.startsWith(quote, j)) {
          return j + 3;
        }
        j++;
      }
      return s.length;
    }
  }
  // Single-quoted or double-quoted string (optionally raw)
  for (final prefix in const ["r'", 'r"', "'", '"']) {
    if (s.startsWith(prefix, i)) {
      final quote = prefix[prefix.length - 1];
      final isRaw = prefix.startsWith('r');
      int j = i + prefix.length;
      while (j < s.length) {
        if (!isRaw && s[j] == r'\') {
          j += 2;
          continue;
        }
        if (s[j] == quote) {
          return j + 1;
        }
        j++;
      }
      return s.length;
    }
  }
  return i;
}
