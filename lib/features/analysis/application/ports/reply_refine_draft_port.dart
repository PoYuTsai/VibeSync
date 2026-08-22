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

abstract class ReplyRefineDraftPort {
  Future<ReplyRefineDraftSnapshot?> loadFor({
    required String ownerUserId,
    required String originText,
  });

  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
  });
}
