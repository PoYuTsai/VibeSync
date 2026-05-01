// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partner_data_quality_state.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NamePairAdapter extends TypeAdapter<NamePair> {
  @override
  final typeId = 15;

  @override
  NamePair read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NamePair(
      first: fields[0] as String,
      second: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, NamePair obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.first)
      ..writeByte(1)
      ..write(obj.second);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NamePairAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PartnerDataQualityStateAdapter
    extends TypeAdapter<PartnerDataQualityState> {
  @override
  final typeId = 14;

  @override
  PartnerDataQualityState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PartnerDataQualityState(
      partnerId: fields[0] as String,
      confirmedSamePersonPairs: (fields[1] as List).cast<NamePair>(),
      updatedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PartnerDataQualityState obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.partnerId)
      ..writeByte(1)
      ..write(obj.confirmedSamePersonPairs)
      ..writeByte(2)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerDataQualityStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
