import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../channels/audio_texture_provider.dart';
import '../compiler/impeller_compiler.dart';
import '../core/shader_pass.dart';
import '../core/shadertoy_uniforms.dart';

/// Low-level multi-pass renderer powered by Flutter GPU (`package:flutter_gpu/gpu.dart`).
/// Executes compiled shader bundles on full-screen quad geometry and renders to [gpu.GpuImageSurface].
class FlutterGpuRenderer {
  FlutterGpuRenderer({
    this.width = 800,
    this.height = 450,
  }) {
    _initGpuResources();
  }

  int width;
  int height;

  gpu.GpuImageSurface? _imageSurface;
  bool _isGpuAvailable = false;

  gpu.ShaderLibrary? _shaderLibrary;
  gpu.Shader? _vertexShader;
  gpu.Shader? _fragmentShader;
  gpu.RenderPipeline? _renderPipeline;
  String? _activeCode;

  gpu.ShaderLibrary? get shaderLibrary => _shaderLibrary;
  gpu.Shader? get vertexShader => _vertexShader;
  gpu.Shader? get fragmentShader => _fragmentShader;

  gpu.DeviceBuffer? _quadVertexBuffer;

  /// Cache of uploaded audio texture (512x2 RGBA)
  gpu.Texture? _audioTexture;

  /// Default 1x1 fallback texture to satisfy samplers when no channel texture is bound.
  gpu.Texture? _defaultTexture;

  /// Cache of uploaded 2D image textures per channel index
  final Map<int, gpu.Texture> _textureChannels = {};

  /// Ping-pong textures for buffer passes
  final Map<int, List<gpu.Texture>> _bufferPingPong = {};

  bool get isGpuAvailable => _isGpuAvailable;
  bool get hasPipeline => _renderPipeline != null;

  gpu.Texture? _getDefaultTexture() {
    if (!_isGpuAvailable) return null;
    try {
      if (_defaultTexture != null) return _defaultTexture;
      _defaultTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      final dummyBytes = Uint8List.fromList([0, 0, 0, 255]);
      _defaultTexture!.overwrite(ByteData.sublistView(dummyBytes));
      return _defaultTexture;
    } catch (e) {
      debugPrint('Failed to create default 1x1 texture: $e');
      return null;
    }
  }

  void _initGpuResources() {
    try {
      final context = gpu.gpuContext;
      _imageSurface = context.createImageSurface(width, height);
      _isGpuAvailable = true;
      _initQuadVertexBuffer();
      debugPrint('Flutter GPU initialized successfully (${width}x$height).');
    } catch (e) {
      _isGpuAvailable = false;
      debugPrint('Flutter GPU initialization: $e');
    }
  }

  /// Initializes the full-screen quad vertex buffer (two triangles, 6 vertices, 2 floats each).
  void _initQuadVertexBuffer() {
    if (!_isGpuAvailable) return;
    try {
      final vertices = Float32List.fromList([
        -1.0, -1.0,
         1.0, -1.0,
        -1.0,  1.0,
        -1.0,  1.0,
         1.0, -1.0,
         1.0,  1.0,
      ]);
      final byteData = ByteData.sublistView(vertices);
      _quadVertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(byteData);
    } catch (e) {
      debugPrint('Failed to allocate quad vertex buffer: $e');
    }
  }

  /// Loads a compiled `.shaderbundle` and builds the GPU render pipeline.
  Future<bool> loadShaderBundle(
    Uint8List bundleBytes, {
    String? activeCode,
  }) async {
    if (!_isGpuAvailable) {
      _initGpuResources();
    }
    if (!_isGpuAvailable) {
      debugPrint('Flutter GPU is not available (Impeller required).');
      return false;
    }
    try {
      final byteData = ByteData.sublistView(bundleBytes);
      final lib = await gpu.ShaderLibrary.fromBytes(byteData);
      if (lib == null) return false;

      final vert = lib['QuadVertex'];
      final frag = lib['ShadertoyFragment'];
      if (vert == null || frag == null) {
        debugPrint('Shader bundle missing QuadVertex or ShadertoyFragment');
        return false;
      }

      final pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);

      _shaderLibrary = lib;
      _vertexShader = vert;
      _fragmentShader = frag;
      _renderPipeline = pipeline;
      if (activeCode != null) {
        _activeCode = activeCode;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to load shader bundle into Flutter GPU: $e');
      return false;
    }
  }

  void resize(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (width == newWidth && height == newHeight) return;

    width = newWidth;
    height = newHeight;

    if (_imageSurface != null) {
      try {
        _imageSurface!.resize(width, height);
      } catch (_) {
        _initGpuResources();
      }
    }

    _clearPingPongBuffers();
  }

  void _clearPingPongBuffers() {
    _bufferPingPong.clear();
  }

  /// Uploads audio spectrum (FFT) and waveform data to a 512x2 GPU texture.
  gpu.Texture? uploadAudioTexture(AudioChannel audioChannel) {
    if (!_isGpuAvailable) return null;
    try {
      _audioTexture ??= gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        kAudioTextureWidth,
        kAudioTextureHeight,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );

      final byteData = ByteData.sublistView(audioChannel.pixelData);
      _audioTexture!.overwrite(byteData);
      return _audioTexture;
    } catch (e) {
      return null;
    }
  }

  /// Uploads raw RGBA pixel data as a 2D GPU texture for a specific channel.
  gpu.Texture? uploadTextureChannel(
    int channelIndex,
    Uint8List rgbaBytes,
    int texWidth,
    int texHeight,
  ) {
    if (!_isGpuAvailable || texWidth <= 0 || texHeight <= 0) return null;
    try {
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        texWidth,
        texHeight,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      texture.overwrite(ByteData.sublistView(rgbaBytes));
      _textureChannels[channelIndex] = texture;
      return texture;
    } catch (e) {
      debugPrint('Failed to upload texture channel $channelIndex: $e');
      return null;
    }
  }

  void removeTextureChannel(int channelIndex) {
    _textureChannels.remove(channelIndex);
  }

  /// Executes the Flutter GPU render pipeline on a full-screen quad plane:
  /// 1. Acquires a presentation frame from [gpu.GpuImageSurface].
  /// 2. Binds the render pipeline and quad vertex buffer.
  /// 3. Packs and binds the std140 `FrameInfo` uniform buffer.
  /// 4. Binds active `iChannel0..3` samplers (audio, 2D textures, buffers).
  /// 5. Draws 6 vertices, presents the frame, and returns [ui.Image].
  Future<ui.Image?> renderFrame({
    required ShaderToyUniforms uniforms,
    required List<ShaderPass> passes,
    AudioChannel? activeAudioChannel,
  }) async {
    if (!_isGpuAvailable) {
      _initGpuResources();
    }
    final targetWidth = uniforms.resolution.width.toInt().clamp(1, 4096);
    final targetHeight = uniforms.resolution.height.toInt().clamp(1, 4096);
    if (width != targetWidth || height != targetHeight) {
      resize(targetWidth, targetHeight);
    }

    if (!_isGpuAvailable ||
        _renderPipeline == null ||
        _imageSurface == null ||
        _quadVertexBuffer == null) {
      return null;
    }

    try {
      final surfaceFrame = _imageSurface!.acquireNextFrame();
      final renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: surfaceFrame.colorTexture),
      );

      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = commandBuffer.createRenderPass(renderTarget);

      // Set explicit viewport matching surface dimensions
      renderPass.setViewport(gpu.Viewport(
        x: 0,
        y: 0,
        width: width,
        height: height,
      ));

      // 1. Bind pipeline
      renderPass.bindPipeline(_renderPipeline!);

      // 2. Bind quad vertex buffer
      final quadView = gpu.BufferView(
        _quadVertexBuffer!,
        offsetInBytes: 0,
        lengthInBytes: _quadVertexBuffer!.sizeInBytes,
      );
      renderPass.bindVertexBuffer(quadView);

      // 3. Pack std140 / MSL FrameInfo uniform buffer (48 bytes):
      // Offset  0..11: iResolution (vec3: width, height, aspect)
      // Offset 12..15: iTime (float)
      // Offset 16..19: iTimeDelta (float)
      // Offset 20..23: iFrame (int32)
      // Offset 24..31: padding (8 bytes for 16-byte alignment of float4)
      // Offset 32..47: iMouse (vec4: x, y, z, w)
      final uniformByteData = ByteData(48);
      uniformByteData.setFloat32(0, targetWidth.toDouble(), Endian.host);
      uniformByteData.setFloat32(4, targetHeight.toDouble(), Endian.host);
      uniformByteData.setFloat32(8, 1.0, Endian.host); // Shadertoy spec: z is pixel aspect ratio (1.0)
      uniformByteData.setFloat32(12, uniforms.time, Endian.host);
      uniformByteData.setFloat32(16, uniforms.timeDelta, Endian.host);
      uniformByteData.setInt32(20, uniforms.frame, Endian.host);
      uniformByteData.setInt32(24, 0, Endian.host);
      uniformByteData.setInt32(28, 0, Endian.host);
      uniformByteData.setFloat32(32, uniforms.mouse.x, Endian.host);
      uniformByteData.setFloat32(36, uniforms.mouse.y, Endian.host);
      uniformByteData.setFloat32(40, uniforms.mouse.z, Endian.host);
      uniformByteData.setFloat32(44, uniforms.mouse.w, Endian.host);

      try {
        final uniformDeviceBuffer =
            gpu.gpuContext.createDeviceBufferWithCopy(uniformByteData);
        final uniformSlot = _fragmentShader!.getUniformSlot('FrameInfo');
        renderPass.bindUniform(
          uniformSlot,
          gpu.BufferView(
            uniformDeviceBuffer,
            offsetInBytes: 0,
            lengthInBytes: uniformByteData.lengthInBytes,
          ),
        );
      } catch (e) {
        // FrameInfo uniform might not be referenced in this shader
      }

      // 4. Update and bind audio texture
      if (activeAudioChannel != null) {
        uploadAudioTexture(activeAudioChannel);
      }

      // 5. Bind iChannel0..3 samplers (only for channels actually referenced in the shader)
      final activePass = passes.firstWhere(
        (p) => p.type == PassType.image && p.enabled,
        orElse: () => passes.isNotEmpty
            ? passes.first
            : ShaderPass(type: PassType.image, name: 'Image', code: ''),
      );
      final codeForChannels = _activeCode ?? activePass.code;

      final fallbackTex = _getDefaultTexture();
      for (int i = 0; i < 4; i++) {
        if (!ImpellerCompiler.shaderUsesChannel(codeForChannels, i)) {
          continue;
        }

        final channelSlot = _fragmentShader!.getUniformSlot('iChannel$i');
        gpu.Texture? texToBind;
        if (i == 0 && _audioTexture != null) {
          texToBind = _audioTexture;
        } else if (_textureChannels.containsKey(i)) {
          texToBind = _textureChannels[i];
        } else {
          texToBind = fallbackTex;
        }

        if (texToBind != null) {
          try {
            renderPass.bindTexture(channelSlot, texToBind);
          } catch (_) {
            // Sampler slot might not be referenced in this shader
          }
        }
      }

      // 6. Draw full-screen quad (6 vertices)
      renderPass.draw(6);

      // 7. Present frame and submit GPU command buffer
      surfaceFrame.present(commandBuffer);
      commandBuffer.submit();

      return _imageSurface!.currentImage;
    } catch (e) {
      debugPrint('Flutter GPU renderFrame error: $e');
      return null;
    }
  }

  void dispose() {
    _clearPingPongBuffers();
    _textureChannels.clear();
    _audioTexture = null;
    _defaultTexture = null;
    _activeCode = null;
    _quadVertexBuffer = null;
    _renderPipeline = null;
    _shaderLibrary = null;
    _imageSurface = null;
  }
}
