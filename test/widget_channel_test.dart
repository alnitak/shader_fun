import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetChannel', () {
    test('default configuration and properties', () {
      final channel = WidgetChannel(
        child: const SizedBox(width: 400, height: 300),
        width: 400,
        height: 300,
      );

      expect(channel.type, equals(ChannelType.widget));
      expect(channel.width, equals(400));
      expect(channel.height, equals(300));
      expect(channel.pixelRatio, equals(1.0));
      expect(channel.resolution, equals(const Size(400, 300)));
      expect(channel.autoRender, isTrue);
      expect(channel.horizontalPercentile, equals((0.0, 1.0)));
      expect(channel.verticalPercentile, equals((0.0, 1.0)));
      expect(channel.interactive, isTrue);
      expect(channel.filter, equals(ChannelFilter.linear));
      expect(channel.wrap, equals(ChannelWrap.clamp));
      expect(channel.vflip, isFalse);

      channel.dispose();
    });

    test('resolution respects pixelRatio', () {
      final channel = WidgetChannel(
        child: const SizedBox(),
        width: 500,
        height: 250,
        pixelRatio: 2.0,
      );

      expect(channel.resolution, equals(const Size(1000, 500)));
      channel.dispose();
    });

    test('autoRender UV coordinate mapping with full coverage', () {
      final channel = WidgetChannel(
        child: const SizedBox(),
        width: 100,
        height: 100,
      );

      final uvTopLeft = channel.mapViewportUvToWidgetUv(const Offset(0.0, 0.0));
      expect(uvTopLeft, equals(const Offset(0.0, 0.0)));
      expect(channel.isUvInside(uvTopLeft), isTrue);

      final uvCenter = channel.mapViewportUvToWidgetUv(const Offset(0.5, 0.5));
      expect(uvCenter, equals(const Offset(0.5, 0.5)));
      expect(channel.isUvInside(uvCenter), isTrue);

      final uvBottomRight =
          channel.mapViewportUvToWidgetUv(const Offset(1.0, 1.0));
      expect(uvBottomRight, equals(const Offset(1.0, 1.0)));
      expect(channel.isUvInside(uvBottomRight), isTrue);

      channel.dispose();
    });

    test('autoRender UV coordinate mapping with percentiles', () {
      final channel = WidgetChannel(
        child: const SizedBox(),
        width: 200,
        height: 200,
        horizontalPercentile: (0.2, 0.8),
        verticalPercentile: (0.1, 0.9),
      );

      // Top-left of the widget area
      final uvTL = channel.mapViewportUvToWidgetUv(const Offset(0.2, 0.1));
      expect(uvTL!.dx, closeTo(0.0, 1e-5));
      expect(uvTL.dy, closeTo(0.0, 1e-5));
      expect(channel.isUvInside(uvTL), isTrue);

      // Center of the widget area
      final uvCenter = channel.mapViewportUvToWidgetUv(const Offset(0.5, 0.5));
      expect(uvCenter!.dx, closeTo(0.5, 1e-5));
      expect(uvCenter.dy, closeTo(0.5, 1e-5));
      expect(channel.isUvInside(uvCenter), isTrue);

      // Bottom-right of the widget area
      final uvBR = channel.mapViewportUvToWidgetUv(const Offset(0.8, 0.9));
      expect(uvBR!.dx, closeTo(1.0, 1e-5));
      expect(uvBR.dy, closeTo(1.0, 1e-5));
      expect(channel.isUvInside(uvBR), isTrue);

      // Outside the widget area (to the left)
      final uvOutside = channel.mapViewportUvToWidgetUv(const Offset(0.1, 0.5));
      expect(uvOutside!.dx, lessThan(0.0));
      expect(channel.isUvInside(uvOutside), isFalse);

      channel.dispose();
    });

    test('vflip inverts vertical UV', () {
      final channel = WidgetChannel(
        child: const SizedBox(),
        width: 100,
        height: 100,
        vflip: true,
      );

      final uvTop = channel.mapViewportUvToWidgetUv(const Offset(0.5, 0.0));
      expect(uvTop, equals(const Offset(0.5, 1.0)));

      final uvBottom = channel.mapViewportUvToWidgetUv(const Offset(0.5, 1.0));
      expect(uvBottom, equals(const Offset(0.5, 0.0)));

      channel.dispose();
    });

    test('custom uvTransform when autoRender is false', () {
      final channel = WidgetChannel(
        child: const SizedBox(),
        width: 100,
        height: 100,
        autoRender: false,
        uvTransform: (uv) => Offset(uv.dx * 2.0, uv.dy * 2.0),
      );

      final uv = channel.mapViewportUvToWidgetUv(const Offset(0.25, 0.25));
      expect(uv, equals(const Offset(0.5, 0.5)));
      expect(channel.isUvInside(uv), isTrue);

      final uvOutside =
          channel.mapViewportUvToWidgetUv(const Offset(0.75, 0.75));
      expect(uvOutside, equals(const Offset(1.5, 1.5)));
      expect(channel.isUvInside(uvOutside), isFalse);

      channel.dispose();
    });
  });
}
