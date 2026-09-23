import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

/// Specialized [CodeController] for GLSL shader code that normalizes
/// foldable blocks:
/// - Places folding handles on function/statement declarations rather than on standalone '{' lines.
/// - Keeps brace blocks ('{ ... }') and multiline comments ('/* ... */'), filtering out
///   distracting parentheses and bracket folding.
class GlslCodeController extends CodeController {
  GlslCodeController({
    super.text,
    super.language,
    super.analyzer,
    super.namedSectionParser,
    super.readOnlySectionNames,
    super.visibleSectionNames,
    super.patternMap,
    super.params,
    super.modifiers,
  }) {
    _normalizeFoldableBlocks();
    addListener(_normalizeFoldableBlocks);
  }

  @override
  void dispose() {
    removeListener(_normalizeFoldableBlocks);
    super.dispose();
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue;
    _normalizeFoldableBlocks();
  }

  @override
  set fullText(String fullText) {
    super.fullText = fullText;
    _normalizeFoldableBlocks();
  }

  void _normalizeFoldableBlocks() {
    final blocks = code.foldableBlocks;
    final lines = code.lines;

    // Filter out parentheses and brackets folding - only keep braces and comments
    blocks.removeWhere((b) =>
        b.type == FoldableBlockType.parentheses ||
        b.type == FoldableBlockType.brackets);

    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type == FoldableBlockType.braces) {
        if (b.firstLine < lines.length) {
          final lineText = lines[b.firstLine].text.trim();
          // If the line only contains the opening brace (e.g. Allman/C style)
          if (lineText == '{' && b.firstLine > 0) {
            // Find previous non-empty line (e.g. function signature or if/for condition)
            int prevLine = b.firstLine - 1;
            while (prevLine > 0 && lines[prevLine].text.trim().isEmpty) {
              prevLine--;
            }
            if (prevLine >= 0 && !lines[prevLine].text.trim().endsWith('{')) {
              blocks[i] = FoldableBlock(
                firstLine: prevLine,
                lastLine: b.lastLine,
                type: b.type,
              );
            }
          }
        }
      }
    }
  }
}

/// Code editor powered by flutter_code_editor with syntax highlighting,
/// line numbers gutter, compilation status banner, and character/line counter.
class StudioCodeEditor extends StatelessWidget {
  const StudioCodeEditor({
    super.key,
    required this.codeController,
    required this.fontSize,
    required this.compileSuccess,
    required this.compileStatus,
    required this.hasError,
    required this.lastError,
    this.onCodeChanged,
  });

  final CodeController codeController;
  final double fontSize;
  final bool compileSuccess;
  final String compileStatus;
  final bool hasError;
  final String? lastError;
  final ValueChanged<String>? onCodeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Editor area with line numbers gutter provided by flutter_code_editor
        Expanded(
          child: Container(
            color: const Color(0xFF181820),
            child: CodeTheme(
              data: CodeThemeData(styles: monokaiSublimeTheme),
              child: CodeField(
                controller: codeController,
                expands: true,
                wrap: false,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize,
                  height: 1.5,
                ),
                cursorColor: const Color(0xFFFF5500),
                background: const Color(0xFF181820),
                gutterStyle: GutterStyle(
                  background: const Color(0xFF14141A),
                  textStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: fontSize,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                onChanged: onCodeChanged,
              ),
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
                  child: Icon(Icons.error, color: Color(0xFFEF4444), size: 14),
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
                      fontWeight:
                          compileSuccess ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ListenableBuilder(
                listenable: codeController,
                builder: (context, _) {
                  final text = codeController.text;
                  final lines = text.isEmpty ? 1 : text.split('\n').length;
                  return Text(
                    'Chars: ${text.length}  |  Lines: $lines',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
