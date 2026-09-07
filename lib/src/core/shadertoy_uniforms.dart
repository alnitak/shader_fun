import 'dart:typed_data';
import 'dart:ui';

/// Container for all standard ShaderToy uniforms passed to shaders.
///
/// Encapsulates the runtime variables accessible in Shadertoy GLSL code
/// (`iResolution`, `iTime`, `iTimeDelta`, `iFrame`, `iFrameRate`, `iMouse`,
/// `iDate`, `iSampleRate`, `iChannelTime`, `iChannelResolution`).
class ShaderToyUniforms {
  ShaderToyUniforms({
    this.resolution = const Size(800, 450),
    this.pixelRatio = 1.0,
    this.time = 0.0,
    this.timeDelta = 0.01666,
    this.frame = 0,
    this.frameRate = 60.0,
    this.mouse = const Offset4(0, 0, 0, 0),
    DateTime? date,
    this.sampleRate = 44100.0,
    List<double>? channelTime,
    List<Size>? channelResolution,
  })  : channelTime = channelTime ?? List<double>.filled(4, 0.0),
        channelResolution = channelResolution ??
            List<Size>.filled(4, const Size(512, 512)),
        date = date ?? DateTime.now();

  /// Viewport resolution in pixels (`iResolution`).
  ///
  /// In Shadertoy GLSL:
  /// - `iResolution.x`: Viewport width in physical pixels.
  /// - `iResolution.y`: Viewport height in physical pixels.
  /// - `iResolution.z`: Pixel aspect ratio (standardized to `1.0` in WebGL Shadertoy).
  ///
  /// Typical GLSL usage:
  /// ```glsl
  /// vec2 uv = fragCoord / iResolution.xy;
  /// ```
  Size resolution;

  /// Display device pixel ratio (DPR) used for scaling UI and high-DPI viewports.
  double pixelRatio;

  /// Elapsed playback time in seconds (`iTime`).
  ///
  /// Monotonically increases during playback, accounts for play/pause/seek.
  /// Standard Shadertoy usage drives periodic animation:
  /// ```glsl
  /// float wave = sin(iTime * 2.0);
  /// ```
  double time;

  /// Time difference from the previous frame in seconds (`iTimeDelta`).
  ///
  /// Typically `~0.01666` at 60 FPS, `~0.00833` at 120 FPS.
  /// Used for delta-time physics simulations and frame-rate-independent decay.
  double timeDelta;

  /// Current render frame index (`iFrame`).
  ///
  /// Starts at 0 when playback begins or rewinds and increments by 1 on every
  /// rendered frame. In multi-pass feedback buffers (e.g., fluid solvers, Conway's
  /// Game of Life, mouse paint canvas), shaders commonly check `if (iFrame == 0)`
  /// to perform initial state setup before iterative accumulation.
  int frame;

  /// Smoothed render frame rate in frames per second (`iFrameRate`).
  double frameRate;

  /// Mouse and pointer interaction coordinates (`iMouse`).
  ///
  /// Follows the complete ShaderToy `iMouse` specification (xyzw in pixel units):
  ///
  /// - **`iMouse.xy`**: Current pointer position in pixels (relative to bottom-left).
  ///   While the left mouse button or touch is held down, this tracks the active
  ///   cursor position. When the button is released, `xy` preserves the last
  ///   position where the user dragged or clicked.
  /// - **`iMouse.zw`**: Click and drag anchor coordinates:
  ///   - **While pressed / dragging**: `zw` holds the positive pixel coordinates
  ///     where the click was originally initiated (`iMouse.z > 0.0`).
  ///   - **When released (mouse up)**: The coordinates are inverted to negative
  ///     values (`-abs(clickX), -abs(clickY)`), signaling that the pointer is up
  ///     (`iMouse.z <= 0.0`) while still preserving the location of the last click
  ///     via `abs(iMouse.zw)`.
  ///
  /// Common GLSL idioms:
  /// ```glsl
  /// // Check if the user is currently clicking or dragging
  /// if (iMouse.z > 0.0) {
  ///     vec2 mousePos = iMouse.xy / iResolution.xy;
  /// }
  ///
  /// // Check if a click has ever occurred
  /// if (abs(iMouse.z) > 0.0) { ... }
  /// ```
  Offset4 mouse;

  /// Current calendar date and clock time (`iDate`).
  ///
  /// In Shadertoy GLSL:
  /// - `iDate.x`: Year (e.g. 2026.0).
  /// - `iDate.y`: Month (0-indexed in Shadertoy: 0.0 = January .. 11.0 = December).
  /// - `iDate.z`: Day of the month (1.0 .. 31.0).
  /// - `iDate.w`: Elapsed seconds into the current day (with millisecond precision:
  ///   `hour * 3600 + minute * 60 + second + millisecond / 1000.0`).
  DateTime date;

  /// Sound audio sample rate in Hz (`iSampleRate`, typically `44100.0`).
  double sampleRate;

  /// Playback time in seconds for each of the 4 channel inputs (`iChannelTime[4]`).
  List<double> channelTime;

  /// Pixel resolution of each of the 4 channel inputs (`iChannelResolution[4]`).
  ///
  /// In Shadertoy GLSL, `uniform vec3 iChannelResolution[4];` exposes a 3D vector
  /// `(width, height, pixel_aspect_ratio)` for each channel slot `0..3`.
  ///
  /// Resolution varies by channel type:
  ///
  /// - **2D Image (`TextureChannel`)**: The physical pixel dimensions of the
  ///   loaded image: `(img.width, img.height, 1.0)`. Used to scale UVs or sample
  ///   texels at native resolution (e.g. `p / iChannelResolution[0].xy`).
  /// - **Multi-pass Buffer (`BufferChannel`)**: Output of Buffer A, B, C, or D.
  ///   Matches the render viewport resolution: `(iResolution.x, iResolution.y, 1.0)`.
  /// - **Audio Spectrum (`AudioChannel`)**: Audio texture resolution:
  ///   `(1024.0, 2.0, 1.0)` in this package (row 0: FFT magnitudes, row 1: waveform;
  ///   Shadertoy web uses `512.0, 2.0, 1.0`).
  /// - **Keyboard State (`KeyboardChannel`)**: Standard 256x3 keyboard texture:
  ///   `(256.0, 3.0, 1.0)` (row 0: is-down, row 1: on-press click, row 2: key toggle).
  /// - **CubeMap (`CubeMapChannel`)**: Cube face resolution: `(512.0, 512.0, 1.0)`.
  /// - **Unused / Empty Slot**: `(0.0, 0.0, 0.0)`.
  ///
  /// Example GLSL usage:
  /// ```glsl
  /// // Sample texture repeating at native pixel scale
  /// vec4 color = texture(iChannel0, fragCoord / iChannelResolution[0].xy);
  /// ```
  List<Size> channelResolution;

  /// Packs the uniform data into a float array for standard uniform buffer uploads.
  Float32List toFloat32List() {
    // Standard layout:
    // 0..2: iResolution (width, height, aspect ratio)
    // 3: iTime
    // 4: iTimeDelta
    // 5: iFrame (as float)
    // 6: iFrameRate
    // 7: iSampleRate
    // 8..11: iMouse (x, y, z, w)
    // 12..15: iDate (year, month, day, seconds)
    // 16..19: iChannelTime[4]
    // 20..31: iChannelResolution[4] (3 floats each = 12 floats)
    final data = Float32List(32);
    data[0] = resolution.width;
    data[1] = resolution.height;
    data[2] = resolution.height > 0 ? resolution.width / resolution.height : 1.0;
    data[3] = time;
    data[4] = timeDelta;
    data[5] = frame.toDouble();
    data[6] = frameRate;
    data[7] = sampleRate;

    data[8] = mouse.x;
    data[9] = mouse.y;
    data[10] = mouse.z;
    data[11] = mouse.w;

    final secondsOfDay = date.hour * 3600.0 +
        date.minute * 60.0 +
        date.second.toDouble() +
        date.millisecond / 1000.0;
    data[12] = date.year.toDouble();
    data[13] = (date.month - 1).toDouble();
    data[14] = date.day.toDouble();
    data[15] = secondsOfDay;

    for (int i = 0; i < 4; i++) {
      data[16 + i] = i < channelTime.length ? channelTime[i] : 0.0;
    }

    for (int i = 0; i < 4; i++) {
      final res = i < channelResolution.length
          ? channelResolution[i]
          : const Size(0, 0);
      data[20 + i * 3] = res.width;
      data[20 + i * 3 + 1] = res.height;
      data[20 + i * 3 + 2] = 1.0;
    }

    return data;
  }
}

/// 4-component vector used for ShaderToy's `iMouse` (xyzw in pixel coordinates).
///
/// - [x], [y]: Current pointer coordinates (or last position when released).
/// - [z], [w]: Click anchor position when pressed (> 0), or negated coordinates when released (<= 0).
class Offset4 {
  const Offset4(this.x, this.y, this.z, this.w);

  /// Current pointer X position in pixels from the bottom-left corner.
  final double x;

  /// Current pointer Y position in pixels from the bottom-left corner.
  final double y;

  /// Click anchor X position. Positive when pressed down, negative when released.
  final double z;

  /// Click anchor Y position. Positive when pressed down, negative when released.
  final double w;

  Offset4 copyWith({double? x, double? y, double? z, double? w}) {
    return Offset4(
      x ?? this.x,
      y ?? this.y,
      z ?? this.z,
      w ?? this.w,
    );
  }

  @override
  String toString() => 'Offset4($x, $y, $z, $w)';
}
