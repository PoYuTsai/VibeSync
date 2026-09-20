import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_haptics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/theme/app_colors.dart';
import '../services/image_compress_service.dart';
import '../services/screenshot_preflight_service.dart';
import 'glassmorphic_container.dart';
import 'pressable_scale.dart';
import 'brand/opener_home_components.dart';
import 'brand/opener_entry_icon.dart';

enum ImagePickerVariant { compact, openerPanel }

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
  final ImagePickerVariant variant;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  final Object? operationScope;

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
    this.variant = ImagePickerVariant.compact,
    this.enabled = true,
    this.onBusyChanged,
    this.operationScope,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final ImagePicker _picker = ImagePicker();

  List<Uint8List> _images = [];
  List<SelectedImageMetrics> _imageMetrics = [];
  bool _isProcessing = false;
  int _epoch = 0;
  String? _panelMessage;

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.externalImages ?? const <Uint8List>[]);
  }

  bool _current(int epoch) => mounted && epoch == _epoch;

  void _busy(bool value) {
    if (!mounted) return;
    setState(() {
      _isProcessing = value;
      if (value) _panelMessage = null;
    });
    widget.onBusyChanged?.call(value);
  }

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 外部狀態變了就採納（清空或整批換圖，如分析頁「重新選圖」），但
    // 一律**不回發**：didUpdateWidget 跑在父層 build 期間，回發等於
    // setState-during-build；而且變更本來就是父層發起的，它狀態已一致，
    // 非空批的 metrics 也由父層持有，回發只會用空 metrics 蓋掉它。
    final external = widget.externalImages;
    if (oldWidget.operationScope != widget.operationScope) {
      _epoch++;
      _panelMessage = null;
    }
    if (external != null && !listEquals(external, _images)) {
      _epoch++;
      setState(() {
        _images = List<Uint8List>.from(external);
        _imageMetrics = [];
        _panelMessage = null;
      });
    }
  }

  Future<void> _pickImage() async {
    if (_isProcessing || !widget.enabled) return;
    if (_images.length >= widget.maxImages) {
      _showError('最多只能上傳 ${widget.maxImages} 張截圖。');
      return;
    }

    final epoch = _epoch;
    _busy(true);
    try {
      final remaining = widget.maxImages - _images.length;
      final files = await _selectFiles(remaining);
      if (!_current(epoch) || files.isEmpty) {
        return;
      }

      var failed = 0;
      for (final file in files.take(remaining)) {
        try {
          final bytes = await file.readAsBytes();
          if (!_current(epoch)) return;
          if (!await _processImage(bytes, file.mimeType, epoch)) failed++;
        } catch (_) {
          failed++;
          if (_current(epoch)) _showError('這張圖片處理失敗，其他已加入的圖片會保留。');
        }
        if (!_current(epoch)) return;
      }
      if (failed > 0 && widget.variant == ImagePickerVariant.openerPanel) {
        _showError('有 $failed 張圖片無法加入，請換張圖片再試。');
      } else if (files.length > remaining &&
          widget.variant == ImagePickerVariant.openerPanel) {
        _showInfo('最多可加入 ${widget.maxImages} 張，已加入可用張數。');
      }
    } catch (_) {
      if (_current(epoch)) _showError('選取圖片失敗，請稍後再試。');
    } finally {
      _busy(false);
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
    if (_isProcessing || !widget.enabled) return;
    if (!kIsWeb) {
      _showError('目前只有網頁版支援從剪貼簿貼上圖片。');
      return;
    }

    if (_images.length >= widget.maxImages) {
      _showError('最多只能上傳 ${widget.maxImages} 張截圖。');
      return;
    }

    final epoch = _epoch;
    _busy(true);
    try {
      final imageBytes = await Pasteboard.image;
      if (!_current(epoch)) return;
      if (imageBytes == null) {
        _showError('剪貼簿裡目前沒有圖片。');
        return;
      }

      await _processImage(imageBytes, 'image/png', epoch);
    } catch (_) {
      if (_current(epoch)) _showError('貼上圖片失敗，請稍後再試。');
    } finally {
      _busy(false);
    }
  }

  Future<bool> _processImage(
      Uint8List bytes, String? mimeType, int epoch) async {
    if (!_current(epoch)) return false;
    if (!ImageCompressService.isSupportedFormat(mimeType)) {
      _showError('目前只支援 JPEG、PNG、WebP、HEIC 截圖。');
      return false;
    }

    final preflight = ScreenshotPreflightService.inspect(bytes);
    if (preflight.isRejected) {
      _showError(preflight.message ?? '這張圖片暫時不適合做聊天截圖辨識。');
      return false;
    }

    if (preflight.isWarning) {
      _showInfo(preflight.message ?? '這張截圖可能辨識較不穩，請先確認內容。');
    }

    final compressed = await ImageCompressService.compressImage(bytes);
    if (!_current(epoch)) return false;

    if (compressed == null) {
      _showError('圖片壓縮失敗，請換一張截圖再試。');
      return false;
    }

    if (compressed.length > ImageCompressService.maxSizeBytes) {
      _showError('這張截圖內容太複雜（例如多張照片拼貼），請只截自介文字段落再試。');
      return false;
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
    return true;
  }

  void _removeImage(int index) {
    if (_isProcessing || !widget.enabled) return;
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
    if (widget.variant == ImagePickerVariant.openerPanel) {
      setState(() => _panelMessage = message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showInfo(String message) {
    if (widget.variant == ImagePickerVariant.openerPanel) {
      setState(() => _panelMessage = message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == ImagePickerVariant.openerPanel) return _buildPanel();
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

  /// 點縮圖看全圖（2026-08-16 Eric 回饋）：配方同練習室對象照片
  /// （practice_girl_photo.dart 的全螢幕 viewer）——黑底、可捏合縮放、
  /// 點任一處或右上關閉。
  Future<void> _showFullImage(Uint8List imageBytes) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 3,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.brandInk.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          '點一下關閉',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: '關閉',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.variant == ImagePickerVariant.openerPanel
                        ? AppHaptics.onPress(
                            () => Navigator.of(dialogContext).pop())
                        : () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            child: GestureDetector(
              onTap: () {
                AppHaptics.tap();
                _showFullImage(imageBytes);
              },
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
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: AppHaptics.onPress(() => _removeImage(index)),
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
            onTap: _isProcessing || !widget.enabled ? null : _pickImage,
            onLongPress: kIsWeb && !_isProcessing && widget.enabled
                ? _pasteFromClipboard
                : null,
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

  Widget _buildPanel() {
    final disabled = _isProcessing || !widget.enabled;
    return OpenerHomePanel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_images.isEmpty)
          Semantics(
            button: true,
            enabled: !disabled,
            label: '加入她的自介或照片，最多 ${widget.maxImages} 張',
            child: InkWell(
              key: const ValueKey('opener-add-images'),
              borderRadius: BorderRadius.circular(24),
              onTap: disabled
                  ? null
                  : () {
                      AppHaptics.tap();
                      _pickImage();
                    },
              child: ExcludeSemantics(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 136),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final vertical =
                        MediaQuery.textScalerOf(context).scale(15) > 20;
                    final icon = OpenerEntryIcon(
                        kind: OpenerEntryKind.photos,
                        size: constraints.maxWidth >= 300 ? 120 : 104);
                    final copy = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('加入她的自介或照片',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Wrap(children: [
                            Text('最多 ${widget.maxImages} 張，',
                                style: OpenerHomeStyle.body),
                            const Text('讓開場更貼近她。', style: OpenerHomeStyle.body),
                          ]),
                        ]);
                    return vertical
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [icon, const SizedBox(height: 12), copy])
                        : Row(children: [
                            icon,
                            const SizedBox(width: 16),
                            Expanded(child: copy)
                          ]);
                  }),
                ),
              )),
            ),
          )
        else
          Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(builder: (context, constraints) {
                final size =
                    ((constraints.maxWidth - 16) / 3).clamp(0.0, 104.0);
                return ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 136),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final entry
                                    in _images.asMap().entries) ...[
                                  if (entry.key > 0) const SizedBox(width: 8),
                                  Container(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.16),
                                                offset: const Offset(0, 2),
                                                blurRadius: 6)
                                          ]),
                                      child: Stack(children: [
                                        Positioned.fill(
                                            child: Semantics(
                                                button: true,
                                                label:
                                                    '第 ${entry.key + 1} 張圖片，點擊查看',
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  onTap: () {
                                                    AppHaptics.tap();
                                                    _showFullImage(entry.value);
                                                  },
                                                  child: ExcludeSemantics(
                                                      child: Container(
                                                          clipBehavior:
                                                              Clip.antiAlias,
                                                          decoration: BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          18),
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .white
                                                                      .withValues(
                                                                          alpha:
                                                                              0.65))),
                                                          child: Image.memory(
                                                              entry.value,
                                                              fit: BoxFit.cover))),
                                                ))),
                                        Positioned(
                                            top: 0,
                                            right: 0,
                                            child: SizedBox(
                                                width: 44,
                                                height: 44,
                                                child: IconButton(
                                                  tooltip:
                                                      '移除第 ${entry.key + 1} 張圖片',
                                                  onPressed: AppHaptics.onPress(
                                                      disabled
                                                          ? null
                                                          : () => _removeImage(
                                                              entry.key)),
                                                  padding: EdgeInsets.zero,
                                                  icon: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration:
                                                          const BoxDecoration(
                                                              color:
                                                                  OpenerHomeStyle
                                                                      .canvas,
                                                              shape: BoxShape
                                                                  .circle),
                                                      child: const Icon(
                                                          Icons.close,
                                                          size: 16,
                                                          color: OpenerHomeStyle
                                                              .icon)),
                                                ))),
                                      ])),
                                ],
                                if (_images.length < widget.maxImages) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                      width: size,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                            width: 64,
                                            child: OutlinedButton(
                                              key: const ValueKey(
                                                  'opener-add-image-tile'),
                                              onPressed: disabled
                                                  ? null
                                                  : () {
                                                      AppHaptics.tap();
                                                      _pickImage();
                                                    },
                                              style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(64, 72),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 8,
                                                          horizontal: 4),
                                                  backgroundColor:
                                                      OpenerHomeStyle.input,
                                                  foregroundColor:
                                                      OpenerHomeStyle.secondary,
                                                  side: BorderSide(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.14)),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              18))),
                                              child: const Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.add, size: 24),
                                                    SizedBox(height: 4),
                                                    Text('加入',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: OpenerHomeStyle
                                                            .helper),
                                                  ]),
                                            )),
                                      )),
                                ],
                              ]),
                          const SizedBox(height: 8),
                          Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                  '已加入 ${_images.length}／${widget.maxImages} 張',
                                  style: OpenerHomeStyle.helper)),
                        ]));
              })),
        if (kIsWeb && _images.length < widget.maxImages)
          TextButton(
              onPressed:
                  AppHaptics.onPress(disabled ? null : _pasteFromClipboard),
              child: const Text('貼上圖片')),
        if (_isProcessing || _panelMessage != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Semantics(
                  liveRegion: true,
                  child: Text(_isProcessing ? '正在處理圖片…' : _panelMessage!,
                      style: OpenerHomeStyle.helper))),
      ]),
    );
  }
}
