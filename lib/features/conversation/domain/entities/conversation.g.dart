// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = 0;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Conversation(
      id: fields[0] as String,
      name: fields[1] as String,
      avatarPath: fields[2] as String?,
      messages: (fields[3] as List).cast<Message>(),
      createdAt: fields[4] as DateTime,
      updatedAt: fields[5] as DateTime,
      lastEnthusiasmScore: fields[6] as int?,
      sessionContext: fields[7] as SessionContext?,
      currentGameStage: fields[8] as String?,
      currentRound: fields[9] as int? ?? 0,
      summaries: (fields[10] as List?)?.cast<ConversationSummary>(),
      lastUserChoice: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.avatarPath)
      ..writeByte(3)
      ..write(obj.messages)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.updatedAt)
      ..writeByte(6)
      ..write(obj.lastEnthusiasmScore)
      ..writeByte(7)
      ..write(obj.sessionContext)
      ..writeByte(8)
      ..write(obj.currentGameStage)
      ..writeByte(9)
      ..write(obj.currentRound)
      ..writeByte(10)
      ..write(obj.summaries)
      ..writeByte(11)
      ..write(obj.lastUserChoice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
