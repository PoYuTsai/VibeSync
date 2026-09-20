import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A local avatar uses the same cross-platform byte reader as the image picker.
/// Web cannot reopen a native filesystem path; missing/stale paths use fallback.
class LocalAvatar extends StatefulWidget {
  const LocalAvatar({super.key, required this.path, required this.fallback});

  final String? path;
  final Widget fallback;

  @override
  State<LocalAvatar> createState() => _LocalAvatarState();
}

class _LocalAvatarState extends State<LocalAvatar> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _read(widget.path);
  }

  @override
  void didUpdateWidget(LocalAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _bytes = _read(widget.path);
  }

  Future<Uint8List?> _read(String? path) async {
    if (path == null || path.isEmpty) return null;
    final scheme = Uri.tryParse(path)?.scheme;
    // avatarPath is local data, never a remote download or upload.
    if (scheme == 'http' || scheme == 'https' || scheme == 'ftp') return null;
    if (kIsWeb && scheme != 'blob' && !path.startsWith('data:image/')) {
      return null;
    }
    try {
      return await XFile(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        key: ValueKey(widget.path),
        future: _bytes,
        builder: (context, snapshot) {
          final bytes = snapshot.connectionState == ConnectionState.done
              ? snapshot.data
              : null;
          return bytes == null || bytes.isEmpty
              ? widget.fallback
              : Image.memory(bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => widget.fallback);
        },
      );
}
