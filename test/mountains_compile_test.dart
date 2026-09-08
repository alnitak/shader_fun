import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/compiler/impeller_compiler.dart';
import 'package:shader_fun/src/core/shader_pass.dart';
import 'package:shader_fun/src/models/shadertoy_json.dart';

void main() {
  test('compile mountains shader with ImpellerCompiler', () async {
    final file = File('example/shaders/mouse_paint_eroded_mountains.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    final project =
        ShaderToyProject.fromJson(jsonDecode(content) as Map<String, dynamic>);

    final common = project.commonPass?.code;

    for (final pass in project.passes) {
      if (pass.type == PassType.common) continue;

      final res = await ImpellerCompiler.compile(
        shadertoyGlsl: pass.code,
        commonGlsl: common,
      );

      expect(res.isSuccess, isTrue,
          reason: '${pass.name} failed: ${res.errorMessage}');
      expect(res.bundleBytes, isNotNull);
    }
  });
}
