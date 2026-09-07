import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shader_fun/shader_fun.dart';

/// Dialog for editing shader metadata and exporting/saving to JSON.
///
/// Responsive standard Dialog that utilizes the maximum available height.
class SaveShaderDialog extends StatefulWidget {
  const SaveShaderDialog({
    super.key,
    required this.project,
  });

  final ShaderToyProject project;

  @override
  State<SaveShaderDialog> createState() => _SaveShaderDialogState();
}

class _SaveShaderDialogState extends State<SaveShaderDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _urlController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _usernameController = TextEditingController(text: widget.project.author);
    _descriptionController =
        TextEditingController(text: widget.project.description);
    _urlController = TextEditingController(text: widget.project.url);
    _tagsController =
        TextEditingController(text: widget.project.tags.join(', '));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _syncProjectFields() {
    widget.project.name = _nameController.text.trim();
    widget.project.author = _usernameController.text.trim();
    widget.project.description = _descriptionController.text.trim();
    widget.project.url = _urlController.text.trim();
    final rawTags = _tagsController.text.split(',');
    widget.project.tags = rawTags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  void _copyToClipboard() {
    _syncProjectFields();
    final jsonString = widget.project.toJsonString();
    Clipboard.setData(ClipboardData(text: jsonString));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Shader JSON copied to clipboard!'),
        backgroundColor: Color(0xFFFF5500),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveAsFile() async {
    _syncProjectFields();
    final jsonString = widget.project.toJsonString();

    String safeName = widget.project.name.trim();
    if (safeName.isEmpty) safeName = 'shader';
    safeName = safeName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName = '$safeName.json';

    try {
      final outputUri = await FilePicker.saveFile(
        dialogTitle: 'Save Shader JSON',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(jsonString)),
      );

      if (outputUri != null) {
        if (!kIsWeb) {
          try {
            final filePath = outputUri.hasScheme && outputUri.isScheme('file')
                ? outputUri.toFilePath()
                : outputUri.path;
            final file = File(filePath);
            await file.writeAsString(jsonString);
            final parentFolder = file.parent.absolute.path;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('last_json_folder_path', parentFolder);
          } catch (_) {
            // Ignore if direct filesystem write fails
          }
        }

        if (mounted) {
          final displayName = outputUri.pathSegments.isNotEmpty
              ? outputUri.pathSegments.last
              : outputUri.toString();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Shader saved successfully to $displayName!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.2),
        fontSize: 12,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: const Color(0xFF101015),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF282832)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF282832)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFFF5500)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncProjectFields();
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = min(screenSize.width - 48, 800.0);
    final dialogHeight = max(400.0, screenSize.height - 48);
    final jsonString = widget.project.toJsonString();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: const Color(0xFF181822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF323242)),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.save, color: Color(0xFFFF5500)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Save Shader: "${widget.project.name.isEmpty ? 'Untitled' : widget.project.name}" (JSON)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Form fields & JSON Preview (Scrollable content)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Form fields row 1: Name and Author
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: _fieldDecoration('Shader Name'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration:
                                  _fieldDecoration('Username / Author'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // URL field
                      TextField(
                        controller: _urlController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration(
                          'URL / Project Link',
                          hint: 'https://shadertoy.com/view/...',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),

                      // Description field
                      TextField(
                        controller: _descriptionController,
                        maxLines: 2,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('Description'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),

                      // Tags field
                      TextField(
                        controller: _tagsController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration(
                          'Tags (comma separated)',
                          hint: '3d, raymarching, audio',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),

                      // Formatted JSON Preview Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'JSON Preview',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${jsonString.length} bytes',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // JSON Preview Container
                      Container(
                        height: max(
                          200.0,
                          dialogHeight - 340.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101016),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF282836)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            jsonString,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Actions Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF383848)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy JSON'),
                    onPressed: _copyToClipboard,
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5500),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.save_alt, size: 16),
                    label: const Text(
                      'Save as...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _saveAsFile,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
