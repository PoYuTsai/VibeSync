// lib/features/analysis/domain/entities/game_stage.dart

/// GAME 五階段流程
enum GameStage {
  opening, // 打開 - 破冰
  premise, // 前提 - 進入男女框架
  qualification, // 評估 - 她證明自己配得上你
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
        return '初識';
      case premise:
        return '熟悉中';
      case qualification:
        return '深入了解';
      case narrative:
        return '分享故事';
      case close:
        return '見面邀約';
    }
  }

  String get description {
    switch (this) {
      case opening:
        return '剛開始聊天';
      case premise:
        return '慢慢熟悉對方';
      case qualification:
        return '彼此更了解中';
      case narrative:
        return '交換故事和想法';
      case close:
        return '可以約出來了';
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

/// GAME 階段狀態
enum GameStageStatus {
  normal, // 正常進行
  stuckFriend, // 卡在朋友框
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
