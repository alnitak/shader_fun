import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

import 'channel_file_loader.dart';

import 'raw_image_decoder.dart';

/// Filtering mode for an iChannel sampler.
enum ChannelFilter { linear, nearest, mipmap }

/// Address wrapping mode for an iChannel sampler.
enum ChannelWrap { clamp, repeat }

/// The type of input connected to an iChannel slot.
enum ChannelType { texture, buffer, audio, mic, cubeMap, keyboard, widget }

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
        final loaded = await loadFileOrHttpBytes(path);
        if (loaded != null) {
          rawBytes = loaded;
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
            rawBytes = tryLoadFilesystemCandidates(candidates);
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

/// Live interactive Flutter widget channel that rasterizes an arbitrary Flutter
/// [Widget] subtree into a GPU texture each frame via `flutter_scene`'s
/// [WidgetTexture] pipeline.
///
/// The resulting texture is bound to the pass's `sampler2D iChannel` slot and
/// can be sampled in GLSL just like any 2D texture. Synthetic pointer events
/// (clicks, drags, touches, and mouse wheel scrolls) are forwarded to the child
/// widget when [interactive] is true.
///
/// ### Dual-Mode Operation
///
/// 1. **Automatic Percentile Mapping (`autoRender = true`)**:
///    - The widget is assumed to occupy a sub-rectangle of the viewport defined by
///      [horizontalPercentile] and [verticalPercentile] (ranges between `0.0` and `1.0`).
///    - For example, `horizontalPercentile: (0.1, 0.9)` and `verticalPercentile: (0.0, 1.0)`
///      places the widget centered with 10% side margins.
///    - Hit-testing and pointer forwarding are automatically calculated by remapping
///      viewport coordinates falling within that bounding box to the widget's
///      internal texture UV space `[0.0, 1.0]`.
///
/// 2. **Custom / Freeform Mode (`autoRender = false`)**:
///    - The user controls texture sampling entirely in their GLSL shader code
///      (e.g., via `texture(iChannel0, distortedUv)`).
///    - The [horizontalPercentile] and [verticalPercentile] bounds are ignored.
///    - Pointer events can be transformed using [uvTransform] to match the shader's
///      geometric distortions, or default to a 1:1 viewport-to-widget coordinate mapping.
///
/// ### Deep Dive: `uvTransform`
///
/// When [autoRender] is `false`, the shader might distort, scale, rotate, or project
/// the widget texture onto arbitrary geometry. [uvTransform] is the mathematical
/// **forward function** mapping normalized viewport coordinates `(u, v)` (where
/// `(0, 0)` is top-left and `(1, 1)` is bottom-right) into the widget's internal
/// texture UV coordinates `(u_w, v_w)`:
///
/// ```dart
/// // Example: The shader draws the widget at half size centered on screen:
/// // GLSL: vec2 widgetUv = (uv - vec2(0.25)) * 2.0;
/// // In Dart, provide the identical mapping so gestures hit the correct controls:
/// uvTransform: (viewportUv) => (viewportUv - const Offset(0.25, 0.25)) * 2.0,
/// ```
///
/// If [uvTransform] returns an offset outside `[0.0, 1.0]`, the pointer event is
/// ignored because it fell outside the active widget surface. If [uvTransform] is null,
/// a default 1:1 mapping `(u, v) -> (u, v)` across the full viewport is applied.
///
/// ### Creative Use Cases
///
/// - **Interactive Screen & Page Transitions**:
///   Place Page A on `iChannel0` and Page B on `iChannel1`. A single GLSL shader can
///   perform liquid cross-dissolves, page curls, burn-away fire wipes, or
///   slicing transitions while both pages remain live Flutter widget trees.
/// - **Exploding / Shattering Buttons**:
///   Trigger a particle shockwave or voronoi shatter shader over an interactive button
///   when clicked, using [horizontalPercentile] and [verticalPercentile] to anchor the
///   explosion epicenter.
/// - **3D Spatial UI & Holograms**:
///   Raymarch curved holographic displays, spherical control panels, or in-game arcade
///   screens in GLSL while Flutter handles state, logic, and buttons.
/// - **Stylized Post-Processing**:
///   Apply CRT phosphor curvature and scanlines, water ripple refractions, magnifying glass
///   distortion, or frosted-glass dispersion over standard Flutter forms and dashboards.
class WidgetChannel extends ShaderChannel {
  WidgetChannel({
    required this.child,
    this.name = 'Widget',
    this.width = 800.0,
    this.height = 450.0,
    this.pixelRatio = 1.0,
    this.autoRender = true,
    this.horizontalPercentile = const (0.0, 1.0),
    this.verticalPercentile = const (0.0, 1.0),
    this.interactive = true,
    this.uvTransform,
    super.filter = ChannelFilter.linear,
    super.wrap = ChannelWrap.clamp,
    super.vflip = false,
  });

  /// The Flutter widget tree to rasterize into a live GPU texture.
  final Widget child;

  /// Display name of the channel in the studio/inspector UI.
  final String name;

  /// Logical width in points for layout and rasterization of [child].
  final double width;

  /// Logical height in points for layout and rasterization of [child].
  final double height;

  /// Pixel ratio applied during rasterization. Higher values yield sharper
  /// textures on HiDPI displays.
  final double pixelRatio;

  /// When true, the widget is automatically placed within the viewport
  /// according to [horizontalPercentile] and [verticalPercentile].
  ///
  /// When false, the widget texture is supplied as raw input to the shader,
  /// leaving full layout and distortion control to GLSL. [horizontalPercentile]
  /// and [verticalPercentile] are ignored in this mode.
  final bool autoRender;

  /// Horizontal start and end percentiles `(min, max)` within `[0.0, 1.0]`.
  /// Only used when [autoRender] is true.
  final (double start, double end) horizontalPercentile;

  /// Vertical start and end percentiles `(min, max)` within `[0.0, 1.0]`.
  /// Only used when [autoRender] is true.
  final (double start, double end) verticalPercentile;

  /// Whether pointer events (taps, drags, mouse wheel scrolls) should be
  /// forwarded to the underlying widget tree.
  bool interactive;

  /// Optional UV transformation mapping normalized viewport coordinates `[0.0, 1.0]`
  /// to normalized widget texture coordinates `[0.0, 1.0]`.
  ///
  /// Only used when [autoRender] is false. If null, a 1:1 identity mapping is assumed.
  final Offset Function(Offset viewportUv)? uvTransform;

  /// Controller managing GPU texture captures and synthetic pointer dispatch.
  final WidgetTextureController textureController = WidgetTextureController();

  @override
  ChannelType get type => ChannelType.widget;

  @override
  ui.Size get resolution => ui.Size(width * pixelRatio, height * pixelRatio);

  /// Maps a normalized viewport UV coordinate `[0.0, 1.0]` into the normalized
  /// texture coordinate `[0.0, 1.0]` for this widget.
  ///
  /// Takes [autoRender], [horizontalPercentile], [verticalPercentile],
  /// [uvTransform], and [vflip] into account.
  Offset? mapViewportUvToWidgetUv(Offset viewportUv) {
    if (autoRender) {
      final hSpan = horizontalPercentile.$2 - horizontalPercentile.$1;
      final vSpan = verticalPercentile.$2 - verticalPercentile.$1;
      if (hSpan == 0 || vSpan == 0) return null;

      final uWidget = (viewportUv.dx - horizontalPercentile.$1) / hSpan;
      final topOnScreen = 1.0 - verticalPercentile.$2;
      var vWidget = (viewportUv.dy - topOnScreen) / vSpan;
      if (vflip) {
        vWidget = 1.0 - vWidget;
      }
      return Offset(uWidget, vWidget);
    } else {
      var widgetUv = uvTransform != null
          ? uvTransform!(viewportUv)
          : viewportUv;
      if (vflip) {
        widgetUv = Offset(widgetUv.dx, 1.0 - widgetUv.dy);
      }
      return widgetUv;
    }
  }

  /// Returns true if [widgetUv] lies within the normalized widget bounds `[0.0, 1.0]`.
  bool isUvInside(Offset? widgetUv) {
    if (widgetUv == null) return false;
    return widgetUv.dx >= 0.0 &&
        widgetUv.dx <= 1.0 &&
        widgetUv.dy >= 0.0 &&
        widgetUv.dy <= 1.0;
  }

  @override
  void dispose() {
    textureController.dispose();
    super.dispose();
  }
}
