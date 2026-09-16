import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  test(
    'Paint streams passes compile and channels are resolved correctly',
    () async {
      final file = File('example/shaders/Paint_streams.json');
      expect(file.existsSync(), isTrue);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final project = ShaderProject.fromJson(json);

      expect(
        project.passes.length,
        5,
      ); // Common, Buffer A, Buffer B, Buffer C, Image
      final commonPass = project.commonPass;
      expect(commonPass, isNotNull);

      for (final pass in project.passes) {
        if (pass.type == PassType.common) continue;

        final compiled = await ImpellerCompiler.compile(
          shaderGlsl: pass.code,
          commonGlsl: commonPass?.code,
        );
        expect(compiled.isSuccess, isTrue, reason: compiled.errorMessage);
        expect(compiled.bundleBytes, isNotNull);

        // Verify that effectiveCode with Common detects channel usage
        final effectiveCode = '${commonPass!.code}\n${pass.code}';
        expect(ImpellerCompiler.shaderUsesChannel(effectiveCode, 0), isTrue);
      }
    },
  );

  test('all json files in example/shaders parse successfully', () {
    final dir = Directory('example/shaders');
    expect(dir.existsSync(), isTrue);
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files.isNotEmpty, isTrue);
    for (final file in files) {
      final content = file.readAsStringSync();
      final project = ShaderProject.parseJsonString(content);
      expect(
        project.name.isNotEmpty,
        isTrue,
        reason: 'Failed parsing ${file.path}',
      );
    }
  });
}
