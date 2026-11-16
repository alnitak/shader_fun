import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';
import 'package:shader_fun/shader_fun.dart';
import 'package:shader_fun/src/compiler/build_hook.dart';

void main() {
  group('Mobile build hook pre-compilation', () {
    test(
      'buildShaderFunBundles skips compilation on non-mobile targets',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('hook_noop_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final sharedOutDir = Directory('${tempDir.path}/out_shared')
          ..createSync();
        final outFile = File('${tempDir.path}/output.json');

        for (final targetOs in <String?>[null, 'macos', 'linux', 'windows']) {
          final inputJson = <String, Object?>{
            'assets': <String, Object?>{},
            'config': <String, Object?>{
              'build_asset_types': targetOs == null
                  ? <String>[]
                  : <String>['code_assets/code'],
              if (targetOs != null)
                'extensions': <String, Object?>{
                  'code_assets': <String, Object?>{
                    'link_mode_preference': 'dynamic',
                    'target_architecture': 'arm64',
                    'target_os': targetOs,
                  },
                },
              'linking_enabled': false,
            },
            'out_dir_shared': sharedOutDir.uri.toFilePath(),
            'out_file': outFile.uri.toFilePath(),
            'package_name': 'test_pkg',
            'package_root': tempDir.uri.toFilePath(),
            'user_defines': <String, Object?>{},
          };

          final input = BuildInput(inputJson);
          final output = BuildOutputBuilder();
          await buildShaderFunBundles(buildInput: input, buildOutput: output);

          final generatedDir = Directory(
            '${tempDir.path}/flutter_scene_generated',
          );
          expect(
            generatedDir.existsSync(),
            isFalse,
            reason: 'Hook should not create bundles for targetOs=$targetOs',
          );
        }
      },
    );

    test('precompilePackageShaders builds bundles for all example JSON and inline shaders on iOS', () async {
      final exampleDir = Directory('example');
      expect(exampleDir.existsSync(), isTrue);

      final deps = <Uri>[];
      final compiledCount = await precompilePackageShaders(
        packageRoot: exampleDir,
        targetOs: 'ios',
        recordedDependencies: deps,
      );
      expect(compiledCount, greaterThan(0));
      expect(deps, isNotEmpty);

      // 1. Verify default starter passes
      final defaultEmpty = ShaderProject.empty();
      for (final pass in defaultEmpty.passes) {
        final prepared = ImpellerCompiler.prepareShaderSources(
          shaderGlsl: pass.code,
          vertexGlsl: pass.vertexCode,
          passType: pass.type,
          mode: pass.mode,
        );
        final hash = ImpellerCompiler.computeBundleHash(
          vertexGlsl: prepared.vertexGlsl,
          fragmentGlsl: prepared.fragmentGlsl,
        );
        final assetKey = ImpellerCompiler.bundleAssetKeyForHash(hash);
        final file = File('${exampleDir.path}/$assetKey');
        expect(
          file.existsSync() && file.lengthSync() > 0,
          isTrue,
          reason: 'Missing bundle for default ${pass.name}: $assetKey',
        );
      }

      // 2. Verify every JSON shader project in example/shaders/
      final shadersDir = Directory('${exampleDir.path}/shaders');
      final jsonFiles = shadersDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(jsonFiles, isNotEmpty);

      for (final jsonFile in jsonFiles) {
        final project = ShaderProject.parseJsonString(
          jsonFile.readAsStringSync(),
        );
        final commonCode = project.commonPass?.code;
        final uniforms = CommonUniforms();

        for (final pass in project.passes.where(
          (p) => p.enabled && p.type != PassType.common,
        )) {
          if (pass.code.trim().isEmpty) continue;
          for (final u in ImpellerCompiler.extractCustomUniforms(
            pass.code,
            existingSlots: uniforms.customSlots,
          )) {
            uniforms.registerCustomUniformSlot(u.name, u.slot);
          }
          if (pass.vertexCode != null && pass.vertexCode!.isNotEmpty) {
            for (final u in ImpellerCompiler.extractCustomUniforms(
              pass.vertexCode!,
              existingSlots: uniforms.customSlots,
            )) {
              uniforms.registerCustomUniformSlot(u.name, u.slot);
            }
          }

          final prepared = ImpellerCompiler.prepareShaderSources(
            shaderGlsl: pass.code,
            vertexGlsl: pass.vertexCode,
            commonGlsl: commonCode,
            customUniformSlots: uniforms.customSlots,
            passType: pass.type,
            mode: pass.mode,
          );
          final hash = ImpellerCompiler.computeBundleHash(
            vertexGlsl: prepared.vertexGlsl,
            fragmentGlsl: prepared.fragmentGlsl,
          );
          final assetKey = ImpellerCompiler.bundleAssetKeyForHash(hash);
          final file = File('${exampleDir.path}/$assetKey');
          expect(
            file.existsSync() && file.lengthSync() > 0,
            isTrue,
            reason:
                'Missing pre-compiled bundle for ${jsonFile.path} pass ${pass.name}: $assetKey',
          );
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('example/hook/build.dart runs cleanly in standalone Dart VM for iOS', () async {
      final exampleDir = Directory('example').absolute;
      final tempDir = await Directory.systemTemp.createTemp('hook_vm_exec_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sharedOutDir = Directory('${tempDir.path}/shared')..createSync();
      final inputFile = File('${tempDir.path}/input.json');
      final outputFile = File('${tempDir.path}/output.json');

      inputFile.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'assets': <String, Object?>{},
          'config': <String, Object?>{
            'build_asset_types': <String>['code_assets/code'],
            'extensions': <String, Object?>{
              'code_assets': <String, Object?>{
                'link_mode_preference': 'dynamic',
                'target_architecture': 'arm64',
                'target_os': 'ios',
              },
            },
            'linking_enabled': false,
          },
          'out_dir_shared': sharedOutDir.uri.toFilePath(),
          'out_file': outputFile.uri.toFilePath(),
          'package_name': 'example',
          'package_root': exampleDir.uri.toFilePath(),
          'user_defines': <String, Object?>{},
        }),
      );

      final impellerc = ImpellerCompiler.findImpellerc();
      expect(impellerc, isNotNull);
      final flutterBinDir = File(impellerc!)
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
      final dartExe = File(
        '$flutterBinDir/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
      );
      final dartCmd = dartExe.existsSync() ? dartExe.path : 'dart';

      final res = await Process.run(dartCmd, [
        'run',
        'hook/build.dart',
        '--config=${inputFile.path}',
      ], workingDirectory: exampleDir.path);
      expect(
        res.exitCode,
        0,
        reason:
            'example/hook/build.dart failed:\nstdout: ${res.stdout}\nstderr: ${res.stderr}',
      );
      expect(outputFile.existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
