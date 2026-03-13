import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import '../services/image_compress_service.dart';
import '../../core/theme/app_colors.dart';
import 'glassmorphic_container.dart';

/// 圖片選擇元件
/// 支援從相簿選圖、剪貼簿貼上，自動壓縮
class ImagePickerWidget extends StatefulWidget {
  final int maxImages;
  final Function(List<Uint8List>) onImagesChanged;

  const ImagePickerWidget({
    super.key,
    this.maxImages = 3,
    required this.onImagesChanged,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final List<Uint8List> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  Future<void> _pickImage() async {
    if (_images.length >= widget.maxImages) {
      _showError('最多上傳 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      await _processImage(await file.readAsBytes(), file.mimeType);
    } catch (e) {
      _showError('選取圖片失敗');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (!kIsWeb) {
      _showError('剪貼簿貼上僅支援網頁版');
      return;
    }

    if (_images.length >= widget.maxImages) {
      _showError('最多上傳 ${widget.maxImages} 張截圖');
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null) {
        _showError('剪貼簿中沒有圖片');
        return;
      }
      await _processImage(imageBytes, 'image/png');
    } catch (e) {
      _showError('貼上圖片失敗');
    }
  }

  Future<void> _processImage(Uint8List bytes, String? mimeType) async {
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('不支援的圖片格式');
      return;
    }

    setState(() => _isProcessing = true);

    final compressed = await ImageCompressService.compressImage(bytes);

    setState(() => _isProcessing = false);

    if (compressed == null) {
      _showError('圖片處理失敗');
      return;
    }

    if (compressed.length > 500 * 1024) {
      _showError('圖片太大，請選擇較小的截圖');
      return;
    }

    setState(() {
      _images.add(compressed);
    });
    widget.onImagesChanged(_images);
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
    widget.onImagesChanged(_images);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 提示文字
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '請按對話時間順序上傳，先傳較早的',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.unselectedText,
              ),
            ),
          ),

        // 圖片預覽區
        SizedBox(
          height: 80,
          child: Row(
            children: [
              // 已選圖片
              ..._images.asMap().entries.map((entry) => _buildImageThumbnail(
                    entry.value,
                    entry.key,
                  )),

              // 新增按鈕
              if (_images.length < widget.maxImages) _buildAddButton(),

              // 處理中指示器
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
          // 刪除按鈕
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
          // 順序標籤
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
