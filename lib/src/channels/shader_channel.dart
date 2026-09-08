import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'raw_image_decoder.dart';

/// Filtering mode for an iChannel sampler.
enum ChannelFilter { linear, nearest, mipmap }

/// Address wrapping mode for an iChannel sampler.
enum ChannelWrap { clamp, repeat }

/// The type of input connected to an iChannel slot.
enum ChannelType { texture, buffer, audio, mic, cubeMap, keyboard }

/// Configuration and state for an iChannel input slot (0..3).
abstract class ShaderChannel {
  ShaderChannel({
    this.filter = ChannelFilter.mipmap,
    this.wrap = ChannelWrap.repeat,
    this.vflip = true,
  });

  ChannelFilter filter;
  ChannelWrap wrap;
  bool vflip;

  ChannelType get type;

  /// Returns the width and height of this channel.
  ui.Size get resolution;

  /// Returns the current playback / recording time in seconds, if applicable.
  double get time => 0.0;

  bool _isDisposed = false;

  /// Whether this channel has already been disposed.
  bool get isDisposed => _isDisposed;

  /// Disposes any resources held by this channel.
  void dispose() {
    _isDisposed = true;
  }
}

/// 2D Image Texture channel.
class TextureChannel extends ShaderChannel {
  TextureChannel({
    String? src,
    String? assetPath,
    this.imageBytes,
    this.name = 'Texture',
    super.filter = ChannelFilter.mipmap,
    super.wrap = ChannelWrap.repeat,
    super.vflip = true,
    ui.Size? initialResolution,
  }) : src = src ?? assetPath,
       _resolution = initialResolution ?? const ui.Size(512, 512);

  /// Source URI, file path, or Flutter asset path.
  final String? src;

  /// Backwards compatibility getter.
  String? get assetPath => src;

  final Uint8List? imageBytes;
  final String name;
  ui.Size _resolution;
  ui.Image? cachedImage;

  /// Un-premultiplied raw 32-bit RGBA pixel bytes (stride = imageWidth * 4).
  /// Preserves exact noise and mathematical data across all 4 channels.
  Uint8List? rawRgbaBytes;
  int? imageWidth;
  int? imageHeight;

  @override
  ChannelType get type => ChannelType.texture;

  @override
  ui.Size get resolution => _resolution;

  void updateResolution(ui.Size size) {
    _resolution = size;
  }

  /// Loads the image from [src] (URL, local file, asset) or [imageBytes].
  Future<ui.Image?> loadImage() async {
    if (cachedImage != null) return cachedImage;
    try {
      Uint8List? rawBytes = imageBytes;

      if (rawBytes == null && src != null && src!.isNotEmpty) {
        final path = src!;
        if (path.startsWith('http://') || path.startsWith('https://')) {
          // HTTP / HTTPS URL
          final uri = Uri.parse(path);
          final client = HttpClient();
          final request = await client.getUrl(uri);
          final response = await request.close();
          final builder = BytesBuilder();
          await for (final chunk in response) {
            builder.add(chunk);
          }
          client.close();
          rawBytes = builder.toBytes();
        } else if (path.startsWith('file://') ||
            path.startsWith('/') ||
            RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) {
          // Local filesystem file
          final cleanPath = path.startsWith('file://')
              ? Uri.parse(path).toFilePath()
              : path;
          final file = File(cleanPath);
          if (await file.exists()) {
            rawBytes = await file.readAsBytes();
          }
        } else {
          // Flutter Asset bundle with filesystem fallback
          try {
            final data = await rootBundle.load(path);
            rawBytes = data.buffer.asUint8List();
          } catch (_) {
            final candidates = [
              path,
              'example/$path',
              '../example/$path',
              'assets/$path',
            ];
            for (final cand in candidates) {
              final f = File(cand);
              if (f.existsSync()) {
                rawBytes = f.readAsBytesSync();
                break;
              }
            }
          }
        }
      }

      if (rawBytes != null && rawBytes.isNotEmpty) {
        final decoded = await RawImageDecoder.decode(rawBytes);
        if (decoded != null) {
          rawRgbaBytes = decoded.rgbaBytes;
          imageWidth = decoded.width;
          imageHeight = decoded.height;
          _resolution = ui.Size(
            decoded.width.toDouble(),
            decoded.height.toDouble(),
          );
          try {
            final completer = Completer<ui.Image>();
            ui.decodeImageFromPixels(
              decoded.rgbaBytes,
              decoded.width,
              decoded.height,
              ui.PixelFormat.rgba8888,
              completer.complete,
            );
            cachedImage = await completer.future;
            return cachedImage;
          } catch (_) {}
        }

        final codec = await ui.instantiateImageCodec(rawBytes);
        final frame = await codec.getNextFrame();
        cachedImage = frame.image;
        _resolution = ui.Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        imageWidth ??= frame.image.width;
        imageHeight ??= frame.image.height;
        return cachedImage;
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    cachedImage?.dispose();
    cachedImage = null;
    super.dispose();
  }
}

/// Multi-pass Buffer channel that feeds the output of Buffer A, B, C, or D.
class BufferChannel extends ShaderChannel {
  BufferChannel({
    required this.bufferIndex, // 0 = Buffer A, 1 = Buffer B, etc.
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  });

  /// The buffer pass index: 0 for Buffer A, 1 for Buffer B, etc.
  final int bufferIndex;

  String get bufferName => 'Buffer ${String.fromCharCode(65 + bufferIndex)}';

  @override
  ChannelType get type => ChannelType.buffer;

  @override
  ui.Size get resolution => const ui.Size(800, 450);
}

/// CubeMap channel with 6 cube faces. Not yet supported.
class CubeMapChannel extends ShaderChannel {
  CubeMapChannel({
    this.assetPaths = const [],
    this.name = 'CubeMap',
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  });

  final List<String> assetPaths;
  final String name;

  @override
  ChannelType get type => ChannelType.cubeMap;

  @override
  ui.Size get resolution => const ui.Size(512, 512);
}

/// Keyboard channel providing 256x3 keyboard state texture (row 0: down, row 1: click, row 2: toggle).
class KeyboardChannel extends ShaderChannel {
  KeyboardChannel({
    super.filter = ChannelFilter.nearest,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  });

  @override
  ChannelType get type => ChannelType.keyboard;

  @override
  ui.Size get resolution => const ui.Size(256, 3);
}
