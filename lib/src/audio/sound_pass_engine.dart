// The realtime stream API of flutter_soloud is still marked experimental.
// ignore_for_file: experimental_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../compiler/impeller_compiler.dart';
import '../core/common_uniforms.dart';
import '../core/shader_pass.dart';
import '../renderer/gpu_renderer.dart';

/// Width of the offscreen sound synthesis texture.
const int kSoundTextureWidth = 256;

/// Height of the offscreen sound synthesis texture.
const int kSoundTextureHeight = 256;

/// Total number of audio samples computed in one GPU render chunk (256x256 = 65,536).
const int kSoundChunkSamples = kSoundTextureWidth * kSoundTextureHeight;

/// Total bytes of stereo 32-bit float PCM per chunk (65,536 * 2 * 4 = 524,288 bytes = 512 KB).
const int kSoundChunkSizeBytes = kSoundChunkSamples * 2 * 4;

/// Height of the offscreen texture in reactive sound mode (256 x 8 = 2,048 samples ≈ 46.4ms at 44.1 kHz).
const int kReactiveSoundTextureHeight = 8;

/// Number of stereo audio frames per reactive chunk (256 x 8 = 2,048 samples).
const int kReactiveSoundChunkSamples =
    kSoundTextureWidth * kReactiveSoundTextureHeight;

/// Total bytes of stereo 32-bit float PCM per reactive chunk (2,048 * 2 * 4 = 16,384 bytes).
const int kReactiveSoundChunkSizeBytes = kReactiveSoundChunkSamples * 2 * 4;

/// Manages continuous procedural audio synthesis for [PassType.sound].
///
/// For static shaders, renders 256x256 audio textures on the GPU in 512 KB chunks
/// (~1.486s at 44.1 kHz). For reactive shaders that sample upstream buffers,
/// textures, keyboard, audio, or custom uniforms, uses small low-latency 256x8
/// chunks (~46.4ms) synchronized with the visual frame loop.
///
/// The two modes feed different SoLoud sources. Static chunks go to a buffer
/// stream, which holds seconds of audio. Reactive chunks go to a realtime
/// stream: a lock-free ring that never pauses the voice to buffer, and fades
/// to silence instead when a chunk arrives late.
///
/// NOTE (Web): On Flutter Web (`dart:ui`), [ui.ImageByteFormat.rawExtendedRgba128] is not
/// available yet. As a result, [ui.ImageByteFormat.rawStraightRgba] (8-bit UNorm) is used as
/// a fallback, which can introduce background noise or distortion due to 8-bit quantization.
class SoundPassEngine {
  SoundPassEngine({
    this._renderer,
    this._uniformsProvider,
    this._commonCodeProvider,
  });

  final FlutterGpuRenderer? _renderer;
  final CommonUniforms Function()? _uniformsProvider;
  final String? Function()? _commonCodeProvider;

  AudioSource? _audioSource;
  SoundHandle? _soundHandle;

  /// The realtime stream behind [_audioSource] in reactive mode, else null.
  RealtimeStreamHandle? _realtimeStream;

  /// Frames pushed to [_realtimeStream] since it was created or rewound.
  int _realtimeFramesPushed = 0;

  /// Ring capacity of the reactive stream: four reactive chunks.
  static const int _kRealtimeBufferFrames = kReactiveSoundChunkSamples * 4;
  Timer? _timer;

  bool _isStreaming = false;
  bool _isPaused = false;
  bool _isReactive = false;
  Object? _activeChunkRenderToken;
  int _startGeneration = 0;

  double _currentBlockOffset = 0.0;
  int _currentSampleOffset = 0;
  double _sampleRate = 44100.0;
  ShaderPass? _activeSoundPass;

  bool get isStreaming => _isStreaming;
  bool get isPaused => _isPaused;
  bool get isReactive => _isReactive;
  AudioSource? get audioSource => _audioSource;
  SoundHandle? get soundHandle => _soundHandle;
  double get currentBlockOffset => _currentBlockOffset;
  double get sampleRate => _sampleRate;

  bool get _isRenderingChunk => _activeChunkRenderToken != null;

  int get _activeTextureHeight =>
      _isReactive ? kReactiveSoundTextureHeight : kSoundTextureHeight;
  int get _activeChunkSamples =>
      _isReactive ? kReactiveSoundChunkSamples : kSoundChunkSamples;
  int get _activeChunkSizeBytes =>
      _isReactive ? kReactiveSoundChunkSizeBytes : kSoundChunkSizeBytes;

  /// Returns `true` if [soundPass] reads any input channel (`iChannel0..3`),
  /// has configured channels, or declares custom uniforms.
  static bool detectReactivePass(ShaderPass soundPass, {String? commonCode}) {
    if (soundPass.channels.any((c) => c != null)) {
      return true;
    }
    final effectiveCode = (commonCode != null && commonCode.isNotEmpty)
        ? '$commonCode\n${soundPass.code}'
        : soundPass.code;
    for (int i = 0; i < 4; i++) {
      if (ImpellerCompiler.shaderUsesChannel(effectiveCode, i)) {
        return true;
      }
    }
    if (ImpellerCompiler.extractCustomUniforms(effectiveCode).isNotEmpty) {
      return true;
    }
    return false;
  }

  /// Elapsed playback time in seconds reported by the audio stream DAC.
  ///
  /// Returns `null` if streaming is not active.
  double? get playbackTime {
    if (!_isStreaming || _audioSource == null) return null;
    final realtime = _realtimeStream;
    if (realtime != null) {
      // What the mixer has taken out of the ring so far.
      try {
        final consumed = _realtimeFramesPushed - realtime.availableToRead;
        return (consumed < 0 ? 0 : consumed) / _sampleRate;
      } catch (_) {
        return null;
      }
    }
    try {
      final duration = SoLoud.instance.getStreamTimeConsumed(_audioSource!);
      return duration.inMicroseconds / 1000000.0;
    } catch (_) {
      return null;
    }
  }

  /// Starts or restarts procedural audio streaming for [soundPass].
  Future<void> start({
    required ShaderPass soundPass,
    required double sampleRate,
    bool paused = false,
  }) async {
    final gen = ++_startGeneration;
    _stopStream();

    _activeSoundPass = soundPass;
    _sampleRate = sampleRate > 0 ? sampleRate : 44100.0;
    _isReactive = detectReactivePass(
      soundPass,
      commonCode: _commonCodeProvider?.call(),
    );

    // Ensure SoLoud is initialized
    if (!SoLoud.instance.isInitialized) {
      try {
        await SoLoud.instance.init(renderAheadFrames: kSoLoudRenderAheadFrames);
      } catch (e) {
        debugPrint('SoundPassEngine: Failed to initialize SoLoud: $e');
        return;
      }
    }
    if (gen != _startGeneration) return;

    try {
      final AudioSource source;
      if (_isReactive) {
        final realtime = SoLoud.instance.setRealtimeStream(
          sampleRate: _sampleRate.toInt(),
          bufferFrames: _kRealtimeBufferFrames,
        );
        _realtimeStream = realtime;
        _realtimeFramesPushed = 0;
        source = realtime.source;
      } else {
        source = SoLoud.instance.setBufferStream(
          maxBufferSizeBytes: 1024 * 1024 * 10,
          sampleRate: _sampleRate.toInt(),
          channels: Channels.stereo,
          format: BufferType.f32le,
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0.5,
        );
      }
      _audioSource = source;

      _isStreaming = true;
      _isPaused = paused;
      _currentBlockOffset = 0.0;
      _currentSampleOffset = 0;

      // Register the active voice handle BEFORE pushing chunks so SoLoud's
      // BufferStream::checkBuffering() finds an active handle immediately.
      _soundHandle = SoLoud.instance.play(source, paused: _isPaused);
      _realtimeStream?.bindActiveVoice(_soundHandle);

      // Pre-buffer 2 initial chunks.
      for (int i = 0; i < 2; i++) {
        if (gen != _startGeneration ||
            !_isStreaming ||
            !identical(_audioSource, source)) {
          return;
        }
        await _renderAndPushNextChunk();
      }

      if (gen != _startGeneration || !_isStreaming) return;

      // Fallback timer in case visual ticks stop (e.g. offscreen), kept gentle
      // in reactive mode so it does not compete with onFrameRendered().
      _timer?.cancel();
      _timer = Timer.periodic(
        Duration(milliseconds: _isReactive ? 50 : 500),
        (_) => _checkAndFillBuffer(),
      );
    } catch (e) {
      debugPrint('SoundPassEngine: Failed to start sound pass stream: $e');
      if (gen == _startGeneration) {
        stop();
      }
    }
  }

  /// Triggers a buffer check right after a visual frame updates buffer passes.
  Future<void> onFrameRendered() => _checkAndFillBuffer();

  /// Checks buffer capacity and schedules the next chunk(s) if buffer is running low.
  Future<void> _checkAndFillBuffer() async {
    if (!_isStreaming || _isPaused || _isRenderingChunk) return;
    final source = _audioSource;
    if (source == null) return;

    final soloud = SoLoud.instance;
    final handle = _soundHandle;
    if (handle != null && !soloud.getIsValidVoiceHandle(handle)) {
      return;
    }

    try {
      final realtime = _realtimeStream;
      final targetBufferBytes = _activeChunkSizeBytes * 2;
      // Keep one engine mix quantum plus a chunk queued, and at least two
      // chunks: below one quantum the ring runs dry on every mix.
      final quantumTarget =
          (realtime?.engineQuantumFrames ?? 0) + _activeChunkSamples;
      final targetBufferFrames = quantumTarget > _activeChunkSamples * 2
          ? quantumTarget
          : _activeChunkSamples * 2;
      bool needsChunk() => realtime != null
          ? realtime.availableToRead < targetBufferFrames &&
                realtime.availableToWrite >= _activeChunkSamples
          : soloud.getBufferSize(source) < targetBufferBytes;

      final maxChunksPerCheck = _isReactive ? 3 : 1;
      int chunksPushed = 0;
      while (_isStreaming &&
          !_isPaused &&
          _audioSource != null &&
          identical(_audioSource, source) &&
          chunksPushed < maxChunksPerCheck &&
          needsChunk()) {
        await _renderAndPushNextChunk();
        chunksPushed++;
      }
    } catch (_) {}
  }

  /// Renders a chunk at the current [_currentBlockOffset] and pushes to SoLoud.
  Future<void> _renderAndPushNextChunk() async {
    if (_isRenderingChunk || _activeSoundPass == null || _renderer == null) {
      return;
    }
    final targetSource = _audioSource;
    if (targetSource == null || !_isStreaming) return;

    final gen = _startGeneration;
    final renderToken = Object();
    _activeChunkRenderToken = renderToken;

    try {
      final chunkSamples = _activeChunkSamples;
      final pcmBytes = await _renderer.renderSoundPass(
        soundPass: _activeSoundPass!,
        blockOffset: _currentBlockOffset,
        sampleRate: _sampleRate,
        width: kSoundTextureWidth,
        height: _activeTextureHeight,
        uniforms: _uniformsProvider?.call(),
        commonCode: _commonCodeProvider?.call(),
      );

      if (pcmBytes != null &&
          gen == _startGeneration &&
          _isStreaming &&
          identical(_audioSource, targetSource)) {
        final realtime = _realtimeStream;
        var framesAccepted = chunkSamples;
        if (realtime != null) {
          framesAccepted = realtime.pushFloat32(
            _asFloat32(pcmBytes),
            frameCount: chunkSamples,
          );
          _realtimeFramesPushed += framesAccepted;
        } else {
          SoLoud.instance.addAudioDataStream(targetSource, pcmBytes);
        }
        // Advance by what was really queued, so a full ring does not skip
        // part of the timeline.
        _currentSampleOffset += framesAccepted;
        _currentBlockOffset = _currentSampleOffset / _sampleRate;
      }
    } catch (e) {
      debugPrint('SoundPassEngine: Error pushing sound chunk: $e');
    } finally {
      if (identical(_activeChunkRenderToken, renderToken)) {
        _activeChunkRenderToken = null;
      }
    }
  }

  /// [bytes] as 32-bit float samples, without a copy when its offset allows.
  static Float32List _asFloat32(Uint8List bytes) {
    final length = bytes.lengthInBytes ~/ 4;
    if (bytes.offsetInBytes % 4 == 0) {
      return bytes.buffer.asFloat32List(bytes.offsetInBytes, length);
    }
    return Uint8List.fromList(bytes).buffer.asFloat32List(0, length);
  }

  /// Pauses audio playback.
  void pause() {
    if (!_isStreaming || _isPaused) return;
    _isPaused = true;
    final handle = _soundHandle;
    if (handle != null) {
      try {
        SoLoud.instance.setPause(handle, true);
      } catch (_) {}
    }
  }

  /// Resumes audio playback.
  void resume() {
    if (!_isStreaming || !_isPaused) return;
    _isPaused = false;
    final handle = _soundHandle;
    if (handle != null) {
      try {
        SoLoud.instance.setPause(handle, false);
      } catch (_) {}
    }
    unawaited(_checkAndFillBuffer());
  }

  /// Rewinds audio stream back to t = 0.0s.
  Future<void> rewind() async {
    if (!_isStreaming) return;
    final gen = ++_startGeneration;
    _activeChunkRenderToken = null;
    final source = _audioSource;
    if (source != null) {
      try {
        final realtime = _realtimeStream;
        if (realtime != null) {
          realtime.reset();
          _realtimeFramesPushed = 0;
        } else {
          SoLoud.instance.resetBufferStream(source);
        }
      } catch (_) {}
    }

    _currentBlockOffset = 0.0;
    _currentSampleOffset = 0;
    await _renderAndPushNextChunk();
    if (gen != _startGeneration || !_isStreaming) return;
    await _renderAndPushNextChunk();
  }

  void _stopStream() {
    _timer?.cancel();
    _timer = null;

    final source = _audioSource;
    if (source != null) {
      try {
        SoLoud.instance.disposeSource(source);
      } catch (_) {}
      _audioSource = null;
    }
    _realtimeStream = null;
    _realtimeFramesPushed = 0;

    _soundHandle = null;
    _isStreaming = false;
    _isPaused = false;
    _isReactive = false;
    _activeChunkRenderToken = null;
    _currentBlockOffset = 0.0;
    _currentSampleOffset = 0;
  }

  /// Stops streaming and frees audio sources.
  void stop() {
    _startGeneration++;
    _stopStream();
  }

  /// Disposes the engine and frees all resources.
  void dispose() {
    stop();
  }
}
