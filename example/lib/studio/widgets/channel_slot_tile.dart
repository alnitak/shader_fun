import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

/// A tile for an individual iChannel (0..3).
class ChannelSlotTile extends StatelessWidget {
  const ChannelSlotTile({
    super.key,
    required this.slotIndex,
    required this.channel,
    required this.onTap,
    required this.onClear,
    this.onSettings,
  });

  final int slotIndex;
  final ShaderChannel? channel;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final hasChannel = channel != null;

    IconData icon;
    String label;
    Color accentColor;

    if (channel is BufferChannel) {
      icon = Icons.layers;
      label = (channel as BufferChannel).bufferName;
      accentColor = const Color(0xFFFF9900);
    } else if (channel is SoLoudAudioChannel) {
      icon = Icons.music_note;
      label = (channel as SoLoudAudioChannel).audioName;
      accentColor = const Color(0xFF00E5FF);
    } else if (channel is MicAudioChannel) {
      icon = Icons.mic;
      label = 'Microphone';
      accentColor = const Color(0xFF4ADE80);
    } else if (channel is CubeMapChannel) {
      icon = Icons.view_in_ar;
      label = 'CubeMap';
      accentColor = const Color(0xFFA855F7);
    } else if (channel is KeyboardChannel) {
      icon = Icons.keyboard;
      label = 'Keyboard';
      accentColor = const Color(0xFFE11D48);
    } else if (channel is TextureChannel) {
      icon = Icons.image;
      label = (channel as TextureChannel).name;
      accentColor = const Color(0xFF38BDF8);
    } else {
      icon = Icons.add;
      label = 'Empty';
      accentColor = Colors.white24;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasChannel
                ? accentColor.withValues(alpha: 0.6)
                : const Color(0xFF2E2E3A),
            width: hasChannel ? 1.2 : 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hasChannel
                    ? accentColor.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  (channel is TextureChannel &&
                      (channel as TextureChannel).assetPath != null)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        (channel as TextureChannel).assetPath!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(icon, color: accentColor, size: 16),
                      ),
                    )
                  : Icon(icon, color: accentColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'iChannel$slotIndex',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasChannel ? Colors.white : Colors.white38,
                      fontSize: 11,
                      fontWeight: hasChannel
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (hasChannel) ...[
              if (onSettings != null)
                Tooltip(
                  message: 'iChannel$slotIndex Setup',
                  child: InkWell(
                    onTap: onSettings,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.settings, size: 15, color: Colors.white70),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Clear Channel',
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 15, color: Colors.white38),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
