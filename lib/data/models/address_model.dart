// lib/data/models/address_model.dart
import '../../domain/entities/address_entity.dart';

/// Modelo de dirección para serialización con Firestore.
class AddressModel extends AddressEntity {
  const AddressModel({
    required super.id,
    required super.userId,
    required super.label,
    required super.formattedAddress,
    required super.latitude,
    required super.longitude,
    super.placeId,
    super.reference,
    super.isDefault,
    super.createdAt,
    super.updatedAt,
  });

  factory AddressModel.fromMap(Map<String, dynamic> map, {required String id}) {
    return AddressModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      label: AddressLabel.fromString(map['label'] as String? ?? 'other'),
      formattedAddress: map['formattedAddress'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      placeId: map['placeId'] as String?,
      reference: map['reference'] as String?,
      isDefault: map['isDefault'] as bool? ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'label': label.name,
      'formattedAddress': formattedAddress,
      'latitude': latitude,
      'longitude': longitude,
      if (placeId != null) 'placeId': placeId,
      if (reference != null) 'reference': reference,
      'isDefault': isDefault,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory AddressModel.fromEntity(AddressEntity entity) {
    return AddressModel(
      id: entity.id,
      userId: entity.userId,
      label: entity.label,
      formattedAddress: entity.formattedAddress,
      latitude: entity.latitude,
      longitude: entity.longitude,
      placeId: entity.placeId,
      reference: entity.reference,
      isDefault: entity.isDefault,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
