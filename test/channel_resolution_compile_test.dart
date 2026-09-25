// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';
import 'package:shader_fun/src/compiler/impeller_compiler.dart';
import 'package:shader_fun/src/core/shader_pass.dart';
import 'package:shader_fun/src/core/common_uniforms.dart';
import 'package:shader_fun/src/gpu/gpu.dart' as gpu;
import 'package:shader_fun/src/models/shader_project.dart';
import 'package:shader_fun/src/renderer/gpu_renderer.dart';

void main() {
  test('Compile Floating Mountains shader with iChannelResolution', () async {
    final file = File('example/shaders/Floating_Mountains.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    final project = ShaderProject.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );

    final pass = project.imagePass!;
    final wrapped = ImpellerCompiler.wrapShaderGlsl(pass.code);
    final tmpDir = Directory.systemTemp.createTempSync('mountains_msl_');
    final fragFile = File('${tmpDir.path}/mountains.frag');
    fragFile.writeAsStringSync(wrapped);
    final metalFile = File('${tmpDir.path}/mountains.metal');
    final impellerc = ImpellerCompiler.findImpellerc()!;
    final proc = Process.runSync(impellerc, [
      '--metal-desktop',
      '--input-type=frag',
      '--input=${fragFile.path}',
      '--sl=${metalFile.path}',
      '--spirv=${tmpDir.path}/mountains.spv',
      '--reflection-json=${tmpDir.path}/mountains.json',
    ]);
    expect(proc.exitCode, 0, reason: proc.stderr.toString());
    final res = await ImpellerCompiler.compile(shaderGlsl: pass.code);
    expect(res.isSuccess, isTrue, reason: res.errorMessage);
  });

  test('Check MipFilter values', () {
    print('MipFilter values: ${gpu.MipFilter.values}');
    print('SamplerAddressMode values: ${gpu.SamplerAddressMode.values}');
  });

  test('Render Floating Mountains frame', () async {
    final file = File('example/shaders/Floating_Mountains.json');
    final project = ShaderProject.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    final pass = project.imagePass!;
    var testCode = pass.code;

    final res = await ImpellerCompiler.compile(shaderGlsl: testCode);
    expect(res.isSuccess, isTrue, reason: res.errorMessage);

    final renderer = FlutterGpuRenderer(width: 320, height: 180);
    if (!renderer.isGpuAvailable) {
      return;
    }
    final loaded = await renderer.loadShaderBundle(
      res.bundleBytes!,
      passType: PassType.image,
      activeCode: testCode,
    );
    expect(loaded, isTrue);

    // Load textures using TextureChannel (with raw PNG decoding and asset filesystem fallback)
    final noiseChannel = TextureChannel(
      src: 'assets/2d_texture/rgba_noise_medium.png',
    );
    await noiseChannel.loadImage();
    expect(noiseChannel.rawRgbaBytes, isNotNull);
    renderer.uploadTextureChannel(
      0,
      noiseChannel.rawRgbaBytes!,
      noiseChannel.imageWidth!,
      noiseChannel.imageHeight!,
    );

    final metalChannel = TextureChannel(
      src: 'assets/2d_texture/rusty_metal.jpg',
    );
    await metalChannel.loadImage();
    expect(metalChannel.rawRgbaBytes, isNotNull);
    renderer.uploadTextureChannel(
      1,
      metalChannel.rawRgbaBytes!,
      metalChannel.imageWidth!,
      metalChannel.imageHeight!,
    );

    final uniforms = CommonUniforms(
      resolution: const ui.Size(320, 180),
      time: 30.0,
      timeDelta: 1.0 / 60.0,
      frameRate: 60.0,
      frame: 1800,
    );

    final img = await renderer.renderFrame(
      uniforms: uniforms,
      passes: project.passes,
      activePass: pass,
    );
    expect(img, isNotNull);
    if (img != null) {
      final imgBytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final list = imgBytes!.buffer.asUint8List();
      int nonZero = 0;
      int totalPixels = list.length ~/ 4;
      double rSum = 0, gSum = 0, bSum = 0;
      for (int i = 0; i < list.length; i += 4) {
        if (list[i] > 10 || list[i + 1] > 10 || list[i + 2] > 10) {
          nonZero++;
        }
        rSum += list[i];
        gSum += list[i + 1];
        bSum += list[i + 2];
      }
      print(
        'Non-black pixels: $nonZero / $totalPixels (${(nonZero / totalPixels * 100).toStringAsFixed(1)}%)',
      );
      print(
        'Average RGB: (${(rSum / totalPixels).toStringAsFixed(1)}, ${(gSum / totalPixels).toStringAsFixed(1)}, ${(bSum / totalPixels).toStringAsFixed(1)})',
      );
      expect(nonZero / totalPixels, greaterThan(0.90));
    }
  });
}
