// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coach_follow_up_result.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CoachFollowUpResultAdapter extends TypeAdapter<CoachFollowUpResult> {
  @override
  final typeId = 16;

  @override
  CoachFollowUpResult read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CoachFollowUpResult(
      partnerId: fields[0] as String,
      phase: fields[1] as String,
      headline: fields[2] as String,
      observation: fields[3] as String,
      task: fields[4] as String,
      suggestedLine: fields[5] as String?,
      boundaryReminder: fields[6] as String,
      generatedAt: fields[7] as DateTime,
      modelUsed: fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, CoachFollowUpResult obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.partnerId)
      ..writeByte(1)
      ..write(obj.phase)
      ..writeByte(2)
      ..write(obj.headline)
      ..writeByte(3)
      ..write(obj.observation)
      ..writeByte(4)
      ..write(obj.task)
      ..writeByte(5)
      ..write(obj.suggestedLine)
      ..writeByte(6)
      ..write(obj.boundaryReminder)
      ..writeByte(7)
      ..write(obj.generatedAt)
      ..writeByte(8)
      ..write(obj.modelUsed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachFollowUpResultAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
