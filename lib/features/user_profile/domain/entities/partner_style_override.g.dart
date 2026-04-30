// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partner_style_override.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PartnerStyleOverrideAdapter extends TypeAdapter<PartnerStyleOverride> {
  @override
  final typeId = 13;

  @override
  PartnerStyleOverride read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PartnerStyleOverride(
      partnerId: fields[0] as String,
      interactionStyle: fields[1] as InteractionStyle?,
      practiceGoals: fields[2] == null
          ? const []
          : (fields[2] as List).cast<PracticeGoal>(),
      notes: fields[3] as String?,
      updatedAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PartnerStyleOverride obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.partnerId)
      ..writeByte(1)
      ..write(obj.interactionStyle)
      ..writeByte(2)
      ..write(obj.practiceGoals)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerStyleOverrideAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
