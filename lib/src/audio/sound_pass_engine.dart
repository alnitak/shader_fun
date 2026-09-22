import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

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

/// Manages continuous procedural audio synthesis for [PassType.sound].
///
/// Renders 256x256 audio textures on the GPU in 512 KB chunks (~1.486s at 44.1 kHz),
/// extracts stereo 32-bit float PCM data, and streams the chunks to [SoLoud.instance.setBufferStream]
/// with [BufferingType.released] for continuous, seamless, glitch-free audio output.
class SoundPassEngine {
  SoundPassEngine({FlutterGpuRenderer? renderer})
    // ignore: prefer_initializing_formals
    : _renderer = renderer;

  final FlutterGpuRenderer? _renderer;

  AudioSource? _audioSource;
  SoundHandle? _soundHandle;
  Timer? _timer;

  bool _isStreaming = false;
  bool _isPaused = false;
  bool _isRenderingChunk = false;

  double _currentBlockOffset = 0.0;
  double _sampleRate = 44100.0;
  ShaderPass? _activeSoundPass;

  bool get isStreaming => _isStreaming;
  bool get isPaused => _isPaused;
  AudioSource? get audioSource => _audioSource;
  SoundHandle? get soundHandle => _soundHandle;
  double get currentBlockOffset => _currentBlockOffset;
  double get sampleRate => _sampleRate;

  /// Starts or restarts procedural audio streaming for [soundPass].
  Future<void> start({
    required ShaderPass soundPass,
    required double sampleRate,
  }) async {
    _activeSoundPass = soundPass;
    _sampleRate = sampleRate > 0 ? sampleRate : 44100.0;

    // Ensure SoLoud is initialized
    if (!SoLoud.instance.isInitialized) {
      try {
        await SoLoud.instance.init();
      } catch (e) {
        debugPrint('SoundPassEngine: Failed to initialize SoLoud: $e');
        return;
      }
    }

    // Stop any existing stream
    stop();

    try {
      _audioSource = SoLoud.instance.setBufferStream(
        sampleRate: _sampleRate.toInt(),
        channels: Channels.stereo,
        format: BufferType.f32le,
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.5,
      );

      _soundHandle = SoLoud.instance.play(_audioSource!);
      _isStreaming = true;
      _isPaused = false;
      _currentBlockOffset = 0.0;

      // Pre-buffer Chunk 0 (0.0s .. ~1.486s) and Chunk 1 (~1.486s .. ~2.972s)
      await _renderAndPushNextChunk();
      await _renderAndPushNextChunk();

      // Maintenance timer to keep ~2 to 3 seconds of audio queued ahead of the DAC
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _checkAndFillBuffer(),
      );
    } catch (e) {
      debugPrint('SoundPassEngine: Failed to start sound pass stream: $e');
      stop();
    }
  }

  /// Checks buffer capacity and schedules the next chunk if buffer is running low.
  Future<void> _checkAndFillBuffer() async {
    if (!_isStreaming || _isPaused || _isRenderingChunk) return;
    final source = _audioSource;
    if (source == null) return;

    try {
      final bufferedBytes = SoLoud.instance.getBufferSize(source);
      // If buffer is below 2 chunks (~3 seconds of audio), queue another chunk
      if (bufferedBytes < kSoundChunkSizeBytes * 2) {
        await _renderAndPushNextChunk();
      }
    } catch (_) {}
  }

  /// Renders a 256x256 chunk at the current [_currentBlockOffset] and pushes to SoLoud.
  Future<void> _renderAndPushNextChunk() async {
    if (_isRenderingChunk || _activeSoundPass == null || _renderer == null) return;
    _isRenderingChunk = true;

    try {
      final pcmBytes = await _renderer.renderSoundPass(
        soundPass: _activeSoundPass!,
        blockOffset: _currentBlockOffset,
        sampleRate: _sampleRate,
        width: kSoundTextureWidth,
        height: kSoundTextureHeight,
      );

      if (pcmBytes != null && _audioSource != null && _isStreaming) {
        SoLoud.instance.addAudioDataStream(_audioSource!, pcmBytes);
        _currentBlockOffset += kSoundChunkSamples / _sampleRate;
      }
    } catch (e) {
      debugPrint('SoundPassEngine: Error pushing sound chunk: $e');
    } finally {
      _isRenderingChunk = false;
    }
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
    final source = _audioSource;
    if (source != null) {
      try {
        SoLoud.instance.resetBufferStream(source);
      } catch (_) {}
    }

    _currentBlockOffset = 0.0;
    await _renderAndPushNextChunk();
    await _renderAndPushNextChunk();
  }

  /// Stops streaming and frees audio sources.
  void stop() {
    _timer?.cancel();
    _timer = null;

    final source = _audioSource;
    if (source != null) {
      try {
        SoLoud.instance.disposeSource(source);
      } catch (_) {}
      _audioSource = null;
    }

    _soundHandle = null;
    _isStreaming = false;
    _isPaused = false;
    _isRenderingChunk = false;
    _currentBlockOffset = 0.0;
  }

  /// Disposes the engine and frees all resources.
  void dispose() {
    stop();
  }
}
