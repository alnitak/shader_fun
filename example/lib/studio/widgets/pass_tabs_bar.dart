import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Horizontal tab strip for switching between Image, Buffers, Common, and Sound passes.
class PassTabsBar extends StatelessWidget {
  const PassTabsBar({
    super.key,
    required this.passes,
    required this.activePassIndex,
    required this.onSelectPass,
    required this.onAddPass,
    required this.onRemovePass,
    required this.showInputs,
    required this.onToggleInputs,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onCompile,
  });

  final List<ShaderPass> passes;
  final int activePassIndex;
  final ValueChanged<int> onSelectPass;
  final ValueChanged<PassType> onAddPass;
  final ValueChanged<PassType> onRemovePass;
  final bool showInputs;
  final VoidCallback onToggleInputs;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback onCompile;

  static IconData iconForPassType(PassType type) {
    switch (type) {
      case PassType.image:
        return Icons.image;
      case PassType.common:
        return Icons.code;
      case PassType.bufferA:
      case PassType.bufferB:
      case PassType.bufferC:
      case PassType.bufferD:
        return Icons.layers;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        border: Border(
          bottom: BorderSide(color: Color(0xFFD98200), width: 2),
        ),
      ),
      child: Row(
        children: [
          // "+" Add Tab Button
          Container(
            margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2E2E36),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: PopupMenuButton<PassType>(
              tooltip: 'Add Tab',
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              padding: EdgeInsets.zero,
              color: const Color(0xFF1F1F28),
              itemBuilder: (context) {
                const addableTypes = [
                  PassType.common,
                  PassType.bufferA,
                  PassType.bufferB,
                  PassType.bufferC,
                  PassType.bufferD,
                ];
                final existing = passes.map((p) => p.type).toSet();
                final available =
                    addableTypes.where((t) => !existing.contains(t)).toList();

                if (available.isEmpty) {
                  return [
                    const PopupMenuItem<PassType>(
                      enabled: false,
                      child: Text(
                        'All tabs added',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ];
                }

                return available.map((type) {
                  return PopupMenuItem<PassType>(
                    value: type,
                    child: Row(
                      children: [
                        Icon(
                          iconForPassType(type),
                          size: 16,
                          color: const Color(0xFFFF9900),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
              onSelected: onAddPass,
            ),
          ),

          // Pass Tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: passes.length,
              itemBuilder: (context, index) {
                final p = passes[index];
                final isSelected = index == activePassIndex;
                final isImage = p.type == PassType.image;

                return GestureDetector(
                  onTap: () => onSelectPass(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4, top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFD98200)
                          : const Color(0xFF383842),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFB347)
                            : Colors.white10,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          iconForPassType(p.type),
                          size: 14,
                          color: isSelected ? Colors.black87 : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.name,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isImage) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => onRemovePass(p.type),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: isSelected
                                    ? Colors.black87
                                    : Colors.white60,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Inputs button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF383842)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: Icon(
              showInputs ? Icons.expand_less : Icons.tune,
              size: 16,
            ),
            label: const Text('Inputs', style: TextStyle(fontSize: 12)),
            onPressed: onToggleInputs,
          ),

          const SizedBox(width: 4),

          // Play / Pause button in editor header
          IconButton(
            iconSize: 20,
            icon: Icon(
              isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: isPlaying
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF4ADE80),
            ),
            tooltip: isPlaying
                ? 'Pause Shader (Space)'
                : 'Play Shader (Space)',
            onPressed: onTogglePlay,
          ),

          // Compile button
          IconButton(
            iconSize: 18,
            icon: const Icon(Icons.bolt, color: Color(0xFF00E5FF)),
            tooltip: 'Compile & Run Shader (Alt + Enter)',
            onPressed: onCompile,
          ),
        ],
      ),
    );
  }
}
