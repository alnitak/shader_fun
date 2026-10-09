import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

/// Specialized [CodeController] for GLSL shader code that normalizes
/// foldable blocks and handles complete shader code reloads cleanly without
/// diffing corruption or folding inheritance:
/// - Places folding handles on function/statement declarations rather than on standalone '{' lines.
/// - Keeps brace blocks ('{ ... }') and multiline comments ('/* ... */'), filtering out
///   distracting parentheses and bracket folding.
/// - Overrides [text] and [fullText] via [loadCode] to prevent [CodeController]'s internal
///   typing diff algorithm from corrupting or truncating code headers/prefixes when switching shaders.
/// - Clears and unfolds any previously folded blocks when loading new code.
/// - Exposes [loadNotifier] so the editor viewport resets its scroll offset to line 1 on load.
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
    _isInitialized = true;
    _normalizeFoldableBlocks();
    addListener(_normalizeFoldableBlocks);
  }

  bool _isInitialized = false;
  final ValueNotifier<int> _loadNotifier = ValueNotifier<int>(0);

  /// Listenable triggered whenever fresh shader code is loaded (not while typing).
  ValueListenable<int> get loadNotifier => _loadNotifier;

  /// Current load revision counter.
  int get loadCount => _loadNotifier.value;

  @override
  void dispose() {
    removeListener(_normalizeFoldableBlocks);
    _loadNotifier.dispose();
    super.dispose();
  }

  /// Sets shader code cleanly without incremental diffing or folding inheritance.
  ///
  /// Standard [TextEditingController.text] calls [set value] under the hood,
  /// which in [CodeController] runs incremental diffing algorithm (`getEditResult`).
  /// When switching shaders or loading a new shader, diffing against previous code
  /// can cause truncation or corruption at the start of the shader.
  /// Calling [loadCode] bypasses diffing, unfolds all blocks, resets selection
  /// to the start of the file, and bumps [loadCount] so the viewport resets scroll to line 1.
  void loadCode(String newCode, {bool resetSelection = true}) {
    unfoldAll();
    super.fullText = newCode;
    unfoldAll();
    if (resetSelection) {
      value = value.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    _loadNotifier.value++;
    _normalizeFoldableBlocks();
  }

  @override
  set text(String newText) {
    if (!_isInitialized) {
      super.text = newText;
      return;
    }
    loadCode(newText);
  }

  @override
  set fullText(String fullText) {
    if (!_isInitialized) {
      super.fullText = fullText;
      return;
    }
    loadCode(fullText);
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue;
    _normalizeFoldableBlocks();
  }

  /// Inserts [str] into the editor text at current selection using standard
  /// editing value diffing, bypassing [text] setter so [loadNotifier] is not
  /// triggered, folding is preserved, and the scroll position does not reset to top.
  @override
  void insertStr(String str) {
    final sel = selection;
    if (sel.start < 0 || sel.end < 0) return;
    final newText = text.replaceRange(sel.start, sel.end, str);
    final len = str.length;
    super.value = TextEditingValue(
      text: newText,
      selection: sel.copyWith(
        baseOffset: sel.start + len,
        extentOffset: sel.start + len,
      ),
    );
  }

  @override
  void removeChar() {
    if (selection.start < 1) return;
    final sel = selection;
    final newText = text.replaceRange(sel.start - 1, sel.start, '');
    super.value = TextEditingValue(
      text: newText,
      selection: sel.copyWith(
        baseOffset: sel.start - 1,
        extentOffset: sel.start - 1,
      ),
    );
  }

  @override
  void removeSelection() {
    final sel = selection;
    if (sel.start < 0 || sel.end < 0) return;
    final newText = text.replaceRange(sel.start, sel.end, '');
    super.value = TextEditingValue(
      text: newText,
      selection: sel.copyWith(
        baseOffset: sel.start,
        extentOffset: sel.start,
      ),
    );
  }

  @override
  KeyEventResult onKey(KeyEvent event) {
    // Intercept Tab to insert tab spaces (or indent/outdent) and prevent
    // Flutter's FocusTraversalGroup from moving focus away from the editor.
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          outdentSelection();
        } else if (popupController.shouldShow) {
          insertSelectedWord();
        } else {
          indentSelection();
        }
      }
      return KeyEventResult.handled;
    }

    // Route Numpad Enter through onEnterKeyAction (unless compile shortcuts with Alt/Cmd/Ctrl are held)
    if (event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final isModPressed = HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (!isModPressed) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          onEnterKeyAction();
        }
        return KeyEventResult.handled;
      }
    }

    // Intercept Home key to move caret to start of line (instead of scrolling to top of document)
    if (event.logicalKey == LogicalKeyboardKey.home) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _handleHomeKey();
      }
      return KeyEventResult.handled;
    }

    // Intercept End key to move caret to end of line (instead of scrolling to bottom of document)
    if (event.logicalKey == LogicalKeyboardKey.end) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _handleEndKey();
      }
      return KeyEventResult.handled;
    }

    return super.onKey(event);
  }

  void _handleHomeKey() {
    if (text.isEmpty) return;
    final pos = selection.extentOffset.clamp(0, text.length);
    final isDocBoundary = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final int target;
    if (isDocBoundary) {
      target = 0;
    } else {
      final lineStart = pos > 0 ? text.lastIndexOf('\n', pos - 1) + 1 : 0;
      var firstNonWs = lineStart;
      while (firstNonWs < text.length &&
          (text[firstNonWs] == ' ' || text[firstNonWs] == '\t') &&
          text[firstNonWs] != '\n') {
        firstNonWs++;
      }

      // If already at first non-whitespace character, toggle to column 0; otherwise jump to first non-ws
      if (pos == firstNonWs) {
        target = lineStart;
      } else {
        target = firstNonWs;
      }
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      selection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: target,
      );
    } else {
      selection = TextSelection.collapsed(offset: target);
    }
  }

  void _handleEndKey() {
    if (text.isEmpty) return;
    final pos = selection.extentOffset.clamp(0, text.length);
    final isDocBoundary = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final int target;
    if (isDocBoundary) {
      target = text.length;
    } else {
      final nextNewline = text.indexOf('\n', pos);
      target = nextNewline == -1 ? text.length : nextNewline;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      selection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: target,
      );
    } else {
      selection = TextSelection.collapsed(offset: target);
    }
  }

  /// Unfolds all currently folded blocks so hidden lines are fully visible.
  void unfoldAll() {
    for (final block in [...code.foldedBlocks]) {
      unfoldAt(block.firstLine);
    }
  }

  void _normalizeFoldableBlocks() {
    final blocks = code.foldableBlocks;
    final lines = code.lines;

    // Filter out parentheses and brackets folding - only keep braces and comments
    blocks.removeWhere(
      (b) =>
          b.type == FoldableBlockType.parentheses ||
          b.type == FoldableBlockType.brackets,
    );

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
            if (prevLine >= 0 &&
                lines[prevLine].text.trim().isNotEmpty &&
                !lines[prevLine].text.trim().endsWith('{')) {
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
    final glslController = codeController is GlslCodeController
        ? codeController as GlslCodeController
        : null;

    Widget buildCodeField([int? loadCount]) {
      return CodeField(
        key: loadCount != null ? ValueKey('code_field_$loadCount') : null,
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
      );
    }

    return Column(
      children: [
        // Editor area with line numbers gutter provided by flutter_code_editor
        Expanded(
          child: Container(
            color: const Color(0xFF181820),
            child: CodeTheme(
              data: CodeThemeData(styles: monokaiSublimeTheme),
              child: glslController != null
                  ? ValueListenableBuilder<int>(
                      valueListenable: glslController.loadNotifier,
                      builder: (context, count, _) => buildCodeField(count),
                    )
                  : buildCodeField(),
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
                      fontWeight: compileSuccess
                          ? FontWeight.normal
                          : FontWeight.bold,
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
