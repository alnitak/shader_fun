import 'package:flutter/material.dart';

/// Synchronized code editor with line number gutter, compilation status banner, and character count.
class StudioCodeEditor extends StatefulWidget {
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

  @override
  State<StudioCodeEditor> createState() => _StudioCodeEditorState();
}

class _StudioCodeEditorState extends State<StudioCodeEditor> {
  late final TextEditingController _lineNumbersController;

  static String _generateLineNumbers(int count) {
    return List.generate(count, (i) => '${i + 1}').join('\n');
  }

  @override
  void initState() {
    super.initState();
    _lineNumbersController = TextEditingController(
      text: _generateLineNumbers(widget.lineCount),
    );
  }

  @override
  void didUpdateWidget(covariant StudioCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lineCount != oldWidget.lineCount) {
      _lineNumbersController.text = _generateLineNumbers(widget.lineCount);
    }
  }

  @override
  void dispose() {
    _lineNumbersController.dispose();
    super.dispose();
  }

  Widget _buildLineNumberGutter(BuildContext context) {
    final gutterWidth = widget.lineCount >= 1000 ? 52.0 : 44.0;

    return Container(
      width: gutterWidth,
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        border: Border(right: BorderSide(color: Color(0xFF22222A), width: 1)),
      ),
      child: TextField(
        controller: _lineNumbersController,
        scrollController: widget.gutterScrollController,
        readOnly: true,
        enableInteractiveSelection: false,
        canRequestFocus: false,
        showCursor: false,
        maxLines: null,
        expands: true,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: widget.fontSize,
          color: Colors.white.withValues(alpha: 0.35),
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(0, 12, 8, 12),
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
                    controller: widget.codeController,
                    scrollController: widget.editorScrollController,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: widget.fontSize,
                      color: const Color(0xFFE2E8F0),
                    ),
                    cursorColor: const Color(0xFFFF5500),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: widget.onCodeChanged,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Error banner directly below the editor when code is broken
        if (!widget.compileSuccess && widget.hasError)
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
                    '❌ Shader error:\n${widget.lastError}',
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
                widget.compileSuccess ? Icons.check_circle : Icons.error,
                size: 13,
                color: widget.compileSuccess
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: widget.lastError ?? widget.compileStatus,
                  child: Text(
                    widget.compileStatus,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.compileSuccess
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFEF4444),
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: widget.compileSuccess
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Chars: ${widget.codeController.text.length}  |  Lines: ${widget.codeController.text.split('\n').length}',
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
