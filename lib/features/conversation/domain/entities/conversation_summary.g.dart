// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_summary.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationSummaryAdapter extends TypeAdapter<ConversationSummary> {
  @override
  final typeId = 2;

  @override
  ConversationSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ConversationSummary(
      id: fields[0] as String,
      roundsCovered: (fields[1] as num).toInt(),
      content: fields[2] as String,
      keyTopics: (fields[3] as List).cast<String>(),
      sharedInterests: (fields[4] as List).cast<String>(),
      relationshipStage: fields[5] as String,
      createdAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ConversationSummary obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roundsCovered)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.keyTopics)
      ..writeByte(4)
      ..write(obj.sharedInterests)
      ..writeByte(5)
      ..write(obj.relationshipStage)
      ..writeByte(6)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
