String? buildAnalysisUsageChargeToast(
  dynamic usage, {
  String actionLabel = '分析',
}) {
  if (usage is! Map || usage['isTestAccount'] == true) {
    return null;
  }
  final messagesUsed = usage['messagesUsed'];
  if (messagesUsed is! num || messagesUsed <= 0) {
    return null;
  }
  return '本次$actionLabel使用 ${messagesUsed.round()} 則';
}
