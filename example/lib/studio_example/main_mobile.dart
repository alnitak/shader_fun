import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShaderToyMobileApp());
}

/// Minimal mobile application displaying full-screen shaders with a shader picker overlay.
///
/// Use this example to see how to use shader_fun on mobile instead of the studio_example/main.dart.
class ShaderToyMobileApp extends StatelessWidget {
  const ShaderToyMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shader_fun mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5500),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF181822),
        ),
      ),
      home: const ShaderToyMobileScreen(),
    );
  }
}

class _ShaderOption {
  const _ShaderOption({
    required this.id,
    required this.label,
    required this.project,
  });

  final String id;
  final String label;
  final ShaderProject project;
}

/// Full-screen shader viewport with a floating dropdown to switch between bundled shaders.
class ShaderToyMobileScreen extends StatefulWidget {
  const ShaderToyMobileScreen({super.key});

  @override
  State<ShaderToyMobileScreen> createState() => _ShaderToyMobileScreenState();
}

class _ShaderToyMobileScreenState extends State<ShaderToyMobileScreen>
    with SingleTickerProviderStateMixin {
  static const String _defaultOptionId = '__default__';

  late final ShaderController _controller;
  late final _ShaderOption _defaultOption;
  List<_ShaderOption> _options = const [];
  String _selectedShaderId = _defaultOptionId;
  bool _isLoadingShaders = true;

  @override
  void initState() {
    super.initState();
    final initialProject = ShaderProject.empty();
    _defaultOption = _ShaderOption(
      id: _defaultOptionId,
      label: 'Default Starter Shader',
      project: initialProject,
    );
    _options = [_defaultOption];

    _controller = ShaderController(
      initialProject: initialProject,
      vsync: this,
      autoPlay: true,
    );
    _controller.play();
    _controller.addListener(_onControllerUpdate);

    _loadAvailableShaders();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableShaders() async {
    final loaded = await _discoverAssetShaders();
    if (loaded.isEmpty && !kIsWeb) {
      loaded.addAll(await _discoverDiskShaders());
    }

    if (!mounted) return;

    final nextOptions = [_defaultOption, ...loaded];
    setState(() {
      _options = nextOptions;
      _isLoadingShaders = false;
    });

    if (loaded.isNotEmpty && _selectedShaderId == _defaultOptionId) {
      await _selectShader(loaded.first.id);
    }
  }

  Future<List<_ShaderOption>> _discoverAssetShaders() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetPaths =
          manifest.listAssets().where((key) {
            final lower = key.toLowerCase();
            return (lower.startsWith('shaders/') ||
                    lower.startsWith('assets/shaders/')) &&
                lower.endsWith('.json');
          }).toList()..sort((a, b) {
            final nameA = a.split('/').last.toLowerCase();
            final nameB = b.split('/').last.toLowerCase();
            return nameA.compareTo(nameB);
          });

      final options = <_ShaderOption>[];
      for (final assetPath in assetPaths) {
        try {
          final project = await ShaderProject.loadFromAsset(assetPath);
          final fileName = assetPath.split('/').last;
          options.add(
            _ShaderOption(
              id: assetPath,
              label: _resolveLabel(project, fileName),
              project: project,
            ),
          );
        } catch (e) {
          debugPrint('Skipping unreadable shader asset $assetPath: $e');
        }
      }
      return options;
    } catch (e) {
      debugPrint('Failed to inspect AssetManifest for shaders: $e');
      return [];
    }
  }

  Future<List<_ShaderOption>> _discoverDiskShaders() async {
    for (final candidate in const ['shaders', 'example/shaders']) {
      final dir = Directory(candidate);
      if (!dir.existsSync()) continue;

      final files =
          dir
              .listSync(followLinks: true)
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.json'))
              .toList()
            ..sort((a, b) {
              final nameA = a.uri.pathSegments.last.toLowerCase();
              final nameB = b.uri.pathSegments.last.toLowerCase();
              return nameA.compareTo(nameB);
            });

      final options = <_ShaderOption>[];
      for (final file in files) {
        try {
          final content = await file.readAsString();
          final project = ShaderProject.parseJsonString(content);
          final fileName = file.uri.pathSegments.last;
          options.add(
            _ShaderOption(
              id: file.path,
              label: _resolveLabel(project, fileName),
              project: project,
            ),
          );
        } catch (e) {
          debugPrint('Skipping unreadable shader file ${file.path}: $e');
        }
      }
      return options;
    }
    return [];
  }

  String _resolveLabel(ShaderProject project, String fileName) {
    final trimmedName = project.name.trim();
    if (trimmedName.isNotEmpty && trimmedName != 'New Shader') {
      return trimmedName;
    }
    final base = fileName.replaceAll(
      RegExp(r'\.json$', caseSensitive: false),
      '',
    );
    return base
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<void> _selectShader(String? shaderId) async {
    if (shaderId == null || shaderId == _selectedShaderId) return;

    final matchIndex = _options.indexWhere((o) => o.id == shaderId);
    if (matchIndex < 0) return;
    final option = _options[matchIndex];

    setState(() {
      _selectedShaderId = shaderId;
    });

    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.disposeAllSources();
    }
    await _controller.loadProject(option.project);
    _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final dropdownValue = _options.any((o) => o.id == _selectedShaderId)
        ? _selectedShaderId
        : _options.first.id;

    return SafeArea(
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: ShaderViewport(controller: _controller)),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14141C).withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            color: Color(0xFF00E5FF),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: dropdownValue,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1A1A24),
                                iconEnabledColor: Colors.white70,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                onChanged: _selectShader,
                                items: [
                                  for (final option in _options)
                                    DropdownMenuItem<String>(
                                      value: option.id,
                                      child: Text(
                                        option.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_isLoadingShaders) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
