// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PracticeMessageAdapter extends TypeAdapter<PracticeMessage> {
  @override
  final typeId = 22;

  @override
  PracticeMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PracticeMessage(
      role: fields[0] as String,
      text: fields[1] as String,
      mood: fields[2] as String?,
      innerThought: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PracticeMessage obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.role)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.mood)
      ..writeByte(3)
      ..write(obj.innerThought);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
