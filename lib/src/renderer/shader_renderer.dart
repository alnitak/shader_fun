import 'dart:typed_data';
import 'dart:ui' as ui;

import '../channels/audio_texture_provider.dart';
import '../core/shader_pass.dart';
import '../core/common_uniforms.dart';
import 'compositor_renderer.dart';
import 'gpu_renderer.dart';

/// Unified rendering engine coordinating GPU pipelines and fallback compositing.
class ShaderRenderer {
  ShaderRenderer({int width = 800, int height = 450})
    : _width = width,
      _height = height {
    _gpuRenderer = FlutterGpuRenderer(width: width, height: height);
    _compositorRenderer = CompositorRenderer(width: width, height: height);
  }

  int _width;
  int _height;
  late final FlutterGpuRenderer _gpuRenderer;
  late final CompositorRenderer _compositorRenderer;

  int get width => _width;
  int get height => _height;
  bool get isUsingGpu => _gpuRenderer.isGpuAvailable;
  FlutterGpuRenderer get gpuRenderer => _gpuRenderer;

  Future<bool> loadShaderBundle(
    Uint8List bytes, {
    PassType passType = PassType.image,
    String? activeCode,
  }) {
    return _gpuRenderer.loadShaderBundle(
      bytes,
      passType: passType,
      activeCode: activeCode,
    );
  }

  void resize(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (_width == newWidth && _height == newHeight) return;

    _width = newWidth;
    _height = newHeight;
    _gpuRenderer.resize(newWidth, newHeight);
    _compositorRenderer.resize(newWidth, newHeight);
  }

  /// Renders a single frame and returns the resulting [ui.Image].
  Future<ui.Image?> renderFrame({
    required CommonUniforms uniforms,
    required List<ShaderPass> passes,
    ShaderPass? activePass,
    AudioChannel? activeAudioChannel,
    Uint8List? keyboardData,
  }) async {
    // 1. If Flutter GPU is supported on this device, execute on GPU
    if (_gpuRenderer.isGpuAvailable) {
      if (activeAudioChannel != null) {
        _gpuRenderer.uploadAudioTexture(activeAudioChannel);
      } else {
        _gpuRenderer.clearAudioTexture();
      }
      if (keyboardData != null) {
        _gpuRenderer.uploadKeyboardTexture(keyboardData);
      }
      final gpuImage = await _gpuRenderer.renderFrame(
        uniforms: uniforms,
        passes: passes,
        activePass: activePass,
        activeAudioChannel: activeAudioChannel,
      );
      // Return the GPU rendered frame. If the shader pipeline is still compiling,
      // return null so the UI waits cleanly for the real shader rather than flashing
      // an unrelated CPU compositor fallback scene.
      return gpuImage;
    }

    // 2. Fallback to Canvas Compositor ONLY when Flutter GPU is completely unsupported
    return _compositorRenderer.renderFrame(
      uniforms: uniforms,
      passes: passes,
      activeAudioChannel: activeAudioChannel,
    );
  }

  /// Clears active audio texture on the GPU renderer.
  void clearAudio() {
    _gpuRenderer.clearAudioTexture();
  }

  /// Clears active keyboard texture on the GPU renderer.
  void clearKeyboard() {
    _gpuRenderer.clearKeyboardTexture();
  }

  void dispose() {
    _gpuRenderer.dispose();
    _compositorRenderer.dispose();
  }
}
