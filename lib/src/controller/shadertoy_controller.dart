import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as flutter_foundation;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as sl;
import 'package:listen/listen.dart' as listen;

import '../channels/audio_texture_provider.dart';
import '../channels/shader_channel.dart';
import '../compiler/impeller_compiler.dart';
import '../core/keyboard_state.dart';
import '../core/shader_pass.dart';
import '../core/shadertoy_uniforms.dart';
import '../models/shadertoy_json.dart';
import '../renderer/shadertoy_renderer.dart';

/// State, compilation, and playback controller for a ShaderToy session.
/// Exposes package capabilities for compiling shaders via `impellerc`, managing
/// channels (audio, mic, textures, buffers), pass sources, and GPU rendering.
///
/// Implements [listen.ChangeNotifier] and provides fine-grained [listen.ValueListenable]
/// properties for reactive UI bindings while also implementing [flutter_foundation.Listenable]
/// for direct Flutter widget interoperability.
class ShaderToyController
    with listen.ChangeNotifier
    implements flutter_foundation.Listenable {
  ShaderToyController({
    ShaderToyProject? initialProject,
    ui.Size initialResolution = const ui.Size(800, 450),
    TickerProvider? vsync,
    bool autoPlay = false,
  }) : _project = initialProject ?? ShaderToyProject.empty(),
       _uniforms = ShaderToyUniforms(resolution: initialResolution),
       _vsync = vsync,
       isPlayingNotifier = listen.ValueNotifier<bool>(autoPlay),
       isCompilingNotifier = listen.ValueNotifier<bool>(true),
       lastErrorNotifier = listen.ValueNotifier<String?>(null),
       activePassIndexNotifier = listen.ValueNotifier<int>(0),
       currentImageNotifier = listen.ValueNotifier<ui.Image?>(null) {
    _renderer = ShaderToyRenderer(
      width: initialResolution.width.toInt(),
      height: initialResolution.height.toInt(),
    );

    if (vsync != null) {
      _ticker = vsync.createTicker(_onTick);
      if (isPlaying) {
        _startTicker();
      }
    }
    _bindAudioChannelListener();
    _initProjectChannels();

    // Perform initial compilation in background
    compile();
  }

  TickerProvider? _vsync;
  TickerProvider? _attachedVsync;
  ShaderToyProject _project;
  final ShaderToyUniforms _uniforms;
  late final ShaderToyRenderer _renderer;
  final ShaderToyKeyboardState _keyboard = ShaderToyKeyboardState();
  Ticker? _ticker;

  bool _isDisposed = false;
  bool _isRendering = false;
  AudioChannel? _boundAudioChannel;

  /// Fine-grained [listen.ValueNotifier] reactive state properties.
  final listen.ValueNotifier<bool> isPlayingNotifier;
  final listen.ValueNotifier<bool> isCompilingNotifier;
  final listen.ValueNotifier<String?> lastErrorNotifier;
  final listen.ValueNotifier<int> activePassIndexNotifier;
  final listen.ValueNotifier<ui.Image?> currentImageNotifier;

  // Frame timing calculation
  double _lastTimestamp = 0.0;
  final List<double> _fpsHistory = [];

  // Getters
  ShaderToyProject get project => _project;
  ShaderToyUniforms get uniforms => _uniforms;
  ShaderToyRenderer get renderer => _renderer;
  ShaderToyKeyboardState get keyboard => _keyboard;
  ui.Image? get currentImage => currentImageNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;
  bool get isCompiling => isCompilingNotifier.value;
  int get activePassIndex => activePassIndexNotifier.value;

  ShaderPass? get activePass =>
      activePassIndex >= 0 && activePassIndex < _project.passes.length
      ? _project.passes[activePassIndex]
      : null;

  String? get activePassCode => activePass?.code;
  String? get imagePassCode => _project.imagePass?.code;

  double get time => _uniforms.time;
  int get frame => _uniforms.frame;
  double get fps => _uniforms.frameRate;
  ui.Size get resolution => _uniforms.resolution;

  String? get lastError => lastErrorNotifier.value;
  bool get hasError => lastErrorNotifier.value != null;

  // ===========================================================================
  // Compilation
  // ===========================================================================

  /// Compiles the active shader pass via `impellerc` or evaluates the Sound pass.
  /// Invoked when clicking "Compile & Run Shader" or pressing Alt+Enter.
  /// If [sourceCode] is provided, it is compiled and, upon success, committed
  /// to the active pass.
  /// Captures compiler error diagnostics from `stderr` on failure.
  Future<bool> compile({String? sourceCode}) async {
    final pass = activePass ?? _project.imagePass;
    final codeToCompile = sourceCode ?? pass?.code ?? '';
    if (codeToCompile.trim().isEmpty) {
      lastErrorNotifier.value = 'Shader code is empty';
      notifyListeners();
      return false;
    }

    // 1. Common pass: update code and recompile all visual passes
    if (pass?.type == PassType.common) {
      pass!.code = codeToCompile;
      return compileAllPasses();
    }

    // 2. Image and Buffer passes
    return compilePass(pass, codeOverride: codeToCompile);
  }

  /// Compiles all enabled visual passes in the project (Buffer A..D, Image).
  Future<bool> compileAllPasses() async {
    isCompilingNotifier.value = true;
    notifyListeners();

    try {
      final commonCode = _project.commonPass?.code;
      final visualPasses = _project.passes.where(
        (p) => p.enabled && p.type != PassType.common,
      );

      for (final pass in visualPasses) {
        if (pass.code.trim().isEmpty) continue;

        final result = await ImpellerCompiler.compile(
          shadertoyGlsl: pass.code,
          commonGlsl: commonCode,
        );
        if (!result.isSuccess) {
          lastErrorNotifier.value =
              '${pass.name}: ${result.errorMessage ?? "Shader compilation failed"}';
          notifyListeners();
          flutter_foundation.debugPrint(
            'Shader error in ${pass.name}: ${lastErrorNotifier.value}',
          );
          return false;
        }

        if (result.bundleBytes != null) {
          final fullCode = (commonCode != null && commonCode.isNotEmpty)
              ? '$commonCode\n${pass.code}'
              : pass.code;
          await _renderer.loadShaderBundle(
            result.bundleBytes!,
            passType: pass.type,
            activeCode: fullCode,
          );
        }
      }

      lastErrorNotifier.value = null;
      await renderSingleFrame();
      notifyListeners();
      return true;
    } catch (e) {
      lastErrorNotifier.value = 'Compilation exception: $e';
      flutter_foundation.debugPrint('Compilation exception: $e');
      notifyListeners();
      return false;
    } finally {
      isCompilingNotifier.value = false;
      notifyListeners();
    }
  }

  /// Compiles an individual visual pass with optional common code prepended.
  Future<bool> compilePass(ShaderPass? pass, {String? codeOverride}) async {
    final targetPass = pass ?? _project.imagePass;
    final codeToCompile = codeOverride ?? targetPass?.code ?? '';
    if (codeToCompile.trim().isEmpty) {
      lastErrorNotifier.value = 'Shader code is empty';
      notifyListeners();
      return false;
    }

    isCompilingNotifier.value = true;
    notifyListeners();

    try {
      final commonCode = (targetPass?.type != PassType.common)
          ? _project.commonPass?.code
          : null;

      final result = await ImpellerCompiler.compile(
        shadertoyGlsl: codeToCompile,
        commonGlsl: commonCode,
      );
      if (!result.isSuccess) {
        lastErrorNotifier.value =
            result.errorMessage ?? 'Shader compilation failed';
        notifyListeners();
        flutter_foundation.debugPrint(
          'Shader error: ${lastErrorNotifier.value}',
        );
        return false;
      }

      if (targetPass != null) {
        targetPass.code = codeToCompile;
      }

      lastErrorNotifier.value = null;
      if (result.bundleBytes != null) {
        final fullCode = (commonCode != null && commonCode.isNotEmpty)
            ? '$commonCode\n$codeToCompile'
            : codeToCompile;
        await _renderer.loadShaderBundle(
          result.bundleBytes!,
          passType: targetPass?.type ?? PassType.image,
          activeCode: fullCode,
        );
      }

      await renderSingleFrame();
      notifyListeners();
      return true;
    } catch (e) {
      lastErrorNotifier.value = 'Compilation exception: $e';
      flutter_foundation.debugPrint('Compilation exception: $e');
      notifyListeners();
      return false;
    } finally {
      isCompilingNotifier.value = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // Shader Source & Settings Management
  // ===========================================================================

  /// Updates the GLSL code of the active pass without auto-compiling.
  void updateActivePassCode(String newCode) {
    if (activePass != null && activePass!.code != newCode) {
      activePass!.code = newCode;
      notifyListeners();
    }
  }

  /// Sets the GLSL code of the Image pass.
  void setImagePassCode(String code) {
    final pass = _project.imagePass;
    if (pass != null) {
      pass.code = code;
      notifyListeners();
    }
  }

  /// Sets the GLSL code of a specific Buffer pass (Buffer A, B, C, D).
  void setBufferPassCode(PassType type, String code) {
    final pass = _project.getPass(type);
    if (pass != null) {
      pass.code = code;
      notifyListeners();
    }
  }

  /// Sets the code for the pass at [passIndex].
  void setPassCode(int passIndex, String code) {
    if (passIndex >= 0 && passIndex < _project.passes.length) {
      _project.passes[passIndex].code = code;
      notifyListeners();
    }
  }

  /// Gets the code for the pass at [passIndex].
  String? getPassCode(int passIndex) {
    if (passIndex >= 0 && passIndex < _project.passes.length) {
      return _project.passes[passIndex].code;
    }
    return null;
  }

  /// Sets the active project (backwards compatibility).
  Future<void> setProject(ShaderToyProject newProject) =>
      loadProject(newProject);

  /// Loads a complete [ShaderToyProject] and optionally compiles.
  Future<void> loadProject(
    ShaderToyProject newProject, {
    bool autoCompile = true,
    int? activePassIndex,
  }) async {
    try {
      if (sl.SoLoud.instance.isInitialized) {
        await sl.SoLoud.instance.disposeAllSources();
      }
    } catch (_) {}

    _project = newProject;
    final defaultIdx =
        _project.passes.indexWhere((p) => p.type == PassType.image);
    activePassIndexNotifier.value =
        activePassIndex ?? (defaultIdx >= 0 ? defaultIdx : 0);
    _renderer.clearAudio();
    _renderer.gpuRenderer.clearPingPongBuffers();

    await _initProjectChannels();

    if (autoCompile) {
      await compileAllPasses();
    }
    rewind();
    if (isPlaying) {
      _startTicker();
    }
    notifyListeners();
  }

  /// Loads project settings from a JSON string (supporting standard ShaderToy and concise JSON formats).
  Future<void> loadProjectFromJson(
    String jsonString, {
    bool autoCompile = true,
  }) async {
    final parsed = ShaderToyProject.parseJsonString(jsonString);
    await loadProject(parsed, autoCompile: autoCompile);
  }

  /// Loads a custom shader setup directly from source strings and channel configurations.
  Future<void> loadShaderSettings({
    required String imageSource,
    String shaderName = 'Custom Shader',
    Map<PassType, String>? bufferSources,
    Map<int, ShaderChannel>? channels,
    bool autoCompile = true,
  }) async {
    final passes = <ShaderPass>[];
    final imagePass = ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: imageSource,
    );
    passes.add(imagePass);

    if (bufferSources != null) {
      bufferSources.forEach((type, code) {
        passes.add(ShaderPass(type: type, name: type.displayName, code: code));
      });
    }

    if (channels != null) {
      channels.forEach((idx, ch) {
        imagePass.setChannel(idx, ch);
      });
    }

    final newProj = ShaderToyProject(name: shaderName, passes: passes);

    await loadProject(newProj, autoCompile: autoCompile);
  }

  // ===========================================================================
  // iChannel Management
  // ===========================================================================

  /// Assigns an audio channel to [channelIndex] (supports URLs, local files, assets, or live microphone).
  Future<void> setAudioChannel(
    int channelIndex, {
    String? src,
    bool isMic = false,
    int? passIndex,
  }) async {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;

    if (targetPass == null) return;

    if (isMic) {
      final micChannel = MicAudioChannel();
      await micChannel.initMicrophone();
      targetPass.setChannel(channelIndex, micChannel);
    } else {
      final audioChannel = SoLoudAudioChannel(src: src);
      if (src != null && src.isNotEmpty) {
        await audioChannel.initAudio(src: src);
      }
      targetPass.setChannel(channelIndex, audioChannel);
    }

    _bindAudioChannelListener();
    notifyListeners();
  }

  /// Assigns a 2D image texture channel to [channelIndex] (supports URLs, local files, assets, or byte data).
  Future<void> setTextureChannel(
    int channelIndex, {
    String? src,
    Uint8List? bytes,
    int? width,
    int? height,
    int? passIndex,
  }) async {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;

    if (targetPass == null) return;

    final channel = TextureChannel(
      src: src,
      imageBytes: bytes,
      initialResolution: width != null && height != null
          ? ui.Size(width.toDouble(), height.toDouble())
          : null,
    );

    await _uploadTextureChannel(channelIndex, channel);

    targetPass.setChannel(channelIndex, channel);
    notifyListeners();
  }

  /// Assigns a buffer feedback channel to [channelIndex].
  void setBufferChannel(
    int channelIndex,
    PassType bufferType, {
    int? passIndex,
  }) {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;

    if (targetPass == null) return;

    int bufIdx = 0;
    if (bufferType == PassType.bufferB) bufIdx = 1;
    if (bufferType == PassType.bufferC) bufIdx = 2;
    if (bufferType == PassType.bufferD) bufIdx = 3;

    targetPass.setChannel(channelIndex, BufferChannel(bufferIndex: bufIdx));
    notifyListeners();
  }

  /// Clears an iChannel slot.
  void removeChannel(int channelIndex, {int? passIndex}) {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;

    if (targetPass != null) {
      targetPass.setChannel(channelIndex, null);
      _renderer.gpuRenderer.removeTextureChannel(channelIndex);
      _bindAudioChannelListener();
      notifyListeners();
    }
  }

  /// Returns the channel connected to [channelIndex].
  ShaderChannel? getChannel(int channelIndex, [int? passIndex]) {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;
    if (targetPass != null &&
        channelIndex >= 0 &&
        channelIndex < targetPass.channels.length) {
      return targetPass.channels[channelIndex];
    }
    return null;
  }

  /// Returns the list of channels for a pass.
  List<ShaderChannel?> getChannels([int? passIndex]) {
    final targetPass = passIndex != null
        ? (passIndex >= 0 && passIndex < _project.passes.length
              ? _project.passes[passIndex]
              : activePass)
        : activePass;
    return targetPass?.channels ?? [];
  }

  /// Legacy helper for assigning channels directly.
  void setChannel(int channelIndex, ShaderChannel? channel) {
    if (activePass != null) {
      activePass!.setChannel(channelIndex, channel);
      if (channel is SoLoudAudioChannel &&
          channel.src != null &&
          channel.src!.isNotEmpty) {
        channel.initAudio(src: channel.src).then((_) {
          if (!isPlaying) {
            channel.pause();
          }
        });
      } else if (channel is MicAudioChannel) {
        channel.startListening();
      } else if (channel is TextureChannel) {
        _uploadTextureChannel(channelIndex, channel);
      } else if (channel == null) {
        _renderer.gpuRenderer.removeTextureChannel(channelIndex);
      }
      _bindAudioChannelListener();
      notifyListeners();
    }
  }

  // ===========================================================================
  // Tab / Pass Selection & Dynamic Management
  // ===========================================================================

  /// Sets the active pass tab (e.g. Image, Buffer A, Common).
  void setActivePass(int index) {
    if (index >= 0 && index < _project.passes.length) {
      activePassIndexNotifier.value = index;
      _bindAudioChannelListener();
      notifyListeners();
    }
  }

  /// Adds a pass of [type] to the project.
  Future<ShaderPass?> addPass(PassType type, {String? code}) async {
    final newPass = _project.addPass(type, code: code);
    if (newPass == null) return null;

    final newIdx = _project.passes.indexOf(newPass);
    if (newIdx != -1) {
      activePassIndexNotifier.value = newIdx;
    }

    await compile();
    notifyListeners();
    return newPass;
  }

  /// Removes the pass of [type] from the project (Image pass cannot be removed).
  Future<bool> removePass(PassType type) async {
    if (type == PassType.image) return false;

    final success = _project.removePass(type);
    if (!success) return false;

    final imgIdx = _project.passes.indexWhere((p) => p.type == PassType.image);
    activePassIndexNotifier.value = imgIdx != -1 ? imgIdx : 0;

    await compile();
    notifyListeners();
    return true;
  }

  // ===========================================================================
  // Playback Controls
  // ===========================================================================

  /// Attaches a ticker if one was not provided in the constructor.
  void attachTicker(TickerProvider vsync) {
    if (_vsync != null) {
      // External vsync was provided in constructor; ensure ticker is alive
      _ticker ??= _vsync!.createTicker(_onTick);
      if (isPlaying) {
        _startTicker();
      }
      return;
    }
    if (_attachedVsync == vsync && _ticker != null) {
      if (isPlaying) {
        _startTicker();
      }
      return;
    }
    _stopTicker();
    _ticker?.dispose();
    _attachedVsync = vsync;
    _ticker = vsync.createTicker(_onTick);
    if (isPlaying) {
      _startTicker();
    }
  }

  /// Detaches the ticker if it was attached by [vsync].
  /// If vsync was provided in the constructor, detaching by a viewport is a no-op.
  void detachTicker([TickerProvider? vsync]) {
    if (_vsync != null) {
      // Controller is driven by constructor vsync; do not let child views detach it.
      return;
    }
    if (vsync != null && _attachedVsync != vsync) {
      return;
    }
    _stopTicker();
    _ticker?.dispose();
    _ticker = null;
    _attachedVsync = null;
  }

  void _startTicker() {
    if (_ticker == null) {
      final provider = _vsync ?? _attachedVsync;
      if (provider != null) {
        _ticker = provider.createTicker(_onTick);
      }
    }
    if (_ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  void _stopTicker() {
    if (_ticker != null && _ticker!.isActive) {
      _ticker!.stop();
    }
  }

  void play() {
    isPlayingNotifier.value = true;
    _lastTimestamp = 0.0;
    _uniforms.timeDelta = 0.016;
    if (_ticker == null) {
      final provider = _vsync ?? _attachedVsync;
      if (provider != null) {
        _ticker = provider.createTicker(_onTick);
      }
    }
    _startTicker();
    final audio = _findActiveAudioChannel();
    if (audio is SoLoudAudioChannel) {
      audio.resume();
    }
    notifyListeners();
  }

  void pause() {
    isPlayingNotifier.value = false;
    _stopTicker();
    _uniforms.timeDelta = 0.0;
    _uniforms.frameRate = 0.0;
    final audio = _findActiveAudioChannel();
    if (audio is SoLoudAudioChannel) {
      audio.pause();
    }
    notifyListeners();
  }

  void togglePlay() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void rewind() {
    _uniforms.time = 0.0;
    _uniforms.frame = 0;
    _uniforms.timeDelta = isPlaying ? 0.016 : 0.0;
    _lastTimestamp = 0.0;
    _renderer.clearAudio();
    _keyboard.reset();
    _renderer.gpuRenderer.clearPingPongBuffers();
    final audio = _findActiveAudioChannel();
    if (audio is SoLoudAudioChannel) {
      audio.seek(Duration.zero);
    }
    renderSingleFrame();
    notifyListeners();
  }

  void resize(ui.Size newSize) {
    if (newSize.width <= 0 || newSize.height <= 0) return;
    if (_uniforms.resolution == newSize) return;

    _uniforms.resolution = newSize;
    _renderer.resize(newSize.width.toInt(), newSize.height.toInt());
    renderSingleFrame();
  }

  void handlePointerDown(ui.Offset localPosition) {
    final flippedY = _uniforms.resolution.height - localPosition.dy;
    _uniforms.mouse = Offset4(
      localPosition.dx,
      flippedY,
      localPosition.dx,
      flippedY,
    );
    notifyListeners();
  }

  void handlePointerMove(ui.Offset localPosition) {
    final flippedY = _uniforms.resolution.height - localPosition.dy;
    _uniforms.mouse = Offset4(
      localPosition.dx,
      flippedY,
      _uniforms.mouse.z,
      _uniforms.mouse.w,
    );
    notifyListeners();
  }

  void handlePointerUp([ui.Offset? localPosition]) {
    final hasValidPos = localPosition != null && localPosition != ui.Offset.zero;
    final x = hasValidPos ? localPosition.dx : _uniforms.mouse.x;
    final y = hasValidPos
        ? (_uniforms.resolution.height - localPosition.dy)
        : _uniforms.mouse.y;
    _uniforms.mouse = Offset4(
      x,
      y,
      -_uniforms.mouse.z.abs(),
      -_uniforms.mouse.w.abs(),
    );
    notifyListeners();
  }

  /// Handles a keyboard event and updates the 256x3 keyboard texture state.
  bool handleKeyEvent(KeyEvent event) {
    final handled = _keyboard.handleKeyEvent(event);
    if (handled) {
      notifyListeners();
      if (!isPlaying) {
        renderSingleFrame();
      }
    }
    return handled;
  }

  void _onTick(Duration elapsed) {
    if (!isPlaying) return;

    final currentSec = elapsed.inMicroseconds / 1000000.0;
    if (_lastTimestamp == 0.0) {
      _lastTimestamp = currentSec;
      return;
    }

    final dt = currentSec - _lastTimestamp;
    _lastTimestamp = currentSec;

    if (dt > 0.0 && dt < 0.5) {
      _uniforms.time += dt;
      _uniforms.timeDelta = dt;
      _uniforms.frame++;

      final currentFps = 1.0 / dt;
      _fpsHistory.add(currentFps);
      if (_fpsHistory.length > 20) {
        _fpsHistory.removeAt(0);
      }
      final avgFps = _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;
      _uniforms.frameRate = avgFps;

      final audioChannel = _findActiveAudioChannel();
      if (audioChannel != null) {
        if (audioChannel is SoLoudAudioChannel) {
          audioChannel.updatePlaybackTime(dt);
        }
      }

      if (!_isRendering) {
        renderSingleFrame();
      }
    }
  }

  void _bindAudioChannelListener() {
    final audio = _findActiveAudioChannel();
    if (_boundAudioChannel != audio) {
      _boundAudioChannel?.removeListener(_onAudioDataUpdated);
      _boundAudioChannel = audio;
      _boundAudioChannel?.addListener(_onAudioDataUpdated);
    }
  }

  Future<void> _initProjectChannels() async {
    for (final pass in _project.passes) {
      for (int i = 0; i < pass.channels.length; i++) {
        final ch = pass.channels[i];
        if (ch is SoLoudAudioChannel) {
          if (ch.src != null && ch.src!.isNotEmpty) {
            try {
              await ch.initAudio(src: ch.src);
              if (!isPlaying) {
                await ch.pause();
              }
            } catch (e) {
              flutter_foundation.debugPrint(
                'Failed to init SoLoudAudioChannel: $e',
              );
            }
          }
        } else if (ch is MicAudioChannel) {
          try {
            await ch.startListening();
          } catch (e) {
            flutter_foundation.debugPrint('Failed to start MicAudioChannel: $e');
          }
        } else if (ch is TextureChannel) {
          try {
            await _uploadTextureChannel(i, ch);
          } catch (e) {
            flutter_foundation.debugPrint(
              'Failed to load TextureChannel image: $e',
            );
          }
        }
      }
    }
    _bindAudioChannelListener();
  }

  /// Updates sampler filter, wrap, or vflip settings of [channelIndex] in the active pass.
  Future<void> updateChannelSettings(
    int channelIndex, {
    ChannelFilter? filter,
    ChannelWrap? wrap,
    bool? vflip,
  }) async {
    final ch = activePass?.getChannel(channelIndex);
    if (ch == null) return;

    bool needsReupload = false;
    if (filter != null) ch.filter = filter;
    if (wrap != null) ch.wrap = wrap;
    if (vflip != null && ch is TextureChannel && ch.vflip != vflip) {
      ch.vflip = vflip;
      needsReupload = true;
    }

    if (needsReupload && ch is TextureChannel) {
      await _uploadTextureChannel(channelIndex, ch);
    }

    renderSingleFrame();
    notifyListeners();
  }

  Future<void> _uploadTextureChannel(
    int channelIndex,
    TextureChannel channel,
  ) async {
    final img = await channel.loadImage();
    var rawRgba = channel.rawRgbaBytes;
    int? w = channel.imageWidth;
    int? h = channel.imageHeight;

    if (rawRgba == null && img != null) {
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData != null) {
        rawRgba = byteData.buffer.asUint8List();
        w = img.width;
        h = img.height;
      }
    }

    if (rawRgba != null && w != null && h != null) {
      final bytesToUpload = channel.vflip ? flipY(rawRgba, w, h) : rawRgba;
      _renderer.gpuRenderer.uploadTextureChannel(
        channelIndex,
        bytesToUpload,
        w,
        h,
      );
    }
  }

  /// Inverts the vertical rows of a 32-bit RGBA pixel buffer.
  static Uint8List flipY(Uint8List src, int width, int height) {
    final dst = Uint8List(src.length);
    final rowBytes = width * 4;
    for (int y = 0; y < height; y++) {
      final srcOffset = y * rowBytes;
      final dstOffset = (height - 1 - y) * rowBytes;
      dst.setRange(dstOffset, dstOffset + rowBytes, src, srcOffset);
    }
    return dst;
  }

  void _onAudioDataUpdated() {
    if (isPlaying && !_isRendering && !_isDisposed) {
      renderSingleFrame();
    }
  }

  AudioChannel? _findActiveAudioChannel() {
    final active = activePass;
    if (active != null) {
      for (final ch in active.channels) {
        if (ch is AudioChannel) return ch;
      }
    }
    return null;
  }

  /// Renders a single frame and updates the current image output.
  Future<void> renderSingleFrame() async {
    if (_isRendering || _isDisposed) return;
    _isRendering = true;
    try {
      final audio = _findActiveAudioChannel();
      if (audio == null) {
        _renderer.clearAudio();
      }
      final hasKeyboard = _project.passes.any(
        (p) => p.channels.any((c) => c is KeyboardChannel),
      );
      if (!hasKeyboard) {
        _renderer.clearKeyboard();
      }
      final img = await _renderer.renderFrame(
        uniforms: _uniforms,
        passes: _project.passes,
        activePass: activePass,
        activeAudioChannel: audio,
        keyboardData: hasKeyboard ? _keyboard.pixelData : null,
      );
      _keyboard.endFrame();
      if (_isDisposed) {
        img?.dispose();
        return;
      }
      if (img != null) {
        currentImageNotifier.value?.dispose();
        currentImageNotifier.value = img;
        notifyListeners();
      }
    } catch (e) {
      flutter_foundation.debugPrint('Render error: $e');
    } finally {
      _isRendering = false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _boundAudioChannel?.removeListener(_onAudioDataUpdated);
    _boundAudioChannel = null;
    _stopTicker();
    _ticker?.dispose();
    _ticker = null;
    _vsync = null;
    _attachedVsync = null;
    currentImageNotifier.value?.dispose();
    currentImageNotifier.value = null;
    isPlayingNotifier.dispose();
    isCompilingNotifier.dispose();
    lastErrorNotifier.dispose();
    activePassIndexNotifier.dispose();
    currentImageNotifier.dispose();
    _renderer.dispose();
    for (final pass in _project.passes) {
      pass.dispose();
    }
    super.dispose();
  }
}
