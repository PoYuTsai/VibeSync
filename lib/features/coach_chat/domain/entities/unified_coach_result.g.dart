// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unified_coach_result.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UnifiedCoachResultAdapter extends TypeAdapter<UnifiedCoachResult> {
  @override
  final typeId = 26;

  @override
  UnifiedCoachResult read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UnifiedCoachResult(
      id: fields[0] as String,
      conversationId: fields[1] as String?,
      partnerId: fields[2] as String?,
      question: fields[3] as String,
      mode: fields[4] as String,
      headline: fields[5] as String,
      answer: fields[6] as String,
      userState: fields[7] as String,
      nextStep: fields[8] as String,
      suggestedLine: fields[9] as String?,
      boundaryReminder: fields[10] as String,
      needsReflection: fields[11] as bool,
      reflectionQuestion: fields[12] as String?,
      generatedAt: fields[13] as DateTime,
      provider: fields[14] as String,
      modelUsed: fields[15] as String,
      responseType: fields[16] == null ? 'coachAnswer' : fields[16] as String,
      sessionId: fields[17] as String?,
      userTruth: fields[18] as String?,
      rewriteDecision: fields[19] as String?,
      rewriteReason: fields[20] as String?,
      costDeducted: fields[21] == null ? 1 : (fields[21] as num).toInt(),
      frictionType: fields[22] == null ? 'unclearIntent' : fields[22] as String,
      earlierSummary: fields[23] as String?,
      earlierResultCount: fields[24] == null ? 0 : (fields[24] as num).toInt(),
      scopeType: fields[25] as String,
      scopeId: fields[26] as String,
      lifecyclePhase: fields[27] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UnifiedCoachResult obj) {
    writer
      ..writeByte(28)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.partnerId)
      ..writeByte(3)
      ..write(obj.question)
      ..writeByte(4)
      ..write(obj.mode)
      ..writeByte(5)
      ..write(obj.headline)
      ..writeByte(6)
      ..write(obj.answer)
      ..writeByte(7)
      ..write(obj.userState)
      ..writeByte(8)
      ..write(obj.nextStep)
      ..writeByte(9)
      ..write(obj.suggestedLine)
      ..writeByte(10)
      ..write(obj.boundaryReminder)
      ..writeByte(11)
      ..write(obj.needsReflection)
      ..writeByte(12)
      ..write(obj.reflectionQuestion)
      ..writeByte(13)
      ..write(obj.generatedAt)
      ..writeByte(14)
      ..write(obj.provider)
      ..writeByte(15)
      ..write(obj.modelUsed)
      ..writeByte(16)
      ..write(obj.responseType)
      ..writeByte(17)
      ..write(obj.sessionId)
      ..writeByte(18)
      ..write(obj.userTruth)
      ..writeByte(19)
      ..write(obj.rewriteDecision)
      ..writeByte(20)
      ..write(obj.rewriteReason)
      ..writeByte(21)
      ..write(obj.costDeducted)
      ..writeByte(22)
      ..write(obj.frictionType)
      ..writeByte(23)
      ..write(obj.earlierSummary)
      ..writeByte(24)
      ..write(obj.earlierResultCount)
      ..writeByte(25)
      ..write(obj.scopeType)
      ..writeByte(26)
      ..write(obj.scopeId)
      ..writeByte(27)
      ..write(obj.lifecyclePhase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedCoachResultAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
