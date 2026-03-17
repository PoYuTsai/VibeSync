import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/theme/app_colors.dart';
import '../services/image_compress_service.dart';
import 'glassmorphic_container.dart';

class SelectedImageMetrics {
  final int originalBytes;
  final int compressedBytes;

  const SelectedImageMetrics({
    required this.originalBytes,
    required this.compressedBytes,
  });
}

class ImagePickerWidget extends StatefulWidget {
  final int maxImages;
  final ValueChanged<List<Uint8List>> onImagesChanged;
  final ValueChanged<List<SelectedImageMetrics>>? onMetricsChanged;
  final List<Uint8List>? externalImages;

  const ImagePickerWidget({
    super.key,
    this.maxImages = 3,
    required this.onImagesChanged,
    this.onMetricsChanged,
    this.externalImages,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final ImagePicker _picker = ImagePicker();

  List<Uint8List> _images = [];
  List<SelectedImageMetrics> _imageMetrics = [];
  bool _isProcessing = false;

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.externalImages != null &&
        widget.externalImages!.isEmpty &&
        _images.isNotEmpty) {
      setState(() {
        _images = [];
        _imageMetrics = [];
      });
      _emitChanges();
    }
  }

  Future<void> _pickImage() async {
    if (_images.length >= widget.maxImages) {
      _showError('最多只能選擇 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }

      await _processImage(await file.readAsBytes(), file.mimeType);
    } catch (_) {
      _showError('選取圖片失敗，請稍後再試');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (!kIsWeb) {
      _showError('只有網頁版支援從剪貼簿貼上圖片');
      return;
    }

    if (_images.length >= widget.maxImages) {
      _showError('最多只能選擇 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null) {
        _showError('剪貼簿裡沒有圖片');
        return;
      }

      await _processImage(imageBytes, 'image/png');
    } catch (_) {
      _showError('貼上圖片失敗，請稍後再試');
    }
  }

  Future<void> _processImage(Uint8List bytes, String? mimeType) async {
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('目前只支援 JPEG、PNG、WebP 或 HEIC 截圖');
      return;
    }

    setState(() => _isProcessing = true);
    final compressed = await ImageCompressService.compressImage(bytes);
    if (mounted) {
      setState(() => _isProcessing = false);
    }

    if (compressed == null) {
      _showError('圖片壓縮失敗，請換一張截圖再試');
      return;
    }

    if (compressed.length > ImageCompressService.maxSizeBytes) {
      _showError('圖片壓縮後仍然偏大，請換一張內容更少的截圖');
      return;
    }

    setState(() {
      _images.add(compressed);
      _imageMetrics.add(
        SelectedImageMetrics(
          originalBytes: bytes.length,
          compressedBytes: compressed.length,
        ),
      );
    });
    _emitChanges();
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      if (index < _imageMetrics.length) {
        _imageMetrics.removeAt(index);
      }
    });
    _emitChanges();
  }

  void _emitChanges() {
    widget.onImagesChanged(List<Uint8List>.from(_images));
    widget.onMetricsChanged
        ?.call(List<SelectedImageMetrics>.from(_imageMetrics));
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '建議每張截圖小於 15 則訊息，辨識會更穩定也更快。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.unselectedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '如果是 LINE 的「回覆」功能，請把引用框和主訊息泡泡一起截進來，避免內容被拆錯。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.unselectedText,
                  ),
                ),
              ],
            ),
          ),
        if (_images.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '建議保留聊天標題列、完整泡泡與上下文，繁中長截圖會更容易辨識。',
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
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '壓縮中',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.unselectedText,
                        ),
                      ),
                    ],
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
              '新增',
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
