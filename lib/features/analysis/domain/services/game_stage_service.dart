// lib/features/analysis/domain/services/game_stage_service.dart
import 'package:flutter/material.dart';
import '../entities/game_stage.dart';

/// GAME 階段分析服務
/// 根據 AI 回傳的分析結果，提供階段相關的 UI 資訊
class GameStageService {
  /// 取得階段顯示名稱 (含英文)
  String getStageName(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 'Opening 打開';
      case GameStage.premise:
        return 'Premise 前提';
      case GameStage.qualification:
        return 'Qualification 評估';
      case GameStage.narrative:
        return 'Narrative 敘事';
      case GameStage.close:
        return 'Close 收尾';
    }
  }

  /// 取得階段詳細描述
  String getStageDescription(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '破冰階段 - 建立初步連結';
      case GameStage.premise:
        return '前提階段 - 進入男女框架，建立張力';
      case GameStage.qualification:
        return '評估階段 - 讓她證明自己配得上你';
      case GameStage.narrative:
        return '敘事階段 - 分享個性樣本、說故事';
      case GameStage.close:
        return '收尾階段 - 從模糊邀約到確立邀約';
    }
  }

  /// 取得階段進度 (0.0 - 1.0)
  double getStageProgress(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 0.2;
      case GameStage.premise:
        return 0.4;
      case GameStage.qualification:
        return 0.6;
      case GameStage.narrative:
        return 0.8;
      case GameStage.close:
        return 1.0;
    }
  }

  /// 取得階段顏色 (Hex)
  String getStageColorHex(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '#4CAF50'; // 綠色
      case GameStage.premise:
        return '#2196F3'; // 藍色
      case GameStage.qualification:
        return '#FF9800'; // 橘色
      case GameStage.narrative:
        return '#9C27B0'; // 紫色
      case GameStage.close:
        return '#E91E63'; // 粉色
    }
  }

  /// 取得階段顏色 (Color)
  Color getStageColor(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return const Color(0xFF4CAF50); // 綠色
      case GameStage.premise:
        return const Color(0xFF2196F3); // 藍色
      case GameStage.qualification:
        return const Color(0xFFFF9800); // 橘色
      case GameStage.narrative:
        return const Color(0xFF9C27B0); // 紫色
      case GameStage.close:
        return const Color(0xFFE91E63); // 粉色
    }
  }

  /// 根據狀態取得建議行動
  String getStatusAdvice(GameStageStatus status) {
    switch (status) {
      case GameStageStatus.normal:
        return '繼續目前節奏';
      case GameStageStatus.stuckFriend:
        return '需要建立曖昧張力，跳出朋友框架';
      case GameStageStatus.canAdvance:
        return '時機成熟，可以推進到下一階段';
      case GameStageStatus.shouldRetreat:
        return '放慢腳步，回到前一階段重新建立連結';
    }
  }

  /// 根據狀態取得圖示
  IconData getStatusIcon(GameStageStatus status) {
    switch (status) {
      case GameStageStatus.normal:
        return Icons.check_circle_outline;
      case GameStageStatus.stuckFriend:
        return Icons.warning_amber_outlined;
      case GameStageStatus.canAdvance:
        return Icons.arrow_forward;
      case GameStageStatus.shouldRetreat:
        return Icons.arrow_back;
    }
  }

  /// 判斷是否應該建議「已讀不回」
  bool shouldSuggestNoReply(int enthusiasmScore, GameStage stage) {
    // 熱度 < 30 且還在 Opening 階段，機會渺茫
    return enthusiasmScore < 30 && stage == GameStage.opening;
  }

  /// 判斷是否應該建議「放棄這段對話」
  bool shouldSuggestGiveUp(int enthusiasmScore, GameStage stage, int roundCount) {
    // 熱度 < 20，且已經超過 10 輪，對方興趣極低
    return enthusiasmScore < 20 && roundCount > 10;
  }

  /// 取得下一階段
  GameStage? getNextStage(GameStage currentStage) {
    final index = currentStage.index;
    if (index < GameStage.values.length - 1) {
      return GameStage.values[index + 1];
    }
    return null; // 已在最後階段
  }

  /// 取得前一階段
  GameStage? getPreviousStage(GameStage currentStage) {
    final index = currentStage.index;
    if (index > 0) {
      return GameStage.values[index - 1];
    }
    return null; // 已在第一階段
  }

  /// 取得階段簡稱 (單字母)
  String getShortName(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 'O';
      case GameStage.premise:
        return 'P';
      case GameStage.qualification:
        return 'Q';
      case GameStage.narrative:
        return 'N';
      case GameStage.close:
        return 'C';
    }
  }
}
