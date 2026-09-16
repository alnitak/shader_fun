import 'package:flutter/services.dart';

/// Manages keyboard input state for shaders adhering to Shadertoy's
/// 256x3 keyboard texture layout:
/// - Row 0 (Shadertoy / OpenGL bottom row): Key down / held state (0 or 255)
/// - Row 1: Key press / click trigger (255 for one frame, then 0)
/// - Row 2: Key toggle state (toggled between 0 and 255 on each press)
///
/// Because Impeller's shader wrapper flips y (`textureSize.y - 1 - y`),
/// the data is stored in the GPU buffer in Metal order:
/// - Metal Row 0: Toggle state (Shadertoy Row 2)
/// - Metal Row 1: Key press trigger (Shadertoy Row 1)
/// - Metal Row 2: Key down state (Shadertoy Row 0)
class ShaderKeyboardState {
  ShaderKeyboardState() {
    _initPixelData();
  }

  final Uint8List _keyDown = Uint8List(256);
  final Uint8List _keyPressed = Uint8List(256);
  final Uint8List _keyToggle = Uint8List(256);

  // 256 columns * 3 rows * 4 bytes (RGBA8) = 3072 bytes
  final Uint8List _pixelData = Uint8List(256 * 3 * 4);
  bool _dirty = true;

  void _initPixelData() {
    for (int i = 0; i < 256 * 3; i++) {
      _pixelData[i * 4 + 3] = 255; // Alpha = 1.0
    }
  }

  /// Whether any key is currently pressed or was pressed in this frame.
  bool get hasActiveInput {
    for (int i = 0; i < 256; i++) {
      if (_keyDown[i] != 0 || _keyPressed[i] != 0 || _keyToggle[i] != 0) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether a key is currently held down.
  bool isKeyDown(int keyCode) =>
      keyCode >= 0 && keyCode < 256 ? _keyDown[keyCode] != 0 : false;

  /// Returns whether a key was pressed in this frame.
  bool isKeyPressed(int keyCode) =>
      keyCode >= 0 && keyCode < 256 ? _keyPressed[keyCode] != 0 : false;

  /// Returns whether a key is currently toggled on.
  bool isKeyToggled(int keyCode) =>
      keyCode >= 0 && keyCode < 256 ? _keyToggle[keyCode] != 0 : false;

  /// Processes a Flutter [KeyEvent] and updates keyboard states.
  /// Returns `true` if the key was recognized and processed.
  bool handleKeyEvent(KeyEvent event) {
    final keyCode = logicalKeyToKeyCode(event.logicalKey);
    if (keyCode == null || keyCode < 0 || keyCode > 255) {
      return false;
    }

    if (event is KeyDownEvent) {
      if (_keyDown[keyCode] == 0) {
        _keyPressed[keyCode] = 255;
        _keyToggle[keyCode] = _keyToggle[keyCode] == 0 ? 255 : 0;
      }
      _keyDown[keyCode] = 255;
      _dirty = true;
      return true;
    } else if (event is KeyRepeatEvent) {
      _keyDown[keyCode] = 255;
      return true;
    } else if (event is KeyUpEvent) {
      _keyDown[keyCode] = 0;
      _dirty = true;
      return true;
    }
    return false;
  }

  /// Clears single-frame key-pressed triggers at the end of each frame.
  void endFrame() {
    for (int i = 0; i < 256; i++) {
      if (_keyPressed[i] != 0) {
        _keyPressed[i] = 0;
        _dirty = true;
      }
    }
  }

  /// Resets all key states (down, pressed, toggled) to 0.
  void reset() {
    _keyDown.fillRange(0, 256, 0);
    _keyPressed.fillRange(0, 256, 0);
    _keyToggle.fillRange(0, 256, 0);
    _dirty = true;
  }

  /// Returns the 256x3 RGBA pixel buffer ready to be uploaded to GPU texture.
  Uint8List get pixelData {
    if (_dirty) {
      _syncPixelData();
      _dirty = false;
    }
    return _pixelData;
  }

  void _syncPixelData() {
    for (int k = 0; k < 256; k++) {
      final toggleVal = _keyToggle[k];
      final pressVal = _keyPressed[k];
      final downVal = _keyDown[k];

      // Metal Row 0 (Toggle - Shadertoy Row 2)
      final off0 = (0 * 256 + k) * 4;
      _pixelData[off0] = toggleVal;
      _pixelData[off0 + 1] = toggleVal;
      _pixelData[off0 + 2] = toggleVal;

      // Metal Row 1 (Press trigger - Shadertoy Row 1)
      final off1 = (1 * 256 + k) * 4;
      _pixelData[off1] = pressVal;
      _pixelData[off1 + 1] = pressVal;
      _pixelData[off1 + 2] = pressVal;

      // Metal Row 2 (KeyDown - Shadertoy Row 0)
      final off2 = (2 * 256 + k) * 4;
      _pixelData[off2] = downVal;
      _pixelData[off2 + 1] = downVal;
      _pixelData[off2 + 2] = downVal;
    }
  }

  /// Maps a Flutter [LogicalKeyboardKey] to standard JavaScript keyCode (0..255).
  static int? logicalKeyToKeyCode(LogicalKeyboardKey key) {
    // 1. Check direct key map for standard control/special keys
    final directCode = _specialKeyMap[key];
    if (directCode != null) return directCode;

    // 2. Letters A-Z (keyCodes 65..90)
    final label = key.keyLabel.toUpperCase();
    if (label.length == 1) {
      final codeUnit = label.codeUnitAt(0);
      if (codeUnit >= 65 && codeUnit <= 90) {
        return codeUnit;
      }
      // Digits 0-9 (keyCodes 48..57)
      if (codeUnit >= 48 && codeUnit <= 57) {
        return codeUnit;
      }
    }

    // 3. Fallback check for ASCII in keyId
    if (key.keyId >= 32 && key.keyId <= 126) {
      return key.keyId;
    }

    return null;
  }

  static final Map<LogicalKeyboardKey, int> _specialKeyMap = {
    LogicalKeyboardKey.backspace: 8,
    LogicalKeyboardKey.tab: 9,
    LogicalKeyboardKey.enter: 13,
    LogicalKeyboardKey.numpadEnter: 13,
    LogicalKeyboardKey.shift: 16,
    LogicalKeyboardKey.shiftLeft: 16,
    LogicalKeyboardKey.shiftRight: 16,
    LogicalKeyboardKey.control: 17,
    LogicalKeyboardKey.controlLeft: 17,
    LogicalKeyboardKey.controlRight: 17,
    LogicalKeyboardKey.alt: 18,
    LogicalKeyboardKey.altLeft: 18,
    LogicalKeyboardKey.altRight: 18,
    LogicalKeyboardKey.pause: 19,
    LogicalKeyboardKey.capsLock: 20,
    LogicalKeyboardKey.escape: 27,
    LogicalKeyboardKey.space: 32,
    LogicalKeyboardKey.pageUp: 33,
    LogicalKeyboardKey.pageDown: 34,
    LogicalKeyboardKey.end: 35,
    LogicalKeyboardKey.home: 36,
    LogicalKeyboardKey.arrowLeft: 37,
    LogicalKeyboardKey.arrowUp: 38,
    LogicalKeyboardKey.arrowRight: 39,
    LogicalKeyboardKey.arrowDown: 40,
    LogicalKeyboardKey.insert: 45,
    LogicalKeyboardKey.delete: 46,

    // Digits
    LogicalKeyboardKey.digit0: 48,
    LogicalKeyboardKey.digit1: 49,
    LogicalKeyboardKey.digit2: 50,
    LogicalKeyboardKey.digit3: 51,
    LogicalKeyboardKey.digit4: 52,
    LogicalKeyboardKey.digit5: 53,
    LogicalKeyboardKey.digit6: 54,
    LogicalKeyboardKey.digit7: 55,
    LogicalKeyboardKey.digit8: 56,
    LogicalKeyboardKey.digit9: 57,

    // Numpad digits
    LogicalKeyboardKey.numpad0: 96,
    LogicalKeyboardKey.numpad1: 97,
    LogicalKeyboardKey.numpad2: 98,
    LogicalKeyboardKey.numpad3: 99,
    LogicalKeyboardKey.numpad4: 100,
    LogicalKeyboardKey.numpad5: 101,
    LogicalKeyboardKey.numpad6: 102,
    LogicalKeyboardKey.numpad7: 103,
    LogicalKeyboardKey.numpad8: 104,
    LogicalKeyboardKey.numpad9: 105,

    // Function keys
    LogicalKeyboardKey.f1: 112,
    LogicalKeyboardKey.f2: 113,
    LogicalKeyboardKey.f3: 114,
    LogicalKeyboardKey.f4: 115,
    LogicalKeyboardKey.f5: 116,
    LogicalKeyboardKey.f6: 117,
    LogicalKeyboardKey.f7: 118,
    LogicalKeyboardKey.f8: 119,
    LogicalKeyboardKey.f9: 120,
    LogicalKeyboardKey.f10: 121,
    LogicalKeyboardKey.f11: 122,
    LogicalKeyboardKey.f12: 123,

    // Punctuation
    LogicalKeyboardKey.semicolon: 186,
    LogicalKeyboardKey.equal: 187,
    LogicalKeyboardKey.comma: 188,
    LogicalKeyboardKey.minus: 189,
    LogicalKeyboardKey.period: 190,
    LogicalKeyboardKey.slash: 191,
    LogicalKeyboardKey.backquote: 192,
    LogicalKeyboardKey.bracketLeft: 219,
    LogicalKeyboardKey.backslash: 220,
    LogicalKeyboardKey.bracketRight: 221,
    LogicalKeyboardKey.quote: 222,
  };
}
