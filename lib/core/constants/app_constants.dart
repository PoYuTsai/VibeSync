// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const appName = 'VibeSync';
  static const appVersion = '1.0.0';

  // Enthusiasm Levels
  static const coldMax = 30;
  static const warmMax = 60;
  static const hotMax = 80;
  // veryHot: 81-100

  // Golden Rule
  static const goldenRuleMultiplier = 1.8;

  // Subscription Tiers (訊息制)
  static const freeMonthlyLimit = 30;
  static const starterMonthlyLimit = 300;
  static const essentialMonthlyLimit = 1000;

  // Daily Limits (每日上限)
  static const freeDailyLimit = 15;
  static const starterDailyLimit = 50;
  static const essentialDailyLimit = 150;

  // Conversation Limits (對話數量)
  static const freeConversationLimit = 3;
  static const starterConversationLimit = 15;
  static const essentialConversationLimit = 50;

  // Memory Limits (對話記憶輪數)
  static const freeMemoryRounds = 5;
  static const paidMemoryRounds = 15;

  // Message Calculation (訊息計算)
  static const maxCharsPerMessage = 200; // 單則上限 200 字
  static const maxTotalChars = 5000; // 單次分析上限 5000 字

  // Local Storage
  static const conversationsBox = 'conversations';
  static const settingsBox = 'settings';
  static const usageBox = 'usage';
}
