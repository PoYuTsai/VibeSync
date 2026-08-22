/// data 端 adapter：以既有 OcrRecognitionCacheService（靜態、加密
/// settings box）實作 application 的 OcrRecognitionCachePort。
library;

import 'dart:typed_data';

import '../../application/ports/screenshot_recognition_ports.dart';
import '../../domain/entities/analysis_models.dart';
import 'ocr_recognition_cache_service.dart';

class OcrRecognitionCacheAdapter implements OcrRecognitionCachePort {
  const OcrRecognitionCacheAdapter();

  @override
  Future<void> invalidate(List<Uint8List> images, String conversationId) =>
      OcrRecognitionCacheService.invalidate(images, conversationId);

  @override
  Future<RecognizedConversation?> read(
    List<Uint8List> images,
    String conversationId,
  ) async {
    final cached = await OcrRecognitionCacheService.read(
      images,
      conversationId,
    );
    return cached?.recognizedConversation;
  }

  @override
  Future<void> write({
    required List<Uint8List> images,
    required RecognizedConversation recognizedConversation,
    required String conversationId,
  }) {
    return OcrRecognitionCacheService.write(
      images: images,
      recognizedConversation: recognizedConversation,
      conversationId: conversationId,
    );
  }
}
