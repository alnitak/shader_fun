import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../channels/shader_channel.dart';
import '../controller/shader_controller.dart';

/// An interactive viewport displaying the rendered output of a [ShaderController].
class ShaderViewport extends StatefulWidget {
  const ShaderViewport({
    super.key,
    required this.controller,
    this.showControls = true,
    this.onToggleFullscreen,
    this.isFullscreen = false,
  });

  final ShaderController controller;
  final bool showControls;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  @override
  State<ShaderViewport> createState() => _ShaderViewportState();
}

class _ShaderViewportState extends State<ShaderViewport>
    with TickerProviderStateMixin {
  Offset? _lastPointerPos;
  final FocusNode _focusNode = FocusNode();
  final Map<WidgetChannel, Set<int>> _activePointers = {};

  List<WidgetChannel> _getActiveWidgetChannels() {
    final channels = <WidgetChannel>{};
    for (final pass in widget.controller.project.passes) {
      for (final ch in pass.channels) {
        if (ch is WidgetChannel) {
          channels.add(ch);
        }
      }
    }
    return channels.toList();
  }

  bool _hasKeyboardChannel() {
    for (final pass in widget.controller.project.passes) {
      for (final ch in pass.channels) {
        if (ch is KeyboardChannel) return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.attachTicker(this);
    widget.controller.renderSingleFrame();
  }

  @override
  void didUpdateWidget(covariant ShaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detachTicker(this);
      widget.controller.attachTicker(this);
      widget.controller.renderSingleFrame();
    }
    final active = _getActiveWidgetChannels().toSet();
    _activePointers.removeWhere((channel, pointers) {
      if (!active.contains(channel)) {
        for (final p in pointers) {
          channel.textureController.pointerCancel(pointer: p);
        }
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    for (final entry in _activePointers.entries) {
      for (final pointer in entry.value) {
        entry.key.textureController.pointerCancel(pointer: pointer);
      }
    }
    _activePointers.clear();
    _focusNode.dispose();
    widget.controller.detachTicker(this);
    super.dispose();
  }

  String _formatTime(double sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).floor().toString().padLeft(2, '0');
    final ms = ((sec % 1.0) * 100).floor().toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 450.0;

        // Fit standard 16:9 canvas within viewport constraints so shaders display the full plane
        double targetW = maxW;
        double targetH = maxW * 9.0 / 16.0;
        if (targetH > maxH) {
          targetH = maxH;
          targetW = targetH * 16.0 / 9.0;
        }

        final renderSize = Size(
          targetW.floorToDouble(),
          targetH.floorToDouble(),
        );

        // Schedule resize if dimensions changed
        if (widget.controller.resolution != renderSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.controller.resolution != renderSize) {
              widget.controller.resize(renderSize);
            }
          });
        }

        final widgetChannels = _getActiveWidgetChannels();

        return Stack(
          fit: StackFit.expand,
          children: [
            // Dark viewport background
            const ColoredBox(color: Color(0xFF0A0A0D)),

            // Mount WidgetTexture for active WidgetChannels so Flutter
            // updates and rasterizes them into GPU textures every frame.
            for (final ch in widgetChannels)
              Positioned(
                left: 0,
                top: 0,
                width: ch.width,
                height: ch.height,
                child: ExcludeSemantics(
                  child: WidgetTexture(
                    controller: ch.textureController,
                    width: ch.width,
                    height: ch.height,
                    pixelRatio: ch.pixelRatio,
                    update: WidgetUpdatePolicy.everyFrame,
                    child: ch.child,
                  ),
                ),
              ),

            // 1. Shader Image Viewport & Pointer Listener (centered 16:9 canvas)
            Center(
              child: SizedBox(
                width: renderSize.width,
                height: renderSize.height,
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: false,
                  onKeyEvent: (node, event) {
                    final handled = widget.controller.handleKeyEvent(event);
                    return handled
                        ? KeyEventResult.handled
                        : KeyEventResult.ignored;
                  },
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      final local = event.localPosition;
                      _lastPointerPos = local;
                      widget.controller.handlePointerDown(local);

                      bool channelHit = false;
                      final uv = Offset(
                        renderSize.width > 0
                            ? local.dx / renderSize.width
                            : 0.0,
                        renderSize.height > 0
                            ? local.dy / renderSize.height
                            : 0.0,
                      );
                      for (final ch in widgetChannels) {
                        if (!ch.interactive) continue;
                        final widgetUv = ch.mapViewportUvToWidgetUv(uv);
                        if (ch.isUvInside(widgetUv)) {
                          channelHit = true;
                          _activePointers
                              .putIfAbsent(ch, () => <int>{})
                              .add(event.pointer);
                          ch.textureController.pointerDown(
                            widgetUv!,
                            pointer: event.pointer,
                          );
                        }
                      }

                      if (!channelHit &&
                          _hasKeyboardChannel() &&
                          !_focusNode.hasFocus) {
                        _focusNode.requestFocus();
                      }
                    },
                    onPointerMove: (event) {
                      final local = event.localPosition;
                      _lastPointerPos = local;
                      widget.controller.handlePointerMove(local);

                      final uv = Offset(
                        renderSize.width > 0
                            ? local.dx / renderSize.width
                            : 0.0,
                        renderSize.height > 0
                            ? local.dy / renderSize.height
                            : 0.0,
                      );
                      for (final ch in widgetChannels) {
                        if (!ch.interactive) continue;
                        if (_activePointers[ch]?.contains(event.pointer) ==
                            true) {
                          final widgetUv = ch.mapViewportUvToWidgetUv(uv);
                          if (widgetUv != null) {
                            ch.textureController.pointerMove(
                              widgetUv,
                              pointer: event.pointer,
                            );
                          }
                        }
                      }
                    },
                    onPointerUp: (event) {
                      final local = event.localPosition;
                      _lastPointerPos = local;
                      widget.controller.handlePointerUp(local);

                      final uv = Offset(
                        renderSize.width > 0
                            ? local.dx / renderSize.width
                            : 0.0,
                        renderSize.height > 0
                            ? local.dy / renderSize.height
                            : 0.0,
                      );
                      for (final ch in widgetChannels) {
                        if (!ch.interactive) continue;
                        if (_activePointers[ch]?.remove(event.pointer) ==
                            true) {
                          final widgetUv = ch.mapViewportUvToWidgetUv(uv);
                          if (widgetUv != null) {
                            ch.textureController.pointerUp(
                              widgetUv,
                              pointer: event.pointer,
                            );
                          } else {
                            ch.textureController.pointerCancel(
                              pointer: event.pointer,
                            );
                          }
                        }
                      }
                    },
                    onPointerCancel: (event) {
                      widget.controller.handlePointerUp(_lastPointerPos);
                      for (final ch in widgetChannels) {
                        if (!ch.interactive) continue;
                        if (_activePointers[ch]?.remove(event.pointer) ==
                            true) {
                          ch.textureController.pointerCancel(
                            pointer: event.pointer,
                          );
                        }
                      }
                    },
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        final local = signal.localPosition;
                        final uv = Offset(
                          renderSize.width > 0
                              ? local.dx / renderSize.width
                              : 0.0,
                          renderSize.height > 0
                              ? local.dy / renderSize.height
                              : 0.0,
                        );
                        for (final ch in widgetChannels) {
                          if (!ch.interactive) continue;
                          final widgetUv = ch.mapViewportUvToWidgetUv(uv);
                          if (ch.isUvInside(widgetUv)) {
                            ch.textureController.pointerScroll(
                              widgetUv!,
                              signal.scrollDelta,
                            );
                          }
                        }
                      }
                    },
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, child) {
                        final image = widget.controller.currentImage;
                        final isCompiling = widget.controller.isCompiling;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              size: renderSize,
                              painter: _ShaderImagePainter(image: image),
                            ),
                            if (image == null)
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isCompiling
                                          ? 'Compiling shader...'
                                          : 'Loading shader...',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // 2. Playback Controls Toolbar
            if (widget.showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    return Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          // Play / Pause
                          IconButton(
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            icon: Icon(
                              widget.controller.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            tooltip: widget.controller.isPlaying
                                ? 'Pause'
                                : 'Play',
                            onPressed: () => widget.controller.togglePlay(),
                          ),

                          // Rewind / Restart
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            icon: const Icon(
                              Icons.replay,
                              color: Colors.white70,
                            ),
                            tooltip: 'Restart (Time = 0)',
                            onPressed: () => widget.controller.rewind(),
                          ),

                          const SizedBox(width: 8),

                          // Time display
                          Text(
                            _formatTime(widget.controller.time),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Frame count
                          Text(
                            '#${widget.controller.frame}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),

                          const Spacer(),

                          // FPS
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white12,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              widget.controller.isPlaying
                                  ? '${widget.controller.fps.toStringAsFixed(1)} fps'
                                  : 'PAUSED',
                              style: TextStyle(
                                color: widget.controller.isPlaying
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFFBBF24),
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Resolution
                          Text(
                            '${widget.controller.resolution.width.toInt()}x${widget.controller.resolution.height.toInt()}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),

                          const SizedBox(width: 6),

                          // Fullscreen toggle
                          if (widget.onToggleFullscreen != null)
                            IconButton(
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30),
                              icon: Icon(
                                widget.isFullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                color: Colors.white70,
                              ),
                              tooltip: widget.isFullscreen
                                  ? 'Exit Fullscreen'
                                  : 'Fullscreen',
                              onPressed: widget.onToggleFullscreen,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShaderImagePainter extends CustomPainter {
  _ShaderImagePainter({this.image});

  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    // Ensure opaque background is always drawn to prevent any bleed-through
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0F0F12),
    );

    if (image == null) return;

    final src = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..filterQuality = FilterQuality.low;
    canvas.drawImageRect(image!, src, dst, paint);
  }

  @override
  bool shouldRepaint(_ShaderImagePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
