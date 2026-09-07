import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    hide ChangeNotifier, Listenable, ValueListenable, ValueNotifier;
import 'package:flutter_recorder/flutter_recorder.dart' as rec;
import 'package:flutter_soloud/flutter_soloud.dart' as sl;
import 'package:listen/listen.dart' as listen;

import 'shader_channel.dart';

/// ShaderToy standard audio texture size: 1024 columns x 2 rows.
/// Row 0 (y = 0 / 0.25): FFT frequency spectrum (1024 bins, 0.0 to 1.0)
/// Row 1 (y = 1 / 0.75): Waveform amplitude (1024 samples, 0.0 to 1.0)
const int kAudioTextureWidth = 1024;
const int kAudioTextureHeight = 2;

/// Abstract base class for ShaderToy audio channels.
/// Implements [listen.ChangeNotifier] to dispatch updates when audio data changes.
abstract class AudioChannel extends ShaderChannel with listen.ChangeNotifier {
  AudioChannel({
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  }) {
    // Initialize buffers with quiet defaults
    _initBuffers();
  }

  final Float32List _fftData = Float32List(kAudioTextureWidth);
  final Float32List _waveData = Float32List(kAudioTextureWidth);
  final Uint8List _pixelData = Uint8List(
    kAudioTextureWidth * kAudioTextureHeight * 4,
  );

  ui.Image? _cachedTextureImage;
  bool _textureDirty = true;

  Float32List get fftData => _fftData;
  Float32List get waveData => _waveData;
  Uint8List get pixelData => _pixelData;

  @override
  ui.Size get resolution =>
      const ui.Size(kAudioTextureWidth + 0.0, kAudioTextureHeight + 0.0);

  bool get isPlaying;

  bool _audioDisposed = false;

  @override
  bool get isDisposed => _audioDisposed || super.isDisposed;

  ui.VoidCallback? _onAudioDataUpdated;

  /// Optional legacy callback for backwards compatibility; prefer [addListener].
  ui.VoidCallback? get onAudioDataUpdated => _onAudioDataUpdated;
  set onAudioDataUpdated(ui.VoidCallback? callback) {
    if (_onAudioDataUpdated != null) {
      removeListener(_onAudioDataUpdated!);
    }
    _onAudioDataUpdated = callback;
    if (_onAudioDataUpdated != null) {
      addListener(_onAudioDataUpdated!);
    }
  }

  void _initBuffers() {
    // Center waveform at 0.5 (silence)
    for (int i = 0; i < kAudioTextureWidth; i++) {
      _fftData[i] = 0.0;
      _waveData[i] = 0.5;
    }
    _updatePixelBytes();
  }

  /// Updates the 512x2 RGBA pixel byte buffer from FFT and Wave data.
  void _updatePixelBytes() {
    // Row 0: FFT frequency values
    for (int x = 0; x < kAudioTextureWidth; x++) {
      final val = (_fftData[x].clamp(0.0, 1.0) * 255.0).round();
      final idx = x * 4;
      _pixelData[idx] = val; // R
      _pixelData[idx + 1] = val; // G
      _pixelData[idx + 2] = val; // B
      _pixelData[idx + 3] = 255; // A
    }

    // Row 1: Waveform amplitude values
    final row1Offset = kAudioTextureWidth * 4;
    for (int x = 0; x < kAudioTextureWidth; x++) {
      final val = (_waveData[x].clamp(0.0, 1.0) * 255.0).round();
      final idx = row1Offset + x * 4;
      _pixelData[idx] = val; // R
      _pixelData[idx + 1] = val; // G
      _pixelData[idx + 2] = val; // B
      _pixelData[idx + 3] = 255; // A
    }

    _textureDirty = true;
  }

  /// Updates the FFT and Waveform data from incoming audio samples.
  void updateAudioData({Float32List? newFft, Float32List? newWave}) {
    if (newFft != null && newFft.isNotEmpty) {
      final step = newFft.length / kAudioTextureWidth;
      for (int i = 0; i < kAudioTextureWidth; i++) {
        final idx = (i * step).toInt().clamp(0, newFft.length - 1);
        _fftData[i] = newFft[idx].clamp(0.0, 1.0);
      }
    }

    if (newWave != null && newWave.isNotEmpty) {
      final step = newWave.length / kAudioTextureWidth;
      for (int i = 0; i < kAudioTextureWidth; i++) {
        final idx = (i * step).toInt().clamp(0, newWave.length - 1);
        final s = newWave[idx];
        // miniaudio / flutter_recorder wave samples are [-1.0, 1.0].
        // ShaderToy audio texture stores waveform amplitude normalized to [0.0, 1.0], centered at 0.5.
        _waveData[i] = ((s + 1.0) * 0.5).clamp(0.0, 1.0);
      }
    }

    _updatePixelBytes();
    if (!isDisposed) {
      notifyListeners();
    }
  }

  /// Converts the 1024x2 pixel buffer to a ui.Image for sampling.
  Future<ui.Image> toUiImage() async {
    if (_cachedTextureImage != null && !_textureDirty) {
      return _cachedTextureImage!;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixelData,
      kAudioTextureWidth,
      kAudioTextureHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedTextureImage?.dispose();
        _cachedTextureImage = image;
        _textureDirty = false;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  @override
  void dispose() {
    if (_audioDisposed) return;
    _audioDisposed = true;
    _cachedTextureImage?.dispose();
    _cachedTextureImage = null;
    super.dispose();
  }
}

/// Audio channel backed by `flutter_soloud` for playing music files and generating FFT/Waveform textures.
class SoLoudAudioChannel extends AudioChannel {
  SoLoudAudioChannel({
    String? src,
    String? audioPath,
    this.audioName = 'Music Track',
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  }) : src = src ?? audioPath;

  /// Source URI, file path, or Flutter asset path.
  final String? src;

  /// Backwards compatibility getter.
  String? get audioPath => src;
  final String audioName;

  sl.SoundHandle? _soundHandle;
  sl.AudioSource? _audioSource;
  StreamSubscription<sl.AudioVisualizationData>? _vizSubscription;
  bool _isPlaying = false;
  double _playbackTime = 0.0;

  @override
  ChannelType get type => ChannelType.audio;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get time => _playbackTime;

  /// Initializes flutter_soloud visualization and audio playback.
  /// Supports network URLs (`http://`, `https://`), local files (`file://`, `/`), and assets.
  Future<void> initAudio({String? assetPath, String? src}) async {
    try {
      final soloud = sl.SoLoud.instance;
      if (!soloud.isInitialized) {
        await soloud.init();
      }

      soloud.setVisualizationEnabled(
        true,
        windowSize: 1024,
        kind: sl.VisualizationKind.waveAndFft,
        channel: sl.VisualizationChannel.merged,
      );
      soloud.setFftSmoothing(0.6);

      _vizSubscription?.cancel();
      _vizSubscription = soloud.audioVisualizationEvents.listen((data) {
        final newFft =
            data.fftData ?? (data.fft.isNotEmpty ? data.fft.first : null);
        final newWave =
            data.waveData ?? (data.wave.isNotEmpty ? data.wave.first : null);
        updateAudioData(newFft: newFft, newWave: newWave);
      });

      final targetPath = src ?? assetPath ?? this.src;
      if (targetPath != null && targetPath.isNotEmpty) {
        await soloud.disposeAllSources();

        if (targetPath.startsWith('http://') ||
            targetPath.startsWith('https://')) {
          _audioSource = await soloud.loadUrl(targetPath);
        } else if (targetPath.startsWith('file://') ||
            targetPath.startsWith('/') ||
            RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(targetPath)) {
          final clean = targetPath.startsWith('file://')
              ? Uri.parse(targetPath).toFilePath()
              : targetPath;
          _audioSource = await soloud.loadFile(clean);
        } else {
          var assetToLoad = targetPath;
          if (!assetToLoad.startsWith('assets/') &&
              !assetToLoad.startsWith('packages/') &&
              !assetToLoad.contains('/')) {
            assetToLoad = 'assets/audio/$assetToLoad';
          }
          _audioSource = await soloud.loadAsset(assetToLoad);
        }

        _soundHandle = soloud.play(_audioSource!, looping: true);
        _isPlaying = true;
        soloud.setVisualizationEnabled(
          true,
          windowSize: 1024,
          kind: sl.VisualizationKind.waveAndFft,
          channel: sl.VisualizationChannel.merged,
        );
      }
    } catch (e) {
      // Fallback to synthetic waves if audio device is unavailable
      _isPlaying = false;
    }
  }

  void updatePlaybackTime(double dt) {
    if (_isPlaying) {
      _playbackTime += dt;
    }
  }

  Future<void> pause() async {
    if (_soundHandle != null && _isPlaying) {
      try {
        sl.SoLoud.instance.setPause(_soundHandle!, true);
      } catch (_) {}
      _isPlaying = false;
    }
  }

  Future<void> resume() async {
    if (_soundHandle != null && !_isPlaying) {
      try {
        sl.SoLoud.instance.setPause(_soundHandle!, false);
      } catch (_) {}
      _isPlaying = true;
    } else if (_soundHandle == null && src != null && src!.isNotEmpty) {
      await initAudio(src: src);
    }
  }

  Future<void> seek(Duration position) async {
    if (_soundHandle != null) {
      try {
        sl.SoLoud.instance.seek(_soundHandle!, position);
      } catch (_) {}
      _playbackTime = position.inMilliseconds / 1000.0;
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _vizSubscription?.cancel();
    _vizSubscription = null;
    if (_soundHandle != null) {
      try {
        sl.SoLoud.instance.stop(_soundHandle!);
      } catch (_) {}
    }
    if (_audioSource != null) {
      try {
        sl.SoLoud.instance.disposeSource(_audioSource!);
      } catch (_) {}
    }
    super.dispose();
  }
}

/// Audio channel backed by `flutter_recorder` for live microphone FFT/Waveform textures.
class MicAudioChannel extends AudioChannel {
  MicAudioChannel({
    this.name = 'Microphone',
    this.micGain = 2.5,
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  });

  final String name;
  final double micGain;
  StreamSubscription<rec.AudioVisualizationData>? _vizSubscription;
  bool _isRecording = false;

  @override
  ChannelType get type => ChannelType.mic;

  @override
  bool get isPlaying => _isRecording;

  /// Initializes microphone capture.
  Future<void> initMicrophone() => startListening();

  /// Initializes flutter_recorder and starts microphone capture for visualization.
  Future<void> startListening() async {
    try {
      final recorder = rec.Recorder.instance;
      if (!recorder.isInitialized) {
        await recorder.init(
          format: rec.PCMFormat.f32le,
          sampleRate: 44100,
          channels: rec.RecorderChannels.mono,
        );
      }

      if (!recorder.isStarted) {
        recorder.start();
      }

      recorder.setVisualizationEnabled(
        true,
        windowSize: 1024,
        kind: rec.VisualizationKind.waveAndFft,
        channel: rec.VisualizationChannel.merged,
      );
      recorder.setFftSmoothing(0.6);

      _vizSubscription?.cancel();
      _vizSubscription = recorder.audioVisualizationEvents.listen(
        (data) {
          final rawFft =
              data.fftData ?? (data.fft.isNotEmpty ? data.fft.first : null);
          final rawWave =
              data.waveData ?? (data.wave.isNotEmpty ? data.wave.first : null);

          Float32List? boostedFft;
          if (rawFft != null) {
            boostedFft = Float32List(rawFft.length);
            for (int i = 0; i < rawFft.length; i++) {
              boostedFft[i] = (rawFft[i] * micGain).clamp(0.0, 1.0);
            }
          }

          Float32List? boostedWave;
          if (rawWave != null) {
            boostedWave = Float32List(rawWave.length);
            for (int i = 0; i < rawWave.length; i++) {
              boostedWave[i] = (rawWave[i] * micGain).clamp(-1.0, 1.0);
            }
          }

          updateAudioData(
            newFft: boostedFft ?? rawFft,
            newWave: boostedWave ?? rawWave,
          );
        },
        onError: (e) {
          debugPrint('[MicAudioChannel] Error in visualization stream: $e');
        },
      );
      _isRecording = true;
      debugPrint(
        '[MicAudioChannel] Live microphone capture started successfully',
      );
    } catch (e, st) {
      debugPrint('[MicAudioChannel] startListening failed: $e\n$st');
      _isRecording = false;
    }
  }

  Future<void> stopListening() async {
    _vizSubscription?.cancel();
    _vizSubscription = null;
    try {
      final recorder = rec.Recorder.instance;
      if (_isRecording || recorder.isStarted) {
        recorder.stop();
      }
    } catch (e) {
      debugPrint('[MicAudioChannel] stopListening error: $e');
    } finally {
      _isRecording = false;
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    stopListening();
    super.dispose();
  }
}
