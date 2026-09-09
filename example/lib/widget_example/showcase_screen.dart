import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

import 'demos/crt_terminal_demo.dart';
import 'demos/exploding_button_demo.dart';
import 'demos/transition_demo.dart';
import 'demos/liquid_list_demo.dart';
import 'demos/showcase_demo.dart';

class WidgetShowcaseScreen extends StatefulWidget {
  const WidgetShowcaseScreen({super.key});

  @override
  State<WidgetShowcaseScreen> createState() => _WidgetShowcaseScreenState();
}

class _WidgetShowcaseScreenState extends State<WidgetShowcaseScreen>
    with TickerProviderStateMixin {
  ShowcaseDemo _currentDemo = ShowcaseDemo.explodingButton;
  ShaderToyController? _controller;

  late final ExplodingButtonDemo _explodingButtonDemo = ExplodingButtonDemo(
    onStateChanged: () => setState(() {}),
  );
  late final LiquidListDemo _liquidListDemo = LiquidListDemo();
  late final CrtTerminalDemo _crtTerminalDemo = CrtTerminalDemo();
  late final TransitionDemo _transitionDemo = TransitionDemo(
    vsync: this,
    onStateChanged: () => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _initControllerForDemo(_currentDemo);
  }

  @override
  void dispose() {
    _explodingButtonDemo.dispose();
    _liquidListDemo.dispose();
    _crtTerminalDemo.dispose();
    _transitionDemo.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _switchDemo(ShowcaseDemo demo) {
    if (_currentDemo == demo) return;
    setState(() {
      _currentDemo = demo;
      _initControllerForDemo(demo);
    });
  }

  void _initControllerForDemo(ShowcaseDemo demo) {
    _controller?.dispose();

    final ShaderToyProject project;
    switch (demo) {
      case ShowcaseDemo.explodingButton:
        project = _explodingButtonDemo.createProject();
        _controller = ShaderToyController(
          initialProject: project,
          autoPlay: true,
        );
        _explodingButtonDemo.attachController(_controller!);
        break;

      case ShowcaseDemo.waterList:
        project = _liquidListDemo.createProject();
        _controller = ShaderToyController(
          initialProject: project,
          autoPlay: true,
        );
        break;

      case ShowcaseDemo.crtTerminal:
        project = _crtTerminalDemo.createProject();
        _controller = ShaderToyController(
          initialProject: project,
          autoPlay: true,
        );
        break;

      case ShowcaseDemo.widgetTransition:
        project = _transitionDemo.createProject();
        _controller = ShaderToyController(
          initialProject: project,
          autoPlay: true,
        );
        _transitionDemo.attachController(_controller!);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F111A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.widgets, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'WidgetChannel Interactive Showcase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF141724),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final demo in ShowcaseDemo.values) ...[
                    _buildDemoTab(demo),
                    if (demo != ShowcaseDemo.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Viewport Area
          Expanded(
            child: controller == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ShaderToyViewport(
                              key: ValueKey(_currentDemo),
                              controller: controller,
                              showControls: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Bottom description & action banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF111420),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _currentDemo.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_currentDemo == ShowcaseDemo.explodingButton) ...[
                  const SizedBox(width: 12),
                  _explodingButtonDemo.buildBannerAction(),
                ],
                if (_currentDemo == ShowcaseDemo.widgetTransition) ...[
                  const SizedBox(width: 12),
                  _transitionDemo.buildBannerActions(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoTab(ShowcaseDemo demo) {
    final isSelected = _currentDemo == demo;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _switchDemo(demo),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF818CF8) : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              demo.title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
