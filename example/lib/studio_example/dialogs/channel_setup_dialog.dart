import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// Modal dialog for configuring iChannel sampler parameters: Filter, Wrap, and VFlip.
class ChannelSetupDialog extends StatefulWidget {
  const ChannelSetupDialog({
    super.key,
    required this.slotIndex,
    required this.channel,
    required this.controller,
  });

  final int slotIndex;
  final ShaderChannel channel;
  final ShaderController controller;

  @override
  State<ChannelSetupDialog> createState() => _ChannelSetupDialogState();
}

class _ChannelSetupDialogState extends State<ChannelSetupDialog> {
  late ChannelFilter _filter;
  late ChannelWrap _wrap;
  late bool _vflip;

  @override
  void initState() {
    super.initState();
    _filter = widget.channel.filter;
    _wrap = widget.channel.wrap;
    _vflip = widget.channel.vflip;
  }

  bool get _isTexture => widget.channel is TextureChannel;
  bool get _isAudio =>
      widget.channel is AudioChannel || widget.channel is MicAudioChannel;
  bool get _isKeyboard => widget.channel is KeyboardChannel;

  List<ChannelFilter> get _availableFilters {
    if (_isKeyboard) {
      return const [ChannelFilter.nearest];
    }
    if (_isAudio) {
      return const [ChannelFilter.linear, ChannelFilter.nearest];
    }
    return const [
      ChannelFilter.mipmap,
      ChannelFilter.linear,
      ChannelFilter.nearest,
    ];
  }

  List<ChannelWrap> get _availableWraps {
    if (_isKeyboard || _isAudio) {
      return const [ChannelWrap.clamp];
    }
    return const [ChannelWrap.repeat, ChannelWrap.clamp];
  }

  String _getChannelTypeName() {
    if (widget.channel is TextureChannel) {
      final name = (widget.channel as TextureChannel).name;
      return 'Texture: $name';
    }
    if (widget.channel is BufferChannel) {
      return (widget.channel as BufferChannel).bufferName;
    }
    if (widget.channel is SoLoudAudioChannel) {
      return 'Audio: ${(widget.channel as SoLoudAudioChannel).audioName}';
    }
    if (widget.channel is MicAudioChannel) {
      return 'Microphone';
    }
    if (widget.channel is KeyboardChannel) {
      return 'Keyboard';
    }
    if (widget.channel is CubeMapChannel) {
      return 'CubeMap';
    }
    return 'Channel ${widget.slotIndex}';
  }

  void _onFilterChanged(ChannelFilter? newFilter) {
    if (newFilter == null || newFilter == _filter) return;
    setState(() => _filter = newFilter);
    widget.controller.updateChannelSettings(
      widget.slotIndex,
      filter: newFilter,
    );
  }

  void _onWrapChanged(ChannelWrap? newWrap) {
    if (newWrap == null || newWrap == _wrap) return;
    setState(() => _wrap = newWrap);
    widget.controller.updateChannelSettings(widget.slotIndex, wrap: newWrap);
  }

  void _onVFlipChanged(bool? newVFlip) {
    if (newVFlip == null || newVFlip == _vflip) return;
    setState(() => _vflip = newVFlip);
    widget.controller.updateChannelSettings(widget.slotIndex, vflip: newVFlip);
  }

  @override
  Widget build(BuildContext context) {
    final availableFilters = _availableFilters;
    final availableWraps = _availableWraps;

    return Dialog(
      backgroundColor: const Color(0xFF1B1B24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF323242), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.settings,
                    size: 18,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'iChannel${widget.slotIndex} Setup',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white60,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    splashRadius: 16,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _getChannelTypeName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Color(0xFF2E2E3E), height: 24),

              // Filter Row
              Row(
                children: [
                  const SizedBox(
                    width: 70,
                    child: Text(
                      'Filter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF242430),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF3C3C50)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ChannelFilter>(
                          value: availableFilters.contains(_filter)
                              ? _filter
                              : availableFilters.first,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF242430),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                            size: 20,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          items: availableFilters.map((f) {
                            return DropdownMenuItem<ChannelFilter>(
                              value: f,
                              child: Text(f.name),
                            );
                          }).toList(),
                          onChanged: _onFilterChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Wrap Row
              Row(
                children: [
                  const SizedBox(
                    width: 70,
                    child: Text(
                      'Wrap',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF242430),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF3C3C50)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ChannelWrap>(
                          value: availableWraps.contains(_wrap)
                              ? _wrap
                              : availableWraps.first,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF242430),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                            size: 20,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          items: availableWraps.map((w) {
                            return DropdownMenuItem<ChannelWrap>(
                              value: w,
                              child: Text(w.name),
                            );
                          }).toList(),
                          onChanged: _onWrapChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // VFlip Checkbox (available only when texture image is chosen!)
              if (_isTexture) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SizedBox(
                      width: 70,
                      child: Text(
                        'VFlip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _onVFlipChanged(!_vflip),
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _vflip,
                            activeColor: const Color(0xFF0284C7),
                            checkColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF6B7280)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                            visualDensity: VisualDensity.compact,
                            onChanged: _onVFlipChanged,
                          ),
                          Text(
                            _vflip ? 'Enabled' : 'Disabled',
                            style: TextStyle(
                              color: _vflip ? Colors.white : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E2E3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Done', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
