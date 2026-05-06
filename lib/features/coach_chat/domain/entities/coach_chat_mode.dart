enum CoachChatMode {
  clarifyIntent,
  stateCalibration,
  boundaryRisk,
  moveForward,
  replyCraft,
  stopSignal,
}

extension CoachChatModeX on CoachChatMode {
  static CoachChatMode fromWire(String value) {
    return CoachChatMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => CoachChatMode.clarifyIntent,
    );
  }

  String get label {
    switch (this) {
      case CoachChatMode.clarifyIntent:
        return '先問清楚';
      case CoachChatMode.stateCalibration:
        return '穩住狀態';
      case CoachChatMode.boundaryRisk:
        return '看清邊界';
      case CoachChatMode.moveForward:
        return '往前推進';
      case CoachChatMode.replyCraft:
        return '幫你接話';
      case CoachChatMode.stopSignal:
        return '先收一下';
    }
  }
}
