import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/theme/app_colors.dart';
import '../services/image_compress_service.dart';
import 'glassmorphic_container.dart';

class ImagePickerWidget extends StatefulWidget {
  final int maxImages;
  final ValueChanged<List<Uint8List>> onImagesChanged;
  final List<Uint8List>? externalImages;

  const ImagePickerWidget({
    super.key,
    this.maxImages = 3,
    required this.onImagesChanged,
    this.externalImages,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final ImagePicker _picker = ImagePicker();

  List<Uint8List> _images = [];
  bool _isProcessing = false;

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.externalImages != null &&
        widget.externalImages!.isEmpty &&
        _images.isNotEmpty) {
      setState(() {
        _images = [];
      });
    }
  }

  Future<void> _pickImage() async {
    if (_images.length >= widget.maxImages) {
      _showError('最多只能選擇 ${widget.maxImages} 張圖片。');
      return;
    }

    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      await _processImage(await file.readAsBytes(), file.mimeType);
    } catch (_) {
      _showError('選取圖片失敗，請再試一次。');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (!kIsWeb) {
      _showError('只有網頁版支援從剪貼簿貼上圖片。');
      return;
    }

    if (_images.length >= widget.maxImages) {
      _showError('最多只能選擇 ${widget.maxImages} 張圖片。');
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null) {
        _showError('剪貼簿裡沒有圖片。');
        return;
      }

      await _processImage(imageBytes, 'image/png');
    } catch (_) {
      _showError('貼上圖片失敗，請再試一次。');
    }
  }

  Future<void> _processImage(Uint8List bytes, String? mimeType) async {
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('這個圖片格式目前不支援。');
      return;
    }

    setState(() => _isProcessing = true);
    final compressed = await ImageCompressService.compressImage(bytes);
    if (mounted) {
      setState(() => _isProcessing = false);
    }

    if (compressed == null) {
      _showError('圖片處理失敗，請換一張試試。');
      return;
    }

    if (compressed.length > ImageCompressService.maxSizeBytes) {
      _showError('圖片仍然過大，請改用內容更精簡的截圖。');
      return;
    }

    setState(() {
      _images.add(compressed);
    });
    widget.onImagesChanged(List<Uint8List>.from(_images));
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
    widget.onImagesChanged(List<Uint8List>.from(_images));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '建議每張截圖小於 15 則訊息，辨識會更快也更準。',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.unselectedText,
              ),
            ),
          ),
        SizedBox(
          height: 80,
          child: Row(
            children: [
              ..._images.asMap().entries.map(
                    (entry) => _buildImageThumbnail(entry.value, entry.key),
                  ),
              if (_images.length < widget.maxImages) _buildAddButton(),
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageThumbnail(Uint8List imageBytes, int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassmorphicContainer(
            width: 70,
            height: 70,
            borderRadius: 12,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                width: 70,
                height: 70,
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _pickImage,
      onLongPress: kIsWeb ? _pasteFromClipboard : null,
      child: GlassmorphicContainer(
        width: 70,
        height: 70,
        borderRadius: 12,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.unselectedText,
              size: 28,
            ),
            const SizedBox(height: 2),
            Text(
              '截圖',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.unselectedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
