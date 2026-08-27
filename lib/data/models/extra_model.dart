// lib/data/models/extra_model.dart
import '../../domain/entities/extra_entity.dart';

/// Modelo de extra para serialización con Firestore/JSON.
class ExtraModel extends ExtraEntity {
  const ExtraModel({
    required super.id,
    required super.name,
    required super.price,
    super.available,
  });

  factory ExtraModel.fromMap(Map<String, dynamic> map) {
    return ExtraModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      available: map['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'available': available,
    };
  }

  factory ExtraModel.fromEntity(ExtraEntity entity) {
    return ExtraModel(
      id: entity.id,
      name: entity.name,
      price: entity.price,
      available: entity.available,
    );
  }
}
