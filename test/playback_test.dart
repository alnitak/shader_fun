// ignore: avoid_relative_lib_imports
import '../example/lib/shadertoy_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test play/pause button in ShaderToyStudio', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: ShaderToyStudio(),
      ),
    );

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

    // Now paused: viewport shows play_arrow, header shows play_circle_fill, badge shows PAUSED
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);

    // 2. Tap play in editor header
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pump();

    // Now playing again
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    expect(find.text('PAUSED'), findsNothing);

    // 3. Tap pause in editor header
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);

    // 4. Tap play in viewport
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    // 5. Verify compile button is present
    expect(find.byIcon(Icons.bolt), findsOneWidget);

    // Pause before unmounting
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
  });
}
