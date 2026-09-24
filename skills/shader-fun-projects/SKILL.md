---
name: shader-fun-projects
version: 1
description: ShaderProject data model, JSON import and export, asset loading, and feature detection in shader_fun. Use when loading shaders from JSON or asset bundles, saving/exporting projects, inspecting shader capabilities, or constructing multi-pass setups in Dart.
---

# shader_fun projects

`ShaderProject` is the data model representing an entire shader composition in `shader_fun`. It contains project metadata (`id`, `name`, `author`, `description`, `url`), the list of `ShaderPass` objects with their bound input channels, and JSON serialization logic compatible with both Shadertoy's schema and `shader_fun` extensions.

---

## 1. Creating Projects Programmatically

### Empty Starter Project
```dart
// Creates a single Image pass with default plasma GLSL code
final project = ShaderProject.empty();
```

### Custom Multi-Pass Project
```dart
final project = ShaderProject(
  name: 'Cyberpunk Neon',
  author: 'Coder',
  description: 'Multi-pass raymarched glowing city',
  passes: [
    ShaderPass(
      type: PassType.common,
      name: 'Common',
      code: commonGlslCode,
    ),
    ShaderPass(
      type: PassType.bufferA,
      name: 'Buffer A',
      code: bufferAGlslCode,
      channels: [
        TextureChannel(src: 'assets/textures/noise.png'),
        null,
        null,
        null,
      ],
    ),
    ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: imageGlslCode,
      channels: [
        BufferChannel(bufferIndex: 0), // Reads Buffer A
        null,
        null,
        null,
      ],
    ),
  ],
);

await controller.loadProject(project);
```

---

## 2. Loading from JSON & Flutter Assets

### Loading from Asset Bundle
```dart
// Provide simple file name or full path:
final project = await ShaderProject.loadFromAsset('shaders/Heartfelt.json');

// Load into controller:
await controller.loadProject(project);
controller.play();
```

### Parsing JSON Strings
```dart
import 'dart:convert';

// Load from network API or local filesystem:
final String jsonText = await fetchShaderFromBackend();
final project = ShaderProject.parseJsonString(jsonText);

await controller.loadProject(project);
```

---

## 3. Serializing & Exporting to JSON

Convert any live `ShaderProject` into a JSON map or string to save locally or upload:

```dart
// Export to JSON Map:
final Map<String, dynamic> jsonMap = project.toJson();

// Encode to formatted JSON string:
final String jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);

// Save to file or cloud storage
await saveToFile('my_shader.json', jsonString);
```

---

## 4. Feature Introspection

`ShaderProject` provides built-in getters to inspect what hardware features or inputs a shader uses:

```dart
// Check if user interaction is needed:
if (project.usesMouse) {
  print('Shader responds to mouse/touch gestures.');
}

if (project.usesKeys) {
  print('Shader requires keyboard focus.');
}

// Check audio requirements:
if (project.usesMic) {
  print('Shader requests live microphone access.');
}

if (project.hasSoundPass) {
  print('Shader generates procedural sound on the GPU.');
}

if (project.usesAudioChannel) {
  print('Shader plays an audio file or music track.');
}

if (project.usesAudio) {
  print('Shader produces sound (either GPU sound pass or audio channel).');
}

// Check texture requirements:
if (project.usesTextures) {
  print('Shader loads external 2D image textures.');
}
```

---

## 5. Querying and Modifying Passes

```dart
// Query specific pass types:
final ShaderPass? imagePass = project.imagePass;
final ShaderPass? commonPass = project.commonPass;
final ShaderPass? soundPass = project.soundPass;
final ShaderPass? bufferA = project.getPass(PassType.bufferA);

// Check if a pass exists:
final bool hasSound = project.hasPass(PassType.sound);

// Modify pass code:
imagePass?.code = myNewCode;

// Swap channels:
imagePass?.setChannel(0, TextureChannel(src: 'assets/textures/new_texture.png'));

// Recompile with updated project:
await controller.compile();
```
