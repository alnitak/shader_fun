import 'package:flutter/material.dart';

/// Top application bar for ShaderToy Studio with branding, title, and file actions.
class StudioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioAppBar({
    super.key,
    required this.projectName,
    required this.onNew,
    required this.onLoad,
    required this.onSave,
  });

  final String projectName;
  final VoidCallback onNew;
  final VoidCallback onLoad;
  final VoidCallback onSave;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF16161C),
        border: Border(bottom: BorderSide(color: Color(0xFF282832), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Icon branding
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5500), Color(0xFFFF2200)],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),

          // Title
          const Text(
            'shader_fun example',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(width: 12),

          // Current shader subtitle
          Flexible(
            child: Text(
              '•  $projectName',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
              ),
            ),
          ),

          const SizedBox(width: 40),

          // New button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF383846)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              backgroundColor: const Color(0xFF202028),
            ),
            icon: const Icon(Icons.add, size: 16, color: Color(0xFFFFCC00)),
            label: const Text('New', style: TextStyle(fontSize: 13)),
            onPressed: onNew,
          ),

          const SizedBox(width: 40),

          // Load button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF383846)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              backgroundColor: const Color(0xFF202028),
            ),
            icon: const Icon(
              Icons.folder_open,
              size: 16,
              color: Color(0xFF00E5FF),
            ),
            label: const Text('Load', style: TextStyle(fontSize: 13)),
            onPressed: onLoad,
          ),

          const SizedBox(width: 10),

          // Save button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 201, 67, 0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            icon: const Icon(Icons.save, size: 16),
            label: const Text(
              'Save',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}
