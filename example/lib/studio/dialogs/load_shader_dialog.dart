import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Dialog for loading shaders from presets, disk, or raw JSON.
///
/// Responsive standard Dialog that utilizes the maximum available height.
class LoadShaderDialog extends StatefulWidget {
  const LoadShaderDialog({
    super.key,
    required this.onLoadProject,
  });

  final ValueChanged<ShaderToyProject> onLoadProject;

  @override
  State<LoadShaderDialog> createState() => _LoadShaderDialogState();
}

class _LoadShaderDialogState extends State<LoadShaderDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _jsonInputController = TextEditingController();
  final Map<String, ShaderToyProject> _loadedPresets = {};
  String? _loadingAsset;
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPresetMetadata();
  }

  Future<void> _loadPresetMetadata() async {
    for (final fileName in ShaderToyProject.exampleAssets) {
      try {
        final proj = await ShaderToyProject.loadFromAsset(fileName);
        if (mounted) {
          setState(() {
            _loadedPresets[fileName] = proj;
          });
        }
      } catch (_) {
        // Fall back gracefully to filename-based display
      }
    }
  }

  Future<void> _choosePreset(String fileName) async {
    setState(() {
      _loadingAsset = fileName;
      _jsonError = null;
    });

    try {
      final project = _loadedPresets[fileName] ??
          await ShaderToyProject.loadFromAsset(fileName);
      if (mounted) {
        widget.onLoadProject(project);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAsset = null;
          _jsonError = 'Failed to load asset "$fileName": $e';
        });
      }
    }
  }

  String _formatDisplayName(String fileName) {
    final base = fileName.split('/').last.replaceAll('.json', '');
    return base
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  void _loadFromJsonString() {
    final text = _jsonInputController.text.trim();
    if (text.isEmpty) return;

    try {
      final project = ShaderToyProject.parseJsonString(text);
      widget.onLoadProject(project);
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _jsonError = 'Invalid JSON: $e';
      });
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select ShaderToy JSON',
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes);
      if (content.isEmpty) return;
      final project = ShaderToyProject.parseJsonString(content);
      if (mounted) {
        widget.onLoadProject(project);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _jsonError = 'Failed to load file: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _jsonInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = min(screenSize.width - 48, 760.0);
    final dialogHeight = max(360.0, screenSize.height - 48);

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
                  const Icon(Icons.folder_open, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 8),
                  const Text(
                    'Load Shader Project',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Load from disk button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text(
                      'Load from disk',
                      style: TextStyle(fontSize: 12),
                    ),
                    onPressed: _loadFromDisk,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF00E5FF),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(icon: Icon(Icons.auto_awesome, size: 16), text: 'Presets'),
                  Tab(icon: Icon(Icons.code, size: 16), text: 'Paste JSON'),
                ],
              ),
              const SizedBox(height: 12),

              // Tab Views (takes available vertical space)
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPresetsTab(),
                    _buildPasteJsonTab(),
                  ],
                ),
              ),

              // Error display
              if (_jsonError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D1515),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF7F1D1D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFF87171),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _jsonError!,
                          style: const TextStyle(
                            color: Color(0xFFF87171),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetsTab() {
    return ListView.builder(
      itemCount: ShaderToyProject.exampleAssets.length,
      itemBuilder: (context, index) {
        final fileName = ShaderToyProject.exampleAssets[index];
        final proj = _loadedPresets[fileName];
        final title = proj?.name.isNotEmpty == true
            ? proj!.name
            : _formatDisplayName(fileName);
        final desc = proj?.description.isNotEmpty == true
            ? proj!.description
            : 'Example preset loaded from $fileName';
        final passCount = proj?.passes.length ?? 1;
        final isSelected = _loadingAsset == fileName;

        return Card(
          color: const Color(0xFF20202A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF2E2E3C)),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF00E5FF),
                size: 20,
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E2E3E),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '$passCount pass${passCount > 1 ? 'es' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: isSelected ? null : () => _choosePreset(fileName),
              child: isSelected
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Load',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPasteJsonTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101016),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF282836)),
            ),
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _jsonInputController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFE2E8F0),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'Paste Shadertoy project JSON here (from Shadertoy.com export or saved JSON)...',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text(
              'Load Pasted JSON',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _loadFromJsonString,
          ),
        ),
      ],
    );
  }
}
