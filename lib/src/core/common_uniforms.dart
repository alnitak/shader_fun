import 'dart:typed_data';
import 'dart:ui';

/// Container for all standard shader uniforms passed to shaders.
///
/// Encapsulates the runtime variables accessible in GLSL code
/// (`iResolution`, `iTime`, `iTimeDelta`, `iFrame`, `iFrameRate`, `iMouse`,
/// `iDate`, `iSampleRate`, `iChannelTime`, `iChannelResolution`).
class CommonUniforms {
  CommonUniforms({
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
    Map<String, Object>? customUniforms,
  }) : channelTime = channelTime ?? List<double>.filled(4, 0.0),
       channelResolution =
           channelResolution ?? List<Size>.filled(4, const Size(512, 512)),
       date = date ?? DateTime.now() {
    if (customUniforms != null) {
      customUniforms.forEach(setCustomUniform);
    }
  }

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
    data[2] = resolution.height > 0
        ? resolution.width / resolution.height
        : 1.0;
    data[3] = time;
    data[4] = timeDelta;
    data[5] = frame.toDouble();
    data[6] = frameRate;
    data[7] = sampleRate;

    data[8] = mouse.x;
    data[9] = mouse.y;
    data[10] = mouse.z;
    data[11] = mouse.w;

    final secondsOfDay =
        date.hour * 3600.0 +
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

  /// Standard uniform block size in bytes (iResolution, iTime, etc.).
  static const int standardUniformsSizeBytes = 144;

  /// Maximum number of generic vec4 custom uniform registers (16 vec4s = 64 floats = 256 bytes by default).
  ///
  /// Note: Sizing the custom uniform pool aligns with typical GPU hardware memory
  /// allocators and driver suballocation pagination (e.g. `minUniformBufferOffsetAlignment`
  /// in Vulkan and Metal is typically 256 bytes). Even allocating a single 4-byte float still consumes
  /// a 256B/4KB physical page in GPU VRAM.
  ///
  /// To increase the custom uniforms capacity across the entire engine, updating this single
  /// [maxCustomUniformSlots] constant (e.g. to 32) is the **only** required step. All GLSL wrappers,
  /// GPU byte buffers, and WebGL reflection structures will automatically scale to match
  /// [totalUniformBufferSize].
  static const int maxCustomUniformSlots = 16;

  /// Byte size reserved for custom uniforms (16 bytes per vec4 register).
  static const int customUniformsSizeBytes = maxCustomUniformSlots * 16;

  /// Total uniform buffer size in bytes uploaded to the GPU [FrameInfo] block
  /// ([standardUniformsSizeBytes] + [customUniformsSizeBytes]).
  ///
  /// Referenced across native Impeller and WebGL pipelines to allocate and bind
  /// uniform byte buffers matching GPU memory alignment and pagination constraints.
  static const int totalUniformBufferSize =
      standardUniformsSizeBytes + customUniformsSizeBytes;

  /// Flattened raw float data for custom uniforms ([maxCustomUniformSlots] vec4 registers * 4 floats).
  final Float32List customData = Float32List(maxCustomUniformSlots * 4);

  final Map<String, int> _customSlots = {};
  final Map<String, Object> _customValues = {};

  /// Read-only map of assigned uniform slot indices (0..[maxCustomUniformSlots] - 1).
  Map<String, int> get customSlots => Map.unmodifiable(_customSlots);

  /// Read-only map of user-assigned custom uniform values.
  Map<String, Object> get customValues => Map.unmodifiable(_customValues);

  /// Explicitly registers or overrides a slot index (0..[maxCustomUniformSlots] - 1) for a uniform [name].
  void registerCustomUniformSlot(String name, int slot) {
    if (slot < 0 || slot >= maxCustomUniformSlots) {
      throw ArgumentError(
        'Custom uniform slot must be between 0 and ${maxCustomUniformSlots - 1}, got $slot',
      );
    }
    _customSlots[name] = slot;
  }

  /// Retrieves the slot index for [name], or dynamically assigns the lowest available slot.
  int getOrAssignSlot(String name) {
    if (_customSlots.containsKey(name)) {
      return _customSlots[name]!;
    }
    for (int i = 0; i < maxCustomUniformSlots; i++) {
      if (!_customSlots.values.contains(i)) {
        _customSlots[name] = i;
        return i;
      }
    }
    return 0;
  }

  /// Sets a custom uniform [value] by [name].
  ///
  /// Up to [maxCustomUniformSlots] `vec4` slots are available within the GPU
  /// uniform buffer of [totalUniformBufferSize] bytes.
  ///
  /// Automatically maps Dart/Flutter types to GLSL vectors:
  /// - [num] / [double] / [int]: 1 float (component `.x`)
  /// - [Offset] / [Size]: 2 floats (components `.xy`)
  /// - [Color]: 4 floats normalized 0.0..1.0 (components `.xyzw`)
  /// - [List<num>]: 1 to 4 floats depending on list length
  void setCustomUniform(String name, Object value) {
    final slot = getOrAssignSlot(name);
    _customValues[name] = value;
    final offset = slot * 4;

    switch (value) {
      case double v:
        customData[offset] = v;
        customData[offset + 1] = 0.0;
        customData[offset + 2] = 0.0;
        customData[offset + 3] = 0.0;
      case int v:
        customData[offset] = v.toDouble();
        customData[offset + 1] = 0.0;
        customData[offset + 2] = 0.0;
        customData[offset + 3] = 0.0;
      case Offset v:
        customData[offset] = v.dx;
        customData[offset + 1] = v.dy;
        customData[offset + 2] = 0.0;
        customData[offset + 3] = 0.0;
      case Size v:
        customData[offset] = v.width;
        customData[offset + 1] = v.height;
        customData[offset + 2] = 0.0;
        customData[offset + 3] = 0.0;
      case Color v:
        customData[offset] = v.r;
        customData[offset + 1] = v.g;
        customData[offset + 2] = v.b;
        customData[offset + 3] = v.a;
      case List<num> v:
        customData[offset] = v.isNotEmpty ? v[0].toDouble() : 0.0;
        customData[offset + 1] = v.length > 1 ? v[1].toDouble() : 0.0;
        customData[offset + 2] = v.length > 2 ? v[2].toDouble() : 0.0;
        customData[offset + 3] = v.length > 3 ? v[3].toDouble() : 0.0;
      default:
        throw ArgumentError(
          'Unsupported uniform value type for "$name": ${value.runtimeType}',
        );
    }
  }

  /// Gets the currently assigned value for custom uniform [name], if any.
  Object? getCustomUniform(String name) => _customValues[name];
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
    return Offset4(x ?? this.x, y ?? this.y, z ?? this.z, w ?? this.w);
  }

  @override
  String toString() => 'Offset4($x, $y, $z, $w)';
}
