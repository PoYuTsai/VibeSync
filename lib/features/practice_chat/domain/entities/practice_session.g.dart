// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PracticeSessionAdapter extends TypeAdapter<PracticeSession> {
  @override
  final typeId = 23;

  @override
  PracticeSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PracticeSession(
      id: fields[0] as String,
      createdAt: fields[1] as DateTime,
      messages: fields[2] == null
          ? const []
          : (fields[2] as List).cast<PracticeMessage>(),
      aiReplyCount: fields[3] == null ? 0 : (fields[3] as num).toInt(),
      debriefSummary: fields[4] as String?,
      debriefStrengths:
          fields[5] == null ? const [] : (fields[5] as List).cast<String>(),
      debriefWatchouts:
          fields[6] == null ? const [] : (fields[6] as List).cast<String>(),
      debriefSuggestedLine: fields[7] as String?,
      debriefVibe: fields[8] as String?,
      personaId: fields[9] as String?,
      personaLabel: fields[10] as String?,
      difficulty: fields[11] as String?,
      difficultyLabel: fields[12] as String?,
      visiblePracticeThreadId: fields[13] as String?,
      roundIndex: (fields[14] as num?)?.toInt(),
      profileId: fields[15] as String?,
      practiceMode: fields[16] as String?,
      temperatureScore: (fields[17] as num?)?.toInt(),
      hintUsedCount: (fields[18] as num?)?.toInt(),
      familiarityScore: (fields[19] as num?)?.toInt(),
      relationshipStageLabel: fields[20] as String?,
      debriefDateChance: fields[21] as String?,
      debriefDateChanceReason: fields[22] as String?,
      debriefNextInviteMove: fields[23] as String?,
      debriefGamePhaseReached: fields[24] as String?,
      debriefGameMissedVariable: fields[25] as String?,
      debriefGameFailureState: fields[26] as String?,
      debriefGameNextFirstLine: fields[27] as String?,
      debriefGameInviteDirection: fields[28] as String?,
      debriefQualitySchemaVersion: fields[29] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PracticeSession obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.messages)
      ..writeByte(3)
      ..write(obj.aiReplyCount)
      ..writeByte(4)
      ..write(obj.debriefSummary)
      ..writeByte(5)
      ..write(obj.debriefStrengths)
      ..writeByte(6)
      ..write(obj.debriefWatchouts)
      ..writeByte(7)
      ..write(obj.debriefSuggestedLine)
      ..writeByte(8)
      ..write(obj.debriefVibe)
      ..writeByte(9)
      ..write(obj.personaId)
      ..writeByte(10)
      ..write(obj.personaLabel)
      ..writeByte(11)
      ..write(obj.difficulty)
      ..writeByte(12)
      ..write(obj.difficultyLabel)
      ..writeByte(13)
      ..write(obj.visiblePracticeThreadId)
      ..writeByte(14)
      ..write(obj.roundIndex)
      ..writeByte(15)
      ..write(obj.profileId)
      ..writeByte(16)
      ..write(obj.practiceMode)
      ..writeByte(17)
      ..write(obj.temperatureScore)
      ..writeByte(18)
      ..write(obj.hintUsedCount)
      ..writeByte(19)
      ..write(obj.familiarityScore)
      ..writeByte(20)
      ..write(obj.relationshipStageLabel)
      ..writeByte(21)
      ..write(obj.debriefDateChance)
      ..writeByte(22)
      ..write(obj.debriefDateChanceReason)
      ..writeByte(23)
      ..write(obj.debriefNextInviteMove)
      ..writeByte(24)
      ..write(obj.debriefGamePhaseReached)
      ..writeByte(25)
      ..write(obj.debriefGameMissedVariable)
      ..writeByte(26)
      ..write(obj.debriefGameFailureState)
      ..writeByte(27)
      ..write(obj.debriefGameNextFirstLine)
      ..writeByte(28)
      ..write(obj.debriefGameInviteDirection)
      ..writeByte(29)
      ..write(obj.debriefQualitySchemaVersion);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
