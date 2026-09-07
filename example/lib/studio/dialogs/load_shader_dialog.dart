import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata wrapper for a ShaderToy JSON file discovered in the folder.
class _JsonFileInfo {
  _JsonFileInfo({
    required this.file,
    required this.fileName,
    this.project,
    this.errorMessage,
  });

  final File file;
  final String fileName;
  final ShaderToyProject? project;
  final String? errorMessage;
}

/// Dialog for loading shaders from the last used folder, disk, or raw JSON.
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
  static const String _kLastJsonFolderKey = 'last_json_folder_path';

  late final TabController _tabController;
  final TextEditingController _jsonInputController = TextEditingController();

  String? _currentFolderPath;
  List<_JsonFileInfo> _folderFiles = [];
  bool _isLoadingFolder = false;
  String? _loadingFile;
  String? _generalError;
  StreamSubscription<FileSystemEvent>? _dirWatcherSubscription;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (mounted && _currentFolderPath != null) {
          _scanFolder(_currentFolderPath!);
        }
      },
    );
    _initAndLoadFolder();
  }

  Future<void> _initAndLoadFolder() async {
    setState(() {
      _isLoadingFolder = true;
      _generalError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      String? folder = prefs.getString(_kLastJsonFolderKey);

      // If no folder stored yet or not existing, try common fallback paths
      if (!kIsWeb) {
        if (folder == null || !Directory(folder).existsSync()) {
          final candidates = [
            'example/shaders',
            'shaders',
            '../example/shaders',
          ];
          for (final candidate in candidates) {
            final d = Directory(candidate);
            if (d.existsSync()) {
              folder = d.absolute.path;
              break;
            }
          }
        }
      }

      if (folder != null) {
        await _scanFolder(folder);
      } else {
        if (mounted) {
          setState(() {
            _isLoadingFolder = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFolder = false;
          _generalError = 'Failed to read last folder setting: $e';
        });
      }
    }
  }

  void _setupDirWatcher(Directory dir) {
    _dirWatcherSubscription?.cancel();
    try {
      _dirWatcherSubscription = dir.watch().listen((event) {
        if (!mounted) return;
        _scanFolder(dir.path);
      });
    } catch (_) {
      // Directory watching might not be supported on all virtual file systems.
    }
  }

  Future<void> _scanFolder(String folderPath) async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _currentFolderPath = folderPath;
          _folderFiles = [];
          _isLoadingFolder = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingFolder = true;
        _currentFolderPath = folderPath;
        _generalError = null;
      });
    }

    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      if (mounted) {
        setState(() {
          _folderFiles = [];
          _isLoadingFolder = false;
          _generalError = 'Folder does not exist: $folderPath';
        });
      }
      return;
    }

    _setupDirWatcher(dir);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastJsonFolderKey, folderPath);

      final entities = dir
          .listSync(followLinks: true)
          .where((f) => f is File || f is Link)
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .map((f) => File(f.path))
          .toList();

      entities.sort((a, b) {
        final nameA = a.uri.pathSegments.last.toLowerCase();
        final nameB = b.uri.pathSegments.last.toLowerCase();
        return nameA.compareTo(nameB);
      });

      final List<_JsonFileInfo> filesInfo = [];
      for (final file in entities) {
        final fileName = file.uri.pathSegments.last;
        try {
          final content = await file.readAsString();
          final project = ShaderToyProject.parseJsonString(content);
          filesInfo.add(_JsonFileInfo(
            file: file,
            fileName: fileName,
            project: project,
          ));
        } catch (e) {
          filesInfo.add(_JsonFileInfo(
            file: file,
            fileName: fileName,
            errorMessage: e.toString(),
          ));
        }
      }

      if (mounted) {
        setState(() {
          _folderFiles = filesInfo;
          _isLoadingFolder = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFolder = false;
          _generalError = 'Error scanning folder "$folderPath": $e';
        });
      }
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final selectedDir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Folder with Shader JSON files',
        initialDirectory: _currentFolderPath,
      );
      if (selectedDir != null && selectedDir.isNotEmpty) {
        await _scanFolder(selectedDir);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generalError = 'Failed to choose folder: $e';
        });
      }
    }
  }

  Future<void> _loadFile(_JsonFileInfo item) async {
    setState(() {
      _loadingFile = item.fileName;
      _generalError = null;
    });

    try {
      final project = item.project ??
          ShaderToyProject.parseJsonString(await item.file.readAsString());
      if (mounted) {
        widget.onLoadProject(project);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingFile = null;
          _generalError = 'Failed to load "${item.fileName}": $e';
        });
      }
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select ShaderToy JSON',
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        initialDirectory: _currentFolderPath,
      );
      if (files.isEmpty) return;
      final file = files.first;
      final path = file.path;

      if (path != null && !kIsWeb) {
        final ioFile = File(path);
        final parentPath = ioFile.parent.path;
        await _scanFolder(parentPath);
      }

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
          _generalError = 'Failed to load file: $e';
        });
      }
    }
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
        _generalError = 'Invalid JSON: $e';
      });
    }
  }

  String _formatDisplayName(String fileName) {
    final base = fileName.replaceAll('.json', '');
    return base
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  @override
  void dispose() {
    _dirWatcherSubscription?.cancel();
    _lifecycleListener?.dispose();
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
                  Tab(icon: Icon(Icons.folder_open, size: 16), text: 'Folder Files'),
                  Tab(icon: Icon(Icons.code, size: 16), text: 'Paste JSON'),
                ],
              ),
              const SizedBox(height: 12),

              // Tab Views (takes available vertical space)
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFolderFilesTab(),
                    _buildPasteJsonTab(),
                  ],
                ),
              ),

              // Error display
              if (_generalError != null) ...[
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
                          _generalError!,
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

  Widget _buildFolderFilesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF101016),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF282836)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder, color: Color(0xFF00E5FF), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: _currentFolderPath ?? 'No folder selected',
                  child: Text(
                    _currentFolderPath ?? 'No folder selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _currentFolderPath != null
                          ? Colors.white70
                          : Colors.white30,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_currentFolderPath != null)
                IconButton(
                  tooltip: 'Refresh folder',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.refresh, color: Colors.white54),
                  onPressed: _isLoadingFolder
                      ? null
                      : () => _scanFolder(_currentFolderPath!),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.drive_file_move_outlined, size: 14),
                label: const Text('Change Folder', style: TextStyle(fontSize: 11)),
                onPressed: _chooseFolder,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Files List / Loading / Empty state
        Expanded(
          child: _isLoadingFolder
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00E5FF),
                  ),
                )
              : _folderFiles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.folder_open_outlined,
                              size: 48,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No Shader JSON files found',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Choose a folder containing ShaderToy .json files or load a file from disk.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E5FF),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  icon: const Icon(Icons.folder_open, size: 16),
                                  label: const Text(
                                    'Choose Folder',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _chooseFolder,
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF38BDF8),
                                    side: const BorderSide(color: Color(0xFF38BDF8)),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                                  label: const Text('Load from disk'),
                                  onPressed: _loadFromDisk,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _folderFiles.length,
                      itemBuilder: (context, index) {
                        final item = _folderFiles[index];
                        final isInvalid = item.errorMessage != null;
                        final proj = item.project;
                        final title = proj != null && proj.name.isNotEmpty
                            ? proj.name
                            : _formatDisplayName(item.fileName);
                        final desc = isInvalid
                            ? 'Invalid ShaderToy JSON file'
                            : proj?.description.isNotEmpty == true
                                ? proj!.description
                                : 'Shader project in ${item.fileName}';
                        final passCount = proj?.passes.length ?? 0;
                        final usesAudio = proj?.usesAudio ?? false;
                        final usesTextures = proj?.usesTextures ?? false;
                        final usesMouse = proj?.usesMouse ?? false;
                        final usesMic = proj?.usesMic ?? false;
                        final usesKeys = proj?.usesKeys ?? false;
                        final isSelected = _loadingFile == item.fileName;

                        return Card(
                          color: const Color(0xFF20202A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isInvalid
                                  ? const Color(0xFF7F1D1D)
                                  : const Color(0xFF2E2E3C),
                            ),
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
                                color: isInvalid
                                    ? const Color(0xFFF87171).withValues(alpha: 0.12)
                                    : const Color(0xFF00E5FF).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isInvalid
                                      ? const Color(0xFFF87171).withValues(alpha: 0.3)
                                      : const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(
                                isInvalid
                                    ? Icons.warning_amber_rounded
                                    : Icons.auto_awesome,
                                color: isInvalid
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFF00E5FF),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                color: isInvalid
                                    ? const Color(0xFFF87171)
                                    : Colors.white,
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
                                  style: TextStyle(
                                    color: isInvalid
                                        ? const Color(0xFFFCA5A5)
                                        : Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (!isInvalid) ...[
                                      _buildFeatureBadge(
                                        '$passCount pass${passCount > 1 ? 'es' : ''}',
                                        const Color(0xFF00E5FF),
                                      ),
                                      if (usesAudio)
                                        _buildFeatureBadge(
                                          'audio',
                                          const Color(0xFFFFB300),
                                        ),
                                      if (usesTextures)
                                        _buildFeatureBadge(
                                          'texture',
                                          const Color(0xFF40C4FF),
                                        ),
                                      if (usesMouse)
                                        _buildFeatureBadge(
                                          'mouse',
                                          const Color(0xFFB388FF),
                                        ),
                                      if (usesMic)
                                        _buildFeatureBadge(
                                          'mic',
                                          const Color(0xFFFF5252),
                                        ),
                                      if (usesKeys)
                                        _buildFeatureBadge(
                                          'keys',
                                          const Color(0xFF69F0AE),
                                        ),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        item.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white24,
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: isInvalid
                                    ? const Color(0xFF383848)
                                    : const Color(0xFF00E5FF),
                                foregroundColor:
                                    isInvalid ? Colors.white38 : Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              onPressed: (isSelected || isInvalid)
                                  ? null
                                  : () => _loadFile(item),
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
                    ),
        ),
      ],
    );
  }

  Widget _buildFeatureBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
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
