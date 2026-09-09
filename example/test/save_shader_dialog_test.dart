import 'package:example/studio_example/dialogs/save_shader_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  testWidgets(
    'SaveShaderDialog updates JSON preview when input fields change',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final project = ShaderToyProject(
        id: 'test_id',
        name: 'Initial Name',
        author: 'Initial Author',
        description: 'Initial Desc',
        url: 'https://initial.url',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SaveShaderDialog(project: project)),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial preview has Initial Name and Initial Author
      expect(find.textContaining('Initial Name'), findsWidgets);
      expect(find.textContaining('Initial Author'), findsWidgets);

      // Find the Shader Name text field and enter new text
      final nameField = find.widgetWithText(TextField, 'Shader Name');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Super Cool Neon Shader');
      await tester.pumpAndSettle();

      // Verify JSON preview reflects the new name
      expect(find.textContaining('Super Cool Neon Shader'), findsWidgets);

      // Find Author text field and change it
      final authorField = find.widgetWithText(TextField, 'Username / Author');
      expect(authorField, findsOneWidget);
      await tester.enterText(authorField, 'StarCoder');
      await tester.pumpAndSettle();

      // Verify JSON preview reflects the new author
      expect(find.textContaining('StarCoder'), findsWidgets);

      // Find Description text field and change it
      final descField = find.widgetWithText(TextField, 'Description');
      expect(descField, findsOneWidget);
      await tester.enterText(descField, 'A futuristic glow effect');
      await tester.pumpAndSettle();

      // Verify JSON preview reflects the description
      expect(find.textContaining('A futuristic glow effect'), findsWidgets);
    },
  );
}
