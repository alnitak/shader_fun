import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';
import 'package:shader_fun/src/compiler/impeller_compiler.dart';
import 'package:shader_fun/src/models/shadertoy_json.dart';

void main() {
  test('Heartfelt shader compiles successfully with texture channel and textureLod', () async {
    final file = File('example/shaders/Heartfelt.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    final project =
        ShaderToyProject.fromJson(jsonDecode(content) as Map<String, dynamic>);

    expect(project.passes.length, 1);
    final pass = project.passes.first;
    expect(pass.channels.isNotEmpty, isTrue);
    final ch0 = pass.channels[0];
    expect(ch0, isA<TextureChannel>());

    final res = await ImpellerCompiler.compile(
      shadertoyGlsl: pass.code,
      commonGlsl: project.commonPass?.code,
    );

    expect(res.isSuccess, isTrue,
        reason: '${pass.name} failed: ${res.errorMessage}');
    expect(res.bundleBytes, isNotNull);
  });
}
