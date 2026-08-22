// lib/features/analysis/domain/entities/game_stage.dart

/// 對話五階段流程
enum GameStage {
  opening, // 打開 - 破冰
  premise, // 升溫 - 建立曖昧張力
  qualification, // 評估 - 互相觀察與篩選
  narrative, // 敘事 - 個性樣本、說故事
  close; // 收尾 - 模糊邀約 → 確立邀約

  static GameStage fromString(String value) {
    return GameStage.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GameStage.opening,
    );
  }

  /// 嚴格解析：只接受五個合法 enum 名（trim 後精確比對）。
  /// 缺值、未知值、中文標籤一律回 null，不得默認成 opening——
  /// 「問號 vs 冰塊」的判讀靠這條守住（見 docs/plans 對象卡互動階段閉環）。
  static GameStage? tryFromString(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final stage in GameStage.values) {
      if (stage.name == normalized) return stage;
    }
    return null;
  }

  String get label {
    switch (this) {
      case opening:
        return '破冰階段';
      case premise:
        return '建立男女感';
      case qualification:
        return '互相評估';
      case narrative:
        return '展現個人魅力';
      case close:
        return '準備邀約';
    }
  }

  String get description {
    switch (this) {
      case opening:
        return '你們還在破冰，先讓對話自然流動';
      case premise:
        return '開始有男女氛圍，可以加點張力';
      case qualification:
        return '她在觀察你，你也判斷是否同頻';
      case narrative:
        return '分享故事展現魅力，讓她更了解你';
      case close:
        return '時機對了，可以邀她出來見面';
    }
  }
}

/// 對話階段狀態
enum GameStageStatus {
  normal, // 正常進行
  stuckFriend, // 偏向朋友感
  canAdvance, // 可以推進
  shouldRetreat; // 應該退回

  static GameStageStatus fromString(String value) {
    return GameStageStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GameStageStatus.normal,
    );
  }

  String get label {
    switch (this) {
      case normal:
        return '維持節奏';
      case stuckFriend:
        return '互動偏平';
      case canAdvance:
        return '可以推進';
      case shouldRetreat:
        return '放慢一點';
    }
  }
}
