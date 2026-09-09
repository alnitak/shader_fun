import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shader_fun/shader_fun.dart';

import 'studio/dialogs/channel_picker_modal.dart';
import 'studio/dialogs/channel_setup_dialog.dart';
import 'studio/dialogs/load_shader_dialog.dart';
import 'studio/dialogs/save_shader_dialog.dart';
import 'studio/widgets/channel_bar.dart';
import 'studio/widgets/pass_tabs_bar.dart';
import 'studio/widgets/shader_inputs_drawer.dart';
import 'studio/widgets/studio_app_bar.dart';
import 'studio/widgets/studio_code_editor.dart';

export 'studio/dialogs/channel_picker_modal.dart';
export 'studio/dialogs/channel_setup_dialog.dart';
export 'studio/dialogs/load_shader_dialog.dart';
export 'studio/dialogs/save_shader_dialog.dart';
export 'studio/models/channel_assets.dart';
export 'studio/widgets/channel_bar.dart';
export 'studio/widgets/channel_slot_tile.dart';
export 'studio/widgets/pass_tabs_bar.dart';
export 'studio/widgets/shader_inputs_drawer.dart';
export 'studio/widgets/studio_app_bar.dart';
export 'studio/widgets/studio_code_editor.dart';

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
  final double _fontSize = 15.0;
  final GlobalKey _viewportKey = GlobalKey();
  bool _isSyncingScroll = false;
  int _cachedLineCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = ShaderToyController(
      initialProject: widget.initialProject ?? ShaderToyProject.empty(),
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
            ? 'Compiled and running (flutter_scene GPU)'
            : 'Compiled with impellerc (GPU offline: Impeller/WebGL2 required)';
        _compileSuccess = true;
      });
    } else {
      setState(() {
        _compileStatus = 'Shader error: ${_controller.lastError}';
        _compileSuccess = false;
      });
    }
  }

  Future<void> _newShader() async {
    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.disposeAllSources();
    }
    final project = ShaderToyProject.empty();
    await _controller.loadProject(project);
    _syncCodeWithActivePass();
    _controller.play();
    if (mounted) {
      setState(() {
        _compileStatus = 'Created new shader (Running)';
        _compileSuccess = true;
      });
    }
  }

  void _openLoadDialog() {
    showDialog(
      context: context,
      builder: (context) => LoadShaderDialog(
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

  void _openSaveDialog() async {
    final cur = _controller.activePass;
    if (cur != null) {
      cur.code = _codeEditorController.text;
    }
    await showDialog(
      context: context,
      builder: (context) => SaveShaderDialog(project: _controller.project),
    );
    if (mounted) setState(() {});
  }

  void _openChannelPicker(int slotIndex) {
    final pass = _controller.activePass;
    if (pass == null) return;

    showDialog(
      context: context,
      builder: (context) => ChannelPickerModal(
        slotIndex: slotIndex,
        currentChannel: pass.getChannel(slotIndex),
        onSelectChannel: (newChannel) {
          _controller.setChannel(slotIndex, newChannel);
          _controller.renderSingleFrame();
        },
      ),
    );
  }

  void _openChannelSettings(int slotIndex) {
    final pass = _controller.activePass;
    final channel = pass?.getChannel(slotIndex);
    if (channel == null) return;

    showDialog(
      context: context,
      builder: (context) => ChannelSetupDialog(
        slotIndex: slotIndex,
        channel: channel,
        controller: _controller,
      ),
    );
  }

  Widget _buildEditorSection(ShaderPass? pass) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, alt: true):
            _compileShader,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _compileShader,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _compileShader,
      },
      child: Column(
        children: [
          // 1. Pass Tabs Strip
          PassTabsBar(
            passes: _controller.project.passes,
            activePassIndex: _controller.activePassIndex,
            onSelectPass: (index) {
              final cur = _controller.activePass;
              if (cur != null) {
                cur.code = _codeEditorController.text;
              }
              _controller.setActivePass(index);
              _syncCodeWithActivePass();
              setState(() {});
            },
            onAddPass: (type) async {
              final cur = _controller.activePass;
              if (cur != null) {
                cur.code = _codeEditorController.text;
              }
              await _controller.addPass(type);
              _syncCodeWithActivePass();
              setState(() {});
            },
            onRemovePass: (type) async {
              await _controller.removePass(type);
              _syncCodeWithActivePass();
              setState(() {});
            },
            showInputs: _showInputs,
            onToggleInputs: () => setState(() => _showInputs = !_showInputs),
            isPlaying: _controller.isPlaying,
            onTogglePlay: () => _controller.togglePlay(),
            onCompile: _compileShader,
          ),

          // 2. Collapsible Shader Inputs Drawer
          if (_showInputs) ShaderInputsDrawer(uniforms: _controller.uniforms),

          // 3. Code Editor
          Expanded(
            child: StudioCodeEditor(
              codeController: _codeEditorController,
              editorScrollController: _editorScrollController,
              gutterScrollController: _gutterScrollController,
              fontSize: _fontSize,
              lineCount: _cachedLineCount,
              compileSuccess: _compileSuccess,
              compileStatus: _compileStatus,
              hasError: _controller.hasError,
              lastError: _controller.lastError,
              onCodeChanged: (val) {
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

          // 4. iChannel slots bar
          ChannelBar(
            pass: pass,
            onOpenChannelPicker: _openChannelPicker,
            onOpenChannelSettings: _openChannelSettings,
            onChannelCleared: (slotIndex) {
              _controller.setChannel(slotIndex, null);
              _controller.renderSingleFrame();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pass = _controller.activePass;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: StudioAppBar(
        projectName: _controller.project.name,
        onNew: _newShader,
        onLoad: _openLoadDialog,
        onSave: _openSaveDialog,
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
}
