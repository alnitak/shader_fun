import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';
import '../example/lib/studio/dialogs/channel_setup_dialog.dart';

void main() {
  test('ShaderChannel and TextureChannel default to ChannelFilter.mipmap', () {
    final tex = TextureChannel();
    expect(tex.filter, equals(ChannelFilter.mipmap));
    expect(tex.wrap, equals(ChannelWrap.repeat));
    expect(tex.vflip, isTrue);

    final buf = BufferChannel(bufferIndex: 0);
    expect(buf.filter, equals(ChannelFilter.linear));
    expect(buf.vflip, isFalse);

    final kbd = KeyboardChannel();
    expect(kbd.filter, equals(ChannelFilter.nearest));
    expect(kbd.wrap, equals(ChannelWrap.clamp));
  });

  test('ShaderToyJson defaults filter to mipmap when unspecified', () {
    final json = {
      'Shader': {
        'info': {'id': 'test', 'name': 'Test'},
        'renderpass': [
          {
            'type': 'image',
            'code': 'void mainImage(out vec4 fragColor, in vec2 fragCoord) {}',
            'inputs': [
              {
                'channel': 0,
                'ctype': 'texture',
                'src': 'assets/2d_texture/london.jpg',
                'sampler': {
                  'wrap': 'repeat',
                  'vflip': 'true',
                },
              },
              {
                'channel': 1,
                'ctype': 'keyboard',
                'sampler': {
                  'wrap': 'clamp',
                },
              },
            ],
            'outputs': [],
          }
        ]
      }
    };

    final project = ShaderToyProject.fromJson(json);
    final pass = project.imagePass!;
    expect(pass.getChannel(0)!.filter, equals(ChannelFilter.mipmap));
    expect(pass.getChannel(1)!.filter, equals(ChannelFilter.nearest));
  });

  test('ShaderToyController updates channel settings and flipY works', () async {
    final controller = ShaderToyController();
    final tex = TextureChannel(
      filter: ChannelFilter.nearest,
      wrap: ChannelWrap.clamp,
      vflip: false,
    );
    controller.activePass!.setChannel(0, tex);

    expect(tex.filter, equals(ChannelFilter.nearest));
    expect(tex.wrap, equals(ChannelWrap.clamp));
    expect(tex.vflip, isFalse);

    await controller.updateChannelSettings(
      0,
      filter: ChannelFilter.mipmap,
      wrap: ChannelWrap.repeat,
      vflip: true,
    );

    expect(tex.filter, equals(ChannelFilter.mipmap));
    expect(tex.wrap, equals(ChannelWrap.repeat));
    expect(tex.vflip, isTrue);

    // Test row inversion for vertical flip: 2x2 image
    // Row 0: [1, 2, 3, 4], [5, 6, 7, 8]
    // Row 1: [9, 10, 11, 12], [13, 14, 15, 16]
    final original = Uint8List.fromList([
      1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16,
    ]);
    final flipped = ShaderToyController.flipY(original, 2, 2);
    expect(flipped, equals([
      9, 10, 11, 12, 13, 14, 15, 16,
      1, 2, 3, 4, 5, 6, 7, 8,
    ]));

    controller.dispose();
  });

  testWidgets('ChannelSetupDialog shows VFlip for TextureChannel and hides for BufferChannel', (tester) async {
    final controller = ShaderToyController();
    final tex = TextureChannel(name: 'TestTexture');
    controller.activePass!.setChannel(0, tex);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelSetupDialog(
            slotIndex: 0,
            channel: tex,
            controller: controller,
          ),
        ),
      ),
    );

    // Filter, Wrap, and VFlip should be displayed for texture
    expect(find.text('iChannel0 Setup'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Wrap'), findsOneWidget);
    expect(find.text('VFlip'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    // Now test BufferChannel: VFlip must NOT be shown
    final buf = BufferChannel(bufferIndex: 0);
    controller.activePass!.setChannel(1, buf);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelSetupDialog(
            slotIndex: 1,
            channel: buf,
            controller: controller,
          ),
        ),
      ),
    );

    expect(find.text('iChannel1 Setup'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Wrap'), findsOneWidget);
    expect(find.text('VFlip'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    controller.dispose();
  });
}
