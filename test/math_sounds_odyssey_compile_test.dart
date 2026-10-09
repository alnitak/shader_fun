import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  test('Math_Sounds_Odyssey compiles Common, Image, and Sound passes', () async {
    final file = File('example/shaders/Math_Sounds_Odyssey.json');
    expect(file.existsSync(), isTrue);

    final project = ShaderProject.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );

    expect(project.passes.length, 3);
    expect(project.hasSoundPass, isTrue);
    expect(project.commonPass, isNotNull);

    final commonCode = project.commonPass!.code;

    // 1. Compile Sound pass
    final soundPass = project.soundPass!;
    final soundRes = await ImpellerCompiler.compile(
      shaderGlsl: soundPass.code,
      commonGlsl: commonCode,
      passType: PassType.sound,
    );
    expect(
      soundRes.isSuccess,
      isTrue,
      reason: 'Sound compilation failed: ${soundRes.errorMessage}',
    );

    // 2. Compile Image pass
    final imagePass = project.passes.firstWhere((p) => p.type == PassType.image);
    final imageRes = await ImpellerCompiler.compile(
      shaderGlsl: imagePass.code,
      commonGlsl: commonCode,
      passType: PassType.image,
    );
    expect(
      imageRes.isSuccess,
      isTrue,
      reason: 'Image compilation failed: ${imageRes.errorMessage}',
    );
  });
}
