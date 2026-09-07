import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/compiler/impeller_compiler.dart';
import 'package:shader_fun/src/models/shadertoy_json.dart';

void main() {
  test('Compile Floating Mountains shader with iChannelResolution', () async {
    final file = File('example/shaders/Floating_Mountains.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    final project =
        ShaderToyProject.fromJson(jsonDecode(content) as Map<String, dynamic>);

    final pass = project.imagePass!;
    final res = await ImpellerCompiler.compile(shadertoyGlsl: pass.code);
    expect(res.isSuccess, isTrue, reason: res.errorMessage);
  });
}
