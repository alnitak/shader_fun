import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

import '../models/channel_assets.dart';

/// Modal for choosing an input for an iChannel (Textures, Audio with flutter_soloud, Mic with flutter_recorder, Buffers, Keyboard).
class ChannelPickerModal extends StatefulWidget {
  const ChannelPickerModal({
    super.key,
    required this.slotIndex,
    required this.currentChannel,
    required this.onSelectChannel,
  });

  final int slotIndex;
  final ShaderChannel? currentChannel;
  final ValueChanged<ShaderChannel?> onSelectChannel;

  @override
  State<ChannelPickerModal> createState() => _ChannelPickerModalState();
}

class _ChannelPickerModalState extends State<ChannelPickerModal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedTextureCategory = 'All';
  bool _isLoading = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF323242)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Stack(
          children: [
            Column(
              children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.input, size: 18, color: Color(0xFFFF5500)),
                  const SizedBox(width: 8),
                  Text(
                    'Select Input for iChannel${widget.slotIndex}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFF5500),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.image, size: 16), text: 'Textures (2D)'),
                Tab(
                  icon: Icon(Icons.music_note, size: 16),
                  text: 'Audio (SoLoud)',
                ),
                Tab(icon: Icon(Icons.mic, size: 16), text: 'Mic (Recorder)'),
                Tab(icon: Icon(Icons.layers, size: 16), text: 'Buffers'),
                Tab(icon: Icon(Icons.keyboard, size: 16), text: 'Keyboard'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTexturesTab(),
                  _buildAudioTab(),
                  _buildMicTab(),
                  _buildBuffersTab(),
                  _buildKeyboardTab(),
                ],
              ),
            ),
          ],
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFF00E5FF),
                    ),
                    if (_loadingMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _loadingMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  ),
);
  }

  Widget _buildAudioTab() {
    final tracks = ChannelAssets.allAudioTracks;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
          ),
          child: Row(
            children: [
              const Text(
                'Preset Tracks',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.folder_open, size: 15),
                label: const Text('Load File', style: TextStyle(fontSize: 12)),
                onPressed: _pickAudioFromFile,
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.link, size: 15),
                label: const Text('Load URL', style: TextStyle(fontSize: 12)),
                onPressed: _loadAudioFromUrl,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tracks.length,
            itemBuilder: (itemCtx, i) {
              final track = tracks[i];
              return Card(
                color: const Color(0xFF22222E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF2E2E3A)),
                ),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: Color(0xFF00E5FF),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    track.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '${track.genre} • 512x2 FFT & Waveform',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text(
                      'Select',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (SoLoud.instance.isInitialized) {
                        await SoLoud.instance.disposeAllSources();
                      }
                      final channel = SoLoudAudioChannel(
                        audioName: track.title,
                        audioPath: track.assetPath,
                      );
                      await channel.initAudio();
                      widget.onSelectChannel(channel);
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMicTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, size: 48, color: Color(0xFF4ADE80)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Live Microphone Input (flutter_recorder)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Streams real-time microphone FFT frequency bands and PCM waveform into a 512x2 texture.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4ADE80),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.check),
            label: const Text(
              'Enable Microphone Channel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              if (SoLoud.instance.isInitialized) {
                await SoLoud.instance.disposeAllSources();
              }
              final channel = MicAudioChannel();
              widget.onSelectChannel(channel);
              await channel.startListening();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBuffersTab() {
    final buffers = [
      {'name': 'Buffer A', 'idx': 0},
      {'name': 'Buffer B', 'idx': 1},
      {'name': 'Buffer C', 'idx': 2},
      {'name': 'Buffer D', 'idx': 3},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: buffers.length,
      itemBuilder: (context, i) {
        final buf = buffers[i];
        return Card(
          color: const Color(0xFF22222E),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFF9900),
              child: Icon(Icons.layers, color: Colors.black87),
            ),
            title: Text(
              buf['name']! as String,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Multi-pass temporal feedback texture',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9900),
              ),
              child: const Text(
                'Select',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                final channel = BufferChannel(bufferIndex: buf['idx']! as int);
                widget.onSelectChannel(channel);
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeyboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xFF1E1E28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFF2E2E3C)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3A3A4C)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.keyboard,
                              size: 44,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 14,
                              height: 2,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Keyboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF282836),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '256 x 3  •  1 ch, int8',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF262634)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Texture Specifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Row 0 (y = 0): Key down / held state (1.0 if pressed, 0.0 if up)\n'
                      '• Row 1 (y = 1): Key press trigger (1.0 for single frame upon press)\n'
                      '• Row 2 (y = 2): Key toggle state (toggled on/off on each press)\n'
                      '• Columns (x = 0..255): JavaScript keyCodes (Backspace=8, Enter=13, Shift=16, Space=32, Left=37, Up=38, Right=39, Down=40, etc.)',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Select Keyboard',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final channel = KeyboardChannel();
                    widget.onSelectChannel(channel);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTexturesTab() {
    final allTextures = ChannelAssets.allTextures;
    final filteredTextures = _selectedTextureCategory == 'All'
        ? allTextures
        : allTextures
            .where((t) => t.category == _selectedTextureCategory)
            .toList();

    const categories = [
      'All',
      'Noise',
      'Organic',
      'Surface',
      'Abstract',
      'Misc',
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSelected = _selectedTextureCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedTextureCategory = cat;
                            });
                          },
                          backgroundColor: const Color(0xFF22222E),
                          selectedColor:
                              const Color(0xFF38BDF8).withValues(alpha: 0.25),
                          checkmarkColor: const Color(0xFF38BDF8),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF323242),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.folder_open, size: 15),
                label: const Text('Load File', style: TextStyle(fontSize: 12)),
                onPressed: _pickTextureFromFile,
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.link, size: 15),
                label: const Text('Load URL', style: TextStyle(fontSize: 12)),
                onPressed: _loadTextureFromUrl,
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemCount: filteredTextures.length,
            itemBuilder: (context, index) {
              final tex = filteredTextures[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                color: const Color(0xFF22222E),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF323242)),
                ),
                child: InkWell(
                  onTap: () async {
                    final channel = TextureChannel(
                      name: tex.name,
                      assetPath: tex.assetPath,
                    );
                    await channel.loadImage();
                    widget.onSelectChannel(channel);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              tex.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white24,
                                  size: 24,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tex.category,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          tex.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<String?> _showUrlInputDialog({
    required String title,
    required String hintText,
    required IconData icon,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2E2E3C)),
          ),
          title: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF00E5FF)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Colors.white30,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFF14141C),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF2E2E3C)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF2E2E3C)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(dialogCtx).pop(trimmed);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(dialogCtx).pop(trimmed);
                }
              },
              child: const Text(
                'Load',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickTextureFromFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select Image Texture',
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Loading ${file.name}...';
      });

      final channel = TextureChannel(
        name: file.name,
        src: file.path,
        imageBytes: bytes,
      );
      final img = await channel.loadImage();
      if (img == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to decode image from ${file.name}'),
            ),
          );
        }
        return;
      }

      widget.onSelectChannel(channel);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking texture: $e')),
        );
      }
    }
  }

  Future<void> _loadTextureFromUrl() async {
    final url = await _showUrlInputDialog(
      title: 'Load Texture from URL',
      hintText: 'https://example.com/texture.png',
      icon: Icons.image,
    );
    if (url == null || url.isEmpty || !mounted) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Downloading texture...';
    });

    try {
      final uri = Uri.tryParse(url);
      final fileName = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'Web Texture';

      final channel = TextureChannel(
        name: fileName,
        src: url,
      );
      final img = await channel.loadImage();
      if (img == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load or decode image from URL'),
            ),
          );
        }
        return;
      }

      widget.onSelectChannel(channel);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading texture from URL: $e')),
        );
      }
    }
  }

  Future<void> _pickAudioFromFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select Audio File',
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'flac'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final path = file.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access audio file path')),
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Loading ${file.name}...';
      });

      if (SoLoud.instance.isInitialized) {
        await SoLoud.instance.disposeAllSources();
      }

      final channel = SoLoudAudioChannel(
        audioName: file.name,
        src: path,
      );
      await channel.initAudio();

      widget.onSelectChannel(channel);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading audio file: $e')),
        );
      }
    }
  }

  Future<void> _loadAudioFromUrl() async {
    final url = await _showUrlInputDialog(
      title: 'Load Audio from URL',
      hintText: 'https://example.com/audio.mp3',
      icon: Icons.music_note,
    );
    if (url == null || url.isEmpty || !mounted) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Connecting audio stream...';
    });

    try {
      final uri = Uri.tryParse(url);
      final audioName = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'Web Audio';

      if (SoLoud.instance.isInitialized) {
        await SoLoud.instance.disposeAllSources();
      }

      final channel = SoLoudAudioChannel(
        audioName: audioName,
        src: url,
      );
      await channel.initAudio();

      widget.onSelectChannel(channel);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading audio from URL: $e')),
        );
      }
    }
  }
}
