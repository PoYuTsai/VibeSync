import 'package:hive_ce/hive_ce.dart';

part 'practice_message.g.dart';

/// AI 實戰練習室的一則訊息。本地加密保存，不寫 Supabase、不綁真實對象。
@HiveType(typeId: 22)
class PracticeMessage {
  /// 'user'（學員）或 'ai'（模擬對象女生）。
  @HiveField(0)
  final String role;

  @HiveField(1)
  final String text;

  @HiveField(2)
  final String? mood;

  @HiveField(3)
  final String? innerThought;

  /// WP4 時間戳：訊息加進列表時蓋的手機本地時間（server 不回時間）。
  /// 舊 Hive 資料沒有這格 → null → 不顯示。
  @HiveField(4)
  final DateTime? sentAt;

  const PracticeMessage({
    required this.role,
    required this.text,
    this.mood,
    this.innerThought,
    this.sentAt,
  });

  bool get isFromMe => role == 'user';
}
