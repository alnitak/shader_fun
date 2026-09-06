import 'dart:typed_data';
import 'dart:ui';

/// Container for all standard ShaderToy uniforms passed to shaders.
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

  /// Viewport resolution in pixels (iResolution.xy = width, height; iResolution.z = pixel aspect ratio)
  Size resolution;

  /// Display pixel ratio
  double pixelRatio;

  /// Elapsed time in seconds (iTime)
  double time;

  /// Time difference from previous frame in seconds (iTimeDelta)
  double timeDelta;

  /// Current frame index (iFrame)
  int frame;

  /// Smoothed frame rate (iFrameRate)
  double frameRate;

  /// Mouse coordinates (iMouse: xy = current pointer position, zw = click / drag anchor position)
  Offset4 mouse;

  /// Current date (iDate: x = year, y = month, z = day, w = seconds into the day)
  DateTime date;

  /// Sound sample rate in Hz (iSampleRate, typically 44100.0)
  double sampleRate;

  /// Playback time for each of the 4 channels (iChannelTime[4])
  List<double> channelTime;

  /// Pixel resolution of each of the 4 channels (iChannelResolution[4])
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

/// 4-component vector used for ShaderToy's `iMouse` (xyzw).
class Offset4 {
  const Offset4(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
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
