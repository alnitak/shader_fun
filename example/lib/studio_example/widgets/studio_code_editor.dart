import 'package:flutter/material.dart';

/// Synchronized code editor with line number gutter, compilation status banner, and character count.
class StudioCodeEditor extends StatelessWidget {
  const StudioCodeEditor({
    super.key,
    required this.codeController,
    required this.editorScrollController,
    required this.gutterScrollController,
    required this.fontSize,
    required this.lineCount,
    required this.compileSuccess,
    required this.compileStatus,
    required this.hasError,
    required this.lastError,
    required this.onCodeChanged,
  });

  final TextEditingController codeController;
  final ScrollController editorScrollController;
  final ScrollController gutterScrollController;
  final double fontSize;
  final int lineCount;
  final bool compileSuccess;
  final String compileStatus;
  final bool hasError;
  final String? lastError;
  final ValueChanged<String> onCodeChanged;

  Widget _buildLineNumberGutter(BuildContext context) {
    final gutterWidth = lineCount >= 1000 ? 52.0 : 44.0;

    return Container(
      width: gutterWidth,
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        border: Border(right: BorderSide(color: Color(0xFF22222A), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: gutterScrollController,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemExtent: fontSize * 1.45,
          itemCount: lineCount,
          itemBuilder: (context, i) {
            return Container(
              height: fontSize * 1.45,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize * 0.9,
                  color: Colors.white.withValues(alpha: 0.35),
                  height: 1.45,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Editor area with line numbers gutter
        Expanded(
          child: Container(
            color: const Color(0xFF181820),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLineNumberGutter(context),
                Expanded(
                  child: TextField(
                    controller: codeController,
                    scrollController: editorScrollController,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: fontSize,
                      color: const Color(0xFFE2E8F0),
                      height: 1.45,
                    ),
                    cursorColor: const Color(0xFFFF5500),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: onCodeChanged,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Error banner directly below the editor when code is broken
        if (!compileSuccess && hasError)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF2E0F14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error,
                    color: Color(0xFFEF4444),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    '❌ Shader error:\n$lastError',
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Editor status & compilation log bar
        Container(
          height: 24,
          color: const Color(0xFF121217),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                compileSuccess ? Icons.check_circle : Icons.error,
                size: 13,
                color: compileSuccess
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: lastError ?? compileStatus,
                  child: Text(
                    compileStatus,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: compileSuccess
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFEF4444),
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: compileSuccess
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Chars: ${codeController.text.length}  |  Lines: ${codeController.text.split('\n').length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
