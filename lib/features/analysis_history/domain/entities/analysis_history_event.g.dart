// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analysis_history_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnalysisHistoryEventAdapter extends TypeAdapter<AnalysisHistoryEvent> {
  @override
  final typeId = 24;

  @override
  AnalysisHistoryEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AnalysisHistoryEvent(
      id: fields[0] as String,
      kind: fields[1] as AnalysisHistoryKind,
      createdAt: fields[2] as DateTime,
      conversationId: fields[3] as String?,
      subjectName: fields[4] as String?,
      enthusiasmScore: (fields[5] as num?)?.toInt(),
      gameStageLabel: fields[6] as String?,
      profileId: fields[7] as String?,
      roundIndex: (fields[8] as num?)?.toInt(),
      temperatureScore: (fields[9] as num?)?.toInt(),
      familiarityScore: (fields[10] as num?)?.toInt(),
      relationshipStageLabel: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AnalysisHistoryEvent obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.conversationId)
      ..writeByte(4)
      ..write(obj.subjectName)
      ..writeByte(5)
      ..write(obj.enthusiasmScore)
      ..writeByte(6)
      ..write(obj.gameStageLabel)
      ..writeByte(7)
      ..write(obj.profileId)
      ..writeByte(8)
      ..write(obj.roundIndex)
      ..writeByte(9)
      ..write(obj.temperatureScore)
      ..writeByte(10)
      ..write(obj.familiarityScore)
      ..writeByte(11)
      ..write(obj.relationshipStageLabel);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisHistoryEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AnalysisHistoryKindAdapter extends TypeAdapter<AnalysisHistoryKind> {
  @override
  final typeId = 25;

  @override
  AnalysisHistoryKind read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AnalysisHistoryKind.analyze;
      case 1:
        return AnalysisHistoryKind.practice;
      default:
        return AnalysisHistoryKind.analyze;
    }
  }

  @override
  void write(BinaryWriter writer, AnalysisHistoryKind obj) {
    switch (obj) {
      case AnalysisHistoryKind.analyze:
        writer.writeByte(0);
      case AnalysisHistoryKind.practice:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisHistoryKindAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
