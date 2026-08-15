import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/theme/app_colors.dart';
import '../services/image_compress_service.dart';
import '../services/screenshot_preflight_service.dart';
import 'glassmorphic_container.dart';
import 'pressable_scale.dart';

typedef ImagePickerFileSelector = Future<List<XFile>> Function({
  required bool allowMultiple,
  required int limit,
});

/// 選圖磚上的品牌漸層弧環（約 300°，缺口朝下）。
class _GradientArcRingPainter extends CustomPainter {
  const _GradientArcRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const startAngle = 2.0; // 缺口朝左下，視覺重心在右上
    const sweepAngle = 5.4; // ~309°
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [AppColors.ctaStart, AppColors.primary],
      ).createShader(rect);
    canvas.drawArc(
      rect.deflate(1.5),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientArcRingPainter oldDelegate) => false;
}

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
  final Color? helperTextColor;
  final bool allowMultiSelect;
  final ImagePickerFileSelector? fileSelector;
  final Color? surfaceColor;
  final Color? surfaceBorderColor;
  final Color? accentColor;

  /// 關掉內建說明文字（外層版型自帶「截圖小提醒」時用）。
  final bool showHelperText;

  /// 選圖磚與縮圖的邊長。
  final double tileSize;

  const ImagePickerWidget({
    super.key,
    this.maxImages = 3,
    required this.onImagesChanged,
    this.onMetricsChanged,
    this.externalImages,
    this.helperTextColor,
    this.allowMultiSelect = false,
    this.fileSelector,
    this.surfaceColor,
    this.surfaceBorderColor,
    this.accentColor,
    this.showHelperText = true,
    this.tileSize = 70,
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
      _showError('最多只能上傳 ${widget.maxImages} 張截圖。');
      return;
    }

    try {
      final remaining = widget.maxImages - _images.length;
      final files = await _selectFiles(remaining);
      if (files.isEmpty) {
        return;
      }

      for (final file in files.take(remaining)) {
        await _processImage(await file.readAsBytes(), file.mimeType);
      }
    } catch (_) {
      _showError('選取圖片失敗，請稍後再試。');
    }
  }

  Future<List<XFile>> _selectFiles(int limit) async {
    final injected = widget.fileSelector;
    if (injected != null) {
      return injected(
        allowMultiple: widget.allowMultiSelect,
        limit: limit,
      );
    }

    if (widget.allowMultiSelect) {
      return _picker.pickMultiImage(limit: limit);
    }

    final file = await _picker.pickImage(source: ImageSource.gallery);
    return file == null ? const <XFile>[] : <XFile>[file];
  }

  Future<void> _pasteFromClipboard() async {
    if (!kIsWeb) {
      _showError('目前只有網頁版支援從剪貼簿貼上圖片。');
      return;
    }

    if (_images.length >= widget.maxImages) {
      _showError('最多只能上傳 ${widget.maxImages} 張截圖。');
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null) {
        _showError('剪貼簿裡目前沒有圖片。');
        return;
      }

      await _processImage(imageBytes, 'image/png');
    } catch (_) {
      _showError('貼上圖片失敗，請稍後再試。');
    }
  }

  Future<void> _processImage(Uint8List bytes, String? mimeType) async {
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('目前只支援 JPEG、PNG、WebP、HEIC 截圖。');
      return;
    }

    final preflight = ScreenshotPreflightService.inspect(bytes);
    if (preflight.isRejected) {
      _showError(preflight.message ?? '這張圖片暫時不適合做聊天截圖辨識。');
      return;
    }

    if (preflight.isWarning) {
      _showInfo(preflight.message ?? '這張截圖可能辨識較不穩，請先確認內容。');
    }

    setState(() => _isProcessing = true);
    final compressed = await ImageCompressService.compressImage(bytes);
    if (mounted) {
      setState(() => _isProcessing = false);
    }

    if (compressed == null) {
      _showError('圖片壓縮失敗，請換一張截圖再試。');
      return;
    }

    if (compressed.length > ImageCompressService.maxSizeBytes) {
      _showError('這張截圖內容太複雜（例如多張照片拼貼），請只截自介文字段落再試。');
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
    widget.onMetricsChanged?.call(
      List<SelectedImageMetrics>.from(_imageMetrics),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final helperTextColor =
        widget.helperTextColor ?? AppColors.onBackgroundSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHelperText && _images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每張盡量保留 15 則內，辨識會更穩。',
                  style: TextStyle(
                    fontSize: 12,
                    color: helperTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '如果有 LINE 回覆框，請把引用和主訊息一起截進來。',
                  style: TextStyle(
                    fontSize: 12,
                    color: helperTextColor,
                  ),
                ),
              ],
            ),
          ),
        if (widget.showHelperText && _images.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '請上傳聊天畫面，盡量保留標題列、訊息泡泡和前後文。',
              style: TextStyle(
                fontSize: 12,
                color: helperTextColor,
              ),
            ),
          ),
        SizedBox(
          height: widget.tileSize + 10,
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
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accentColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '壓縮中',
                        style: TextStyle(
                          fontSize: 12,
                          color: helperTextColor,
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
            width: widget.tileSize,
            height: widget.tileSize,
            borderRadius: 12,
            padding: EdgeInsets.zero,
            color: widget.surfaceColor,
            borderColor: widget.surfaceBorderColor,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                width: widget.tileSize,
                height: widget.tileSize,
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
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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
    // 對標示意稿（2026-08-14）：深色磚＋品牌漸層弧環繞著加圖 icon。
    final iconColor = widget.accentColor ?? Colors.white.withValues(alpha: 0.9);
    final ringDiameter = widget.tileSize * 0.52;
    // 點擊感對齊首頁功能入口（home_feature_entries）：PressableScale 縮放
    // ＋透明 Material 上的 InkWell 白色 highlight。
    return PressableScale(
      child: Container(
        width: widget.tileSize,
        height: widget.tileSize,
        decoration: BoxDecoration(
          color: widget.surfaceColor ?? Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.surfaceBorderColor ??
                Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _pickImage,
            onLongPress: kIsWeb ? _pasteFromClipboard : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: ringDiameter,
                  height: ringDiameter,
                  child: CustomPaint(
                    painter: const _GradientArcRingPainter(),
                    child: Center(
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: iconColor,
                        size: ringDiameter * 0.52,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.allowMultiSelect ? '多選' : '選圖',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
