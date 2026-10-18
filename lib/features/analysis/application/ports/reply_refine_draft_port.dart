/// 微調稿 durable 暫存的窄 port（先存得回來、才清付費身分）。
library;

class ReplyRefineDraftSnapshot {
  final String refinedText;
  final String? requestId;

  const ReplyRefineDraftSnapshot({
    required this.refinedText,
    this.requestId,
  });
}

/// [scope]＝草稿分區：一般微調是 null，v3 任務卡帶卡片規格（兩邊的稿不能互相預選）。
abstract class ReplyRefineDraftPort {
  Future<ReplyRefineDraftSnapshot?> loadFor({
    required String ownerUserId,
    required String originText,
    String? scope,
  });

  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
    String? scope,
  });
}
