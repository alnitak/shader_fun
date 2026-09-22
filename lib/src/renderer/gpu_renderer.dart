import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../channels/audio_texture_provider.dart';
import '../channels/shader_channel.dart';
import '../compiler/impeller_compiler.dart';
import '../core/shader_pass.dart';
import '../core/common_uniforms.dart';
import '../gpu/gpu.dart' as gpu;

/// Low-level multi-pass renderer powered by flutter_scene's cross-platform GPU pipeline.
/// Executes compiled shader bundles on full-screen quad geometry and renders to swapchain [gpu.Texture]s.
class FlutterGpuRenderer {
  FlutterGpuRenderer({this.width = 800, this.height = 450}) {
    _initGpuResources();
  }

  int width;
  int height;

  final List<gpu.Texture> _swapchainColors = [];
  int _swapchainCursor = 0;
  int _swapchainWidth = 0;
  int _swapchainHeight = 0;
  bool _isGpuAvailable = false;

  gpu.ShaderLibrary? _shaderLibrary;
  gpu.Shader? _vertexShader;
  gpu.Shader? _fragmentShader;
  gpu.RenderPipeline? _renderPipeline;
  String? _activeCode;

  final Map<PassType, _PassPipeline> _passPipelines = {};
  final Map<PassType, _PingPongBuffer> _bufferPingPongs = {};

  gpu.ShaderLibrary? get shaderLibrary => _shaderLibrary;
  gpu.Shader? get vertexShader => _vertexShader;
  gpu.Shader? get fragmentShader => _fragmentShader;

  gpu.DeviceBuffer? _quadVertexBuffer;

  /// Cache of uploaded audio texture (512x2 RGBA)
  gpu.Texture? _audioTexture;

  /// Cache of uploaded keyboard texture (256x3 RGBA)
  gpu.Texture? _keyboardTexture;

  /// Default 1x1 fallback texture to satisfy samplers when no channel texture is bound.
  gpu.Texture? _defaultTexture;

  /// Cache of uploaded 2D image textures per channel index
  final Map<int, gpu.Texture> _textureChannels = {};
  final Map<int, ui.Size> _textureChannelResolutions = {};

  bool get isGpuAvailable => _isGpuAvailable;
  bool get hasPipeline => _renderPipeline != null || _passPipelines.isNotEmpty;
  bool hasPassPipeline(PassType type) => _passPipelines.containsKey(type);

  /// Clears audio texture reference so other shaders don't sample stale audio data.
  void clearAudioTexture() {
    _audioTexture = null;
  }

  /// Clears keyboard texture reference.
  void clearKeyboardTexture() {
    _keyboardTexture = null;
  }

  void _clearPingPongBuffers() {
    for (final buffer in _bufferPingPongs.values) {
      buffer.clear();
    }
    _bufferPingPongs.clear();
  }

  void clearPingPongBuffers() {
    _clearPingPongBuffers();
  }

  gpu.Texture? _createRenderTargetTexture(int w, int h) {
    if (!_isGpuAvailable) return null;
    try {
      final supportsFloat32 = gpu.gpuContext.supportsTextureFormat(
        gpu.PixelFormat.r32g32b32a32Float,
        renderTarget: true,
        shaderRead: true,
      );
      final supportsFloat16 = gpu.gpuContext.supportsTextureFormat(
        gpu.PixelFormat.r16g16b16a16Float,
        renderTarget: true,
        shaderRead: true,
      );
      final format = supportsFloat32
          ? gpu.PixelFormat.r32g32b32a32Float
          : (supportsFloat16
                ? gpu.PixelFormat.r16g16b16a16Float
                : gpu.PixelFormat.r8g8b8a8UNormInt);

      return gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        w,
        h,
        format: format,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
    } catch (e) {
      debugPrint('Failed to allocate offscreen render target texture: $e');
      return null;
    }
  }

  _PingPongBuffer _getOrCreatePingPong(PassType type, int w, int h) {
    var buffer = _bufferPingPongs[type];
    if (buffer == null) {
      buffer = _PingPongBuffer()
        ..readTexture = _createRenderTargetTexture(w, h)
        ..readWidth = w
        ..readHeight = h
        ..writeTexture = _createRenderTargetTexture(w, h)
        ..writeWidth = w
        ..writeHeight = h;
      _bufferPingPongs[type] = buffer;
    } else if (buffer.writeWidth != w || buffer.writeHeight != h) {
      // Allocate a new writeTexture with the new dimensions.
      // Retain readTexture (even with its old dimensions) so ping-pong buffers that
      // accumulate state (such as Buffer A) can bilinearly resample their previous
      // content into the new resolution on this frame without losing their data or centering.
      buffer.writeTexture = _createRenderTargetTexture(w, h);
      buffer.writeWidth = w;
      buffer.writeHeight = h;
      if (buffer.readTexture == null) {
        buffer.readTexture = _createRenderTargetTexture(w, h);
        buffer.readWidth = w;
        buffer.readHeight = h;
      }
    }
    return buffer;
  }

  static const int _kDefaultTextureSize = 256;

  gpu.Texture? _getDefaultTexture() {
    if (!_isGpuAvailable) return null;
    try {
      if (_defaultTexture != null) return _defaultTexture;
      _defaultTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        _kDefaultTextureSize,
        _kDefaultTextureSize,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      final dummyBytes = Uint8List(
        _kDefaultTextureSize * _kDefaultTextureSize * 4,
      );
      for (int i = 3; i < dummyBytes.length; i += 4) {
        dummyBytes[i] = 255; // Opaque black
      }
      _defaultTexture!.overwrite(ByteData.sublistView(dummyBytes));
      return _defaultTexture;
    } catch (e) {
      debugPrint(
        'Failed to create default ${_kDefaultTextureSize}x$_kDefaultTextureSize texture: $e',
      );
      return null;
    }
  }

  gpu.Texture _getNextSwapchainTexture(int w, int h) {
    if (w != _swapchainWidth || h != _swapchainHeight) {
      _swapchainColors.clear();
      _swapchainCursor = 0;
      _swapchainWidth = w;
      _swapchainHeight = h;
    }
    if (_swapchainCursor >= _swapchainColors.length) {
      final tex = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        w,
        h,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _swapchainColors.add(tex);
    }
    final result = _swapchainColors[_swapchainCursor];
    _swapchainCursor = (_swapchainCursor + 1) % 2;
    return result;
  }

  void _initGpuResources() {
    try {
      final _ = gpu.gpuContext;
      _isGpuAvailable = true;
      _initQuadVertexBuffer();
      debugPrint('GPU initialized successfully (${width}x$height).');
    } catch (e) {
      _isGpuAvailable = false;
      debugPrint('GPU initialization: $e');
    }
  }

  /// Initializes the full-screen quad vertex buffer (two triangles, 6 vertices, 2 floats each).
  void _initQuadVertexBuffer() {
    if (!_isGpuAvailable) return;
    try {
      final vertices = Float32List.fromList([
        -1.0,
        -1.0,
        1.0,
        -1.0,
        -1.0,
        1.0,
        -1.0,
        1.0,
        1.0,
        -1.0,
        1.0,
        1.0,
      ]);
      final byteData = ByteData.sublistView(vertices);
      _quadVertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(byteData);
    } catch (e) {
      debugPrint('Failed to allocate quad vertex buffer: $e');
    }
  }

  /// Loads a compiled `.shaderbundle` and builds the GPU render pipeline for [passType].
  Future<bool> loadShaderBundle(
    Uint8List bundleBytes, {
    PassType passType = PassType.image,
    String? activeCode,
  }) async {
    if (!_isGpuAvailable) {
      _initGpuResources();
    }
    if (!_isGpuAvailable) {
      debugPrint('GPU context is not available.');
      return false;
    }
    try {
      final byteData = ByteData.sublistView(bundleBytes);
      final lib = await gpu.loadShaderLibraryFromBytesAsync(byteData);
      if (lib == null) return false;

      final vert = lib['QuadVertex'];
      final frag = lib['ShaderFragment'];
      if (vert == null || frag == null) {
        debugPrint('Shader bundle missing QuadVertex or ShaderFragment');
        return false;
      }

      final pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);

      _passPipelines[passType] = _PassPipeline(
        pipeline: pipeline,
        fragmentShader: frag,
        vertexShader: vert,
        code: activeCode,
      );

      // Fallback single-pass fields for backwards compatibility
      _shaderLibrary = lib;
      _vertexShader = vert;
      _fragmentShader = frag;
      _renderPipeline = pipeline;
      if (activeCode != null) {
        _activeCode = activeCode;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to load shader bundle into GPU: $e');
      return false;
    }
  }

  void resize(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (width == newWidth && height == newHeight) return;

    width = newWidth;
    height = newHeight;
    _swapchainColors.clear();
    _swapchainCursor = 0;
    _swapchainWidth = width;
    _swapchainHeight = height;
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

      final rawBytes = audioChannel.pixelData;
      final rowBytes = kAudioTextureWidth * 4;
      final flippedBytes = Uint8List(rawBytes.length);
      // Row 0 in Metal gets waveform (raw Row 1), Row 1 gets FFT (raw Row 0)
      // so sampling at y = 0.25 (OpenGL bottom row) samples FFT with st_texture.
      flippedBytes.setRange(0, rowBytes, rawBytes, rowBytes);
      flippedBytes.setRange(rowBytes, rowBytes * 2, rawBytes, 0);

      _audioTexture!.overwrite(ByteData.sublistView(flippedBytes));
      return _audioTexture;
    } catch (e) {
      return null;
    }
  }

  /// Uploads keyboard state to a 256x3 GPU texture.
  gpu.Texture? uploadKeyboardTexture(Uint8List keyboardBytes) {
    if (!_isGpuAvailable) return null;
    try {
      _keyboardTexture ??= gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        256,
        3,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );

      _keyboardTexture!.overwrite(ByteData.sublistView(keyboardBytes));
      return _keyboardTexture;
    } catch (e) {
      debugPrint('Failed to upload keyboard texture: $e');
      return null;
    }
  }

  /// Uploads raw RGBA pixel data as a 2D GPU texture for a specific channel,
  /// generating a complete mipmap pyramid for textureLod and trilinear filtering.
  gpu.Texture? uploadTextureChannel(
    int channelIndex,
    Uint8List rgbaBytes,
    int texWidth,
    int texHeight,
  ) {
    if (!_isGpuAvailable || texWidth <= 0 || texHeight <= 0) return null;
    try {
      final maxMipLevels = gpu.Texture.fullMipCount(texWidth, texHeight);
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        texWidth,
        texHeight,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
        mipLevelCount: maxMipLevels,
      );
      texture.overwrite(ByteData.sublistView(rgbaBytes), mipLevel: 0);

      // Generate and upload mipmap pyramid for textureLod and trilinear filtering
      var currentBytes = rgbaBytes;
      var currentW = texWidth;
      var currentH = texHeight;

      for (int level = 1; level < maxMipLevels; level++) {
        final nextW = texture.getMipLevelWidth(level);
        final nextH = texture.getMipLevelHeight(level);
        final nextBytes = _downsampleRgba(
          currentBytes,
          currentW,
          currentH,
          nextW,
          nextH,
        );
        texture.overwrite(ByteData.sublistView(nextBytes), mipLevel: level);
        currentBytes = nextBytes;
        currentW = nextW;
        currentH = nextH;
      }

      _textureChannels[channelIndex] = texture;
      _textureChannelResolutions[channelIndex] = ui.Size(
        texWidth.toDouble(),
        texHeight.toDouble(),
      );
      return texture;
    } catch (e) {
      debugPrint('Failed to upload texture channel $channelIndex: $e');
      return null;
    }
  }

  /// Fast 2x2 box-filter downsampling for RGBA mipmap generation.
  static Uint8List _downsampleRgba(
    Uint8List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final dst = Uint8List(dstW * dstH * 4);
    for (int y = 0; y < dstH; y++) {
      final srcY0 = y * 2;
      final srcY1 = (srcY0 + 1 < srcH) ? srcY0 + 1 : srcY0;
      final row0Offset = srcY0 * srcW * 4;
      final row1Offset = srcY1 * srcW * 4;
      final dstRowOffset = y * dstW * 4;

      for (int x = 0; x < dstW; x++) {
        final srcX0 = x * 2;
        final srcX1 = (srcX0 + 1 < srcW) ? srcX0 + 1 : srcX0;

        final p00 = row0Offset + (srcX0 * 4);
        final p10 = row0Offset + (srcX1 * 4);
        final p01 = row1Offset + (srcX0 * 4);
        final p11 = row1Offset + (srcX1 * 4);

        final dstOffset = dstRowOffset + (x * 4);
        dst[dstOffset] = (src[p00] + src[p10] + src[p01] + src[p11] + 2) >> 2;
        dst[dstOffset + 1] =
            (src[p00 + 1] + src[p10 + 1] + src[p01 + 1] + src[p11 + 1] + 2) >>
            2;
        dst[dstOffset + 2] =
            (src[p00 + 2] + src[p10 + 2] + src[p01 + 2] + src[p11 + 2] + 2) >>
            2;
        dst[dstOffset + 3] =
            (src[p00 + 3] + src[p10 + 3] + src[p01 + 3] + src[p11 + 3] + 2) >>
            2;
      }
    }
    return dst;
  }

  void removeTextureChannel(int channelIndex) {
    _textureChannels.remove(channelIndex);
    _textureChannelResolutions.remove(channelIndex);
  }

  /// Clears all bound texture channels and their cached resolutions.
  void clearTextureChannels() {
    _textureChannels.clear();
    _textureChannelResolutions.clear();
  }

  static PassType _bufferIndexToPassType(int index) {
    switch (index) {
      case 1:
        return PassType.bufferB;
      case 2:
        return PassType.bufferC;
      case 3:
        return PassType.bufferD;
      case 0:
      default:
        return PassType.bufferA;
    }
  }

  void _bindPassChannels({
    required gpu.RenderPass renderPass,
    required gpu.Shader fragmentShader,
    required String? codeForChannels,
    required ShaderPass pass,
    required Map<PassType, gpu.Texture> availableTextures,
    required gpu.Texture fallbackTex,
    String? commonCode,
  }) {
    final effectiveCode = (commonCode != null && commonCode.isNotEmpty)
        ? '$commonCode\n${codeForChannels ?? pass.code}'
        : (codeForChannels ?? pass.code);

    for (int i = 0; i < 4; i++) {
      final hasConfiguredChannel =
          i < pass.channels.length && pass.channels[i] != null;
      final codeUsesChannel = ImpellerCompiler.shaderUsesChannel(
        effectiveCode,
        i,
      );

      if (!hasConfiguredChannel && !codeUsesChannel) {
        continue;
      }

      final channel = (i < pass.channels.length) ? pass.channels[i] : null;
      gpu.Texture? texToBind;

      if (channel is BufferChannel) {
        final bufferType = _bufferIndexToPassType(channel.bufferIndex);
        texToBind = availableTextures[bufferType] ?? fallbackTex;
      } else if (channel is AudioChannel) {
        texToBind = _audioTexture ?? fallbackTex;
      } else if (channel is KeyboardChannel) {
        texToBind = _keyboardTexture ?? fallbackTex;
      } else if (channel is TextureChannel && _textureChannels.containsKey(i)) {
        texToBind = _textureChannels[i];
      } else if (channel is WidgetChannel) {
        texToBind = channel.textureController.texture ?? fallbackTex;
      } else {
        texToBind = fallbackTex;
      }

      if (texToBind != null) {
        try {
          final channelSlot = fragmentShader.getUniformSlot('iChannel$i');
          final minFilter = channel?.filter == ChannelFilter.nearest
              ? gpu.MinMagFilter.nearest
              : gpu.MinMagFilter.linear;
          final magFilter = channel?.filter == ChannelFilter.nearest
              ? gpu.MinMagFilter.nearest
              : gpu.MinMagFilter.linear;
          final mipFilter = channel?.filter == ChannelFilter.nearest
              ? gpu.MipFilter.nearest
              : gpu.MipFilter.linear;
          final addressMode = channel?.wrap == ChannelWrap.repeat
              ? gpu.SamplerAddressMode.repeat
              : gpu.SamplerAddressMode.clampToEdge;

          final sampler = gpu.SamplerOptions(
            minFilter: minFilter,
            magFilter: magFilter,
            mipFilter: mipFilter,
            widthAddressMode: addressMode,
            heightAddressMode: addressMode,
          );

          renderPass.bindTexture(channelSlot, texToBind, sampler: sampler);
        } catch (_) {}
      }
    }
  }

  ui.Size _getPassChannelResolution(
    ShaderPass pass,
    int channelIndex,
    double targetWidth,
    double targetHeight,
    CommonUniforms uniforms,
  ) {
    if (channelIndex < pass.channels.length &&
        pass.channels[channelIndex] != null) {
      final ch = pass.channels[channelIndex]!;
      if (ch is BufferChannel) {
        return ui.Size(targetWidth, targetHeight);
      } else if (ch is TextureChannel) {
        if (_textureChannelResolutions.containsKey(channelIndex)) {
          return _textureChannelResolutions[channelIndex]!;
        }
        return ch.resolution;
      } else if (ch is AudioChannel) {
        return const ui.Size(
          kAudioTextureWidth + 0.0,
          kAudioTextureHeight + 0.0,
        );
      } else if (ch is KeyboardChannel) {
        return const ui.Size(256.0, 3.0);
      } else {
        return ch.resolution;
      }
    }
    if (_textureChannelResolutions.containsKey(channelIndex)) {
      return _textureChannelResolutions[channelIndex]!;
    }
    if (channelIndex < uniforms.channelResolution.length) {
      return uniforms.channelResolution[channelIndex];
    }
    return const ui.Size(0, 0);
  }

  ByteData _packUniformByteData({
    required CommonUniforms uniforms,
    required double targetWidth,
    required double targetHeight,
    required ShaderPass pass,
  }) {
    final uniformByteData = ByteData(CommonUniforms.totalUniformBufferSize);
    uniformByteData.setFloat32(0, targetWidth, Endian.host);
    uniformByteData.setFloat32(4, targetHeight, Endian.host);
    uniformByteData.setFloat32(8, 1.0, Endian.host); // aspect ratio
    uniformByteData.setFloat32(12, uniforms.time, Endian.host);
    uniformByteData.setFloat32(16, uniforms.timeDelta, Endian.host);
    uniformByteData.setFloat32(20, uniforms.frameRate, Endian.host);
    uniformByteData.setInt32(24, uniforms.frame, Endian.host);
    uniformByteData.setInt32(28, 0, Endian.host);
    uniformByteData.setFloat32(32, uniforms.mouse.x, Endian.host);
    uniformByteData.setFloat32(36, uniforms.mouse.y, Endian.host);
    uniformByteData.setFloat32(40, uniforms.mouse.z, Endian.host);
    uniformByteData.setFloat32(44, uniforms.mouse.w, Endian.host);
    final secondsOfDay =
        uniforms.date.hour * 3600.0 +
        uniforms.date.minute * 60.0 +
        uniforms.date.second.toDouble() +
        uniforms.date.millisecond / 1000.0;
    uniformByteData.setFloat32(48, uniforms.date.year.toDouble(), Endian.host);
    uniformByteData.setFloat32(
      52,
      (uniforms.date.month - 1).toDouble(),
      Endian.host,
    );
    uniformByteData.setFloat32(56, uniforms.date.day.toDouble(), Endian.host);
    uniformByteData.setFloat32(60, secondsOfDay, Endian.host);
    uniformByteData.setFloat32(64, uniforms.sampleRate, Endian.host);

    // 68..79: std140 padding before vec3 array

    // 80..143: vec3 iChannelResolution[4] with 16-byte std140 stride
    for (int i = 0; i < 4; i++) {
      final res = _getPassChannelResolution(
        pass,
        i,
        targetWidth,
        targetHeight,
        uniforms,
      );
      final offset = 80 + i * 16;
      uniformByteData.setFloat32(offset, res.width, Endian.host);
      uniformByteData.setFloat32(offset + 4, res.height, Endian.host);
      uniformByteData.setFloat32(
        offset + 8,
        res.height > 0 ? (res.width / res.height) : 1.0,
        Endian.host,
      );
      uniformByteData.setFloat32(offset + 12, 0.0, Endian.host);
    }

    // 144..(ShaderUniforms.totalUniformBufferSize - 1): vec4 iCustom[...]
    // Sized to match GPU memory allocators and driver uniform pagination
    // (typically minUniformBufferOffsetAlignment is 256 bytes in Vulkan and Metal).
    // If more registers are needed, update [ShaderUniforms.maxCustomUniformSlots];
    // this allocation dynamically scales to match [ShaderUniforms.totalUniformBufferSize].
    final customFloats = uniforms.customData;
    for (int i = 0; i < customFloats.length; i++) {
      uniformByteData.setFloat32(
        CommonUniforms.standardUniformsSizeBytes + i * 4,
        customFloats[i],
        Endian.host,
      );
    }

    return uniformByteData;
  }

  /// Executes the multi-pass GPU pipeline:
  /// 1. Executes all enabled buffer passes (Buffer A -> Buffer B -> Buffer C -> Buffer D)
  ///    into offscreen ping-pong render targets.
  /// 2. Binds upstream and historical buffer textures to `iChannel0..3`.
  /// 3. Executes the presentation pass (Image) to the display surface.
  /// 4. Swaps ping-pong buffers for the next frame.
  Future<ui.Image?> renderFrame({
    required CommonUniforms uniforms,
    required List<ShaderPass> passes,
    ShaderPass? activePass,
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

    if (!_isGpuAvailable || !hasPipeline || _quadVertexBuffer == null) {
      return null;
    }

    try {
      gpu.DeviceBuffer? createPassUniformBuffer(ShaderPass pass) {
        final byteData = _packUniformByteData(
          uniforms: uniforms,
          targetWidth: targetWidth.toDouble(),
          targetHeight: targetHeight.toDouble(),
          pass: pass,
        );
        try {
          return gpu.gpuContext.createDeviceBufferWithCopy(byteData);
        } catch (e) {
          debugPrint(
            'Failed to allocate uniform device buffer for ${pass.name}: $e',
          );
          return null;
        }
      }

      final quadView = gpu.BufferView(
        _quadVertexBuffer!,
        offsetInBytes: 0,
        lengthInBytes: _quadVertexBuffer!.sizeInBytes,
      );

      final fallbackTex = _getDefaultTexture();
      if (fallbackTex == null) return null;

      // Update audio texture if active
      if (activeAudioChannel != null) {
        uploadAudioTexture(activeAudioChannel);
      }

      final commonCode = passes
          .cast<ShaderPass?>()
          .firstWhere((p) => p?.type == PassType.common, orElse: () => null)
          ?.code;

      const bufferOrder = [
        PassType.bufferA,
        PassType.bufferB,
        PassType.bufferC,
        PassType.bufferD,
      ];

      final executedBufferPasses = <PassType>[];

      // 2. Execute offscreen Buffer passes
      for (final bpType in bufferOrder) {
        final pass = passes.firstWhere(
          (p) => p.type == bpType && p.enabled,
          orElse: () =>
              ShaderPass(type: bpType, name: bpType.displayName, code: ''),
        );
        if (!pass.enabled) continue;

        final pipelineInfo = _passPipelines[bpType];
        if (pipelineInfo == null) continue;

        final pingPong = _getOrCreatePingPong(bpType, width, height);
        if (pingPong.writeTexture == null) continue;

        final renderTarget = gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: pingPong.writeTexture!,
            loadAction: gpu.LoadAction.clear,
          ),
        );

        final passCommandBuffer = gpu.gpuContext.createCommandBuffer();
        final renderPass = passCommandBuffer.createRenderPass(renderTarget);
        renderPass.setViewport(
          gpu.Viewport(x: 0, y: 0, width: width, height: height),
        );

        renderPass.bindPipeline(pipelineInfo.pipeline);
        renderPass.bindVertexBuffer(quadView);

        try {
          final passUniformDeviceBuffer = createPassUniformBuffer(pass);
          if (passUniformDeviceBuffer != null) {
            final uniformSlot = pipelineInfo.fragmentShader.getUniformSlot(
              'FrameInfo',
            );
            renderPass.bindUniform(
              uniformSlot,
              gpu.BufferView(
                passUniformDeviceBuffer,
                offsetInBytes: 0,
                lengthInBytes: passUniformDeviceBuffer.sizeInBytes,
              ),
            );
          }
        } catch (_) {}

        // Prepare textures available to this buffer pass
        final availableTextures = <PassType, gpu.Texture>{};
        for (final otherType in bufferOrder) {
          final otherPingPong = _bufferPingPongs[otherType];
          if (otherPingPong == null) continue;

          if (otherType == bpType) {
            // Self-reference: read from previous frame's read texture
            if (otherPingPong.readTexture != null) {
              availableTextures[otherType] = otherPingPong.readTexture!;
            }
          } else {
            // If already executed this frame, sample writeTexture; otherwise readTexture
            final hasExecuted = executedBufferPasses.contains(otherType);
            final tex = hasExecuted
                ? (otherPingPong.writeTexture ?? otherPingPong.readTexture)
                : otherPingPong.readTexture;
            if (tex != null) {
              availableTextures[otherType] = tex;
            }
          }
        }

        _bindPassChannels(
          renderPass: renderPass,
          fragmentShader: pipelineInfo.fragmentShader,
          codeForChannels: pipelineInfo.code ?? pass.code,
          pass: pass,
          availableTextures: availableTextures,
          fallbackTex: fallbackTex,
          commonCode: commonCode,
        );

        renderPass.draw(6);
        passCommandBuffer.submit();
        executedBufferPasses.add(bpType);
      }

      // 3. Execute presentation pass (Image) to swapchain color texture
      final presentationTexture = _getNextSwapchainTexture(width, height);
      final surfaceRenderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: presentationTexture,
          loadAction: gpu.LoadAction.clear,
        ),
      );

      final presentationPass = passes.firstWhere(
        (p) => p.type == PassType.image && p.enabled,
        orElse: () =>
            activePass ??
            (passes.isNotEmpty
                ? passes.first
                : ShaderPass(type: PassType.image, name: 'Image', code: '')),
      );

      final presentationPipeline =
          _passPipelines[presentationPass.type] ??
          (hasPipeline
              ? _PassPipeline(
                  pipeline: _renderPipeline!,
                  fragmentShader: _fragmentShader!,
                  vertexShader: _vertexShader!,
                  code: _activeCode,
                )
              : null);

      if (presentationPipeline == null) {
        return null;
      }

      final presentationCommandBuffer = gpu.gpuContext.createCommandBuffer();
      final surfaceRenderPass = presentationCommandBuffer.createRenderPass(
        surfaceRenderTarget,
      );
      surfaceRenderPass.setViewport(
        gpu.Viewport(x: 0, y: 0, width: width, height: height),
      );

      surfaceRenderPass.bindPipeline(presentationPipeline.pipeline);
      surfaceRenderPass.bindVertexBuffer(quadView);

      try {
        final presentationUniformDeviceBuffer = createPassUniformBuffer(
          presentationPass,
        );
        if (presentationUniformDeviceBuffer != null) {
          final uniformSlot = presentationPipeline.fragmentShader
              .getUniformSlot('FrameInfo');
          surfaceRenderPass.bindUniform(
            uniformSlot,
            gpu.BufferView(
              presentationUniformDeviceBuffer,
              offsetInBytes: 0,
              lengthInBytes: presentationUniformDeviceBuffer.sizeInBytes,
            ),
          );
        }
      } catch (_) {}

      // For presentation pass, all buffers have finished this frame, so bind their fresh writeTexture
      final imageAvailableTextures = <PassType, gpu.Texture>{};
      for (final bpType in bufferOrder) {
        final pingPong = _bufferPingPongs[bpType];
        if (pingPong != null) {
          final tex = pingPong.writeTexture ?? pingPong.readTexture;
          if (tex != null) {
            imageAvailableTextures[bpType] = tex;
          }
        }
      }

      _bindPassChannels(
        renderPass: surfaceRenderPass,
        fragmentShader: presentationPipeline.fragmentShader,
        codeForChannels: presentationPipeline.code ?? presentationPass.code,
        pass: presentationPass,
        availableTextures: imageAvailableTextures,
        fallbackTex: fallbackTex,
        commonCode: commonCode,
      );

      surfaceRenderPass.draw(6);

      // 4. Swap ping-pong buffers for executed buffer passes
      for (final bpType in executedBufferPasses) {
        _bufferPingPongs[bpType]?.swap();
      }

      // 5. Submit presentation command buffer and snapshot texture to ui.Image
      presentationCommandBuffer.submit();

      return presentationTexture.asImage();
    } catch (e) {
      debugPrint('GPU renderFrame error: $e');
      return null;
    }
  }

  gpu.Texture? _soundTexture;

  /// Renders a single sound chunk for [PassType.sound] at [blockOffset] (in seconds).
  /// Returns raw stereo 32-bit float PCM bytes suitable for SoLoud.addAudioDataStream,
  /// or null if rendering or readback is unavailable.
  Future<Uint8List?> renderSoundPass({
    required ShaderPass soundPass,
    required double blockOffset,
    required double sampleRate,
    int width = 256,
    int height = 256,
  }) async {
    if (!_isGpuAvailable) _initGpuResources();
    if (!_isGpuAvailable) return null;

    final pipelineInfo = _passPipelines[PassType.sound];
    if (pipelineInfo == null) return null;

    try {
      if (_soundTexture == null ||
          _soundTexture!.width != width ||
          _soundTexture!.height != height) {
        final supportsFloat32 = gpu.gpuContext.supportsTextureFormat(
          gpu.PixelFormat.r32g32b32a32Float,
          renderTarget: true,
          shaderRead: true,
        );
        final format = supportsFloat32
            ? gpu.PixelFormat.r32g32b32a32Float
            : gpu.PixelFormat.r8g8b8a8UNormInt;

        _soundTexture = gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          width,
          height,
          format: format,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        );
      }

      final soundTex = _soundTexture;
      if (soundTex == null) return null;

      final renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: soundTex,
          loadAction: gpu.LoadAction.clear,
          storeAction: gpu.StoreAction.store,
        ),
      );

      final cmdBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = cmdBuffer.createRenderPass(renderTarget);
      renderPass.setViewport(
        gpu.Viewport(x: 0, y: 0, width: width, height: height),
      );

      renderPass.bindPipeline(pipelineInfo.pipeline);
      if (_quadVertexBuffer == null) return null;
      final quadView = gpu.BufferView(
        _quadVertexBuffer!,
        offsetInBytes: 0,
        lengthInBytes: _quadVertexBuffer!.sizeInBytes,
      );
      renderPass.bindVertexBuffer(quadView);

      // FrameInfo uniform buffer with time = blockOffset (#define iBlockOffset iTime)
      // and sampleRate = sampleRate
      final soundUniforms = CommonUniforms(
        resolution: ui.Size(width.toDouble(), height.toDouble()),
        time: blockOffset,
        sampleRate: sampleRate,
      );

      final uniformByteData = _packUniformByteData(
        uniforms: soundUniforms,
        targetWidth: width.toDouble(),
        targetHeight: height.toDouble(),
        pass: soundPass,
      );

      final uniformDeviceBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(uniformByteData),
      );
      final slot = pipelineInfo.fragmentShader.getUniformSlot('FrameInfo');
      renderPass.bindUniform(
        slot,
        gpu.BufferView(
          uniformDeviceBuffer,
          offsetInBytes: 0,
          lengthInBytes: uniformByteData.lengthInBytes,
        ),
      );

      final fallbackTex = _getDefaultTexture();
      if (fallbackTex == null) return null;

      _bindPassChannels(
        renderPass: renderPass,
        fragmentShader: pipelineInfo.fragmentShader,
        codeForChannels: pipelineInfo.code ?? soundPass.code,
        pass: soundPass,
        availableTextures: const {},
        fallbackTex: fallbackTex,
      );

      renderPass.draw(6);
      cmdBuffer.submit();

      final uiImage = soundTex.asImage();
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawExtendedRgba128,
      );

      if (byteData != null) {
        final floatData = byteData.buffer.asFloat32List(
          byteData.offsetInBytes,
          byteData.lengthInBytes ~/ 4,
        );
        final stereoFloats = Float32List(width * height * 2);
        for (
          int p = 0, s = 0;
          p < floatData.length && s < stereoFloats.length;
          p += 4, s += 2
        ) {
          stereoFloats[s] = floatData[p];
          stereoFloats[s + 1] = floatData[p + 1];
        }
        return stereoFloats.buffer.asUint8List();
      }

      // Fallback if rawExtendedRgba128 is not supported
      final byteData8 = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (byteData8 != null) {
        final u8Data = byteData8.buffer.asUint8List(
          byteData8.offsetInBytes,
          byteData8.lengthInBytes,
        );
        final stereoFloats = Float32List(width * height * 2);
        for (
          int p = 0, s = 0;
          p < u8Data.length && s < stereoFloats.length;
          p += 4, s += 2
        ) {
          stereoFloats[s] = (u8Data[p] / 127.5) - 1.0;
          stereoFloats[s + 1] = (u8Data[p + 1] / 127.5) - 1.0;
        }
        return stereoFloats.buffer.asUint8List();
      }

      return null;
    } catch (e) {
      debugPrint('Error rendering sound pass: $e');
      return null;
    }
  }

  void dispose() {
    _clearPingPongBuffers();
    _swapchainColors.clear();
    _textureChannels.clear();
    _textureChannelResolutions.clear();
    _passPipelines.clear();
    _soundTexture = null;
    _audioTexture = null;
    _keyboardTexture = null;
    _defaultTexture = null;
    _activeCode = null;
    _quadVertexBuffer = null;
    _renderPipeline = null;
    _shaderLibrary = null;
  }
}

class _PassPipeline {
  _PassPipeline({
    required this.pipeline,
    required this.fragmentShader,
    required this.vertexShader,
    this.code,
  });

  final gpu.RenderPipeline pipeline;
  final gpu.Shader fragmentShader;
  final gpu.Shader vertexShader;
  final String? code;
}

class _PingPongBuffer {
  gpu.Texture? readTexture;
  gpu.Texture? writeTexture;
  int readWidth = 0;
  int readHeight = 0;
  int writeWidth = 0;
  int writeHeight = 0;

  void swap() {
    final tempTex = readTexture;
    readTexture = writeTexture;
    writeTexture = tempTex;

    final tempW = readWidth;
    readWidth = writeWidth;
    writeWidth = tempW;

    final tempH = readHeight;
    readHeight = writeHeight;
    writeHeight = tempH;
  }

  void clear() {
    readTexture = null;
    writeTexture = null;
    readWidth = 0;
    readHeight = 0;
    writeWidth = 0;
    writeHeight = 0;
  }
}
