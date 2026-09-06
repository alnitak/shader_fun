import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:shader_fun/src/controller/shadertoy_controller.dart';
import 'package:shader_fun/src/models/shadertoy_json.dart';
import 'package:shader_fun/src/widgets/shadertoy_viewport.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resizing controller does not freeze playback or null ticker', (tester) async {
    final project = ShaderToyProject.empty();
    late ShaderToyController controller;

    await tester.pumpWidget(
      TestHarness(
        onInit: (vsync) {
          controller = ShaderToyController(
            initialProject: project,
            vsync: vsync,
            autoPlay: true,
          );
        },
      ),
    );

    expect(controller.isPlaying, isTrue);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.frame, greaterThan(0));
    final frameBefore = controller.frame;

    // Simulate rapid window resizing
    for (double w = 800; w <= 850; w += 5) {
      controller.resize(Size(w, w * 9 / 16));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.isPlaying, isTrue);
    expect(controller.frame, greaterThan(frameBefore));
    controller.dispose();
  });

  testWidgets('switching viewport layout across 900px does not kill ticker', (tester) async {
    final project = ShaderToyProject.empty();
    late ShaderToyController controller;

    Widget buildStudio(double width) {
      return MaterialApp(
        home: SizedBox(
          width: width,
          height: 600,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              final viewport = ShaderToyViewport(controller: controller);
              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: viewport),
                    const Expanded(child: SizedBox()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Expanded(child: viewport),
                    const Expanded(child: SizedBox()),
                  ],
                );
              }
            },
          ),
        ),
      );
    }


    controller = ShaderToyController(
      initialProject: project,
      autoPlay: true,
    );

    await tester.pumpWidget(buildStudio(1000));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.isPlaying, isTrue);
    final f1 = controller.frame;

    // Now resize to narrow (crossing 900px)
    await tester.pumpWidget(buildStudio(800));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.isPlaying, isTrue);
    expect(controller.frame, greaterThan(f1));

    // Now click play/pause
    controller.pause();
    expect(controller.isPlaying, isFalse);
    final fPaused = controller.frame;
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.frame, equals(fPaused));

    controller.play();
    expect(controller.isPlaying, isTrue);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.frame, greaterThan(fPaused));

    controller.dispose();
  });

  testWidgets('parent-owned vsync controller does not lose ticker when viewport unmounts', (tester) async {
    final project = ShaderToyProject.empty();
    late ShaderToyController controller;

    Widget buildApp(double width) {
      return MaterialApp(
        home: StudioTestWidget(
          width: width,
          onInit: (c) => controller = c,
          project: project,
        ),
      );
    }

    await tester.pumpWidget(buildApp(1000));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.isPlaying, isTrue);
    final f1 = controller.frame;
    expect(f1, greaterThan(0));

    // Now resize below 900
    await tester.pumpWidget(buildApp(800));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.isPlaying, isTrue);
    expect(controller.frame, greaterThan(f1));

    // Try pressing pause and play
    controller.pause();
    expect(controller.isPlaying, isFalse);
    final fPaused = controller.frame;
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.frame, equals(fPaused));

    controller.play();
    expect(controller.isPlaying, isTrue);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.frame, greaterThan(fPaused));
  });
}

class StudioTestWidget extends StatefulWidget {
  final double width;
  final ValueChanged<ShaderToyController> onInit;
  final ShaderToyProject project;

  const StudioTestWidget({
    super.key,
    required this.width,
    required this.onInit,
    required this.project,
  });

  @override
  State<StudioTestWidget> createState() => _StudioTestWidgetState();
}

class _StudioTestWidgetState extends State<StudioTestWidget>
    with SingleTickerProviderStateMixin {
  late final ShaderToyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShaderToyController(
      initialProject: widget.project,
      vsync: this,
      autoPlay: true,
    );
    _controller.play();
    widget.onInit(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 600,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final viewport = ShaderToyViewport(controller: _controller);
          if (isWide) {
            return Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide()),
                    ),
                    child: viewport,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(child: viewport),
                const Expanded(child: SizedBox()),
              ],
            );
          }
        },
      ),
    );
  }
}

class TestHarness extends StatefulWidget {
  final void Function(TickerProvider vsync) onInit;
  const TestHarness({super.key, required this.onInit});

  @override
  State<TestHarness> createState() => _TestHarnessState();
}

class _TestHarnessState extends State<TestHarness> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onInit(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
