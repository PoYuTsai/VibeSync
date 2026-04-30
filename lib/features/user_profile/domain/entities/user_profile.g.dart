// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final typeId = 9;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      interactionStyle: fields[0] as InteractionStyle?,
      practiceGoals: fields[1] == null
          ? const []
          : (fields[1] as List).cast<PracticeGoal>(),
      topicSeeds:
          fields[2] == null ? const [] : (fields[2] as List).cast<TopicSeed>(),
      customTopics: fields[3] as String?,
      notes: fields[4] as String?,
      updatedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.interactionStyle)
      ..writeByte(1)
      ..write(obj.practiceGoals)
      ..writeByte(2)
      ..write(obj.topicSeeds)
      ..writeByte(3)
      ..write(obj.customTopics)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InteractionStyleAdapter extends TypeAdapter<InteractionStyle> {
  @override
  final typeId = 10;

  @override
  InteractionStyle read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return InteractionStyle.steady;
      case 1:
        return InteractionStyle.direct;
      case 2:
        return InteractionStyle.humorous;
      case 3:
        return InteractionStyle.gentle;
      case 4:
        return InteractionStyle.playful;
      default:
        return InteractionStyle.steady;
    }
  }

  @override
  void write(BinaryWriter writer, InteractionStyle obj) {
    switch (obj) {
      case InteractionStyle.steady:
        writer.writeByte(0);
      case InteractionStyle.direct:
        writer.writeByte(1);
      case InteractionStyle.humorous:
        writer.writeByte(2);
      case InteractionStyle.gentle:
        writer.writeByte(3);
      case InteractionStyle.playful:
        writer.writeByte(4);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionStyleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PracticeGoalAdapter extends TypeAdapter<PracticeGoal> {
  @override
  final typeId = 11;

  @override
  PracticeGoal read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PracticeGoal.softInvite;
      case 1:
        return PracticeGoal.reduceAnxiety;
      case 2:
        return PracticeGoal.humorousReply;
      case 3:
        return PracticeGoal.buildCloseness;
      case 4:
        return PracticeGoal.explainLess;
      default:
        return PracticeGoal.softInvite;
    }
  }

  @override
  void write(BinaryWriter writer, PracticeGoal obj) {
    switch (obj) {
      case PracticeGoal.softInvite:
        writer.writeByte(0);
      case PracticeGoal.reduceAnxiety:
        writer.writeByte(1);
      case PracticeGoal.humorousReply:
        writer.writeByte(2);
      case PracticeGoal.buildCloseness:
        writer.writeByte(3);
      case PracticeGoal.explainLess:
        writer.writeByte(4);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeGoalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TopicSeedAdapter extends TypeAdapter<TopicSeed> {
  @override
  final typeId = 12;

  @override
  TopicSeed read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TopicSeed.fitness;
      case 1:
        return TopicSeed.travel;
      case 2:
        return TopicSeed.coffee;
      case 3:
        return TopicSeed.music;
      case 4:
        return TopicSeed.movies;
      case 5:
        return TopicSeed.photography;
      case 6:
        return TopicSeed.food;
      case 7:
        return TopicSeed.pets;
      case 8:
        return TopicSeed.reading;
      case 9:
        return TopicSeed.workLife;
      default:
        return TopicSeed.fitness;
    }
  }

  @override
  void write(BinaryWriter writer, TopicSeed obj) {
    switch (obj) {
      case TopicSeed.fitness:
        writer.writeByte(0);
      case TopicSeed.travel:
        writer.writeByte(1);
      case TopicSeed.coffee:
        writer.writeByte(2);
      case TopicSeed.music:
        writer.writeByte(3);
      case TopicSeed.movies:
        writer.writeByte(4);
      case TopicSeed.photography:
        writer.writeByte(5);
      case TopicSeed.food:
        writer.writeByte(6);
      case TopicSeed.pets:
        writer.writeByte(7);
      case TopicSeed.reading:
        writer.writeByte(8);
      case TopicSeed.workLife:
        writer.writeByte(9);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicSeedAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
