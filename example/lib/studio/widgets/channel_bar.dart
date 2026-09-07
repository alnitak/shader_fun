import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

import 'channel_slot_tile.dart';

/// Bottom bar displaying the 4 iChannel slots for the active shader pass.
class ChannelBar extends StatelessWidget {
  const ChannelBar({
    super.key,
    required this.pass,
    required this.onOpenChannelPicker,
    required this.onChannelCleared,
    this.onOpenChannelSettings,
  });

  final ShaderPass? pass;
  final ValueChanged<int> onOpenChannelPicker;
  final ValueChanged<int> onChannelCleared;
  final ValueChanged<int>? onOpenChannelSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        border: Border(top: BorderSide(color: Color(0xFF282832), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: List.generate(4, (index) {
          final ch = pass?.getChannel(index);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChannelSlotTile(
                slotIndex: index,
                channel: ch,
                onTap: () => onOpenChannelPicker(index),
                onSettings: onOpenChannelSettings != null
                    ? () => onOpenChannelSettings!(index)
                    : null,
                onClear: () async {
                  final oldCh = pass?.getChannel(index);
                  if (oldCh is SoLoudAudioChannel &&
                      SoLoud.instance.isInitialized) {
                    await SoLoud.instance.disposeAllSources();
                  }
                  onChannelCleared(index);
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}
