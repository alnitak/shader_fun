import 'package:flutter/material.dart';

import 'custom_mesh_widget_example.dart';
import 'custom_moving_triangle_example.dart';
import 'custom_rotating_cube.dart';
import 'shadertoy_inside_custom_triangle_example.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExamplesLauncher(),
    ),
  );
}

/// Description of an example item in the selector list.
class _ExampleItem {
  const _ExampleItem({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

/// Launcher screen that hosts the example navigation on the left pane
/// (max width 300) and displays the selected example on the right pane.
class ExamplesLauncher extends StatefulWidget {
  /// Creates an [ExamplesLauncher].
  const ExamplesLauncher({super.key});

  @override
  State<ExamplesLauncher> createState() => _ExamplesLauncherState();
}

class _ExamplesLauncherState extends State<ExamplesLauncher> {
  int _selectedIndex = 0;

  static final List<_ExampleItem> _examples = <_ExampleItem>[
    _ExampleItem(
      title: '1. Moving Triangle',
      subtitle: 'Custom vertex shader moves geometry over an animated ShaderToy background.',
      builder: (_) => const CustomMovingTriangleExample(),
    ),
    _ExampleItem(
      title: '2. Wavy Flutter Widget',
      subtitle:
          'Live interactive WidgetChannel deformed by sinusoidal vertex waves.',
      builder: (_) => const CustomMeshWidgetExample(),
    ),
    _ExampleItem(
      title: '3. ShaderToy Inside Mesh',
      subtitle: 'Procedural ShaderToy kaleidoscope texture-mapped onto rotating triangle geometry.',
      builder: (_) => const ShaderToyInsideCustomTriangleExample(),
    ),
    _ExampleItem(
      title: '4. Rotating 3D Cube',
      subtitle: 'Pure custom vertex and fragment shaders rendering a 3D rotating cube with perspective and lighting.',
      builder: (_) => const CustomRotatingCubeExample(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('shader_fun - Custom Shader Examples'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF11111B),
      body: Row(
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: SizedBox(
              width: 300,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF181825),
                  border: Border(right: BorderSide(color: Color(0xFF313244))),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _examples.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final _ExampleItem item = _examples[index];
                    final bool isSelected = index == _selectedIndex;

                    return Card(
                      color: isSelected
                          ? const Color(0xFF313244)
                          : const Color(0xFF1E1E2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.cyanAccent
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.cyanAccent
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            item.subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        selected: isSelected,
                        onTap: () {
                          if (_selectedIndex != index) {
                            setState(() {
                              _selectedIndex = index;
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: _examples[_selectedIndex].builder(context),
            ),
          ),
        ],
      ),
    );
  }
}
