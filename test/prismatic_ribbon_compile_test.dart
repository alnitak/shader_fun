import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/compiler/impeller_compiler.dart';
import 'package:shader_fun/src/models/shader_project.dart';

void main() {
  test('Prismatic Ribbon JSON parses and compiles successfully with ImpellerCompiler', () async {
    final file = File('example/shaders/Prismatic_Ribbon.json');
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    final project = ShaderProject.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );

    expect(project.name, 'Prismatic Ribbon');
    expect(project.passes.length, 1);

    final pass = project.passes.first;
    final res = await ImpellerCompiler.compile(
      shaderGlsl: pass.code,
      commonGlsl: project.commonPass?.code,
    );

    expect(
      res.isSuccess,
      isTrue,
      reason: '${pass.name} compilation failed: ${res.errorMessage}',
    );
    expect(res.bundleBytes, isNotNull);
  });

  test('Prismatic Flutter Logo JSON parses and compiles successfully with ImpellerCompiler', () async {
    final file = File('example/shaders/Prismatic_Flutter.json');
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    final project = ShaderProject.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );

    expect(project.name, 'Prismatic Flutter Logo');
    expect(project.passes.length, 1);

    final pass = project.passes.first;
    final res = await ImpellerCompiler.compile(
      shaderGlsl: pass.code,
      commonGlsl: project.commonPass?.code,
    );

    expect(
      res.isSuccess,
      isTrue,
      reason: '${pass.name} compilation failed: ${res.errorMessage}',
    );
    expect(res.bundleBytes, isNotNull);
  });

  test('Prismatic Dash Plushie JSON parses and compiles successfully with ImpellerCompiler', () async {
    final file = File('example/shaders/Prismatic_Dash.json');
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    final project = ShaderProject.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );

    expect(project.name, 'Prismatic Dash');
    expect(project.passes.length, 1);

    final pass = project.passes.first;
    final res = await ImpellerCompiler.compile(
      shaderGlsl: pass.code,
      commonGlsl: project.commonPass?.code,
    );

    expect(
      res.isSuccess,
      isTrue,
      reason: '${pass.name} compilation failed: ${res.errorMessage}',
    );
    expect(res.bundleBytes, isNotNull);
  });
}
