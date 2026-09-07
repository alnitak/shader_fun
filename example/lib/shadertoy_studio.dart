import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shader_fun/shader_fun.dart';

import 'shader_presets.dart';

/// Complete ShaderToy Studio interface mimicking the official ShaderToy web experience.
class ShaderToyStudio extends StatefulWidget {
  const ShaderToyStudio({super.key, this.initialProject});

  final ShaderToyProject? initialProject;

  @override
  State<ShaderToyStudio> createState() => _ShaderToyStudioState();
}

class _ShaderToyStudioState extends State<ShaderToyStudio>
    with SingleTickerProviderStateMixin {
  late final ShaderToyController _controller;
  final TextEditingController _codeEditorController = TextEditingController();
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();

  bool _showInputs = false;
  bool _isFullscreen = false;
  String _compileStatus = 'Ready';
  bool _compileSuccess = true;
  final double _fontSize = 13.0;
  final GlobalKey _viewportKey = GlobalKey();
  bool _isSyncingScroll = false;
  int _cachedLineCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = ShaderToyController(
      initialProject:
          widget.initialProject ?? ShaderPresets.raymarchingPrimitives(),
      vsync: this,
      autoPlay: true,
    );
    _controller.play();

    _syncCodeWithActivePass();
    _controller.addListener(_onControllerUpdate);
    _editorScrollController.addListener(_onEditorScroll);
    _gutterScrollController.addListener(_onGutterScroll);
    _codeEditorController.addListener(_onCodeChanged);
  }

  void _onEditorScroll() {
    if (_isSyncingScroll) return;
    if (_gutterScrollController.hasClients &&
        _editorScrollController.hasClients) {
      _isSyncingScroll = true;
      final maxGutter = _gutterScrollController.position.maxScrollExtent;
      final target = _editorScrollController.offset.clamp(0.0, maxGutter);
      if ((_gutterScrollController.offset - target).abs() > 0.01) {
        _gutterScrollController.jumpTo(target);
      }
      _isSyncingScroll = false;
    }
  }

  void _onGutterScroll() {
    if (_isSyncingScroll) return;
    if (_editorScrollController.hasClients &&
        _gutterScrollController.hasClients) {
      _isSyncingScroll = true;
      final maxEditor = _editorScrollController.position.maxScrollExtent;
      final target = _gutterScrollController.offset.clamp(0.0, maxEditor);
      if ((_editorScrollController.offset - target).abs() > 0.01) {
        _editorScrollController.jumpTo(target);
      }
      _isSyncingScroll = false;
    }
  }

  void _onCodeChanged() {
    final count = _codeEditorController.text.split('\n').length;
    if (count != _cachedLineCount) {
      setState(() {
        _cachedLineCount = count;
      });
    }
  }

  void _onControllerUpdate() {
    if (mounted) {
      if (_controller.hasError && _compileSuccess) {
        _compileStatus = 'Shader error';
        _compileSuccess = false;
      }
      setState(() {});
    }
  }

  void _syncCodeWithActivePass() {
    final pass = _controller.activePass;
    if (pass != null && _codeEditorController.text != pass.code) {
      _codeEditorController.text = pass.code;
      _cachedLineCount = pass.code.split('\n').length;
      if (_editorScrollController.hasClients) {
        _editorScrollController.jumpTo(0.0);
      }
      if (_gutterScrollController.hasClients) {
        _gutterScrollController.jumpTo(0.0);
      }
    }
  }

  @override
  void dispose() {
    _editorScrollController.removeListener(_onEditorScroll);
    _gutterScrollController.removeListener(_onGutterScroll);
    _codeEditorController.removeListener(_onCodeChanged);
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _codeEditorController.dispose();
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  Future<void> _compileShader() async {
    final newCode = _codeEditorController.text;

    setState(() {
      _compileStatus = 'Compiling with impellerc...';
    });

    final success = await _controller.compile(sourceCode: newCode);
    if (!mounted) return;

    if (success) {
      _controller.play();
      final isGpu = _controller.renderer.gpuRenderer.isGpuAvailable;
      setState(() {
        _compileStatus = isGpu
            ? 'Compiled and running (flutter_gpu)'
            : 'Compiled with impellerc (GPU offline: Impeller required)';
        _compileSuccess = true;
      });
    } else {
      setState(() {
        _compileStatus = 'Shader error: ${_controller.lastError}';
        _compileSuccess = false;
      });
    }
  }

  void _openLoadDialog() {
    showDialog(
      context: context,
      builder: (context) => _LoadShaderDialog(
        onLoadProject: (project) async {
          if (SoLoud.instance.isInitialized) {
            SoLoud.instance.disposeAllSources();
          }
          await _controller.loadProject(project);
          _syncCodeWithActivePass();
          _controller.play();
          if (mounted) {
            setState(() {
              _compileStatus = 'Loaded "${project.name}" (Running)';
              _compileSuccess = true;
            });
          }
        },
      ),
    );
  }

  void _openSaveDialog() {
    final cur = _controller.activePass;
    if (cur != null) {
      cur.code = _codeEditorController.text;
    }
    showDialog(
      context: context,
      builder: (context) => _SaveShaderDialog(project: _controller.project),
    );
  }

  void _openChannelPicker(int slotIndex) {
    final pass = _controller.activePass;
    if (pass == null) return;

    showDialog(
      context: context,
      builder: (context) => _ChannelPickerModal(
        slotIndex: slotIndex,
        currentChannel: pass.getChannel(slotIndex),
        onSelectChannel: (newChannel) {
          _controller.setChannel(slotIndex, newChannel);
          _controller.renderSingleFrame();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pass = _controller.activePass;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      // 1. Top Header: Title "shader_fun example" + Load & Save buttons
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF16161C),
            border: Border(
              bottom: BorderSide(color: Color(0xFF282832), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Icon branding
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5500), Color(0xFFFF2200)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),

              // Title "shader_fun example"
              const Text(
                'shader_fun example',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(width: 12),

              // Current shader subtitle
              Flexible(
                child: Text(
                  '•  ${_controller.project.name}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Load button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF383846)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  backgroundColor: const Color(0xFF202028),
                ),
                icon: const Icon(
                  Icons.folder_open,
                  size: 16,
                  color: Color(0xFF00E5FF),
                ),
                label: const Text('Load', style: TextStyle(fontSize: 13)),
                onPressed: _openLoadDialog,
              ),

              const SizedBox(width: 10),

              // Save button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5500),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                icon: const Icon(Icons.save, size: 16),
                label: const Text(
                  'Save',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: _openSaveDialog,
              ),
            ],
          ),
        ),
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          if (_isFullscreen) {
            return ShaderToyViewport(
              key: _viewportKey,
              controller: _controller,
              isFullscreen: true,
              onToggleFullscreen: () => setState(() => _isFullscreen = false),
            );
          }

          final viewportWidget = ShaderToyViewport(
            key: _viewportKey,
            controller: _controller,
            isFullscreen: false,
            onToggleFullscreen: () => setState(() => _isFullscreen = true),
          );

          final editorSection = _buildEditorSection(pass);

          if (isWide) {
            // Horizontal split (Viewport on Left, Editor on Right)
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Color(0xFF22222A), width: 1),
                      ),
                    ),
                    child: viewportWidget,
                  ),
                ),
                Expanded(flex: 6, child: editorSection),
              ],
            );
          } else {
            // Vertical split (Viewport on Top, Editor on Bottom)
            return Column(
              children: [
                Expanded(flex: 4, child: viewportWidget),
                Expanded(flex: 5, child: editorSection),
              ],
            );
          }
        },
      ),
    );
  }

  /// Builds the multi-pass tabs, code editor, and iChannel slots.
  Widget _buildEditorSection(ShaderPass? pass) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): () {
          _compileShader();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          _compileShader();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          _compileShader();
        },
      },
      child: Column(
        children: [
          // 1. Pass Tabs Strip
          Container(
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
                      final existing = _controller.project.passes
                          .map((p) => p.type)
                          .toSet();
                      final available = addableTypes
                          .where((t) => !existing.contains(t))
                          .toList();

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
                                _iconForPassType(type),
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
                    onSelected: (type) async {
                      final cur = _controller.activePass;
                      if (cur != null) {
                        cur.code = _codeEditorController.text;
                      }
                      await _controller.addPass(type);
                      _syncCodeWithActivePass();
                      setState(() {});
                    },
                  ),
                ),

                // Pass Tabs
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _controller.project.passes.length,
                    itemBuilder: (context, index) {
                      final p = _controller.project.passes[index];
                      final isSelected = index == _controller.activePassIndex;
                      final isImage = p.type == PassType.image;

                      return GestureDetector(
                        onTap: () {
                          final cur = _controller.activePass;
                          if (cur != null) {
                            cur.code = _codeEditorController.text;
                          }
                          _controller.setActivePass(index);
                          _syncCodeWithActivePass();
                          setState(() {});
                        },
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
                                _iconForPassType(p.type),
                                size: 14,
                                color: isSelected
                                    ? Colors.black87
                                    : Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                p.name,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!isImage) ...[
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () async {
                                    await _controller.removePass(p.type);
                                    _syncCodeWithActivePass();
                                    setState(() {});
                                  },
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
                    _showInputs ? Icons.expand_less : Icons.tune,
                    size: 16,
                  ),
                  label: const Text('Inputs', style: TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _showInputs = !_showInputs),
                ),

                const SizedBox(width: 4),

                // Play / Pause button in editor header
                IconButton(
                  iconSize: 20,
                  icon: Icon(
                    _controller.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: _controller.isPlaying
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF4ADE80),
                  ),
                  tooltip: _controller.isPlaying
                      ? 'Pause Shader (Space)'
                      : 'Play Shader (Space)',
                  onPressed: () => _controller.togglePlay(),
                ),

                // Compile button
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.bolt, color: Color(0xFF00E5FF)),
                  tooltip: 'Compile & Run Shader (Alt + Enter)',
                  onPressed: _compileShader,
                ),
              ],
            ),
          ),

          // 2. Collapsible Shader Inputs Drawer
          if (_showInputs) _buildShaderInputsDrawer(),

          // 3. Code Editor Area with Line Numbers
          Expanded(
            child: Container(
              color: const Color(0xFF181820),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Line numbers gutter
                  _buildLineNumberGutter(),

                  // Code text field
                  Expanded(
                    child: TextField(
                      controller: _codeEditorController,
                      scrollController: _editorScrollController,
                      maxLines: null,
                      expands: true,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                        color: const Color(0xFFE2E8F0),
                        height: 1.45,
                      ),
                      cursorColor: const Color(0xFFFF5500),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (val) {
                        if (_compileStatus !=
                            'Uncompiled changes (Alt+Enter to compile)') {
                          setState(() {
                            _compileStatus =
                                'Uncompiled changes (Alt+Enter to compile)';
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Error banner directly below the editor when code is broken
          if (!_compileSuccess && _controller.hasError)
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
                      '❌ Shader error:\n${_controller.lastError}',
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

          // 4. Editor status & compilation log bar
          Container(
            height: 24,
            color: const Color(0xFF121217),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  _compileSuccess ? Icons.check_circle : Icons.error,
                  size: 13,
                  color: _compileSuccess
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: _controller.lastError ?? _compileStatus,
                    child: Text(
                      _compileStatus,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _compileSuccess
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFEF4444),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: _compileSuccess
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Chars: ${_codeEditorController.text.length}  |  Lines: ${_codeEditorController.text.split('\n').length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // 5. 4 iChannel Slots Bar
          _buildChannelBar(pass),
        ],
      ),
    );
  }

  IconData _iconForPassType(PassType type) {
    switch (type) {
      case PassType.common:
        return Icons.code;
      case PassType.bufferA:
      case PassType.bufferB:
      case PassType.bufferC:
      case PassType.bufferD:
        return Icons.crop_square_sharp;
      case PassType.image:
        return Icons.desktop_windows;
    }
  }

  /// Builds the 4 iChannel slots at the bottom of the editor.
  Widget _buildChannelBar(ShaderPass? pass) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        border: Border(top: BorderSide(color: Color(0xFF282832), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: List.generate(4, (index) {
          final ch = pass?.getChannel(index);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ChannelSlotTile(
                slotIndex: index,
                channel: ch,
                onTap: () => _openChannelPicker(index),
                onClear: () async {
                  final oldCh = pass?.getChannel(index);
                  if (oldCh is SoLoudAudioChannel &&
                      SoLoud.instance.isInitialized) {
                    await SoLoud.instance.disposeAllSources();
                  }
                  _controller.setChannel(index, null);
                  _controller.renderSingleFrame();
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Builds line number gutter synced with editor scroll.
  Widget _buildLineNumberGutter() {
    final lineCount = _cachedLineCount;
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
          controller: _gutterScrollController,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemExtent: _fontSize * 1.45,
          itemCount: lineCount,
          itemBuilder: (context, i) {
            return Container(
              height: _fontSize * 1.45,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: _fontSize * 0.9,
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

  /// Shader inputs reference drawer.
  Widget _buildShaderInputsDrawer() {
    final uniforms = _controller.uniforms;

    final vars = [
      {
        'name': 'vec3 iResolution',
        'val':
            '${uniforms.resolution.width.toInt()}x${uniforms.resolution.height.toInt()}',
      },
      {'name': 'float iTime', 'val': '${uniforms.time.toStringAsFixed(2)}s'},
      {
        'name': 'float iTimeDelta',
        'val': '${uniforms.timeDelta.toStringAsFixed(4)}s',
      },
      {
        'name': 'float iFrameRate',
        'val': '${uniforms.frameRate.toStringAsFixed(1)} fps',
      },
      {'name': 'int iFrame', 'val': '${uniforms.frame}'},
      {
        'name': 'vec4 iMouse',
        'val': '(${uniforms.mouse.x.toInt()}, ${uniforms.mouse.y.toInt()})',
      },
      {'name': 'sampler2D iChannel0..3', 'val': 'Textures / Audio'},
    ];

    return Container(
      color: const Color(0xFF101015),
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: vars.map((v) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E26),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2C2C38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v['name']!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  v['val']!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A tile for an individual iChannel (0..3).
class _ChannelSlotTile extends StatelessWidget {
  const _ChannelSlotTile({
    required this.slotIndex,
    required this.channel,
    required this.onTap,
    required this.onClear,
  });

  final int slotIndex;
  final ShaderChannel? channel;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasChannel = channel != null;

    IconData icon;
    String label;
    Color accentColor;

    if (channel is BufferChannel) {
      icon = Icons.layers;
      label = (channel as BufferChannel).bufferName;
      accentColor = const Color(0xFFFF9900);
    } else if (channel is SoLoudAudioChannel) {
      icon = Icons.music_note;
      label = (channel as SoLoudAudioChannel).audioName;
      accentColor = const Color(0xFF00E5FF);
    } else if (channel is MicAudioChannel) {
      icon = Icons.mic;
      label = 'Microphone';
      accentColor = const Color(0xFF4ADE80);
    } else if (channel is CubeMapChannel) {
      icon = Icons.view_in_ar;
      label = 'CubeMap';
      accentColor = const Color(0xFFA855F7);
    } else if (channel is KeyboardChannel) {
      icon = Icons.keyboard;
      label = 'Keyboard';
      accentColor = const Color(0xFFE11D48);
    } else if (channel is TextureChannel) {
      icon = Icons.image;
      label = (channel as TextureChannel).name;
      accentColor = const Color(0xFF38BDF8);
    } else {
      icon = Icons.add;
      label = 'Empty';
      accentColor = Colors.white24;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasChannel
                ? accentColor.withValues(alpha: 0.6)
                : const Color(0xFF2E2E3A),
            width: hasChannel ? 1.2 : 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hasChannel
                    ? accentColor.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  (channel is TextureChannel &&
                      (channel as TextureChannel).assetPath != null)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        (channel as TextureChannel).assetPath!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(icon, color: accentColor, size: 16),
                      ),
                    )
                  : Icon(icon, color: accentColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'iChannel$slotIndex',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasChannel ? Colors.white : Colors.white38,
                      fontSize: 11,
                      fontWeight: hasChannel
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (hasChannel)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 14, color: Colors.white38),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Texture asset metadata
class _TextureInfo {
  const _TextureInfo({
    required this.name,
    required this.fileName,
    required this.category,
  });

  final String name;
  final String fileName;
  final String category;

  String get assetPath => 'assets/2d_texture/$fileName';
}

/// Audio track metadata
class _AudioTrackInfo {
  const _AudioTrackInfo({
    required this.title,
    required this.fileName,
    required this.genre,
  });

  final String title;
  final String fileName;
  final String genre;

  String get assetPath => 'assets/audio/$fileName';
}

/// Modal for choosing an input for an iChannel (Textures, Audio with flutter_soloud, Mic with flutter_recorder, Buffers).
class _ChannelPickerModal extends StatefulWidget {
  const _ChannelPickerModal({
    required this.slotIndex,
    required this.currentChannel,
    required this.onSelectChannel,
  });

  final int slotIndex;
  final ShaderChannel? currentChannel;
  final ValueChanged<ShaderChannel?> onSelectChannel;

  @override
  State<_ChannelPickerModal> createState() => _ChannelPickerModalState();
}

class _ChannelPickerModalState extends State<_ChannelPickerModal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedTextureCategory = 'All';

  static const List<_AudioTrackInfo> _allAudioTracks = [
    _AudioTrackInfo(
      title: '8-Bit Mentality',
      fileName: '8_bit_mentality.mp3',
      genre: 'Chiptune / Retro Arcade',
    ),
    _AudioTrackInfo(
      title: 'Electro Nebulae',
      fileName: 'electro_nebulae.mp3',
      genre: 'Electronic / Synthwave',
    ),
    _AudioTrackInfo(
      title: 'Experiment',
      fileName: 'experiment.mp3',
      genre: 'Ambient / Glitch IDM',
    ),
    _AudioTrackInfo(
      title: 'Most Geometric Person',
      fileName: 'most_geometric_person.mp3',
      genre: 'Electro Groove / Beats',
    ),
    _AudioTrackInfo(
      title: 'Tropical Beeper',
      fileName: 'tropical_beeper.mp3',
      genre: 'Tropical / Chiptune Melodic',
    ),
    _AudioTrackInfo(
      title: 'X Track Ture',
      fileName: 'x_track_ture.mp3',
      genre: 'Drum & Bass / Cyber Electronic',
    ),
  ];

  static const List<_TextureInfo> _allTextures = [
    // Noise
    _TextureInfo(
      name: 'Blue Noise',
      fileName: 'blue_noise.png',
      category: 'Noise',
    ),
    _TextureInfo(
      name: 'Bayer Matrix',
      fileName: 'bayer.png',
      category: 'Noise',
    ),
    _TextureInfo(
      name: 'Grey Noise Medium',
      fileName: 'grey_noise_medium.png',
      category: 'Noise',
    ),
    _TextureInfo(
      name: 'Grey Noise Small',
      fileName: 'grey_noise_small.png',
      category: 'Noise',
    ),
    _TextureInfo(
      name: 'RGBA Noise Medium',
      fileName: 'rgba_noise_medium.png',
      category: 'Noise',
    ),
    _TextureInfo(
      name: 'RGBA Noise Small',
      fileName: 'rgba_noise_small.png',
      category: 'Noise',
    ),

    // Organic
    _TextureInfo(
      name: 'Organic 1',
      fileName: 'organic_1.jpg',
      category: 'Organic',
    ),
    _TextureInfo(
      name: 'Organic 2',
      fileName: 'organic_2.jpg',
      category: 'Organic',
    ),
    _TextureInfo(
      name: 'Organic 3',
      fileName: 'organic_3.jpg',
      category: 'Organic',
    ),
    _TextureInfo(
      name: 'Organic 4',
      fileName: 'organic_4.jpg',
      category: 'Organic',
    ),
    _TextureInfo(name: 'Lichen', fileName: 'lichen.jpg', category: 'Organic'),

    // Surface
    _TextureInfo(name: 'Wood Grain', fileName: 'wood.jpg', category: 'Surface'),
    _TextureInfo(
      name: 'Rock Tiles',
      fileName: 'rock_tiles.jpg',
      category: 'Surface',
    ),
    _TextureInfo(
      name: 'Rusty Metal',
      fileName: 'rusty_metal.jpg',
      category: 'Surface',
    ),
    _TextureInfo(name: 'Pebbles', fileName: 'pobbles.png', category: 'Surface'),

    // Abstract
    _TextureInfo(
      name: 'Abstract 1',
      fileName: 'abstract_1.jpg',
      category: 'Abstract',
    ),
    _TextureInfo(
      name: 'Abstract 2',
      fileName: 'abstract_2.jpg',
      category: 'Abstract',
    ),
    _TextureInfo(
      name: 'Abstract 3',
      fileName: 'abstract_3.jpg',
      category: 'Abstract',
    ),

    // Misc
    _TextureInfo(
      name: 'Stars & Space',
      fileName: 'stars.jpg',
      category: 'Misc',
    ),
    _TextureInfo(
      name: 'London Street',
      fileName: 'london.jpg',
      category: 'Misc',
    ),
    _TextureInfo(name: 'Nyancat', fileName: 'nyancat.png', category: 'Misc'),
    _TextureInfo(name: 'Font Atlas', fileName: 'font_1.png', category: 'Misc'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF323242)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.input, size: 18, color: Color(0xFFFF5500)),
                  const SizedBox(width: 8),
                  Text(
                    'Select Input for iChannel${widget.slotIndex}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFF5500),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.image, size: 16), text: 'Textures (2D)'),
                Tab(
                  icon: Icon(Icons.music_note, size: 16),
                  text: 'Audio (SoLoud)',
                ),
                Tab(icon: Icon(Icons.mic, size: 16), text: 'Mic (Recorder)'),
                Tab(icon: Icon(Icons.layers, size: 16), text: 'Buffers'),
                Tab(icon: Icon(Icons.keyboard, size: 16), text: 'Keyboard'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 2D Textures
                  _buildTexturesTab(),

                  // Tab 2: SoLoud Audio
                  _buildAudioTab(),

                  // Tab 3: Flutter Recorder Mic
                  _buildMicTab(),

                  // Tab 4: Buffers
                  _buildBuffersTab(),

                  // Tab 5: Keyboard
                  _buildKeyboardTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allAudioTracks.length,
      itemBuilder: (itemCtx, i) {
        final track = _allAudioTracks[i];
        return Card(
          color: const Color(0xFF22222E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF2E2E3A)),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.music_note,
                color: Color(0xFF00E5FF),
                size: 20,
              ),
            ),
            title: Text(
              track.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              '${track.genre} • 512x2 FFT & Waveform',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(
                'Select',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                if (SoLoud.instance.isInitialized) {
                  await SoLoud.instance.disposeAllSources();
                }
                final channel = SoLoudAudioChannel(
                  audioName: track.title,
                  audioPath: track.assetPath,
                );
                await channel.initAudio();
                widget.onSelectChannel(channel);
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMicTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, size: 48, color: Color(0xFF4ADE80)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Live Microphone Input (flutter_recorder)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Streams real-time microphone FFT frequency bands and PCM waveform into a 512x2 texture.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4ADE80),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.check),
            label: const Text(
              'Enable Microphone Channel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              if (SoLoud.instance.isInitialized) {
                await SoLoud.instance.disposeAllSources();
              }
              final channel = MicAudioChannel();
              widget.onSelectChannel(channel);
              await channel.startListening();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBuffersTab() {
    final buffers = [
      {'name': 'Buffer A', 'idx': 0},
      {'name': 'Buffer B', 'idx': 1},
      {'name': 'Buffer C', 'idx': 2},
      {'name': 'Buffer D', 'idx': 3},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: buffers.length,
      itemBuilder: (context, i) {
        final buf = buffers[i];
        return Card(
          color: const Color(0xFF22222E),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFF9900),
              child: Icon(Icons.layers, color: Colors.black87),
            ),
            title: Text(
              buf['name']! as String,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Multi-pass temporal feedback texture',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9900),
              ),
              child: const Text(
                'Select',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                final channel = BufferChannel(bufferIndex: buf['idx']! as int);
                widget.onSelectChannel(channel);
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeyboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xFF1E1E28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFF2E2E3C)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shadertoy-style keyboard preview tile
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3A3A4C)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.keyboard,
                              size: 44,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 14,
                              height: 2,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Keyboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF282836),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '256 x 3  •  1 ch, int8',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF262634)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Texture Specifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Row 0 (y = 0): Key down / held state (1.0 if pressed, 0.0 if up)\n'
                      '• Row 1 (y = 1): Key press trigger (1.0 for single frame upon press)\n'
                      '• Row 2 (y = 2): Key toggle state (toggled on/off on each press)\n'
                      '• Columns (x = 0..255): JavaScript keyCodes (Backspace=8, Enter=13, Shift=16, Space=32, Left=37, Up=38, Right=39, Down=40, etc.)',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Select Keyboard',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final channel = KeyboardChannel();
                    widget.onSelectChannel(channel);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTexturesTab() {
    final filteredTextures = _selectedTextureCategory == 'All'
        ? _allTextures
        : _allTextures
              .where((t) => t.category == _selectedTextureCategory)
              .toList();

    const categories = [
      'All',
      'Noise',
      'Organic',
      'Surface',
      'Abstract',
      'Misc',
    ];

    return Column(
      children: [
        // Category Filter Chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedTextureCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedTextureCategory = cat;
                      });
                    },
                    backgroundColor: const Color(0xFF22222E),
                    selectedColor: const Color(0xFF38BDF8)
                        .withValues(alpha: 0.25),
                    checkmarkColor: const Color(0xFF38BDF8),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? const Color(0xFF38BDF8)
                          : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF323242),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Textures Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemCount: filteredTextures.length,
            itemBuilder: (context, index) {
              final tex = filteredTextures[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                color: const Color(0xFF22222E),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF323242)),
                ),
                child: InkWell(
                  onTap: () async {
                    final channel = TextureChannel(
                      name: tex.name,
                      assetPath: tex.assetPath,
                    );
                    await channel.loadImage();
                    widget.onSelectChannel(channel);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              tex.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white24,
                                  size: 24,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tex.category,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          tex.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Dialog for loading shaders from JSON format or presets.
class _LoadShaderDialog extends StatefulWidget {
  const _LoadShaderDialog({required this.onLoadProject});

  final ValueChanged<ShaderToyProject> onLoadProject;

  @override
  State<_LoadShaderDialog> createState() => _LoadShaderDialogState();
}

class _LoadShaderDialogState extends State<_LoadShaderDialog> {
  final TextEditingController _jsonInputController = TextEditingController();
  String? _jsonError;

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

  @override
  void dispose() {
    _jsonInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = ShaderPresets.all;

    return Dialog(
      backgroundColor: const Color(0xFF181822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF323242)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_open, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 8),
                  const Text(
                    'Load Shader (JSON Format)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose a built-in ShaderToy preset or paste raw ShaderToy JSON below:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Presets list
              SizedBox(
                height: 150,
                child: ListView.builder(
                  itemCount: presets.length,
                  itemBuilder: (context, i) {
                    final p = presets[i];
                    return Card(
                      color: const Color(0xFF22222E),
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          p.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          p.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: const BorderSide(color: Color(0xFF00E5FF)),
                          ),
                          child: const Text('Load'),
                          onPressed: () {
                            widget.onLoadProject(p);
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Or Paste ShaderToy JSON:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),

              Expanded(
                child: TextField(
                  controller: _jsonInputController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: '{\n  "Shader": {\n    "info": { ... },\n    "renderpass": [ ... ]\n  }\n}',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF101015),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF282832)),
                    ),
                  ),
                ),
              ),

              if (_jsonError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _jsonError!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
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
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text(
                    'Load from JSON',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _loadFromJsonString,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for saving/exporting shaders to JSON format.
class _SaveShaderDialog extends StatelessWidget {
  const _SaveShaderDialog({required this.project});

  final ShaderToyProject project;

  @override
  Widget build(BuildContext context) {
    final jsonString = project.toJsonString();

    return Dialog(
      backgroundColor: const Color(0xFF181822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF323242)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.save, color: Color(0xFFFF5500)),
                  const SizedBox(width: 8),
                  Text(
                    'Save Shader: "${project.name}" (JSON)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Standard ShaderToy JSON export format with all passes and iChannel bindings:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101015),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF282832)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonString,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF4ADE80),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF383846)),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy JSON'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shader JSON copied to clipboard!'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5500),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
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
