import 'dart:io';

import 'package:example/studio_example/dialogs/load_shader_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoadShaderDialog Feature Badges', () {
    testWidgets('shows GPU sound badge when shader project has sound pass',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tempDir = Directory.systemTemp.createTempSync('shader_dialog_test');
      try {
        final gpuSoundFile = File('${tempDir.path}/gpu_sound_shader.json');
        gpuSoundFile.writeAsStringSync('''
        {
          "Shader": {
            "info": { "name": "Synthesized Grand Piano", "description": "Sound generated on GPU" },
            "renderpass": [
              {
                "name": "Image",
                "type": "image",
                "code": "void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }",
                "inputs": [],
                "outputs": []
              },
              {
                "name": "Sound",
                "type": "sound",
                "code": "vec2 mainSound(int samp, float time) { return vec2(0.0); }",
                "inputs": [],
                "outputs": []
              }
            ]
          }
        }
        ''');

        SharedPreferences.setMockInitialValues({
          'last_json_folder_path': tempDir.path,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LoadShaderDialog(
                onLoadProject: (_) {},
              ),
            ),
          ),
        );

        // Wait for directory scan
        await tester.pumpAndSettle();

        expect(find.text('GPU sound'), findsOneWidget);
        expect(find.text('2 passes'), findsOneWidget);
        // It does not have an audio file/channel, so 'audio' should not appear
        expect(find.text('audio'), findsNothing);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
