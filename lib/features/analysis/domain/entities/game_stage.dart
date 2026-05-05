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

  String get emoji {
    switch (this) {
      case opening:
        return '👋';
      case premise:
        return '💫';
      case qualification:
        return '✨';
      case narrative:
        return '📖';
      case close:
        return '🎯';
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
        return '進展順利';
      case stuckFriend:
        return '偏向朋友';
      case canAdvance:
        return '可以更進一步';
      case shouldRetreat:
        return '放慢節奏';
    }
  }
}
