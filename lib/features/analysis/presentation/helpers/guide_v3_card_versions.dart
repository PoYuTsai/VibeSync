/// 結果頁上 v3 任務卡的版本（key＝runId:slot，只在這個畫面裡）：
/// - 他自己改的（填空、改寫）：卡上顯示「已改成你的」，不再提醒編的細節。
/// - 「再調一下」選定的版本：模型寫的字，編的細節提醒照留、空格一樣要先填，
///   複製記成那一輪微調的獨立事件（Eric 2026-10-18：不放進自己改的那一份）。
///
/// 顯示：自己改的 > 再調的 > 伺服器原樣。選定再調的版本時，之前自己改的就不要了
/// （再調的原句就是那一份）；之後再自己填空或改字，再調的那一輪仍是這張卡複製
/// 紀錄的來源。
library;

/// 「再調一下」選定的版本。
class GuideV3RefinedVersion {
  const GuideV3RefinedVersion({required this.messages, this.requestId});

  /// 面板帶回來的字是一則一行（伺服器定稿後用換行接），拆回每一則。
  factory GuideV3RefinedVersion.fromAdoptedText(
    String text, {
    String? requestId,
  }) {
    return GuideV3RefinedVersion(
      messages: List.unmodifiable(
        text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      ),
      requestId: requestId,
    );
  }

  final List<String> messages;

  /// 產生這一版的那一輪微調（複製紀錄的冪等鍵）；沒有就不記。
  final String? requestId;
}

class GuideV3CardVersions {
  final Map<String, List<String>> _edited = {};
  final Map<String, GuideV3RefinedVersion> _refined = {};

  List<String>? editedFor(String key) => _edited[key];

  GuideV3RefinedVersion? refinedFor(String key) => _refined[key];

  /// 卡上現在顯示的那一份（填空、再調、複製都從這一份開始）。
  List<String> displayed(String key, List<String> original) =>
      _edited[key] ?? _refined[key]?.messages ?? original;

  void saveEdit(String key, List<String> messages) {
    _edited[key] = List.unmodifiable(messages);
  }

  void adoptRefined(String key, GuideV3RefinedVersion version) {
    _refined[key] = version;
    _edited.remove(key);
  }

  /// 新的一輪分析開始時清掉（key 帶 runId，舊的也不會被拿錯）。
  void clear() {
    _edited.clear();
    _refined.clear();
  }
}
