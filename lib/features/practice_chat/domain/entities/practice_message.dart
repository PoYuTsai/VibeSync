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

  const PracticeMessage({
    required this.role,
    required this.text,
    this.mood,
    this.innerThought,
  });

  bool get isFromMe => role == 'user';
}
