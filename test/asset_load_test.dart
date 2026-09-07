import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Test loading TextureChannel asset with raw decoding and fallback', () async {
    final channel = TextureChannel(src: 'assets/2d_texture/rgba_noise_medium.png');
    final img = await channel.loadImage();
    expect(img, isNotNull);
    expect(channel.rawRgbaBytes, isNotNull);
    expect(channel.imageWidth, 256);
    expect(channel.imageHeight, 256);
  });
}
