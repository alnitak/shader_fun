import 'package:example/studio_example/shadertoy_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test play/pause button in ShaderToyStudio', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: ShaderToyStudio()));

    // Pump frames to initialize and compile
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Initially playing
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    expect(find.text('PAUSED'), findsNothing);

    // 1. Tap pause in viewport
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // 2. Tap play in viewport
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // 3. Tap pause in editor bottom bar
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

    // 4. Tap play in editor bottom bar
    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
  });
}
