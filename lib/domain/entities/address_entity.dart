// lib/domain/entities/address_entity.dart
import 'package:equatable/equatable.dart';

/// Tipos de etiqueta para una dirección.
enum AddressLabel {
  home,
  work,
  other;

  String get displayName {
    return switch (this) {
      AddressLabel.home => 'Casa',
      AddressLabel.work => 'Trabajo',
      AddressLabel.other => 'Otro',
    };
  }

  static AddressLabel fromString(String value) {
    return AddressLabel.values.firstWhere(
      (l) => l.name == value,
      orElse: () => AddressLabel.other,
    );
  }
}

/// Entidad de dirección de entrega.
class AddressEntity extends Equatable {
  const AddressEntity({
    required this.id,
    required this.userId,
    required this.label,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.reference,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final AddressLabel label;
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String? placeId;
  final String? reference;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AddressEntity copyWith({
    String? id,
    String? userId,
    AddressLabel? label,
    String? formattedAddress,
    double? latitude,
    double? longitude,
    String? placeId,
    String? reference,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AddressEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeId: placeId ?? this.placeId,
      reference: reference ?? this.reference,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, userId, label, formattedAddress, latitude, longitude,
    placeId, reference, isDefault,
  ];
}
