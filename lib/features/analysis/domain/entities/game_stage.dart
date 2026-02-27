// lib/features/analysis/domain/entities/game_stage.dart

/// GAME 五階段流程
enum GameStage {
  opening, // 打開 - 破冰
  premise, // 前提 - 進入男女框架
  qualification, // 評估 - 她證明自己配得上你
  narrative, // 敘事 - 個性樣本、說故事
  close; // 收尾 - 模糊邀約 → 確立邀約

  String get label {
    switch (this) {
      case opening:
        return '打開';
      case premise:
        return '前提';
      case qualification:
        return '評估';
      case narrative:
        return '敘事';
      case close:
        return '收尾';
    }
  }

  String get description {
    switch (this) {
      case opening:
        return '破冰階段';
      case premise:
        return '進入男女框架';
      case qualification:
        return '她在證明自己';
      case narrative:
        return '說故事、個性樣本';
      case close:
        return '準備邀約';
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

  String get label {
    switch (this) {
      case normal:
        return '正常進行';
      case stuckFriend:
        return '卡在朋友框';
      case canAdvance:
        return '可以推進';
      case shouldRetreat:
        return '建議退回';
    }
  }
}
